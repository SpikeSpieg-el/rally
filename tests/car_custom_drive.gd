# godot --headless --path . --fixed-fps 120 --script res://tests/car_custom_drive.gd
# Физическая проверка тюнингованной машины на плоском гравии.
extends SceneTree

const CarScene = preload("res://scenes/rally_car.tscn")
const Setup = preload("res://data/setups/engine_stock.tres")


func _initialize() -> void:
	call_deferred("_run")


func _steps(count: int) -> void:
	for i in range(count):
		await physics_frame


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	ground.add_to_group("Dirt")
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(500.0, 1.0, 500.0)
	collision.shape = shape
	collision.position.y = -0.5
	ground.add_child(collision)
	world.add_child(ground)

	var tuned := Setup.duplicate(true) as RallyCarSetup
	tuned.max_torque = 650.0
	tuned.tire_radius = 0.48
	tuned.tire_width = 280.0
	tuned.front_spring_length = 0.34
	tuned.rear_spring_length = 0.32
	tuned.grip_scale = 1.2
	tuned.brake_force_multiplier = 1.3
	tuned.front_brake_bias = 0.58
	var car = CarScene.instantiate()
	car.setup_override = tuned
	car.mouse_look_enabled = false
	car.position.y = 0.3
	world.add_child(car)
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
	var speed_after: float = car.speed_kmh
	var ok: bool = contacts >= 3 and distance > 3.0 and speed_before > 8.0 and speed_after < speed_before and car.linear_velocity.is_finite()
	print("Тюнингованный заезд: контактов %d, разгон %.1f м / %.1f км/ч, после торможения %.1f км/ч" % [contacts, distance, speed_before, speed_after])
	world.queue_free()
	await process_frame
	if ok:
		print("PASS: тюнингованная машина разгоняется и тормозит")
		quit(0)
	else:
		printerr("FAIL: физика тюнингованной машины")
		quit(1)
