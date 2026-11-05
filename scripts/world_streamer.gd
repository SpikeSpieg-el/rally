## Bounded active world: full route metadata, but only local meshes/colliders.
## CPU terrain data uses one isolated worker on native builds. Web builds use
## the same resumable generator on the main thread; scene/physics/GPU work
## always remains on the main thread.
extends Node3D

# The frame clock is owned by the SceneTree root, not the streamed stage. If
# a completion callback frees the stage while a tick is being emitted, the
# emitter remains alive until queue_free() runs at the end of the frame.
class StreamClock extends Node:
	signal tick

	func _process(_delta: float) -> void:
		tick.emit()

	func cancel() -> void:
		for connection in get_signal_connection_list("tick"):
			disconnect("tick", connection.callable)

var _clock: StreamClock = null

const ROAD_LENGTH := 128.0
const TILE_SIZE := 96.0
const TILE_DIVISIONS := 16
const LOAD_RADIUS := 384.0
const KEEP_RADIUS := 576.0
# У процедурной трассы заранее загружаем узкий коридор вдоль маршрута,
# а не огромный круг вокруг машины. При скорости 200 км/ч — до ~950 м.
const LIVE_LOOKAHEAD_MIN := 640.0
const LIVE_LOOKAHEAD_MAX := 960.0
const LIVE_LOOKAHEAD_SECONDS := 6.0
const DECOR_PRIORITY_OFFSET := 22000.0
const TERRAIN_SLICE_USEC := 1800
const LOADING_SLICE_USEC := 6000
const TerrainJob = preload("res://scripts/stream_terrain_job.gd")
const TerrainCache = preload("res://scripts/stream_terrain_cache.gd")

var stage
var roads: Dictionary = {}
var tiles: Dictionary = {}
var _road_index: Dictionary = {}
var _road_centres: Dictionary = {}
var _wanted_roads: Dictionary = {}
var _wanted_tiles: Dictionary = {}
var _pending: Array[Dictionary] = []
# Retired nodes stay available for a quick reversal until they are actually
# freed. Destroying a whole old region in a single frame causes another hitch.
var _retired_roads: Dictionary = {}
var _retired_tiles: Dictionary = {}
var _retire_queue: Array[Dictionary] = []
var _retire_enqueued: Dictionary = {}
var _jobs_since_retire: int = 0
var _ground_material: Material
var _busy: bool = false
var _priming: bool = true
var _last_position := Vector3(INF, INF, INF)
var _refresh_clock: float = 0.0
var _holding_car: bool = false
var _saved_freeze: bool = false
var _saved_velocity := Vector3.ZERO
var _saved_angular_velocity := Vector3.ZERO
# Set false before initialize() to exercise the single-threaded Web path.
var allow_worker: bool = true
var _terrain_sampler: Node3D = null
var _terrain_cache = TerrainCache.new()
var _terrain_task_id: int = -1
var _stopping: bool = false
var _terrain_work_max_usec: int = 0
var _terrain_upload_max_usec: int = 0
var _terrain_collider_max_usec: int = 0

func initialize(owner_stage: Node3D, start: Vector3) -> void:
	stage = owner_stage
	var started: int = Time.get_ticks_msec()
	_clock = StreamClock.new()
	_clock.name = "StreamingFrameClock"
	_clock.process_mode = Node.PROCESS_MODE_ALWAYS
	# Emit after the streamer has made its scheduling decision for this frame.
	_clock.process_priority = 1000
	get_tree().root.add_child(_clock)
	set_process(true)
	_ground_material = stage._make_ground_material()
	if allow_worker and not OS.has_feature("web") and not OS.has_feature("nothreads") and not Engine.is_editor_hint() and stage.has_method("_make_streaming_terrain_sampler"):
		_terrain_sampler = stage._make_streaming_terrain_sampler()
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
		await _clock.tick
	# Baking prop scenes reads meshes and creates materials. Do it while the
	# loading screen is visible, not the first time a new tree appears in game.
	if stage.track.procedural_scenery and stage.has_method("_bake_prop_mesh"):
		var library = stage.s_props()
		var props: Array = library.active_props()
		var scenery = stage.s_scenery()
		var companion_ids: Array[String] = scenery.undergrowth_prop_ids.duplicate()
		if companion_ids.is_empty() and not scenery.undergrowth_prop_id.is_empty():
			companion_ids.append(scenery.undergrowth_prop_id)
		for companion_id in companion_ids:
			var companion = library.by_id(companion_id)
			if companion != null and not props.has(companion):
				props.append(companion)
		for ground_cover_id in scenery.ground_cover_prop_ids:
			var ground_cover = library.by_id(ground_cover_id)
			if ground_cover != null and not props.has(ground_cover):
				props.append(ground_cover)
		for prop in props:
			stage._bake_prop_mesh(prop)
			stage._report_progress(0.8, "Подготовка деревьев и камней…")
			await _clock.tick
			if _stopping:
				return
	# У «Живой ленты» стартовые объекты должны существовать до снятия
	# загрузочного экрана, а не появляться после ближайшей геометрии.
	if stage.track.procedural and (stage.track.procedural_scenery or stage.track.spawn_edge_posts):
		var start_along: float = stage.network.along_road(start.x, start.z)
		var first: int = maxi(0, floori(start_along / ROAD_LENGTH) - 1)
		var last: int = mini(count - 1, floori((start_along + 512.0) / ROAD_LENGTH))
		for id in range(first, last + 1):
			if roads.has(id) and not roads[id].has_meta("decorated"):
				_pending.append({"kind": "decor", "key": id, "priority": float(id - first)})
		while not _pending.is_empty():
			await _run_job()
			if _stopping:
				return
			stage._report_progress(0.8, "Подготовка объектов перед стартом…")
			await _clock.tick
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
	var tile_priorities: Dictionary = {}
	var road_priorities: Dictionary = {}
	var centre: Vector2i = _tile_key(position)
	var forward := Vector2.ZERO
	var velocity := Vector3.ZERO
	if stage.car != null:
		velocity = stage.global_transform.basis.inverse() * stage.car.linear_velocity
		if Vector2(velocity.x, velocity.z).length_squared() > 4.0:
			forward = Vector2(velocity.x, velocity.z).normalized()
	var reach: int = ceili(radius / TILE_SIZE) + 1
	for z in range(-reach, reach + 1):
		for x in range(-reach, reach + 1):
			var key: Vector2i = centre + Vector2i(x, z)
			var tile_centre: Vector3 = _tile_centre(key)
			var distance_squared: float = _plan_distance_squared(position, tile_centre)
			if distance_squared > pow(radius + TILE_SIZE * 0.71, 2.0):
				continue
			var offset := Vector2(tile_centre.x - position.x, tile_centre.z - position.z)
			var priority: float = distance_squared - offset.dot(forward) * 180.0
			if key == centre:
				priority -= 2000000.0
			tile_priorities[key] = priority

	# Дополнительный коридор следует изгибам, а не направлению взгляда:
	# шпильки и подъёмы подгружаются даже когда они за ближайшим поворотом.
	if stage.track != null and stage.track.procedural and stage.network.distance_to_road(position.x, position.z) < 80.0:
		var along: float = stage.network.along_road(position.x, position.z)
		var tangent: Vector3 = stage.network.direction_at(along)
		var direction: float = -1.0 if velocity.length_squared() > 4.0 and velocity.dot(tangent) < -1.0 else 1.0
		var speed: float = Vector2(velocity.x, velocity.z).length()
		var ahead: float = clampf(LIVE_LOOKAHEAD_MIN + speed * LIVE_LOOKAHEAD_SECONDS, LIVE_LOOKAHEAD_MIN, LIVE_LOOKAHEAD_MAX)
		var total: float = stage.network.total_length
		var distance := 0.0
		while distance <= ahead:
			var target: float = clampf(along + direction * distance, 0.0, total)
			var target_point: Vector3 = stage.network.point_at(target)
			var target_key := _tile_key(target_point)
			var route_priority: float = 20000.0 + distance * 100.0
			var road_id: int = mini(floori(target / ROAD_LENGTH), ceili(total / ROAD_LENGTH) - 1)
			if road_id >= 0:
				road_priorities[road_id] = minf(float(road_priorities.get(road_id, INF)), route_priority)
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var key := target_key + Vector2i(dx, dz)
					var cost: float = route_priority + float(dx * dx + dz * dz) * 6000.0
					tile_priorities[key] = minf(float(tile_priorities.get(key, INF)), cost)
			if target <= 0.0 and direction < 0.0 or target >= total and direction > 0.0:
				break
			distance += TILE_SIZE * 0.5

	for key in tile_priorities:
		_wanted_tiles[key] = true
		if _retired_tiles.has(key):
			tiles[key] = _retired_tiles[key]
			_retired_tiles.erase(key)
		if not tiles.has(key):
			_pending.append({"kind": "terrain", "key": key, "priority": tile_priorities[key]})
		for id in _road_index.get(key, {}):
			_wanted_roads[id] = true
	for id in road_priorities:
		_wanted_roads[id] = true
	for id in _wanted_roads:
		if _retired_roads.has(id):
			roads[id] = _retired_roads[id]
			_retired_roads.erase(id)
		var road_centre: Vector3 = _road_centres[id]
		var offset := Vector2(road_centre.x - position.x, road_centre.z - position.z)
		var priority: float = _plan_distance_squared(position, road_centre) - offset.dot(forward) * 180.0
		priority = minf(priority, float(road_priorities.get(id, INF)))
		if not roads.has(id):
			_pending.append({"kind": "road", "key": id, "priority": priority - TILE_SIZE * TILE_SIZE})
		elif not roads[id].has_meta("decorated"):
			_pending.append({"kind": "decor", "key": id, "priority": priority + DECOR_PRIORITY_OFFSET})
	_sort_pending()
	for key in tiles.keys():
		if not _wanted_tiles.has(key) and _plan_distance_squared(position, _tile_centre(key)) > KEEP_RADIUS * KEEP_RADIUS:
			_schedule_retirement("terrain", key, tiles[key])
			tiles.erase(key)
	for id in roads.keys():
		if not _wanted_roads.has(id) and _plan_distance_squared(position, _road_centres[id]) > KEEP_RADIUS * KEEP_RADIUS:
			_schedule_retirement("road", id, roads[id])
			roads.erase(id)


func _sort_pending() -> void:
	_pending.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.priority) < float(b.priority))


func _schedule_retirement(kind: String, key, node: Node) -> void:
	var retired: Dictionary = _retired_tiles if kind == "terrain" else _retired_roads
	retired[key] = node
	var instance_id: int = node.get_instance_id()
	# A reclaimed node can be retired again before its old queue entry is
	# visited. Keep one entry per node even under repeated reversals/teleports.
	if not _retire_enqueued.has(instance_id):
		_retire_enqueued[instance_id] = true
		_retire_queue.append({"kind": kind, "key": key, "node": node, "instance_id": instance_id})


func _retire_one() -> bool:
	# Reclaimed chunks leave stale entries. Bound their cleanup too, even if a
	# player repeatedly teleports between two areas before the queue drains.
	for _attempt in range(mini(8, _retire_queue.size())):
		var item: Dictionary = _retire_queue.pop_front()
		_retire_enqueued.erase(item.instance_id)
		var retired: Dictionary = _retired_tiles if item.kind == "terrain" else _retired_roads
		# The player may have returned before the node was destroyed.
		if retired.get(item.key) != item.node:
			continue
		retired.erase(item.key)
		if is_instance_valid(item.node):
			item.node.queue_free()
		return true
	return false

func _process(delta: float) -> void:
	if _priming or _stopping or stage == null or not stage._stage_live or stage.car == null or stage.is_paused:
		return
	var position: Vector3 = stage.to_local(stage.car.global_position)
	_refresh_clock += delta
	# The frame clock completes jobs after this scheduling decision, so a
	# mesh/collider commit and a new job do not share the same frame.
	if not _busy and (_plan_distance_squared(position, _last_position) > 32.0 * 32.0 or _refresh_clock > 1.0):
		_refresh_clock = 0.0
		_request(position)
	var distance: float = stage.network.distance_to_road(position.x, position.z)
	var along: float = stage.network.along_road(position.x, position.z)
	var road_id: int = floori(along / ROAD_LENGTH)
	road_id = mini(road_id, ceili(stage.network.total_length / ROAD_LENGTH) - 1)
	var needs_road: bool = distance <= stage.track.half_width_at(along) + stage.track.road_shoulder + 2.0
	# Off-road teleports only need ground: the nearest road may be kilometres
	# away and outside the streamed radius, so requiring it would freeze forever.
	var safe: bool = tiles.has(_tile_key(position)) and (not needs_road or roads.has(road_id))
	# Teleports/resets must never drop the car through a chunk still loading.
	if not safe and not _holding_car:
		_saved_freeze = stage.car.freeze
		_saved_velocity = stage.car.linear_velocity
		_saved_angular_velocity = stage.car.angular_velocity
		stage.car.freeze = true
		_holding_car = true
	elif safe and _holding_car:
		stage.car.freeze = _saved_freeze
		stage.car.linear_velocity = _saved_velocity
		stage.car.angular_velocity = _saved_angular_velocity
		_holding_car = false
	if not _busy:
		if not _pending.is_empty():
			_run_job()
		else:
			_retire_one()

func _run_job() -> void:
	if _pending.is_empty():
		return
	# Interleave destruction with construction, but never in the same frame.
	# A large teleport backlog is drained more aggressively to bound memory.
	var retire_interval: int = 1 if _retired_tiles.size() + _retired_roads.size() > 40 else 3
	if _jobs_since_retire >= retire_interval and _retire_one():
		_jobs_since_retire = 0
		return
	_busy = true
	_jobs_since_retire += 1
	var job: Dictionary = _pending.pop_front()
	if job.kind == "road" and not roads.has(job.key):
		var id: int = int(job.key)
		var root := Node3D.new()
		root.name = "Road_%04d" % id
		add_child(root)
		await stage._build_road(true, 0.0, 0.0, float(id) * ROAD_LENGTH, float(id + 1) * ROAD_LENGTH, root)
		roads[id] = root
		if not _priming:
			_pending.append({"kind": "decor", "key": id, "priority": float(job.priority) + TILE_SIZE * TILE_SIZE + DECOR_PRIORITY_OFFSET})
			_sort_pending()
	elif job.kind == "terrain" and not tiles.has(job.key):
		await _build_tile(job.key)
	elif job.kind == "decor" and roads.has(job.key) and not roads[job.key].has_meta("decorated"):
		var id: int = int(job.key)
		var root: Node3D = roads[id]
		if stage.track.spawn_edge_posts and stage.s_spawn().edge_posts:
			stage._spawn_edge_posts(float(id) * ROAD_LENGTH, float(id + 1) * ROAD_LENGTH, root)
			await _clock.tick
			if _stopping or not is_instance_valid(root):
				return
		if stage.track.procedural_scenery:
			await stage._spawn_procedural_scenery(true, float(id) * ROAD_LENGTH, float(id + 1) * ROAD_LENGTH, root)
		if _stopping or not is_instance_valid(root):
			return
		root.set_meta("decorated", true)
	_busy = false

func _build_tile(key: Vector2i) -> void:
	var sampler = _terrain_sampler if _terrain_sampler != null else stage
	var job = TerrainJob.new(sampler, key, TILE_SIZE, TILE_DIVISIONS, _terrain_cache)
	if _terrain_sampler != null:
		_terrain_task_id = WorkerThreadPool.add_task(job.run, false, "Stream terrain data")
		while not WorkerThreadPool.is_task_completed(_terrain_task_id):
			await _clock.tick
			if _stopping:
				return
		WorkerThreadPool.wait_for_task_completion(_terrain_task_id)
		_terrain_task_id = -1
	else:
		var slice_usec: int = LOADING_SLICE_USEC if _priming else TERRAIN_SLICE_USEC
		while not job.advance(slice_usec):
			await _clock.tick
			if _stopping:
				return
	_terrain_work_max_usec = maxi(_terrain_work_max_usec, job.work_usec)
	# GPU upload and physics shape creation can each stall independently. Never
	# combine them with generation (or each other) in one frame. In particular,
	# don't call mesh.create_trimesh_shape(): that reads mesh data back from the
	# rendering server. The collision faces were prepared from the CPU arrays.
	await _clock.tick
	if _stopping:
		return
	var started: int = Time.get_ticks_usec()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, job.mesh_arrays())
	_terrain_upload_max_usec = maxi(_terrain_upload_max_usec, Time.get_ticks_usec() - started)
	await _clock.tick
	if _stopping:
		return
	started = Time.get_ticks_usec()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(job.faces)
	var body := StaticBody3D.new()
	body.name = "Terrain_%d_%d" % [key.x, key.y]
	body.position = job.origin
	body.add_to_group("Grass")
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _ground_material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(visual)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	tiles[key] = body
	_terrain_collider_max_usec = maxi(_terrain_collider_max_usec, Time.get_ticks_usec() - started)


func _exit_tree() -> void:
	_stopping = true
	if _clock != null:
		_clock.cancel()
		_clock.queue_free()
		_clock = null
	# Wait only when closing/rebuilding the world, never during gameplay. This
	# ensures the private sampler outlives the one in-flight worker task.
	if _terrain_task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_terrain_task_id)
		_terrain_task_id = -1
	if _terrain_sampler != null:
		_terrain_sampler.free()
		_terrain_sampler = null

func statistics() -> Dictionary:
	return {"road_chunks": roads.size(), "terrain_tiles": tiles.size(),
		"pending_jobs": _pending.size(), "retired_nodes": _retired_tiles.size() + _retired_roads.size(), "terrain_triangles": tiles.size() * TILE_DIVISIONS * TILE_DIVISIONS * 2,
		"global_field_cells": stage.network.field_dist.size(),
		"terrain_worker": _terrain_sampler != null,
		"terrain_work_max_ms": float(_terrain_work_max_usec) / 1000.0,
		"terrain_upload_max_ms": float(_terrain_upload_max_usec) / 1000.0,
		"terrain_collider_max_ms": float(_terrain_collider_max_usec) / 1000.0}
