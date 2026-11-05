## Визуальная модель Subaru из сцены, подготовленной для автомобиля.
## Физика, камеры и настройки заезда остаются общими с Mitsubishi.
extends RefCounted

const SUBARU_SCENE := "res://scenes/rally_car2.tscn"
## Салон Subaru — отдельная сцена со своей геометрией и приборами.
const SUBARU_COCKPIT_SCENE := "res://scenes/subaru_cockpit.tscn"
## Как называется салон Lancer в сцене машины. Его нужно спрятать, иначе
## из кабины Subaru видна приборка Mitsubishi.
const LANCER_COCKPIT := "RallyCockpit"
const SUBARU_COCKPIT := "SubaruCockpit"
const SUBARU_WHEELS := ["3DWheel Front L_6", "3DWheel Front R_15", "3DWheel Rear L_24", "3DWheel Rear R_33"]
const WHEEL_MOUNTS := ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]

static func make_subaru() -> Node3D:
	var scene := load(SUBARU_SCENE) as PackedScene
	if scene == null:
		push_warning("Subaru: сцена модели не найдена")
		return null
	var source := scene.instantiate()
	var model := source.get_node_or_null("Sketchfab_Scene") as Node3D
	if model != null:
		source.remove_child(model)
		for wheel_name in SUBARU_WHEELS:
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


static func install_subaru(car: Node3D) -> bool:
	var model := make_subaru()
	if model == null:
		return false
	# Check the entire mapping before changing the existing car, so a broken
	# imported model safely falls back to the original vehicle.
	var wheels: Array[Node3D] = []
	var mounts: Array[Node3D] = []
	for i in range(SUBARU_WHEELS.size()):
		var wheel := model.find_child(SUBARU_WHEELS[i], true, false) as Node3D
		var mount := car.get_node_or_null(WHEEL_MOUNTS[i] + "/WheelVisual") as Node3D
		if wheel == null or mount == null:
			push_warning("Subaru: не найдены колёса или крепления")
			model.free()
			return false
		wheels.append(wheel)
		mounts.append(mount)
	car.add_child(model)
	var old_model := car.get_node_or_null("low poly lance evo") as Node3D
	if old_model != null:
		old_model.visible = false
	install_cockpit(car)
	for i in range(wheels.size()):
		for child in mounts[i].get_children():
			if child is VisualInstance3D:
				child.visible = false
		# Preserve imported wheel orientation and size while moving its pivot to
		# the simulated suspension. GEVP then steers, spins and suspends it.
		wheels[i].reparent(mounts[i], true)
		wheels[i].position = Vector3.ZERO
	return true


## Меняет салон Lancer на салон Impreza. Сцена машины остаётся общей, поэтому
## приборка Mitsubishi просто скрывается: её узлы (магнитола, брелок) остаются
## в дереве и продолжают работать, но в кабине Subaru их не видно.
static func install_cockpit(car: Node3D) -> bool:
	var lancer := car.get_node_or_null(LANCER_COCKPIT) as Node3D
	if lancer != null:
		lancer.visible = false
		lancer.process_mode = Node.PROCESS_MODE_DISABLED
	var existing := car.get_node_or_null(SUBARU_COCKPIT) as Node3D
	if existing != null:
		existing.visible = true
		existing.process_mode = Node.PROCESS_MODE_INHERIT
		return true
	if not ResourceLoader.exists(SUBARU_COCKPIT_SCENE):
		push_warning("Subaru: сцена салона не найдена")
		return false
	var scene := load(SUBARU_COCKPIT_SCENE) as PackedScene
	if scene == null:
		push_warning("Subaru: не удалось загрузить сцену салона")
		return false
	var cockpit := scene.instantiate() as Node3D
	if cockpit == null:
		return false
	cockpit.name = SUBARU_COCKPIT
	# Импортированный салон Subaru — это только приборный щиток: сидений,
	# каркаса и руля в модели нет. Если оставить их, из кабины видно
	# «пустой» кузов и торчащий щиток. Скрываем интерьер модели, оставляя
	# стёкла: свой салон рисует отдельная сцена.
	hide_model_interior(car)
	car.add_child(cockpit)
	return true


## Прячет интерьерные меши импортированной модели Subaru.
## Только внутренние детали (MAT_Details_INT) — кузов, стёкла и колёса
## остаются как есть.
static func hide_model_interior(car: Node3D) -> void:
	var model := car.get_node_or_null("Sketchfab_Scene") as Node3D
	if model == null:
		return
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null:
			continue
		if _is_interior_mesh(mesh_instance):
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
