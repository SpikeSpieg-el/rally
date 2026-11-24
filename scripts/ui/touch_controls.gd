## Сенсорные кнопки для общего гоночного HUD.
## Каждый палец хранит своё действие: руль, газ, тормоз и передачи можно
## нажимать одновременно. Размер считается от короткой стороны экрана, а область
## касания шире видимого круга, чтобы промахиваться было сложнее.
## Передачи: в автомате «R» (назад) и «D» (вперёд); в ручной — стрелки ▼ ▲;
## в ручной с педалью дополнительно «СЦЕП». Стрелки и паузу рисуем полигонами,
## чтобы не зависеть от наличия символов в шрифте браузера.
class_name RallyTouchControls
extends Control

signal pause_requested

const STEER_TINT := Color(1.0, 0.48, 0.12, 1.0)
const THROTTLE_TINT := Color(0.22, 0.92, 0.48, 1.0)
const BRAKE_TINT := Color(1.0, 0.30, 0.22, 1.0)
const HANDBRAKE_TINT := Color(0.35, 0.72, 1.0, 1.0)
const PAUSE_TINT := Color(0.92, 0.95, 1.0, 1.0)
const GEAR_TINT := Color(0.98, 0.84, 0.30, 1.0)
const CLUTCH_TINT := Color(0.74, 0.58, 1.0, 1.0)
const INK := Color(0.96, 0.98, 1.0, 0.98)

## Значения совпадают с RallyCarSetup.Transmission и RallyGame.transmission_index.
const GameSettings = preload("res://scripts/ui/game_settings.gd")
const TRANSMISSION_AUTOMATIC := 0
const TRANSMISSION_MANUAL_CLUTCH := 2

## Главные педали и руль — доля короткой стороны экрана (раньше было 0.18).
const MAIN_SIDE_RATIO := 0.24
const MAIN_SIDE_MIN := 64.0
const MAIN_SIDE_MAX := 132.0
## Browser/телефон: проект рисуется в 1080 px по короткой стороне, поэтому
## кнопка 26 % ≈ 280 px ≈ 13–15 мм на экране. Прежний потолок 132 px давал ~6 мм.
const WEB_MAIN_SIDE_RATIO := 0.26
const WEB_MAIN_SIDE_MIN := 200.0
const WEB_MAIN_SIDE_MAX := 340.0
## Вспомогательные кнопки — доли главной.
const HANDBRAKE_RATIO := 0.70
const GEAR_RATIO := 0.60
const CLUTCH_RATIO := 0.70
const PAUSE_RATIO := 0.50
## Размер текста относительно радиуса круга.
const TEXT_LABEL_SCALE := 0.30
const SHORT_LABEL_SCALE := 0.50

## Для проверки раскладки в редакторе; в обычном запуске показываем элементы
## только на сенсорном устройстве.
@export var force_visible: bool = false

var _touch_device_detected: bool = false
var _zones: Array[Dictionary] = []
## finger id -> action
var _touch_actions: Dictionary = {}
## action -> число удерживающих палец пальцев
var _action_holds: Dictionary = {}
## Ключ раскладки (коробка передач). При смене в меню зоны пересобираем.
var _layout_key: String = ""
var _game: Node = null


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
	var key := str(_transmission_index())
	if key != _layout_key:
		_layout_key = key
		_rebuild_zones()


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


## Коробка из главного меню (RallyGame). Нет автозагрузки — считаем автоматом.
func _transmission_index() -> int:
	if _game == null or not is_instance_valid(_game):
		_game = get_node_or_null("/root/RallyGame")
	if _game == null:
		return TRANSMISSION_AUTOMATIC
	var value: Variant = _game.get("transmission_index")
	return int(value) if value != null else TRANSMISSION_AUTOMATIC


func _rebuild_zones() -> void:
	_zones.clear()
	if size.x <= 0.0 or size.y <= 0.0:
		queue_redraw()
		return

	var short_side := minf(size.x, size.y)
	var margin := clampf(short_side * 0.03, 8.0, 24.0)
	var gap := maxf(8.0, short_side * 0.03)
	var side := _main_side(short_side)
	# В узком экране (портрет) кнопки не должны налезать друг на друга.
	side = minf(side, (size.x - 2.0 * margin - 2.0 * gap) * 0.25)
	side = maxf(side, 44.0)

	var bottom_y := maxf(0.0, size.y - margin - side)
	var throttle_x := size.x - margin - side
	var brake_x := throttle_x - gap - side
	var handbrake := side * HANDBRAKE_RATIO
	var handbrake_x := brake_x + (side - handbrake) * 0.5
	var handbrake_y := maxf(margin, bottom_y - handbrake - gap)
	var gear := side * GEAR_RATIO
	var gear_x := throttle_x + (side - gear) * 0.5
	var gear_down_y := maxf(margin, bottom_y - gap - gear)
	var gear_up_y := maxf(margin, gear_down_y - gap - gear)
	var transmission := _transmission_index()
	var automatic := transmission == TRANSMISSION_AUTOMATIC

	# Левая группа — руль.
	_add_zone("steer_left", "", Rect2(Vector2(margin, bottom_y), Vector2(side, side)), STEER_TINT)
	_add_zone(
		"steer_right", "",
		Rect2(Vector2(margin + side + gap, bottom_y), Vector2(side, side)), STEER_TINT
	)
	# Правая группа — тормоз и газ; ручник над тормозом; передачи над газом.
	_add_zone("brake", "ТОРМОЗ", Rect2(Vector2(brake_x, bottom_y), Vector2(side, side)), BRAKE_TINT)
	_add_zone(
		"throttle", "ГАЗ", Rect2(Vector2(throttle_x, bottom_y), Vector2(side, side)), THROTTLE_TINT
	)
	_add_zone(
		"handbrake", "РУЧНИК",
		Rect2(Vector2(handbrake_x, handbrake_y), Vector2(handbrake, handbrake)), HANDBRAKE_TINT
	)
	_add_zone(
		"shift_down", "R" if automatic else "",
		Rect2(Vector2(gear_x, gear_down_y), Vector2(gear, gear)), GEAR_TINT
	)
	_add_zone(
		"shift_up", "D" if automatic else "",
		Rect2(Vector2(gear_x, gear_up_y), Vector2(gear, gear)), GEAR_TINT
	)
	if transmission == TRANSMISSION_MANUAL_CLUTCH:
		var clutch := side * CLUTCH_RATIO
		var clutch_x := brake_x + (side - clutch) * 0.5
		var clutch_y := maxf(margin, handbrake_y - gap - clutch)
		_add_zone("clutch", "СЦЕП", Rect2(Vector2(clutch_x, clutch_y), Vector2(clutch, clutch)), CLUTCH_TINT)

	var pause_side := side * PAUSE_RATIO
	_add_zone(
		"pause", "",
		Rect2(Vector2((size.x - pause_side) * 0.5, bottom_y), Vector2(pause_side, pause_side)),
		PAUSE_TINT
	)
	queue_redraw()


func _main_side(short_side: float) -> float:
	if GameSettings.is_low_power_runtime():
		return clampf(short_side * WEB_MAIN_SIDE_RATIO, WEB_MAIN_SIDE_MIN, WEB_MAIN_SIDE_MAX)
	return clampf(short_side * MAIN_SIDE_RATIO, MAIN_SIDE_MIN, MAIN_SIDE_MAX)


func _add_zone(action: String, label: String, rect: Rect2, tint: Color) -> void:
	# Область касания шире круга на несколько пикселей: палец почти всегда
	# попадает чуть мимо видимой кнопки.
	var pad := clampf(minf(rect.size.x, rect.size.y) * 0.12, 4.0, 14.0)
	_zones.append({
		"action": action,
		"label": label,
		"rect": rect,
		"hit": rect.grow(pad),
		"tint": tint,
	})


func _action_at(point: Vector2) -> String:
	# При пересечении областей выигрывает кнопка, добавленная позже.
	for index in range(_zones.size() - 1, -1, -1):
		var zone: Dictionary = _zones[index]
		var hit: Rect2 = zone["hit"]
		if hit.has_point(point):
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
	for zone: Dictionary in _zones:
		var rect: Rect2 = zone["rect"]
		var action := String(zone["action"])
		var label := String(zone["label"])
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
		if label.is_empty():
			_draw_icon(action, center, radius)
		elif font != null:
			var text_scale: float = SHORT_LABEL_SCALE if label.length() <= 2 else TEXT_LABEL_SCALE
			var font_size := clampi(roundi(radius * text_scale), 11, 27)
			var baseline := center.y + float(font_size) * 0.36
			draw_string(
				font, Vector2(rect.position.x, baseline), label,
				HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, INK
			)


## Стрелки и пауза из полигонов: не зависят от шрифта браузера.
func _draw_icon(action: String, center: Vector2, radius: float) -> void:
	var s := radius * 0.42
	match action:
		"steer_left":
			_fill_triangle(center + Vector2(-s, 0.0), center + Vector2(s * 0.5, -s), center + Vector2(s * 0.5, s))
		"steer_right":
			_fill_triangle(center + Vector2(s, 0.0), center + Vector2(-s * 0.5, -s), center + Vector2(-s * 0.5, s))
		"shift_up":
			_fill_triangle(center + Vector2(0.0, -s), center + Vector2(s, s * 0.6), center + Vector2(-s, s * 0.6))
		"shift_down":
			_fill_triangle(center + Vector2(0.0, s), center + Vector2(s, -s * 0.6), center + Vector2(-s, -s * 0.6))
		"pause":
			var bar := s * 0.42
			draw_rect(Rect2(center + Vector2(-s * 0.7, -s * 0.8), Vector2(bar, s * 1.6)), INK)
			draw_rect(Rect2(center + Vector2(s * 0.28, -s * 0.8), Vector2(bar, s * 1.6)), INK)


func _fill_triangle(a: Vector2, b: Vector2, c: Vector2) -> void:
	draw_colored_polygon(PackedVector2Array([a, b, c]), INK)
