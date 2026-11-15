## Машины игры: реестр и витрина гаража.
##
## Машина — это игровая сцена res://scenes/rally_car*.tscn. Новая сцена
## подхватывается сама: при загрузке игры для неё создаётся машина с базовыми
## пресетами. Свой ресурс (data/vehicles/*.tres) нужен только для звука,
## пресетов и имени — он находится по полю race_scene.
extends RefCounted

const CONFIG_PATH := "res://data/rally_game_config.tres"
const SCENES_DIR := "res://scenes/"
const CAR_SCENE_PREFIX := "rally_car"
## Метка кузова на корне сцены машины: её ищут покраска и эффекты грязи/крови.
const BODY_META := "car_body_mesh"
## Узлы физики и интерьера: в витрину гаража не попадают.
const PREVIEW_SKIP := ["RallyCockpit", "Cameras"]
const DEFAULT_MAX_RPM := 7800.0

## Общие значения пресетов автоматических машин. Пресет переопределяет свои поля.
const BASE_SETUP := {
	"max_torque": 400.0,
	"idle_rpm": 850.0,
	"torque_shape": 1,
	"turbo": true,
	"final_drive": 4.1,
	"vehicle_mass": 1250.0,
	"awd_front_torque": 0.38,
	"tire_width": 245.0,
	"grip_scale": 1.0,
}

const PRESETS := [
	{
		"key": "stock",
		"name": "СТОК",
		"desc": "Стоковая настройка: ровная тяга, полный привод и мягкая подвеска. Для любых дорог.",
		"set": {"max_torque": 435.0, "vehicle_mass": 1270.0},
	},
	{
		"key": "gravel",
		"name": "ГРАВИЙ",
		"desc": "Гравийная настройка: мягче подвеска, длиннее ход и больше сцепления переднего моста.",
		"set": {
			"max_torque": 430.0, "vehicle_mass": 1280.0, "awd_front_torque": 0.42,
			"front_spring_length": 0.36, "rear_spring_length": 0.38,
			"front_damping_ratio": 0.40, "rear_damping_ratio": 0.46,
			"tire_width": 215.0, "grip_scale": 0.95,
		},
	},
	{
		"key": "snow",
		"name": "СНЕГ",
		"desc": "Снежная настройка: атмосферный отклик без турбо-рывка и чувствительный контроль тяги.",
		"set": {
			"max_torque": 300.0, "torque_shape": 2, "turbo": false, "final_drive": 4.4,
			"vehicle_mass": 1260.0, "awd_front_torque": 0.45, "traction_control_max_slip": 0.5,
			"tire_width": 195.0, "grip_scale": 0.85, "max_rpm": 6900.0,
			"front_spring_length": 0.38, "rear_spring_length": 0.40,
		},
	},
	{
		"key": "tarmac",
		"name": "АСФАЛЬТ",
		"desc": "Асфальтовая настройка: жёсткая подвеска, широкие шины и высокое сцепление.",
		"set": {
			"max_torque": 440.0, "final_drive": 3.9, "vehicle_mass": 1270.0, "awd_front_torque": 0.33,
			"front_arb_ratio": 0.20, "rear_arb_ratio": 0.15,
			"front_damping_ratio": 0.60, "rear_damping_ratio": 0.66,
			"tire_width": 265.0, "grip_scale": 1.1, "brake_force_multiplier": 1.05, "max_rpm": 7100.0,
		},
	},
	{
		"key": "gravel_spec",
		"name": "ГРАВИЙ SPEC",
		"desc": "Спец-гравий: максимум момента и сильнее на длинных грунтовых прямых, тяжелее на поворотах.",
		"set": {
			"max_torque": 450.0, "final_drive": 3.9, "vehicle_mass": 1290.0, "awd_front_torque": 0.45,
			"bump_damp_multiplier": 0.9, "tire_width": 215.0, "grip_scale": 0.95, "max_rpm": 7200.0,
		},
	},
]


## Ресурс машины по id. Прямой запуск сцены (F6) читает реестр сам.
static func vehicle(vehicle_id: String) -> RallyVehicle:
	if vehicle_id.is_empty():
		return null
	var config: RallyGameConfig = _game_config()
	if config == null:
		return null
	return config.vehicle(vehicle_id)


## Игровая сцена машины по id — её заезд ставит на место машины трассы.
static func race_scene_path(vehicle_id: String) -> String:
	var data: RallyVehicle = vehicle(vehicle_id)
	return data.race_scene if data != null else ""


static func _game_config() -> RallyGameConfig:
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	var game: Node = loop.root.get_node_or_null("RallyGame") if loop != null else null
	if game != null and "config" in game:
		var loaded: RallyGameConfig = game.get("config") as RallyGameConfig
		if loaded != null:
			return loaded
	if ResourceLoader.exists(CONFIG_PATH):
		return load(CONFIG_PATH) as RallyGameConfig
	return null


## Все игровые сцены машин в res://scenes/ (rally_car.tscn, rally_car2.tscn, ...).
static func car_scene_paths() -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(SCENES_DIR)
	if dir == null:
		return result
	for file in dir.get_files():
		# В экспорте сцены лежат как .tscn.remap — имя то же, суффикс лишний.
		var name := file.trim_suffix(".remap")
		if not name.begins_with(CAR_SCENE_PREFIX) or not name.ends_with(".tscn"):
			continue
		var path := SCENES_DIR + name
		if not result.has(path):
			result.append(path)
	result.sort()
	return result


## Регистрирует новые игровые сцены машин в конфиге. Уже известные сцены не
## трогает: их ресурс машины (если есть) главнее.
static func sync_registry(config: RallyGameConfig) -> void:
	if config == null:
		return
	for path in car_scene_paths():
		if _has_scene(config, path):
			continue
		var id := path.get_file().get_basename()
		if config.has_vehicle(id):
			push_warning("Машина %s: id %s уже занят, сцена пропущена" % [path, id])
			continue
		var vehicle := RallyVehicle.new()
		vehicle.id = id
		vehicle.display_name = id.to_upper().replace("_", " ")
		vehicle.race_scene = path
		vehicle.uses_livery_presets = false
		var setup_ids: Array[String] = []
		for preset: Dictionary in PRESETS:
			var setup := _make_setup(vehicle, preset)
			config.all_setups.append(setup)
			setup_ids.append(setup.id)
		vehicle.setup_ids = setup_ids
		config.vehicles.append(vehicle)


static func _has_scene(config: RallyGameConfig, path: String) -> bool:
	for resource in config.vehicles:
		var candidate := resource as RallyVehicle
		if candidate != null and candidate.race_scene == path:
			return true
	return false


static func _make_setup(vehicle: RallyVehicle, preset: Dictionary) -> RallyCarSetup:
	var setup := RallyCarSetup.new()
	setup.id = "%s_%s" % [vehicle.id, String(preset["key"])]
	setup.display_name = "%s · %s" % [vehicle.display_name, String(preset["name"])]
	setup.description = String(preset["desc"])
	setup.engine_name = "%s · МОТОР" % vehicle.display_name
	setup.drivetrain = RallyCarSetup.Drivetrain.AWD
	var values: Dictionary = BASE_SETUP.duplicate()
	values["max_rpm"] = DEFAULT_MAX_RPM
	values.merge(preset["set"] as Dictionary, true)
	for key: String in values:
		setup.set(key, values[key])
		if setup.get(key) == null:
			push_error("[Машины] у RallyCarSetup нет поля %s" % key)
	return setup


## Витрина гаража: exterior машины из её игровой сцены, без физики, интерьера
## и камер. Низ кузова ставится на пол витрины, центр — в ноль.
static func make_model(vehicle_id: String) -> Node3D:
	var path := race_scene_path(vehicle_id)
	if path.is_empty():
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("Машина %s: сцена %s не открывается" % [vehicle_id, path])
		return null
	var car := packed.instantiate() as Node3D
	if car == null:
		return null
	var preview := _build_preview(car)
	car.free()
	if preview == null:
		push_warning("Машина %s: в сцене %s нет кузова для витрины" % [vehicle_id, path])
	return preview


static func _build_preview(car: Node3D) -> Node3D:
	var meshes: Array[MeshInstance3D] = []
	for node in car.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh != null and _is_exterior(mesh, car):
			meshes.append(mesh)
	if meshes.is_empty():
		return null
	var box := AABB()
	var first := true
	for mesh in meshes:
		var bounds: AABB = _relative_transform(mesh, car) * mesh.get_aabb()
		if first:
			box = bounds
			first = false
		else:
			box = box.merge(bounds)
	var preview := Node3D.new()
	preview.name = "CarPreview"
	# Смещение входит в трансформы мешей: гараж сбрасывает position корня витрины.
	var center := box.get_center()
	var offset := Vector3(-center.x, -box.position.y, -center.z)
	for mesh in meshes:
		var copy := mesh.duplicate(Node.DUPLICATE_GROUPS) as MeshInstance3D
		var local := _relative_transform(mesh, car)
		copy.transform = Transform3D(local.basis, local.origin + offset)
		preview.add_child(copy)
	var body_name := String(car.get_meta(BODY_META, ""))
	if not body_name.is_empty():
		preview.set_meta(BODY_META, body_name)
	return preview


## Меш входит в витрину, если не спрятан и не лежит внутри узла физики/интерьера.
static func _is_exterior(mesh: MeshInstance3D, car: Node3D) -> bool:
	var current: Node = mesh
	while current != null and current != car:
		if current is Node3D and not (current as Node3D).visible:
			return false
		if PREVIEW_SKIP.has(String(current.name)):
			return false
		current = current.get_parent()
	return true


static func _relative_transform(node: Node, root: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result
