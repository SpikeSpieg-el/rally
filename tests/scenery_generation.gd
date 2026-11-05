# godot --headless --path . --script res://tests/scenery_generation.gd
extends SceneTree

const Stage = preload("res://scripts/rally_stage.gd")
const Track = preload("res://scripts/data/rally_track_config.gd")
const Placement = preload("res://scripts/data/rally_scenery_placement.gd")
const Prop = preload("res://scripts/data/rally_prop.gd")
const Network = preload("res://scripts/road_network.gd")

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func group_names(stage) -> Array[String]:
	var names: Array[String] = []
	for prop in stage.s_props().spawnable_props():
		var value := String(prop.group_name())
		if not value.is_empty() and not names.has(value):
			names.append(value)
	return names

func snapshot(stage) -> Dictionary:
	var result := {}
	var scenery: Node = stage.generated.get_node_or_null("Scenery")
	check(scenery != null, "контейнер обстановки должен существовать")
	if scenery == null:
		return result
	for group_name in group_names(stage):
		var group: Node = scenery.get_node_or_null(group_name)
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

func total_of(snapshot: Dictionary) -> int:
	var total := 0
	for key in snapshot:
		total += (snapshot[key] as Array).size()
	return total

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var placement := Placement.new()
	placement.reserve(Vector3.ZERO, 2.0)
	check(not placement.has_space(Vector3(3, 0, 0), 2.0), "пересекающиеся пропсы отклоняются")
	check(placement.has_space(Vector3(5, 0, 0), 2.0), "свободная позиция доступна")
	placement.reserve(Vector3(-12, 0, -12), 2.0)
	check(not placement.has_space(Vector3(-11, 0, -11), 1.0), "сетка работает на отрицательных координатах")
	var stage = Stage.new()
	stage.track = Track.new()
	stage.track.use_baked_props = false
	stage.track.scenery_density = 1.0
	stage.track.terrain_seed = 4711
	check(stage.s_scenery().density_multiplier <= 6.0, "крупные объекты не должны заполнять каждый свободный метр")
	check(stage.s_scenery().ground_cover_density <= 2.5, "трава не должна заглушать остальное окружение")
	check(stage.s_scenery().extra_grass_density > 0.0, "дополнительная трава включена по умолчанию")
	stage.scenery = stage.s_scenery().duplicate(true)
	stage.scenery.extra_grass_density = 0.0
	check(stage.s_scenery().roadside_prop_chance < 0.5, "заборы и гоночный реквизит должны быть редкими")
	var curve := Curve3D.new()
	curve.add_point(Vector3.ZERO)
	curve.add_point(Vector3(0, 0, 600))
	stage.terrain_rect = Rect2(-100, -100, 200, 800)
	stage.network = Network.build(curve, stage.terrain_rect, 3.0)
	stage._setup_noise()
	stage.generated = Node3D.new()
	stage.add_child(stage.generated)
	check(stage.s_props().active_props().size() >= 10, "в библиотеке должно быть хотя бы десять расставляемых видов")
	for prop in stage.s_props().spawnable_props():
		for zone in range(4):
			if prop.category == Prop.Category.FENCE or prop.category == Prop.Category.FIELD:
				check(Placement.allows(prop, zone) == (zone == 2), "сено и заборы только на полевых участках")
			if prop.category == Prop.Category.ROCKS:
				check(Placement.allows(prop, zone) == (zone == 1), "камни отдельно от полевого реквизита")
		if prop.category == Prop.Category.FENCE:
			check(prop.align_to_road and not prop.random_yaw, "забор ориентирован вдоль дороги")
	await stage._spawn_procedural_scenery(false)
	var first := snapshot(stage)
	var total := total_of(first)
	# Плотность ограничена свободным местом, а не числом успешных бросков.
	check(total > 300, "обстановка не должна исчезать после разделения зон: %d" % total)
	check(total < 10000, "генерация не должна забивать сцену объектами: %d" % total)
	check(group_names(stage).size() >= 8, "видов обстановки должно быть много")
	var cells := 0
	for key in first:
		cells = maxi(cells, stage.generated.get_node("Scenery/" + key).get_child_count())
	check(cells > 1, "объекты должны быть разделены на ячейки")
	stage.generated.get_node("Scenery").free()
	await stage._spawn_procedural_scenery(false)
	var second := snapshot(stage)
	check(first == second, "одинаковый сид должен давать одинаковые позиции")
	stage.generated.get_node("Scenery").free()
	stage.scenery.extra_grass_density = 2.5
	await stage._spawn_procedural_scenery(false)
	var grassy := snapshot(stage)
	var base_grass: int = (first.get("Grass2", []) as Array).size() + (first.get("Grass3", []) as Array).size()
	var extra_grass: int = (grassy.get("Grass2", []) as Array).size() + (grassy.get("Grass3", []) as Array).size()
	check(extra_grass > base_grass, "дополнительный слой должен увеличивать количество травы")
	for prop in stage.s_props().active_props():
		check(first.get(prop.group_name(), []) == grassy.get(prop.group_name(), []), "дополнительная трава не меняет расстановку крупных пропсов: " + prop.id)
	stage.generated.get_node("Scenery").free()
	stage.track.scenery_density = 2.0
	await stage._spawn_procedural_scenery(false)
	var dense_total := total_of(snapshot(stage))
	check(dense_total > 300 and dense_total < 15000, "высокая плотность также ограничена свободным местом")
	stage.generated.get_node("Scenery").free()
	stage.track.scenery_density = 0.0
	await stage._spawn_procedural_scenery(false)
	check(total_of(snapshot(stage)) == 0, "нулевая плотность должна убирать лес")
	stage.free()
	print("Scenery: %d объектов; ошибок %d" % [total, failures.size()])
	quit(0 if failures.is_empty() else 1)
