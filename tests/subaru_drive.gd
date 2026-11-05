# godot --headless --path . --fixed-fps 120 --script res://tests/subaru_drive.gd
# Гараж, сохранение выбора и реальная физика Subaru на ровном грунте.
extends SceneTree

const Game = preload("res://scripts/game_state.gd")
const Garage = preload("res://scenes/garage_menu.tscn")
const Car = preload("res://scenes/rally_car.tscn")
const Config = preload("res://data/rally_game_config.tres")
const Models = preload("res://scripts/car_models.gd")
const Setup = preload("res://data/setups/engine_stock.tres")

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("_run")

func _steps(count: int) -> void:
	for i in range(count):
		await physics_frame

func _run() -> void:
	var old_game := root.get_node_or_null("RallyGame")
	if old_game != null:
		root.remove_child(old_game)
		old_game.queue_free()
	var game := Game.new()
	game.name = "RallyGame"
	game.config = Config.duplicate(true)
	game.conditions_path = "user://subaru_drive_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.conditions_path))
	root.add_child(game)
	var garage = Garage.instantiate()
	root.add_child(garage)
	garage.open(game.config, 0, game)
	var subaru: RallyVehicle = Models.vehicle("subaru")
	check(subaru != null, "в реестре машин есть Subaru")
	garage.select_vehicle("subaru")
	var preview: Node3D = garage._vehicle_models.get("subaru")
	check(game.vehicle_id == "subaru" and preview != null and preview.visible and not garage._model.visible, "Subaru выбирается и показывается в гараже")
	for name in subaru.wheel_names:
		var wheel = preview.find_child(name, true, false)
		check(wheel != null and wheel.visible, "колесо Subaru видно в гараже: " + name)
	game.load_conditions()
	game.vehicle_id = "mitsubishi"
	game._restore_saved_selection()
	check(game.vehicle_id == "subaru", "выбор машины сохраняется между сеансами")
	garage.select_vehicle("mitsubishi")
	check(game.vehicle_id == "mitsubishi" and garage._model.visible and not preview.visible, "можно вернуться к Mitsubishi")
	garage.select_vehicle("subaru")
	game._race_uses_selected_setup = true
	garage.free()

	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	ground.add_to_group("Dirt")
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(500.0, 1.0, 500.0)
	collider.shape = box
	collider.position.y = -0.5
	ground.add_child(collider)
	world.add_child(ground)
	var car = Car.instantiate()
	car.setup_override = Setup.duplicate(true)
	car.mouse_look_enabled = false
	car.position.y = 0.3
	world.add_child(car)
	check(car.get_node_or_null("Sketchfab_Scene") != null and not car.get_node("low poly lance evo").visible, "в заезде используется модель Subaru")
	for i in range(Models.WHEEL_MOUNTS.size()):
		var mount: Node = car.get_node(Models.WHEEL_MOUNTS[i] + "/WheelVisual")
		var wheel = mount.get_node_or_null(subaru.wheel_names[i])
		check(wheel != null and wheel.visible, "колесо прикреплено к симуляции подвески")
	await _steps(180)
	var contacts: int = car.get_wheel_contact_count()
	var start: Vector3 = car.global_position
	Input.action_press("throttle")
	await _steps(360)
	Input.action_release("throttle")
	var distance: float = car.global_position.z - start.z
	var speed_before: float = car.speed_kmh
	Input.action_press("brake")
	await _steps(240)
	Input.action_release("brake")
	check(contacts >= 3 and distance > 3.0 and speed_before > 8.0 and car.speed_kmh < speed_before, "Subaru разгоняется и тормозит")
	world.free()
	game._race_uses_selected_setup = false
	var direct = Car.instantiate()
	direct.mouse_look_enabled = false
	root.add_child(direct)
	check(direct.get_node("low poly lance evo").visible and direct.get_node_or_null("Sketchfab_Scene") == null, "прямой запуск не подменяет сценическую машину")
	direct.free()
	game.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://subaru_drive_test.cfg"))
	print("Subaru: %d failures; distance %.1f m, speed %.1f km/h" % [failures, distance, speed_before])
	quit(0 if failures == 0 else 1)
