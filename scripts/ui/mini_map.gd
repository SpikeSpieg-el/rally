## Мини-карта спецучастка. Рисует осевую линию, старт/финиш, контрольные
## точки, машину и «пройденный» отрезок. Используется и в меню (без машины),
## и в HUD заезда.
##
## Весь масштаб считается сам: маршрут масштабируется по себе с отступом,
## поэтому карта подходит и для прямой стартовой прямой, и для тесных шпилек.
class_name MiniMap
extends Control

@export_group("Стиль")
@export var background_color: Color = Color(0.03, 0.05, 0.07, 0.94)
@export var grid_color: Color = Color(0.12, 0.18, 0.22, 1.0)
@export var border_color: Color = Color(0.30, 0.42, 0.50, 1.0)
@export var route_color: Color = Color(0.78, 0.64, 0.38, 1.0)
@export var route_glow_color: Color = Color(0.78, 0.64, 0.38, 0.22)
@export var checkpoint_color: Color = Color(0.96, 0.86, 0.22, 1.0)
@export var start_color: Color = Color(0.28, 0.88, 1.0, 1.0)
@export var finish_color: Color = Color(1.0, 0.50, 0.10, 1.0)
@export var progress_color: Color = Color(0.30, 0.95, 0.55, 1.0)
@export var car_color: Color = Color(1.0, 0.95, 0.85, 1.0)
@export var show_grid: bool = true
@export var show_route: bool = true
@export var show_checkpoints: bool = true
@export var show_car: bool = true
@export_range(0.0, 2.0, 0.05) var route_line_width: float = 1.0

## Маршрут (план XZ), обычно — выборка осевой линии через 2–4 м.
var route: PackedVector2Array = PackedVector2Array()
## Положения контрольных точек (план XZ).
var checkpoints: PackedVector2Array = PackedVector2Array()
var start_point: Vector2 = Vector2.ZERO
var finish_point: Vector2 = Vector2.ZERO
## Положение и направление машины (0 = по маршруту).
var car_position: Vector2 = Vector2.ZERO
var car_heading: float = 0.0
var has_car: bool = false
## 0..1 — сколько маршрута уже пройдено (по ближайшей точке).
var progress: float = 0.0

var _screen: PackedVector2Array = PackedVector2Array()
var _scale: float = 1.0
var _offset: Vector2 = Vector2.ZERO


func set_route(new_route: PackedVector2Array, new_checkpoints: PackedVector2Array, new_start: Vector2, new_finish: Vector2) -> void:
	route = new_route
	checkpoints = new_checkpoints
	start_point = new_start
	finish_point = new_finish
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
	if route.is_empty():
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
	var margin: float = 14.0
	var usable := Rect2(margin, margin, maxf(8.0, size.x - margin * 2.0), maxf(8.0, size.y - margin * 2.0))
	var span_x: float = maxf(1.0, max_x - min_x + margin * 2.0)
	var span_z: float = maxf(1.0, max_z - min_z + margin * 2.0)
	_scale = minf(usable.size.x / span_x, usable.size.y / span_z)
	_offset = Vector2(
		usable.position.x + usable.size.x * 0.5 - (min_x - margin + span_x * 0.5) * _scale,
		usable.position.y + usable.size.y * 0.5 - (min_z - margin + span_z * 0.5) * _scale
	)
	for p in route:
		_screen.append(Vector2(p.x * _scale + _offset.x, p.y * _scale + _offset.y))


func _to_screen(p: Vector2) -> Vector2:
	return Vector2(p.x * _scale + _offset.x, p.y * _scale + _offset.y)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, background_color)
	if show_grid:
		_draw_grid(rect)
	draw_rect(rect, border_color, false, 2.0)

	if route.is_empty():
		_draw_text(Vector2(10.0, 10.0), "НЕТ МАРШРУТА", Color(0.7, 0.75, 0.8, 1.0))
		return

	if show_route:
		# Свечение под полотном + основная линия.
		draw_polyline(_screen, route_glow_color, route_line_width + 5.0, true)
		draw_polyline(_screen, route_color, route_line_width, true)

	if show_checkpoints:
		for cp in checkpoints:
			var point := _to_screen(cp)
			draw_rect(Rect2(point.x - 3.0, point.y - 3.0, 6.0, 6.0), checkpoint_color, true)

	# Старт и финиш.
	draw_circle(_to_screen(start_point), 5.5, start_color)
	draw_circle(_to_screen(finish_point), 5.5, finish_color)

	# Пройденный отрезок: от старта до projection машины по маршруту.
	if has_car:
		var along_index: int = _nearest_route_index(car_position)
		if along_index > 0 and along_index < _screen.size():
			var from := _screen[0]
			var to := _screen[along_index]
			draw_line(from, to, progress_color, 3.0)
			draw_circle(to, 4.0, progress_color)

	# Машина.
	if show_car and has_car:
		var car_screen := _to_screen(car_position)
		var heading: float = car_heading
		var size: float = 9.0
		var points := PackedVector2Array()
		points.append(car_screen + Vector2(0.0, -size))
		points.append(car_screen + Vector2(size * 0.62, size * 0.62))
		points.append(car_screen + Vector2(-size * 0.62, size * 0.62))
		points.append(car_screen)
		# Поворот «носом» вверх по маршруту: экран +Y вниз, поэтому
		# вращаем на -heading, чтобы стрелка смотрела по направлению движения.
		var basis := Basis2D.create_from_angle(-heading)
		var rotated := PackedVector2Array()
		for p in points:
			rotated.append((basis * (p - car_screen)) + car_screen)
		draw_colored_polygon(rotated, car_color)
		draw_circle(car_screen, 3.0, Color(0.05, 0.05, 0.05, 1.0))


func _nearest_route_index(p: Vector2) -> int:
	var best: int = 0
	var best_dist: float = INF
	for i in range(_screen.size()):
		var d: float = _to_screen(p).distance_to(_screen[i])
		if d < best_dist:
			best_dist = d
			best = i
	return best


func _draw_grid(rect: Rect2) -> void:
	var cell: float = 24.0
	var x: float = cell
	while x < rect.size.x:
		draw_line(Vector2(x, 0.0), Vector2(x, rect.size.y), grid_color, 1.0)
		x += cell
	var y: float = cell
	while y < rect.size.y:
		draw_line(Vector2(0.0, y), Vector2(rect.size.x, y), grid_color, 1.0)
		y += cell


func _draw_text(position: Vector2, value: String, color: Color) -> void:
	var font: Font = get_theme_default_font()
	if font != null:
		draw_string(font, position, value, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
