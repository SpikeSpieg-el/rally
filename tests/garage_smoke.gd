# godot --headless --path . --script res://tests/garage_smoke.gd
extends SceneTree

const GameScript = preload("res://scripts/game_state.gd")
const GarageScene = preload("res://scenes/garage_menu.tscn")
const Config = preload("res://data/rally_game_config.tres")
const CarScene = preload("res://scenes/rally_car.tscn")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game = GameScript.new()
	game.config = Config
	game.conditions_path = "user://garage_smoke_conditions.cfg"
	game.records_path = "user://garage_smoke_records.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.conditions_path))
	root.add_child(game)
	var original = Config.get_setup(0)
	var original_torque: float = original.max_torque
	var garage = GarageScene.instantiate()
	root.add_child(garage)
	garage.open(Config, 0, game)
	var ok: bool = garage.setup != original and garage._model != null and garage._wheels.size() == 4
	# Видимые узлы хранятся в сцене, а не создаются в _ready.
	ok = ok and garage.get_node_or_null("%Turntable") != null
	ok = ok and garage.get_node_or_null("%TorqueSlider") is HSlider
	ok = ok and garage.get_node_or_null("Margin/Layout/Body/ShowroomColumn/Preview/Viewport/Showroom/Camera") is Camera3D
	ok = ok and garage.get_node_or_null("Margin/Layout/Body/ShowroomColumn/Preview/Viewport/Showroom/Platform") is MeshInstance3D
	garage._on_slider_changed(560.0, "max_torque")
	garage._on_slider_changed(0.48, "tire_radius")
	garage._on_color_changed(Color(0.3, 0.6, 0.8))
	ok = ok and is_equal_approx(original.max_torque, original_torque)
	ok = ok and is_equal_approx(garage._wheel_visuals[0].basis.get_scale().x, 0.48 / 0.438)
	game.select_setup(0)
	game.save_custom_setup(0, garage.setup)
	game.load_conditions()
	game.select_setup(0)
	var restored = game.current_setup
	ok = ok and is_equal_approx(restored.max_torque, 560.0) and is_equal_approx(restored.tire_radius, 0.48)
	ok = ok and restored.body_color.is_equal_approx(Color(0.3, 0.6, 0.8))
	var car = CarScene.instantiate()
	car.freeze = true
	root.add_child(car)
	car.apply_setup(restored)
	ok = ok and is_equal_approx(car.max_torque, 560.0) and is_equal_approx(car.front_tire_radius, 0.48)
	garage._select_setup(1)
	garage._select_setup(0)
	ok = ok and is_equal_approx(garage.setup.max_torque, 560.0)
	garage._reset_setup()
	ok = ok and is_equal_approx(garage.setup.max_torque, original_torque)
	car.queue_free()
	garage.queue_free()
	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://garage_smoke_conditions.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://garage_smoke_records.cfg"))
	if ok:
		print("PASS: гараж, превью, сохранение и настройки машины")
		quit(0)
	else:
		printerr("FAIL: гараж, превью или настройки машины")
		quit(1)
