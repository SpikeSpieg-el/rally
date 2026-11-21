# godot --headless --path . --fixed-fps 120 --script res://tests/damage_lab.gd
# Лаборатория деформации: кузов собирается для каждой машины реестра и для
# произвольной сцены, удары по зонам и в точку мнут только панели rally_body_fx,
# ремонт возвращает исходную геометрию, а настройка из поля сцены ограничивает глубину.
extends SceneTree

const LabScene := preload("res://scenes/editor/damage_lab.tscn")

var failures: Array[String] = []


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)


func _initialize() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _run() -> void:
	var lab := LabScene.instantiate() as DamageLab
	check(lab != null, "сцена лаборатории открывается")
	if lab == null:
		quit(1)
		return
	root.add_child(lab)
	await _frames(3)

	# Каждая машина реестра: панели есть, удар спереди мнёт, ремонт выправляет.
	for index in range(3):
		lab.set_vehicle_index(index)
		await _frames(2)
		check(lab.body_model() != null, "кузов собран: индекс %d" % index)
		check(lab.panel_count() > 0,
			"кузовные панели найдены: индекс %d (%d шт.)" % [index, lab.panel_count()])
		var depth := lab.preset_impact(0)
		check(depth > 0.0, "удар спереди мнёт кузов: индекс %d (%.3f м)" % [index, depth])
		var stats: Dictionary = lab.deformation_stats()
		check(int(stats["moved_vertices"]) > 0, "вершины сдвинуты: индекс %d" % index)
		lab.repair()
		check(lab.total_dent_depth() == 0.0, "ремонт выправляет кузов: индекс %d" % index)
		var cleared: Dictionary = lab.deformation_stats()
		check(int(cleared["moved_vertices"]) == 0,
			"после ремонта вершины на месте: индекс %d" % index)

	# Точка удара напрямую: центр передней грани по AABB кузова.
	lab.set_vehicle_index(0)
	await _frames(2)
	var box: AABB = lab.body_aabb()
	check(box.size.length_squared() > 0.0, "AABB кузова посчитан")
	var center := box.get_center()
	var front_point := Vector3(center.x, center.y, box.position.z + box.size.z)
	var direct := lab.dent_at(front_point, Vector3(0.0, 0.0, -1.0), 15.0)
	check(direct > 0.0, "удар в точку мнёт кузов (%.3f м)" % direct)

	# Все зоны и случайный удар обрабатываются без падений.
	for preset in range(6):
		var gained := lab.preset_impact(preset)
		check(gained >= 0.0, "зона %d: удар обработан" % preset)
	var random_depth := lab.random_impact()
	check(random_depth >= 0.0, "случайный удар обработан")
	lab.repair()

	# Произвольный кузов: сцена Golf вместо реестра.
	lab.custom_car_scene = load("res://scenes/rally_car2.tscn") as PackedScene
	lab.rebuild_body()
	await _frames(2)
	check(lab.panel_count() > 0,
		"произвольная сцена даёт кузовные панели (%d шт.)" % lab.panel_count())
	check(lab.preset_impact(0) > 0.0, "произвольный кузов мнётся")
	lab.custom_car_scene = null

	# Настройка из поля сцены: потолок глубины 5 см вместо 16 см.
	var soft := RallyDamageVisualConfig.new()
	soft.depth_min_m = 0.05
	soft.depth_max_m = 0.05
	lab.damage_config = soft
	lab.set_vehicle_index(0)
	await _frames(2)
	var soft_depth := lab.preset_impact(0)
	check(soft_depth > 0.0 and soft_depth <= 0.05 + 0.0005,
		"глубина берётся из ресурса сцены (%.3f м ≤ 0.05)" % soft_depth)
	lab.damage_config = null
	lab.repair()

	lab.queue_free()
	await _frames(2)

	if failures.is_empty():
		print("PASS: лаборатория собирает любой кузов и показывает деформацию")
	print("Damage lab: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
