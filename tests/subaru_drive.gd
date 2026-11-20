# godot --headless --path . --fixed-fps 120 --script res://tests/subaru_drive.gd
# Гараж, сохранение выбора и реальная физика Subaru на ровном грунте.
extends SceneTree

const Game = preload("res://scripts/game_state.gd")
const Garage = preload("res://scenes/garage_menu.tscn")
const Config = preload("res://data/rally_game_config.tres")
const Models = preload("res://scripts/car_models.gd")
## Крепления подвески одинаковы у всех машин игры, а меши колёс ищем по
## структуре: Subaru и Golf сегодня ездят на колёсах Lancer, но новая машина
## может привезти свои — имя меша не должно быть частью контракта.
const WHEEL_MOUNTS := ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("_run")

func _steps(count: int) -> void:
	for i in range(count):
		await physics_frame

## Меш колеса под креплением подвески: Wheel_FL → WheelVisual → меш.
func wheel_visual(mount: Node) -> MeshInstance3D:
	if mount == null:
		return null
	var holder := mount.find_child("WheelVisual", true, false)
	if holder == null:
		return null
	var meshes := holder.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return null
	return meshes[0] as MeshInstance3D

func _run() -> void:
	var old_game := root.get_node_or_null("RallyGame")
	if old_game != null:
		root.remove_child(old_game)
		old_game.queue_free()
	var game := Game.new()
	game.name = "RallyGame"
	game.config = Config.duplicate(true)
	game.conditions_path = "user://subaru_drive_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.conditions_path))
	root.add_child(game)
	var garage = Garage.instantiate()
	root.add_child(garage)
	garage.open(game.config, 0, game)
	var subaru: RallyVehicle = Models.vehicle("subaru")
	check(subaru != null, "в реестре машин есть Subaru")
	garage.select_vehicle("subaru")
	var preview: Node3D = garage._vehicle_models.get("subaru")
	check(game.vehicle_id == "subaru" and preview != null and preview.visible and not garage._model.visible, "Subaru выбирается и показывается в гараже")
	# Колёса витрины берутся из самой видимой модели: гараж кладёт их список в
	# метку кузова (Garage.WHEELS_META). В этом списке обязаны быть ровно четыре
	# колеса текущей машины, а не колёса всех загруженных кузовов разом.
	var vitrine_wheels: Array = garage._model_wheels(preview)
	check(vitrine_wheels.size() == WHEEL_MOUNTS.size(),
		"на витрине Subaru четыре колеса, найдено %d" % vitrine_wheels.size())
	for entry in vitrine_wheels:
		var wheel: Node3D = null
		if entry is Dictionary:
			wheel = entry.get("node") as Node3D
		check(wheel != null and preview.is_ancestor_of(wheel) and wheel.visible,
			"колесо Subaru видно в гараже")
	game.load_conditions()
	game.vehicle_id = "mitsubishi"
	game._restore_saved_selection()
	check(game.vehicle_id == "subaru", "выбор машины сохраняется между сеансами")
	garage.select_vehicle("mitsubishi")
	check(game.vehicle_id == "mitsubishi",
		"выбор возвращается к Mitsubishi (id=%s)" % game.vehicle_id)
	var mitsu_preview: Node3D = garage._vehicle_models.get("mitsubishi") as Node3D
	check(garage._vehicle_models.has("mitsubishi"),
		"у Mitsubishi своя модель витрины (загружена при открытии гаража)")
	check(mitsu_preview != null and mitsu_preview.visible,
		"витрина показывает кузов Mitsubishi")
	check(not preview.visible, "кузов Subaru скрыт после смены машины")
	garage.select_vehicle("subaru")
	game._race_uses_selected_setup = true
	garage.free()

	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	ground.add_to_group("Dirt")
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(500.0, 1.0, 500.0)
	collider.shape = box
	collider.position.y = -0.5
	ground.add_child(collider)
	world.add_child(ground)
	# Subaru едет на своей игровой сцене, а не на сцене Lancer с подменой кузова.
	var car = load(Models.scene_path(subaru.race_scene)).instantiate()
	# Свой стоковый пресет Subaru, а не 4G63T от Lancer: иначе «физика Subaru»
	# измерялась бы на чужом моторе и главной паре.
	var subaru_setup := game.config.get_setup(0, "subaru") as RallyCarSetup
	check(subaru_setup != null and subaru_setup.engine_name.begins_with("EJ25"),
		"у Subaru свой стоковый пресет")
	car.setup_override = subaru_setup.duplicate(true) if subaru_setup != null else null
	car.mouse_look_enabled = false
	car.position.y = 0.3
	world.add_child(car)
	check(car.scene_file_path == Models.scene_path(subaru.race_scene),
		"в заезде используется сцена Subaru")
	for mount_name in WHEEL_MOUNTS:
		var mount: Node = car.get_node_or_null(mount_name)
		check(mount != null, "в сцене Subaru есть крепление подвески " + mount_name)
		var visual := wheel_visual(mount)
		check(visual != null and visual.visible,
			"колесо прикреплено к симуляции подвески: " + mount_name)
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
	check(contacts >= 3 and distance > 3.0 and speed_before > 8.0 and car.speed_kmh < speed_before, "Subaru разгоняется и тормозит")
	world.free()
	game._race_uses_selected_setup = false
	# Прямой запуск сцены (F6) показывает машину по умолчанию из конфига.
	var default_id := game.config.default_vehicle_id()
	var default_vehicle: RallyVehicle = game.config.vehicle(default_id)
	check(default_vehicle != null, "в конфиге есть машина по умолчанию")
	var direct: RallyCar = null
	if default_vehicle != null:
		var direct_scene := load(Models.scene_path(default_vehicle.race_scene)) as PackedScene
		if direct_scene != null:
			direct = direct_scene.instantiate() as RallyCar
	check(direct != null, "сцена машины по умолчанию открывается")
	if direct != null:
		direct.mouse_look_enabled = false
		root.add_child(direct)
		check(direct._find_body_model() != null,
			"прямой запуск %s показывает свой кузов" % default_id)
		direct.free()
	game.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://subaru_drive_test.cfg"))
	print("Subaru: %d failures; distance %.1f m, speed %.1f km/h" % [failures, distance, speed_before])
	quit(0 if failures == 0 else 1)
