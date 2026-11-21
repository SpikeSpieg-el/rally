## Лаборатория деформации кузова (Deformation Lab).
##
## Сцена scenes/editor/deformation_lab.tscn — запустите её (F6), чтобы мять
## любую машину каталога без заезда:
##   ЛКМ по кузову          — удар в эту точку (направление — от камеры);
##   Shift + ЛКМ и тянуть   — царапина вдоль кузова (как скольжение по забору);
##   ПКМ + мышь             — вращать камеру, колесо — зум;
##   Enter                  — удар из полей инспектора (точка, направление, сила);
##   R                      — починить кузов, W — показать сетку (видно, что
##                            треугольники не перекашиваются), F — эффекты удара.
## Деформация и следы берут настройку из RallyDamageVisualConfig (поле
## damage_config), эффекты — из RallyImpactFxConfig (impact_fx_config).
## Лаборатория работает с копиями ресурсов: ползунки не портят оригинал.
@tool
extends Node3D

class_name DeformationLab

const CarModels = preload("res://scripts/car_models.gd")
const DEFAULT_DAMAGE_PATH := "res://data/car/default_damage_visual.tres"
const DEFAULT_IMPACT_FX_PATH := "res://data/car/default_impact_fx.tres"
## Шаг царапины при протягивании мышью, м: чаще — плотнее след.
const SCRAPE_STEP_M := 0.03

# ── Экспорт (инспектор) ──────────────────────────────────────────────────────
@export_group("Автомобиль")
## id машины из data/vehicles/ (mitsubishi, golf, subaru, …).
@export var car_id: String = "mitsubishi"
## Высота пола витрины над землёй, м.
@export var spawn_height: float = 0.0

@export_group("Камера")
@export var orbit_distance: float = 6.5
@export var orbit_min_distance: float = 2.0
@export var orbit_max_distance: float = 22.0
@export var orbit_pitch_deg: float = -18.0
@export var orbit_yaw_deg: float = 35.0
@export var orbit_sensitivity: float = 0.3
## Высота точки, вокруг которой вращается камера, м.
@export var orbit_target_height: float = 0.7

@export_group("Удар")
## Точка удара в системе машины (Enter и кнопка «Удар»).
@export var impact_point_local: Vector3 = Vector3(0.0, 0.6, 2.4)
## Куда вдавливается металл (внутрь кузова).
@export var impact_push_dir: Vector3 = Vector3(0.0, 0.0, -1.0)
## Сила удара — потеря скорости, м/с.
@export var impact_speed_mps: float = 18.0
## Скорость скольжения для царапин мышью, м/с.
@export var scrape_speed_mps: float = 14.0
## Показывать эффекты удара: искры, обломки, звук, тряску камеры.
@export var show_impact_fx: bool = true

@export_group("Настройки")
## Вмятины и следы. Пусто — res://data/car/default_damage_visual.tres.
@export var damage_config: RallyDamageVisualConfig = null
## Эффекты удара. Пусто — res://data/car/default_impact_fx.tres.
@export var impact_fx_config: RallyImpactFxConfig = null

# ── Внутреннее состояние ─────────────────────────────────────────────────────
var car_root: Node3D = null
var damage_visual: CarDamageVisual = null
var impact_fx: CarImpactFx = null
var body_meshes: Array[MeshInstance3D] = []
var body_faces: Array[PackedVector3Array] = []

var _cam: Camera3D = null
var _orbiting := false
var _scraping := false
var _last_scrape := Vector3.INF
var _wireframe := false

var _ui: Control = null
var _car_selector: OptionButton = null
var _speed_slider: HSlider = null
var _speed_label: Label = null
var _budget_slider: HSlider = null
var _budget_label: Label = null
var _scale_slider: HSlider = null
var _scale_label: Label = null
var _status_label: Label = null
var _car_ids: Array[String] = []


# ── Жизненный цикл ──────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("rally_editor_tool")
	_setup_environment()
	_cam = get_node_or_null("CameraOrbit") as Camera3D
	if _cam == null:
		_cam = Camera3D.new()
		_cam.name = "CameraOrbit"
		add_child(_cam)
	_cam.fov = 55.0
	if not Engine.is_editor_hint():
		# Сетка (W) видна только у мешей, созданных после этого вызова, — а
		# кузов лаборатории пересобирается как раз ниже.
		RenderingServer.set_debug_generate_wireframes(true)
		_cam.current = true
		_build_ui()
		_populate_car_list()
	_apply_orbit()
	reload_car()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_apply_orbit()
	if impact_fx != null and show_impact_fx:
		impact_fx.restore_camera(_cam)
		impact_fx.apply_camera(_cam, false)
	_update_status()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or _cam == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _orbiting else Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_distance = clampf(orbit_distance - 0.5, orbit_min_distance, orbit_max_distance)
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_distance = clampf(orbit_distance + 0.5, orbit_min_distance, orbit_max_distance)
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and not _orbiting:
				if mb.shift_pressed:
					_scraping = true
					_last_scrape = Vector3.INF
					_scrape_at_mouse(mb.position)
				else:
					_try_hit_at_mouse(mb.position)
			elif not mb.pressed:
				_scraping = false
			return

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _orbiting:
			orbit_yaw_deg -= motion.relative.x * orbit_sensitivity
			orbit_pitch_deg = clampf(orbit_pitch_deg - motion.relative.y * orbit_sensitivity, -89.0, 89.0)
			get_viewport().set_input_as_handled()
		elif _scraping:
			_scrape_at_mouse(motion.position)
		return

	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var key := event as InputEventKey
		match key.keycode:
			KEY_R:
				_reset_car()
			KEY_ENTER, KEY_KP_ENTER:
				punch_impact()
			KEY_W:
				_toggle_wireframe()
			KEY_F:
				show_impact_fx = not show_impact_fx


# ── Камера ───────────────────────────────────────────────────────────────────

func _apply_orbit() -> void:
	if _cam == null:
		return
	var target := Vector3(0.0, spawn_height + orbit_target_height, 0.0)
	var orbit := Basis.from_euler(Vector3(deg_to_rad(orbit_pitch_deg), deg_to_rad(orbit_yaw_deg), 0.0))
	_cam.global_transform = Transform3D(orbit, target + orbit * Vector3(0.0, 0.0, orbit_distance))


func _toggle_wireframe() -> void:
	_wireframe = not _wireframe
	get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME if _wireframe else Viewport.DEBUG_DRAW_DISABLED


# ── UI ───────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	add_child(layer)

	_ui = PanelContainer.new()
	_ui.name = "UIPanel"
	_ui.position = Vector2(0.0, 0.0)
	_ui.custom_minimum_size = Vector2(330.0, 0.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.85)
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	_ui.add_theme_stylebox_override("panel", style)
	layer.add_child(_ui)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_ui.add_child(vbox)

	var title := Label.new()
	title.text = "ЛАБОРАТОРИЯ ДЕФОРМАЦИИ"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(title)

	_car_selector = OptionButton.new()
	_car_selector.item_selected.connect(_on_car_selected)
	vbox.add_child(_car_selector)

	var speed := _slider_row(vbox, "Сила удара", 1.0, 60.0, 1.0, impact_speed_mps, _on_speed_changed)
	_speed_slider = speed[0]
	_speed_label = speed[1]
	var budget := _slider_row(vbox, "Запас глубины", 0.5, 50.0, 0.5, 50.0, _on_budget_changed)
	_budget_slider = budget[0]
	_budget_label = budget[1]
	var dent_scale := _slider_row(vbox, "Сила вмятин", 0.0, 3.0, 0.05, 1.0, _on_scale_changed)
	_scale_slider = dent_scale[0]
	_scale_label = dent_scale[1]
	_on_speed_changed(impact_speed_mps)
	_on_budget_changed(50.0)
	_on_scale_changed(1.0)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	vbox.add_child(buttons)
	_button(buttons, "Удар (Enter)", punch_impact)
	_button(buttons, "Ремонт (R)", _reset_car)
	var buttons2 := HBoxContainer.new()
	buttons2.add_theme_constant_override("separation", 6)
	vbox.add_child(buttons2)
	_button(buttons2, "Сетка (W)", _toggle_wireframe)
	_button(buttons2, "Перечитать настройки", reload_car)

	vbox.add_child(HSeparator.new())
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status_label.custom_minimum_size.x = 300.0
	vbox.add_child(_status_label)

	var help := Label.new()
	help.text = "ЛКМ — удар · Shift+ЛКМ — царапина\nПКМ — вращение · колесо — зум\nF — эффекты удара вкл/выкл"
	help.add_theme_font_size_override("font_size", 11)
	help.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	vbox.add_child(help)


func _slider_row(parent: Container, title: String, min_value: float, max_value: float, step: float,
		start: float, callback: Callable) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var caption := Label.new()
	caption.text = title + ":"
	caption.add_theme_font_size_override("font_size", 13)
	row.add_child(caption)
	var value_label := Label.new()
	value_label.add_theme_font_size_override("font_size", 13)
	value_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	row.add_child(value_label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = start
	slider.custom_minimum_size.x = 290.0
	slider.value_changed.connect(callback)
	parent.add_child(slider)
	return [slider, value_label]


func _button(parent: Container, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)


func _populate_car_list() -> void:
	if _car_selector == null:
		return
	_car_selector.clear()
	_car_ids.clear()
	var dir := DirAccess.open("res://data/vehicles/")
	if dir != null:
		var files := dir.get_files()
		files.sort()
		for file in files:
			var file_name: String = file.trim_suffix(".remap")
			if not file_name.ends_with(".tres"):
				continue
			var id: String = file_name.get_basename()
			_car_ids.append(id)
			_car_selector.add_item(id.to_upper())
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
		_budget_label.text = "∞" if value >= 50.0 else "%.1f м" % value


func _on_scale_changed(value: float) -> void:
	if damage_visual != null and damage_visual.config != null:
		damage_visual.config.dent_scale = value
	if _scale_label != null:
		_scale_label.text = "×%.2f" % value


func _update_status() -> void:
	if _status_label == null:
		return
	if damage_visual == null:
		_status_label.text = "Модель %s не загружена" % car_id.to_upper()
		return
	var quality: Dictionary = damage_visual.triangle_stats()
	_status_label.text = ("Модель: %s · панелей %d · вершин %d\nУдаров: %d · вмято %.2f / %.1f м · следов %d\n"
		+ "Треугольников вывернуто: %d из %d · растяжение ×%.2f · шов %.1f мм") % [
		car_id.to_upper(), damage_visual.panel_count(), damage_visual.vertex_count(),
		damage_visual.impact_count(), damage_visual.total_dent_depth(), damage_visual.config.dent_budget_m,
		damage_visual.mark_count(), int(quality["flipped"]), int(quality["triangles"]),
		float(quality["max_stretch"]), float(quality["seam_gap_m"]) * 1000.0]


# ── Загрузка машины ──────────────────────────────────────────────────────────

func reload_car() -> void:
	if car_root != null:
		car_root.queue_free()
		car_root = null
	if damage_visual != null:
		damage_visual.queue_free()
		damage_visual = null
	if impact_fx != null:
		impact_fx.queue_free()
		impact_fx = null
	body_meshes.clear()
	body_faces.clear()

	car_root = CarModels.make_model(car_id)
	if car_root == null:
		push_warning("DeformationLab: модель для '%s' не найдена." % car_id)
		return
	add_child(car_root)
	car_root.position = Vector3(0.0, spawn_height, 0.0)

	var cfg: RallyDamageVisualConfig = damage_config
	if cfg == null:
		cfg = load(DEFAULT_DAMAGE_PATH) as RallyDamageVisualConfig
	if cfg == null:
		push_warning("DeformationLab: ресурс настроек деформации не найден.")
		return
	# Своя копия: ползунки лаборатории не меняют ресурс на диске.
	cfg = cfg.duplicate() as RallyDamageVisualConfig
	cfg.dent_budget_m = _budget_slider.value if _budget_slider != null else 50.0
	cfg.dent_scale = _scale_slider.value if _scale_slider != null else cfg.dent_scale

	damage_visual = CarDamageVisual.new()
	damage_visual.set_name("DeformationVisual")
	add_child(damage_visual)
	damage_visual.setup(car_root, car_root, cfg)
	_refresh_faces()

	if not Engine.is_editor_hint():
		var fx_cfg: RallyImpactFxConfig = impact_fx_config
		if fx_cfg == null:
			fx_cfg = load(DEFAULT_IMPACT_FX_PATH) as RallyImpactFxConfig
		impact_fx = CarImpactFx.new()
		impact_fx.name = "ImpactFx"
		add_child(impact_fx)
		impact_fx.setup(car_root, fx_cfg.duplicate() as RallyImpactFxConfig if fx_cfg != null else null)


## Треугольники кузова для попадания мышью — после каждой вмятины заново,
## чтобы клик попадал в уже помятую поверхность.
func _refresh_faces() -> void:
	body_meshes.clear()
	body_faces.clear()
	if car_root == null:
		return
	for node in car_root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh != null and mesh.is_in_group("rally_body_fx") and mesh.mesh != null:
			body_meshes.append(mesh)
			body_faces.append(mesh.mesh.get_faces())


# ── Удары ────────────────────────────────────────────────────────────────────

func punch_impact() -> void:
	if damage_visual == null:
		return
	var push: Vector3 = impact_push_dir
	if push.length_squared() < 1e-8:
		push = Vector3(0.0, 0.0, -1.0)
	push = push.normalized()
	damage_visual.apply_impact(impact_point_local, push, impact_speed_mps)
	if show_impact_fx and impact_fx != null and car_root != null:
		var xform := car_root.global_transform
		impact_fx.impact(xform * impact_point_local, (xform.basis * push).normalized(), impact_speed_mps,
			Vector3.ZERO)
	_refresh_faces()


func _try_hit_at_mouse(mouse: Vector2) -> void:
	if _ui != null and _ui.get_global_rect().has_point(mouse):
		return
	var hit := _raycast_body(_cam.project_ray_origin(mouse), _cam.project_ray_normal(mouse))
	if hit.get("hit", false):
		_set_impact_from_world(hit["position"])
		punch_impact()


## Царапина вдоль следа мыши: точка за точкой, направление — куда тянем.
func _scrape_at_mouse(mouse: Vector2) -> void:
	if damage_visual == null or car_root == null:
		return
	if _ui != null and _ui.get_global_rect().has_point(mouse):
		return
	var hit := _raycast_body(_cam.project_ray_origin(mouse), _cam.project_ray_normal(mouse))
	if not hit.get("hit", false):
		return
	var to_car := car_root.global_transform.affine_inverse()
	var point: Vector3 = to_car * Vector3(hit["position"])
	if _last_scrape == Vector3.INF:
		_last_scrape = point
		return
	var step := point - _last_scrape
	if step.length() < SCRAPE_STEP_M:
		return
	var push := (to_car.basis * _cam.project_ray_normal(mouse)).normalized()
	var slide := step.normalized() * scrape_speed_mps
	damage_visual.add_scrape(point, push, slide, 1.0, 0.05)
	if show_impact_fx and impact_fx != null:
		var xform := car_root.global_transform
		impact_fx.scrape(hit["position"], (xform.basis * push).normalized(), scrape_speed_mps, xform.basis * slide)
	_last_scrape = point


func _set_impact_from_world(world_point: Vector3) -> void:
	if car_root == null or not car_root.is_inside_tree():
		return
	impact_point_local = car_root.global_transform.affine_inverse() * world_point
	var dir := (world_point - _cam.global_position).normalized()
	impact_push_dir = car_root.global_transform.basis.inverse() * dir


func _reset_car() -> void:
	if car_root != null:
		car_root.position = Vector3(0.0, spawn_height, 0.0)
		car_root.rotation = Vector3.ZERO
	if damage_visual != null:
		damage_visual.clear_damage()
	if impact_fx != null:
		impact_fx.clear()
	_refresh_faces()


# ── Рейкаст по мешам ────────────────────────────────────────────────────────

func _raycast_body(from: Vector3, dir: Vector3) -> Dictionary:
	var closest := {}
	var best_t := 100.0
	for i in body_meshes.size():
		if not is_instance_valid(body_meshes[i]):
			continue
		var faces: PackedVector3Array = body_faces[i]
		var xform: Transform3D = body_meshes[i].global_transform
		for tri in range(faces.size() / 3):
			var a: Vector3 = xform * faces[tri * 3]
			var b: Vector3 = xform * faces[tri * 3 + 1]
			var c: Vector3 = xform * faces[tri * 3 + 2]
			var hit: Variant = Geometry3D.ray_intersects_triangle(from, dir, a, b, c)
			if hit != null:
				var dist: float = (hit as Vector3 - from).length()
				if dist < best_t:
					best_t = dist
					closest = {"hit": true, "position": hit as Vector3, "distance": dist}
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
		e.glow_enabled = true
		env.environment = e


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _orbiting:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if _wireframe and is_inside_tree():
			get_viewport().debug_draw = Viewport.DEBUG_DRAW_DISABLED
