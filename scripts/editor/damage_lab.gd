## Лаборатория деформации кузова. Откройте сцену и нажмите F6.
##
## Отдельная тестовая сцена для проверки и показа вмятин без заезда: кузов
## стоит на месте, а удары наносятся кликом по кузову или кнопками по зонам.
## Работает на Lancer и на любом другом кузове из реестра (Golf, Subaru),
## а также на произвольной сцене, назначенной в поле custom_car_scene.
##
## Деформация — тот же компонент, что в игре (CarDamageVisual), настройка —
## тот же ресурс (RallyDamageVisualConfig): поле damage_config в инспекторе
## или data/car/default_damage_visual.tres. Ресурс при запуске дублируется,
## поэтому эксперименты в лаборатории не меняют игровую настройку.
##
## Управление: ЛКМ по кузову — вмятина в точке клика, перетаскивание — камера,
## колесо — зум, R — ремонт, 1/2/3 — смена кузова, Пробел — случайный удар.
class_name DamageLab
extends Node3D

const CarModels = preload("res://scripts/car_models.gd")
const DEFAULT_DAMAGE_PATH := "res://data/car/default_damage_visual.tres"
## Машины реестра в порядке enum'а vehicle_index (data/vehicles/*.tres).
const VEHICLE_IDS: Array[String] = ["mitsubishi", "golf", "subaru"]
const VEHICLE_TITLES: Array[String] = ["Lancer", "Golf", "Subaru"]
## Слой коллайдера-подборщика: только для кликов лаборатории, физике игры не виден.
const PICKER_LAYER := 4

@export_group("Кузов")
## Машина из реестра: 0 — Lancer, 1 — Golf, 2 — Subaru. Смена — и в инспекторе,
## и клавишами 1/2/3 во время работы.
@export_enum("Lancer (mitsubishi)", "Golf (golf)", "Subaru (subaru)") var vehicle_index: int = 0
## Любой другой кузов: сцена машины (rally_car*.tscn) или сцена с мешками
## в группе rally_body_fx. Если задано — берётся вместо реестра.
@export var custom_car_scene: PackedScene = null

@export_group("Настройка деформации")
## Пусто — res://data/car/default_damage_visual.tres. Свой экземпляр ресурса
## (дубликат в FileSystem) даёт лаборатории свои числа без правки игры.
@export var damage_config: RallyDamageVisualConfig = null

@export_group("Удар")
## Сила удара, м/с: глубина и радиус вмятины считаются из неё по настройке.
@export_range(1.0, 30.0, 0.5, "suffix:м/с") var impact_dv_mps: float = 12.0
## Автоматические удары по случайным зонам после запуска — для показа.
@export var demo_on_start: bool = false
@export_range(0.3, 5.0, 0.1, "suffix:с") var demo_interval_sec: float = 1.2

@export_group("Камера и показ")
## Медленное вращение камеры вокруг кузова.
@export var auto_rotate: bool = true
@export_range(0.0, 1.0, 0.05) var auto_rotate_speed: float = 0.25
@export_range(3.0, 15.0, 0.1, "suffix:м") var camera_distance: float = 7.5
## Оранжевые маркеры в точках ударов.
@export var show_markers: bool = true
## Панель со статистикой деформации.
@export var show_stats: bool = true

@onready var _camera: Camera3D = $Camera3D
@onready var _model_holder: Node3D = $ModelRoot

var _model_root: Node3D = null
var _damage: CarDamageVisual = null
var _body_aabb: AABB = AABB()
var _has_body_aabb: bool = false
var _yaw: float = 0.7
var _pitch: float = 0.30
var _distance: float = 7.5
var _markers: Array[Dictionary] = []
var _demo_enabled: bool = false
var _demo_timer: float = 0.0
var _pressing: bool = false
var _dragging: bool = false
var _press_pos: Vector2 = Vector2.ZERO
var _stats_label: Label = null
var _vehicle_label: Label = null
var _dv_label: Label = null
var _demo_button: Button = null


func _ready() -> void:
	_distance = camera_distance
	_demo_enabled = demo_on_start
	_build_ui()
	rebuild_body()
	_demo_timer = 0.6


## Собрать кузов заново: модель, коллайдер-подборщик и компонент деформации.
## Вызывается при запуске и при смене кузова (кнопки, клавиши 1/2/3).
func rebuild_body() -> void:
	if _damage != null:
		_damage.queue_free()
		_damage = null
	if _model_root != null:
		_model_root.queue_free()
		_model_root = null
	_markers.clear()
	_has_body_aabb = false
	_model_root = _make_model()
	if _model_root == null:
		push_warning("[DamageLab] кузов не собран: проверьте vehicle_index и custom_car_scene")
		_refresh_stats()
		return
	_model_holder.add_child(_model_root)
	_body_aabb = _compute_body_aabb(_model_root)
	_has_body_aabb = _body_aabb.size.length_squared() > 0.0
	_add_picker(_model_root, _body_aabb)
	_damage = CarDamageVisual.new()
	_damage.name = "DamageVisual"
	add_child(_damage)
	_damage.setup(_model_root, _model_root, _active_config())
	if _damage.panel_count() == 0:
		push_warning("[DamageLab] у кузова нет мешей в группе rally_body_fx — мять нечего")
	_refresh_stats()


## Удар в точке point_space (координаты кузова) по направлению push_dir.
## Возвращает, на сколько выросла суммарная глубина вмятин, метры.
func dent_at(point_space: Vector3, push_dir: Vector3, dv: float) -> float:
	if _damage == null:
		return 0.0
	var before := _damage.total_dent_depth()
	_damage.apply_impact(point_space, push_dir, dv)
	_spawn_marker(point_space)
	_refresh_stats()
	return _damage.total_dent_depth() - before


## Удар по готовой зоне: 0 — спереди, 1 — сзади, 2 — слева, 3 — справа,
## 4 — капот, 5 — крыша. Точки берутся из AABB кузова, поэтому зоны работают
## на любом кузове, а не только на Lancer.
func preset_impact(preset: int) -> float:
	if not _has_body_aabb or _model_root == null:
		return 0.0
	var center := _body_aabb.get_center()
	var extent := _body_aabb.size
	var point := center
	var push := Vector3.ZERO
	match preset:
		0:
			point = Vector3(center.x, center.y, _body_aabb.position.z + extent.z)
			push = Vector3(0.0, 0.0, -1.0)
		1:
			point = Vector3(center.x, center.y, _body_aabb.position.z)
			push = Vector3(0.0, 0.0, 1.0)
		2:
			point = Vector3(_body_aabb.position.x + extent.x, center.y, center.z)
			push = Vector3(-1.0, 0.0, 0.0)
		3:
			point = Vector3(_body_aabb.position.x, center.y, center.z)
			push = Vector3(1.0, 0.0, 0.0)
		4:
			point = Vector3(center.x, _body_aabb.position.y + extent.y, center.z + extent.z * 0.25)
			push = Vector3(0.0, -1.0, 0.0)
		5:
			point = Vector3(center.x, _body_aabb.position.y + extent.y, center.z)
			push = Vector3(0.0, -1.0, 0.0)
		_:
			point = center
			push = Vector3(0.0, 0.0, -1.0)
	return dent_at(point, push, impact_dv_mps)


## Удар по случайной зоне — режим показа и клавиша Пробел.
func random_impact() -> float:
	return preset_impact(randi_range(0, 5))


## Ремонт: вернуть исходную геометрию кузова.
func repair() -> void:
	if _damage != null:
		_damage.clear_damage()
	_refresh_stats()


## Сменить кузов из реестра (0 — Lancer, 1 — Golf, 2 — Subaru).
func set_vehicle_index(index: int) -> void:
	vehicle_index = clampi(index, 0, VEHICLE_IDS.size() - 1)
	custom_car_scene = null
	rebuild_body()


func body_model() -> Node3D:
	return _model_root


func body_aabb() -> AABB:
	return _body_aabb


func panel_count() -> int:
	return 0 if _damage == null else _damage.panel_count()


func total_dent_depth() -> float:
	return 0.0 if _damage == null else _damage.total_dent_depth()


func deformation_stats() -> Dictionary:
	if _damage == null:
		return {"moved_vertices": 0, "centroid_local": Vector3.ZERO, "max_offset_m": 0.0, "panels": 0}
	return _damage.deformation_stats()


func _process(delta: float) -> void:
	if _demo_enabled:
		_demo_timer -= delta
		if _demo_timer <= 0.0:
			random_impact()
			_demo_timer = demo_interval_sec
	_update_markers(delta)
	_update_camera(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if mouse_button.pressed:
				_pressing = true
				_dragging = false
				_press_pos = mouse_button.position
			elif _pressing:
				if not _dragging:
					_click_dent(mouse_button.position)
				_pressing = false
				_dragging = false
		elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button.pressed:
			_distance = clampf(_distance * 0.9, 3.0, 15.0)
		elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button.pressed:
			_distance = clampf(_distance * 1.1, 3.0, 15.0)
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _pressing:
			if not _dragging and motion.position.distance_to(_press_pos) > 6.0:
				_dragging = true
			if _dragging:
				_yaw -= motion.relative.x * 0.01
				_pitch = clampf(_pitch + motion.relative.y * 0.01, -0.2, 1.4)
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			match key_event.keycode:
				KEY_R:
					repair()
				KEY_1:
					set_vehicle_index(0)
				KEY_2:
					set_vehicle_index(1)
				KEY_3:
					set_vehicle_index(2)
				KEY_SPACE:
					random_impact()


## Модель кузова: из реестра через витрину гаража или из произвольной сцены.
func _make_model() -> Node3D:
	if custom_car_scene != null:
		return _model_from_scene(custom_car_scene)
	var index := clampi(vehicle_index, 0, VEHICLE_IDS.size() - 1)
	return CarModels.make_model(VEHICLE_IDS[index])


## Кузов из произвольной сцены: сцена машины (берём её body_model_path) или
## сцена с кузовными мешками. Меши копируются с группами, как в витрине гаража.
func _model_from_scene(packed: PackedScene) -> Node3D:
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return null
	var source: Node3D = inst
	if "body_model_path" in inst:
		var raw: Variant = inst.get("body_model_path")
		if raw is NodePath:
			var path: NodePath = raw
			if not path.is_empty():
				var found := inst.get_node_or_null(path) as Node3D
				if found != null:
					source = found
	var meshes: Array[MeshInstance3D] = []
	for node in source.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := node as MeshInstance3D
		if mesh_inst != null and mesh_inst.mesh != null:
			meshes.append(mesh_inst)
	if meshes.is_empty():
		inst.free()
		return null
	var box := AABB()
	var first := true
	for mesh_inst in meshes:
		var bounds: AABB = _relative_transform(mesh_inst, source) * mesh_inst.mesh.get_aabb()
		if first:
			box = bounds
			first = false
		else:
			box = box.merge(bounds)
	var preview := Node3D.new()
	preview.name = "CustomBody"
	var center := box.get_center()
	var offset := Vector3(-center.x, -box.position.y, -center.z)
	for mesh_inst in meshes:
		var copy := mesh_inst.duplicate(Node.DUPLICATE_GROUPS) as MeshInstance3D
		var local := _relative_transform(mesh_inst, source)
		copy.transform = Transform3D(local.basis, local.origin + offset)
		preview.add_child(copy)
	inst.free()
	return preview


## Активная настройка деформации: дубликат ресурса, чтобы лаборатория не
## портила игровые числа при переборе силы и формы вмятин.
func _active_config() -> RallyDamageVisualConfig:
	var base: RallyDamageVisualConfig = damage_config
	if base == null and ResourceLoader.exists(DEFAULT_DAMAGE_PATH):
		base = ResourceLoader.load(DEFAULT_DAMAGE_PATH) as RallyDamageVisualConfig
	if base == null:
		return RallyDamageVisualConfig.new()
	return base.duplicate() as RallyDamageVisualConfig


## AABB только кузовных панелей (группа rally_body_fx) в координатах модели:
## по нему строятся зоны ударов и коллайдер-подборщик.
func _compute_body_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := node as MeshInstance3D
		if mesh_inst == null or not mesh_inst.is_in_group("rally_body_fx"):
			continue
		if mesh_inst.mesh == null:
			continue
		var local_box: AABB = _relative_transform(mesh_inst, root) * mesh_inst.mesh.get_aabb()
		if first:
			box = local_box
			first = false
		else:
			box = box.merge(local_box)
	return box


## Коллайдер-подборщик по AABB кузова: луч клика даёт точку и нормаль удара.
func _add_picker(root: Node3D, box: AABB) -> void:
	if box.size.length_squared() <= 0.0:
		return
	var picker_body := StaticBody3D.new()
	picker_body.name = "Picker"
	picker_body.collision_layer = PICKER_LAYER
	picker_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box.size
	shape.shape = box_shape
	shape.position = box.get_center()
	picker_body.add_child(shape)
	root.add_child(picker_body)


## Вмятина в точке клика: луч из камеры до коллайдера-подборщика кузова.
func _click_dent(screen_pos: Vector2) -> void:
	if _camera == null or _model_root == null:
		return
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * 100.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = PICKER_LAYER
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var hit_pos: Vector3 = hit["position"]
	var hit_normal: Vector3 = hit["normal"]
	var point_space: Vector3 = _model_root.to_local(hit_pos)
	var push_space: Vector3 = (_model_root.global_transform.basis.inverse() * -hit_normal).normalized()
	dent_at(point_space, push_space, impact_dv_mps)


func _update_camera(delta: float) -> void:
	if _camera == null:
		return
	if auto_rotate and not _dragging:
		_yaw += auto_rotate_speed * delta
	var target := Vector3(0.0, 0.7, 0.0)
	if _has_body_aabb:
		target = _body_aabb.get_center()
	var offset := Vector3(
		sin(_yaw) * cos(_pitch),
		sin(_pitch),
		cos(_yaw) * cos(_pitch)) * _distance
	_camera.global_position = target + offset
	_camera.look_at(target, Vector3.UP)


func _spawn_marker(point_space: Vector3) -> void:
	if not show_markers or _model_root == null:
		return
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.07
	sphere.height = 0.14
	marker.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.15, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = mat
	_model_root.add_child(marker)
	marker.position = point_space
	_markers.append({"node": marker, "material": mat, "life": 0.7})


func _update_markers(delta: float) -> void:
	for i in range(_markers.size() - 1, -1, -1):
		var entry: Dictionary = _markers[i]
		var node := entry["node"] as MeshInstance3D
		var mat := entry["material"] as StandardMaterial3D
		var life := float(entry["life"]) - delta
		if node == null or not is_instance_valid(node) or life <= 0.0:
			if node != null and is_instance_valid(node):
				node.queue_free()
			_markers.remove_at(i)
			continue
		entry["life"] = life
		if mat != null:
			var color := mat.albedo_color
			color.a = clampf(life / 0.7, 0.0, 1.0) * 0.9
			mat.albedo_color = color


func _refresh_stats() -> void:
	if _vehicle_label != null:
		if custom_car_scene != null:
			_vehicle_label.text = "Кузов: %s (custom_car_scene)" % custom_car_scene.resource_path.get_file()
		else:
			var index := clampi(vehicle_index, 0, VEHICLE_IDS.size() - 1)
			_vehicle_label.text = "Кузов: %s (%s)" % [VEHICLE_TITLES[index], VEHICLE_IDS[index]]
	if _stats_label == null:
		return
	if _damage == null:
		_stats_label.text = "Кузов не собран"
		return
	var stats := _damage.deformation_stats()
	var budget := _damage.cfg().dent_budget_m
	_stats_label.text = "Панелей: %d · Ударов: %d\nСуммарная вмятина: %.3f м (запас %.2f м)\nСдвинуто вершин: %d · Макс. сдвиг: %.3f м" % [
		_damage.panel_count(),
		_damage.impact_count(),
		_damage.total_dent_depth(),
		budget,
		int(stats["moved_vertices"]),
		float(stats["max_offset_m"]),
	]


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	var top_panel := PanelContainer.new()
	top_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top_panel.offset_left = 12.0
	top_panel.offset_top = 12.0
	top_panel.offset_right = 372.0
	top_panel.offset_bottom = 178.0
	layer.add_child(top_panel)
	var top_box := VBoxContainer.new()
	top_panel.add_child(top_box)
	var title := Label.new()
	title.text = "Лаборатория деформации кузова"
	top_box.add_child(title)
	_vehicle_label = Label.new()
	_vehicle_label.text = "Кузов: …"
	top_box.add_child(_vehicle_label)
	_stats_label = Label.new()
	_stats_label.text = "…"
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top_box.add_child(_stats_label)
	var hint := Label.new()
	hint.text = "ЛКМ по кузову — вмятина · перетаскивание — камера · колесо — зум\nR — ремонт · 1/2/3 — кузов · Пробел — случайный удар"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top_box.add_child(hint)
	top_panel.visible = show_stats

	var bottom_panel := PanelContainer.new()
	bottom_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom_panel.offset_left = -470.0
	bottom_panel.offset_top = -86.0
	bottom_panel.offset_right = 470.0
	bottom_panel.offset_bottom = -12.0
	layer.add_child(bottom_panel)
	var bottom_box := VBoxContainer.new()
	bottom_panel.add_child(bottom_box)
	var row_impacts := HBoxContainer.new()
	bottom_box.add_child(row_impacts)
	_add_preset_button(row_impacts, "Спереди", 0)
	_add_preset_button(row_impacts, "Сзади", 1)
	_add_preset_button(row_impacts, "Слева", 2)
	_add_preset_button(row_impacts, "Справа", 3)
	_add_preset_button(row_impacts, "Капот", 4)
	_add_preset_button(row_impacts, "Крыша", 5)
	_add_preset_button(row_impacts, "Случайный", -1)
	var repair_button := _make_button("Ремонт (R)", "Вернуть исходную геометрию кузова")
	repair_button.pressed.connect(repair)
	row_impacts.add_child(repair_button)

	var row_cars := HBoxContainer.new()
	bottom_box.add_child(row_cars)
	for i in range(VEHICLE_IDS.size()):
		var car_button := _make_button(VEHICLE_TITLES[i], "Показать кузов " + VEHICLE_TITLES[i])
		car_button.pressed.connect(set_vehicle_index.bind(i))
		row_cars.add_child(car_button)
	var slider := HSlider.new()
	slider.focus_mode = Control.FOCUS_NONE
	slider.min_value = 1.0
	slider.max_value = 30.0
	slider.step = 0.5
	slider.value = impact_dv_mps
	slider.custom_minimum_size = Vector2(200.0, 0.0)
	slider.value_changed.connect(_on_dv_changed)
	row_cars.add_child(slider)
	_dv_label = Label.new()
	_dv_label.text = "Сила: %.1f м/с" % impact_dv_mps
	row_cars.add_child(_dv_label)
	_demo_button = _make_button("Демо: вкл" if _demo_enabled else "Демо: выкл", "Автоматические удары по случайным зонам")
	_demo_button.toggle_mode = true
	_demo_button.button_pressed = _demo_enabled
	_demo_button.toggled.connect(_on_demo_toggled)
	row_cars.add_child(_demo_button)


func _add_preset_button(parent: Container, text: String, preset: int) -> void:
	var button := _make_button(text, "Удар по зоне: " + text)
	if preset < 0:
		button.pressed.connect(random_impact)
	else:
		button.pressed.connect(preset_impact.bind(preset))
	parent.add_child(button)


func _make_button(text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	# Без фокуса: Пробел остаётся случайным ударом, а не повторным нажатием кнопки.
	button.focus_mode = Control.FOCUS_NONE
	return button


func _on_dv_changed(new_value: float) -> void:
	impact_dv_mps = new_value
	if _dv_label != null:
		_dv_label.text = "Сила: %.1f м/с" % new_value


func _on_demo_toggled(on: bool) -> void:
	_demo_enabled = on
	if _demo_button != null:
		_demo_button.text = "Демо: вкл" if on else "Демо: выкл"
	if on:
		_demo_timer = 0.3


## Переход из системы узла в систему корня модели (как в витрине гаража).
func _relative_transform(node: Node, root: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result
