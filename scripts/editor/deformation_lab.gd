## Лаборатория деформации кузова (Deformation Lab)
## Визуальный инструмент для тестирования CarDamageVisual: выбор машины из
## каталога, орбитальная камера (ПКМ + мышь), удары кликом по кузову и кнопками.
@tool
extends Node3D

class_name DeformationLab

const CarModels = preload("res://scripts/car_models.gd")

# ── Экспорт (инспектор) ──────────────────────────────────────────────────────
@export_group("Автомобиль")
@export var car_id: String = "mitsubishi"
@export var spawn_height: float = 1.4

@export_group("Камера")
@export var orbit_distance: float = 6.0
@export var orbit_min_distance: float = 2.0
@export var orbit_max_distance: float = 22.0
@export var orbit_pitch_deg: float = -20.0
@export var orbit_yaw_deg: float = 0.0
@export var orbit_sensitivity: float = 0.3

@export_group("Удар")
@export var impact_point_local: Vector3 = Vector3(0.9, 0.8, 0.6)
@export var impact_push_dir: Vector3 = Vector3(-1.0, 0.0, 0.0)
@export var impact_speed_mps: float = 12.0

@export var damage_config: RallyDamageVisualConfig = null

# ── Внутреннее состояние ─────────────────────────────────────────────────────
var car_root: Node3D = null
var damage_visual: CarDamageVisual = null
var body_meshes: Array[MeshInstance3D] = []
var body_faces: Array[PackedVector3Array] = []

# Орбитальная камера
var _cam: Camera3D = null
var _pivot: Node3D = null
var _orbiting: bool = false

# UI
var _ui: Control = null
var _car_selector: OptionButton = null
var _speed_slider: HSlider = null
var _speed_label: Label = null
var _budget_slider: HSlider = null
var _budget_label: Label = null
var _status_label: Label = null
var _car_ids: Array[String] = []

# ── Жизненный цикл ──────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("rally_editor_tool")
	_setup_environment()
	_build_orbit_camera()
	_build_ui()
	_populate_car_list()
	reload_car()

func _process(_delta: float) -> void:
	_update_status()

func _unhandled_input(event: InputEvent) -> void:
	if _cam == null:
		return

	# ПКМ — начать/закончить вращение орбиты
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _orbiting else Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
			return
		# Колесо — зум
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				orbit_distance = clampf(orbit_distance - 0.5, orbit_min_distance, orbit_max_distance)
				_apply_orbit()
				return
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				orbit_distance = clampf(orbit_distance + 0.5, orbit_min_distance, orbit_max_distance)
				_apply_orbit()
				return

	# Движение мыши при зажатой ПКМ — вращение
	if event is InputEventMouseMotion and _orbiting:
		var motion := event as InputEventMouseMotion
		orbit_yaw_deg -= motion.relative.x * orbit_sensitivity
		orbit_pitch_deg = clampf(orbit_pitch_deg - motion.relative.y * orbit_sensitivity, -89.0, 89.0)
		_apply_orbit()
		get_viewport().set_input_as_handled()
		return

	# ЛКМ — удар в точку клика
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not _orbiting:
			_try_hit_at_mouse()
			return

	# Клавиши
	if event is InputEventKey and (event as InputEventKey).pressed:
		var key := event as InputEventKey
		if key.keycode == KEY_R:
			_reset_car()
		elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
			punch_impact()

# ── Орбитальная камера ───────────────────────────────────────────────────────

func _build_orbit_camera() -> void:
	_pivot = Node3D.new()
	_pivot.name = "CameraPivot"
	_pivot.position = Vector3(0.0, spawn_height, 0.0)
	add_child(_pivot)

	_cam = Camera3D.new()
	_cam.name = "OrbitCamera"
	_cam.current = true
	_cam.fov = 55.0
	_pivot.add_child(_cam)
	_apply_orbit()

func _apply_orbit() -> void:
	if _pivot == null or _cam == null:
		return
	_pivot.rotation_degrees = Vector3(orbit_pitch_deg, orbit_yaw_deg, 0.0)
	_cam.position = Vector3(0.0, 0.0, orbit_distance)

# ── UI ───────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	# CanvasLayer чтобы UI был поверх 3D
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	add_child(layer)

	_ui = Control.new()
	_ui.name = "UIPanel"
	_ui.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_ui.offset_right = 320.0
	_ui.offset_bottom = 400.0
	layer.add_child(_ui)

	# Фон панели
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.85)
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 0
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", style)
	_ui.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	# Заголовок
	var title := Label.new()
	title.text = "ЛАБОРАТОРИЯ ДЕФОРМАЦИИ"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(title)

	# Выбор машины
	var car_label := Label.new()
	car_label.text = "Автомобиль:"
	car_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(car_label)

	_car_selector = OptionButton.new()
	_car_selector.item_selected.connect(_on_car_selected)
	vbox.add_child(_car_selector)

	# Скорость удара
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 8)
	vbox.add_child(speed_row)

	var sp_label := Label.new()
	sp_label.text = "Сила удара:"
	sp_label.add_theme_font_size_override("font_size", 13)
	speed_row.add_child(sp_label)

	_speed_label = Label.new()
	_speed_label.text = "%.0f м/с" % impact_speed_mps
	_speed_label.add_theme_font_size_override("font_size", 13)
	_speed_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	speed_row.add_child(_speed_label)

	_speed_slider = HSlider.new()
	_speed_slider.min_value = 1.0
	_speed_slider.max_value = 60.0
	_speed_slider.step = 1.0
	_speed_slider.value = impact_speed_mps
	_speed_slider.custom_minimum_size.x = 280.0
	_speed_slider.value_changed.connect(_on_speed_changed)
	vbox.add_child(_speed_slider)

	# Бюджет деформации (максимум суммарной глубины вмятин)
	var budget_row := HBoxContainer.new()
	budget_row.add_theme_constant_override("separation", 8)
	vbox.add_child(budget_row)

	var bd_label := Label.new()
	bd_label.text = "Бюджет:"
	bd_label.add_theme_font_size_override("font_size", 13)
	budget_row.add_child(bd_label)

	_budget_label = Label.new()
	_budget_label.text = "∞"
	_budget_label.add_theme_font_size_override("font_size", 13)
	_budget_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5))
	budget_row.add_child(_budget_label)

	_budget_slider = HSlider.new()
	_budget_slider.min_value = 0.5
	_budget_slider.max_value = 50.0
	_budget_slider.step = 0.5
	_budget_slider.value = 50.0
	_budget_slider.custom_minimum_size.x = 280.0
	_budget_slider.value_changed.connect(_on_budget_changed)
	vbox.add_child(_budget_slider)

	# Кнопки
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var btn_punch := Button.new()
	btn_punch.text = "💥 Удар (Enter)"
	btn_punch.pressed.connect(punch_impact)
	btn_punch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(btn_punch)

	var btn_reset := Button.new()
	btn_reset.text = "🔄 Сброс (R)"
	btn_reset.pressed.connect(_reset_car)
	btn_reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(btn_reset)

	# Разделитель
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Статус
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_status_label)

	# Подсказка
	var hint := Label.new()
	hint.text = "ПКМ + мышь — вращение\nКолесо — зум\nЛКМ — удар в точку"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(hint)

func _populate_car_list() -> void:
	if _car_selector == null:
		return
	_car_selector.clear()
	_car_ids.clear()
	# Файлы ресурсов машин из data/vehicles/
	var dir := DirAccess.open("res://data/vehicles/")
	if dir != null:
		var files := dir.get_files()
		files.sort()
		for file in files:
			var name: String = file.trim_suffix(".remap")
			if not name.ends_with(".tres"):
				continue
			var id: String = name.get_basename()
			_car_ids.append(id)
			_car_selector.add_item(id.to_upper())
	# Выбираем текущую
	var idx: int = _car_ids.find(car_id)
	if idx >= 0:
		_car_selector.selected = idx

func _on_car_selected(index: int) -> void:
	if index >= 0 and index < _car_ids.size():
		car_id = _car_ids[index]
		reload_car()

func _on_speed_changed(value: float) -> void:
	impact_speed_mps = value
	if _speed_label != null:
		_speed_label.text = "%.0f м/с" % value

func _on_budget_changed(value: float) -> void:
	if damage_visual != null and damage_visual.config != null:
		damage_visual.config.dent_budget_m = value
	if _budget_label != null:
		if value >= 50.0:
			_budget_label.text = "∞"
		else:
			_budget_label.text = "%.1f м" % value

func _update_status() -> void:
	if _status_label == null:
		return
	var impacts: int = damage_visual.impact_count() if damage_visual != null else 0
	var panels: int = damage_visual.panel_count() if damage_visual != null else 0
	var dent: float = damage_visual.total_dent_depth() if damage_visual != null else 0.0
	var budget: float = damage_visual.config.dent_budget_m if damage_visual != null and damage_visual.config != null else 0.0
	_status_label.text = "Модель: %s | Ударов: %d | Панелей: %d | Вмято: %.2f / %.1f м" % [car_id.to_upper(), impacts, panels, dent, budget]

# ── Загрузка машины ──────────────────────────────────────────────────────────

func reload_car() -> void:
	# Очистка предыдущей
	if car_root != null:
		car_root.queue_free()
		car_root = null
	if damage_visual != null:
		damage_visual.queue_free()
		damage_visual = null
	body_meshes.clear()
	body_faces.clear()

	car_root = CarModels.make_model(car_id)
	if car_root == null:
		push_warning("DeformationLab: модель для '%s' не найдена." % car_id)
		return

	add_child(car_root)
	car_root.position = Vector3(0.0, spawn_height, 0.0)

	# Собираем меши кузова для рейкаста
	for node in car_root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh != null and mesh.is_in_group("rally_body_fx") and mesh.mesh != null:
			body_meshes.append(mesh)
			body_faces.append(mesh.mesh.get_faces())

	# Деформация
	var cfg: RallyDamageVisualConfig = damage_config
	if cfg == null:
		cfg = load("res://data/car/default_damage_visual.tres") as RallyDamageVisualConfig
	if cfg == null:
		push_warning("DeformationLab: ресурс настроек деформации не найден.")
		return

	# Лаборатория работает со своей копией конфига, чтобы не менять оригинал.
	# По умолчанию бюджет максимальный — можно мять сколько угодно.
	cfg = cfg.duplicate() as RallyDamageVisualConfig
	var lab_budget: float = _budget_slider.value if _budget_slider != null else 50.0
	cfg.dent_budget_m = lab_budget

	damage_visual = CarDamageVisual.new()
	damage_visual.set_name("DeformationVisual")
	add_child(damage_visual)
	damage_visual.setup(car_root, car_root, cfg)

# ── Удары ────────────────────────────────────────────────────────────────────

func punch_impact() -> void:
	if damage_visual == null:
		return
	var push: Vector3 = impact_push_dir
	if push.length_squared() < 1e-8:
		push = Vector3(-1.0, 0.0, 0.0)
	damage_visual.apply_impact(impact_point_local, push.normalized(), impact_speed_mps)

func _try_hit_at_mouse() -> void:
	if car_root == null or _cam == null:
		return
	var mouse: Vector2 = get_viewport().get_mouse_position()
	# Проверяем, не кликнули ли по UI
	if _ui != null and _ui.get_global_rect().has_point(mouse):
		return
	var from: Vector3 = _cam.project_ray_origin(mouse)
	var direction: Vector3 = _cam.project_ray_normal(mouse)
	var hit: Dictionary = _raycast_body(from, direction)
	if hit.get("hit", false):
		_set_impact_from_world(hit["position"])
		punch_impact()

func _set_impact_from_world(world_point: Vector3) -> void:
	if car_root == null or not car_root.is_inside_tree():
		return
	impact_point_local = car_root.global_transform.affine_inverse() * world_point
	# Направление удара — от камеры к точке
	if _cam != null:
		impact_push_dir = (world_point - _cam.global_position).normalized()
	else:
		impact_push_dir = Vector3(-1.0, 0.0, 0.0)

func _reset_car() -> void:
	if car_root != null:
		car_root.position = Vector3(0.0, spawn_height, 0.0)
		car_root.rotation = Vector3.ZERO
	if damage_visual != null:
		damage_visual.clear_damage()

# ── Рейкаст по мешам ────────────────────────────────────────────────────────

func _raycast_body(from: Vector3, dir: Vector3) -> Dictionary:
	var closest := Dictionary()
	var best_t: float = 100.0
	for i in body_meshes.size():
		var faces: PackedVector3Array = body_faces[i]
		if faces.is_empty():
			continue
		var xform: Transform3D = body_meshes[i].global_transform
		var tri_count: int = faces.size() / 3
		for tri in tri_count:
			var a: Vector3 = xform * faces[tri * 3]
			var b: Vector3 = xform * faces[tri * 3 + 1]
			var c: Vector3 = xform * faces[tri * 3 + 2]
			var hit: Variant = Geometry3D.ray_intersects_triangle(from, dir, a, b, c)
			if hit != null:
				var dist: float = (hit as Vector3 - from).length()
				if dist < best_t:
					best_t = dist
					closest = {"hit": true, "position": hit as Vector3, "distance": dist}
	if closest.is_empty():
		return {}
	return closest

# ── Окружение ────────────────────────────────────────────────────────────────

func _setup_environment() -> void:
	var env := get_node_or_null("Environment") as WorldEnvironment
	if env == null:
		env = WorldEnvironment.new()
		env.name = "Environment"
		add_child(env)
	if env.environment == null:
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.15, 0.16, 0.18)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.6, 0.65, 0.7)
		e.ambient_light_energy = 0.55
		e.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.environment = e

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _orbiting:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if car_root != null and car_root.is_inside_tree():
			car_root.queue_free()
