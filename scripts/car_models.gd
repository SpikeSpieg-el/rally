## Кузов и колёса машины по её ресурсу (res://data/vehicles/*.tres).
## Физика, камеры и настройки заезда общие: у машин разное только то, что
## описано в ресурсе — модель, меши колёс и звук мотора.
extends RefCounted

const CONFIG_PATH := "res://data/rally_game_config.tres"
## Кузов сцены заезда: его прячем, когда у машины своя модель.
const SCENE_BODY := "low poly lance evo"
const WHEEL_MOUNTS := ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]


## Ресурс машины по id. Прямой запуск сцены (F6) читает реестр сам.
static func vehicle(vehicle_id: String) -> RallyVehicle:
	if vehicle_id.is_empty():
		return null
	var config := _game_config()
	if config == null:
		return null
	return config.vehicle(vehicle_id)


static func _game_config() -> RallyGameConfig:
	var loop := Engine.get_main_loop() as SceneTree
	var game: Node = loop.root.get_node_or_null("RallyGame") if loop != null else null
	if game != null and "config" in game:
		var loaded := game.get("config") as RallyGameConfig
		if loaded != null:
			return loaded
	if ResourceLoader.exists(CONFIG_PATH):
		return load(CONFIG_PATH) as RallyGameConfig
	return null


## Модель кузова машины для витрины гаража: только кузов, без физики.
## Машина без своей модели возвращает null — витрина покажет кузов сцены.
static func make_model(vehicle_id: String) -> Node3D:
	var data := vehicle(vehicle_id)
	if data == null or data.model_scene.is_empty():
		return null
	var scene := load(data.model_scene) as PackedScene
	if scene == null:
		push_warning("Машина %s: сцена модели не найдена" % vehicle_id)
		return null
	var source := scene.instantiate()
	var model: Node3D = null
	if data.model_root.is_empty():
		model = source as Node3D
	else:
		model = source.get_node_or_null(data.model_root) as Node3D
		if model != null:
			source.remove_child(model)
	if model == null:
		push_warning("Машина %s: в сцене модели нет узла %s" % [vehicle_id, data.model_root])
		source.free()
		return null
	for wheel_name in data.wheel_names:
		var wheel := model.find_child(wheel_name, true, false) as Node3D
		if wheel != null:
			_show_wheel_parts(wheel)
	source.free()
	return model


static func _show_wheel_parts(node: Node) -> void:
	# The authored scene has several parts of the front-left wheel hidden.
	# Reveal the complete imported wheel, not just its parent pivot.
	if node is Node3D:
		node.visible = true
	for child in node.get_children():
		_show_wheel_parts(child)


## Меняет кузов машины заезда на кузов из ресурса. Возвращает false и
## оставляет машину как есть, если модель или колёса не сошлись.
static func install(car: Node3D, vehicle_id: String) -> bool:
	var data := vehicle(vehicle_id)
	if data == null or data.model_scene.is_empty():
		return false
	var model := make_model(vehicle_id)
	if model == null:
		return false

	# Имена колёс и крепления проверяем до любых изменений машины: битая
	# модель должна безопасно оставить кузов сцены, а не полмашины.
	var wheels: Array[Node3D] = []
	var mounts: Array[Node3D] = []
	for i in range(mini(data.wheel_names.size(), WHEEL_MOUNTS.size())):
		var wheel := model.find_child(data.wheel_names[i], true, false) as Node3D
		var mount := car.get_node_or_null(WHEEL_MOUNTS[i] + "/WheelVisual") as Node3D
		if wheel == null or mount == null:
			push_warning("Машина %s: не найдены колёса или крепления" % vehicle_id)
			model.free()
			return false
		wheels.append(wheel)
		mounts.append(mount)

	car.add_child(model)
	if data.hide_scene_body:
		var old_model := car.get_node_or_null(SCENE_BODY) as Node3D
		if old_model != null:
			old_model.visible = false
	if data.hide_model_interior:
		hide_model_interior(model)
	for i in range(wheels.size()):
		for child in mounts[i].get_children():
			if child is VisualInstance3D:
				child.visible = false
		# Preserve imported wheel orientation and size while moving its pivot to
		# the simulated suspension. GEVP then steers, spins and suspends it.
		wheels[i].reparent(mounts[i], true)
		wheels[i].position = Vector3.ZERO
	return true


## Прячет интерьерные меши импортированной модели: у некоторых моделей
## салона нет вовсе, и его рисует отдельная сцена.
static func hide_model_interior(model: Node3D) -> void:
	if model == null:
		return
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null and _is_interior_mesh(mesh_instance):
			mesh_instance.visible = false


static func _is_interior_mesh(mesh: MeshInstance3D) -> bool:
	var path := String(mesh.get_path()).to_upper()
	if path.contains("MAT_DETAILS_INT") or path.contains("SM_INTERIOR"):
		return true
	var mesh_resource := mesh.mesh
	if mesh_resource == null:
		return false
	for i in range(mesh_resource.get_surface_count()):
		var material := mesh_resource.surface_get_material(i)
		if material == null:
			continue
		if String(material.resource_name).to_upper().contains("INT"):
			return true
	return false
