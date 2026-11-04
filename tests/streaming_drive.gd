# Headless streaming stress test: two sections of the actual 100 km route.
# This measures CPU scheduling/coverage, NOT graphics FPS or real car physics.
# godot --headless --path . --script res://tests/streaming_drive.gd
# Append `-- --cooperative` to exercise the no-thread Web implementation.
extends SceneTree

const Network = preload("res://scripts/road_network.gd")
const Streamer = preload("res://scripts/world_streamer.gd")

class BenchStage extends "res://scripts/rally_stage.gd":
	func _ready() -> void:
		set_process(false)

class BenchCar extends "res://scripts/rally_car.gd":
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
		gravity_scale = 0.0
		freeze = true

func _initialize() -> void:
	call_deferred("_run")

func _make_car() -> BenchCar:
	var result := BenchCar.new()
	var particles := GPUParticles3D.new()
	particles.name = "GravelParticles"
	result.add_child(particles)
	var cameras := Node3D.new()
	cameras.name = "Cameras"
	result.add_child(cameras)
	var active := Camera3D.new()
	active.name = "ActiveCamera"
	cameras.add_child(active)
	for name in ["CamChase", "CamHood", "CamCockpit"]:
		var marker := Marker3D.new()
		marker.name = name
		cameras.add_child(marker)
	return result

func _run() -> void:
	var cooperative: bool = "--cooperative" in OS.get_cmdline_user_args()
	var failures := 0
	for start in [14.0, 27000.0]:
		var stage := BenchStage.new()
		root.add_child(stage)
		stage.track = load("res://data/tracks/stage_mountain_100.tres")
		stage.network = Network.build_sparse(stage.track.road_curve)
		stage.terrain_rect = stage._curve_terrain_rect(stage.track.road_curve)
		stage._setup_noise()
		stage.generated = Node3D.new()
		stage.add_child(stage.generated)
		var streamer = Streamer.new()
		streamer.allow_worker = not cooperative
		stage.world_streamer = streamer
		stage.generated.add_child(streamer)
		await streamer.initialize(stage, stage.network.point_at(start))
		var car := _make_car()
		stage.add_child(car)
		stage.car = car
		car.position = stage.network.point_at(start) + Vector3.UP
		stage._stage_live = true
		var distance: float = start
		var hold_frames := 0
		var max_pending := 0
		var max_retired := 0
		var frame_times: Array[float] = []
		var before: int = Time.get_ticks_usec()
		for frame in range(1800):
			if streamer._holding_car:
				hold_frames += 1
			else:
				# 200 km/h at 60 simulated frames per second. No acceleration or
				# steering assumptions hide gaps in collision coverage.
				distance += (200.0 / 3.6) / 60.0
			car.position = stage.network.point_at(distance) + Vector3.UP
			car.linear_velocity = stage.network.direction_at(distance) * (200.0 / 3.6)
			await process_frame
			var now: int = Time.get_ticks_usec()
			frame_times.append(float(now - before) / 1000.0)
			before = now
			max_pending = maxi(max_pending, streamer._pending.size())
			max_retired = maxi(max_retired, streamer._retired_tiles.size() + streamer._retired_roads.size())
		frame_times.sort()
		print("drive start=%.1fkm mode=%s distance=%.0fm held=%d/1800 pending_max=%d retired_max=%d p95=%.2fms max=%.2fms" % [start / 1000.0, "cooperative" if cooperative else "worker", distance - start, hold_frames, max_pending, max_retired, frame_times[floori(frame_times.size() * 0.95)], frame_times.back()])
		if hold_frames > 0:
			failures += 1
		stage.free() # Also tests shutdown while a terrain job may be in flight.
		await process_frame
	print("Streaming drive: %d failures" % failures)
	quit(0 if failures == 0 else 1)
