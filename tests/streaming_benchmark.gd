# Headless CPU benchmark for the real 100 km stage; this is NOT a GPU/FPS test.
# godot --headless --path . --script res://tests/streaming_benchmark.gd
extends SceneTree

const Network = preload("res://scripts/road_network.gd")
const Streamer = preload("res://scripts/world_streamer.gd")

class BenchStage extends "res://scripts/rally_stage.gd":
	# Build only the real streamed world, without starting car/HUD/game systems.
	func _ready() -> void:
		set_process(false)

class FrameMonitor extends Node:
	var last_usec: int = 0
	var label := "idle"
	var samples: Dictionary = {}

	func _process(_delta: float) -> void:
		var now: int = Time.get_ticks_usec()
		if last_usec > 0:
			if not samples.has(label):
				samples[label] = []
			(samples[label] as Array).append(float(now - last_usec) / 1000.0)
		last_usec = now

	func print_results() -> void:
		for kind in samples:
			var times: Array = samples[kind]
			if times.is_empty():
				continue
			times.sort()
			var sum := 0.0
			for value in times:
				sum += float(value)
			print("%s: frames=%d avg=%.2fms p95=%.2fms max=%.2fms" % [kind, times.size(), sum / times.size(), times[mini(times.size() - 1, floori(times.size() * 0.95))], times.back()])

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var monitor := FrameMonitor.new()
	root.add_child(monitor)
	var stage := BenchStage.new()
	root.add_child(stage)
	stage.track = load("res://data/tracks/stage_mountain_100.tres")
	stage.network = Network.build_sparse(stage.track.road_curve)
	stage.terrain_rect = stage._curve_terrain_rect(stage.track.road_curve)
	stage._setup_noise()
	stage.generated = Node3D.new()
	stage.add_child(stage.generated)
	var streamer = Streamer.new()
	streamer.allow_worker = not ("--cooperative" in OS.get_cmdline_user_args())
	stage.generated.add_child(streamer)
	monitor.label = "startup"
	await streamer.initialize(stage, stage.network.point_at(14.0))
	stage._stage_live = true
	monitor.samples.clear()
	monitor.last_usec = 0
	# Decor is queued after the safe start; then move forward through several
	# tile/chunk boundaries and sample one mountain switchback as a teleport.
	for distance in [14.0, 110.0, 206.0, 302.0, 398.0, 27000.0]:
		streamer._request(stage.network.point_at(distance))
		while not streamer._pending.is_empty():
			monitor.label = str(streamer._pending[0].kind)
			await streamer._run_job()
			await process_frame
		print("km %.3f: %s" % [distance / 1000.0, streamer.statistics()])
	monitor.print_results()
	stage.free()
	monitor.free()
	quit(0)
