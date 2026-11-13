## Мини-карта спецучастка. Рисует осевую линию, старт/финиш, контрольные
## точки, машину и «пройденный» отрезок. Поддерживает единый пиксельный стиль
## HUD через RallyHudStyle / pixel_mode.
@tool
class_name MiniMap
extends Control

@export var hud_style: RallyHudStyle:
	set(v):
		if hud_style != null and hud_style.changed.is_connected(_on_hud_style_changed):
			hud_style.changed.disconnect(_on_hud_style_changed)
		hud_style = v
		if hud_style != null and not hud_style.changed.is_connected(_on_hud_style_changed):
			hud_style.changed.connect(_on_hud_style_changed)
		_apply_hud_style_sync()

@export_group("Стиль")
@export var pixel_mode: bool = false:
	set(v):
		pixel_mode = v
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if pixel_mode else CanvasItem.TEXTURE_FILTER_LINEAR
		queue_redraw()
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
@export_group("Геометрия и тени")
## Скругление карточки, px.
@export_range(0, 40, 1) var corner_radius: int = 10
@export_range(0, 4, 1) var border_width: int = 1
@export var shadow_color: Color = Color(0, 0, 0, 0.28)
@export_range(0, 32, 1) var shadow_size: int = 8
@export var shadow_offset: Vector2 = Vector2(0, 3)
## Подложка под маркерами старта/финиша и машины.
@export var marker_outline_color: Color = Color(0, 0, 0, 0.6)
@export_range(0.0, 20.0, 0.1) var start_marker_radius: float = 3.8
@export_range(0.0, 20.0, 0.1) var checkpoint_radius: float = 2.5
@export_range(0.0, 40.0, 0.1) var car_marker_size: float = 7.5

var route: PackedVector2Array = PackedVector2Array()
var checkpoints: PackedVector2Array = PackedVector2Array()
var start_point: Vector2 = Vector2.ZERO
var finish_point: Vector2 = Vector2.ZERO
var car_position: Vector2 = Vector2.ZERO
var car_heading: float = 0.0
var has_car: bool = false
var progress: float = 0.0
var _has_progress: bool = false

var _screen: PackedVector2Array = PackedVector2Array()
var _scale: float = 1.0
var _offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	_apply_hud_style_sync()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_compute_transform()
		queue_redraw()


func set_hud_style(style_res: RallyHudStyle) -> void:
	hud_style = style_res


func _on_hud_style_changed() -> void:
	_apply_hud_style_sync()


func _apply_hud_style_sync() -> void:
	if hud_style == null:
		return
	if hud_style.is_pixel_mode():
		pixel_mode = true
		background_color = hud_style.panel_bg_color
		border_color = hud_style.panel_border_color
		border_width = hud_style.border_width
		corner_radius = hud_style.corner_radius
		shadow_size = hud_style.shadow_size
		grid_color = Color(hud_style.panel_border_color.r, hud_style.panel_border_color.g, hud_style.panel_border_color.b, 0.14)
		progress_color = hud_style.panel_accent_color
		finish_color = hud_style.panel_accent_color
	else:
		pixel_mode = false
		background_color = Color(0.04, 0.055, 0.08, 0.72)
		border_color = Color(1.0, 1.0, 1.0, 0.12)
		border_width = 1
		corner_radius = 10
		shadow_size = 8
		grid_color = Color(1.0, 1.0, 1.0, 0.03)
	queue_redraw()


func set_route(new_route: PackedVector2Array, new_checkpoints: PackedVector2Array, new_start: Vector2, new_finish: Vector2) -> void:
	route.clear()
	var count: int = mini(1400, new_route.size())
	for i in range(count):
		var index: int = roundi(float(i) * float(new_route.size() - 1) / float(maxi(1, count - 1)))
		route.append(new_route[index])
	_has_progress = false
	checkpoints = new_checkpoints
	start_point = new_start
	finish_point = new_finish
	_compute_transform()
	queue_redraw()


func set_car(car_pos: Vector2, heading: float) -> void:
	car_position = car_pos
	car_heading = heading
	has_car = true
	queue_redraw()


func clear_car() -> void:
	has_car = false
	queue_redraw()


func set_progress(val: float) -> void:
	_has_progress = true
	progress = clampf(val, 0.0, 1.0)
	queue_redraw()


func _compute_transform() -> void:
	_screen.clear()
	_scale = 1.0
	_offset = Vector2.ZERO
	var w := self.size.x
	var h := self.size.y
	if route.is_empty() or w <= 1.0 or h <= 1.0:
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
	var usable_w: float = maxf(8.0, w - margin * 2.0)
	var usable_h: float = maxf(8.0, h - margin * 2.0)
	var span_x: float = maxf(1.0, max_x - min_x)
	var span_z: float = maxf(1.0, max_z - min_z)
	_scale = minf(usable_w / span_x, usable_h / span_z)
	var center_world := Vector2((min_x + max_x) * 0.5, (min_z + max_z) * 0.5)
	_offset = Vector2(w, h) * 0.5 - center_world * _scale
	for p in route:
		var pt := p * _scale + _offset
		_screen.append(pt.round() if pixel_mode else pt)


func _to_screen(p: Vector2) -> Vector2:
	var pt := p * _scale + _offset
	return pt.round() if pixel_mode else pt


func _draw() -> void:
	var w := self.size.x
	var h := self.size.y
	var rect := Rect2(Vector2.ZERO, Vector2(w, h))

	var panel := StyleBoxFlat.new()
	panel.bg_color = background_color
	panel.border_color = border_color
	panel.set_border_width_all(border_width)
	panel.set_corner_radius_all(0 if pixel_mode else corner_radius)
	panel.shadow_color = shadow_color
	panel.shadow_size = 0 if pixel_mode else shadow_size
	panel.shadow_offset = shadow_offset
	draw_style_box(panel, rect)

	if show_grid:
		_draw_grid(rect)

	if route.is_empty():
		return

	if _screen.is_empty():
		_compute_transform()

	var aa := not pixel_mode
	if show_route and _screen.size() >= 2:
		draw_polyline(_screen, route_glow_color, route_line_width + 3.0, aa)
		draw_polyline(_screen, route_color, route_line_width, aa)

	if has_car and _screen.size() >= 2:
		var along_index: int = clampi(roundi(progress * float(_screen.size() - 1)), 0, _screen.size() - 1) if _has_progress else _nearest_route_index(car_position)
		if along_index >= 1:
			var passed := _screen.slice(0, along_index + 1)
			draw_polyline(passed, progress_color, route_line_width + 0.8, aa)

	if show_checkpoints:
		for cp in checkpoints:
			var point := _to_screen(cp)
			if pixel_mode:
				var r := checkpoint_radius
				draw_rect(Rect2(point - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), checkpoint_color, true)
			else:
				draw_circle(point, checkpoint_radius, checkpoint_color)

	var sp := _to_screen(start_point)
	var fp := _to_screen(finish_point)
	if pixel_mode:
		var sr := start_marker_radius
		draw_rect(Rect2(sp - Vector2(sr + 1.0, sr + 1.0), Vector2((sr + 1.0) * 2.0, (sr + 1.0) * 2.0)), marker_outline_color, true)
		draw_rect(Rect2(sp - Vector2(sr, sr), Vector2(sr * 2.0, sr * 2.0)), start_color, true)
		draw_rect(Rect2(fp - Vector2(sr + 1.0, sr + 1.0), Vector2((sr + 1.0) * 2.0, (sr + 1.0) * 2.0)), marker_outline_color, true)
		draw_rect(Rect2(fp - Vector2(sr, sr), Vector2(sr * 2.0, sr * 2.0)), finish_color, true)
	else:
		draw_circle(sp, start_marker_radius + 1.2, marker_outline_color)
		draw_circle(sp, start_marker_radius, start_color)
		draw_circle(fp, start_marker_radius + 1.2, marker_outline_color)
		draw_circle(fp, start_marker_radius, finish_color)

	if show_car and has_car:
		var car_screen := _to_screen(car_position)
		var s: float = car_marker_size
		var pts := PackedVector2Array([
			Vector2(0.0, -s),
			Vector2(s * 0.65, s * 0.65),
			Vector2(0.0, s * 0.3),
			Vector2(-s * 0.65, s * 0.65)
		])
		var rotated := PackedVector2Array()
		for p in pts:
			rotated.append(car_screen + p.rotated(-car_heading))
		draw_circle(car_screen, s * 0.85, marker_outline_color)
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
	if pixel_mode:
		var step := 24.0
		var x := step
		while x < rect.size.x - 4.0:
			draw_line(Vector2(x, 6.0), Vector2(x, rect.size.y - 6.0), grid_color, 1.0)
			x += step
		var y := step
		while y < rect.size.y - 4.0:
			draw_line(Vector2(6.0, y), Vector2(rect.size.x - 6.0, y), grid_color, 1.0)
			y += step
		return
	var cx: float = rect.size.x * 0.5
	var cy: float = rect.size.y * 0.5
	draw_line(Vector2(cx, 10.0), Vector2(cx, rect.size.y - 10.0), grid_color, 1.0)
	draw_line(Vector2(10.0, cy), Vector2(rect.size.x - 10.0, cy), grid_color, 1.0)
