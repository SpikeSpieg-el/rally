## Меш одного чанка аркадной дороги: полотно с обочинами и кюветом,
## переходная земляная кромка к мировым тайлам рельефа, зебры переходов и
## передача в генератор обстановки.
##
## Чанк строится ТОЛЬКО по километражу и сиду, без состояния: тот же кусок
## дороги после выгрузки соберётся в точности таким же. Это требование
## стримера — иначе при возврате назад появлялись бы швы и «переезжающие»
## объекты.
##
## НОРМАЛИ НА СТЫКЕ ЧАНКОВ. Сетка строится с одним «полем» вершин за границей
## чанка с каждой стороны, нормали считаются по полной сетке, а в меш идут
## только внутренние ряды. Без этого на каждом стыке (каждые 130 м) был бы
## скачок освещения.
class_name RallyArcadeChunk
extends RefCounted

const RoadType = preload("res://scripts/arcade/arcade_road.gd")

## Обочина, м (как road_shoulder в раллийных трассах).
const SHOULDER: float = 1.2
## Внешняя кромка полотна: куда ложится земляная лента, м.
const EDGE_BAND: float = 1.1
## Шаг меша вдоль дороги, м.
const ROW_STEP: float = 2.5
## Насколько полотно приподнято над землёй (как ROAD_MESH_LIFT в этапе).
const ROAD_LIFT: float = 0.04
## Крен полотна к обочинам, м (road_camber).
const CAMBER: float = 0.07
## Глубина кювета у кромки полотна, м.
const DITCH_DEPTH: float = 0.5
## Ширина придорожной юбки до перехода в мировые тайлы рельефа, м.
## Узкая полоса (< половины зазора шпилек), поэтому на серпантине не
## перекрывает соседний виток.
const VERGE_WIDTH: float = 8.0
## Насколько земля уходит ниже полотна на краю ленты без тайлов, м.
const VERGE_DROP: float = 1.4
## Сколько домов максимум на чанк в автономном fallback-режиме.
const MAX_HOUSES: int = 24
## Пунктир осевой линии: штрих и период, м.
const DASH_ON: float = 4.5
const DASH_PERIOD: float = 9.0
## Полосы поперёк полотна: край, обочина, кромка, у разметки, центр,
## у разметки, кромка, обочина, край.
const ROAD_LANES := 9
## Полуширина дорожной разметки, м.
const LINE_HALF: float = 0.09
## Пунктир правой (встречной) полосы: штрих и период, м.
const LANE_DASH_ON: float = 3.0
const LANE_DASH_PERIOD: float = 7.0
## Насколько краска приподнята над асфальтом, м.
const PAINT_LIFT: float = 0.012
## Полосы земляной ленты: три слева (кромка → вниз → край) и три справа.
const VERGE_LANES := 6
## Доли ширины земляной ленты по полосам.
const VERGE_SPREAD := [0.0, 0.42, 1.0, 1.0, 0.42, 0.0]


## Результат сборки: готовый узел и коллайдеры (полотно и земля).
class Build:
	extends RefCounted
	var root: Node3D
	var shapes: Array[ConcavePolygonShape3D] = []
	## Тип поверхности каждого коллайдера: "road" или "grass", в том же порядке.
	var kinds: Array[String] = []


## Собрать чанк, покрывающий километраж [start_along, end_along).
static func build(
	start_along: float, end_along: float, seed_value: int, materials: Dictionary
) -> Build:
	var out := Build.new()
	out.root = Node3D.new()
	out.root.name = "ArcadeChunk"
	var terrain = materials.get("terrain", null)
	var scenery = materials.get("scenery", null)
	_road_surface(out, start_along, end_along, seed_value, materials)
	_verge_strip(out, start_along, end_along, seed_value, materials.get("ground", null), terrain)
	_crossings(out, start_along, end_along, seed_value)
	if scenery != null:
		var post_col: Color = materials.get("edge_post_color", Color(0.88, 0.14, 0.10))
		scenery.decorate_chunk(out.root, start_along, end_along, seed_value, terrain, post_col)
	else:
		_village(out, start_along, end_along, seed_value)
	return out


# ------------------------------------------------------------- геометрия


static func half_width_at(distance: float, seed_value: int) -> float:
	return RoadType.half_width_at(distance, seed_value)


static func center_at(distance: float, seed_value: int) -> Vector3:
	var leg_index: int = RoadType.leg_index_at(distance)
	var built: RoadType.Leg = RoadType.leg(leg_index, seed_value)
	if built.points.is_empty():
		return Vector3.ZERO
	return built.point_at(distance)


static func direction_at(distance: float, seed_value: int) -> Vector3:
	var leg_index: int = RoadType.leg_index_at(distance)
	var built: RoadType.Leg = RoadType.leg(leg_index, seed_value)
	if built.points.size() < 2:
		return Vector3.FORWARD
	return built.direction_at(distance)


## Поперечный вектор вправо от направления движения.
static func side_at(direction: Vector3) -> Vector3:
	return Vector3(direction.z, 0.0, -direction.x)


## Высота ПОВЕРХНОСТИ полотна на километраже с поперечным сдвигом.
static func surface_height(distance: float, lateral: float, seed_value: int) -> float:
	var center: Vector3 = center_at(distance, seed_value)
	return surface_height_from(center.y, half_width_at(distance, seed_value), lateral)


static func surface_height_from(center_y: float, half: float, lateral: float) -> float:
	var shoulder: float = half + SHOULDER
	var across: float = clampf(absf(lateral) / maxf(shoulder, 0.01), 0.0, 1.0)
	var y: float = center_y - CAMBER * across * across
	if absf(lateral) > half:
		y -= DITCH_DEPTH * smoothstep(0.0, EDGE_BAND, absf(lateral) - half)
	return y + ROAD_LIFT


## Высота земли в полосе вокруг дороги (fallback без тайлов рельефа).
static func verge_height(distance: float, lateral: float, seed_value: int) -> float:
	var center: Vector3 = center_at(distance, seed_value)
	var half: float = half_width_at(distance, seed_value)
	var inner: float = half + SHOULDER + EDGE_BAND
	var across: float = absf(lateral)
	var edge_y: float = center.y + ROAD_LIFT - DITCH_DEPTH
	if across <= inner:
		return edge_y
	var t: float = clampf((across - inner) / VERGE_WIDTH, 0.0, 1.0)
	var hills: float = sin(distance * 0.031 + across * 0.045) * 0.45 * t
	return edge_y - VERGE_DROP * smoothstep(0.0, 1.0, t) + hills


# ------------------------------------------------------------- полотно


static func _road_surface(
	chunk: Build, start_along: float, end_along: float, seed_value: int, materials: Dictionary
) -> void:
	var material: Material = materials.get("road", null)
	var terrain = materials.get("terrain", null)
	var road_col: Color = materials.get("road_color", Color(0.22, 0.22, 0.24))
	var road_col2: Color = materials.get("road_color_2", Color(0.29, 0.29, 0.31))
	var shoulder_col: Color = materials.get("shoulder_color", Color(0.31, 0.26, 0.18))
	var loose_surface: bool = bool(materials.get("loose_surface", false))

	var rows: int = maxi(2, ceili((end_along - start_along) / ROW_STEP) + 1)
	var padding: int = 1
	var total_rows: int = rows + padding * 2
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	vertices.resize(total_rows * ROAD_LANES)
	normals.resize(total_rows * ROAD_LANES)
	colors.resize(total_rows * ROAD_LANES)
	uvs.resize(total_rows * ROAD_LANES)
	for row in range(total_rows):
		var distance: float = _row_distance(row, padding, rows, start_along, end_along)
		var center: Vector3 = center_at(distance, seed_value)
		var half: float = half_width_at(distance, seed_value)
		var side: Vector3 = side_at(direction_at(distance, seed_value))
		var shoulder: float = half + SHOULDER
		var outer: float = shoulder + EDGE_BAND
		var lateral: Array[float] = _road_laterals(half, shoulder, outer)
		var dash: bool = fposmod(distance, DASH_PERIOD) < DASH_ON
		var lane_dash: bool = fposmod(distance, LANE_DASH_PERIOD) < LANE_DASH_ON
		var bridge_amt: float = terrain.bridge_deck_factor(distance) if terrain != null else 0.0
		var wear_noise: float = RoadType.roll(int(floor(distance * 0.25)), seed_value, 97)
		for lane in range(ROAD_LANES):
			var lat: float = lateral[lane]
			var point: Vector3 = center + side * lat
			var y: float = surface_height_from(center.y, half, lat)
			if bridge_amt > 0.01 and absf(lat) > half:
				# На мосту кромка не ныряет в овраг — она остаётся настилом.
				var flat_deck: float = center.y - CAMBER * 0.5 + ROAD_LIFT - (0.08 if absf(lat) > shoulder else 0.0)
				y = lerpf(y, flat_deck, bridge_amt)
			var index: int = row * ROAD_LANES + lane
			uvs[index] = Vector2(lat, distance)
			var base_col := _surface_color_ex(
				absf(lat), half, shoulder, dash, lane_dash,
				road_col.lerp(road_col2, wear_noise * 0.45), shoulder_col
			)
			if not loose_surface and absf(lat) <= half:
				base_col.a = 0.08
			else:
				base_col.a = 1.0
			colors[index] = base_col
			if _is_paint(absf(lat), half, dash, lane_dash):
				y += PAINT_LIFT
			vertices[index] = Vector3(point.x, y, point.z)
	_normals_from_grid(vertices, normals, total_rows, ROAD_LANES)
	var indices := _grid_indices(rows, ROAD_LANES, padding)
	_emit(chunk, "Road", vertices, normals, colors, uvs, indices, total_rows, padding,
		ROAD_LANES, material)


static func _verge_strip(
	chunk: Build,
	start_along: float,
	end_along: float,
	seed_value: int,
	material: Material,
	terrain
) -> void:
	var rows: int = maxi(2, ceili((end_along - start_along) / (ROW_STEP * 2.0)) + 1)
	var padding: int = 1
	var total_rows: int = rows + padding * 2
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var spreads_per_vertex := PackedFloat32Array()
	vertices.resize(total_rows * VERGE_LANES)
	normals.resize(total_rows * VERGE_LANES)
	colors.resize(total_rows * VERGE_LANES)
	uvs.resize(total_rows * VERGE_LANES)
	spreads_per_vertex.resize(total_rows * VERGE_LANES)

	for row in range(total_rows):
		var distance: float = _row_distance(row, padding, rows, start_along, end_along)
		var center: Vector3 = center_at(distance, seed_value)
		var half: float = half_width_at(distance, seed_value)
		var side: Vector3 = side_at(direction_at(distance, seed_value))
		var inner: float = half + SHOULDER + EDGE_BAND
		var edge_y: float = center.y + ROAD_LIFT - DITCH_DEPTH
		var bridge_amt: float = terrain.bridge_deck_factor(distance) if terrain != null else 0.0
		for lane in range(VERGE_LANES):
			var sign_side: float = -1.0 if lane < 3 else 1.0
			var spread: float = float(VERGE_SPREAD[lane])
			var across: float = inner + VERGE_WIDTH * spread
			var point: Vector3 = center + side * across * sign_side
			var index: int = row * VERGE_LANES + lane
			var y: float
			if terrain != null:
				var world_y: float = terrain.height_at(point.x, point.z)
				# На мосту придорожная полоса сразу опускается к берегам ущелья.
				var start_y: float = lerpf(edge_y, world_y, bridge_amt)
				var blend_t: float = smoothstep(0.0, 0.92, spread)
				y = lerpf(start_y, world_y, blend_t) - 0.12 * smoothstep(0.65, 1.0, spread)
			else:
				y = verge_height(distance, across * sign_side, seed_value)
			vertices[index] = Vector3(point.x, y, point.z)
			uvs[index] = Vector2(across * sign_side, distance)
			spreads_per_vertex[index] = spread
	_normals_from_grid(vertices, normals, total_rows, VERGE_LANES)
	for i in range(total_rows * VERGE_LANES):
		var sp: float = spreads_per_vertex[i]
		var influence: float = smoothstep(0.0, 0.72, sp)
		var rock: float = clampf((1.0 - normals[i].y) * influence * 1.35, 0.0, 1.0)
		colors[i] = Color(influence, rock, 0.5, 1.0)
	# Полосы земли идут поперёк обхода полотна, поэтому треугольники
	# разворачиваются, чтобы лицевые грани смотрели вверх.
	var indices := _grid_indices(rows, VERGE_LANES, padding, 2)
	for i in range(0, indices.size(), 3):
		var swap: int = indices[i + 1]
		indices[i + 1] = indices[i + 2]
		indices[i + 2] = swap
	_emit(chunk, "Verge", vertices, normals, colors, uvs, indices, total_rows, padding,
		VERGE_LANES, material)


static func _row_distance(
	row: int, padding: int, rows: int, start_along: float, end_along: float
) -> float:
	var step: float = (end_along - start_along) / float(maxi(rows - 1, 1))
	return start_along + float(row - padding) * step


static func _normals_from_grid(
	vertices: PackedVector3Array, normals: PackedVector3Array, rows: int, lanes: int
) -> void:
	for row in range(rows):
		for lane in range(lanes):
			var here: int = row * lanes + lane
			var before: Vector3 = vertices[maxi(0, here - lanes)]
			var after: Vector3 = vertices[mini(rows * lanes - 1, here + lanes)]
			var left: Vector3 = vertices[row * lanes + maxi(0, lane - 1)]
			var right: Vector3 = vertices[row * lanes + mini(lanes - 1, lane + 1)]
			var normal: Vector3 = (after - before).cross(right - left)
			if normal.y < 0.0:
				normal = -normal
			normals[here] = normal.normalized() if normal.length() > 0.0001 else Vector3.UP


static func _grid_indices(
	rows: int, lanes: int, padding: int, skip_lane: int = -1
) -> PackedInt32Array:
	var indices := PackedInt32Array()
	for row in range(padding, padding + rows - 1):
		for lane in range(lanes - 1):
			if lane == skip_lane:
				continue
			var i0: int = row * lanes + lane
			var i1: int = i0 + 1
			var i2: int = i0 + lanes
			var i3: int = i2 + 1
			indices.append(i0)
			indices.append(i1)
			indices.append(i2)
			indices.append(i1)
			indices.append(i3)
			indices.append(i2)
	return indices


static func _emit(
	chunk: Build,
	node_name: String,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	total_rows: int,
	padding: int,
	lanes: int,
	material: Material
) -> void:
	var used := PackedVector3Array()
	var used_normals := PackedVector3Array()
	var used_colors := PackedColorArray()
	var used_uvs := PackedVector2Array()
	var first: int = padding * lanes
	var last: int = (total_rows - padding) * lanes
	used.resize(last - first)
	used_normals.resize(last - first)
	used_colors.resize(last - first)
	used_uvs.resize(last - first)
	for i in range(first, last):
		used[i - first] = vertices[i]
		used_normals[i - first] = normals[i]
		used_colors[i - first] = colors[i]
		used_uvs[i - first] = uvs[i]
	var shifted := PackedInt32Array()
	shifted.resize(indices.size())
	var offset: int = first
	for i in range(indices.size()):
		shifted[i] = indices[i] - offset
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = used
	arrays[Mesh.ARRAY_NORMAL] = used_normals
	arrays[Mesh.ARRAY_COLOR] = used_colors
	arrays[Mesh.ARRAY_TEX_UV] = used_uvs
	arrays[Mesh.ARRAY_INDEX] = shifted
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var visual := MeshInstance3D.new()
	visual.name = node_name
	visual.mesh = mesh
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.root.add_child(visual)
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	chunk.shapes.append(shape)
	chunk.kinds.append("road" if node_name == "Road" else "grass")


static func _road_laterals(half: float, shoulder: float, outer: float) -> Array[float]:
	var center_line: float = LINE_HALF
	var lane_line: float = maxf(half * 0.5, LINE_HALF * 4.0)
	return [
		-outer, -shoulder, -half,
		-center_line, center_line,
		lane_line - LINE_HALF, lane_line + LINE_HALF,
		shoulder, outer,
	]


static func _is_paint(lateral: float, half: float, dash: bool, lane_dash: bool) -> bool:
	if lateral <= LINE_HALF + 0.001 and dash:
		return true
	var lane_line: float = maxf(half * 0.5, LINE_HALF * 4.0)
	return absf(lateral - lane_line) <= LINE_HALF + 0.001 and lane_dash


## Цвет полотна по умолчанию (используется и статическими проверками).
static func _surface_color(
	lateral: float, half: float, shoulder: float, dash: bool, lane_dash: bool
) -> Color:
	var asphalt := Color(0.30, 0.28, 0.26)
	var shoulder_color := Color(0.33, 0.28, 0.20)
	var verge := Color(0.26, 0.30, 0.18)
	if lateral > shoulder:
		return verge
	if lateral > half:
		return shoulder_color
	if _is_paint(lateral, half, dash, lane_dash):
		# Краска: почти белая, чуть тёплая — читается и в темноте, и в снег.
		return Color(0.86, 0.84, 0.78)
	var wear: float = smoothstep(half * 0.55, half, lateral)
	return asphalt.lerp(shoulder_color, wear * 0.35)


static func _surface_color_ex(
	lateral: float, half: float, shoulder: float, dash: bool, lane_dash: bool,
	asphalt: Color, shoulder_color: Color
) -> Color:
	var verge := shoulder_color * 0.9
	if lateral > shoulder:
		return verge
	if lateral > half:
		return shoulder_color
	if _is_paint(lateral, half, dash, lane_dash):
		return Color(0.86, 0.84, 0.78)
	var wear: float = smoothstep(half * 0.55, half, lateral)
	return asphalt.lerp(shoulder_color, wear * 0.35)


# ------------------------------------------------------------- переходы и fallback


static func _crossings(
	chunk: Build, start_along: float, end_along: float, seed_value: int
) -> void:
	var first_leg: int = RoadType.leg_index_at(start_along)
	var last_leg: int = RoadType.leg_index_at(end_along)
	for leg_index in range(first_leg, last_leg + 1):
		var built: RoadType.Leg = RoadType.leg(leg_index, seed_value)
		for crossing in built.crossings:
			if crossing >= start_along and crossing < end_along:
				_place_crossing(chunk.root, crossing, seed_value)


static func _village(chunk: Build, start_along: float, end_along: float, seed_value: int) -> void:
	var first_leg: int = RoadType.leg_index_at(start_along)
	var last_leg: int = RoadType.leg_index_at(end_along)
	var placed: int = 0
	for leg_index in range(first_leg, last_leg + 1):
		var built: RoadType.Leg = RoadType.leg(leg_index, seed_value)
		for house in built.houses:
			if placed >= MAX_HOUSES:
				return
			var along: float = _house_along(house, built)
			if along < start_along or along >= end_along:
				continue
			_place_house(chunk.root, house, along, seed_value, placed)
			placed += 1


static func _house_along(house: Vector4, built: RoadType.Leg) -> float:
	var best: float = INF
	var best_along: float = 0.0
	for i in range(0, built.points.size(), 4):
		var p: Vector3 = built.points[i]
		var d: float = Vector2(p.x - house.x, p.z - house.z).length_squared()
		if d < best:
			best = d
			best_along = built.along[i]
	return best_along


static func _place_house(
	parent: Node3D, house: Vector4, along: float, seed_value: int, index: int
) -> void:
	var house_seed: int = int(absf(house.x) * 17.0) & 0xffff
	var scale_val: float = RoadType.roll_range(index, house_seed, 351, 0.9, 1.25)
	var box_size := Vector3(7.0, 3.2, 5.4) * scale_val
	var ground: float = verge_height(along, _house_lateral(house, along, seed_value), seed_value)
	var walls := MeshInstance3D.new()
	var body := BoxMesh.new()
	body.size = box_size
	walls.mesh = body
	walls.material_override = _flat_material(Color(0.74, 0.70, 0.60))
	walls.position = Vector3(house.x, ground + box_size.y * 0.5, house.z)
	walls.rotation.y = float(house.w)
	parent.add_child(walls)
	var roof := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(box_size.z * 1.08, box_size.y * 0.52, box_size.x * 1.05)
	roof.mesh = prism
	roof.material_override = _flat_material(Color(0.40, 0.19, 0.15))
	roof.position = Vector3(house.x, ground + box_size.y + prism.size.y * 0.5, house.z)
	roof.rotation.y = float(house.w)
	parent.add_child(roof)


static func _house_lateral(house: Vector4, along: float, seed_value: int) -> float:
	var center: Vector3 = center_at(along, seed_value)
	var side: Vector3 = side_at(direction_at(along, seed_value))
	return side.dot(Vector3(float(house.x) - center.x, 0.0, float(house.z) - center.z))


static func _place_crossing(parent: Node3D, along: float, seed_value: int) -> void:
	# Классическая «зебра» из отдельных белых полос по профилю полотна.
	var half: float = half_width_at(along, seed_value)
	var center: Vector3 = center_at(along, seed_value)
	var direction: Vector3 = direction_at(along, seed_value)
	var side: Vector3 = side_at(direction)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	var stripe_count: int = 5
	var stripe_half_len: float = 1.05
	var usable_half: float = half - 0.45
	for s in range(stripe_count):
		var lat_center: float = lerpf(-usable_half + 0.35, usable_half - 0.35, float(s) / float(stripe_count - 1))
		var lat_a: float = lat_center - 0.28
		var lat_b: float = lat_center + 0.28
		var base_idx: int = vertices.size()
		for d_sign in [-1.0, 1.0]:
			var p_along: Vector3 = center + direction * (stripe_half_len * float(d_sign))
			for lat in [lat_a, lat_b]:
				var pt: Vector3 = p_along + side * lat
				var y: float = surface_height_from(center.y, half, lat) + 0.025
				vertices.append(Vector3(pt.x, y, pt.z))
				normals.append(Vector3.UP)
		indices.append(base_idx)
		indices.append(base_idx + 1)
		indices.append(base_idx + 2)
		indices.append(base_idx + 1)
		indices.append(base_idx + 3)
		indices.append(base_idx + 2)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var slab := MeshInstance3D.new()
	slab.name = "Crossing"
	slab.mesh = mesh
	slab.material_override = _flat_material(Color(0.88, 0.86, 0.80))
	slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(slab)


static func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.92
	return mat
