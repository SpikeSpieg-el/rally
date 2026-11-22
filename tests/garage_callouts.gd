# godot --headless --path . --script res://tests/garage_callouts.gd
# Гараж — 3D-сцена во весь экран с выносками-инфографикой:
#   * у каждой машины реестра пять выносок, точки стоят на своих частях
#     (мотор — на капоте спереди, подвеска — над передним колесом, шины —
#     у заднего колеса, привод — у заднего моста), карточки не наезжают
#     друг на друга и не вылезают за экран;
#   * цифры на карточках берутся из пресета и меняются вместе с ним;
#   * нажатие на карточку открывает панель настроек этой части, камера
#     подъезжает, остальные выноски прячутся; Esc закрывает панель, не уходя
#     из гаража.
extends SceneTree

const GameScript = preload("res://scripts/game_state.gd")
const GarageScene = preload("res://scenes/garage_menu.tscn")
const Config = preload("res://data/rally_game_config.tres")

var failures: Array[String] = []


func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: " + message)
	else:
		failures.append(message)
		printerr("FAIL: " + message)


func _initialize() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var game = GameScript.new()
	game.config = Config
	game.conditions_path = "user://garage_callouts_conditions.cfg"
	game.records_path = "user://garage_callouts_records.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.conditions_path))
	root.add_child(game)
	var garage = GarageScene.instantiate()
	root.add_child(garage)
	garage.open(Config, 0, game)
	await _frames(20)

	var callouts: GarageCallouts = garage.get_node("%Callouts")
	check(callouts != null, "слой выносок на месте")
	check(garage.get_node("%Preview").get_rect().size.x >= 1900.0, "3D-гараж занимает весь экран")
	for id in Config.vehicle_ids():
		garage.select_vehicle(id)
		await _frames(30)
		_check_vehicle(garage, callouts, id)

	garage.select_vehicle("mitsubishi")
	await _frames(10)
	check(
		callouts.card_text("engine").contains("Н·м"),
		"на карточке мотора момент: " + callouts.card_text("engine")
	)
	garage._create_copy()
	garage._on_slider_changed(650.0, "max_torque")
	await _frames(2)
	check(
		callouts.card_text("engine").contains("650"), "карточка мотора меняется вместе с пресетом"
	)

	# Нажатие на карточку подвески открывает её панель.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var start_distance: float = garage._cam_dist
	callouts.card("suspension").gui_input.emit(click)
	await _frames(90)
	var panel: Control = garage.get_node("%DetailPanel")
	check(
		panel.visible and garage._active_group == "suspension",
		"карточка открывает панель своей части"
	)
	check(garage._tabs.current_tab == 3, "в панели — настройки подвески")
	check(not callouts.card("engine").visible, "остальные выноски прячутся")
	check(
		garage._cam_dist < start_distance * (1.0 + garage.focus_distance) * 0.5,
		"камера подъезжает к части (%.2f → %.2f)" % [start_distance, garage._cam_dist]
	)
	check(callouts.anchor_points().has("suspension"), "линия к открытой части видна")

	var backs := [0]
	garage.back_requested.connect(func() -> void: backs[0] += 1)
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	garage._unhandled_input(esc)
	await _frames(60)
	check(not panel.visible and backs[0] == 0, "Esc закрывает панель и не уходит из гаража")
	check(callouts.card("engine").visible, "после закрытия выноски возвращаются")
	check(
		garage._cam_dist > start_distance * (1.0 + garage.focus_distance) * 0.5,
		"камера возвращается"
	)
	garage._unhandled_input(esc)
	check(backs[0] == 1, "второй Esc — выход из гаража")

	garage.queue_free()
	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path("user://garage_callouts_conditions.cfg")
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://garage_callouts_records.cfg"))
	if failures.is_empty():
		print("OK: выноски гаража")
		quit(0)
	else:
		printerr("итого провалов: %d" % failures.size())
		quit(1)


func _check_vehicle(garage, callouts: GarageCallouts, id: String) -> void:
	var points := callouts.anchor_points()
	check(points.size() == 5, "%s: пять выносок (%d)" % [id, points.size()])
	var layer := Rect2(Vector2.ZERO, callouts.size)
	for part: String in points:
		check(
			layer.has_point(points[part]),
			"%s: точка «%s» в кадре %s" % [id, part, str(points[part])]
		)
	# Точки — на своих частях: проверяем в координатах модели (перед — +Z).
	var model: Node3D = garage._active_model()
	var data: Dictionary = callouts.anchor_data(model)
	var box: AABB = data["box"]
	var to_local := model.global_transform.affine_inverse()
	var anchors := callouts.part_anchors()
	var engine: Vector3 = to_local * (anchors["engine"] as Vector3)
	var suspension: Vector3 = to_local * (anchors["suspension"] as Vector3)
	var tires: Vector3 = to_local * (anchors["tires"] as Vector3)
	var drive: Vector3 = to_local * (anchors["drivetrain"] as Vector3)
	print(
		(
			"[callouts] %s: мотор %s, подвеска %s, шины %s, привод %s, кузов %s"
			% [id, engine, suspension, tires, drive, box]
		)
	)
	check(engine.z > box.get_center().z + box.size.z * 0.15, "%s: мотор — от передней части" % id)
	check(engine.y > box.position.y + box.size.y * 0.45, "%s: мотор — от капота сверху" % id)
	check(suspension.z > box.get_center().z, "%s: подвеска — у переднего колеса" % id)
	check(
		tires.z < box.get_center().z and drive.z < box.get_center().z,
		"%s: шины и привод — сзади" % id
	)
	# Карточки одной стороны не наезжают друг на друга и не выходят за экран.
	var rects: Array[Rect2] = []
	for part: String in GarageCallouts.PART_ORDER:
		var card := callouts.card(part)
		check(card.visible, "%s: карточка «%s» видна" % [id, part])
		var rect := Rect2(card.position, card.size)
		check(layer.encloses(rect), "%s: карточка «%s» в пределах экрана" % [id, part])
		for other in rects:
			check(
				not rect.grow(-1.0).intersects(other),
				"%s: карточка «%s» не наезжает на соседнюю" % [id, part]
			)
		rects.append(rect)
