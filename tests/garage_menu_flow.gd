# godot --headless --path . --script res://tests/garage_menu_flow.gd
# Главное меню → гараж → RallyGame → автомобиль заезда, без смены сцены.
extends SceneTree

const MainScene = preload("res://scenes/main_menu.tscn")
const StageScene = preload("res://scenes/rally_stage.tscn")
const Config = preload("res://data/rally_game_config.tres")

# Настоящая сцена и порядок _enter_tree/_ready, но без тяжёлой сборки дороги.
class MinimalStage:
	extends "res://scripts/rally_stage.gd"
	func _ready() -> void:
		pass


class TestGame:
	extends "res://scripts/game_state.gd"
	var starts := 0
	var fail_writes := false

	func save_custom_setups(setups: Dictionary) -> bool:
		if fail_writes:
			return false
		return super.save_custom_setups(setups)

	func start_race() -> void:
		starts += 1
		await super.start_race()

	func _change_scene(_scene_path: String) -> void:
		# Сцену меняем вручную ниже, чтобы проверить исходный stage без загрузки.
		pass


var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Автозагрузка проекта может уже существовать даже при запуске --script.
	# Подменяем её тестовой, чтобы не трогать реальные сохранения.
	var existing := root.get_node_or_null("RallyGame")
	if existing != null:
		root.remove_child(existing)
		existing.queue_free()
	var game := TestGame.new()
	game.name = "RallyGame"
	game.config = Config.duplicate(true)
	game.conditions_path = "user://garage_menu_flow.cfg"
	game.records_path = "user://garage_menu_flow_records.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.conditions_path))
	root.add_child(game)
	var menu = MainScene.instantiate()
	root.add_child(menu)

	# Вход в гараж и возврат без записи черновика.
	menu._on_start_pressed()
	check(menu.garage != null and menu.garage.visible, "главное меню открывает гараж")
	var original := (game.get_custom_setup(0) as RallyCarSetup).max_torque
	menu.garage._on_slider_changed(555.0, "max_torque")
	menu.garage._request_back()
	check(not menu.garage.visible and menu.get_node("Content").visible, "возврат показывает меню трассы")
	menu._on_start_pressed()
	check(is_equal_approx(menu.garage.setup.max_torque, original), "возврат без сохранения отменяет черновик")

	# Явное сохранение выбирает нужный пресет и обновляет состояние меню.
	menu.garage._select_setup(2)
	menu.garage._on_slider_changed(680.0, "max_torque")
	menu.garage._on_choice_changed(2, "livery")
	menu.garage._on_slider_changed(0.55, "front_brake_bias")
	menu.garage._save_button_pressed()
	check(menu.selected_setup == 2 and game.setup_index == 2, "сохранённый пресет выбран в меню и RallyGame")
	check(is_equal_approx((game.current_setup as RallyCarSetup).max_torque, 680.0), "текущая настройка обновлена без старта")
	menu.garage._request_back()
	menu._on_start_pressed()
	check(menu.garage.selected_index == 2 and menu.garage.setup.livery == 2, "повторный вход восстанавливает выбранный пресет")

	# При ошибке сохранения старт блокируется, текущая конфигурация не портится.
	game.fail_writes = true
	menu.garage._on_slider_changed(705.0, "max_torque")
	menu.garage._start_race()
	check(game.starts == 0 and menu.garage.visible, "ошибка записи не запускает заезд")
	check(is_equal_approx((game.current_setup as RallyCarSetup).max_torque, 680.0), "ошибка записи не меняет текущий сетап")
	game.fail_writes = false
	menu.garage._on_slider_changed(0.51, "tire_radius")
	menu.garage._start_race()
	check(game.starts == 1 and game.setup_index == 2, "старт запускается после успешного сохранения")
	check(is_equal_approx((game.current_setup as RallyCarSetup).max_torque, 705.0), "гараж передаёт новые настройки в RallyGame")

	# В реальной сцене этапа у машины назначен старый setup_override. Заезд
	# из меню должен заменить его ДО того, как у дочерней машины вызовется _ready.
	var stage = StageScene.instantiate()
	stage.set_script(MinimalStage)
	var car = stage.get_node("RallyCar")
	check(car.setup_override != null and car.setup_override.id == "gravel", "сценический тест содержит исходный override")
	car.freeze = true
	root.add_child(stage)
	check(car.active_setup != null and is_equal_approx(car.max_torque, 705.0), "реальный этап получает момент выбранного пресета")
	check(is_equal_approx(car.front_tire_radius, 0.51) and is_equal_approx(car.front_axle.brake_bias, 0.55), "шины и тормоза доходят до физики этапа")
	var body := car.get_node("low poly lance evo/Mitsubishi_Body") as MeshInstance3D
	check((body.material_override as StandardMaterial3D).albedo_texture.resource_path.ends_with("иташа3.jpg"), "выбранная ливрея доходит до машины этапа")
	stage.queue_free()

	# Прямой F6 по-прежнему использует override, заданный в сцене.
	game._race_uses_selected_setup = false
	var direct_stage = StageScene.instantiate()
	direct_stage.set_script(MinimalStage)
	var direct_car = direct_stage.get_node("RallyCar")
	direct_car.freeze = true
	root.add_child(direct_stage)
	check(direct_car.active_setup != null and direct_car.active_setup.id == "gravel", "прямой F6 сохраняет сценический override")
	direct_stage.queue_free()

	# Явный override корня этапа имеет приоритет над выбранной машиной.
	game._race_uses_selected_setup = true
	var authored_stage = StageScene.instantiate()
	authored_stage.set_script(MinimalStage)
	authored_stage.car_setup_override = Config.get_setup(1)
	var authored_car = authored_stage.get_node("RallyCar")
	authored_car.freeze = true
	root.add_child(authored_stage)
	check(authored_car.active_setup != null and authored_car.active_setup.id == "engine_group_a", "настройка root car_setup_override приоритетна")
	authored_stage.queue_free()
	menu.queue_free()
	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://garage_menu_flow.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://garage_menu_flow_records.cfg"))
	if failures.is_empty():
		print("PASS: меню → гараж → сохранение → машина заезда и ошибка записи")
		quit(0)
	else:
		printerr("FAIL: переход меню/гаража: %d проблем(ы)" % failures.size())
		quit(1)
