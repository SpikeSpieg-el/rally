## 3D-доска выбора трассы внутри витрины гаража.
##
## Геометрия целиком в сцене garage_showroom.tscn, узел TrackBoard → Pads:
## каждый дочерний Pad_N — одна плита с подписью (Plate и Name). Порядок узлов в
## дереве = порядок трасс в списке гаража. Положение и размер плит, шрифт и
## высоту подписей меняйте прямо в 3D-редакторе. Подписи берутся из названий
## трасс (RallyTrackConfig.display_name), поэтому текст узла Name в сцене —
## только заглушка для предпросмотра.
##
## Наведение мышью и стрелки/D-pad двигают подсветку, клик или Enter выбирают
## трассу. Доска не знает про RallyGame: она отдаёт индекс, гараж решает, что с ним делать.
class_name GarageTrackBoard
extends Node3D

## Подсветка сменилась (наведение, стрелки или первый показ).
signal focus_changed(index: int)
## Трасса выбрана (клик или Enter).
signal track_chosen(index: int)

## Цвет плиты в покое.
@export var idle_color: Color = Color(0.11, 0.15, 0.19)
## Цвет подсветки выбранной плиты.
@export var highlight_color: Color = Color(1.0, 0.58, 0.08)
## Точка, на которую смотрит камера при выборе (в локальных координатах доски).
@export var camera_target: Vector3 = Vector3(0.0, 0.9, 0.0)
## Где стоит камера относительно camera_target (в локальных координатах доски).
## Чем дальше, тем шире кадр: подберите так, чтобы вся доска влезала.
@export var camera_offset: Vector3 = Vector3(0.0, 2.7, 12.5)
## Радиус клика по подписи на экране, пикс. (координаты вьюпорта витрины).
@export_range(20.0, 300.0, 1.0, "suffix:px") var pick_radius_px: float = 110.0

## Индекс подсвеченной трассы.
var focus_index: int = 0

## Плиты, подписи и их материалы в порядке дерева Pads.
var _pads: Array[Node3D] = []
var _labels: Array[Label3D] = []
var _materials: Array[StandardMaterial3D] = []
var _track_count: int = 0


func _ready() -> void:
	_collect_pads()


## Собрать плиты из сцены. У каждой плиты свой материал: копия материала из сцены,
## чтобы подсвечивалась только одна.
func _collect_pads() -> void:
	_pads.clear()
	_labels.clear()
	_materials.clear()
	var pads_root: Node = get_node_or_null("Pads")
	if pads_root == null:
		push_warning("GarageTrackBoard: нет узла Pads — добавьте плиты в сцену garage_showroom.tscn")
		return
	for child in pads_root.get_children():
		var pad := child as Node3D
		if pad == null:
			continue
		var plate := pad.get_node_or_null("Plate") as MeshInstance3D
		var label := pad.get_node_or_null("Name") as Label3D
		if plate == null or label == null:
			push_warning("GarageTrackBoard: у %s нет Plate или Name" % pad.name)
			continue
		var material := StandardMaterial3D.new()
		var scene_material := plate.material_override as StandardMaterial3D
		if scene_material != null:
			material = scene_material.duplicate() as StandardMaterial3D
		plate.material_override = material
		_pads.append(pad)
		_labels.append(label)
		_materials.append(material)


## Показать плиты для списка трасс. Гараж вызывает при каждом открытии.
## Лишние плиты в сцене скрываются, нехватка плит — предупреждение в лог.
func build(track_names: PackedStringArray, start_index: int) -> void:
	_track_count = mini(track_names.size(), _pads.size())
	if track_names.size() > _pads.size():
		push_warning("GarageTrackBoard: трасс %d, а плит в сцене %d — добавьте Pad_N в Pads" % [track_names.size(), _pads.size()])
	for i in range(_pads.size()):
		_pads[i].visible = i < _track_count
		if i < _track_count:
			_labels[i].text = track_names[i]
	set_focus(clampi(start_index, 0, maxi(0, _track_count - 1)))


## Подсветить трассу (без сигнала, если она уже подсвечена).
func set_focus(index: int) -> void:
	if _track_count <= 0:
		return
	var next: int = clampi(index, 0, _track_count - 1)
	var changed: bool = next != focus_index or _materials[next].albedo_color != highlight_color
	focus_index = next
	for i in range(_track_count):
		var lit: bool = i == focus_index
		_materials[i].albedo_color = highlight_color if lit else idle_color
		_materials[i].emission_enabled = true
		_materials[i].emission = highlight_color
		_materials[i].emission_energy_multiplier = 0.8 if lit else 0.0
	if changed:
		focus_changed.emit(focus_index)


## Сдвинуть подсветку стрелками (step = -1 или +1), по кругу.
func step_focus(step: int) -> void:
	if _track_count <= 0:
		return
	set_focus(posmod(focus_index + step, _track_count))


## Выбрать подсвеченную трассу (Enter, геймпад, клик без попадания в плиту).
func choose_focused() -> void:
	track_chosen.emit(focus_index)


## Какая плита под точкой экрана (координаты вьюпорта), или -1.
func pick(camera: Camera3D, viewport_point: Vector2) -> int:
	if camera == null or _track_count <= 0:
		return -1
	var best: int = -1
	var best_distance: float = pick_radius_px
	for i in range(_track_count):
		var world: Vector3 = _labels[i].global_position
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
