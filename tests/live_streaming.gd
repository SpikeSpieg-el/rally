# godot --headless --path . --script res://tests/live_streaming.gd
# Проверка начальной загрузки с быстрыми заглушками: до старта уже есть декор.
extends SceneTree

const Network = preload("res://scripts/road_network.gd")
const Track = preload("res://scripts/data/rally_track_config.gd")

class FastStreamer extends "res://scripts/world_streamer.gd":
	func _build_tile(key: Vector2i) -> void:
		var tile := Node3D.new()
		add_child(tile)
		tiles[key] = tile

class FakeStage extends Node3D:
	var network
	var track = Track.new()
	var car = null
	var _stage_live := false
	var is_paused := false
	var decorated: Array[float] = []
	func _make_ground_material() -> Material:
		return StandardMaterial3D.new()
	func _report_progress(_value: float, _status: String) -> void:
		pass
	func _build_road(_light: bool, _from: float, _to: float, _start: float, _end: float, _parent: Node3D) -> void:
		pass
	func _spawn_procedural_scenery(_light: bool, start: float, _end: float, _parent: Node3D) -> void:
		decorated.append(start)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var curve := Curve3D.new()
	curve.add_point(Vector3.ZERO)
	curve.add_point(Vector3(0, 0, 2000))
	var stage := FakeStage.new()
	stage.network = Network.build_sparse(curve)
	stage.track.procedural = true
	stage.track.procedural_scenery = true
	stage.track.spawn_edge_posts = false
	root.add_child(stage)
	var streamer := FastStreamer.new()
	stage.add_child(streamer)
	await streamer.initialize(stage, Vector3(0, 0, 14))
	var ok := true
	for id in range(5):
		if not streamer.roads.has(id) or not streamer.roads[id].has_meta("decorated"):
			printerr("FAIL: декор начального блока %d не готов к старту" % id)
			ok = false
	if stage.decorated.size() < 5:
		printerr("FAIL: пропсы перед стартом не подготовлены")
		ok = false
	stage.free()
	print("Live streaming start: ", "OK" if ok else "FAIL")
	quit(0 if ok else 1)
