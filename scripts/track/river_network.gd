## Геометрия реки: осевая линия, ширина русла, зеркало воды.
##
## Класс ничего не знает о сцене: это чистая математика, поэтому его одинаково
## используют сборка мира, потоковый рельеф (в рабочем потоке) и тесты.
##
## Запрос «где река» идёт по сетке корзин: река длинная, а спрашивают о ней
## сотни тысяч вершин рельефа. Корзина 8 м + поиск кольцами с ранним выходом
## дают O(1) на вершину вместо перебора всех точек осевой линии.
@tool
class_name RallyRiverNetwork
extends RefCounted

const CELL := 8.0
const UV_METERS := 9.0

## Точки осевой линии: Y — уровень воды.
var samples := PackedVector3Array()
## Множитель ширины русла в каждой точке (расширение под большим мостом).
var width_scales := PackedFloat32Array()
var half_width: float = 7.0
var bank_width: float = 9.0
var bed_depth: float = 2.0
## Длина русла по осевой линии, м.
var total_length: float = 0.0
## Насколько далеко от оси реки вообще имеет смысл спрашивать рельеф.
var reach: float = 16.0
## Габарит реки в плане с полем reach.
var bounds := Rect2()

var _buckets := {}
var _cell: float = CELL


## Собрать сеть из конфига реки. Точки расширения — центры мостов в мире,
## их множители и радиусы сглаживания.
static func build(
	cfg: RallyRiverConfig,
	widen_points: PackedVector3Array = PackedVector3Array(),
	widen_scales: PackedFloat32Array = PackedFloat32Array(),
	widen_radii: PackedFloat32Array = PackedFloat32Array()
) -> RallyRiverNetwork:
	if cfg == null or not cfg.enabled or cfg.water_curve == null:
		return null
	var length: float = cfg.water_curve.get_baked_length()
	if length <= 1.0:
		return null
	var net := RallyRiverNetwork.new()
	net.half_width = maxf(0.5, cfg.half_width)
	net.bank_width = maxf(0.1, cfg.bank_width)
	net.bed_depth = maxf(0.1, cfg.bed_depth)
	var step: float = maxf(1.0, cfg.sample_step)
	var count: int = maxi(2, int(ceil(length / step)) + 1)
	net.samples.resize(count)
	net.width_scales.resize(count)
	var max_scale := 1.0
	for i in range(count):
		var distance: float = minf(length, float(i) * step)
		var point: Vector3 = cfg.water_curve.sample_baked(distance)
		net.samples[i] = point
		var scale := 1.0
		for k in range(mini(widen_scales.size(), widen_points.size())):
			var radius: float = widen_radii[k] if k < widen_radii.size() else 0.0
			if radius <= 0.0:
				continue
			var flat: float = Vector2(point.x - widen_points[k].x, point.z - widen_points[k].z).length()
			var factor: float = 1.0 - smoothstep(0.0, radius, flat)
			scale = maxf(scale, lerpf(1.0, widen_scales[k], factor))
		net.width_scales[i] = scale
		max_scale = maxf(max_scale, scale)
	for i in range(1, count):
		net.total_length += Vector2(
			net.samples[i].x - net.samples[i - 1].x,
			net.samples[i].z - net.samples[i - 1].z
		).length()
	net.reach = (net.half_width + net.bank_width) * max_scale + 4.0
	net._cell = maxf(CELL, net.reach)
	net._fill_bounds()
	net._fill_buckets()
	return net


func _fill_bounds() -> void:
	var min_x := INF
	var min_z := INF
	var max_x := -INF
	var max_z := -INF
	for point in samples:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_z = minf(min_z, point.z)
		max_z = maxf(max_z, point.z)
	bounds = Rect2(
		Vector2(min_x - reach, min_z - reach),
		Vector2(max_x - min_x + reach * 2.0, max_z - min_z + reach * 2.0)
	)


func _fill_buckets() -> void:
	_buckets.clear()
	for i in range(samples.size()):
		var key := _key(samples[i].x, samples[i].z)
		var list: Array = _buckets.get(key, [])
		list.append(i)
		_buckets[key] = list


func _key(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / _cell)), int(floor(z / _cell)))


## Дешёвая отсечка: точка вообще рядом с рекой?
func near(x: float, z: float) -> bool:
	return bounds.has_point(Vector2(x, z))


## Расстояние до оси русла, уровень воды и множитель ширины в точке.
## X — расстояние (0 на оси), Y — уровень воды, Z — множитель ширины.
func channel_at(x: float, z: float) -> Vector3:
	if samples.size() < 2 or not near(x, z):
		return Vector3(INF, 0.0, 1.0)
	var origin := _key(x, z)
	var max_ring: int = int(ceil(reach / _cell)) + 1
	var best_distance := INF
	var best_index := -1
	var best_t := 0.0
	for ring in range(0, max_ring + 1):
		for dx in range(-ring, ring + 1):
			for dz in range(-ring, ring + 1):
				# Только рамка кольца: внутренность уже проверена.
				if ring > 0 and absi(dx) != ring and absi(dz) != ring:
					continue
				var list: Array = _buckets.get(Vector2i(origin.x + dx, origin.y + dz), [])
				for raw in list:
					var index: int = int(raw)
					var hit: Vector3 = _probe(x, z, index - 1)
					if hit.x < best_distance:
						best_distance = hit.x
						best_index = int(hit.y)
						best_t = hit.z
					hit = _probe(x, z, index)
					if hit.x < best_distance:
						best_distance = hit.x
						best_index = int(hit.y)
						best_t = hit.z
		# Всё, что лежит в следующем кольце, не ближе ring * _cell.
		if best_distance <= float(ring) * _cell:
			break
	if best_index < 0:
		return Vector3(INF, 0.0, 1.0)
	return _channel_quantities(best_index, best_distance, best_t)


## Ближайшая точка отрезка [segment, segment + 1] к (x, z).
## X — расстояние, Y - 1 — индекс отрезка, Z — доля вдоль отрезка.
func _probe(x: float, z: float, segment: int) -> Vector3:
	if segment < 0 or segment + 1 >= samples.size():
		return Vector3(INF, -1.0, 0.0)
	var a: Vector3 = samples[segment]
	var b: Vector3 = samples[segment + 1]
	var abx: float = b.x - a.x
	var abz: float = b.z - a.z
	var length_sq: float = abx * abx + abz * abz
	var t := 0.0
	if length_sq > 0.0001:
		t = clampf(((x - a.x) * abx + (z - a.z) * abz) / length_sq, 0.0, 1.0)
	var px: float = a.x + abx * t
	var pz: float = a.z + abz * t
	return Vector3(Vector2(x - px, z - pz).length(), float(segment), t)


func _channel_quantities(best_index: int, distance: float, t: float) -> Vector3:
	var scale: float = lerpf(width_scales[best_index], width_scales[best_index + 1], t)
	var water: float = lerpf(samples[best_index].y, samples[best_index + 1].y, t)
	return Vector3(distance, water, scale)


## Мешает ли река поставить объект обстановки в этой точке.
func blocks(x: float, z: float, margin: float = 0.0) -> bool:
	var info := channel_at(x, z)
	if info.x == INF:
		return false
	return info.x < half_width * info.z + margin


## Высота русла в точке с учётом естественного рельефа: дно у оси, откос
## к берегу, дальше — исходная земля.
func carve(x: float, z: float, natural: float, cfg: RallyRiverConfig) -> float:
	var info := channel_at(x, z)
	if info.x == INF:
		return natural
	var scale: float = info.z
	var water_edge: float = half_width * scale
	var bank: float = maxf(0.5, bank_width * scale)
	var depth: float = bed_depth * lerpf(0.75, 1.15, clampf(scale - 1.0, 0.0, 1.0))
	var water: float = info.y
	var bed: float = water - depth
	# Профиль русла: дно у оси, на кромке воды дно поднимается РОВНО до уровня
	# воды (это береговая линия), дальше откос сливается с естественным
	# рельефом. Иначе плоское дно до самой кромки оставляло бы зеркало воды
	# висеть над землёй, а между водой и берегом зияла бы щель.
	var inner: float = smoothstep(0.0, water_edge, info.x)
	var channel: float = lerpf(bed, water, inner)
	var ramp: float = smoothstep(water_edge, water_edge + bank, info.x)
	channel = lerpf(channel, natural, ramp)
	# minf, а не просто откос: там, где естественный рельеф ниже дна, река
	# не поднимает землю валом — она просто течёт по низине.
	return minf(natural, channel)


## Сетка зеркала воды. blocked(x, z) — необязательный фильтр участков
## (например, перекрытая насыпью дорога вне моста), ground(x, z) — высота
## готового рельефа: вода никогда не висит над берегом, кромка ложится на грунт.
func build_water_mesh(
	cfg: RallyRiverConfig,
	blocked: Callable = Callable(),
	ground: Callable = Callable()
) -> ArrayMesh:
	if cfg == null or samples.size() < 2:
		return null
	var drop: float = maxf(0.0, cfg.surface_drop)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var run := 0.0
	for i in range(samples.size()):
		var point: Vector3 = samples[i]
		var previous: Vector3 = samples[maxi(0, i - 1)]
		var next: Vector3 = samples[mini(samples.size() - 1, i + 1)]
		var tangent := Vector3(next.x - previous.x, 0.0, next.z - previous.z)
		if tangent.length_squared() < 0.0001:
			tangent = Vector3(0.0, 0.0, 1.0)
		tangent = tangent.normalized()
		var side := Vector3(tangent.z, 0.0, -tangent.x)
		var width: float = half_width * width_scales[i]
		if i > 0:
			run += Vector2(point.x - previous.x, point.z - previous.z).length()
		var v: float = run / UV_METERS
		var wave: float = cfg.wave_height
		var center_y: float = point.y - drop
		var left_x: float = point.x - side.x * width
		var left_z: float = point.z - side.z * width
		var right_x: float = point.x + side.x * width
		var right_z: float = point.z + side.z * width
		var left_y: float = center_y + wave * 0.35
		var right_y: float = center_y + wave * 0.55
		if ground.is_valid():
			# Кромка садится на береговую линию из carve(): вода не висит над
			# землёй и не перерезает берег. Запас 3 см — чтобы кромка не
			# мерцала с землёй в одной плоскости.
			left_y = minf(left_y, float(ground.call(left_x, left_z)) - 0.03)
			right_y = minf(right_y, float(ground.call(right_x, right_z)) - 0.03)
		var left := Vector3(left_x, left_y, left_z)
		var right := Vector3(right_x, right_y, right_z)
		var middle := Vector3(point.x, center_y, point.z)
		vertices.append(left)
		vertices.append(middle)
		vertices.append(right)
		for _slot in range(3):
			normals.append(Vector3.UP)
		uvs.append(Vector2(0.0, v))
		uvs.append(Vector2(0.5, v))
		uvs.append(Vector2(1.0, v))
		var grain: float = RallyTrackConfig.hash_noise(point.x * 3.1, point.z * 2.7)
		colors.append(Color(1.0, grain, 0.0, 1.0))
		colors.append(Color(0.15, grain, 0.35, 1.0))
		colors.append(Color(1.0, grain, 0.0, 1.0))
		if i > 0:
			var base: int = (i - 1) * 3
			var skip: bool = false
			if blocked.is_valid():
				skip = blocked.call(point.x, point.z)
			if not skip:
				for column in range(2):
					var a: int = base + column
					var b: int = base + column + 1
					var c: int = b + 3
					var d: int = a + 3
					indices.append(a)
					indices.append(b)
					indices.append(c)
					indices.append(a)
					indices.append(c)
					indices.append(d)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
