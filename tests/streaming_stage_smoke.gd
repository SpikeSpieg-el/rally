# Full scene integration for the 100 km streamed stage (headless).
# godot --headless --path . --script res://tests/streaming_stage_smoke.gd
extends SceneTree

const StageScene = preload("res://scenes/rally_stage.tscn")
var failures: Array[String] = []

class FrameProbe extends Node:
	var measuring := false
	var previous_usec := 0
	var times := PackedFloat32Array()

	func _process(_delta: float) -> void:
		if measuring:
			var now := Time.get_ticks_usec()
			if previous_usec > 0:
				times.append(float(now - previous_usec) / 1000.0)
			previous_usec = now

	func summary() -> String:
		if times.is_empty():
			return "no frames"
		times.sort()
		return "p95=%.2fms max=%.2fms frames=%d" % [times[mini(times.size() - 1, floori(times.size() * 0.95))], times[-1], times.size()]

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var stage = StageScene.instantiate()
	stage.track_override = load("res://data/tracks/stage_mountain_100.tres")
	root.add_child(stage)
	var deadline: int = Time.get_ticks_msec() + 60000
	while not stage._stage_live and Time.get_ticks_msec() < deadline:
		await process_frame
	if not stage._stage_live:
		printerr("FAIL: streamed stage did not start")
		stage.queue_free()
		quit(1)
		return
	var streamer = stage.world_streamer
	check(streamer != null, "long stage must use the streamer")
	check(stage.car != null and not stage.car.freeze, "car must be released after startup")
	check(not streamer.roads.is_empty() and not streamer.tiles.is_empty(), "startup geometry missing")
	await physics_frame
	var start: Vector3 = stage.network.point_at(stage.s_spawn().car_spawn_distance)
	var ray := PhysicsRayQueryParameters3D.create(stage.to_global(start + Vector3.UP * 20.0), stage.to_global(start - Vector3.UP * 20.0))
	ray.exclude = [stage.car.get_rid()]
	var hit: Dictionary = stage.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty(), "start collision must be raycastable")

	# Unlike the route-position stress test, this uses the real RallyCar,
	# input, suspension and physics on the full streamed scene.
	for i in range(120):
		await physics_frame
	var drive_start: Vector3 = stage.car.global_position
	var drive_forward: Vector3 = stage.car.global_basis.z.normalized()
	var drive_plan_start: Vector3 = streamer._last_position
	var held_frames := 0
	var contact_frames := 0
	var tiles_before: int = streamer.tiles.size()
	var probe := FrameProbe.new()
	root.add_child(probe)
	probe.measuring = true
	Input.action_press("throttle")
	for i in range(480):
		await physics_frame
		if streamer._holding_car:
			held_frames += 1
		if stage.car.get_wheel_contact_count() > 0:
			contact_frames += 1
	Input.action_release("throttle")
	probe.measuring = false
	var travelled: float = (stage.car.global_position - drive_start).dot(drive_forward)
	print("Full stage physics: forward=%.1fm speed=%.1fkm/h contacts=%d/480 held=%d tiles=%d->%d %s" % [travelled, stage.car.speed_kmh, contact_frames, held_frames, tiles_before, streamer.tiles.size(), probe.summary()])
	probe.queue_free()
	check(travelled > 8.0 and stage.car.linear_velocity.is_finite(), "car must be able to drive on the streamed track")
	check(contact_frames > 0, "wheels must contact streamed collision")
	check(held_frames == 0, "normal driving should not be held by the streamer")
	check(streamer._plan_distance_squared(drive_plan_start, streamer._last_position) > 16.0 * 16.0, "streaming plan should update while driving")

	# Teleport during normal streaming. Both road and terrain must eventually
	# appear; the pre-existing freeze state must not be changed by the streamer.
	stage.car.freeze = true
	stage.car.set_physics_process(false)
	for distance in [27000.0, 96000.0]:
		var destination: Vector3 = stage.network.point_at(distance)
		stage.car.global_position = stage.to_global(destination + Vector3.UP * 2.0)
		await process_frame
		var along: float = stage.network.along_road(destination.x, destination.z)
		var road_id: int = mini(floori(along / streamer.ROAD_LENGTH), ceili(stage.network.total_length / streamer.ROAD_LENGTH) - 1)
		var key: Vector2i = streamer._tile_key(destination)
		deadline = Time.get_ticks_msec() + 30000
		while (not streamer.roads.has(road_id) or not streamer.tiles.has(key) or streamer._holding_car) and Time.get_ticks_msec() < deadline:
			await process_frame
		check(streamer.roads.has(road_id), "teleport road collision was not loaded at %.0f m" % distance)
		check(streamer.tiles.has(key), "teleport terrain collision was not loaded at %.0f m" % distance)
		check(not streamer._holding_car, "car was not released after teleport at %.0f m" % distance)
		check(stage.car.freeze, "streamer must restore the car's previous freeze state")
		await physics_frame
		ray = PhysicsRayQueryParameters3D.create(stage.to_global(destination + Vector3.UP * 20.0), stage.to_global(destination - Vector3.UP * 20.0))
		ray.exclude = [stage.car.get_rid()]
		hit = stage.get_world_3d().direct_space_state.intersect_ray(ray)
		check(not hit.is_empty(), "teleport collision must be raycastable at %.0f m" % distance)
	stage.queue_free()
	await process_frame
	print("Full streamed stage: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
