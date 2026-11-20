# godot --headless --path . --fixed-fps 120 --script res://tests/car_stationary_slip.gd
# Стоящая машина не должна «скользить»: скорость пятна контакта считается
# конечной разностью позиции колеса, и физический дрожжевой сдвиг на месте раньше
# превращался в фантомное скольжение — телеметрия показывала занос, хотя машина
# стояла. Здесь проверяем, что после сглаживания скорости колеса у стоящей машины
# скольжение и дрейф остаются около нуля на каждой модели реестра.
extends SceneTree

const Config = preload("res://data/rally_game_config.tres")
const CarModels = preload("res://scripts/car_models.gd")

## Кадров на усадку подвески и на замер стояния (по ~1 с при fixed-fps 120).
const SETTLE_FRAMES := 120
const MEASURE_FRAMES := 120
## Пороги «стоит на месте»: скольжение 0..1 и горизонтальный дрейф, м.
const MAX_SLIP := 0.05
const MAX_DRIFT_M := 0.15

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
	box.size = Vector3(200.0, 1.0, 200.0)
	collider.shape = box
	collider.position.y = -0.5
	ground.add_child(collider)
	world.add_child(ground)
	return world


func _run() -> void:
	var config := Config.duplicate(true) as RallyGameConfig
	for vehicle_resource in config.vehicles:
		var data := vehicle_resource as RallyVehicle
		if data == null:
			continue
		var world := _make_world()
		var scene := load(CarModels.scene_path(data.race_scene)) as PackedScene
		check(scene != null, "сцена машины открывается: " + data.id)
		if scene == null:
			world.queue_free()
			continue
		var car := scene.instantiate() as RallyCar
		car.mouse_look_enabled = false
		car.position.y = 0.3
		world.add_child(car)
		# Никакого ввода: ни газа, ни руля, ни тормоза, ни ручника.
		car.throttle_input = 0.0
		car.steer_input = 0.0
		car.steering_input = 0.0
		car.brake_input = 0.0
		car.handbrake_input = 0.0

		await _steps(SETTLE_FRAMES)
		var start: Vector3 = car.global_position
		var max_slip := 0.0
		for i in range(MEASURE_FRAMES):
			await physics_frame
			max_slip = maxf(max_slip, car.get_average_tire_slip())
		var drift: float = Vector2(
			car.global_position.x - start.x,
			car.global_position.z - start.z
		).length()

		check(max_slip <= MAX_SLIP,
			"%s: стоящая машина не скользит (slip %.3f ≤ %.2f)" % [data.id, max_slip, MAX_SLIP])
		check(drift <= MAX_DRIFT_M,
			"%s: стоящая машина не уезжает (дрейф %.3f м ≤ %.2f)" % [data.id, drift, MAX_DRIFT_M])
		world.queue_free()
		await _steps(2)

	if failures.is_empty():
		print("PASS: ни одна машина не скользит и не уезжает, стоя на месте")
	quit(0 if failures.is_empty() else 1)
