# godot --headless --path . --fixed-fps 120 --script res://tests/car_obstacle_collision.gd
extends SceneTree

const CARS := [preload("res://scenes/rally_car.tscn"), preload("res://scenes/rally_car2.tscn")]
const SETUP := preload("res://data/setups/11_gravel.tres")
const Placement = preload("res://scripts/data/rally_guardrail_placement.gd")
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)

func make_ground() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.add_to_group("Dirt")
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	var collider := CollisionShape3D.new()
	collider.shape = box
	collider.position.y = -0.5
	body.add_child(collider)
	return body

func make_fence() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	# Две соседние секции с тем же швом и размерами, что у трассы.
	for endpoints in [[Vector3(-20, 0, 10), Vector3(0, 0, 10)], [Vector3(0, 0, 10), Vector3(20, 0, 10)]]:
		var a: Vector3 = endpoints[0]
		var b: Vector3 = endpoints[1]
		var box := BoxShape3D.new()
		box.size = Placement.collision_size(a, b)
		var collider := CollisionShape3D.new()
		collider.shape = box
		collider.transform = Placement.collision_transform(a, b)
		body.add_child(collider)
	return body

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var ground := make_ground()
	world.add_child(ground)
	world.add_child(make_fence())
	# Луч сверху над забором должен находить грунт, а не верх секции.
	var ray := RayCast3D.new()
	ray.position = Vector3(0, 3, 10)
	ray.target_position = Vector3(0, -4, 0)
	world.add_child(ray)
	await physics_frame
	ray.force_raycast_update()
	check(ray.is_colliding() and ray.get_collider() == ground, "колёсный луч проходит сквозь забор к грунту")
	ray.queue_free()
	for scene in CARS:
		var car = scene.instantiate()
		car.setup_override = SETUP
		car.mouse_look_enabled = false
		car.position = Vector3(0, 0.3, 0)
		world.add_child(car)
		for i in range(240):
			await physics_frame
		check(car.continuous_cd and (car.collision_mask & 2) != 0, "CCD и столкновение кузова с препятствиями")
		check(car.get_wheel_contact_count() >= 3, "подвеска стоит на грунте")
		var base_y: float = car.global_position.y
		car.sleeping = false
		car.linear_velocity = Vector3(0, 0, 35)
		car.angular_velocity = Vector3.ZERO
		var max_z := -INF
		var max_y := -INF
		var min_z_velocity := INF
		for i in range(150):
			await physics_frame
			max_z = maxf(max_z, car.global_position.z)
			max_y = maxf(max_y, car.global_position.y)
			min_z_velocity = minf(min_z_velocity, car.linear_velocity.z)
		check(max_z < 10.2, "кузов не проходит сквозь тонкую секцию/стык: %.2f" % max_z)
		check(max_y - base_y < 1.4, "удар не должен запускать машину через забор: %.2f" % (max_y - base_y))
		check(min_z_velocity > -10.0, "удар не должен резко отбрасывать машину назад: %.2f" % min_z_velocity)
		# Возможность отъехать от барьера, без скрытого ограничения скорости.
		car.linear_velocity = Vector3(0, 0, -5)
		var start_z: float = car.global_position.z
		for i in range(60):
			await physics_frame
		check(car.global_position.z < start_z - 0.2, "после удара можно отъехать назад")
		# Косой удар: ограничение по нормали не должно запрещать скольжение.
		car.spawn_transform = Transform3D(Basis.IDENTITY, Vector3(-10, 0.3, 0))
		car.reset_to_spawn()
		for i in range(120):
			await physics_frame
		car.linear_velocity = Vector3(15, 0, 15)
		var oblique_max_z := -INF
		for i in range(130):
			await physics_frame
			oblique_max_z = maxf(oblique_max_z, car.global_position.z)
		check(oblique_max_z < 10.2, "косой удар не проходит сквозь забор")
		check(car.global_position.x > -8.0, "машина сохраняет движение вдоль забора")
		# Вне столкновения вертикальная скорость не обрезается.
		car.spawn_transform = Transform3D(Basis.IDENTITY, Vector3(0, 15, 0))
		car.reset_to_spawn()
		car.linear_velocity = Vector3(0, 4, 0)
		await physics_frame
		await physics_frame
		check(car.linear_velocity.y > 3.0, "свободный прыжок сохраняется")
		car.queue_free()
		await process_frame
	world.queue_free()
	print("Car obstacle collision: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
