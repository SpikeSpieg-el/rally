# Небольшой воспроизводимый тест управления на плоском гравии.
# godot --headless --path . --fixed-fps 120 --script res://tests/handling_benchmark.gd
extends SceneTree

const CarScene = preload("res://scenes/rally_car.tscn")
const Setup = preload("res://data/setups/11_gravel.tres")
const Track = preload("res://data/tracks/stage_forest.tres")


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
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1000.0, 1.0, 1000.0)
	shape_node.shape = shape
	shape_node.position.y = -0.5
	ground.add_child(shape_node)
	world.add_child(ground)
	var car = CarScene.instantiate()
	car.setup_override = Setup
	car.mouse_look_enabled = false
	car.position.y = 0.3
	world.add_child(car)
	car.spawn_transform = Transform3D(Basis.IDENTITY, car.position)
	car.apply_track_grip(Track.grip_scale, Track.rolling_resistance_scale)
	await _steps(240)
	Input.action_press("throttle")
	var elapsed := 0
	while car.speed_kmh < 45.0 and elapsed < 1800:
		await physics_frame
		elapsed += 1
	Input.action_release("throttle")
	var speed_at_turn: float = car.speed_kmh
	var initial_forward: Vector3 = car.global_basis.z
	var peak_sideslip := 0.0
	var slip_sum := 0.0
	Input.action_press("steer_left")
	for i in range(180):
		await physics_frame
		var local_velocity: Vector3 = car.global_basis.inverse() * car.linear_velocity
		if local_velocity.length() > 2.0:
			peak_sideslip = maxf(peak_sideslip, absf(atan2(local_velocity.x, local_velocity.z)))
		slip_sum += car.get_average_tire_slip()
	Input.action_release("steer_left")
	var heading := rad_to_deg(initial_forward.angle_to(car.global_basis.z))
	print("Разгон до %.1f км/ч: %.2f с; поворот: курс %.1f°, макс. снос %.1f°, среднее проскальзывание %.2f; скорость %.1f км/ч" % [
		speed_at_turn, elapsed / 120.0, heading, rad_to_deg(peak_sideslip), slip_sum / 180.0, car.speed_kmh,
	])
	world.queue_free()
	await process_frame
	quit(0)
