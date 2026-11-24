## Сенсорные кнопки для общего гоночного HUD.
## Каждый палец хранит своё действие: руль и педаль можно нажимать одновременно.
class_name RallyTouchControls
extends Control

signal pause_requested

const STEER_TINT := Color(1.0, 0.48, 0.12, 1.0)
const THROTTLE_TINT := Color(0.22, 0.92, 0.48, 1.0)
const BRAKE_TINT := Color(1.0, 0.30, 0.22, 1.0)
const HANDBRAKE_TINT := Color(0.35, 0.72, 1.0, 1.0)
const PAUSE_TINT := Color(0.92, 0.95, 1.0, 1.0)

## Для проверки раскладки в редакторе; в обычном запуске показываем элементы
## только на сенсорном устройстве.
@export var force_visible: bool = false

var _touch_device_detected: bool = false
var _zones: Array[Dictionary] = []
## finger id -> action
var _touch_actions: Dictionary = {}
## action -> число удерживающих палец пальцев
var _action_holds: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_touch_device_detected = force_visible or _is_touch_device()
	resized.connect(_rebuild_zones)
	_rebuild_zones()
	call_deferred("_rebuild_zones")
	_refresh_visibility()


func _process(_delta: float) -> void:
	_refresh_visibility()


func _exit_tree() -> void:
	_release_all()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		# В некоторых браузерах is_touchscreen_available() сообщает false до
		# первого PointerEvent. Первый реальный тап включает тот же HUD.
		if touch.pressed and not _touch_device_detected and OS.has_feature("web"):
			_touch_device_detected = true
			_rebuild_zones()
			_refresh_visibility()
		if not touch.pressed:
			if _touch_actions.has(touch.index):
				_release_touch(touch.index)
				get_viewport().set_input_as_handled()
			return
		if not visible or _input_blocked():
			return
		var action := _action_at(_screen_to_local(touch.position))
		if action.is_empty():
			return
		_set_touch_action(touch.index, action)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if not _touch_actions.has(drag.index):
			return
		if _input_blocked():
			_release_touch(drag.index)
			get_viewport().set_input_as_handled()
			return
		var next_action := _action_at(_screen_to_local(drag.position))
		if next_action != String(_touch_actions[drag.index]):
			_set_touch_action(drag.index, next_action)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_release_all()


func _is_touch_device() -> bool:
	if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available():
		return true
	# Fallback для мобильного WebGL, если браузер не передал свойство touch
	# движку до первого нажатия. Большие desktop-вьюпорты кнопки не получают.
	var viewport_size := get_viewport_rect().size
	return OS.has_feature("web") and minf(viewport_size.x, viewport_size.y) <= 720.0


func _refresh_visibility() -> void:
	var should_show := (force_visible or _touch_device_detected) and _gameplay_controls_available()
	if visible == should_show:
		return
	visible = should_show
	if not should_show:
		_release_all()
	queue_redraw()


func _gameplay_controls_available() -> bool:
	if not is_inside_tree() or get_tree().paused:
		return false
	var hud_root := get_parent()
	if hud_root == null:
		return true
	for panel_name in ["PausePanel", "ResultsPanel", "InputSettings"]:
		var panel := hud_root.get_node_or_null(panel_name) as CanvasItem
		if panel != null and panel.visible:
			return false
	return true


func _input_blocked() -> bool:
	return not visible or not _gameplay_controls_available()


func _rebuild_zones() -> void:
	_zones.clear()
	if size.x <= 0.0 or size.y <= 0.0:
		queue_redraw()
		return

	var short_side := minf(size.x, size.y)
	var margin := clampf(short_side * 0.04, 10.0, 30.0)
	var side := minf(clampf(short_side * 0.18, 52.0, 122.0), size.x * 0.20)
	side = maxf(side, 44.0)
	var gap := maxf(7.0, side * 0.13)
	var bottom_y := maxf(0.0, size.y - margin - side)
	var right_group_left := size.x - margin - (side * 2.0) - gap

	_add_zone(
		"steer_left", "◀", Rect2(Vector2(margin, bottom_y), Vector2(side, side)), STEER_TINT
	)
	_add_zone(
		"steer_right", "▶", Rect2(Vector2(margin + side + gap, bottom_y), Vector2(side, side)),
		STEER_TINT
	)
	_add_zone(
		"brake", "ТОРМОЗ", Rect2(Vector2(right_group_left, bottom_y), Vector2(side, side)), BRAKE_TINT
	)
	_add_zone(
		"throttle", "ГАЗ", Rect2(Vector2(size.x - margin - side, bottom_y), Vector2(side, side)),
		THROTTLE_TINT
	)

	var aux_side := side * 0.70
	var brake_x := right_group_left + (side - aux_side) * 0.5
	var handbrake_y := maxf(margin, bottom_y - aux_side - gap)
	_add_zone(
		"handbrake", "РУЧНИК",
		Rect2(Vector2(brake_x, handbrake_y), Vector2(aux_side, aux_side)),
		HANDBRAKE_TINT
	)

	var pause_side := side * 0.62
	_add_zone(
		"pause", "Ⅱ",
		Rect2(Vector2((size.x - pause_side) * 0.5, bottom_y), Vector2(pause_side, pause_side)),
		PAUSE_TINT
	)
	queue_redraw()


func _add_zone(action: String, label: String, rect: Rect2, tint: Color) -> void:
	_zones.append({
		"action": action,
		"label": label,
		"rect": rect,
		"tint": tint,
	})


func _action_at(point: Vector2) -> String:
	# При пересечении областей выигрывает меньшая кнопка, добавленная позже.
	for index in range(_zones.size() - 1, -1, -1):
		var zone: Dictionary = _zones[index]
		var rect: Rect2 = zone["rect"]
		if rect.has_point(point):
			return String(zone["action"])
	return ""


func _screen_to_local(screen_position: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_position


func _set_touch_action(finger: int, action: String) -> void:
	var previous := String(_touch_actions.get(finger, ""))
	if previous == action:
		return
	if not previous.is_empty():
		_release_touch(finger)
	if action.is_empty():
		return

	_touch_actions[finger] = action
	var held_count := int(_action_holds.get(action, 0))
	_action_holds[action] = held_count + 1
	if held_count == 0:
		if action == "pause":
			pause_requested.emit()
		else:
			Input.action_press(action, 1.0)
	queue_redraw()


func _release_touch(finger: int) -> void:
	if not _touch_actions.has(finger):
		return
	var action := String(_touch_actions[finger])
	_touch_actions.erase(finger)
	var held_count := int(_action_holds.get(action, 0))
	if held_count <= 1:
		_action_holds.erase(action)
		if action != "pause":
			Input.action_release(action)
	else:
		_action_holds[action] = held_count - 1
	queue_redraw()


func _release_all() -> void:
	for finger in _touch_actions.keys().duplicate():
		_release_touch(int(finger))


func _draw() -> void:
	if _zones.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	for zone: Dictionary in _zones:
		var rect: Rect2 = zone["rect"]
		var action := String(zone["action"])
		var tint: Color = zone["tint"]
		var is_pressed := int(_action_holds.get(action, 0)) > 0
		var center := rect.get_center()
		var radius := minf(rect.size.x, rect.size.y) * 0.5
		var fill_alpha := 0.14 if not is_pressed else 0.54
		var ring_alpha := 0.76 if not is_pressed else 1.0
		draw_circle(center, radius, Color(0.015, 0.025, 0.04, 0.58))
		draw_circle(center, radius - 3.0, Color(tint.r, tint.g, tint.b, fill_alpha))
		draw_arc(
			center, radius - 1.5, 0.0, TAU, 40,
			Color(tint.r, tint.g, tint.b, ring_alpha),
			maxf(2.0, radius * 0.055), true
		)
		var font_scale := 0.48 if action in ["steer_left", "steer_right", "pause"] else 0.27
		var font_size := clampi(roundi(radius * font_scale), 11, 27)
		var baseline := center.y + float(font_size) * 0.36
		draw_string(
			font, Vector2(rect.position.x, baseline), String(zone["label"]),
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size,
			Color(0.96, 0.98, 1.0, 0.98)
		)
