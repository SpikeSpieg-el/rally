# godot --headless --path . --script res://tests/streaming_runtime.gd
extends SceneTree

const Network = preload("res://scripts/road_network.gd")
const Stage = preload("res://scripts/rally_stage.gd")
const Streamer = preload("res://scripts/world_streamer.gd")
const TerrainJob = preload("res://scripts/stream_terrain_job.gd")
const TerrainCache = preload("res://scripts/stream_terrain_cache.gd")
const Track = preload("res://scripts/data/rally_track_config.gd")

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _initialize() -> void:
	call_deferred("_run")


func brute_nearest(net, x: float, z: float) -> Vector2:
	var best := Vector2(INF, 0.0)
	for i in range(net.samples.size() - 1):
		var a: Vector3 = net.samples[i]
		var b: Vector3 = net.samples[i + 1]
		var hit: Vector3 = net._nearest_on_segment(Vector2(x, z), Vector2(a.x, a.z), Vector2(b.x, b.z), net.sample_dists[i], net.sample_dists[i + 1])
		if hit.x < best.x:
			best = Vector2(hit.x, hit.y)
	return best


func _run() -> void:
	var track = load("res://data/tracks/stage_mountain_100.tres")
	var stage = Stage.new()
	stage.track = track
	stage.network = Network.build_sparse(track.road_curve)
	stage._setup_noise()
	# Compare the spatial lookup to the actual metre segments, including the
	# far-off-route fallback and negative coordinates.
	for distance in [14.0, 8000.0, 27000.0, 58000.0, 96000.0]:
		var p: Vector3 = stage.network.point_at(distance)
		var dir: Vector3 = stage.network.direction_at(distance)
		var side := Vector3(dir.z, 0, -dir.x)
		for offset in [0.0, 20.0, -45.0]:
			var at: Vector3 = p + side * offset
			var reference := brute_nearest(stage.network, at.x, at.z)
			var actual: Vector2 = stage.network._sparse_sample(at.x, at.z)
			check(absf(actual.x - reference.x) < 0.1, "sparse distance near %.0f m: %s vs %s" % [distance, actual, reference])
	for p in [Vector2(-30000, -50000), Vector2(15000, 20000)]:
		var reference := brute_nearest(stage.network, p.x, p.y)
		var actual: Vector2 = stage.network._sparse_sample(p.x, p.y)
		check(absf(actual.x - reference.x) < 1.0, "far sparse lookup: %s vs %s" % [actual, reference])

	var sampler = stage._make_streaming_terrain_sampler()
	var original_query: Vector2 = stage.network._last_query
	sampler.network.distance_to_road(123.0, -456.0)
	check(stage.network._last_query == original_query, "worker must not mutate live road query cache")
	sampler.network.regional_height(123.0, -456.0)
	check(sampler.network._regional_nodes != stage.network._regional_nodes, "regional caches must be independent")
	var short_curve := Curve3D.new()
	short_curve.add_point(Vector3.ZERO)
	short_curve.add_point(Vector3(0, 0, 16))
	var short_net = Network.build_sparse(short_curve)
	for n in range(Network.REGIONAL_NODE_LIMIT + 2):
		short_net._regional_node(Vector2i(n, 0))
	check(short_net._regional_nodes.size() == Network.REGIONAL_NODE_LIMIT, "regional cache must stay bounded without wholesale clears")
	check(short_net._regional_nodes.has(Vector2i(2, 0)) and not short_net._regional_nodes.has(Vector2i.ZERO), "regional cache must evict only its oldest entries")

	var point: Vector3 = stage.network.point_at(27000.0)
	var key := Vector2i(floori(point.x / 96.0), floori(point.z / 96.0))
	var reference_job = TerrainJob.new(stage, key, 96.0, 16)
	reference_job.advance(0)
	var cache = TerrainCache.new()
	var worker_job = TerrainJob.new(sampler, key, 96.0, 16, cache)
	var task: int = WorkerThreadPool.add_task(worker_job.run)
	while not WorkerThreadPool.is_task_completed(task):
		await process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	check(worker_job.vertices == reference_job.vertices, "worker and cooperative terrain vertices differ")
	check(worker_job.normals == reference_job.normals, "worker and cooperative terrain normals differ")
	check(worker_job.colors == reference_job.colors, "worker and cooperative terrain colours differ")
	check(worker_job.indices == reference_job.indices, "worker and cooperative indices differ")
	check(worker_job.faces.size() == worker_job.indices.size(), "collider triangle count")
	for i in range(worker_job.indices.size()):
		if worker_job.faces[i] != worker_job.vertices[worker_job.indices[i]]:
			check(false, "collision faces must be made from the identical CPU vertices")
			break
	# Values should match the previous analytical terrain, not merely agree
	# between two copies of the new generator.
	for i in range(0, worker_job.vertices.size(), 23):
		var vertex: Vector3 = worker_job.vertices[i]
		var px: float = worker_job.origin.x + vertex.x
		var pz: float = worker_job.origin.z + vertex.z
		var expected: float = stage.height_at(px, pz) - stage._road_ditch(stage.network.distance_to_road(px, pz))
		check(absf(vertex.y - expected) < 0.002, "terrain height changed at %s" % Vector2(px, pz))

	var neighbour = TerrainJob.new(sampler, key + Vector2i(1, 0), 96.0, 16, cache)
	while not neighbour.advance(1000):
		await process_frame
	check(cache.hits > 0, "adjacent tiles must reuse halo samples")
	for z in range(17):
		var a: int = z * 17 + 16
		var b: int = z * 17
		check(absf(worker_job.vertices[a].y - neighbour.vertices[b].y) < 0.0001, "tile height seam")
		check(worker_job.normals[a].distance_to(neighbour.normals[b]) < 0.0001, "tile normal seam")
	var bounded = TerrainCache.new()
	for i in range(TerrainCache.LIMIT + 32):
		bounded.put_sample(Vector2i(i, 0), Vector3(float(i), 0, 0))
	check(bounded._values.size() == TerrainCache.LIMIT, "terrain cache must stay bounded")
	check(bounded.get_sample(Vector2i(0, 0)) == null, "old terrain sample must be evicted")
	sampler.free()
	var route_network = stage.network
	stage.free()

	await _test_scheduler()
	_test_car_tracking()
	_test_live_scheduler()
	await _test_inflight_shutdown(route_network, track, key)
	print("Streaming runtime: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _test_scheduler() -> void:
	var curve := Curve3D.new()
	curve.add_point(Vector3.ZERO)
	curve.add_point(Vector3(0, 0, 1000))
	var mock := MockStage.new()
	mock.network = Network.build_sparse(curve)
	root.add_child(mock)
	var streamer = Streamer.new()
	mock.add_child(streamer)
	streamer.set_process(false)
	streamer.stage = mock
	streamer._priming = false
	var initial := Vector3(0, 0, 64)
	var tile_key: Vector2i = streamer._tile_key(initial)
	var tile := Node3D.new()
	var road := Node3D.new()
	streamer.add_child(tile)
	streamer.add_child(road)
	streamer.tiles[tile_key] = tile
	streamer.roads[0] = road
	streamer._road_centres[0] = initial
	streamer._road_index[tile_key] = {0: true}
	var far := Vector3(5000, 0, 5000)
	streamer._request(far)
	check(streamer.tiles.is_empty() and streamer.roads.is_empty(), "teleport retires old active nodes")
	check(streamer._retired_tiles.size() == 1 and streamer._retired_roads.size() == 1, "teleport must defer destruction")
	streamer._request(initial)
	check(streamer.tiles.get(tile_key) == tile and streamer.roads.get(0) == road, "return must reuse not-yet-freed chunks")
	streamer._request(far)
	check(streamer._retire_queue.size() == 2, "repeated retirement must not duplicate queued nodes")
	check(streamer._pending[0].kind == "terrain" and streamer._pending[0].key == streamer._tile_key(far), "ground under a teleport has priority")
	check(streamer._retire_one(), "retirement queue must make progress")
	check(streamer._retired_tiles.size() + streamer._retired_roads.size() == 1, "retire only one node per frame")
	await process_frame

	# Off-road teleports must unfreeze after ground arrives even when no road
	# is in range; on-road positions must also wait for the corresponding road.
	var car := RigidBody3D.new()
	mock.add_child(car)
	mock.car = car
	mock._stage_live = true
	car.gravity_scale = 0.0
	car.global_position = far
	car.linear_velocity = Vector3(3, 0, 4)
	streamer._pending.clear()
	streamer._last_position = far
	streamer._process(0.0)
	check(car.freeze and streamer._holding_car, "missing ground must hold car")
	var ground := Node3D.new()
	streamer.add_child(ground)
	streamer.tiles[streamer._tile_key(far)] = ground
	streamer._process(0.0)
	check(not car.freeze and not streamer._holding_car, "off-road car must resume without a faraway road")
	check(car.linear_velocity.distance_to(Vector3(3, 0, 4)) < 0.01, "velocity must survive the hold")

	car.global_position = Vector3(0, 0, 64)
	streamer._pending.clear()
	streamer._last_position = car.global_position
	var near_ground := Node3D.new()
	streamer.add_child(near_ground)
	streamer.tiles[tile_key] = near_ground
	streamer.roads.clear()
	streamer._process(0.0)
	check(car.freeze, "on-road car must wait for its road collision")
	var near_road := Node3D.new()
	streamer.add_child(near_road)
	streamer.roads[0] = near_road
	streamer._process(0.0)
	check(not car.freeze, "car resumes when both ground and road are ready")
	mock.free()


# A moving car, not the stationary streamer node, must drive planning and the
# safety hold. Use a transformed stage so world/local coordinate mixups fail.
func _test_car_tracking() -> void:
	var curve := Curve3D.new()
	curve.add_point(Vector3.ZERO)
	curve.add_point(Vector3(0, 0, 3000))
	var mock := MockStage.new()
	mock.network = Network.build_sparse(curve)
	root.add_child(mock)
	mock.position = Vector3(1200, 30, -800)
	mock.rotation.y = 0.7
	var streamer := TrackingStreamer.new()
	mock.add_child(streamer)
	streamer.set_process(false)
	streamer.stage = mock
	streamer.position = Vector3(500, 0, -500)
	streamer._priming = false
	var car := RigidBody3D.new()
	mock.add_child(car)
	mock.car = car
	mock._stage_live = true
	car.gravity_scale = 0.0
	var initial := Vector3(0, 0, 64)
	car.global_position = mock.to_global(initial)
	streamer._last_position = initial
	streamer.tiles[streamer._tile_key(initial)] = Node3D.new()
	streamer.roads[0] = Node3D.new()
	streamer._process(0.0)
	check(streamer.requests.is_empty(), "stationary car must not replan around the streamer")
	check(not streamer._holding_car, "loaded ground under car must be considered safe")
	var destination := Vector3(0, 0, 180)
	car.global_position = mock.to_global(destination)
	var velocity := Vector3(3, 0, 4)
	car.linear_velocity = velocity
	streamer._process(0.0)
	check(streamer.requests.size() == 1 and streamer.requests[0].distance_to(destination) < 0.01, "plan follows car in stage-local coordinates")
	check(streamer._holding_car and car.freeze, "missing ground at car must hold it")
	streamer.tiles[streamer._tile_key(destination)] = Node3D.new()
	streamer._process(0.0)
	check(streamer._holding_car, "on-road car must wait for the new road too")
	streamer.roads[1] = Node3D.new()
	streamer._process(0.0)
	check(not streamer._holding_car and not car.freeze, "car resumes when its own terrain and road are ready")
	check(car.linear_velocity.distance_to(velocity) < 0.01, "car velocity survives streaming hold")
	for node in streamer.tiles.values():
		node.free()
	for node in streamer.roads.values():
		node.free()
	mock.free()


class TrackingStreamer extends "res://scripts/world_streamer.gd":
	var requests: Array[Vector3] = []

	func _request(centre_pos: Vector3, _radius: float = 384.0) -> void:
		requests.append(centre_pos)
		_last_position = centre_pos

	func _run_job(_index: int = 0) -> void:
		pass


func _test_live_scheduler() -> void:
	var curve := Curve3D.new()
	curve.add_point(Vector3.ZERO)
	curve.add_point(Vector3(0, 0, 3000))
	var mock := MockStage.new()
	mock.network = Network.build_sparse(curve)
	mock.track.procedural = true
	root.add_child(mock)
	var streamer = Streamer.new()
	mock.add_child(streamer)
	streamer.set_process(false)
	streamer.stage = mock
	streamer._priming = false
	var count: int = ceili(mock.network.total_length / streamer.ROAD_LENGTH)
	for id in range(count):
		streamer._road_centres[id] = mock.network.point_at((float(id) + 0.5) * streamer.ROAD_LENGTH)
		var d: float = float(id) * streamer.ROAD_LENGTH
		while d <= minf(mock.network.total_length, float(id + 1) * streamer.ROAD_LENGTH):
			var key: Vector2i = streamer._tile_key(mock.network.point_at(d))
			if not streamer._road_index.has(key):
				streamer._road_index[key] = {}
			streamer._road_index[key][id] = true
			d += 16.0
	var car := RigidBody3D.new()
	mock.add_child(car)
	mock.car = car
	car.global_position = mock.network.point_at(100.0)
	car.linear_velocity = Vector3(0, 0, 55.0)
	streamer._request(car.position)
	var future: Vector2i = streamer._tile_key(mock.network.point_at(850.0))
	check(streamer._wanted_tiles.has(future) and streamer._wanted_roads.has(6), "live route loads terrain and road well ahead")
	check(streamer._wanted_tiles.size() < 275, "predictive corridor stays bounded")
	var future_tile := Node3D.new()
	streamer.add_child(future_tile)
	streamer.tiles[future] = future_tile
	var near_road := Node3D.new()
	streamer.add_child(near_road)
	streamer.roads[1] = near_road
	streamer._request(car.position)
	check(streamer.tiles.has(future), "wanted lookahead tile beyond keep radius is not retired")
	var decor_priority := INF
	var far_terrain_priority := -INF
	for job in streamer._pending:
		if job.kind == "decor" and job.key == 1:
			decor_priority = float(job.priority)
		if job.kind == "terrain" and streamer._plan_distance_squared(car.position, streamer._tile_centre(job.key)) > 300.0 * 300.0:
			far_terrain_priority = maxf(far_terrain_priority, float(job.priority))
	check(decor_priority < far_terrain_priority, "nearby decoration must not wait for all distant terrain")
	car.global_position = mock.network.point_at(1500.0)
	car.linear_velocity = Vector3(0, 0, -55.0)
	streamer._request(car.position)
	check(streamer._wanted_roads.has(7) and not streamer._wanted_roads.has(17), "lookahead follows reversing direction")
	mock.free()


func _test_inflight_shutdown(net, track, key: Vector2i) -> void:
	var stage := QuietStage.new()
	root.add_child(stage)
	stage.network = net
	stage.track = track
	stage._setup_noise()
	var streamer = Streamer.new()
	stage.add_child(streamer)
	streamer.stage = stage
	streamer._ground_material = StandardMaterial3D.new()
	streamer._clock = Streamer.StreamClock.new()
	root.add_child(streamer._clock)
	var sampler := GatedSampler.new()
	sampler.track = track.duplicate(true)
	sampler.network = net.sparse_reader()
	sampler._setup_noise()
	streamer._terrain_sampler = sampler
	streamer._build_tile(key)
	check(streamer._terrain_task_id >= 0, "terrain worker should be in flight")
	# Wait until the worker is actually inside the sampler, then remove the
	# streamer while it is still running (rather than merely queued).
	sampler.started.wait()
	check(not WorkerThreadPool.is_task_completed(streamer._terrain_task_id), "worker must still be active during shutdown")
	# _exit_tree joins the worker before freeing the private sampler and
	# cancels frame waits, so no freed node can be accessed by the worker.
	streamer.free()
	await process_frame
	stage.free()


class QuietStage extends "res://scripts/rally_stage.gd":
	func _ready() -> void:
		set_process(false)


class GatedSampler extends "res://scripts/rally_stage.gd":
	var started := Semaphore.new()
	var first_sample := true

	func _height_with_sample(x: float, z: float, distance: float, along: float) -> float:
		if first_sample:
			first_sample = false
			started.post()
			OS.delay_msec(150)
		return super._height_with_sample(x, z, distance, along)


class MockStage:
	extends Node3D
	var network
	var track = Track.new()
	var _stage_live: bool = false
	var is_paused: bool = false
	var car: RigidBody3D = null
