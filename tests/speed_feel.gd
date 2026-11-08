# godot --headless --path . --script res://tests/speed_feel.gd
## Ощущение скорости без тряски: чистая математика камеры и поведение
## в заезде. Проверяем, что отдача только плавная и предсказуемая:
## нет дрожания между кадрами, нет мгновенных скачков, стоянка — ноль.
extends SceneTree

const Sway = preload("res://scripts/effects/rally_speed_sway.gd")
const Feel = preload("res://scripts/data/rally_car_feel_config.gd")
const CarScript = preload("res://scripts/rally_car.gd")
const CarScene = preload("res://scenes/rally_car.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _run() -> void:
	_check_speed_weight()
	_check_lean()
	_check_smoothness()
	_check_fov_curve()
	await _check_camera_in_game()
	if failures.is_empty():
		print("PASS: ощущение скорости — плавное, без тряски, стоянка спокойна")
		quit(0)
	else:
		printerr("FAIL: ощущение скорости: %d проблем(ы)" % failures.size())
		quit(1)


## Вес скорости: ровно ноль на стоянке и монотонный рост к максимуму.
func _check_speed_weight() -> void:
	_check(is_zero_approx(Sway.speed_weight(0.0, 25.0, 130.0)), "на стоянке эффект скорости должен быть ровно нулевым")
	_check(is_zero_approx(Sway.speed_weight(10.0, 25.0, 130.0)), "ниже порога эффект должен молчать")
	_check(is_equal_approx(Sway.speed_weight(400.0, 25.0, 130.0), 1.0), "выше порога — полный эффект")
	var previous: float = -1.0
	var monotone: bool = true
	var speed: float = 0.0
	while speed <= 260.0:
		var value: float = Sway.speed_weight(speed, 25.0, 130.0)
		if value < previous - 0.000001:
			monotone = false
		previous = value
		speed += 5.0
	_check(monotone, "вес скорости должен расти монотонно")
	_check(is_zero_approx(Sway.speed_weight(100.0, 130.0, 130.0)), "вырожденный порог не должен ломать расчёт")
	_check(is_zero_approx(Sway.speed_weight(NAN, 25.0, 130.0)), "NaN на входе не должен ломать камеру")


## Занос: конечен, ограничен единицей и меняет сторону вместе с поворотом.
func _check_lean() -> void:
	var left: float = Sway.corner_lean(45.0, 4.0, 0.55, false)
	var right: float = Sway.corner_lean(-45.0, -4.0, 0.55, false)
	_check(left > 0.0 and right < 0.0, "поворот влево и вправо должны давать разные знаки заноса")
	_check(is_equal_approx(left, -right), "занос должен быть симметричным")
	_check(absf(Sway.corner_lean(5000.0, 400.0, 0.55, false)) <= 1.0, "занос должен быть ограничен единицей")
	_check(is_zero_approx(Sway.corner_lean(0.0, 0.0)), "прямая без боковой перегрузки не даёт заноса")
	_check(is_zero_approx(Sway.corner_lean(NAN, 4.0)), "NaN не должен ломать занос")
	_check(is_equal_approx(Sway.corner_lean(45.0, 0.0, 1.0, true), -Sway.corner_lean(45.0, 0.0, 1.0, false)), "инверсия меняет только знак")
	var angle: float = Sway.lean_angle(1.0, 2.4, 1.0)
	_check(is_equal_approx(angle, deg_to_rad(2.4)), "полный занос должен давать ровно предел в градусах")
	_check(is_zero_approx(Sway.lean_angle(1.0, 2.4, 0.0)), "нулевая скорость выключает занос")


## Плавность: соседние кадры не могут отличаться скачком.
func _check_smoothness() -> void:
	var dt: float = 1.0 / 60.0
	var previous: float = 0.0
	var max_step: float = 0.0
	var time: float = 0.0
	while time < 6.0:
		var value: float = Sway.float_bob(time, 0.7, 0.012)
		max_step = maxf(max_step, absf(value - previous))
		previous = value
		time += dt
	_check(max_step < 0.003, "«дыхание» камеры должно быть плавным, без скачков (шаг %.5f м)" % max_step)
	var weight: float = Sway.response_weight(5.0, dt)
	_check(weight > 0.0 and weight < 1.0, "сглаживание не должно давать мгновенный скачок")
	_check(is_zero_approx(Sway.response_weight(5.0, 0.0)), "нулевой кадр не меняет состояние")
	# Предел вертикальной реакции: даже удар не подбрасывает кадр выше лимита.
	_check(absf(Sway.vertical_inertia(-200.0, 0.006, 0.05)) <= 0.05, "вертикальная реакция должна быть ограничена")


## FOV: спокойный старт и полное раскрытие только к максимуму.
func _check_fov_curve() -> void:
	var linear_at_start: float = Sway.speed_fov_factor(40.0, 160.0, 0.0)
	var eased_at_start: float = Sway.speed_fov_factor(40.0, 160.0, 0.75)
	_check(eased_at_start < linear_at_start, "плавная кривая должна быть спокойнее линейной на малой скорости")
	_check(is_equal_approx(Sway.speed_fov_factor(160.0, 160.0, 0.75), 1.0), "к максимуму FOV раскрывается полностью")
	_check(is_zero_approx(Sway.speed_fov_factor(0.0, 160.0, 0.75)), "на стоянке FOV базовый")
	var feel := Feel.new()
	_check(feel.fov_speed_ease > 0.0, "плавная кривая FOV должна быть включена по умолчанию")
	_check(feel.high_speed_bob_hz < 2.0, "«дыхание» камеры должно быть медленнее 2 Гц")
	_check(feel.corner_lean_max_deg <= 4.0, "занос камеры должен оставаться деликатным")
	_check(feel.speed_motes_enabled, "придорожный поток должен быть включён по умолчанию")
	feel.free()


## В игре: камера ззади следует за машиной, не дрожит между кадрами и
## полностью успокаивается при выключенном ощущении скорости.
func _check_camera_in_game() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(600.0, 1.0, 600.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	world.add_child(ground)
	var car = CarScene.instantiate()
	car.mouse_look_enabled = false
	car.initial_camera_mode = CarScript.CameraMode.CHASE_3RD
	world.add_child(car)
	car.spawn_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, 0.0))
	await physics_frame
	await physics_frame

	# Стоянка: отдача ровно нулевая, камера не «дышит».
	car.speed_kmh = 0.0
	for i in range(60):
		await physics_frame
	_check(is_zero_approx(car._feel_lean) and is_zero_approx(car._feel_roll), "на стоянке камера не должна качаться")
	_check(is_zero_approx(car._feel_pull), "на стоянке дистанция камеры не должна меняться")
	_check(is_zero_approx(car.speed_motes_intensity()), "на стоянке придорожного потока быть не должно")

	# Скорость: занос остаётся в пределах конфига и не «звенит».
	car.speed_kmh = 150.0
	car._feel_yaw_rate_deg = 60.0
	var dt: float = 1.0 / 120.0
	for i in range(240):
		car._update_speed_feel(dt)
	var limit: float = deg_to_rad(car.f().corner_lean_max_deg) + 0.0001
	_check(absf(car._feel_lean) <= limit, "занос камеры не должен превышать предел (%.4f)" % car._feel_lean)
	_check(absf(car._feel_roll) <= deg_to_rad(car.f().corner_roll_max_deg) + 0.0001, "крен камеры ограничен")
	_check(absf(car._feel_pull) <= car.f().speed_pull_limit + 0.0001, "сдвиг дистанции ограничен")

	# Выключение: отдача полностью успокаивается, но камера остаётся рабочей.
	car.camera_feel_strength = 0.0
	for i in range(240):
		car._update_speed_feel(dt)
	_check(is_zero_approx(car._chase_feel_scale()), "выключатель должен обнулять масштаб отдачи")
	var before: Transform3D = car.active_camera.global_transform
	car._update_cameras(dt)
	var after: Transform3D = car.active_camera.global_transform
	_check(before.origin.distance_to(after.origin) < 1.0, "камера должна оставаться на месте при выключенной отдаче")

	world.queue_free()
	await process_frame
