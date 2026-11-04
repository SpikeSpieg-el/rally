## Bounded active world: full route metadata, but only local meshes/colliders.
## All jobs run on the main thread in small pieces (also works in Web exports).
extends Node3D

const ROAD_LENGTH := 128.0
const TILE_SIZE := 96.0
const TILE_DIVISIONS := 16
const LOAD_RADIUS := 384.0
const KEEP_RADIUS := 576.0

var stage
var roads: Dictionary = {}
var tiles: Dictionary = {}
var _road_index: Dictionary = {}
var _road_centres: Dictionary = {}
var _wanted_roads: Dictionary = {}
var _wanted_tiles: Dictionary = {}
var _pending: Array[Dictionary] = []
var _ground_material: Material
var _busy: bool = false
var _priming: bool = true
var _last_position := Vector3(INF, INF, INF)
var _refresh_clock: float = 0.0
var _holding_car: bool = false
var _saved_velocity := Vector3.ZERO
var _saved_angular_velocity := Vector3.ZERO

func initialize(owner_stage: Node3D, start: Vector3) -> void:
	stage = owner_stage
	var started: int = Time.get_ticks_msec()
	set_process(false)
	_ground_material = stage._make_ground_material()
	# A cheap spatial index of road chunks, including neighbouring switchbacks.
	var count: int = ceili(stage.network.total_length / ROAD_LENGTH)
	for id in range(count):
		_road_centres[id] = stage.network.point_at((float(id) + 0.5) * ROAD_LENGTH)
		var distance: float = float(id) * ROAD_LENGTH
		while distance <= minf(stage.network.total_length, float(id + 1) * ROAD_LENGTH):
			var point: Vector3 = stage.network.point_at(distance)
			var key := _tile_key(point)
			if not _road_index.has(key):
				_road_index[key] = {}
			_road_index[key][id] = true
			distance += 16.0
	_request(start, LOAD_RADIUS)
	var total: int = _pending.size()
	while not _pending.is_empty():
		await _run_job()
		stage._report_progress(lerpf(0.15, 0.8, 1.0 - float(_pending.size()) / float(maxi(1, total))), "Ближайшие повороты и рельеф…")
		await get_tree().process_frame
	print("Streamed start: %d ms; %d road chunks; %d terrain tiles; no global distance field" % [Time.get_ticks_msec() - started, roads.size(), tiles.size()])
	# Expand in the background once the start area is safe.
	_last_position = Vector3(INF, INF, INF)
	_priming = false
	set_process(true)

func _tile_key(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / TILE_SIZE), floori(point.z / TILE_SIZE))

func _tile_centre(key: Vector2i) -> Vector3:
	return Vector3((float(key.x) + 0.5) * TILE_SIZE, 0.0, (float(key.y) + 0.5) * TILE_SIZE)

func _plan_distance_squared(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_squared_to(Vector2(b.x, b.z))

func _request(position: Vector3, radius: float = LOAD_RADIUS) -> void:
	_last_position = position
	_wanted_roads.clear()
	_wanted_tiles.clear()
	_pending.clear()
	var centre: Vector2i = _tile_key(position)
	var reach: int = ceili(radius / TILE_SIZE) + 1
	for z in range(-reach, reach + 1):
		for x in range(-reach, reach + 1):
			var key: Vector2i = centre + Vector2i(x, z)
			var priority: float = _plan_distance_squared(position, _tile_centre(key))
			if priority > pow(radius + TILE_SIZE * 0.71, 2.0):
				continue
			_wanted_tiles[key] = true
			if not tiles.has(key):
				_pending.append({"kind": "terrain", "key": key, "priority": priority})
			for id in _road_index.get(key, {}):
				_wanted_roads[id] = true
	for id in _wanted_roads:
		var priority: float = _plan_distance_squared(position, _road_centres[id])
		if not roads.has(id):
			# Road and collision first, decoration only once the ground is safe.
			_pending.append({"kind": "road", "key": id, "priority": priority - 1000000.0})
		elif not roads[id].has_meta("decorated"):
			_pending.append({"kind": "decor", "key": id, "priority": priority + 1000000.0})
	_pending.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.priority) < float(b.priority))
	for key in tiles.keys():
		if _plan_distance_squared(position, _tile_centre(key)) > KEEP_RADIUS * KEEP_RADIUS:
			tiles[key].queue_free()
			tiles.erase(key)
	for id in roads.keys():
		if not _wanted_roads.has(id) and _plan_distance_squared(position, _road_centres[id]) > KEEP_RADIUS * KEEP_RADIUS:
			roads[id].queue_free()
			roads.erase(id)

func _process(delta: float) -> void:
	if stage == null or not stage._stage_live or stage.car == null or stage.is_paused:
		return
	var position: Vector3 = stage.to_local(stage.car.global_position)
	_refresh_clock += delta
	# Do not replace the queue midway through an asynchronous build.
	if not _busy and (_plan_distance_squared(position, _last_position) > 32.0 * 32.0 or _refresh_clock > 1.0):
		_refresh_clock = 0.0
		_request(position)
	var along: float = stage.network.along_road(position.x, position.z)
	var road_id: int = floori(along / ROAD_LENGTH)
	road_id = mini(road_id, ceili(stage.network.total_length / ROAD_LENGTH) - 1)
	var safe: bool = roads.has(road_id) and tiles.has(_tile_key(position))
	# Teleports/resets must never drop the car through a chunk still loading.
	if not safe and not _holding_car:
		_saved_velocity = stage.car.linear_velocity
		_saved_angular_velocity = stage.car.angular_velocity
		stage.car.freeze = true
		_holding_car = true
	elif safe and _holding_car:
		stage.car.freeze = false
		stage.car.linear_velocity = _saved_velocity
		stage.car.angular_velocity = _saved_angular_velocity
		_holding_car = false
	if not _busy and not _pending.is_empty():
		_run_job()

func _run_job() -> void:
	if _pending.is_empty():
		return
	_busy = true
	var job: Dictionary = _pending.pop_front()
	if job.kind == "road" and not roads.has(job.key):
		var id: int = int(job.key)
		var root := Node3D.new()
		root.name = "Road_%04d" % id
		add_child(root)
		await stage._build_road(true, 0.0, 0.0, float(id) * ROAD_LENGTH, float(id + 1) * ROAD_LENGTH, root)
		roads[id] = root
		if not _priming:
			_pending.append({"kind": "decor", "key": id, "priority": 2000000.0})
	elif job.kind == "terrain" and not tiles.has(job.key):
		await _build_tile(job.key)
	elif job.kind == "decor" and roads.has(job.key) and not roads[job.key].has_meta("decorated"):
		var id: int = int(job.key)
		var root: Node3D = roads[id]
		if stage.track.spawn_edge_posts and stage.s_spawn().edge_posts:
			stage._spawn_edge_posts(float(id) * ROAD_LENGTH, float(id + 1) * ROAD_LENGTH, root)
		if stage.track.procedural_scenery:
			await stage._spawn_procedural_scenery(true, float(id) * ROAD_LENGTH, float(id + 1) * ROAD_LENGTH, root)
		root.set_meta("decorated", true)
	_busy = false

func _build_tile(key: Vector2i) -> void:
	var cell: float = TILE_SIZE / float(TILE_DIVISIONS)
	var origin := Vector3(float(key.x) * TILE_SIZE, 0.0, float(key.y) * TILE_SIZE)
	var width: int = TILE_DIVISIONS + 1
	var halo: int = width + 2
	var heights := PackedFloat32Array()
	heights.resize(halo * halo)
	# Halo samples make normals at tile boundaries identical in either tile.
	for z in range(halo):
		for x in range(halo):
			var px: float = origin.x + float(x - 1) * cell
			var pz: float = origin.z + float(z - 1) * cell
			var distance: float = stage.network.distance_to_road(px, pz)
			heights[z * halo + x] = stage.height_at(px, pz) - stage._road_ditch(distance)
		if z % 9 == 8:
			await get_tree().process_frame
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for z in range(width):
		for x in range(width):
			var h: int = (z + 1) * halo + x + 1
			var point := Vector3(float(x) * cell, heights[h], float(z) * cell)
			var normal := Vector3(heights[h - 1] - heights[h + 1], 2.0 * cell, heights[h - halo] - heights[h + halo]).normalized()
			vertices.append(point)
			normals.append(normal)
			var px: float = origin.x + point.x
			var pz: float = origin.z + point.z
			var distance: float = stage.network.distance_to_road(px, pz)
			var corridor: float = stage.track.half_width_at(stage.network.along_road(px, pz)) + stage.track.road_shoulder
			var influence: float = smoothstep(corridor * 0.85, corridor + 14.0, distance)
			colors.append(Color(influence, (1.0 - normal.y) * influence, 0.5, 1.0))
	for z in range(TILE_DIVISIONS):
		for x in range(TILE_DIVISIONS):
			var i: int = z * width + x
			indices.append_array(PackedInt32Array([i, i + 1, i + width, i + 1, i + width + 1, i + width]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var body := StaticBody3D.new()
	body.name = "Terrain_%d_%d" % [key.x, key.y]
	body.position = origin
	body.add_to_group("Grass")
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _ground_material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(visual)
	var collider := CollisionShape3D.new()
	collider.shape = mesh.create_trimesh_shape()
	(collider.shape as ConcavePolygonShape3D).backface_collision = true
	body.add_child(collider)
	add_child(body)
	tiles[key] = body

func statistics() -> Dictionary:
	return {"road_chunks": roads.size(), "terrain_tiles": tiles.size(),
		"pending_jobs": _pending.size(), "terrain_triangles": tiles.size() * TILE_DIVISIONS * TILE_DIVISIONS * 2,
		"global_field_cells": stage.network.field_dist.size()}
