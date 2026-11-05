# godot --headless --path . --script res://tests/rev_limiter.gd
# Детерминированная проверка реальных методов двигателя/сцепления без трассы.
extends SceneTree

const VehicleType = preload("res://scripts/gevp/vehicle.gd")
const WheelType = preload("res://scripts/gevp/wheel.gd")
const CarType = preload("res://scripts/rally_car.gd")
const SoundType = preload("res://scripts/engine_sound.gd")
const CarScene = preload("res://scenes/rally_car.tscn")
const SetupType = preload("res://scripts/data/rally_car_setup.gd")

const DT := 1.0 / 120.0

var failures: Array[String] = []


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)


func _initialize() -> void:
	call_deferred("_run")


func engine(redline: float, pedal: bool):
	var vehicle := VehicleType.new()
	vehicle.max_rpm = redline
	vehicle.max_torque = 650.0
	vehicle.max_clutch_torque = 1040.0
	vehicle.motor_rpm = 900.0
	vehicle.idle_rpm = 900.0
	vehicle.motor_moment = 0.5
	vehicle.automatic_transmission = false
	vehicle.manual_clutch_control = pedal
	vehicle.traction_control_max_slip = -1.0
	vehicle.torque_curve = Curve.new()
	vehicle.torque_curve.add_point(Vector2(0, 1))
	vehicle.torque_curve.add_point(Vector2(1, 1))
	vehicle.drive_axles_inertia = 4.0
	for i in range(4):
		var wheel := WheelType.new()
		wheel.tire_radius = 0.438
		vehicle.add_child(wheel)
		vehicle.drive_wheels.append(wheel)
	return vehicle


func set_coupled_rpm(vehicle, rpm: float, reaction: float = 0.0) -> void:
	var ratio: float = vehicle.get_gear_ratio(vehicle.current_gear)
	for wheel in vehicle.drive_wheels:
		wheel.spin = rpm / (ratio * vehicle.ANGULAR_VELOCITY_TO_RPM)
		wheel.force_vector.y = reaction


func _run() -> void:
	for pedal in [false, true]:
		for redline in [3000.0, 4500.0, 10000.0]:
			var vehicle = engine(redline, pedal)
			vehicle.current_gear = 0
			vehicle.throttle_amount = 1.0
			var peak := 0.0
			var cuts := 0
			for i in range(1800):
				vehicle.process_motor(DT)
				peak = maxf(peak, vehicle.motor_rpm)
				if vehicle.motor_is_redline:
					cuts += 1
					check(vehicle.torque_output <= 0.0, "отсечка не создаёт тягу")
			check(
				peak <= redline + 0.01 and peak > redline * 0.94,
				"свободная раскрутка до настроенной, а не +10%, отсечки"
			)
			check(cuts > 0, "отсечка реально срабатывает")
			check(
				is_zero_approx(vehicle.get_torque_at_rpm(redline)),
				"кривая не даёт тягу на/выше отсечки"
			)
			check(
				is_zero_approx(vehicle.get_torque_at_rpm(redline * 1.2)),
				"нет тяги за пределами кривой"
			)
			vehicle.motor_rpm = redline * 0.99
			vehicle.motor_is_redline = true
			check(
				vehicle._limit_motor_torque(0.0, DT) <= 0.0 and vehicle.motor_is_redline,
				"гистерезис удерживает отсечку"
			)
			vehicle.motor_rpm = redline * 0.95
			check(
				vehicle._limit_motor_torque(100.0, DT) > 0.0 and not vehicle.motor_is_redline,
				"тяга возвращается ниже порога"
			)
			vehicle.motor_is_redline = true
			vehicle.throttle_input = 1.0
			vehicle.process_throttle(DT)
			check(vehicle.throttle_amount > 0.0, "отсечка не подменяет педаль газа")
			vehicle.free()

		# Передаточное число, при котором отсечка 4000 RPM соответствует 90 км/ч.
		for gear in [1, -1]:
			var vehicle = engine(4000.0, pedal)
			var ratio: float = 4000.0 / vehicle.ANGULAR_VELOCITY_TO_RPM * 0.438 / (90.0 / 3.6)
			vehicle.final_drive = 4.1
			vehicle.gear_ratios = [ratio / vehicle.final_drive]
			vehicle.reverse_ratio = ratio / vehicle.final_drive
			vehicle.current_gear = gear
			vehicle.motor_rpm = vehicle.max_rpm
			vehicle.throttle_amount = 1.0
			vehicle.linear_velocity = Vector3(0, 0, 120.0 / 3.6 * gear)
			# Реакция шин раньше возвращала положительный момент при моторе на
			# отсечке и колёсах на 120 км/ч. Проверяем обе стороны трансмиссии.
			set_coupled_rpm(vehicle, vehicle.max_rpm * 120.0 / 90.0, -6000.0 * gear)
			check(
				is_equal_approx(vehicle.get_coupled_rpm(), 4000.0 * 120.0 / 90.0),
				"RPM колёс учитывает ряд и задний ход"
			)
			vehicle.process_motor(DT)
			vehicle.process_clutch(DT)
			check(
				vehicle.motor_is_redline and vehicle.torque_output <= 0.0,
				"мотор не тянет сверх настроенной отсечки"
			)
			check(
				vehicle.clutch_torque <= 0.0, "сцепление не создаёт тягу от реакции шин на 120 км/ч"
			)
			check(
				is_equal_approx(absf(vehicle.linear_velocity.z), 120.0 / 3.6),
				"никакого скрытого ограничения скорости кузова"
			)

			# С внешним приводом колёса могут превысить отсечку. RPM не скрываем.
			vehicle.motor_rpm = vehicle.max_rpm
			vehicle.torque_output = 0.0
			set_coupled_rpm(vehicle, vehicle.max_rpm * 1.5)
			for i in range(180):
				vehicle.process_clutch(DT)
			check(
				vehicle.motor_rpm > vehicle.max_rpm * 1.1,
				"механический перекрут не маскируется зажимом RPM"
			)
			vehicle.clutch_amount = 1.0
			vehicle.process_clutch(DT)
			check(is_zero_approx(vehicle.clutch_torque), "выжатое сцепление не тормозит накат")
			vehicle.current_gear = 0
			vehicle.process_clutch(DT)
			check(is_zero_approx(vehicle.clutch_torque), "нейтраль не тормозит накат")
			vehicle.free()

	var car := CarType.new()
	var sound := SoundType.new()
	sound.car = car
	car.max_rpm = 4000.0
	check(
		sound._engine_load_target(4000, 1.0) > 0.99, "звук использует нагрузку настроенного мотора"
	)
	car.motor_is_redline = true
	check(
		is_zero_approx(sound._engine_load_target(4000, 1.0)),
		"звук сбрасывает нагрузку по физической отсечке"
	)
	var last: int = sound.RPM_GRID.size() - 1
	check(
		sound._pitch_for(last, 10000) > sound._pitch_for(last, 9000), "звук не замирает на 9000 RPM"
	)
	check(
		is_equal_approx(sound._pitch_for(last, 10000), 10000.0 / sound.RPM_GRID[last]),
		"питч соответствует оборотам мотора"
	)
	sound.free()
	car.free()

	# Настройки гаража применяются к реальному экземпляру; сброс снимает старый cut.
	var configured = CarScene.instantiate()
	var setup := SetupType.new()
	setup.max_rpm = 4000.0
	setup.max_torque = 600.0
	setup.final_drive = 5.0
	setup.gear_ratios = [3.0, 2.0, 1.0]
	configured.setup_override = setup
	root.add_child(configured)
	configured.set_physics_process(false)
	check(is_equal_approx(configured.max_rpm, 4000.0), "настроенная отсечка применена")
	check(is_equal_approx(configured.get_gear_ratio(3), 5.0), "настроенная коробка применена")
	configured.motor_is_redline = true
	configured.reset_to_spawn()
	check(not configured.motor_is_redline, "сброс снимает старую отсечку")
	check(
		is_equal_approx(configured.current_rpm, configured.motor_rpm),
		"HUD получает фактические обороты"
	)
	configured.queue_free()
	await process_frame
	print("Rev limiter: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
