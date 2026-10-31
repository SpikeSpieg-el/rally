# godot --headless --path . --fixed-fps 120 --script res://tests/transmission.gd
# Реальное сцепление, ручной ряд передач и поведение после сброса.
extends SceneTree

const CarScene = preload("res://scenes/rally_car.tscn")
const Setup = preload("res://data/setups/engine_stock.tres")
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("_run")

func steps(count: int) -> void:
	for i in range(count):
		await physics_frame

func tap(action: String) -> void:
	Input.action_press(action)
	await steps(2)
	Input.action_release(action)
	await steps(2)

func keyboard_event(code: Key, pressed: bool, shift_held: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.shift_pressed = shift_held
	return event

func make_car(world: Node3D, mode: int) -> RallyCar:
	var setup := Setup.duplicate(true) as RallyCarSetup
	setup.transmission_mode = mode
	var car := CarScene.instantiate() as RallyCar
	car.setup_override = setup
	car.mouse_look_enabled = false
	car.position.y = 0.3
	world.add_child(car)
	return car

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

	var car := make_car(world, RallyCarSetup.Transmission.MANUAL_CLUTCH)
	await steps(120)
	check(car.manual_clutch_control and not car.automatic_transmission and car.current_gear == 0, "педальная МКПП начинает с нейтрали")
	await tap("shift_up")
	check(car.current_gear == 0 and car.shift_notice_time > 0.0, "без сцепления включить передачу нельзя")
	# Проверяем не только action_press, но и реальное сочетание Shift + E.
	Input.parse_input_event(keyboard_event(KEY_SHIFT, true, true))
	await steps(3)
	check(car.clutch_input > 0.99, "физический Shift выжимает педаль")
	Input.parse_input_event(keyboard_event(KEY_E, true, true))
	await steps(3)
	Input.parse_input_event(keyboard_event(KEY_E, false, true))
	await steps(2)
	check(car.current_gear == 1, "с выжатым Shift клавиша E включает первую")
	var start := car.global_position
	Input.action_press("throttle")
	await steps(40)
	var free_rpm: float = car.motor_rpm
	check(car.clutch_amount > 0.99 and absf(car.clutch_torque) < 0.01, "выжатая педаль размыкает передачу момента")
	check(free_rpm > car.idle_rpm * 1.5 and car.global_position.distance_to(start) < 1.0, "газ с выжатым сцеплением раскручивает мотор, но не разгоняет машину")
	Input.parse_input_event(keyboard_event(KEY_SHIFT, false, false))
	await steps(240)
	Input.action_release("throttle")
	var distance: float = car.global_position.z - start.z
	print("МКПП + сцепление: свободные обороты %.0f, разгон %.1f м, %.1f км/ч, заглох=%s" % [free_rpm, distance, car.speed_kmh, car.engine_stalled])
	check(distance > 3.0 and car.speed_kmh > 8.0 and not car.engine_stalled, "после отпускания сцепления машина разгоняется")
	# На скорости передача без педали не меняется.
	await tap("shift_up")
	check(car.current_gear == 1, "переключение на вторую без выжатой педали отклоняется")
	Input.action_press("clutch")
	await tap("shift_up")
	await steps(30)
	check(car.current_gear == 2, "с педалью включается вторая")
	# Выжатая педаль не должна вызывать скрытую автоперегазовку на понижении.
	car.motor_rpm = 2500.0
	car.requested_gear = 1
	car.complete_shift()
	check(is_equal_approx(car.motor_rpm, 2500.0), "ручное сцепление не меняет обороты при переключении")
	Input.action_release("clutch")
	car.reset_to_spawn()
	check(car.current_gear == 0 and not car.automatic_transmission and car.manual_clutch_control, "сброс не возвращает автомат")

	# При нагрузке на заглушённый мотор сцепление не подменяется автоматом.
	await steps(120)
	Input.action_press("clutch")
	await tap("shift_up")
	Input.action_release("clutch")
	await steps(90)
	print("Отпускание без газа: обороты %.0f, заглох=%s" % [car.motor_rpm, car.engine_stalled])
	check(car.engine_stalled and is_zero_approx(car.motor_rpm), "резкое отпускание сцепления без газа может заглушить двигатель")
	# Headless сам не запускает аудиодрайвер, но можно проверить уровни лупов.
	var sound = car.get_node("EngineAudio")
	sound._build_players()
	sound._streams["0900_light"] = load("res://audio/engine/engine_0900_light.wav")
	sound._streams["0900_full"] = load("res://audio/engine/engine_0900_full.wav")
	car.engine_stalled = false
	sound._update_engine(car.idle_rpm, 0.2)
	var light_bank = sound._banks[0]
	check(light_bank.players[light_bank.cur].volume_db > -30.0, "звук работающего двигателя слышен")
	car.engine_stalled = true
	sound._update_engine(0.0, 0.2)
	for bank in sound._banks:
		for player in bank.players:
			check(player.volume_db <= -60.0, "звук заглохшего двигателя приглушён")
	Input.action_press("clutch")
	await steps(90)
	check(not car.engine_stalled and car.motor_rpm > 0.0, "выжатие сцепления запускает заглохший двигатель")
	sound._update_engine(car.idle_rpm, 0.2)
	check(light_bank.players[light_bank.cur].volume_db > -30.0, "звук двигателя возвращается после запуска")
	Input.action_release("clutch")
	car.queue_free()
	await process_frame

	var manual := make_car(world, RallyCarSetup.Transmission.MANUAL)
	await steps(30)
	check(not manual.automatic_transmission and not manual.manual_clutch_control, "ручная коробка с автоматическим сцеплением")
	await tap("shift_up")
	await steps(30)
	check(manual.current_gear == 2, "ручная коробка переключает передачи вперёд")
	await tap("shift_down")
	await steps(30)
	check(manual.current_gear == 1, "ручная коробка переключает вниз")
	await tap("shift_down")
	await steps(30)
	check(manual.current_gear == 0, "между первой и задней есть нейтраль")
	await tap("shift_down")
	check(manual.current_gear == -1, "задняя включается через нейтраль")
	manual.reset_to_spawn()
	check(not manual.automatic_transmission and manual.current_gear == 1, "сброс сохраняет ручной режим")
	manual.queue_free()
	await process_frame

	var auto := make_car(world, RallyCarSetup.Transmission.AUTOMATIC)
	await steps(30)
	await tap("shift_up")
	check(auto.current_gear == 1 and auto.automatic_transmission, "автомат не переключает вперёд вручную")
	await tap("shift_down")
	await steps(30)
	check(auto.current_gear == -1, "на автомате сохранён выбор R одной кнопкой")
	auto.reset_to_spawn()
	check(auto.current_gear == 1 and auto.automatic_transmission, "автомат сохраняется после сброса")
	world.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: автомат, ручная коробка и рабочая педаль сцепления")
		quit(0)
	else:
		printerr("FAIL: коробка и сцепление: %d" % failures.size())
		quit(1)
