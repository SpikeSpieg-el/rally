## Мини-карта спецучастка. Рисует осевую линию, старт/финиш, контрольные
## точки, машину и «пройденный» отрезок.
class_name MiniMap
extends Control

@export_group("Стиль")
@export var background_color: Color = Color(0.04, 0.055, 0.08, 0.72)
@export var grid_color: Color = Color(1.0, 1.0, 1.0, 0.03)
@export var border_color: Color = Color(1.0, 1.0, 1.0, 0.12)
@export var route_color: Color = Color(0.85, 0.90, 0.96, 0.55)
@export var route_glow_color: Color = Color(0.0, 0.0, 0.0, 0.45)
@export var checkpoint_color: Color = Color(0.98, 0.82, 0.25, 0.9)
@export var start_color: Color = Color(0.30, 0.88, 1.0, 1.0)
@export var finish_color: Color = Color(1.0, 0.45, 0.12, 1.0)
@export var progress_color: Color = Color(1.0, 0.52, 0.12, 1.0)
@export var car_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var show_grid: bool = true
@export var show_route: bool = true
@export var show_checkpoints: bool = true
@export var show_car: bool = true
@export_range(0.5, 4.0, 0.1) var route_line_width: float = 2.2

var route: PackedVector2Array = PackedVector2Array()
var checkpoints: PackedVector2Array = PackedVector2Array()
var start_point: Vector2 = Vector2.ZERO
var finish_point: Vector2 = Vector2.ZERO
var car_position: Vector2 = Vector2.ZERO
var car_heading: float = 0.0
var has_car: bool = false
var progress: float = 0.0

var _screen: PackedVector2Array = PackedVector2Array()
var _scale: float = 1.0
var _offset: Vector2 = Vector2.ZERO


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_compute_transform()
		queue_redraw()


func set_route(new_route: PackedVector2Array, new_checkpoints: PackedVector2Array, new_start: Vector2, new_finish: Vector2) -> void:
	route = new_route
	checkpoints = new_checkpoints
	start_point = new_start
	finish_point = new_finish
	_compute_transform()
	queue_redraw()


func set_car(position: Vector2, heading: float) -> void:
	car_position = position
	car_heading = heading
	has_car = true
	queue_redraw()


func clear_car() -> void:
	has_car = false
	queue_redraw()


func set_progress(value: float) -> void:
	progress = clampf(value, 0.0, 1.0)
	queue_redraw()


func _compute_transform() -> void:
	_screen.clear()
	_scale = 1.0
	_offset = Vector2.ZERO
	if route.is_empty() or size.x <= 1.0 or size.y <= 1.0:
		return
	var min_x: float = INF
	var min_z: float = INF
	var max_x: float = -INF
	var max_z: float = -INF
	for p in route:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.y)
		max_z = maxf(max_z, p.y)
	var margin: float = 18.0
	var usable_w: float = maxf(8.0, size.x - margin * 2.0)
	var usable_h: float = maxf(8.0, size.y - margin * 2.0)
	var span_x: float = maxf(1.0, max_x - min_x)
	var span_z: float = maxf(1.0, max_z - min_z)
	_scale = minf(usable_w / span_x, usable_h / span_z)
	var center_world := Vector2((min_x + max_x) * 0.5, (min_z + max_z) * 0.5)
	_offset = size * 0.5 - center_world * _scale
	for p in route:
		_screen.append(p * _scale + _offset)


func _to_screen(p: Vector2) -> Vector2:
	return p * _scale + _offset


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	
	# Скругленная карточка в едином стиле с HUD
	var panel := StyleBoxFlat.new()
	panel.bg_color = background_color
	panel.border_color = border_color
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(10)
	panel.shadow_color = Color(0, 0, 0, 0.28)
	panel.shadow_size = 8
	panel.shadow_offset = Vector2(0, 3)
	draw_style_box(panel, rect)

	if show_grid:
		_draw_grid(rect)

	if route.is_empty():
		return

	if _screen.is_empty():
		_compute_transform()

	if show_route and _screen.size() >= 2:
		# Контрастная подложка + линия трассы
		draw_polyline(_screen, route_glow_color, route_line_width + 3.0, true)
		draw_polyline(_screen, route_color, route_line_width, true)

	# Пройденный участок рисуем строго по точкам маршрута
	if has_car and _screen.size() >= 2:
		var along_index: int = _nearest_route_index(car_position)
		if along_index >= 1:
			var passed := _screen.slice(0, along_index + 1)
			draw_polyline(passed, progress_color, route_line_width + 0.8, true)

	if show_checkpoints:
		for cp in checkpoints:
			var point := _to_screen(cp)
			draw_circle(point, 2.5, checkpoint_color)

	# Старт и финиш с аккуратным темным контуром
	var sp := _to_screen(start_point)
	var fp := _to_screen(finish_point)
	draw_circle(sp, 5.0, Color(0, 0, 0, 0.6))
	draw_circle(sp, 3.8, start_color)
	draw_circle(fp, 5.0, Color(0, 0, 0, 0.6))
	draw_circle(fp, 3.8, finish_color)

	# Курсор машины
	if show_car and has_car:
		var car_screen := _to_screen(car_position)
		var s: float = 7.5
		var pts := PackedVector2Array([
			Vector2(0.0, -s),
			Vector2(s * 0.65, s * 0.65),
			Vector2(0.0, s * 0.3),
			Vector2(-s * 0.65, s * 0.65)
		])
		var rotated := PackedVector2Array()
		for p in pts:
			rotated.append(car_screen + p.rotated(-car_heading))
		draw_circle(car_screen, s * 0.85, Color(0, 0, 0, 0.45))
		draw_colored_polygon(rotated, car_color)


func _nearest_route_index(p: Vector2) -> int:
	var best: int = 0
	var best_dist: float = INF
	var sp := _to_screen(p)
	for i in range(_screen.size()):
		var d: float = sp.distance_squared_to(_screen[i])
		if d < best_dist:
			best_dist = d
			best = i
	return best


func _draw_grid(rect: Rect2) -> void:
	# Деликатное перекрестие вместо навязчивой клетки
	var cx: float = rect.size.x * 0.5
	var cy: float = rect.size.y * 0.5
	draw_line(Vector2(cx, 10.0), Vector2(cx, rect.size.y - 10.0), grid_color, 1.0)
	draw_line(Vector2(10.0, cy), Vector2(rect.size.x - 10.0, cy), grid_color, 1.0)
