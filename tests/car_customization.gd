# godot --headless --path . --script res://tests/car_customization.gd
extends SceneTree

const GameScript = preload("res://scripts/game_state.gd")
const GarageScene = preload("res://scenes/garage_menu.tscn")
const CarScene = preload("res://scenes/rally_car.tscn")
const Config = preload("res://data/rally_game_config.tres")
const Schema = preload("res://scripts/car_customization.gd")

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var config := Config.duplicate(true) as RallyGameConfig
	var path := "user://car_customization_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var game = GameScript.new()
	game.config = config
	game.conditions_path = path
	game.records_path = "user://car_customization_records.cfg"
	root.add_child(game)
	check(config.setup_count() == 10, "десять готовых пресетов")
	var names := {}
	for i in range(config.setup_count()):
		var preset := config.get_setup(i) as RallyCarSetup
		check(preset != null and not preset.engine_name.is_empty(), "каждый пресет содержит двигатель")
		if preset != null:
			names[preset.engine_name] = true
	check(names.size() == 10, "двигатели различаются")

	var base := config.get_setup(0) as RallyCarSetup
	var original := base.max_torque
	var garage = GarageScene.instantiate()
	root.add_child(garage)
	garage.open(config, 0, game)
	check(garage._tabs.get_tab_count() == 5 and garage._controls.size() == Schema.FIELDS.size(), "все характеристики доступны")
	check(not garage._editing and not garage._controls["max_torque"].visible, "готовый пресет только для просмотра")
	garage._on_slider_changed(700.0, "max_torque")
	check(is_equal_approx(garage.setup.max_torque, original), "готовый пресет нельзя изменить")
	garage._create_copy()
	garage._name_input.text = "Мой гравий"
	garage._on_slider_changed(650.0, "max_torque")
	garage._on_slider_changed(0.52, "tire_radius")
	garage._on_slider_changed(0.35, "front_spring_length")
	garage._on_slider_changed(0.58, "front_brake_bias")
	garage._on_slider_changed(2.7, "gear_2")
	garage._on_slider_changed(4.0, "gear_3")
	check(garage.setup.gear_ratios[2] < garage.setup.gear_ratios[1], "редактор ограничивает порядок передач")
	garage._on_choice_changed(1, "livery")
	garage._on_choice_changed(RallyCarSetup.Transmission.MANUAL_CLUTCH, "transmission_mode")
	garage._on_custom_color_changed(Color(0.6, 0.7, 0.8), "body_color")
	check(garage._save_drafts(), "сохранение копии")
	var first: int = garage.selected_index
	check(first == 10 and game.setup_count() == 11, "копия добавлена отдельным пунктом")
	check(is_equal_approx(base.max_torque, original) and is_equal_approx((game.get_custom_setup(0) as RallyCarSetup).max_torque, original), "оригинал не изменён")
	garage._create_copy()
	garage._name_input.text = "Мой второй"
	garage._on_slider_changed(700.0, "max_torque")
	check(garage._save_drafts(), "копия пользовательского пресета сохраняется отдельно")
	var second: int = garage.selected_index
	check(second == 11 and is_equal_approx((game.get_custom_setup(first) as RallyCarSetup).max_torque, 650.0), "копия не меняет свой источник")
	game.select_setup(first)
	game.load_conditions()
	var restored := game.get_custom_setup(first) as RallyCarSetup
	check(restored.display_name == "Мой гравий" and restored.livery == 1, "название и ливрея переживают загрузку")
	check(restored.body_color.is_equal_approx(Color(0.6, 0.7, 0.8)) and is_equal_approx(restored.tire_radius, 0.52), "настройки переживают загрузку")
	check(restored.transmission_mode == RallyCarSetup.Transmission.MANUAL_CLUTCH, "коробка сохранена")
	check(is_equal_approx(restored.front_spring_length, 0.35) and is_equal_approx(restored.front_brake_bias, 0.58), "подвеска и тормоза сохранены")
	check(Schema.valid_gears([1.0, 2.0], base.gear_ratios) == base.gear_ratios, "повреждённые передачи отклоняются")
	game._restore_saved_selection()
	check(game.setup_index == first and is_equal_approx((game.current_setup as RallyCarSetup).max_torque, 650.0), "выбранный пользовательский пресет восстанавливается")
	check(is_equal_approx((game.get_custom_setup(second) as RallyCarSetup).max_torque, 700.0), "несколько своих пресетов хранятся независимо")
	garage.open(config, first, game)
	garage._on_slider_changed(600.0, "max_torque")
	garage._reset_setup()
	check(is_equal_approx(garage.setup.max_torque, 650.0), "отмена возвращает сохранённую версию")
	garage._on_slider_changed(675.0, "max_torque")
	check(garage._save_drafts(), "редактирование своего пресета сохраняется")
	check(game.setup_count() == 12 and is_equal_approx((game.get_custom_setup(first) as RallyCarSetup).max_torque, 675.0), "редактирование не создаёт лишнюю запись")

	var car = CarScene.instantiate()
	car.freeze = true
	car.setup_override = game.get_custom_setup(first)
	root.add_child(car)
	check(is_equal_approx(car.max_torque, 675.0) and is_equal_approx(car.front_tire_radius, 0.52), "свой пресет применяется к физике автомобиля")
	check(car.manual_clutch_control, "выбранная коробка применяется к автомобилю")

	# Старые настройки переносятся в отдельный пользовательский пресет.
	var legacy := ConfigFile.new()
	legacy.set_value("garage_" + base.id, "max_torque", 560.0)
	legacy.set_value("garage_" + base.id, "body_color", Color(0.2, 0.4, 0.8, 0.3))
	legacy.set_value("selection", "setup_index", 0)
	legacy.save(path)
	game.load_conditions()
	game._restore_saved_selection()
	check(game.setup_count() == 11 and game.setup_index == 10, "старый выбор перенесён в отдельный пресет")
	var migrated := game.get_custom_setup(10) as RallyCarSetup
	check(is_equal_approx(migrated.max_torque, 560.0) and migrated.body_color.is_equal_approx(Color(0.2, 0.4, 0.8, 1.0)), "старые значения перенесены и проверены")
	check(is_equal_approx((game.get_custom_setup(0) as RallyCarSetup).max_torque, original), "миграция не меняет готовый пресет")
	game.load_conditions()
	check(game.setup_count() == 11, "миграция не создаёт дубликаты")

	var previous_path: String = game.conditions_path
	game.conditions_path = "user://missing_directory/cannot_save.cfg"
	check(game.save_user_setup(0, migrated, "Ошибка", true) == -1 and game.setup_count() == 11, "ошибка записи не меняет список")
	game.conditions_path = previous_path
	car.queue_free()
	garage.queue_free()
	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://car_customization_records.cfg"))
	if failures.is_empty():
		print("PASS: готовые и пользовательские пресеты, миграция и физика")
		quit(0)
	else:
		printerr("FAIL: %d проблем(ы)" % failures.size())
		quit(1)
