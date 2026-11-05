## Визуальная модель Subaru из сцены, подготовленной для автомобиля.
## Физика, камеры и настройки заезда остаются общими с Mitsubishi.
extends RefCounted

const SUBARU_SCENE := "res://scenes/rally_car2.tscn"
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
	for i in range(wheels.size()):
		for child in mounts[i].get_children():
			if child is VisualInstance3D:
				child.visible = false
		# Preserve imported wheel orientation and size while moving its pivot to
		# the simulated suspension. GEVP then steers, spins and suspends it.
		wheels[i].reparent(mounts[i], true)
		wheels[i].position = Vector3.ZERO
	return true
