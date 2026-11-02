# godot --headless --path . --script res://tests/scenery_generation.gd
extends SceneTree

const Stage = preload("res://scripts/rally_stage.gd")
const Track = preload("res://scripts/data/rally_track_config.gd")
const Network = preload("res://scripts/road_network.gd")

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func snapshot(stage) -> Dictionary:
	var result := {}
	var scenery: Node = stage.generated.get_node("Scenery")
	for group_name in ["Firs", "Pines", "TrunkVisuals", "Bushes", "Boulders", "Grass", "Stumps", "Logs"]:
		var group: Node = scenery.get_node_or_null(group_name)
		check(group != null, "отсутствует вид объектов " + group_name)
		if group == null:
			continue
		var positions: Array[Vector3] = []
		for child in group.get_children():
			var cell := child as MultiMeshInstance3D
			check(cell != null and cell.visibility_range_end > 0.0, "ячейка должна отсекаться по дистанции")
			if cell == null:
				continue
			check(cell.multimesh.instance_count > 0, "пустая ячейка")
			for i in range(cell.multimesh.instance_count):
				var point: Vector3 = (cell.transform * cell.multimesh.get_instance_transform(i)).origin
				positions.append(point)
				check(stage.network.distance_to_road(point.x, point.z) >= stage.corridor_half() + 3.45, "объект на полотне или слишком близко к другому витку")
		result[group_name] = positions
	return result

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var stage = Stage.new()
	stage.track = Track.new()
	stage.track.use_baked_props = false
	stage.track.scenery_density = 1.0
	stage.track.terrain_seed = 4711
	var curve := Curve3D.new()
	curve.add_point(Vector3.ZERO)
	curve.add_point(Vector3(0, 0, 600))
	stage.terrain_rect = Rect2(-100, -100, 200, 800)
	stage.network = Network.build(curve, stage.terrain_rect, 3.0)
	stage._setup_noise()
	stage.generated = Node3D.new()
	stage.add_child(stage.generated)
	await stage._spawn_procedural_scenery(false)
	var first := snapshot(stage)
	var total := 0
	for key in first:
		if key != "TrunkVisuals":
			total += first[key].size()
	check(total > 220, "сцена должна быть плотнее прежней: %d" % total)
	check(stage.generated.get_node("Scenery/Firs").get_child_count() > 1, "деревья должны быть разделены на ячейки")
	stage.generated.get_node("Scenery").free()
	await stage._spawn_procedural_scenery(false)
	var second := snapshot(stage)
	check(first == second, "одинаковый сид должен давать одинаковые позиции")
	stage.generated.get_node("Scenery").free()
	stage.track.scenery_density = 2.0
	await stage._spawn_procedural_scenery(false)
	var dense := snapshot(stage)
	var dense_total := 0
	for key in dense:
		if key != "TrunkVisuals":
			dense_total += dense[key].size()
	check(dense_total > total * 1.5, "увеличение плотности должно заметно добавлять объекты")
	stage.generated.get_node("Scenery").free()
	stage.track.scenery_density = 0.0
	await stage._spawn_procedural_scenery(false)
	check(stage.generated.get_node("Scenery").get_node_or_null("Firs") == null, "нулевая плотность должна убирать лес")
	stage.free()
	print("Scenery: %d объектов; ошибок %d" % [total, failures.size()])
	quit(0 if failures.is_empty() else 1)
