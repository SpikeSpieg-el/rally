## Потоковый рельеф аркадного мира: бесконечная сетка тайлов 96×96 м вокруг
## машины с холмами, горными хребтами, кюветами и речными ущельями под мостами.
##
## Зачем отдельный слой поверх полосы обочины (`arcade_chunk.gd`):
## на серпантине соседние витки шпилек лежат в 25–35 м друг от друга, поэтому
## широкая «лента вдоль оси» пересекала бы сама себя и засыпала асфальт травой.
## Мировые тайлы считают расстояние до ближайших сегментов дороги через
## пространственный хэш O(1), никогда не вылезают сквозь полотно и укрывают
## горизонт до самого тумана.
class_name RallyArcadeTerrain
extends Node3D

const RoadType = preload("res://scripts/arcade/arcade_road.gd")
const LegType = preload("res://scripts/data/rally_arcade_leg.gd")

const TILE_SIZE: float = 96.0
const TILE_DIVISIONS: int = 16
const ROAD_CELL_SIZE: float = 96.0
const REP_CELL_SIZE: float = 128.0
const LOAD_RADIUS: float = 384.0
const KEEP_RADIUS: float = 504.0
const COLLISION_RADIUS: float = 192.0
const BUDGET_USEC: int = 2400

const SHOULDER: float = 1.2
const EDGE_BAND: float = 1.1
const ROAD_LIFT: float = 0.04
const DITCH_DEPTH: float = 0.5
const BRIDGE_GORGE_DEPTH: float = 6.8

var track_seed: int = 0
var terrain_seed: int = 4049
var hills_height: float = 24.0
var ridge_height: float = 20.0
var detail_height: float = 0.45
var ground_material: Material = null
## Поперечная геометрия должна совпадать с чанк-мешем, иначе тайл земли
## вернётся к старой обочине и начнёт прорезать расширенную дорогу.
var shoulder_width: float = SHOULDER
var edge_band_width: float = EDGE_BAND
var road_lift_height: float = ROAD_LIFT
var ditch_depth: float = DITCH_DEPTH

var _noise_hills: FastNoiseLite = null
var _noise_ridge: FastNoiseLite = null
var _noise_detail: FastNoiseLite = null

var _road_cells: Dictionary = {}
var _rep_cells: Dictionary = {}
var _synced_leg: int = -1
var _bridges_by_leg: Dictionary = {}
var _bridge_cells: Dictionary = {}

var _tiles: Dictionary = {}
var _pending: Array[Vector2i] = []
## Готовые заготовки тайлов: высоты/дистанции посчитаны, меш ещё нет.
## Строим тайл двумя стадиями, чтобы ни одна из них не выбивалась из
## кадрового бюджета целиком (см. _process).
var _prepared: Dictionary = {}
var _ready_queue: Array[Vector2i] = []
var _last_center_tile := Vector2i(999999, 999999)
var _focus_pos := Vector3.ZERO


func setup(
	road_seed: int,
	t_seed: int,
	p_hills_height: float,
	p_hills_freq: float,
	p_ridge_height: float,
	p_ridge_freq: float,
	p_detail_height: float,
	p_ground_material: Material,
	geometry: Dictionary = {}
) -> void:
	track_seed = road_seed
	terrain_seed = t_seed
	hills_height = p_hills_height
	ridge_height = p_ridge_height
	detail_height = p_detail_height
	ground_material = p_ground_material
	shoulder_width = float(geometry.get("road_shoulder", SHOULDER))
	edge_band_width = float(geometry.get("road_edge_band", EDGE_BAND))
	road_lift_height = float(geometry.get("road_lift", ROAD_LIFT))
	ditch_depth = float(geometry.get("road_ditch_depth", DITCH_DEPTH))

	for child in get_children():
		child.queue_free()
	_tiles.clear()
	_pending.clear()
	_prepared.clear()
	_ready_queue.clear()
	_road_cells.clear()
	_rep_cells.clear()
	_bridges_by_leg.clear()
	_bridge_cells.clear()
	_synced_leg = -1
	_last_center_tile = Vector2i(999999, 999999)

	_noise_hills = FastNoiseLite.new()
	_noise_hills.seed = terrain_seed ^ (track_seed & 0xffff)
	_noise_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_hills.frequency = maxf(0.0005, p_hills_freq)
	_noise_hills.fractal_octaves = 3

	_noise_ridge = FastNoiseLite.new()
	_noise_ridge.seed = (terrain_seed + 137) ^ (track_seed & 0xffff)
	_noise_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_ridge.frequency = maxf(0.0004, p_ridge_freq)
	_noise_ridge.fractal_octaves = 2

	_noise_detail = FastNoiseLite.new()
	_noise_detail.seed = (terrain_seed + 911) ^ (track_seed & 0xffff)
	_noise_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_detail.frequency = 0.085
	_noise_detail.fractal_octaves = 2


## Индексировать участки дороги в пространственную решётку до `end_along`.
func sync_road_to(end_along: float) -> void:
	var target_leg: int = RoadType.leg_index_at(maxf(0.0, end_along)) + 2
	while _synced_leg < target_leg:
		_synced_leg += 1
		_index_leg(_synced_leg)


func _index_leg(leg_index: int) -> void:
	var built: RoadType.Leg = RoadType.leg(leg_index, track_seed)
	if built == null or built.points.is_empty():
		return
	# Шаг индексации 4 м (каждая 2-я точка) — компактно и точно для дистанций.
	var count: int = built.points.size()
	for i in range(0, count, 2):
		var pt: Vector3 = built.points[i]
		var d: float = built.along[i]
		var hw: float = built.half_width[i] if i < built.half_width.size() else 5.0
		var cell_key := Vector2i(floori(pt.x / ROAD_CELL_SIZE), floori(pt.z / ROAD_CELL_SIZE))
		var bucket: Array
		if _road_cells.has(cell_key):
			bucket = _road_cells[cell_key] as Array
		else:
			bucket = []
			_road_cells[cell_key] = bucket
		bucket.append({"x": pt.x, "y": pt.y, "z": pt.z, "along": d, "half": hw})
		var rep_key := Vector2i(floori(pt.x / REP_CELL_SIZE), floori(pt.z / REP_CELL_SIZE))
		if not _rep_cells.has(rep_key):
			_rep_cells[rep_key] = pt

	# Регистрация мостов участка для ущелий и русел.
	var leg_bridges: Array[Dictionary] = []
	for slot in range(built.domains.size()):
		if int(built.domains[slot]) != LegType.Kind.BRIDGE:
			continue
		var d_start: float = built.domain_starts[slot]
		var d_end: float = built.end_along()
		if slot + 1 < built.domain_starts.size():
			d_end = built.domain_starts[slot + 1]
		var bridge_along: float = lerpf(d_start, d_end, 0.62)
		var center: Vector3 = built.point_at(bridge_along)
		var dir: Vector3 = built.direction_at(bridge_along)
		var side := Vector3(dir.z, 0.0, -dir.x)
		var info := {
			"leg": leg_index,
			"along": bridge_along,
			"start": d_start,
			"end": d_end,
			"center": center,
			"dir": dir,
			"side": side,
			"span_half": 11.0,
		}
		leg_bridges.append(info)
		var b_key := Vector2i(floori(center.x / REP_CELL_SIZE), floori(center.z / REP_CELL_SIZE))
		var b_bucket: Array
		if _bridge_cells.has(b_key):
			b_bucket = _bridge_cells[b_key] as Array
		else:
			b_bucket = []
			_bridge_cells[b_key] = b_bucket
		b_bucket.append(info)
	_bridges_by_leg[leg_index] = leg_bridges


## Список мостов конкретного участка (для декора и выемки обочины).
func bridges_for_leg(leg_index: int) -> Array[Dictionary]:
	if _bridges_by_leg.has(leg_index):
		return _bridges_by_leg[leg_index] as Array[Dictionary]
	return []


## Коэффициент близости к пролёту моста [0..1] по километражу.
func bridge_deck_factor(along: float) -> float:
	var leg_index: int = RoadType.leg_index_at(along)
	for offset in range(-1, 2):
		var list := bridges_for_leg(leg_index + offset)
		for b in list:
			var span_half: float = float(b["span_half"])
			var delta: float = absf(along - float(b["along"]))
			if delta <= span_half + 4.0:
				return 1.0 - smoothstep(span_half - 2.0, span_half + 4.0, delta)
	return 0.0


## Минимальное расстояние от мировой точки (px, pz) до полотна (O(1) по сетке).
func distance_to_road(px: float, pz: float) -> float:
	var sample := _nearest_road_sample(px, pz)
	return float(sample["dist"])


## Высота дикого рельефа (без прижатия под дорогой) — для посадки обочины и пропсов.
func height_at(px: float, pz: float) -> float:
	return _sample_height(px, pz, false)


## Высота для тайла рельефа: с аккуратным прижатием под дорогой/обочиной, чтобы
## меш тайла никогда не протыкал полотно и не мерцал с ним.
func tile_height_at(px: float, pz: float) -> float:
	return _sample_height(px, pz, true)


func _nearest_road_sample(px: float, pz: float) -> Dictionary:
	var cx: int = floori(px / ROAD_CELL_SIZE)
	var cz: int = floori(pz / ROAD_CELL_SIZE)
	var best_d2: float = INF
	var best_y: float = 0.0
	var best_along: float = 0.0
	var best_half: float = 3.6
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := Vector2i(cx + dx, cz + dz)
			if not _road_cells.has(key):
				continue
			var bucket: Array = _road_cells[key] as Array
			for entry in bucket:
				var ex: float = float(entry["x"])
				var ez: float = float(entry["z"])
				var d2: float = (px - ex) * (px - ex) + (pz - ez) * (pz - ez)
				if d2 < best_d2:
					best_d2 = d2
					best_y = float(entry["y"])
					best_along = float(entry["along"])
					best_half = float(entry["half"])
	var dist: float = sqrt(best_d2) if best_d2 < INF else 999.0
	return {"dist": dist, "y": best_y, "along": best_along, "half": best_half}


func _regional_height(px: float, pz: float, fallback_y: float) -> float:
	var cx: int = floori(px / REP_CELL_SIZE)
	var cz: int = floori(pz / REP_CELL_SIZE)
	var weight_sum: float = 0.0
	var y_sum: float = 0.0
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			var key := Vector2i(cx + dx, cz + dz)
			if not _rep_cells.has(key):
				continue
			var p: Vector3 = _rep_cells[key] as Vector3
			var d2: float = (px - p.x) * (px - p.x) + (pz - p.z) * (pz - p.z) + 1600.0
			var w: float = 1.0 / d2
			weight_sum += w
			y_sum += p.y * w
	if weight_sum <= 0.0:
		return fallback_y
	return y_sum / weight_sum


func _gorge_depth_at(px: float, pz: float) -> Dictionary:
	var best_carve: float = 0.0
	var target_bed_y: float = 0.0
	var cx: int = floori(px / REP_CELL_SIZE)
	var cz: int = floori(pz / REP_CELL_SIZE)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var b_key := Vector2i(cx + dx, cz + dz)
			if not _bridge_cells.has(b_key):
				continue
			var bucket: Array = _bridge_cells[b_key] as Array
			for b in bucket:
				var center: Vector3 = b["center"] as Vector3
				var ddx: float = px - center.x
				var ddz: float = pz - center.z
				if ddx * ddx + ddz * ddz > 110.0 * 110.0:
					continue
				var dir: Vector3 = b["dir"] as Vector3
				var side: Vector3 = b["side"] as Vector3
				var along_bridge: float = ddx * dir.x + ddz * dir.z
				var across_river: float = ddx * side.x + ddz * side.z
				var meander: float = sin(across_river * 0.045) * 4.5
				var river_offset: float = absf(along_bridge - meander)
				if river_offset < 22.0 and absf(across_river) < 96.0:
					var across_fade: float = 1.0 - smoothstep(55.0, 96.0, absf(across_river))
					var bank_fade: float = 1.0 - smoothstep(4.5, 22.0, river_offset)
					var carve: float = across_fade * bank_fade
					if carve > best_carve:
						best_carve = carve
						target_bed_y = center.y - BRIDGE_GORGE_DEPTH
	return {"carve": best_carve, "bed_y": target_bed_y}


func _sample_height(px: float, pz: float, apply_road_dip: bool) -> float:
	var near := _nearest_road_sample(px, pz)
	var dist: float = float(near["dist"])
	var road_y: float = float(near["y"])
	var half: float = float(near["half"])
	var reg_y: float = _regional_height(px, pz, road_y)

	var hills: float = _noise_hills.get_noise_2d(px, pz) * hills_height if _noise_hills != null else 0.0
	var ridge_raw: float = 1.0 - absf(_noise_ridge.get_noise_2d(px, pz)) if _noise_ridge != null else 0.5
	var ridge: float = (ridge_raw - 0.5) * 2.0 * ridge_height
	var detail: float = _noise_detail.get_noise_2d(px, pz) * detail_height if _noise_detail != null else 0.0

	var corridor: float = half + shoulder_width + edge_band_width
	var road_edge_y: float = road_y + road_lift_height - ditch_depth
	var far_blend: float = smoothstep(corridor + 1.5, corridor + 64.0, dist)
	var h: float = lerpf(road_edge_y, reg_y + hills + ridge, far_blend)
	h += detail * smoothstep(corridor, corridor + 8.0, dist)

	# Ущелье под мостом прорезает и придорожную насыпь, чтобы река текла под пролётом.
	var gorge := _gorge_depth_at(px, pz)
	var carve: float = float(gorge["carve"])
	if carve > 0.001:
		var bed_y: float = float(gorge["bed_y"]) + detail * 0.4
		h = lerpf(h, minf(h, bed_y), carve)

	if apply_road_dip and dist < corridor + 7.5 and carve < 0.25:
		# Опускаем тайл под полотном и внутренней полосой обочины, чтобы
		# не возникало мерцания (z-fighting) со стыком `Verge`.
		var dip: float = 0.65 * (1.0 - smoothstep(corridor + 2.5, corridor + 7.5, dist))
		h -= dip
	return h


# -------------------------------------------------------------- стриминг тайлов


func prime(center_pos: Vector3) -> void:
	_focus_pos = center_pos
	var center_tile := _tile_key(center_pos)
	_last_center_tile = center_tile
	_refresh_wanted(center_tile)
	while not _ready_queue.is_empty():
		var ready_key: Vector2i = _ready_queue.pop_front()
		if not _tiles.has(ready_key) and _prepared.has(ready_key):
			_finish_tile(ready_key)
	while not _pending.is_empty():
		var key: Vector2i = _pending.pop_front()
		if _tiles.has(key):
			continue
		if _prepared.has(key):
			_finish_tile(key)
		else:
			_build_tile(key)


func focus(center_pos: Vector3) -> void:
	_focus_pos = center_pos
	var center_tile := _tile_key(center_pos)
	if center_tile != _last_center_tile:
		_last_center_tile = center_tile
		_refresh_wanted(center_tile)


func _process(_delta: float) -> void:
	if _pending.is_empty() and _ready_queue.is_empty():
		return
	var started: int = Time.get_ticks_usec()
	while Time.get_ticks_usec() - started < BUDGET_USEC:
		if not _ready_queue.is_empty():
			# Сначала достраиваем начатое: меш из готовых высот стоит
			# дешевле, чем подготовка нового тайла.
			var ready_key: Vector2i = _ready_queue.pop_front()
			if _tiles.has(ready_key) or not _prepared.has(ready_key):
				continue
			_finish_tile(ready_key)
		elif not _pending.is_empty():
			var key: Vector2i = _pending.pop_front()
			if _tiles.has(key) or _prepared.has(key):
				continue
			_prepare_tile(key)
		else:
			return


func _tile_key(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / TILE_SIZE), floori(pos.z / TILE_SIZE))


func _refresh_wanted(center_tile: Vector2i) -> void:
	var radius_tiles: int = ceili(LOAD_RADIUS / TILE_SIZE)
	var keep_tiles: int = ceili(KEEP_RADIUS / TILE_SIZE)
	var wanted := {}
	var queue_list: Array[Dictionary] = []
	for dz in range(-radius_tiles, radius_tiles + 1):
		for dx in range(-radius_tiles, radius_tiles + 1):
			var key := Vector2i(center_tile.x + dx, center_tile.y + dz)
			var tile_center := Vector3((float(key.x) + 0.5) * TILE_SIZE, 0.0, (float(key.y) + 0.5) * TILE_SIZE)
			var d: float = Vector2(tile_center.x - _focus_pos.x, tile_center.z - _focus_pos.z).length()
			if d > LOAD_RADIUS + TILE_SIZE * 0.75:
				continue
			wanted[key] = true
			if not _tiles.has(key):
				queue_list.append({"key": key, "dist": d})

	for existing_key in _tiles.keys():
		var k: Vector2i = existing_key as Vector2i
		if maxi(absi(k.x - center_tile.x), absi(k.y - center_tile.y)) > keep_tiles:
			var tile_node := _tiles[existing_key] as Node
			_tiles.erase(existing_key)
			if is_instance_valid(tile_node):
				tile_node.queue_free()

	queue_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
	_pending.clear()
	_ready_queue.clear()
	var queued := {}
	for item in queue_list:
		var key: Vector2i = item["key"] as Vector2i
		if queued.has(key):
			continue
		queued[key] = true
		if _prepared.has(key):
			# Заготовка уже есть — тайлу остаётся только финиш.
			_ready_queue.append(key)
		else:
			_pending.append(key)
	# Забытые заготовки вне круга внимания — выбросить.
	for prep_key in _prepared.keys():
		if not wanted.has(prep_key):
			_prepared.erase(prep_key)


## Собрать тайл целиком (синхронно — для старта заезда).
func _build_tile(key: Vector2i) -> void:
	_prepare_tile(key)
	_finish_tile(key)


## Стадия 1: высоты и дистанции до дороги по «полю» из halo-вершин.
## Самая дорогая часть тайла, поэтому вынесена в отдельную ступень
## кадрового бюджета.
func _prepare_tile(key: Vector2i) -> void:
	var width: int = TILE_DIVISIONS + 1
	var halo: int = width + 2
	var cell: float = TILE_SIZE / float(TILE_DIVISIONS)
	var origin_x: float = float(key.x) * TILE_SIZE
	var origin_z: float = float(key.y) * TILE_SIZE

	var heights := PackedFloat32Array()
	var road_dists := PackedFloat32Array()
	var road_halves := PackedFloat32Array()
	heights.resize(halo * halo)
	road_dists.resize(halo * halo)
	road_halves.resize(halo * halo)

	for gz in range(halo):
		var pz: float = origin_z + float(gz - 1) * cell
		for gx in range(halo):
			var px: float = origin_x + float(gx - 1) * cell
			var idx: int = gz * halo + gx
			var near := _nearest_road_sample(px, pz)
			road_dists[idx] = float(near["dist"])
			road_halves[idx] = float(near["half"])
			heights[idx] = _sample_height(px, pz, true)

	_prepared[key] = {
		"heights": heights,
		"road_dists": road_dists,
		"road_halves": road_halves,
	}
	_ready_queue.append(key)


## Стадия 2: меш и коллайдер из готовой заготовки.
func _finish_tile(key: Vector2i) -> void:
	if not _prepared.has(key):
		return
	var data: Dictionary = _prepared[key]
	var heights: PackedFloat32Array = data["heights"]
	var road_dists: PackedFloat32Array = data["road_dists"]
	var road_halves: PackedFloat32Array = data["road_halves"]
	_prepared.erase(key)

	var width: int = TILE_DIVISIONS + 1
	var halo: int = width + 2
	var cell: float = TILE_SIZE / float(TILE_DIVISIONS)
	var origin_x: float = float(key.x) * TILE_SIZE
	var origin_z: float = float(key.y) * TILE_SIZE
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.resize(width * width)
	normals.resize(width * width)
	colors.resize(width * width)
	indices.resize(TILE_DIVISIONS * TILE_DIVISIONS * 6)

	for vz in range(width):
		for vx in range(width):
			var h: int = (vz + 1) * halo + (vx + 1)
			var vi: int = vz * width + vx
			vertices[vi] = Vector3(float(vx) * cell, heights[h], float(vz) * cell)
			var normal := Vector3(
				heights[h - 1] - heights[h + 1],
				2.0 * cell,
				heights[h - halo] - heights[h + halo]
			).normalized()
			normals[vi] = normal
			var corridor: float = road_halves[h] + shoulder_width
			var influence: float = smoothstep(corridor * 0.85, corridor + 14.0, road_dists[h])
			var rock_factor: float = clampf((1.0 - normal.y) * influence * 1.35, 0.0, 1.0)
			colors[vi] = Color(influence, rock_factor, 0.5, 1.0)

	var cursor: int = 0
	for qz in range(TILE_DIVISIONS):
		for qx in range(TILE_DIVISIONS):
			var i: int = qz * width + qx
			indices[cursor] = i
			indices[cursor + 1] = i + 1
			indices[cursor + 2] = i + width
			indices[cursor + 3] = i + 1
			indices[cursor + 4] = i + width + 1
			indices[cursor + 5] = i + width
			cursor += 6

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var tile_root := Node3D.new()
	tile_root.name = "Tile_%d_%d" % [key.x, key.y]
	tile_root.position = Vector3(origin_x, 0.0, origin_z)

	var visual := MeshInstance3D.new()
	visual.name = "Mesh"
	visual.mesh = mesh
	visual.material_override = ground_material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tile_root.add_child(visual)

	var dist_to_car: float = Vector2(
		origin_x + TILE_SIZE * 0.5 - _focus_pos.x,
		origin_z + TILE_SIZE * 0.5 - _focus_pos.z
	).length()
	if dist_to_car <= COLLISION_RADIUS + TILE_SIZE:
		var body := StaticBody3D.new()
		body.name = "TerrainBody"
		body.add_to_group("Grass")
		var shape := mesh.create_trimesh_shape()
		shape.backface_collision = true
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		tile_root.add_child(body)

	add_child(tile_root)
	_tiles[key] = tile_root