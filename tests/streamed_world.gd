# godot --headless --path . --script res://tests/streamed_world.gd
extends SceneTree

const Network = preload("res://scripts/road_network.gd")
const Stage = preload("res://scripts/rally_stage.gd")
const Track = preload("res://scripts/data/rally_track_config.gd")
const Streamer = preload("res://scripts/world_streamer.gd")
const Preview = preload("res://scripts/stage_preview.gd")
const Map = preload("res://scripts/ui/mini_map.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var curve := Curve3D.new()
	curve.add_point(Vector3(-50, 0, -100))
	curve.add_point(Vector3(0, 8, 100))
	curve.add_point(Vector3(80, 18, 180))
	curve.add_point(Vector3(120, 35, 300))
	var net = Network.build_sparse(curve)
	assert(net.field_dist.is_empty() and net.field_along.is_empty())
	assert(net.regional.is_empty(), "нет глобальной сетки региона")
	# Exact nearest positions, negative coordinates, and a wide query range.
	for i in range(1, 100):
		var along: float = net.total_length * float(i) / 100.0
		var point: Vector3 = net.point_at(along)
		assert(net.distance_to_road(point.x, point.z) < 0.02)
		assert(absf(net.along_road(point.x, point.z) - along) < 0.05)
		var normal := Vector3(net.direction_at(along).z, 0.0, -net.direction_at(along).x)
		var off: Vector3 = point + normal * 3.0
		if net.direction_at(along - 5.0).dot(net.direction_at(along + 5.0)) > 0.99:
			assert(absf(net.distance_to_road(off.x, off.z) - 3.0) < 0.08)
		assert(is_finite(net.regional_height(off.x, off.z)))
	# Adjacent slices share exactly the same border geometry and normals.
	var stage = Stage.new()
	stage.track = Track.new()
	stage.track.use_baked_props = false
	stage.track.road_curve = curve
	stage.network = net
	stage.terrain_rect = Rect2(-200, -200, 600, 700)
	stage._setup_noise()
	stage.generated = Node3D.new()
	stage.add_child(stage.generated)
	var a := Node3D.new()
	var b := Node3D.new()
	stage.generated.add_child(a)
	stage.generated.add_child(b)
	await stage._build_road(false, 0, 0, 0, 128, a)
	await stage._build_road(false, 0, 0, 128, 256, b)
	var first: Array = a.get_node("RoadMesh").mesh.surface_get_arrays(0)
	var second: Array = b.get_node("RoadMesh").mesh.surface_get_arrays(0)
	for lane in range(9):
		var end_index: int = first[Mesh.ARRAY_VERTEX].size() - 9 + lane
		assert(first[Mesh.ARRAY_VERTEX][end_index].distance_to(second[Mesh.ARRAY_VERTEX][lane]) < 0.0001)
		assert(first[Mesh.ARRAY_NORMAL][end_index].distance_to(second[Mesh.ARRAY_NORMAL][lane]) < 0.0001)
	# HUD never draws 100,000 route points or searches them per frame.
	var map = Map.new()
	var points := PackedVector2Array()
	for i in range(100001):
		points.append(Vector2(i, i % 100))
	map.set_route(points, PackedVector2Array(), points[0], points[points.size() - 1])
	assert(map.route.size() == 1400)
	assert(map.route[0] == points[0] and map.route[1399] == points[100000])
	map.free()
	var preview = Preview.new()
	preview.track = load("res://data/tracks/stage_mountain_100.tres")
	preview._rebuild(false)
	assert(preview._points.size() <= 2200)
	preview.free()
	stage.free()
	# Exercise scheduling and eviction without textures or a 100 km mesh.
	var mock := StreamStage.new()
	mock.network = net
	root.add_child(mock)
	var streamer = Streamer.new()
	mock.add_child(streamer)
	await streamer.initialize(mock, net.point_at(14.0))
	assert(streamer.tiles.size() <= 85)
	assert(streamer.roads.size() < 10)
	assert(streamer.statistics().global_field_cells == 0)
	streamer._request(Vector3(4000.0, 0.0, 4000.0))
	assert(streamer.tiles.is_empty() and streamer.roads.is_empty(), "далёкие тайлы и коллизии выгружаются")
	assert(streamer._pending.size() <= 85)
	mock.free()
	print("Sparse network, chunk seams, bounded minimap: OK")
	quit(0)

class StreamStage:
	extends Node3D
	var network
	var track = preload("res://scripts/data/rally_track_config.gd").new()
	var _stage_live: bool = false
	var car = null

	func _make_ground_material() -> Material:
		return StandardMaterial3D.new()

	func height_at(x: float, z: float) -> float:
		return x * 0.01 + z * 0.02

	func _road_ditch(_distance: float) -> float:
		return 0.0

	func _report_progress(_value: float, _status: String) -> void:
		pass

	func _build_road(_light: bool, _from: float, _to: float, _start: float, _end: float, _parent: Node3D) -> void:
		pass
