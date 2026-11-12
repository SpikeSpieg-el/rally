# godot --headless --path . --fixed-fps 120 --script res://tests/engine_brake.gd
# Торможение двигателем. Поле engine_brake_scale сетапа (ползунок «Торможение
# двигателем» в гараже) задаёт motor_brake — момент сопротивления мотора при
# закрытом дросселе. Раньше motor_brake только записывался: модель мотора его
# не читала, и ползунок ничего не менял. Тест следит, что множитель меняет
# замедление на сбросе газа и не трогает разгон под полным газом.
extends SceneTree

const CarScene = preload("res://scenes/rally_car.tscn")
const StockSetup = preload("res://data/setups/engine_stock.tres")
const PHYSICS_FPS := 120
const SETTLE_STEPS := 240
## Края ползунка «Торможение двигателем» в гараже.
const WEAK_SCALE := 0.2
const STRONG_SCALE := 3.0
## С какой скорости сбрасывается газ.
const LIFT_SPEED_KMH := 100.0
## Дроссель закрывается не мгновенно: замер начинается после этой паузы.
const LIFT_SETTLE_S := 0.5
const MEASURE_S := 2.0
## Насколько сильнее обязан замедляться «сильный» мотор, м/с². По замеру
## разница между краями ползунка на 100 км/ч — около 0.9 м/с².
const MIN_DECEL_GAIN := 0.6
## Допуск на разницу разгона 0–100 под полным газом, с.
const MAX_ACCEL_DIFF_S := 0.15
const ACCEL_TIMEOUT_S := 30.0

var failures: Array[String] = []


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)


func _initialize() -> void:
	call_deferred("_run")


func _steps(count: int) -> void:
	for i in range(count):
		await physics_frame


func _make_world() -> Node3D:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	ground.add_to_group("Dirt")
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 2000.0)
	collider.shape = box
	collider.position = Vector3(0.0, -0.5, 900.0)
	ground.add_child(collider)
	world.add_child(ground)
	return world


## Разгон с места до LIFT_SPEED_KMH, сброс газа и замер замедления накатом.
func _lift_off(scale: float) -> Dictionary:
	var world := _make_world()
	var setup := StockSetup.duplicate(true) as RallyCarSetup
	setup.engine_brake_scale = scale
	var car := CarScene.instantiate() as RallyCar
	car.setup_override = setup
	car.mouse_look_enabled = false
	car.position.y = 0.3
	world.add_child(car)
	await _steps(SETTLE_STEPS)
	var result := {
		"motor_brake": car.motor_brake,
		"idle_torque": 0.0,
		"full_throttle_torque": 0.0,
		"accel_s": -1.0,
		"decel": 0.0,
		"gear": 0,
		"rpm": 0.0,
	}
	# Контракт самой формулы: на холостых и под полным газом торможения нет.
	car.motor_rpm = car.idle_rpm
	result["idle_torque"] = car.get_engine_brake_torque(0.0)
	car.motor_rpm = car.max_rpm
	result["full_throttle_torque"] = car.get_engine_brake_torque(1.0)
	car.motor_rpm = car.idle_rpm
	Input.action_press("throttle")
	for i in range(int(ACCEL_TIMEOUT_S * PHYSICS_FPS)):
		await physics_frame
		if car.speed_kmh >= LIFT_SPEED_KMH:
			result["accel_s"] = float(i + 1) / PHYSICS_FPS
			break
	Input.action_release("throttle")
	await _steps(int(LIFT_SETTLE_S * PHYSICS_FPS))
	var from_kmh: float = car.speed_kmh
	result["gear"] = car.current_gear
	result["rpm"] = car.motor_rpm
	await _steps(int(MEASURE_S * PHYSICS_FPS))
	result["decel"] = (from_kmh - car.speed_kmh) / 3.6 / MEASURE_S
	world.free()
	await _steps(2)
	return result


func _run() -> void:
	# Коробку выбирает игрок в меню (RallyGame), а не пресет: тесту нужен автомат.
	var game := root.get_node_or_null("RallyGame")
	if game != null:
		game.set("transmission_index", RallyCarSetup.Transmission.AUTOMATIC)

	var weak: Dictionary = await _lift_off(WEAK_SCALE)
	var strong: Dictionary = await _lift_off(STRONG_SCALE)
	for run in [[WEAK_SCALE, weak], [STRONG_SCALE, strong]]:
		var scale: float = run[0]
		var result: Dictionary = run[1]
		check(is_equal_approx(result["motor_brake"], RallyCar.BASE_MOTOR_BRAKE * scale), "множитель ×%.1f из сетапа доходит до motor_brake" % scale)
		check(is_zero_approx(result["idle_torque"]), "на холостых торможения двигателем нет (×%.1f)" % scale)
		check(is_zero_approx(result["full_throttle_torque"]), "под полным газом торможения двигателем нет (×%.1f)" % scale)
		check(result["accel_s"] > 0.0, "машина разгоняется до %.0f км/ч (×%.1f)" % [LIFT_SPEED_KMH, scale])
		print("Торможение двигателем ×%.1f: 0–%.0f за %.2f с; сброс газа на %d-й передаче (%.0f об/мин) — замедление %.2f м/с²" % [
			scale, LIFT_SPEED_KMH, result["accel_s"], result["gear"], result["rpm"], result["decel"],
		])
	check(strong["decel"] - weak["decel"] >= MIN_DECEL_GAIN, "×%.1f должно замедлять сильнее ×%.1f не меньше чем на %.1f м/с²: %.2f против %.2f" % [STRONG_SCALE, WEAK_SCALE, MIN_DECEL_GAIN, strong["decel"], weak["decel"]])
	check(absf(strong["accel_s"] - weak["accel_s"]) <= MAX_ACCEL_DIFF_S, "разгон под полным газом не зависит от торможения двигателем: %.2f против %.2f с" % [strong["accel_s"], weak["accel_s"]])

	print("Engine brake: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
