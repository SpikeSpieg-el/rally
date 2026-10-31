# godot --headless --path . --script res://tests/car_customization.gd
extends SceneTree

const GameScript = preload("res://scripts/game_state.gd")
const GarageScene = preload("res://scenes/garage_menu.tscn")
const CarScene = preload("res://scenes/rally_car.tscn")
const Config = preload("res://data/rally_game_config.tres")
const Schema = preload("res://scripts/car_customization.gd")
const Ps1Materials = preload("res://scripts/ps1_materials.gd")

var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var config := Config.duplicate(true) as RallyGameConfig
	config.car_setups = Config.car_setups.duplicate()
	for i in range(config.car_setups.size()):
		config.car_setups[i] = Config.car_setups[i].duplicate(true)
	var base := config.get_setup(0) as RallyCarSetup
	var original_torque := base.max_torque
	var game = GameScript.new()
	game.config = config
	game.conditions_path = "user://car_customization_test.cfg"
	game.records_path = "user://car_customization_records.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.conditions_path))
	root.add_child(game)

	# Старые файлы содержали только шесть ключей; новые берутся из пресета.
	var section := "garage_" + base.id
	game._conditions.set_value(section, "body_color", Color(0.2, 0.4, 0.8, 0.3))
	game._conditions.set_value(section, "max_torque", 560.0)
	game._conditions.set_value(section, "final_drive", 4.6)
	game._conditions.set_value(section, "front_spring_length", 0.28)
	game._conditions.set_value(section, "rear_spring_length", 0.33)
	game._conditions.set_value(section, "tire_radius", 0.47)
	var legacy := game.get_custom_setup(0) as RallyCarSetup
	check(legacy != base and is_equal_approx(legacy.max_torque, 560.0), "старый момент загружен в независимую копию")
	check(legacy.body_color.is_equal_approx(Color(0.2, 0.4, 0.8, 1.0)), "старый цвет непрозрачен")
	check(is_equal_approx(legacy.front_spring_length, 0.28) and is_equal_approx(legacy.rear_spring_length, 0.33), "старые настройки подвески загружены")
	check(legacy.livery == base.livery and is_equal_approx(legacy.brake_force_multiplier, 1.0), "новые поля старого сохранения получают значения пресета")

	# Повреждённые значения не должны приводить к ошибкам или нарушать физику.
	game._conditions.set_value(section, "max_torque", "wrong")
	game._conditions.set_value(section, "drivetrain", 999)
	game._conditions.set_value(section, "wheel_color", "not a color")
	game._conditions.set_value(section, "headlight_energy", 10000.0)
	game._conditions.set_value(section, "turbo", "not a bool")
	game._conditions.set_value(section, "gear_ratios", [1.0, 2.0, 3.0, 4.0, 5.0, 6.0])
	var invalid := game.get_custom_setup(0) as RallyCarSetup
	check(is_equal_approx(invalid.max_torque, base.max_torque), "нечисловой момент заменён значением пресета")
	check(invalid.drivetrain == RallyCarSetup.Drivetrain.FWD, "enum ограничен допустимым диапазоном")
	check(invalid.wheel_color == base.wheel_color and invalid.turbo == base.turbo, "неверные типы цвета и флага отклонены")
	check(is_equal_approx(invalid.headlight_energy, 12.0), "яркость ограничена диапазоном")
	check(invalid.gear_ratios == base.gear_ratios, "повреждённый ряд передач отклонён целиком")
	check(Schema.valid_gears([3.0, 2.0, 2.0, 1.2, 1.0, 0.8], base.gear_ratios) == base.gear_ratios, "равные передаточные числа отклонены")
	check(Schema.valid_gears([3.0, 2.0, 1.995, 1.2, 1.0, 0.8], base.gear_ratios) == base.gear_ratios, "ряд со слишком малым зазором отклонён")
	check(not game.save_custom_setups({-1: invalid}) and not game.save_custom_setups({999: invalid}), "недопустимый номер пресета не записывается")

	# Начинаем работу в чистом гараже.
	game._conditions.erase_section(section)
	var garage = GarageScene.instantiate()
	root.add_child(garage)
	garage.open(config, 0, game)
	check(garage._tabs.get_tab_count() == 5 and garage._controls.size() == Schema.FIELDS.size(), "все категории и элементы схемы созданы")
	check(garage.get_node_or_null("%TorqueSlider") is HSlider, "доступ к ползунку момента сохранён")
	check((garage._controls["awd_front_torque"] as HSlider).editable, "распределение AWD доступно на полном приводе")

	garage._on_choice_changed(1, "livery")
	garage._on_choice_changed(2, "paint_finish")
	var body_for_finish := garage._model.get_node("Mitsubishi_Body") as MeshInstance3D
	check(is_equal_approx((body_for_finish.material_override as StandardMaterial3D).roughness, 0.9), "матовое покрытие меняет материал")
	garage._on_choice_changed(0, "paint_finish")
	check(is_equal_approx((body_for_finish.material_override as StandardMaterial3D).roughness, 1.0), "заводское покрытие возвращает исходный материал")
	garage._on_choice_changed(3, "paint_finish")
	garage._on_custom_color_changed(Color(0.6, 0.7, 0.8), "body_color")
	garage._on_custom_color_changed(Color(0.7, 0.4, 0.3), "wheel_color")
	garage._on_custom_color_changed(Color(0.4, 0.7, 1.0), "headlight_color")
	garage._on_slider_changed(5.5, "headlight_energy")
	garage._on_slider_changed(650.0, "max_torque")
	garage._on_slider_changed(8400.0, "max_rpm")
	garage._on_choice_changed(RallyCarSetup.TorqueShape.HIGH_REV, "torque_shape")
	garage._on_toggle_changed(false, "turbo")
	garage._on_slider_changed(4.8, "final_drive")
	garage._on_slider_changed(3.8, "gear_1")
	garage._on_slider_changed(2.7, "gear_2")
	garage._on_slider_changed(4.0, "gear_3") # Ограничено второй передачей.
	check(garage.setup.gear_ratios[2] < garage.setup.gear_ratios[1], "UI не позволяет нарушить порядок передач")
	garage._on_choice_changed(RallyCarSetup.Drivetrain.RWD, "drivetrain")
	check(not (garage._controls["awd_front_torque"] as HSlider).editable, "баланс AWD отключён для RWD")
	garage._on_choice_changed(RallyCarSetup.Drivetrain.AWD, "drivetrain")
	garage._on_slider_changed(0.48, "awd_front_torque")
	garage._on_slider_changed(0.0, "traction_control_max_slip")
	garage._on_slider_changed(1320.0, "vehicle_mass")
	garage._on_slider_changed(0.35, "front_spring_length")
	garage._on_slider_changed(0.29, "rear_spring_length")
	garage._on_slider_changed(0.62, "front_damping_ratio")
	garage._on_slider_changed(0.52, "tire_radius")
	garage._on_slider_changed(300.0, "tire_width")
	garage._on_slider_changed(1.4, "grip_scale")
	garage._on_slider_changed(1.3, "brake_force_multiplier")
	garage._on_slider_changed(0.58, "front_brake_bias")
	check(is_equal_approx(base.max_torque, original_torque), "редактирование не меняет ресурс пресета")

	var preview_body := garage._model.get_node("Mitsubishi_Body") as MeshInstance3D
	var preview_material := preview_body.material_override as StandardMaterial3D
	var preview_mirror := garage._model.get_node("Mitsubishi_Body_002") as MeshInstance3D
	check(preview_material.albedo_texture.resource_path.ends_with("иташа.jpg"), "ливрея отображается на превью")
	check(preview_material.albedo_color.is_equal_approx(garage.setup.body_color) and is_equal_approx(preview_material.metallic, 0.65), "цвет и покрытие кузова отображаются на превью")
	check(preview_mirror.material_override == null, "несколько поверхностей зеркал не заменяются общей краской")
	var preview_wheel := garage._wheel_visuals[0] as MeshInstance3D
	var wheel_size := preview_wheel.basis.get_scale()
	check(is_equal_approx(wheel_size.x, 300.0 / 245.0) and is_equal_approx(wheel_size.y, 0.52 / 0.438), "ширина и радиус колеса независимо меняют превью")
	check((preview_wheel.material_override as StandardMaterial3D).albedo_color.is_equal_approx(garage.setup.wheel_color), "тон колеса виден на превью")

	# Черновики пресетов изолированы и сохраняются одной операцией.
	garage._select_setup(1)
	garage._on_slider_changed(700.0, "max_torque")
	garage._select_setup(0)
	check(is_equal_approx(garage.setup.max_torque, 650.0), "черновик переживает переключение пресета")
	check(garage._save_drafts(), "сохранение всех черновиков успешно")
	game.load_conditions()
	var restored := game.get_custom_setup(0) as RallyCarSetup
	var restored_other := game.get_custom_setup(1) as RallyCarSetup
	check(restored.livery == 1 and restored.paint_finish == 3 and restored.body_color.is_equal_approx(Color(0.6, 0.7, 0.8)), "ливрея, покрытие и краска переживают загрузку")
	check(restored.wheel_color.is_equal_approx(Color(0.7, 0.4, 0.3)) and restored.headlight_color.is_equal_approx(Color(0.4, 0.7, 1.0)), "колёса и фары переживают загрузку")
	check(is_equal_approx(restored.headlight_energy, 5.5) and not restored.turbo, "яркость и звук турбины переживают загрузку")
	check(is_equal_approx(restored.max_torque, 650.0) and is_equal_approx(restored_other.max_torque, 700.0), "разные пресеты сохраняются независимо")
	check(restored.gear_ratios == garage.setup.gear_ratios and restored.torque_shape == RallyCarSetup.TorqueShape.HIGH_REV, "коробка и кривая переживают загрузку")
	check(is_equal_approx(restored.front_spring_length, 0.35) and is_equal_approx(restored.rear_spring_length, 0.29), "передняя и задняя подвеска сохранены отдельно")
	check(is_equal_approx(restored.front_brake_bias, 0.58) and is_equal_approx(restored.brake_force_multiplier, 1.3), "тормоза переживают загрузку")

	# Машина в заезде использует те же материалы и физические значения.
	var car = CarScene.instantiate()
	car.freeze = true
	car.setup_override = restored
	root.add_child(car)
	check(is_equal_approx(car.max_torque, 650.0) and is_equal_approx(car.max_rpm, 8400.0), "мотор применён в машине")
	check(car.gear_ratios == restored.gear_ratios and is_equal_approx(car.final_drive, 4.8), "передаточные числа применены в машине")
	check(is_equal_approx(car.torque_curve.sample_baked(0.25), restored.build_torque_curve().sample_baked(0.25)), "форма кривой реально меняет момент")
	check(car.drivetrain_mode == RallyCarSetup.Drivetrain.AWD and is_equal_approx(car.front_torque_split, 0.48), "привод применён")
	check(is_equal_approx(car.vehicle_mass, 1320.0) and is_equal_approx(car.front_spring_length, 0.35), "масса и подвеска применены")
	check(is_equal_approx(car.front_tire_width, 300.0) and is_equal_approx(car.front_tire_radius, 0.52), "физические шины применены")
	check(is_equal_approx(car.coefficient_of_friction["Road"], 1.5 * 1.4) and is_zero_approx(car.traction_control_max_slip), "сцепление и отключение антипробуксовки применены")
	check(is_equal_approx(car.front_left_wheel.spring_length, 0.35) and is_equal_approx(car.rear_left_wheel.spring_length, 0.29), "подвеска действительно обновляет колёса")
	check(is_equal_approx(car.front_axle.brake_bias, 0.58) and is_equal_approx(car.brake_force_multiplier, 1.3), "тормозное усилие и баланс применены к осям")
	var race_wheel := car.get_node("Wheel_FL/WheelVisual") as Node3D
	check(is_equal_approx(race_wheel.scale.x, 300.0 / 245.0) and is_equal_approx(race_wheel.scale.y, 0.52 / 0.438), "масштаб колёс в заезде совпадает с превью")
	var race_body := car.get_node("low poly lance evo/Mitsubishi_Body") as MeshInstance3D
	check((race_body.material_override as StandardMaterial3D).albedo_texture == preview_material.albedo_texture, "ливрея в заезде совпадает с превью")
	var lamp := car.get_node("HeadlightL") as SpotLight3D
	check(lamp.light_color.is_equal_approx(restored.headlight_color) and is_equal_approx(lamp.light_energy, 5.5), "фары применены в заезде")

	# Повторное применение после PS1-стилизации не теряет фильтрацию и не
	# дублирует оси / колёса GEVP.
	Ps1Materials.apply_nearest(car)
	car.apply_setup(restored)
	check(car.axles.size() == 2 and car.wheel_array.size() == 4 and car.drive_wheels.size() == 4, "повторное применение не дублирует оси и колёса")
	check((race_body.material_override as StandardMaterial3D).texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS, "повторное применение сохраняет PS1-фильтрацию")
	var strong_brakes: float = car.max_brake_force
	var other_mode := restored.duplicate(true) as RallyCarSetup
	other_mode.brake_force_multiplier = 1.0
	other_mode.drivetrain = RallyCarSetup.Drivetrain.RWD
	car.apply_setup(other_mode)
	check(car.drive_wheels.size() == 2 and not car.front_axle.is_drive_axle and car.rear_axle.is_drive_axle, "RWD действительно оставляет ведущей заднюю ось")
	check(is_equal_approx(strong_brakes, car.max_brake_force * 1.3), "множитель изменяет реальное тормозное усилие")
	other_mode.drivetrain = RallyCarSetup.Drivetrain.FWD
	car.apply_setup(other_mode)
	check(car.drive_wheels.size() == 2 and car.front_axle.is_drive_axle and not car.rear_axle.is_drive_axle, "FWD действительно оставляет ведущей переднюю ось")

	# Сброс применяется только к выбранному черновику, пока явно не сохранён.
	garage._reset_setup()
	check(is_equal_approx(garage.setup.max_torque, original_torque), "сброс восстанавливает исходный пресет")
	check(is_equal_approx((game.get_custom_setup(0) as RallyCarSetup).max_torque, 650.0), "сброс не записывается до сохранения")
	garage.open(config, 0, game)
	check(is_equal_approx(garage.setup.max_torque, 650.0), "повторный вход отменяет несохранённый сброс")
	garage._reset_setup()
	check(garage._save_drafts(), "сброс можно сохранить")
	check(is_equal_approx((game.get_custom_setup(0) as RallyCarSetup).max_torque, original_torque), "сохранённый сброс переживает повторную загрузку")
	check(is_equal_approx((game.get_custom_setup(1) as RallyCarSetup).max_torque, 700.0), "сброс не меняет другой пресет")

	# Кнопка старта сохраняет все черновики перед сигналом, возврат — нет.
	garage._select_setup(1)
	garage._on_slider_changed(730.0, "max_torque")
	garage._select_setup(0)
	garage._on_slider_changed(580.0, "max_torque")
	var started := {"count": 0, "index": -1}
	garage.start_requested.connect(func(index: int, _setup: RallyCarSetup) -> void:
		started["count"] += 1
		started["index"] = index
	)
	garage._start_race()
	check(started["count"] == 1 and started["index"] == 0, "старт отправляет выбранный пресет")
	check(is_equal_approx((game.get_custom_setup(0) as RallyCarSetup).max_torque, 580.0) and is_equal_approx((game.get_custom_setup(1) as RallyCarSetup).max_torque, 730.0), "старт сохраняет все открытые черновики")
	garage._on_slider_changed(640.0, "max_torque")
	garage._request_back()
	garage.open(config, 0, game)
	check(is_equal_approx(garage.setup.max_torque, 580.0), "возврат отменяет изменения после последнего сохранения")

	# Авторская кривая пресета сохраняется, пока игрок не выберет другую.
	var authored := Curve.new()
	authored.add_point(Vector2(0.0, 0.2))
	authored.add_point(Vector2(1.0, 0.9))
	base.torque_curve = authored
	game._conditions.erase_section(section)
	var untouched := game.get_custom_setup(0) as RallyCarSetup
	check(game.save_custom_setup(0, untouched), "сохранение авторской кривой")
	check((game.get_custom_setup(0) as RallyCarSetup).torque_curve != null, "нетронутая авторская кривая переживает загрузку")
	garage.open(config, 0, game)
	garage._on_choice_changed(RallyCarSetup.TorqueShape.ATMO_LINEAR, "torque_shape")
	check(garage.setup.torque_curve == null and garage._save_drafts(), "выбор формы снимает приоритет авторской кривой")
	check((game.get_custom_setup(0) as RallyCarSetup).torque_curve == null, "выбранная форма переживает загрузку")
	garage._on_choice_changed(RallyCarSetup.TorqueShape.CUSTOM, "torque_shape")
	check(garage.setup.torque_curve != null, "базовая форма возвращает авторскую кривую")

	car.queue_free()
	garage.queue_free()
	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://car_customization_test.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://car_customization_records.cfg"))
	if failures.is_empty():
		print("PASS: полный кастом, совместимость, независимые пресеты и применение в заезде")
		quit(0)
	else:
		printerr("FAIL: проверок не пройдено: %d" % failures.size())
		quit(1)
