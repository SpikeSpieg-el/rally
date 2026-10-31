# godot --headless --path . --fixed-fps 120 --script res://tests/custom_stage_smoke.gd
# Полный этап: сохранённый гараж → автозагрузка → сцена → GEVP + PS1-материалы.
extends SceneTree

const GameScript = preload("res://scripts/game_state.gd")
const Config = preload("res://data/rally_game_config.tres")
const StageScene = preload("res://scenes/rally_stage.tscn")

var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var existing := root.get_node_or_null("RallyGame")
	if existing != null:
		root.remove_child(existing)
		existing.queue_free()
	var game = GameScript.new()
	game.name = "RallyGame"
	game.config = Config.duplicate(true)
	game.conditions_path = "user://custom_stage_smoke.cfg"
	game.records_path = "user://custom_stage_records.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.conditions_path))
	root.add_child(game)
	game.select_setup(1)
	var tuned := game.get_custom_setup(1) as RallyCarSetup
	tuned.max_torque = 705.0
	tuned.livery = 1
	tuned.wheel_color = Color(0.6, 0.5, 0.8)
	tuned.tire_radius = 0.51
	tuned.tire_width = 290.0
	tuned.front_brake_bias = 0.57
	tuned.brake_force_multiplier = 1.2
	check(game.save_custom_setup(1, tuned), "сохранение тестового пресета")
	game.load_conditions()
	game.select_setup(1)
	# Такую же отметку выставляет RallyGame.start_race() перед сменой сцены.
	game._race_uses_selected_setup = true

	var stage = StageScene.instantiate()
	root.add_child(stage)
	var deadline := Time.get_ticks_msec() + 240000
	while not stage._stage_live and Time.get_ticks_msec() < deadline:
		await process_frame
	if not stage._stage_live:
		printerr("FAIL: этап не завершил сборку")
		stage.queue_free()
		game.queue_free()
		await process_frame
		quit(1)
		return

	var car = stage.get_node("RallyCar")
	check(car.active_setup != null and car.active_setup.id == "engine_group_a", "этап использует выбранный пресет")
	check(is_equal_approx(car.max_torque, 705.0) and is_equal_approx(car.front_tire_radius, 0.51), "мотор и радиус дошли до физики")
	check(is_equal_approx(car.front_tire_width, 290.0) and is_equal_approx(car.front_axle.brake_bias, 0.57), "ширина и баланс тормозов дошли до колёс")
	check(is_equal_approx(car.brake_force_multiplier, 1.2) and car.wheel_array.size() == 4, "тормоза и колёса инициализированы корректно")
	var body := car.get_node("low poly lance evo/Mitsubishi_Body") as MeshInstance3D
	var material := body.material_override as StandardMaterial3D
	check(material.albedo_texture.resource_path.ends_with("иташа.jpg"), "ливрея сохранена после оформления этапа")
	check(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS, "PS1-фильтрация сохранена")
	var wheel := car.get_node("Wheel_FL/WheelVisual/Mitsubishi_Wheel_Ft_L") as MeshInstance3D
	check((wheel.material_override as StandardMaterial3D).albedo_color.is_equal_approx(tuned.wheel_color), "тон колеса сохранён после оформления этапа")
	check(not car.freeze and stage.setup == car.active_setup, "этап запущен с выбранной машиной")

	stage.queue_free()
	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://custom_stage_smoke.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://custom_stage_records.cfg"))
	if failures.is_empty():
		print("PASS: сохранённая настройка и ливрея на полном этапе")
		quit(0)
	else:
		printerr("FAIL: настройки полного этапа: %d проблем(ы)" % failures.size())
		quit(1)
