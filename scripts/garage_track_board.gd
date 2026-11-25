## 3D-доска выбора трассы внутри витрины гаража.
##
## Каждая трасса — плита с названием на стойке. Наведение мышью и стрелки/D-pad
## двигают подсветку, клик или Enter выбирают трассу. Доска не знает про RallyGame:
## она отдаёт индекс, а гараж решает, что с ним делать.
##
## Положение доски и позу камеры задаёт сцена garage_showroom.tscn (узел TrackBoard):
## двигайте его в 3D-редакторе, а позу камеры при выборе меняйте в инспекторе.
class_name GarageTrackBoard
extends Node3D

## Подсветка сменилась (наведение, стрелки или первый показ).
signal focus_changed(index: int)
## Трасса выбрана (клик или Enter).
signal track_chosen(index: int)

## Расстояние между плитами по горизонтали, м.
@export_range(0.5, 5.0, 0.05, "suffix:м") var pad_spacing: float = 1.7
## Размер плиты: ширина (X) и глубина (Z), м.
@export var pad_size: Vector2 = Vector2(1.5, 0.9)
## Толщина плиты, м.
@export_range(0.02, 0.5, 0.01, "suffix:м") var pad_thickness: float = 0.12
## Высота стойки и названия над плитой, м.
@export_range(0.2, 3.0, 0.05, "suffix:м") var label_height: float = 0.9
## Цвет плиты в покое.
@export var idle_color: Color = Color(0.11, 0.15, 0.19)
## Цвет подсветки выбранной плиты.
@export var highlight_color: Color = Color(1.0, 0.58, 0.08)
## Точка, на которую смотрит камера при выборе (в локальных координатах доски).
@export var camera_target: Vector3 = Vector3(0.0, 0.8, 0.0)
## Где стоит камера относительно camera_target (в локальных координатах доски).
@export var camera_offset: Vector3 = Vector3(0.0, 2.2, 6.5)
## Радиус клика по плите на экране, пикс. (координаты вьюпорта витрины).
@export_range(20.0, 300.0, 1.0, "suffix:px") var pick_radius_px: float = 110.0

## Индекс подсвеченной трассы.
var focus_index: int = 0

var _materials: Array[StandardMaterial3D] = []
var _pad_nodes: Array[Node3D] = []
var _pads_root: Node3D = null


## Построить плиты по списку названий трасс. Гараж вызывает при каждом открытии.
func build(track_names: PackedStringArray, start_index: int) -> void:
	if _pads_root != null:
		remove_child(_pads_root)
		_pads_root.queue_free()
	_pads_root = Node3D.new()
	_pads_root.name = "Pads"
	add_child(_pads_root)
	_materials.clear()
	_pad_nodes.clear()
	var count: int = track_names.size()
	for i in range(count):
		var pad := Node3D.new()
		pad.name = "Pad_%d" % i
		pad.position = Vector3((float(i) - float(count - 1) * 0.5) * pad_spacing, 0.0, 0.0)
		_pads_root.add_child(pad)

		var box := BoxMesh.new()
		box.size = Vector3(pad_size.x, pad_thickness, pad_size.y)
		var material := StandardMaterial3D.new()
		material.albedo_color = idle_color
		material.roughness = 0.55
		material.emission_enabled = true
		material.emission = highlight_color
		material.emission_energy_multiplier = 0.0
		var mesh := MeshInstance3D.new()
		mesh.name = "Plate"
		mesh.mesh = box
		mesh.material_override = material
		mesh.position = Vector3(0.0, pad_thickness * 0.5, 0.0)
		pad.add_child(mesh)
		_materials.append(material)

		var label := Label3D.new()
		label.name = "Name"
		label.text = track_names[i]
		label.font_size = 36
		label.pixel_size = 0.004
		label.width = pad_size.x / 0.004
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.outline_size = 10
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(0.0, label_height, 0.0)
		pad.add_child(label)
		_pad_nodes.append(pad)
	set_focus(clampi(start_index, 0, maxi(0, count - 1)))


## Подсветить трассу (без сигнала, если она уже подсвечена).
func set_focus(index: int) -> void:
	if _materials.is_empty():
		return
	var next: int = clampi(index, 0, _materials.size() - 1)
	var changed: bool = next != focus_index or _materials[next].albedo_color != highlight_color
	focus_index = next
	for i in range(_materials.size()):
		var lit: bool = i == focus_index
		_materials[i].albedo_color = highlight_color if lit else idle_color
		_materials[i].emission_energy_multiplier = 0.8 if lit else 0.0
	if changed:
		focus_changed.emit(focus_index)


## Сдвинуть подсветку стрелками (step = -1 или +1), по кругу.
func step_focus(step: int) -> void:
	if _materials.is_empty():
		return
	set_focus(posmod(focus_index + step, _materials.size()))


## Выбрать подсвеченную трассу (Enter, геймпад, клик без попадания в плиту).
func choose_focused() -> void:
	track_chosen.emit(focus_index)


## Какая плита под точкой экрана (координаты вьюпорта), или -1.
func pick(camera: Camera3D, viewport_point: Vector2) -> int:
	if camera == null or _pad_nodes.is_empty():
		return -1
	var best: int = -1
	var best_distance: float = pick_radius_px
	for i in range(_pad_nodes.size()):
		var world: Vector3 = _pad_nodes[i].global_position + Vector3(0.0, label_height * 0.5, 0.0)
		if camera.is_position_behind(world):
			continue
		var distance: float = camera.unproject_position(world).distance_to(viewport_point)
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


## Цель камеры при выборе трассы — в координатах родителя доски (витрины).
func camera_pose_target() -> Vector3:
	return transform * camera_target


## Направление и расстояние камеры от цели — в координатах родителя доски.
func camera_pose_offset() -> Vector3:
	return transform.basis * camera_offset
