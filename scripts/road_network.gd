## Дорожная сеть спецучастка: построена из одной кривой (Curve3D).
##
## Один раз считаются:
##   * плотная выборка осевой линии (позиция, накопленное расстояние, касательная);
##   * поле «расстояние до оси дороги» и «километраж по трассе» для сетки рельефа.
##
## Поле считается в три шага:
##   1) засев точными расстояниями в ячейках рядом с осевой линией;
##   2) chamfer-проход, чтобы каждая ячейка знала ближайший участок дороги;
##   3) уточнение по настоящим отрезкам (+-N точек) — расстояние и километраж
##      получаются гладкими, без «ступенек» дискретной сетки. Именно из-за
##      ступенек в старом генераторе дорога и рельеф разъезжались.
class_name RoadNetwork
extends RefCounted

## Значение «дороги рядом нет».
const FAR: float = 100000.0
## Порог «углы ячейки указывают на разные витки трассы» (м километража).
## См. along_road(): усреднять такие километражи нельзя — получаются впадины.
const ALONG_JUMP: float = 30.0

## Точки осевой линии (x, y, z) примерно через 1 м.
var samples := PackedVector3Array()
## Накопленное расстояние по трассе до каждой точки (м).
var sample_dists := PackedFloat32Array()
## Горизонтальные единичные касательные.
var sample_dirs := PackedVector3Array()
## Полная длина осевой линии (м).
var total_length: float = 0.0
## Габарит осевой линии в плане (x, z).
var bounds: Rect2 = Rect2()

# Поле расстояний (прямоугольник покрывает весь рельеф).
var cell: float = 2.0
var origin: Vector2 = Vector2.ZERO
var cols: int = 0
var rows: int = 0
var field_dist := PackedFloat32Array()
var field_along := PackedFloat32Array()
var field_site := PackedInt32Array()

# «Региональный» рельеф: сильно размытая высота дороги на грубой сетке.
# Нужен как база для земли — гладкая по всей карте, без стенок между
# ветками шпильки.
var regional := PackedFloat32Array()
var regional_cell: float = 12.0
var regional_cols: int = 0
var regional_rows: int = 0
var regional_origin := Vector2.ZERO


## Построить дорожную сеть.
## curve     — осевая линия (x/z — план, y — высота);
## area      — прямоугольник рельефа в плане (x, z);
## cell_size — шаг сетки поля.
static func build(curve: Curve3D, area: Rect2, cell_size: float) -> RoadNetwork:
	var net := RoadNetwork.new()
	net._sample_curve(curve)
	net._build_field(area, cell_size)
	return net


func _sample_curve(curve: Curve3D) -> void:
	samples.clear()
	sample_dists.clear()
	sample_dirs.clear()
	var length: float = curve.get_baked_length()
	total_length = maxf(length, 0.01)
	if length <= 0.01:
		samples.append(Vector3.ZERO)
		sample_dists.append(0.0)
		sample_dirs.append(Vector3.FORWARD)
		bounds = Rect2(Vector2.ZERO, Vector2.ZERO)
		return
	var count: int = maxi(2, ceili(length) + 1)
	for i in range(count):
		var d: float = minf(length, float(i) * length / float(count - 1))
		samples.append(curve.sample_baked(d))
		sample_dists.append(d)
	var min_x: float = INF
	var min_z: float = INF
	var max_x: float = -INF
	var max_z: float = -INF
	for i in range(samples.size()):
		var p: Vector3 = samples[i]
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
		var ahead: Vector3 = samples[mini(i + 1, samples.size() - 1)]
		var behind: Vector3 = samples[maxi(i - 1, 0)]
		var dir: Vector3 = ahead - behind
		dir.y = 0.0
		if dir.length() < 0.0001:
			dir = Vector3.FORWARD
		sample_dirs.append(dir.normalized())
	bounds = Rect2(Vector2(min_x, min_z), Vector2(max_x - min_x, max_z - min_z))


func _build_field(area: Rect2, cell_size: float) -> void:
	cell = maxf(0.5, cell_size)
	origin = area.position
	cols = maxi(2, ceili(area.size.x / cell) + 1)
	rows = maxi(2, ceili(area.size.y / cell) + 1)
	var count: int = cols * rows
	field_dist.resize(count)
	field_along.resize(count)
	field_dist.fill(FAR)
	field_along.fill(0.0)
	field_site.resize(count)
	field_site.fill(-1)

	var seg_count: int = samples.size() - 1
	if seg_count < 1:
		return

	# 1) Засев: ячейки вокруг каждого отрезка осевой линии.
	for i in range(seg_count):
		var a: Vector3 = samples[i]
		var b: Vector3 = samples[i + 1]
		var ax: float = (a.x - origin.x) / cell
		var az: float = (a.z - origin.y) / cell
		var bx: float = (b.x - origin.x) / cell
		var bz: float = (b.z - origin.y) / cell
		var lo_x: int = maxi(0, int(floor(minf(ax, bx))) - 1)
		var hi_x: int = mini(cols - 1, int(ceilf(maxf(ax, bx))) + 1)
		var lo_z: int = maxi(0, int(floor(minf(az, bz))) - 1)
		var hi_z: int = mini(rows - 1, int(ceilf(maxf(az, bz))) + 1)
		var a2 := Vector2(a.x, a.z)
		var b2 := Vector2(b.x, b.z)
		for gz in range(lo_z, hi_z + 1):
			var row_offset: int = gz * cols
			for gx in range(lo_x, hi_x + 1):
				var p := Vector2(origin.x + float(gx) * cell, origin.y + float(gz) * cell)
				var result: Vector3 = _nearest_on_segment(p, a2, b2, sample_dists[i], sample_dists[i + 1])
				var index: int = row_offset + gx
				if result.x < field_dist[index]:
					field_dist[index] = result.x
					field_along[index] = result.y
					field_site[index] = i

	# 2) Chamfer: распространяем ближайший участок на всю сетку.
	_chamfer_pass(false)
	_chamfer_pass(true)

	# 3) Уточнение по настоящим отрезкам вокруг найденного участка.
	#    Дальним ячейкам точность не нужна (там рельеф уже полностью свой),
	#    поэтому их пропускаем — сборка карты заметно быстрее.
	var window: int = 5
	var refine_limit: float = 90.0
	for gz in range(rows):
		var row_offset: int = gz * cols
		var z: float = origin.y + float(gz) * cell
		for gx in range(cols):
			var index: int = row_offset + gx
			var site: int = field_site[index]
			if site < 0 or field_dist[index] > refine_limit:
				continue
			var p := Vector2(origin.x + float(gx) * cell, z)
			# ВАЖНО: along берём всегда из найденного отрезка, а не «если
			# стало ближе». У ячеек, до которых доехал chamfer, field_along
			# остаётся нулём-заглушкой; при точном совпадении расстояния
			# условие «строго меньше» не срабатывало, и высота земли
			# считалась по высоте старта трассы (y = 0) — получались
			# вертикальные шипы в 25–70 м у кромки дороги.
			var found_dist: float = INF
			var best_along: float = field_along[index]
			for k in range(maxi(0, site - window), mini(seg_count, site + window + 1)):
				var a: Vector3 = samples[k]
				var b: Vector3 = samples[k + 1]
				var result: Vector3 = _nearest_on_segment(
					p, Vector2(a.x, a.z), Vector2(b.x, b.z), sample_dists[k], sample_dists[k + 1]
				)
				if result.x < found_dist:
					found_dist = result.x
					best_along = result.y
			field_dist[index] = minf(field_dist[index], found_dist)
			field_along[index] = best_along

	_build_regional(area)


## Гладкая база рельефа: высота дороги, размытая на десятки метров.
func _build_regional(area: Rect2) -> void:
	regional_cell = maxf(cell * 5.0, 10.0)
	regional_origin = area.position - Vector2(regional_cell, regional_cell)
	regional_cols = maxi(3, ceili(area.size.x / regional_cell) + 3)
	regional_rows = maxi(3, ceili(area.size.y / regional_cell) + 3)
	var count: int = regional_cols * regional_rows
	regional.resize(count)
	for gz in range(regional_rows):
		var z: float = regional_origin.y + float(gz) * regional_cell
		for gx in range(regional_cols):
			var x: float = regional_origin.x + float(gx) * regional_cell
			# Высота дороги в этой точке (до оси дороги далеко — всё равно
			# берём ближайшую точку трассы: это «региональный уровень»).
			regional[gz * regional_cols + gx] = height_at_along(along_road(x, z))
	# Размытие: 40 проходов раздельного box-фильтра — как широкая гауссиана.
	for pass_index in range(40):
		regional = _blur_separable(regional, regional_cols, regional_rows)


## Один проход раздельного box-фильтра. Возвращает новый массив: Packed-массивы
## в GDScript передаются по значению, менять их «на месте» из функции нельзя.
func _blur_separable(values: PackedFloat32Array, width: int, height: int) -> PackedFloat32Array:
	var result := values.duplicate()
	var temp := values.duplicate()
	# по строкам
	for y in range(height):
		var row: int = y * width
		for x in range(width):
			var left: float = temp[row + maxi(0, x - 1)]
			var center: float = temp[row + x]
			var right: float = temp[row + mini(width - 1, x + 1)]
			result[row + x] = left * 0.25 + center * 0.5 + right * 0.25
	temp = result.duplicate()
	# по столбцам
	for y in range(height):
		var up: int = maxi(0, y - 1) * width
		var mid: int = y * width
		var down: int = mini(height - 1, y + 1) * width
		for x in range(width):
			result[mid + x] = temp[up + x] * 0.25 + temp[mid + x] * 0.5 + temp[down + x] * 0.25
	return result


## Возвращает (расстояние до отрезка, километраж в точке проекции, 0).
func _nearest_on_segment(p: Vector2, a: Vector2, b: Vector2, dist_a: float, dist_b: float) -> Vector3:
	var ab: Vector2 = b - a
	var len2: float = ab.length_squared()
	if len2 < 0.000001:
		return Vector3(p.distance_to(a), dist_a, 0.0)
	var t: float = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	var closest: Vector2 = a + ab * t
	return Vector3(p.distance_to(closest), lerpf(dist_a, dist_b, t), 0.0)


func _chamfer_pass(reverse: bool) -> void:
	var offsets := [
		Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1),
	]
	if reverse:
		offsets = [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
		]
	var z_start: int = rows - 1 if reverse else 0
	var z_step: int = -1 if reverse else 1
	for step_z in range(rows):
		var gz: int = z_start + step_z * z_step
		var x_start: int = cols - 1 if reverse else 0
		for step_x in range(cols):
			var gx: int = x_start + step_x * (-1 if reverse else 1)
			var index: int = gz * cols + gx
			var best: float = field_dist[index]
			var best_site: int = field_site[index]
			# Километраж тянем вместе с участком. Иначе у всех ячеек, до
			# которых дошёл chamfer, along остаётся нулём-заглушкой.
			var best_along: float = field_along[index]
			for off in offsets:
				var nx: int = gx + off.x
				var nz: int = gz + off.y
				if nx < 0 or nz < 0 or nx >= cols or nz >= rows:
					continue
				var n_index: int = nz * cols + nx
				if field_site[n_index] < 0:
					continue
				var distance: float = cell if (off.x == 0 or off.y == 0) else cell * 1.4142135
				var candidate: float = field_dist[n_index] + distance
				if candidate < best:
					best = candidate
					best_site = field_site[n_index]
					best_along = field_along[n_index]
			field_dist[index] = best
			field_site[index] = best_site
			field_along[index] = best_along


# ---------------------------------------------------------------- запросы


func _bilinear(field: PackedFloat32Array, x: float, z: float) -> float:
	if cols < 2 or rows < 2:
		return FAR
	var fx: float = (x - origin.x) / cell
	var fz: float = (z - origin.y) / cell
	var gx: int = clampi(int(floor(fx)), 0, cols - 2)
	var gz: int = clampi(int(floor(fz)), 0, rows - 2)
	var tx: float = clampf(fx - float(gx), 0.0, 1.0)
	var tz: float = clampf(fz - float(gz), 0.0, 1.0)
	var i00: int = gz * cols + gx
	var top: float = lerpf(field[i00], field[i00 + 1], tx)
	var bottom: float = lerpf(field[i00 + cols], field[i00 + cols + 1], tx)
	return lerpf(top, bottom, tz)


## Расстояние от точки до оси дороги (м).
func distance_to_road(x: float, z: float) -> float:
	return _bilinear(field_dist, x, z)


## Километраж по трассе (м) для этой точки плана.
##
## Тонкость: если четыре угла сеточной ячейки «голосуют» за сильно разные
## километражи (рядом второй виток шпильки или лестница серпантина),
## билинейное усреднение изобретает километраж ПОСЕРЕДИНЕ — и высота дороги
## в этой точке уходит в несуществующую впадину. Поэтому при расхождении
## углов больше ALONG_JUMP берём километраж угла, ближайшего к дороге:
## оба варианта — настоящие высоты трассы, выдуманных не остаётся.
func along_road(x: float, z: float) -> float:
	if cols < 2 or rows < 2:
		return 0.0
	var fx: float = (x - origin.x) / cell
	var fz: float = (z - origin.y) / cell
	var gx: int = clampi(int(floor(fx)), 0, cols - 2)
	var gz: int = clampi(int(floor(fz)), 0, rows - 2)
	var tx: float = clampf(fx - float(gx), 0.0, 1.0)
	var tz: float = clampf(fz - float(gz), 0.0, 1.0)
	var i00: int = gz * cols + gx
	var i10: int = i00 + 1
	var i01: int = i00 + cols
	var i11: int = i01 + 1
	var a_min: float = minf(minf(field_along[i00], field_along[i10]), minf(field_along[i01], field_along[i11]))
	var a_max: float = maxf(maxf(field_along[i00], field_along[i10]), maxf(field_along[i01], field_along[i11]))
	if a_max - a_min > ALONG_JUMP:
		# Углы disagree: ближе к дороге — правдивее.
		var best: int = i00
		var best_dist: float = field_dist[i00]
		if field_dist[i10] < best_dist:
			best = i10
			best_dist = field_dist[i10]
		if field_dist[i01] < best_dist:
			best = i01
			best_dist = field_dist[i01]
		if field_dist[i11] < best_dist:
			best = i11
		return field_along[best]
	var top: float = lerpf(field_along[i00], field_along[i10], tx)
	var bottom: float = lerpf(field_along[i01], field_along[i11], tx)
	return lerpf(top, bottom, tz)


## Гладкая базовая высота рельефа в точке плана.
func regional_height(x: float, z: float) -> float:
	if regional.is_empty() or regional_cols < 2 or regional_rows < 2:
		return height_at_along(along_road(x, z))
	var fx: float = (x - regional_origin.x) / regional_cell
	var fz: float = (z - regional_origin.y) / regional_cell
	var gx: int = clampi(int(floor(fx)), 0, regional_cols - 2)
	var gz: int = clampi(int(floor(fz)), 0, regional_rows - 2)
	var tx: float = clampf(fx - float(gx), 0.0, 1.0)
	var tz: float = clampf(fz - float(gz), 0.0, 1.0)
	var i00: int = gz * regional_cols + gx
	var top: float = lerpf(regional[i00], regional[i00 + 1], tx)
	var bottom: float = lerpf(regional[i00 + regional_cols], regional[i00 + regional_cols + 1], tx)
	return lerpf(top, bottom, tz)


## Высота осевой линии на расстоянии d метров по трассе.
func height_at_along(d: float) -> float:
	if samples.is_empty():
		return 0.0
	var f: float = clampf(d, 0.0, total_length) * float(samples.size() - 1) / maxf(total_length, 0.0001)
	var i: int = clampi(int(floor(f)), 0, samples.size() - 2)
	return lerpf(samples[i].y, samples[i + 1].y, clampf(f - float(i), 0.0, 1.0))


## Точка осевой линии на расстоянии d метров от старта.
func point_at(d: float) -> Vector3:
	if samples.is_empty():
		return Vector3.ZERO
	var f: float = clampf(d, 0.0, total_length) * float(samples.size() - 1) / maxf(total_length, 0.0001)
	var i: int = clampi(int(floor(f)), 0, samples.size() - 2)
	var frac: float = clampf(f - float(i), 0.0, 1.0)
	return samples[i].lerp(samples[i + 1], frac)


## Горизонтальная касательная на расстоянии d (единичная).
func direction_at(d: float) -> Vector3:
	if sample_dirs.is_empty():
		return Vector3.FORWARD
	var f: float = clampf(d, 0.0, total_length) * float(sample_dirs.size() - 1) / maxf(total_length, 0.0001)
	var i: int = clampi(int(floor(f)), 0, sample_dirs.size() - 2)
	var dir: Vector3 = sample_dirs[i].lerp(sample_dirs[i + 1], 0.5)
	if dir.length_squared() < 0.0001:
		dir = sample_dirs[i]
	if dir.length_squared() < 0.0001:
		return Vector3.FORWARD
	return dir.normalized()
