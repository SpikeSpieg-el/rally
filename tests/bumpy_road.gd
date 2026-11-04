# godot --headless --path . --fixed-fps 120 --script res://tests/bumpy_road.gd
extends SceneTree

const CarScene = preload("res://scenes/rally_car.tscn")
const Setup = preload("res://data/setups/11_gravel.tres")
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

# Синтетическая стиральная доска — стресс-тест подвески, не профиль трасс.
func height(z: float) -> float:
	return 0.05 * sin((z - 12.0) * TAU / 9.0) * smoothstep(10.0, 14.0, z)

func road() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.add_to_group("Dirt")
	var faces := PackedVector3Array()
	for i in range(500):
		var z: float = -20.0 + i * 0.5
		var next: float = z + 0.5
		var a := Vector3(-20.0, height(z), z)
		var b := Vector3(20.0, height(z), z)
		var c := Vector3(-20.0, height(next), next)
		var d := Vector3(20.0, height(next), next)
		faces.append_array(PackedVector3Array([a, c, b, b, c, d]))
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	return body

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(road())
	var car = CarScene.instantiate()
	car.setup_override = Setup
	car.mouse_look_enabled = false
	car.position.y = 0.3
	world.add_child(car)
	for i in range(240):
		await physics_frame
	check(car.get_wheel_contact_count() >= 3, "машина должна устойчиво стоять на колёсах")
	var hull := car.get_node_or_null("BodyCollider") as CollisionShape3D
	check(hull != null and hull.shape is ConvexPolygonShape3D, "кузов должен иметь единую скошенную коллизию")
	car.sleeping = false
	car.linear_velocity = Vector3(0.0, 0.0, 30.0)
	var peak_height := 0.0
	var peak_up_speed := 0.0
	var peak_force_ratio := 0.0
	for i in range(300):
		await physics_frame
		peak_height = maxf(peak_height, car.global_position.y - height(car.global_position.z))
		peak_up_speed = maxf(peak_up_speed, car.linear_velocity.y)
		for wheel in car.wheel_array:
			var static_load: float = wheel.mass_over_wheel * maxf(car.current_gravity.length(), 1.0)
			peak_force_ratio = maxf(peak_force_ratio, wheel.spring_force / maxf(static_load, 1.0))
	check(car.global_position.z > 25.0, "машина должна проехать неровности")
	check(peak_force_ratio <= car.max_suspension_load_g + 0.01, "импульс подвески должен быть ограничен")
	check(peak_height < 1.2 and peak_up_speed < 6.0, "небольшие неровности не должны катапультировать машину")
	print("Неровности: пройдено %.1f м, высота %.2f м, скорость вверх %.2f м/с, нагрузка %.2f g" % [car.global_position.z, peak_height, peak_up_speed, peak_force_ratio])
	# В воздухе сила не должна искусственно обрезать скорость или прижимать
	# машину: реальные прыжки с трамплинов остаются возможными.
	car.spawn_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 15.0, 0.0))
	car.reset_to_spawn()
	car.linear_velocity = Vector3(0.0, 4.0, 0.0)
	car.angular_velocity = Vector3.ZERO
	await physics_frame
	await physics_frame
	check(car.linear_velocity.y > 3.0, "прыжки в воздухе должны оставаться возможными")
	# Жёсткое приземление должно реально доходить до ограничителя.
	car.spawn_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 5.0, 5.0))
	car.reset_to_spawn()
	var drop_peak := 0.0
	var landed := false
	for i in range(240):
		await physics_frame
		landed = landed or car.get_wheel_contact_count() > 0
		for wheel in car.wheel_array:
			var load: float = wheel.mass_over_wheel * maxf(car.current_gravity.length(), 1.0)
			drop_peak = maxf(drop_peak, wheel.spring_force / maxf(load, 1.0))
	check(landed and drop_peak > 2.0 and drop_peak <= car.max_suspension_load_g + 0.01, "удар при приземлении должен ограничиваться (%.2f g)" % drop_peak)
	# После замены формы кузов по-прежнему должен сталкиваться с препятствиями.
	var wall := StaticBody3D.new()
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(30.0, 5.0, 1.0)
	var wall_collision := CollisionShape3D.new()
	wall_collision.shape = wall_shape
	wall_collision.position = Vector3(0.0, 2.5, 18.0)
	wall.add_child(wall_collision)
	world.add_child(wall)
	car.spawn_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, 0.0))
	car.reset_to_spawn()
	car.linear_velocity = Vector3(0.0, 0.0, 20.0)
	car.angular_velocity = Vector3.ZERO
	for i in range(240):
		await physics_frame
	check(car.global_position.z < 18.0, "кузов должен останавливаться о стену")
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
