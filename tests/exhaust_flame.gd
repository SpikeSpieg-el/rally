# godot --headless --path . --fixed-fps 120 --script res://tests/exhaust_flame.gd
# Выстрелы пламени из выхлопа (textures/fire.png) на ВСЕХ машинах реестра:
#   * компонент стоит, трубы найдены у заднего бампера, язык смотрит назад;
#   * хлопок в звуке мотора (EngineAudio.exhaust_pop) зажигает пламя, оно гаснет
#     само за долю секунды;
#   * сброс газа, переключение вверх и отсечка стреляют и без звука;
#   * без турбины (turbo = false) пламени нет; выключатель в ресурсе работает;
#   * физика не задета: траектория разгона с пламенем и без совпадает.
extends SceneTree

const Config = preload("res://data/rally_game_config.tres")
const CarModels = preload("res://scripts/car_models.gd")
const SETUP := preload("res://data/setups/11_gravel.tres")
const FIRE := preload("res://textures/fire.png")
const SETTINGS := preload("res://data/car/default_exhaust_flame.tres")

const SETTLE_FRAMES := 90

var failures: Array[String] = []


class GameStub:
	extends Node

	var race_vehicle_id := "mitsubishi"

	func get_race_vehicle_id() -> String:
		return race_vehicle_id


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)
	else:
		print("PASS: " + message)


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
	box.size = Vector3(400.0, 1.0, 400.0)
	collider.shape = box
	collider.position.y = -0.5
	ground.add_child(collider)
	world.add_child(ground)
	return world


func _spawn(
	world: Node3D, scene: PackedScene, setup: RallyCarSetup, settings: RallyExhaustFlameConfig
) -> RallyCar:
	var car := scene.instantiate() as RallyCar
	car.setup_override = setup
	car.mouse_look_enabled = false
	if settings != null:
		car.exhaust_flame_config = settings
	car.position = Vector3(0.0, 0.3, 0.0)
	world.add_child(car)
	return car


func _turbo_setup(turbo: bool) -> RallyCarSetup:
	var setup := SETUP.duplicate(true) as RallyCarSetup
	setup.turbo = turbo
	return setup


func _run() -> void:
	var game := GameStub.new()
	game.name = "RallyGame"
	root.add_child(game)
	check(SETTINGS.flame_texture == FIRE, "ресурс пламени берёт textures/fire.png")

	var config := Config.duplicate(true) as RallyGameConfig
	for vehicle_resource in config.vehicles:
		var data := vehicle_resource as RallyVehicle
		if data == null:
			continue
		game.race_vehicle_id = data.id
		var scene := load(CarModels.scene_path(data.race_scene)) as PackedScene
		if scene == null:
			check(false, "сцена машины открывается: " + data.id)
			continue
		var world := _make_world()
		var car := _spawn(world, scene, _turbo_setup(true), null)
		await _steps(SETTLE_FRAMES)
		await _check_car(data.id, car)
		world.queue_free()
		await _steps(2)

	await _check_switches(game)
	await _check_physics(game)

	if failures.is_empty():
		print("OK: выстрелы пламени из выхлопа")
		quit(0)
	else:
		printerr("итого провалов: %d" % failures.size())
		quit(1)


func _check_car(id: String, car: RallyCar) -> void:
	var fx := car.exhaust_flames
	check(fx != null, "%s: компонент пламени установлен" % id)
	if fx == null:
		return
	check(fx.outlet_count() >= 1, "%s: найдена хотя бы одна труба" % id)
	var outlets := fx.outlets_local()
	print("[exhaust] %s: труб %d, срезы %s" % [id, outlets.size(), str(outlets)])
	for point in outlets:
		check(point.z < -0.8 and point.y > 0.0 and point.y < 1.4 and absf(point.x) < 1.2,
			"%s: срез трубы у заднего бампера (%s)" % [id, str(point)])
	var audio := car.get_node_or_null("EngineAudio")
	check(audio != null and audio.has_signal("exhaust_pop"), "%s: звук мотора сообщает о хлопках" % id)
	if audio == null:
		return
	var before := fx.shot_count()
	audio.emit_signal("exhaust_pop", 1.0)
	check(fx.shot_count() == before + 1, "%s: хлопок в звуке зажигает пламя" % id)
	check(fx.active_flames() >= fx.outlet_count(), "%s: горит язык у каждой трубы" % id)
	# Язык смотрит назад машины: ось -Z корня языка против хода.
	var back := -car.global_basis.z.normalized()
	var all_back := true
	var textured := true
	for flame in fx.find_children("Flame_*", "Node3D", true, false):
		var node := flame as Node3D
		if not node.visible:
			continue
		var dir := (-node.global_basis.z).normalized()
		if dir.dot(back) < 0.8:
			all_back = false
		var jet := node.get_node("Jet") as MeshInstance3D
		var mat := jet.material_override as StandardMaterial3D
		if mat == null or mat.albedo_texture != FIRE or mat.blend_mode != BaseMaterial3D.BLEND_MODE_ADD:
			textured = false
	check(all_back, "%s: пламя бьёт назад из трубы" % id)
	check(textured, "%s: язык нарисован fire.png со сложением цвета" % id)
	await _steps(48)
	check(fx.active_flames() == 0, "%s: пламя гаснет само за 0.4 с" % id)


## Триггеры без звука, турбина и выключатель.
func _check_switches(game: GameStub) -> void:
	game.race_vehicle_id = "mitsubishi"
	var scene := load(CarModels.race_scene_path("mitsubishi")) as PackedScene
	var world := _make_world()

	var settings := SETTINGS.duplicate(true) as RallyExhaustFlameConfig
	settings.sync_with_audio = false
	settings.crackle_enabled = false
	settings.cooldown_sec = 0.02
	var car := _spawn(world, scene, _turbo_setup(true), settings)
	await _steps(SETTLE_FRAMES)
	var fx := car.exhaust_flames
	fx.set_process(false)
	var dt := 1.0 / 60.0
	# Сброс газа на высоких оборотах.
	car.is_shifting = false
	car.motor_is_redline = false
	car.current_gear = 3
	car.current_rpm = 6000.0
	car.throttle_input = 1.0
	fx._update_triggers(dt)
	fx._cooldown = 0.0
	var before := fx.shot_count()
	car.throttle_input = 0.0
	fx._update_triggers(dt)
	check(fx.shot_count() == before + 1, "сброс газа стреляет без звука")
	# На низких оборотах — нет.
	fx._cooldown = 0.0
	car.current_rpm = 2000.0
	car.throttle_input = 1.0
	fx._update_triggers(dt)
	before = fx.shot_count()
	car.throttle_input = 0.0
	fx._update_triggers(dt)
	check(fx.shot_count() == before, "сброс газа на холостых не стреляет")
	# Переключение вверх под газом.
	fx._cooldown = 0.0
	car.current_rpm = 6500.0
	car.throttle_input = 1.0
	fx._update_triggers(dt)
	before = fx.shot_count()
	car.current_gear = 4
	fx._update_triggers(dt)
	check(fx.shot_count() == before + 1, "переключение вверх стреляет")
	# Отсечка.
	fx._cooldown = 0.0
	car.motor_is_redline = true
	before = fx.shot_count()
	for i in range(30):
		fx._cooldown = 0.0
		fx._update_triggers(dt)
	car.motor_is_redline = false
	check(fx.shot_count() > before, "отсечка стреляет")
	fx.clear()
	check(fx.active_flames() == 0 and fx.shot_count() == 0, "очистка гасит пламя")
	car.queue_free()
	await _steps(2)

	# Без турбины пламени нет, хотя компонент стоит (пресет мотора могут сменить).
	var atmo := _spawn(world, scene, _turbo_setup(false), null)
	await _steps(10)
	check(atmo.exhaust_flames != null and not atmo.exhaust_flames.is_allowed(),
		"без турбины пламя выключено")
	check(atmo.exhaust_flames == null or not atmo.exhaust_flames.fire(1.0),
		"без турбины выстрел не происходит")
	atmo.queue_free()
	await _steps(2)

	var off := SETTINGS.duplicate(true) as RallyExhaustFlameConfig
	off.enabled = false
	var silent := _spawn(world, scene, _turbo_setup(true), off)
	await _steps(10)
	check(silent.exhaust_flames == null, "выключатель в ресурсе убирает пламя")
	world.queue_free()
	await _steps(2)


## Разгон с выстрелами и без: траектория одна и та же.
func _check_physics(game: GameStub) -> void:
	game.race_vehicle_id = "mitsubishi"
	var scene := load(CarModels.race_scene_path("mitsubishi")) as PackedScene
	var ends: Array[Vector3] = []
	for with_flames in [true, false]:
		var world := _make_world()
		var settings := SETTINGS.duplicate(true) as RallyExhaustFlameConfig
		settings.enabled = with_flames
		var car := _spawn(world, scene, _turbo_setup(true), settings)
		await _steps(SETTLE_FRAMES)
		car.linear_velocity = car.global_basis.z * 15.0
		for i in range(120):
			if with_flames and i % 10 == 0 and car.exhaust_flames != null:
				car.exhaust_flames.fire(1.0, true)
			await physics_frame
		ends.append(car.global_position)
		world.queue_free()
		await _steps(2)
	var diff := ends[0].distance_to(ends[1])
	print("[exhaust] расхождение траекторий %.4f м" % diff)
	check(diff < 0.02, "пламя не влияет на физику (%.4f м)" % diff)
