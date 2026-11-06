## Сердце «Студии трассы»: состояние, ввод и правки.
##
## Плагин (addons/rally_track_studio/plugin.gd) — тонкая оболочка: кнопки,
## ввод из 3D-вьюпорта и отрисовка. Здесь живёт вся логика.
##
## Что важно знать по устройству:
##   * данные не дублируются — студия правит те же Curve3D, RallyTrackConfig и
##     RallySpawnLayout, которые читает RallyStage при сборке мира;
##   * каждая правка проходит через EditorUndoRedoManager, поэтому Ctrl+Z
##     возвращает и точки кривой, и участки, и расстановку;
##   * после правки .tres сохраняется на диск (можно выключить в настройках):
##     именно из-за «сохранил сцену — а в игре старая дорога» редактор трасс
##     раньше считался неудобным;
##   * тяжёлая пересборка мира НЕ запускается на каждый сдвиг мыши: мгновенную
##     картину рисует 2D-разметка, а мир собирается по Ctrl+R или по таймеру.
extends RefCounted

const SettingsType = preload("res://scripts/data/rally_track_studio_settings.gd")
const TrackType = preload("res://scripts/data/rally_track_config.gd")
const SpawnType = preload("res://scripts/data/rally_spawn_layout.gd")
const SectionType = preload("res://scripts/data/rally_route_section.gd")
const PropLibraryType = preload("res://scripts/data/rally_prop_library.gd")
const PropType = preload("res://scripts/data/rally_prop.gd")
const Analysis = preload("res://scripts/track/route_analysis.gd")
const ViewType = preload("res://addons/rally_track_studio/studio_view.gd")
const Modes = preload("res://addons/rally_track_studio/studio_modes.gd")

const INPUT_PASS := 0
const INPUT_STOP := 1
const DEFAULT_PROP_LIBRARY := "res://data/stage/default_prop_library.tres"
const DEFAULT_SPAWN_LAYOUT := "res://data/stage/default_spawn_layout.tres"

var host: EditorPlugin = null
var settings: SettingsType = null
var view: ViewType = null

var active: bool = false
var mode: int = Modes.Mode.ROUTE

var stage: Node = null
var scene_root: Node = null
var curve: Curve3D = null
var track: TrackType = null
var spawn: SpawnType = null
var prop_library: PropLibraryType = null

var samples: Dictionary = {}
var corners: Array = []
var warnings: Array = []
var stats: Dictionary = {}
var length: float = 0.0
var route_ready: bool = false

# Экранные области HUD: по ним клики не проваливаются в мир.
var overlay_size := Vector2(1280.0, 720.0)
var hud_rect := Rect2()
var warnings_rect := Rect2()
var profile_rect := Rect2()
var mouse_pos := Vector2(-1000.0, -1000.0)

var hover_distance: float = -1.0
var hover_point := Vector3.ZERO
var hover_valid: bool = false
var hover_control: int = -1
var hover_section: int = -1
var hover_zone: int = -1
var hover_brush := Vector3.ZERO
var hover_brush_valid: bool = false
var hover_new_point := Vector3.ZERO
var hover_new_valid: bool = false

var selected_distance: float = -1.0
var selected_control: int = -1
var selected_section: int = -1

var drag_kind: String = ""
var dragging: bool = false

var needs_rebuild: bool = false
var building: bool = false
var last_build_seconds: float = 0.0

var brush_index: int = 0

var _dirty: bool = true
var _last_hover_ms: int = 0
var _camera: Camera3D = null
var _last_mouse := Vector2.ZERO
var _hover_ground_pos := Vector2(-10000.0, -10000.0)
var _hover_ground := Vector3.ZERO
var _hover_ground_ok: bool = false
var _hover_ground_camera := Transform3D.IDENTITY

var _curve_before: Dictionary = {}
var _sections_before: Array = []
var _section: Resource = null
var _section_before: Dictionary = {}
var _spawn_before: Dictionary = {}
var _drag_index: int = -1
var _drag_side: int = 1
var _stroke_nodes: Array = []
var _stroke_last := Vector3.ZERO
var _rebuild_timer: float = 0.0
var _curve_hash_value: int = 0
var _signature_timer: float = 0.0
var _building_timer: float = 0.0
var _zone_grab: float = 0.0


# ------------------------------------------------------------------ жизненный цикл

func setup(host_plugin: EditorPlugin, settings_resource: SettingsType) -> void:
	host = host_plugin
	settings = settings_resource
	if view == null:
		view = ViewType.new()
	active = settings.enabled_on_open
	sync_scene()


func shutdown() -> void:
	_disconnect_curve()
	stage = null
	scene_root = null
	curve = null
	track = null
	spawn = null
	active = false


func toggle_active() -> void:
	active = not active
	if active:
		sync_scene()
		_focus_stage_root()
	_dirty = true
	_request_redraw()


func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	if active:
		sync_scene()
		_focus_stage_root()
	_dirty = true
	_request_redraw()


func set_mode(value: int) -> void:
	mode = clampi(value, 0, int(Modes.Mode.ZONES))
	_cancel_drag()
	_dirty = true
	_update_hover(_camera, mouse_pos)
	_request_redraw()


func mode_name() -> String:
	if settings == null or mode >= settings.mode_names.size():
		return ""
	return settings.mode_names[mode]


## Найти сцену этапа в текущем редакторе. Возвращает true, если нашли.
func sync_scene() -> bool:
	if host == null:
		return false
	var edited: Node = host.get_editor_interface().get_edited_scene_root()
	if edited != scene_root or (stage != null and not is_instance_valid(stage)):
		_reset_scene()
		scene_root = edited
		if scene_root != null:
			stage = _find_stage(scene_root)
	if stage == null or not is_instance_valid(stage):
		_reset_scene()
		return false
	_bind_resources()
	return true


func _reset_scene() -> void:
	_disconnect_curve()
	stage = null
	curve = null
	track = null
	spawn = null
	prop_library = null
	samples = {}
	corners = []
	warnings = []
	stats = {}
	length = 0.0
	route_ready = false
	hover_valid = false
	selected_control = -1
	selected_distance = -1.0
	_dirty = true


func _find_stage(node: Node) -> Node:
	var script_obj = node.get_script()
	if script_obj is Script:
		var script_path: String = script_obj.resource_path
		if script_path.ends_with("rally_stage.gd"):
			return node
	for child in node.get_children():
		var found: Node = _find_stage(child)
		if found != null:
			return found
	return null


func _bind_resources() -> void:
	var raw_track = stage.get("track_override")
	if raw_track is RallyTrackConfig:
		track = raw_track
	elif track == null:
		var raw_base = stage.get("track")
		if raw_base is RallyTrackConfig:
			track = raw_base
	var raw_spawn = stage.get("spawn_layout")
	if raw_spawn is RallySpawnLayout:
		spawn = raw_spawn
	elif spawn == null:
		spawn = load(DEFAULT_SPAWN_LAYOUT) as SpawnType
	var raw_library = stage.get("prop_library")
	if raw_library is RallyPropLibrary:
		prop_library = raw_library
	elif prop_library == null:
		prop_library = load(DEFAULT_PROP_LIBRARY) as PropLibraryType
	var next_curve: Curve3D = null
	if track != null and track.road_curve != null:
		next_curve = track.road_curve
	else:
		var route_node := stage.get_node_or_null("Route") as Path3D
		if route_node != null:
			next_curve = route_node.curve
	if next_curve != curve:
		_disconnect_curve()
		curve = next_curve
		if curve != null and not curve.changed.is_connected(_on_curve_changed):
			curve.changed.connect(_on_curve_changed)
		_dirty = true


func _disconnect_curve() -> void:
	if curve != null and is_instance_valid(curve) and curve.changed.is_connected(_on_curve_changed):
		curve.changed.disconnect(_on_curve_changed)


func _focus_stage_root() -> void:
	if host == null or stage == null:
		return
	var selection := host.get_editor_interface().get_selection()
	if selection == null:
		return
	var nodes := selection.get_selected_nodes()
	if nodes.size() == 1 and (nodes[0] == stage or stage.is_ancestor_of(nodes[0])):
		return
	selection.clear()
	selection.add_node(stage)


func _on_curve_changed() -> void:
	_dirty = true
	_request_redraw()


## Тик из плагина: обновить анализ, дождаться затишья и собрать мир.
func tick(delta: float) -> void:
	if not active:
		return
	if host == null:
		return
	if stage == null or not is_instance_valid(stage):
		if not sync_scene():
			return
	if dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		# Отпускание кнопки могло случиться вне вьюпорта — не залипаем в драге.
		_end_drag()
	_signature_timer -= delta
	if _signature_timer <= 0.0:
		# Кривую могли править и мимо студии (гизмо Path3D, скрипт, Undo).
		_signature_timer = 0.25
		var current_hash := _curve_hash()
		if current_hash != _curve_hash_value:
			_curve_hash_value = current_hash
			_dirty = true
	if _building_timer > 0.0:
		_building_timer -= delta
		if _building_timer <= 0.0:
			building = false
			_curve_hash_value = _curve_hash()
			_request_redraw()
	if _dirty:
		_refresh_analysis()
		_dirty = false
		_request_redraw()
	if _rebuild_timer > 0.0:
		_rebuild_timer -= delta
		if _rebuild_timer <= 0.0:
			rebuild_stage()


## Дешёвый отпечаток кривой: по нему студия замечает чужие правки.
func _curve_hash() -> int:
	if curve == null:
		return 0
	var acc := curve.point_count * 131 + (7 if curve.closed else 3)
	for i in range(curve.point_count):
		var p := curve.get_point_position(i)
		var a := curve.get_point_in(i)
		var b := curve.get_point_out(i)
		acc = (acc * 31 + int(p.x * 100.0) + int(p.y * 100.0) * 7 + int(p.z * 100.0) * 13) & 0x7FFFFFFF
		acc = (acc * 17 + int(a.x * 100.0) + int(a.y * 100.0) * 3 + int(a.z * 100.0) * 5) & 0x7FFFFFFF
		acc = (acc * 13 + int(b.x * 100.0) + int(b.y * 100.0) * 3 + int(b.z * 100.0) * 5) & 0x7FFFFFFF
	return acc


func _refresh_analysis() -> void:
	if curve == null or settings == null:
		route_ready = false
		length = 0.0
		return
	samples = Analysis.sample_curve(curve, settings.sample_step, settings.max_samples)
	length = float(samples.get("length", 0.0))
	route_ready = length > 0.0
	if not route_ready:
		corners = []
		warnings = []
		stats = {}
		return
	corners = Analysis.find_corners(
		samples,
		settings.corner_window,
		settings.corner_threshold_deg,
		settings.pace_note_min_angle,
		settings.pace_note_max_angle
	)
	warnings = Analysis.find_warnings(
		samples,
		corners,
		settings.min_radius_warning,
		settings.max_grade_warning,
		settings.min_gap_warning,
		settings.gap_along_margin
	)
	stats = Analysis.stats(samples, corners, settings.estimate_speed_kmh)


# ------------------------------------------------------------------ рисование

func current_camera() -> Camera3D:
	if _camera != null and is_instance_valid(_camera):
		return _camera
	if host != null:
		var viewport := host.get_editor_interface().get_editor_viewport_3d(0)
		if viewport != null:
			return viewport.get_camera_3d()
	return null


func draw_overlay(overlay: Control) -> void:
	if not active or settings == null or overlay == null:
		return
	if stage == null or not is_instance_valid(stage):
		return
	var camera := current_camera()
	if camera == null:
		return
	overlay_size = overlay.size
	if view != null:
		view.draw_all(overlay, self, camera, settings)


## Перерисовать разметку (плагин и кнопки HUD зовут это публично).
func request_redraw() -> void:
	_request_redraw()


func _request_redraw() -> void:
	if host != null:
		host.update_overlays()


func _screen_scale(camera: Camera3D) -> Vector2:
	if camera == null:
		return Vector2.ONE
	var viewport := camera.get_viewport()
	if viewport == null:
		return Vector2.ONE
	var area := viewport.get_visible_rect().size
	if area.x < 1.0 or area.y < 1.0:
		return Vector2.ONE
	return overlay_size / area


func project_point(camera: Camera3D, world: Vector3) -> Vector2:
	if camera == null:
		return Vector2.ZERO
	return camera.unproject_position(world) * _screen_scale(camera)


func is_on_screen(camera: Camera3D, world: Vector3) -> bool:
	if camera == null or camera.is_position_behind(world):
		return false
	var screen := project_point(camera, world)
	return screen.x > -120.0 and screen.y > -120.0 \
		and screen.x < overlay_size.x + 120.0 and screen.y < overlay_size.y + 120.0


# ------------------------------------------------------------------ ввод

func forward_input(camera: Camera3D, event: InputEvent) -> int:
	if not active or settings == null:
		return INPUT_PASS
	if stage == null or not is_instance_valid(stage):
		if not sync_scene():
			return INPUT_PASS
	_camera = camera
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		mouse_pos = motion.position
		if dragging:
			_apply_drag(camera, motion.position)
			_request_redraw()
			return INPUT_STOP
		_last_mouse = motion.position
		var now := Time.get_ticks_msec()
		var period := int(1000.0 / maxf(4.0, settings.hover_hz))
		if now - _last_hover_ms >= period:
			_last_hover_ms = now
			_update_hover(camera, motion.position)
			_request_redraw()
		return INPUT_PASS
	if event is InputEventMouseButton:
		return _on_mouse_button(camera, event as InputEventMouseButton)
	if event is InputEventKey:
		return _on_key(camera, event as InputEventKey)
	return INPUT_PASS


func _on_mouse_button(camera: Camera3D, event: InputEventMouseButton) -> int:
	mouse_pos = event.position
	var left := event.button_index == MOUSE_BUTTON_LEFT
	var right := event.button_index == MOUSE_BUTTON_RIGHT
	if event.pressed and _hud_contains(event.position):
		return INPUT_STOP
	if left and not event.pressed:
		if dragging:
			_end_drag()
			return INPUT_STOP
		return INPUT_PASS
	if event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		if mode == Modes.Mode.PROPS and event.ctrl_pressed:
			var wheel_step := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			settings.brush_radius = clampf(settings.brush_radius + wheel_step, 1.0, 40.0)
			_request_redraw()
			return INPUT_STOP
		return INPUT_PASS
	if not event.pressed:
		return INPUT_PASS
	if left:
		if profile_rect.has_point(event.position):
			drag_kind = "profile"
			dragging = true
			_scrub_profile(event.position)
			return INPUT_STOP
		_update_hover(camera, event.position)
		return _press_left(camera, event)
	if right:
		return _press_right(camera, event)
	return INPUT_PASS


func _press_left(camera: Camera3D, event: InputEventMouseButton) -> int:
	if mode == Modes.Mode.ROUTE:
		return _press_route(camera, event)
	if mode == Modes.Mode.ROAD:
		return _press_road(camera, event)
	if mode == Modes.Mode.PROPS:
		return _press_props(camera, event)
	if mode == Modes.Mode.ZONES:
		return _press_zones(camera, event)
	return INPUT_PASS


func _press_route(camera: Camera3D, event: InputEventMouseButton) -> int:
	var control := _nearest_control(camera, event.position)
	if control >= 0:
		selected_control = control
		selected_distance = _control_distance(control)
		_drag_index = control
		_curve_before = capture_curve(curve)
		dragging = true
		drag_kind = "point_height" if event.shift_pressed else "point"
		_last_mouse = event.position
		_request_redraw()
		return INPUT_STOP
	var near := _nearest_sample_screen(camera, event.position, settings.insert_radius_px)
	if near >= 0:
		var insert_at: float = _sample_distance(near)
		_curve_before = capture_curve(curve)
		var index := _insert_point(insert_at)
		if index >= 0:
			selected_control = index
			selected_distance = insert_at
			_drag_index = index
			dragging = true
			drag_kind = "point_height" if event.shift_pressed else "point"
			_last_mouse = event.position
			_request_redraw()
			return INPUT_STOP
		return INPUT_PASS
	var ground := _ray_ground(camera, event.position)
	if not bool(ground.get("ok", false)):
		return INPUT_PASS
	_curve_before = capture_curve(curve)
	var point: Vector3 = ground["point"]
	var appended := _append_point(point)
	if appended >= 0:
		selected_control = appended
		selected_distance = length
		_drag_index = appended
		dragging = true
		drag_kind = "point_height" if event.shift_pressed else "point"
		_last_mouse = event.position
		_request_redraw()
		return INPUT_STOP
	return INPUT_PASS


func _press_road(camera: Camera3D, event: InputEventMouseButton) -> int:
	if track == null:
		return INPUT_PASS
	var boundary := _nearest_section_boundary(camera, event.position)
	if boundary >= 0:
		_section = track.route_sections[boundary]
		_sections_before = track.route_sections.duplicate()
		_section_before = _section_state(_section)
		_drag_index = boundary
		drag_kind = "section_start"
		dragging = true
		_request_redraw()
		return INPUT_STOP
	var handle := _nearest_width_handle(camera, event.position)
	if not handle.is_empty():
		var distance: float = float(handle.get("distance", 0.0))
		_sections_before = track.route_sections.duplicate()
		_section = _section_for_edit(distance)
		_section_before = _section_state(_section)
		_drag_side = int(handle.get("side", 1))
		drag_kind = "width"
		dragging = true
		_update_hover(camera, event.position)
		_request_redraw()
		return INPUT_STOP
	if hover_valid:
		selected_section = _section_index_at(hover_distance)
		selected_distance = hover_distance
		_request_redraw()
		return INPUT_STOP
	return INPUT_PASS


func _press_props(camera: Camera3D, event: InputEventMouseButton) -> int:
	var ground := _ray_ground(camera, event.position)
	_stroke_nodes = []
	if not bool(ground.get("ok", false)):
		return INPUT_PASS
	_stroke_last = ground["point"]
	_place_brush(ground["point"])
	drag_kind = "paint"
	dragging = true
	return INPUT_STOP


func _press_zones(camera: Camera3D, event: InputEventMouseButton) -> int:
	if event.shift_pressed or event.ctrl_pressed:
		# Shift+клик — старт под курсором, Ctrl+клик — финиш: быстрее, чем тянуть.
		var quick := _distance_at_screen(camera, event.position)
		if quick >= 0.0 and spawn != null:
			_spawn_before = _spawn_state()
			var clamped := clampf(quick, 0.0, length)
			if event.shift_pressed:
				spawn.start_distance = clamped
			else:
				spawn.finish_margin = maxf(0.0, length - clamped)
			_commit_spawn("положение зоны")
			return INPUT_STOP
	var zone := _nearest_zone(camera, event.position)
	if not zone.is_empty():
		_spawn_before = _spawn_state()
		drag_kind = String(zone.get("kind", "checkpoint"))
		_drag_index = int(zone.get("index", -1))
		_zone_grab = 0.0
		if hover_valid and hover_distance >= 0.0:
			_zone_grab = float(zone.get("distance", 0.0)) - hover_distance
		dragging = true
		_request_redraw()
		return INPUT_STOP
	if not hover_valid:
		return INPUT_PASS
	_spawn_before = _spawn_state()
	var cps := _checkpoint_distances()
	var distance := hover_distance
	if distance < settings.checkpoint_spacing_min:
		return INPUT_PASS
	for value in cps:
		if absf(float(value) - distance) < settings.checkpoint_spacing_min:
			_request_redraw()
			return INPUT_STOP
	cps.append(distance)
	cps.sort()
	spawn.custom_checkpoint_distances = cps
	_commit_spawn("добавить КПП")
	return INPUT_STOP


func _press_right(camera: Camera3D, event: InputEventMouseButton) -> int:
	if mode == Modes.Mode.ROUTE:
		var control := _nearest_control(camera, event.position)
		if control >= 0:
			_curve_before = capture_curve(curve)
			curve.remove_point(control)
			_refresh_handles([control - 1, control])
			selected_control = -1
			_commit_curve("удалить точку", _curve_before)
			return INPUT_STOP
		return INPUT_PASS
	if mode == Modes.Mode.PROPS:
		if _erase_prop(camera, event.position):
			return INPUT_STOP
		return INPUT_PASS
	if mode == Modes.Mode.ZONES:
		var zone := _nearest_zone(camera, event.position)
		if not zone.is_empty() and String(zone.get("kind", "")) == "checkpoint":
			_spawn_before = _spawn_state()
			var cps := _checkpoint_distances()
			var index := int(zone.get("index", -1))
			if index >= 0 and index < cps.size():
				cps.remove_at(index)
				spawn.custom_checkpoint_distances = cps
				_commit_spawn("удалить КПП")
				return INPUT_STOP
	return INPUT_PASS


func _on_key(camera: Camera3D, event: InputEventKey) -> int:
	if not event.pressed or event.echo:
		return INPUT_PASS
	var code := event.physical_keycode
	if code == 0:
		code = event.keycode
	if event.ctrl_pressed and code == KEY_R:
		rebuild_stage()
		return INPUT_STOP
	match code:
		KEY_0:
			toggle_active()
			return INPUT_STOP
		KEY_1:
			set_mode(Modes.Mode.ROUTE)
			return INPUT_STOP
		KEY_2:
			set_mode(Modes.Mode.ROAD)
			return INPUT_STOP
		KEY_3:
			set_mode(Modes.Mode.PROPS)
			return INPUT_STOP
		KEY_4:
			set_mode(Modes.Mode.ZONES)
			return INPUT_STOP
		KEY_ESCAPE:
			if dragging:
				_cancel_drag()
				_request_redraw()
				return INPUT_STOP
		KEY_DELETE, KEY_BACKSPACE:
			return _delete_hovered()
		KEY_S:
			if mode == Modes.Mode.ROUTE:
				_smooth_route()
				return INPUT_STOP
		KEY_X:
			if mode == Modes.Mode.ROAD:
				_cycle_surface(-1 if event.shift_pressed else 1)
				return INPUT_STOP
		KEY_V:
			if mode == Modes.Mode.PROPS:
				_cycle_brush(1 if event.shift_pressed else -1)
				return INPUT_STOP
		KEY_B:
			if mode == Modes.Mode.PROPS:
				_cycle_brush(-1)
				return INPUT_STOP
		KEY_BRACKETLEFT:
			if mode == Modes.Mode.PROPS:
				settings.brush_radius = clampf(settings.brush_radius - 1.0, 1.0, 40.0)
				_request_redraw()
				return INPUT_STOP
		KEY_BRACKETRIGHT:
			if mode == Modes.Mode.PROPS:
				settings.brush_radius = clampf(settings.brush_radius + 1.0, 1.0, 40.0)
				_request_redraw()
				return INPUT_STOP
		KEY_H:
			settings.show_hud = not settings.show_hud
			_request_redraw()
			return INPUT_STOP
	return INPUT_PASS


func _delete_hovered() -> int:
	if mode == Modes.Mode.ROUTE and hover_control >= 0 and curve != null:
		_curve_before = capture_curve(curve)
		curve.remove_point(hover_control)
		_refresh_handles([hover_control - 1, hover_control])
		_commit_curve("удалить точку", _curve_before)
		return INPUT_STOP
	return INPUT_PASS


# ------------------------------------------------------------------ подсказка под курсором

func _update_hover(camera: Camera3D, screen_pos: Vector2) -> void:
	hover_valid = false
	hover_control = -1
	hover_zone = -1
	hover_brush_valid = false
	hover_new_valid = false
	if camera == null or not route_ready:
		return
	if profile_rect.has_point(screen_pos) or hud_rect.has_point(screen_pos) or warnings_rect.has_point(screen_pos):
		return
	var sample_index := _nearest_sample_screen(camera, screen_pos, settings.insert_radius_px)
	if sample_index >= 0:
		hover_distance = _sample_distance(sample_index)
		hover_point = _sample_point(sample_index)
		hover_valid = true
		hover_section = _section_index_at(hover_distance)
	if mode == Modes.Mode.ROUTE:
		hover_control = _nearest_control(camera, screen_pos)
		if hover_control >= 0:
			hover_valid = true
			hover_point = curve.get_point_position(hover_control)
			hover_distance = _control_distance(hover_control)
	if mode == Modes.Mode.ZONES:
		var zone := _nearest_zone(camera, screen_pos)
		if not zone.is_empty():
			hover_zone = int(zone.get("index", -1)) + 2
			hover_valid = true
			hover_distance = float(zone.get("distance", 0.0))
			hover_point = Analysis.point_at_distance(samples, hover_distance)
	if mode == Modes.Mode.PROPS:
		var ground := _ray_ground(camera, screen_pos)
		if bool(ground.get("ok", false)):
			hover_brush = ground["point"]
			hover_brush_valid = true
	elif mode == Modes.Mode.ROUTE and not hover_valid:
		var ghost := _ray_ground(camera, screen_pos)
		if bool(ghost.get("ok", false)):
			hover_new_point = ghost["point"]
			hover_new_valid = true


func _hud_contains(point: Vector2) -> bool:
	return hud_rect.has_point(point) or profile_rect.has_point(point) or warnings_rect.has_point(point)


func _scrub_profile(point: Vector2) -> void:
	if length <= 0.0 or profile_rect.size.x < 1.0:
		return
	var t: float = clampf((point.x - profile_rect.position.x) / profile_rect.size.x, 0.0, 1.0)
	selected_distance = t * length
	hover_distance = selected_distance
	hover_point = Analysis.point_at_distance(samples, hover_distance)
	hover_valid = true
	_request_redraw()


# ------------------------------------------------------------------ геометрия/выбор

func _sample_count() -> int:
	var points: PackedVector3Array = samples.get("points", PackedVector3Array())
	return points.size()


func _sample_point(index: int) -> Vector3:
	var points: PackedVector3Array = samples.get("points", PackedVector3Array())
	if points.is_empty():
		return Vector3.ZERO
	return points[clampi(index, 0, points.size() - 1)]


func _sample_distance(index: int) -> float:
	var dists: PackedFloat32Array = samples.get("distances", PackedFloat32Array())
	if dists.is_empty():
		return 0.0
	return dists[clampi(index, 0, dists.size() - 1)]


func _nearest_sample_screen(camera: Camera3D, screen_pos: Vector2, limit_px: float) -> int:
	var points: PackedVector3Array = samples.get("points", PackedVector3Array())
	var best := -1
	var best_dist := limit_px
	for i in range(points.size()):
		if camera.is_position_behind(points[i]):
			continue
		var screen := project_point(camera, points[i])
		var dist := screen.distance_to(screen_pos)
		if dist < best_dist:
			best_dist = dist
			best = i
	return best


func _nearest_control(camera: Camera3D, screen_pos: Vector2) -> int:
	if curve == null:
		return -1
	var best := -1
	var best_dist := settings.handle_radius_px
	for i in range(curve.point_count):
		var world := curve.get_point_position(i)
		if camera.is_position_behind(world):
			continue
		var dist := project_point(camera, world).distance_to(screen_pos)
		if dist < best_dist:
			best_dist = dist
			best = i
	return best


func _control_distance(index: int) -> float:
	if curve == null or index < 0 or index >= curve.point_count:
		return 0.0
	return curve.get_closest_offset(curve.get_point_position(index))


func half_width_at(distance: float) -> float:
	if track != null:
		return track.half_width_at(distance)
	return settings.fallback_half_width


func surface_color(distance: float) -> Color:
	if track != null:
		var section := track.section_at(distance)
		if section != null:
			var index := Analysis.surface_index(section.surface_name, settings.surface_names)
			if index >= 0 and index < settings.surface_colors.size():
				return settings.surface_colors[index]
	return settings.road_edge_color


func _ray_ground(camera: Camera3D, screen_pos: Vector2) -> Dictionary:
	if camera == null:
		return {"ok": false, "point": Vector3.ZERO}
	if _hover_ground_ok and _hover_ground_pos.distance_to(screen_pos) < 2.0 \
			and _hover_ground_camera.is_equal_approx(camera.global_transform):
		return {"ok": true, "point": _hover_ground}
	var origin: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	if dir.y > -0.02:
		return {"ok": false, "point": Vector3.ZERO}
	var t: float = maxf(0.5, camera.near * 4.0)
	var prev_t: float = t
	var prev_diff: float = origin.y + dir.y * t - _ground_y(origin + dir * t)
	var limit: float = 2600.0
	var guard: int = 0
	while t < limit and guard < 200:
		guard += 1
		t += maxf(0.75, t * 0.03)
		var p: Vector3 = origin + dir * t
		var diff: float = p.y - _ground_y(p)
		if diff <= 0.0 and prev_diff > 0.0:
			var lo: float = prev_t
			var hi: float = t
			for _step in range(16):
				var mid: float = (lo + hi) * 0.5
				var q: Vector3 = origin + dir * mid
				if q.y - _ground_y(q) > 0.0:
					lo = mid
				else:
					hi = mid
			var hit: Vector3 = origin + dir * hi
			_hover_ground = hit
			_hover_ground_ok = true
			_hover_ground_pos = screen_pos
			_hover_ground_camera = camera.global_transform
			return {"ok": true, "point": hit}
		prev_t = t
		prev_diff = diff
	var plane_y: float = 0.0
	if curve != null and curve.point_count > 0:
		plane_y = curve.get_point_position(curve.point_count - 1).y
	if absf(dir.y) < 0.0001:
		return {"ok": false, "point": Vector3.ZERO}
	var plane_t: float = (plane_y - origin.y) / dir.y
	if plane_t > 0.0 and plane_t < 6000.0:
		var point: Vector3 = origin + dir * plane_t
		_hover_ground = point
		_hover_ground_ok = true
		_hover_ground_pos = screen_pos
		_hover_ground_camera = camera.global_transform
		return {"ok": true, "point": point}
	return {"ok": false, "point": Vector3.ZERO}


func _ground_y(point: Vector3) -> float:
	if stage != null and stage.has_method("ground_height"):
		return float(stage.call("ground_height", point.x, point.z))
	return 0.0


# ------------------------------------------------------------------ правка кривой

func _append_point(world_point: Vector3) -> int:
	if curve == null:
		return -1
	var point := _snapped_point(world_point)
	curve.add_point(point, Vector3.ZERO, Vector3.ZERO)
	var index: int = curve.point_count - 1
	_refresh_handles([index - 1, index])
	_after_curve_changed()
	return index


func _insert_point(distance: float) -> int:
	if curve == null:
		return -1
	var point := curve.sample_baked(clampf(distance, 0.0, length), true)
	var index := _insertion_index(distance)
	curve.add_point(point, Vector3.ZERO, Vector3.ZERO, index)
	_refresh_handles([index - 1, index, index + 1])
	_after_curve_changed()
	return index


func _insertion_index(distance: float) -> int:
	if curve == null:
		return 0
	for i in range(curve.point_count):
		if curve.get_closest_offset(curve.get_point_position(i)) > distance:
			return i
	return curve.point_count


func _snapped_point(world_point: Vector3) -> Vector3:
	var point := world_point + Vector3.UP * settings.point_height_offset
	if settings.snap_step > 0.0:
		point.x = round(point.x / settings.snap_step) * settings.snap_step
		point.z = round(point.z / settings.snap_step) * settings.snap_step
	return point


func _neighbor(index: int, delta: int) -> int:
	if curve == null or curve.point_count < 2:
		return -1
	if curve.closed:
		return posmod(index + delta, curve.point_count)
	var result := index + delta
	if result < 0 or result >= curve.point_count:
		return -1
	return result


func _refresh_handles(indices: Array) -> void:
	if curve == null or curve.point_count < 2:
		return
	for raw_index in indices:
		var index := int(raw_index)
		if index < 0 or index >= curve.point_count:
			continue
		var point := curve.get_point_position(index)
		var prev_index := _neighbor(index, -1)
		var next_index := _neighbor(index, 1)
		if prev_index < 0 and next_index < 0:
			continue
		if prev_index < 0:
			var forward := curve.get_point_position(next_index) - point
			if forward.length() < 0.001:
				continue
			var out_len := forward.length() * settings.handle_length_ratio
			curve.set_point_in(index, Vector3.ZERO)
			curve.set_point_out(index, forward.normalized() * out_len)
			continue
		if next_index < 0:
			var backward := curve.get_point_position(prev_index) - point
			if backward.length() < 0.001:
				continue
			var in_len := backward.length() * settings.handle_length_ratio
			curve.set_point_in(index, backward.normalized() * in_len)
			curve.set_point_out(index, Vector3.ZERO)
			continue
		var prev_point := curve.get_point_position(prev_index)
		var next_point := curve.get_point_position(next_index)
		var tangent := next_point - prev_point
		if tangent.length() < 0.001:
			continue
		tangent = tangent.normalized()
		var incoming := point.distance_to(prev_point) * settings.handle_length_ratio
		var outgoing := point.distance_to(next_point) * settings.handle_length_ratio
		curve.set_point_in(index, -tangent * incoming)
		curve.set_point_out(index, tangent * outgoing)


func _smooth_route() -> void:
	if curve == null or curve.point_count < 3:
		return
	_curve_before = capture_curve(curve)
	var indices: Array = []
	for i in range(curve.point_count):
		indices.append(i)
	_refresh_handles(indices)
	_after_curve_changed()
	_commit_curve("сгладить трассу", _curve_before)


func capture_curve(source: Curve3D) -> Dictionary:
	var state: Dictionary = {
		"positions": PackedVector3Array(),
		"ins": PackedVector3Array(),
		"outs": PackedVector3Array(),
		"closed": false,
		"bake_interval": 0.5,
	}
	if source == null:
		return state
	var positions := PackedVector3Array()
	var ins := PackedVector3Array()
	var outs := PackedVector3Array()
	for i in range(source.point_count):
		positions.append(source.get_point_position(i))
		ins.append(source.get_point_in(i))
		outs.append(source.get_point_out(i))
	state["positions"] = positions
	state["ins"] = ins
	state["outs"] = outs
	state["closed"] = source.closed
	state["bake_interval"] = source.bake_interval
	return state


## Восстанавливает кривую из снимка. Вызывается и кодом, и UndoRedo.
func apply_curve_state(target: Curve3D, state: Dictionary) -> void:
	if target == null:
		return
	var positions: PackedVector3Array = state.get("positions", PackedVector3Array())
	var ins: PackedVector3Array = state.get("ins", PackedVector3Array())
	var outs: PackedVector3Array = state.get("outs", PackedVector3Array())
	target.clear_points()
	for i in range(positions.size()):
		var point_in := Vector3.ZERO
		var point_out := Vector3.ZERO
		if i < ins.size():
			point_in = ins[i]
		if i < outs.size():
			point_out = outs[i]
		target.add_point(positions[i], point_in, point_out)
	target.closed = bool(state.get("closed", false))
	target.bake_interval = float(state.get("bake_interval", 0.5))
	target.emit_changed()
	_dirty = true
	_request_redraw()


func _after_curve_changed() -> void:
	_dirty = true
	_request_redraw()


func _curve_changed(before: Dictionary, after: Dictionary) -> bool:
	var old_points: PackedVector3Array = before.get("positions", PackedVector3Array())
	var new_points: PackedVector3Array = after.get("positions", PackedVector3Array())
	if old_points != new_points:
		return true
	if bool(before.get("closed", false)) != bool(after.get("closed", false)):
		return true
	return float(before.get("width", 0.0)) != float(after.get("width", 0.0))


func _commit_curve(label: String, before: Dictionary) -> void:
	if curve == null or host == null:
		return
	var after := capture_curve(curve)
	if not _curve_changed(before, after):
		_dirty = true
		_request_redraw()
		return
	var ur := host.get_undo_redo()
	ur.create_action("Студия трассы: " + label)
	ur.add_do_method(self, "apply_curve_state", curve, after)
	ur.add_undo_method(self, "apply_curve_state", curve, before)
	ur.add_do_method(self, "_after_edit")
	ur.add_undo_method(self, "_after_edit")
	ur.commit_action()


# ------------------------------------------------------------------ участки полотна

func _section_index_at(distance: float) -> int:
	if track == null:
		return -1
	var best := -1
	for i in range(track.route_sections.size()):
		var section: Resource = track.route_sections[i]
		if section != null and float(section.get("start_distance")) <= distance:
			best = i
	return best


func _section_for_edit(distance: float) -> Resource:
	if track == null:
		return null
	var nearest := -1
	var nearest_gap := INF
	for i in range(track.route_sections.size()):
		var section: Resource = track.route_sections[i]
		if section == null:
			continue
		var gap := absf(float(section.get("start_distance")) - distance)
		if gap < nearest_gap:
			nearest_gap = gap
			nearest = i
	if nearest >= 0 and nearest_gap <= settings.section_grab_distance:
		return track.route_sections[nearest]
	var created := SectionType.new()
	created.start_distance = distance
	created.title = "Участок %d" % (track.route_sections.size() + 1)
	created.surface_name = track.surface_name
	created.half_width = clampf(track.half_width_at(distance), settings.min_half_width, settings.max_half_width)
	created.road_color = track.road_color
	created.transition_length = settings.section_transition
	var insert_at: int = track.route_sections.size()
	for i in range(track.route_sections.size()):
		var section: Resource = track.route_sections[i]
		if section != null and float(section.get("start_distance")) > distance:
			insert_at = i
			break
	track.route_sections.insert(insert_at, created)
	return created


func _section_state(section: Resource) -> Dictionary:
	if section == null:
		return {}
	return {
		"start": float(section.get("start_distance")),
		"width": float(section.get("half_width")),
		"surface": String(section.get("surface_name")),
		"color": section.get("road_color"),
		"transition": float(section.get("transition_length")),
	}


## Восстанавливает поля участка. Вызывается и кодом, и UndoRedo.
func apply_section_state(section: Resource, state: Dictionary) -> void:
	if section == null or state.is_empty():
		return
	section.set("start_distance", float(state.get("start", 0.0)))
	section.set("half_width", float(state.get("width", 4.0)))
	section.set("surface_name", String(state.get("surface", "")))
	var color = state.get("color")
	if color is Color:
		section.set("road_color", color)
	section.set("transition_length", float(state.get("transition", 100.0)))
	_dirty = true
	_request_redraw()


## Восстанавливает список участков (создание/удаление). UndoRedo-совместимо.
func apply_sections(target: TrackType, snapshot: Array) -> void:
	if target == null:
		return
	target.route_sections.assign(snapshot)
	_dirty = true
	_request_redraw()


func _nearest_width_handle(camera: Camera3D, screen_pos: Vector2) -> Dictionary:
	if not route_ready:
		return {}
	var step: float = maxf(5.0, settings.width_handle_step)
	var distance: float = 0.0
	var best: Dictionary = {}
	var best_dist: float = settings.handle_radius_px * 1.6
	while distance <= length:
		var center := Analysis.point_at_distance(samples, distance)
		var direction := _direction_at_distance(distance)
		var side := Vector3(direction.z, 0.0, -direction.x)
		var half := half_width_at(distance)
		for which in [-1, 1]:
			var world := center + side * half * float(which)
			if camera.is_position_behind(world):
				continue
			var dist := project_point(camera, world).distance_to(screen_pos)
			if dist < best_dist:
				best_dist = dist
				best = {"distance": distance, "side": which}
		distance += step
	return best


func _direction_at_distance(distance: float) -> Vector3:
	var nearest := Analysis.nearest(samples, Analysis.point_at_distance(samples, distance))
	var index := int(nearest.get("index", 0))
	var points: PackedVector3Array = samples.get("points", PackedVector3Array())
	return Analysis.direction_at(points, index)


func _nearest_section_boundary(camera: Camera3D, screen_pos: Vector2) -> int:
	if track == null:
		return -1
	var best := -1
	var best_dist := settings.handle_radius_px
	for i in range(track.route_sections.size()):
		var section: Resource = track.route_sections[i]
		if section == null:
			continue
		var distance := float(section.get("start_distance"))
		if distance < 0.0 or distance > length:
			continue
		var world := Analysis.point_at_distance(samples, distance)
		if camera.is_position_behind(world):
			continue
		var dist := project_point(camera, world).distance_to(screen_pos)
		if dist < best_dist:
			best_dist = dist
			best = i
	return best


func _cycle_surface(direction: int) -> void:
	if track == null or settings.surface_names.is_empty():
		return
	var index := selected_section
	if index < 0 and hover_valid:
		index = _section_index_at(hover_distance)
	if index < 0:
		return
	var section: Resource = track.route_sections[index]
	if section == null:
		return
	_sections_before = track.route_sections.duplicate()
	_section = section
	_section_before = _section_state(section)
	var current := Analysis.surface_index(String(section.get("surface_name")), settings.surface_names)
	var next := posmod(current + direction, settings.surface_names.size())
	section.set("surface_name", settings.surface_names[next])
	if next < settings.surface_colors.size():
		section.set("road_color", settings.surface_colors[next])
	selected_section = index
	_commit_section("покрытие участка")
	_request_redraw()


func _section_changed(before: Dictionary, after: Dictionary) -> bool:
	if before.is_empty() or after.is_empty():
		return false
	if before.size() != after.size():
		return true
	if float(before.get("start", 0.0)) != float(after.get("start", 0.0)):
		return true
	if float(before.get("width", 0.0)) != float(after.get("width", 0.0)):
		return true
	if float(before.get("transition", 0.0)) != float(after.get("transition", 0.0)):
		return true
	if String(before.get("surface", "")) != String(after.get("surface", "")):
		return true
	return before.get("color") != after.get("color")


func _commit_section(label: String) -> void:
	if host == null or track == null or _section == null:
		return
	var after := _section_state(_section)
	if not _section_changed(_section_before, after):
		_dirty = true
		_request_redraw()
		return
	var ur := host.get_undo_redo()
	ur.create_action("Студия трассы: " + label)
	ur.add_do_method(self, "apply_sections", track, track.route_sections.duplicate())
	ur.add_do_method(self, "apply_section_state", _section, after)
	ur.add_undo_method(self, "apply_sections", track, _sections_before.duplicate())
	ur.add_undo_method(self, "apply_section_state", _section, _section_before)
	ur.add_do_method(self, "_after_edit")
	ur.add_undo_method(self, "_after_edit")
	ur.commit_action()


# ------------------------------------------------------------------ зоны

func _spawn_state() -> Dictionary:
	if spawn == null:
		return {}
	return {
		"start": spawn.start_distance,
		"finish": spawn.finish_margin,
		"cps": spawn.custom_checkpoint_distances.duplicate(),
	}


## Восстанавливает старт/финиш/КПП. Вызывается и кодом, и UndoRedo.
func apply_spawn_state(state: Dictionary) -> void:
	if spawn == null or state.is_empty():
		return
	spawn.start_distance = float(state.get("start", spawn.start_distance))
	spawn.finish_margin = float(state.get("finish", spawn.finish_margin))
	var cps: PackedFloat32Array = state.get("cps", PackedFloat32Array())
	spawn.custom_checkpoint_distances = cps
	_dirty = true
	_request_redraw()


func _spawn_changed(before: Dictionary, after: Dictionary) -> bool:
	if before.is_empty() or after.is_empty():
		return false
	if float(before.get("start", 0.0)) != float(after.get("start", 0.0)):
		return true
	if float(before.get("finish", 0.0)) != float(after.get("finish", 0.0)):
		return true
	var old_cps: PackedFloat32Array = before.get("cps", PackedFloat32Array())
	var new_cps: PackedFloat32Array = after.get("cps", PackedFloat32Array())
	return old_cps != new_cps


func _commit_spawn(label: String) -> void:
	if host == null or spawn == null:
		return
	var after := _spawn_state()
	if not _spawn_changed(_spawn_before, after):
		_dirty = true
		_request_redraw()
		return
	var ur := host.get_undo_redo()
	ur.create_action("Студия трассы: " + label)
	ur.add_do_method(self, "apply_spawn_state", after)
	ur.add_undo_method(self, "apply_spawn_state", _spawn_before)
	ur.add_do_method(self, "_after_edit")
	ur.add_undo_method(self, "_after_edit")
	ur.commit_action()


func _checkpoint_distances() -> PackedFloat32Array:
	var result := PackedFloat32Array()
	if spawn == null:
		return result
	if not spawn.custom_checkpoint_distances.is_empty():
		result = spawn.custom_checkpoint_distances.duplicate()
		return result
	if track == null or track.checkpoint_interval <= 0.0 or length <= 0.0:
		return result
	var interval: float = maxf(50.0, track.checkpoint_interval)
	var distance: float = interval
	var limit: float = length - spawn.checkpoint_end_margin
	while distance < limit:
		result.append(distance)
		distance += interval
	return result


## Маркеры старта, финиша и КПП — общий список для рисования и для мыши.
func zone_markers() -> Array:
	var markers: Array = []
	if spawn == null or not route_ready:
		return markers
	markers.append({
		"distance": clampf(spawn.start_distance, 0.0, length),
		"kind": "start",
		"index": 0,
	})
	markers.append({
		"distance": clampf(length - spawn.finish_margin, 0.0, length),
		"kind": "finish",
		"index": 1,
	})
	var cps := _checkpoint_distances()
	for i in range(cps.size()):
		markers.append({"distance": cps[i], "kind": "checkpoint", "index": i})
	return markers


func _nearest_zone(camera: Camera3D, screen_pos: Vector2) -> Dictionary:
	if not route_ready:
		return {}
	var best: Dictionary = {}
	var best_dist := settings.zone_radius_px
	for marker in zone_markers():
		var distance: float = float(marker.get("distance", 0.0))
		var world := Analysis.point_at_distance(samples, distance)
		if camera.is_position_behind(world):
			continue
		var dist := project_point(camera, world).distance_to(screen_pos)
		if dist < best_dist:
			best_dist = dist
			best = marker
	return best


func _cycle_brush(direction: int) -> void:
	var list := brush_props()
	if list.is_empty():
		return
	brush_index = posmod(brush_index + direction, list.size())
	_request_redraw()
	toast("Кисть: " + String(list[brush_index].display_name))


func brush_props() -> Array:
	if prop_library == null:
		return []
	var all: Array = prop_library.spawnable_props()
	if settings.brush_prop_ids.is_empty():
		return all
	var filtered: Array = []
	for prop in all:
		var entry: PropType = prop
		if entry != null and settings.brush_prop_ids.has(entry.id):
			filtered.append(entry)
	return filtered


func _place_brush(world_point: Vector3) -> void:
	var list := brush_props()
	if list.is_empty():
		toast("В библиотеке пропсов нет сцен")
		return
	var props_root := _props_root()
	if props_root == null:
		return
	var placed: int = 0
	var radius: float = maxf(1.0, settings.brush_radius)
	var attempts: int = int(maxf(1.0, radius * 2.0))
	for _i in range(attempts):
		if placed >= settings.brush_max_per_stroke:
			break
		var angle := randf() * TAU
		var distance := sqrt(randf()) * radius
		var candidate := world_point + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		if settings.brush_avoid_road and _too_close_to_road(candidate):
			continue
		if randf() > settings.brush_chance:
			continue
		if _stroke_last.distance_to(candidate) < settings.brush_spacing and placed > 0:
			continue
		var prop: PropType = list[brush_index % list.size()]
		var node := _instantiate_prop(prop, candidate)
		if node == null:
			continue
		_stroke_nodes.append(node)
		_stroke_last = candidate
		placed += 1
	if placed > 0:
		_request_redraw()


func _too_close_to_road(world_point: Vector3) -> bool:
	if not route_ready:
		return false
	var nearest := Analysis.nearest(samples, world_point)
	var offset := absf(float(nearest.get("offset", 0.0)))
	return offset < half_width_at(float(nearest.get("distance", 0.0))) + settings.brush_road_margin


func _props_root() -> Node3D:
	if scene_root == null:
		return null
	var existing := scene_root.get_node_or_null("Props") as Node3D
	if existing != null:
		return existing
	var created := Node3D.new()
	created.name = "Props"
	scene_root.add_child(created)
	created.owner = scene_root
	return created


func _instantiate_prop(prop: PropType, world_point: Vector3) -> Node3D:
	if prop == null or prop.scene == null:
		return null
	var node := prop.scene.instantiate() as Node3D
	if node == null:
		return null
	var size_roll := randf_range(prop.size.x, prop.size.y) * settings.brush_scale
	var width := randf_range(prop.width_jitter.x, prop.width_jitter.y)
	var height := randf_range(prop.height_jitter.x, prop.height_jitter.y)
	node.scale = Vector3(size_roll * width, size_roll * height, size_roll * width)
	if prop.random_yaw:
		node.rotation.y = randf() * TAU
	node.position = Vector3(world_point.x, world_point.y + prop.y_offset * size_roll, world_point.z)
	var props_root := _props_root()
	if props_root == null:
		node.free()
		return null
	props_root.add_child(node)
	node.owner = scene_root
	return node


func _commit_props_placed() -> void:
	if host == null or scene_root == null or _stroke_nodes.is_empty():
		return
	var props_root := _props_root()
	var ur := host.get_undo_redo()
	ur.create_action("Студия трассы: поставить обстановку")
	for raw_node in _stroke_nodes:
		var node: Node3D = raw_node
		if node == null or not is_instance_valid(node):
			continue
		ur.add_do_reference(node)
		ur.add_do_method(self, "_attach_node", node, props_root, scene_root)
		ur.add_undo_method(self, "_detach_node", node)
	ur.add_do_method(self, "_mark_scene_dirty")
	ur.add_undo_method(self, "_mark_scene_dirty")
	ur.add_do_method(self, "_after_edit")
	ur.add_undo_method(self, "_after_edit")
	ur.commit_action()
	_stroke_nodes = []


func _commit_props_erased(node: Node3D) -> void:
	if host == null or scene_root == null or node == null:
		return
	var props_root := _props_root()
	var ur := host.get_undo_redo()
	ur.create_action("Студия трассы: убрать обстановку")
	ur.add_do_method(self, "_detach_node", node)
	ur.add_undo_method(self, "_attach_node", node, props_root, scene_root)
	ur.add_do_reference(node)
	ur.add_do_method(self, "_mark_scene_dirty")
	ur.add_undo_method(self, "_mark_scene_dirty")
	ur.add_do_method(self, "_after_edit")
	ur.add_undo_method(self, "_after_edit")
	ur.commit_action()


func _detach_node(node: Node) -> void:
	if node != null and is_instance_valid(node) and node.get_parent() != null:
		node.get_parent().remove_child(node)
	_dirty = true
	_request_redraw()


func _attach_node(node: Node, parent: Node, owner_node: Node) -> void:
	if node == null or parent == null or not is_instance_valid(node):
		return
	if node.get_parent() == parent:
		return
	parent.add_child(node)
	node.owner = owner_node
	_dirty = true
	_request_redraw()


func _erase_prop(camera: Camera3D, screen_pos: Vector2) -> bool:
	var props_root: Node3D = null
	if scene_root != null:
		props_root = scene_root.get_node_or_null("Props") as Node3D
	if props_root == null:
		return false
	var best: Node3D = null
	var best_dist := settings.brush_radius
	for child in props_root.get_children():
		var node := child as Node3D
		if node == null:
			continue
		var world := node.global_position
		if camera.is_position_behind(world):
			continue
		var dist := project_point(camera, world).distance_to(screen_pos)
		if dist < best_dist:
			best_dist = dist
			best = node
	if best == null:
		return false
	_detach_node(best)
	_commit_props_erased(best)
	return true


# ------------------------------------------------------------------ перетаскивание

func _apply_drag(camera: Camera3D, screen_pos: Vector2) -> void:
	var delta := screen_pos - _last_mouse
	_last_mouse = screen_pos
	match drag_kind:
		"profile":
			_scrub_profile(screen_pos)
		"point":
			_move_control(camera, screen_pos)
		"point_height":
			_move_control_height(delta)
		"width":
			_drag_width(camera, screen_pos)
		"section_start":
			_drag_section_start(camera, screen_pos)
		"paint":
			_paint_drag(camera, screen_pos)
		"start":
			_drag_zone(camera, screen_pos, "start")
		"finish":
			_drag_zone(camera, screen_pos, "finish")
		"checkpoint":
			_drag_zone(camera, screen_pos, "checkpoint")
	_update_hover(camera, screen_pos)


func _end_drag() -> void:
	dragging = false
	match drag_kind:
		"point", "point_height":
			_commit_curve("сдвинуть точку", _curve_before)
		"width", "section_start":
			_commit_section("ширина участка")
		"start", "finish", "checkpoint":
			_commit_spawn("положение зоны")
		"paint":
			_commit_props_placed()
		_:
			_after_edit()
	drag_kind = ""
	_drag_index = -1
	_section = null
	_sections_before = []
	_request_redraw()


func _cancel_drag() -> void:
	if not dragging:
		return
	dragging = false
	match drag_kind:
		"point", "point_height":
			apply_curve_state(curve, _curve_before)
		"width", "section_start":
			apply_sections(track, _sections_before)
			apply_section_state(_section, _section_before)
		"start", "finish", "checkpoint":
			apply_spawn_state(_spawn_before)
		"paint":
			for node in _stroke_nodes:
				_detach_node(node)
			_stroke_nodes = []
	drag_kind = ""
	_drag_index = -1
	_section = null
	_dirty = true
	_request_redraw()


func _move_control(camera: Camera3D, screen_pos: Vector2) -> void:
	if curve == null or _drag_index < 0 or _drag_index >= curve.point_count:
		return
	var ground := _ray_ground(camera, screen_pos)
	var target: Vector3
	if not bool(ground.get("ok", false)):
		target = curve.get_point_position(_drag_index)
	else:
		target = _snapped_point(ground["point"])
	curve.set_point_position(_drag_index, target)
	_refresh_handles([_drag_index - 1, _drag_index, _drag_index + 1])
	selected_distance = _control_distance(_drag_index)
	_dirty = true
	_request_redraw()


func _move_control_height(delta: Vector2) -> void:
	if curve == null or _drag_index < 0 or _drag_index >= curve.point_count:
		return
	var current := curve.get_point_position(_drag_index)
	var pixels := maxf(0.01, _pixels_per_meter(_camera, current))
	var meters := -delta.y / pixels * settings.vertical_drag_scale
	curve.set_point_position(_drag_index, current + Vector3(0.0, meters, 0.0))
	_refresh_handles([_drag_index - 1, _drag_index, _drag_index + 1])
	selected_distance = _control_distance(_drag_index)
	_dirty = true
	_request_redraw()



func _pixels_per_meter(camera: Camera3D, world: Vector3) -> float:
	if camera == null or camera.is_position_behind(world):
		return 1.0
	var base := project_point(camera, world)
	var above := project_point(camera, world + Vector3.UP * 5.0)
	return base.distance_to(above) / 5.0


func _drag_width(camera: Camera3D, screen_pos: Vector2) -> void:
	if _section == null:
		return
	var ground := _ray_ground(camera, screen_pos)
	if not bool(ground.get("ok", false)):
		return
	var nearest := Analysis.nearest(samples, ground["point"])
	var offset := absf(float(nearest.get("offset", 0.0)))
	var width := clampf(offset, settings.min_half_width, settings.max_half_width)
	_section.set("half_width", width)
	_dirty = true
	_request_redraw()


## Километраж под курсором (или -1, если луч не нашёл землю).
func _distance_at_screen(camera: Camera3D, screen_pos: Vector2) -> float:
	if not route_ready:
		return -1.0
	if camera == null:
		return hover_distance
	var ground := _ray_ground(camera, screen_pos)
	if bool(ground.get("ok", false)):
		var nearest := Analysis.nearest(samples, ground["point"])
		return float(nearest.get("distance", -1.0))
	return -1.0


func _drag_section_start(camera: Camera3D, screen_pos: Vector2) -> void:
	if _section == null or not route_ready:
		return
	var distance := _distance_at_screen(camera, screen_pos)
	if distance < 0.0:
		distance = hover_distance
	distance = clampf(distance, 0.0, length)
	var step: float = maxf(1.0, settings.width_handle_step * 0.1)
	distance = round(distance / step) * step
	_section.set("start_distance", distance)
	_dirty = true
	_request_redraw()


func _drag_zone(camera: Camera3D, screen_pos: Vector2, kind: String) -> void:
	if spawn == null or not route_ready:
		return
	var distance := _distance_at_screen(camera, screen_pos)
	if distance < 0.0:
		distance = hover_distance
	if distance < 0.0:
		return
	distance = clampf(distance + _zone_grab, 0.0, length)
	match kind:
		"start":
			spawn.start_distance = distance
		"finish":
			spawn.finish_margin = maxf(0.0, length - distance)
		"checkpoint":
			var cps := _checkpoint_distances()
			if _drag_index >= 0 and _drag_index < cps.size():
				cps[_drag_index] = distance
				spawn.custom_checkpoint_distances = cps
	_dirty = true
	_request_redraw()


func _paint_drag(camera: Camera3D, screen_pos: Vector2) -> void:
	var ground := _ray_ground(camera, screen_pos)
	if not bool(ground.get("ok", false)):
		return
	var point: Vector3 = ground["point"]
	if _stroke_last.distance_to(point) < settings.brush_spacing:
		return
	_stroke_last = point
	_place_brush(point)


# ------------------------------------------------------------------ сборка и сохранение

func rebuild_stage() -> void:
	if stage == null or not is_instance_valid(stage) or not stage.has_method("rebuild_preview"):
		return
	# Сборка мира асинхронная и идёт по кадрам: плагин только запускает её.
	# Точное время печатает сам RallyStage в панель «Вывод».
	building = true
	_building_timer = maxf(0.5, settings.build_feedback_seconds)
	var started := Time.get_ticks_msec()
	stage.call("rebuild_preview")
	last_build_seconds = float(Time.get_ticks_msec() - started) / 1000.0
	needs_rebuild = false
	_dirty = true
	_mark_scene_dirty()
	_refresh_analysis()
	_request_redraw()
	toast("Пересборка мира запущена")


## Вызывается UndoRedo (и кодом) после любой правки.
func _after_edit() -> void:
	if host == null:
		return
	_dirty = true
	needs_rebuild = true
	_save_resources()
	_schedule_rebuild()
	_request_redraw()


## Пометить сцену изменённой: правка добавила/убрала узлы (обстановка, мир).
func _mark_scene_dirty() -> void:
	if host == null:
		return
	var interface := host.get_editor_interface()
	if interface != null:
		interface.mark_scene_as_unsaved()


## Правка «числовых» параметров мира из дока (рельеф, насыпь, свет).
func world_param_changed() -> void:
	_dirty = true
	needs_rebuild = true
	_save_resources()
	_schedule_rebuild()
	_request_redraw()


func _schedule_rebuild() -> void:
	if settings != null and settings.auto_rebuild:
		_rebuild_timer = maxf(0.2, settings.auto_rebuild_delay)
	else:
		_rebuild_timer = 0.0


## Записать правленые ресурсы на диск (кнопка «Сохранить»).
func save_now() -> void:
	_save_resource(curve)
	_save_resource(track)
	_save_resource(spawn)


func _save_resources() -> void:
	if settings == null or not settings.save_resources_on_commit:
		return
	save_now()


func _save_resource(resource: Resource) -> void:
	if resource == null or not is_instance_valid(resource):
		return
	if resource.resource_path.is_empty():
		return
	if not resource.resource_path.begins_with("res://"):
		return
	ResourceSaver.save(resource, resource.resource_path)


func toast(message: String) -> void:
	if host == null:
		return
	var interface := host.get_editor_interface()
	if interface == null:
		return
	if interface.has_method("get_editor_toaster"):
		var toaster := interface.get_editor_toaster()
		if toaster != null and toaster.has_method("push_toast"):
			toaster.push_toast(message)
			return
	print("Студия трассы: " + message)
