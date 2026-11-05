# godot --headless --path . --script res://tests/streaming_decor_priority.gd
extends SceneTree

const Streamer = preload("res://scripts/world_streamer.gd")
const Network = preload("res://scripts/road_network.gd")
const Track = preload("res://scripts/data/rally_track_config.gd")
const Spawn = preload("res://scripts/data/rally_spawn_layout.gd")

class FakeStage extends Node3D:
	var network
	var track = Track.new()
	var spawn = Spawn.new()
	var car: RigidBody3D
	var _stage_live := true
	var is_paused := false
	var clock
	func s_spawn():
		return spawn
	func _build_road(_light: bool, _from: float, _to: float, _start: float, _end: float, _parent: Node3D) -> void:
		pass
	func _spawn_procedural_scenery(_light: bool, _start: float, _end: float, _parent: Node3D) -> void:
		await clock.tick
		await clock.tick

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var stage := FakeStage.new()
	var curve := Curve3D.new()
	curve.add_point(Vector3.ZERO)
	curve.add_point(Vector3(0, 0, 1000))
	stage.network = Network.build_sparse(curve)
	stage.track.procedural_scenery = true
	stage.track.spawn_edge_posts = false
	stage.spawn.guardrails = false
	root.add_child(stage)
	stage.car = RigidBody3D.new()
	stage.car.freeze = true
	stage.add_child(stage.car)
	var streamer = Streamer.new()
	stage.add_child(streamer)
	streamer.set_process(false)
	streamer.stage = stage
	streamer._priming = false
	streamer._clock = Streamer.StreamClock.new()
	stage.clock = streamer._clock
	root.add_child(streamer._clock)
	streamer._clock.set_process(false)
	var road := Node3D.new()
	streamer.add_child(road)
	streamer.roads[0] = road
	var tile := Node3D.new()
	streamer.add_child(tile)
	streamer.tiles[Vector2i.ZERO] = tile
	streamer._last_position = Vector3.ZERO
	streamer._pending = [{"kind": "decor", "key": 0, "priority": 0.0}]
	streamer._run_job()
	var ok: bool = streamer._decor_busy and not streamer._busy
	# A geometry job arriving while scenery is still running must start now.
	streamer._pending = [{"kind": "decor", "key": 0, "priority": 0.0}, {"kind": "road", "key": 1, "priority": 100.0}]
	streamer._process(0.016)
	ok = ok and streamer.roads.has(1) and streamer._decor_busy
	streamer._clock.tick.emit()
	streamer._clock.tick.emit()
	ok = ok and road.has_meta("decorated") and not streamer._decor_busy
	stage.free()
	print("Decoration priority: ", "OK" if ok else "FAIL")
	quit(0 if ok else 1)
