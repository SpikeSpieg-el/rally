## Сборка машин из glb-кузовов прямо в редакторе Godot.
##
## Как пользоваться: положите файл кузова в папку cars/ (например cars/ferrari.glb).
## При открытии проекта и после каждого импорта glb плагин сам создаёт:
##   • модель машины scenes/vehicles/<id>_model.tscn — кузов и четыре колеса;
##   • ресурс машины data/vehicles/<id>.tres — подгонка кузова и звук мотора;
##   • пять пресетов data/setups/<id>/ — стоковый, гравий, снег, асфальт, гравий SPEC;
##   • регистрацию машины и пресетов в data/rally_game_config.tres.
##
## Уже созданное не перезаписывается: дальше правьте ресурсы в инспекторе.
## Чтобы пересобрать модель после смены подгонки, включите rebuild_model у машины.
## Если сборка не сошлась, файлы этой машины удаляются, а конфиг не меняется.
@tool
extends RefCounted

const CARS_DIR := "res://cars/"
const VEHICLES_DIR := "res://data/vehicles/"
const SETUPS_DIR := "res://data/setups/"
const MODELS_DIR := "res://scenes/vehicles/"
const CONFIG_PATH := "res://data/rally_game_config.tres"
const RALLY_CAR_SCENE := "res://scenes/rally_car.tscn"
## Шаблон двигателя: новая машина берёт звук и сетку оборотов отсюда.
const TEMPLATE_VEHICLE := "res://data/vehicles/mitsubishi.tres"
const BODY_META := "car_body_mesh"
const WHEEL_NAMES := ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]
## Процедурная шина: радиус как у стокового колеса (rally_car.gd, wheel_visual_radius).
const TIRE_RADIUS := 0.438
const TIRE_WIDTH := 0.245
const RIM_RADIUS := 0.29
## Запас оборотов над верхней точкой сетки двигателя.
const RPM_HEADROOM := 200.0
const DEFAULT_RPM_TOP := 6800.0
const WAIT := "__wait__"

## Общие значения пресетов. Пресет переопределяет только свои поля.
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


## Точка входа: вызывается плагином при открытии проекта и после импорта.
static func run() -> void:
	if not Engine.is_editor_hint():
		return
	if not DirAccess.dir_exists_absolute(CARS_DIR):
		return
	var dir := DirAccess.open(CARS_DIR)
	if dir == null:
		return
	var files := Array(dir.get_files())
	files.sort()
	for file: String in files:
		if not file.to_lower().ends_with(".glb"):
			continue
		var glb_path := CARS_DIR + file
		# Пока редактор не импортировал кузов, .import ещё нет: ждём следующего запуска.
		if not FileAccess.file_exists(glb_path + ".import"):
			continue
		var id := car_id_for(file)
		if not _valid_id(id):
			push_error("[Машины] %s: имя файла должно быть латиницей, цифрами и _" % file)
			continue
		var vehicle_path := VEHICLES_DIR + id + ".tres"
		var message := ""
		if ResourceLoader.exists(vehicle_path):
			message = _rebuild_if_requested(id, vehicle_path, glb_path)
		else:
			message = _create_car(id, glb_path)
		if message == WAIT or message.is_empty():
			continue
		push_error("[Машины] %s: %s" % [id, message])


## Идентификатор машины из имени файла: строчные буквы, пробелы — в _.
static func car_id_for(file: String) -> String:
	return file.get_basename().to_lower().replace(" ", "_").replace("-", "_")


static func _valid_id(id: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[a-z][a-z0-9_]*$")
	return regex.search(id) != null


## Новая машина: создаёт все ресурсы и регистрирует её. Возвращает текст ошибки
## (пусто — успех, WAIT — кузов ещё не импортирован).
static func _create_car(id: String, glb_path: String) -> String:
	var model_path := MODELS_DIR + id + "_model.tscn"
	var setup_dir := SETUPS_DIR + id + "/"
	if ResourceLoader.exists(model_path):
		return "файл модели %s уже есть — переименуйте кузов" % model_path
	var glb := ResourceLoader.load(glb_path) as PackedScene
	if glb == null:
		return WAIT
	var template := ResourceLoader.load(TEMPLATE_VEHICLE) as RallyVehicle
	if template == null:
		return "нет шаблона машины %s" % TEMPLATE_VEHICLE
	var vehicle := RallyVehicle.new()
	_fill_vehicle(vehicle, id, template)
	var created: Array[String] = []
	var setup_dir_created := not DirAccess.dir_exists_absolute(setup_dir)
	var message := _write_car(id, glb, glb_path, vehicle, created)
	if message.is_empty():
		print("[Машины] создана «%s» из %s" % [vehicle.display_name, glb_path])
		return ""
	_remove_files(created)
	if setup_dir_created:
		_remove_dir_if_empty(setup_dir)
	return message


## Пишет все ресурсы машины и регистрирует её в конфиге. Каждый созданный файл
## добавляется в created, чтобы его можно было удалить при ошибке.
static func _write_car(id: String, glb: PackedScene, glb_path: String, vehicle: RallyVehicle, created: Array[String]) -> String:
	var model_path := MODELS_DIR + id + "_model.tscn"
	var vehicle_path := VEHICLES_DIR + id + ".tres"
	var setup_dir := SETUPS_DIR + id + "/"
	var errors: Array[String] = []
	var packed := _build_model(id, glb, glb_path, vehicle, errors)
	if packed == null:
		return errors[0] if not errors.is_empty() else "не удалось собрать модель"
	vehicle.model_scene = model_path
	if ResourceSaver.save(packed, model_path) != OK:
		return "не записалась модель %s" % model_path
	created.append(model_path)

	DirAccess.make_dir_recursive_absolute(setup_dir)
	var setup_ids: Array[String] = []
	var setups: Array[Resource] = []
	for preset: Dictionary in PRESETS:
		var setup := _make_setup(id, vehicle, preset)
		var setup_path: String = setup_dir + id + "_" + String(preset["key"]) + ".tres"
		if ResourceSaver.save(setup, setup_path) != OK:
			return "не записался пресет %s" % setup_path
		created.append(setup_path)
		setup_ids.append(setup.id)
		setups.append(setup)
	vehicle.setup_ids = setup_ids
	if ResourceSaver.save(vehicle, vehicle_path) != OK:
		return "не записалась машина %s" % vehicle_path
	created.append(vehicle_path)

	var check := _check_saved(model_path, vehicle_path)
	if not check.is_empty():
		return check

	var config := ResourceLoader.load(CONFIG_PATH) as RallyGameConfig
	if config == null:
		return "не открылся конфиг %s" % CONFIG_PATH
	for existing in config.vehicles:
		if existing != null and String(existing.get("id")) == id:
			return "машина «%s» уже есть в конфиге" % id
	config.vehicles.append(vehicle)
	for setup in setups:
		config.all_setups.append(setup)
	if ResourceSaver.save(config, CONFIG_PATH) != OK:
		config.vehicles.erase(vehicle)
		for setup in setups:
			config.all_setups.erase(setup)
		return "не записался конфиг %s" % CONFIG_PATH
	return ""


## Перечитывает сохранённые модель и машину: колёса на месте, пути живые.
static func _check_saved(model_path: String, vehicle_path: String) -> String:
	var model := ResourceLoader.load(model_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if model == null:
		return "модель %s не читается" % model_path
	var vehicle := ResourceLoader.load(vehicle_path, "", ResourceLoader.CACHE_MODE_IGNORE) as RallyVehicle
	if vehicle == null:
		return "машина %s не читается" % vehicle_path
	var instance := model.instantiate()
	var missing: Array[String] = []
	for wheel_name in vehicle.wheel_names:
		if instance.find_child(String(wheel_name), true, false) == null:
			missing.append(String(wheel_name))
	instance.free()
	if not missing.is_empty():
		return "в модели нет колёс: %s" % ", ".join(PackedStringArray(missing))
	if not vehicle.engine_dir.is_empty() and not DirAccess.dir_exists_absolute(vehicle.engine_dir):
		return "нет папки звука %s" % vehicle.engine_dir
	return ""


## Пересборка по флагу rebuild_model. Возвращает текст ошибки или пусто.
static func _rebuild_if_requested(id: String, vehicle_path: String, glb_path: String) -> String:
	var vehicle := ResourceLoader.load(vehicle_path) as RallyVehicle
	if vehicle == null or not vehicle.rebuild_model:
		return ""
	var glb := ResourceLoader.load(glb_path) as PackedScene
	if glb == null:
		return WAIT
	var errors: Array[String] = []
	var packed := _build_model(id, glb, glb_path, vehicle, errors)
	if packed == null:
		return errors[0] if not errors.is_empty() else "не удалось собрать модель"
	var model_path := vehicle.model_scene
	if model_path.is_empty():
		model_path = MODELS_DIR + id + "_model.tscn"
	vehicle.model_scene = model_path
	if ResourceSaver.save(packed, model_path) != OK:
		return "не записалась модель %s" % model_path
	vehicle.rebuild_model = false
	if ResourceSaver.save(vehicle, vehicle_path) != OK:
		return "не записалась машина %s" % vehicle_path
	print("[Машины] модель «%s» пересобрана" % vehicle.display_name)
	return ""


static func _fill_vehicle(vehicle: RallyVehicle, id: String, template: RallyVehicle) -> void:
	vehicle.id = id
	vehicle.display_name = id.to_upper().replace("_", " ")
	vehicle.model_root = ""
	vehicle.uses_livery_presets = false
	vehicle.engine_dir = template.engine_dir
	vehicle.engine_rpm_grid = template.engine_rpm_grid.duplicate()
	vehicle.engine_events_dir = template.engine_events_dir
	vehicle.engine_trim_db = template.engine_trim_db
	vehicle.engine_event_pitch = template.engine_event_pitch


static func _make_setup(id: String, vehicle: RallyVehicle, preset: Dictionary) -> RallyCarSetup:
	var setup := RallyCarSetup.new()
	setup.id = "%s_%s" % [id, String(preset["key"])]
	setup.display_name = "%s · %s" % [vehicle.display_name, String(preset["name"])]
	setup.description = String(preset["desc"])
	setup.engine_name = "%s · МОТОР" % vehicle.display_name
	setup.drivetrain = RallyCarSetup.Drivetrain.AWD
	var values := BASE_SETUP.duplicate()
	values["max_rpm"] = _rpm_top(vehicle) + RPM_HEADROOM
	values.merge(preset["set"] as Dictionary, true)
	for key: String in values:
		setup.set(key, values[key])
		if setup.get(key) == null:
			push_error("[Машины] у RallyCarSetup нет поля %s" % key)
	return setup


static func _rpm_top(vehicle: RallyVehicle) -> float:
	if vehicle.engine_rpm_grid.is_empty():
		return DEFAULT_RPM_TOP
	return float(vehicle.engine_rpm_grid[vehicle.engine_rpm_grid.size() - 1])


## Собирает сцену модели: кузов из glb, подгонка по размеру и колёса.
## Колёса берутся из glb (узлы Wheel_*), иначе создаются процедурно на точках
## крепления физики из rally_car.tscn. Пишет wheel_names в машину.
static func _build_model(id: String, glb: PackedScene, glb_path: String, vehicle: RallyVehicle, errors: Array[String]) -> PackedScene:
	var body := glb.instantiate() as Node3D
	if body == null:
		errors.append("кузов %s не открывается" % glb_path)
		return null
	body.name = "Body"
	var meshes: Array[MeshInstance3D] = []
	_collect_body_meshes(body, meshes)
	if meshes.is_empty():
		body.free()
		errors.append("в %s нет ни одного меша кузова" % glb_path)
		return null
	var body_mesh_name := ""
	var biggest := -1.0
	for mesh in meshes:
		var volume := mesh.get_aabb().get_volume()
		if volume > biggest:
			biggest = volume
			body_mesh_name = String(mesh.name)
	var box := _bounds(meshes, body)
	var mounts := _mount_positions()
	if mounts.size() != WHEEL_NAMES.size():
		body.free()
		errors.append("в rally_car.tscn не найдены точки крепления колёс")
		return null

	var rotate_deg := vehicle.body_rotate_deg
	if rotate_deg < 0.0:
		rotate_deg = 90.0 if box.size.x > box.size.z else 0.0
	var turn := Basis(Vector3.UP, deg_to_rad(rotate_deg))
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in 8:
		var corner: Vector3 = turn * box.get_endpoint(i)
		lo = lo.min(corner)
		hi = hi.max(corner)
	var length := hi.z - lo.z
	if length <= 0.01:
		body.free()
		errors.append("кузов %s пустой или плоский" % glb_path)
		return null
	var scale_factor := vehicle.body_scale if vehicle.body_scale > 0.0 else vehicle.body_length_m / length
	var mid := (lo + hi) * 0.5
	var center_z: float = (float(mounts["Wheel_FL"].z) + float(mounts["Wheel_RL"].z)) * 0.5
	var origin := Vector3(-mid.x * scale_factor, vehicle.ground_clearance - lo.y * scale_factor, center_z - mid.z * scale_factor)
	origin += vehicle.body_offset
	body.transform = Transform3D(turn.scaled(Vector3.ONE * scale_factor), origin)

	var root := Node3D.new()
	root.name = "Model"
	root.set_meta(BODY_META, body_mesh_name)
	root.add_child(body)
	body.owner = root

	var wheel_names: Array[String] = []
	if _has_glb_wheels(body):
		for wheel_name in WHEEL_NAMES:
			wheel_names.append(wheel_name)
	else:
		_add_procedural_wheels(root, mounts, wheel_names)
	vehicle.wheel_names = wheel_names

	var packed := PackedScene.new()
	var err := packed.pack(root)
	root.free()
	if err != OK:
		errors.append("модель %s не упаковалась: код %d" % [id, err])
		return null
	return packed


static func _add_procedural_wheels(root: Node3D, mounts: Dictionary, names: Array[String]) -> void:
	var tire_mesh := CylinderMesh.new()
	tire_mesh.top_radius = TIRE_RADIUS
	tire_mesh.bottom_radius = TIRE_RADIUS
	tire_mesh.height = TIRE_WIDTH
	var tire_material := StandardMaterial3D.new()
	tire_material.albedo_color = Color(0.09, 0.09, 0.10, 1.0)
	tire_material.roughness = 0.9
	var rim_mesh := CylinderMesh.new()
	rim_mesh.top_radius = RIM_RADIUS
	rim_mesh.bottom_radius = RIM_RADIUS
	rim_mesh.height = TIRE_WIDTH + 0.01
	var rim_material := StandardMaterial3D.new()
	rim_material.albedo_color = Color(0.72, 0.74, 0.78, 1.0)
	rim_material.metallic = 0.6
	rim_material.roughness = 0.35
	# Цилиндр лежит вдоль оси X: ось колеса совпадает с осью крепления.
	var lay_flat := Basis(Vector3(0.0, 0.0, 1.0), PI * 0.5)
	for wheel_name in WHEEL_NAMES:
		var holder := Node3D.new()
		holder.name = wheel_name + "_Model"
		holder.position = mounts[wheel_name]
		root.add_child(holder)
		holder.owner = root
		var tire := MeshInstance3D.new()
		tire.name = "Tire"
		tire.mesh = tire_mesh
		tire.material_override = tire_material
		tire.transform = Transform3D(lay_flat, Vector3.ZERO)
		holder.add_child(tire)
		tire.owner = root
		var rim := MeshInstance3D.new()
		rim.name = "Rim"
		rim.mesh = rim_mesh
		rim.material_override = rim_material
		rim.transform = Transform3D(lay_flat, Vector3.ZERO)
		holder.add_child(rim)
		rim.owner = root
		names.append(String(holder.name))


static func _has_glb_wheels(body: Node3D) -> bool:
	for wheel_name in WHEEL_NAMES:
		if body.find_child(wheel_name, true, false) == null:
			return false
	return true


## Точки крепления колёс физики — из rally_car.tscn, общие для всех машин.
static func _mount_positions() -> Dictionary:
	var result := {}
	var scene := ResourceLoader.load(RALLY_CAR_SCENE) as PackedScene
	if scene == null:
		return result
	var car := scene.instantiate()
	for wheel_name in WHEEL_NAMES:
		var node := car.get_node_or_null(wheel_name) as Node3D
		if node != null:
			result[wheel_name] = node.position
	car.free()
	return result


static func _collect_body_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if String(child.name).begins_with("Wheel_"):
			continue
		if child is MeshInstance3D:
			out.append(child as MeshInstance3D)
		_collect_body_meshes(child, out)


## Общий объём мешей кузова в системе координат кузова.
static func _bounds(meshes: Array[MeshInstance3D], root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh in meshes:
		var local := _relative_transform(mesh, root)
		var aabb := mesh.get_aabb()
		for i in 8:
			var point: Vector3 = local * aabb.get_endpoint(i)
			if first:
				box = AABB(point, Vector3.ZERO)
				first = false
			else:
				box = box.expand(point)
	return box


static func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


static func _remove_files(paths: Array[String]) -> void:
	for path in paths:
		var folder := DirAccess.open(path.get_base_dir())
		if folder != null:
			folder.remove(path.get_file())


static func _remove_dir_if_empty(path: String) -> void:
	var trimmed := path.trim_suffix("/")
	var parent := DirAccess.open(trimmed.get_base_dir())
	if parent != null:
		parent.remove(trimmed.get_file())
