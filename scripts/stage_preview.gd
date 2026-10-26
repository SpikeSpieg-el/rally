## Мини-карта трассы в меню. Рисует тот же маршрут, который создаст
## scripts/rally_stage.gd: параметры берутся из ресурса RallyTrackConfig.
extends Control

const TrackConfigType = preload("res://scripts/data/rally_track_config.gd")

@export var background_color: Color = Color(0.025, 0.045, 0.065, 1.0)
@export var grid_color: Color = Color(0.10, 0.16, 0.19, 1.0)
@export var road_color: Color = Color(0.72, 0.58, 0.36, 1.0)
@export var accent_color: Color = Color(1.0, 0.58, 0.08, 1.0)
@export_range(2.0, 12.0, 0.5) var road_line_width: float = 5.0

var track: TrackConfigType = null
var seed_value: int = 1337
var random_stage: bool = false
var _params: Array = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]


func set_track(new_track: TrackConfigType, new_seed: int, is_random: bool) -> void:
	track = new_track
	seed_value = maxi(1, absi(new_seed))
	random_stage = is_random
	if track != null:
		_params = track.get_route_parameters(seed_value, random_stage)
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, background_color)
	_draw_grid(rect)
	if track == null:
		_draw_text(rect.get_center() - Vector2(80, 0), "НЕТ ДАННЫХ")
		return

	var margin: float = 18.0
	var usable_width: float = maxf(10.0, size.x - margin * 2.0)
	var usable_height: float = maxf(10.0, size.y - margin * 2.0)
	var max_x: float = maxf(12.0, track.curve_amplitude + track.secondary_curve_amplitude + track.road_half_width + 12.0)
	var scale_x: float = usable_width / (max_x * 2.0)
	var scale_z: float = usable_height / maxf(10.0, track.length)
	var center: Vector2 = Vector2(size.x * 0.5, size.y - margin)
	var z_start: float = -track.length * 0.5

	var points := PackedVector2Array()
	var steps: int = 120
	for i in range(steps + 1):
		var z: float = z_start + track.length * float(i) / float(steps)
		var x: float = track.route_center(z, _params)
		points.append(Vector2(center.x + x * scale_x, center.y - (z - z_start) * scale_z))

	draw_polyline(points, road_color.darkened(0.55), road_line_width + 5.0, true)
	draw_polyline(points, road_color, road_line_width, true)

	# Деревья и камни — та же функция сида, что и у генератора сцены.
	for i in range(90):
		var u: float = _hash_unit(seed_value, 20.0 + float(i) * 1.7)
		var v: float = _hash_unit(seed_value, 90.0 + float(i) * 2.3)
		var z: float = z_start + track.length * v
		var side: float = 1.0 if u > 0.5 else -1.0
		var offset: float = side * (track.road_half_width + 4.0 + u * max_x * 0.7)
		var x: float = track.route_center(z, _params) + offset
		var point := Vector2(center.x + x * scale_x, center.y - (z - z_start) * scale_z)
		draw_circle(point, 1.6, track.tree_color.lightened(0.35))

	var finish: Vector2 = points[points.size() - 1]
	var start: Vector2 = points[0]
	draw_circle(start, 5.0, Color(0.2, 0.8, 1.0))
	draw_circle(finish, 5.0, accent_color)
	_draw_text(Vector2(margin, margin), "СТАРТ / ФИНИШ")
	_draw_text(Vector2(margin, size.y - 10.0), "SEED %d  •  %.0f м  •  %s" % [seed_value, track.length, track.surface_name])


func _hash_unit(value: int, salt: float) -> float:
	var x: float = sin(float(absi(value) % 100000) * 0.01723 + salt * 12.9898) * 43758.5453
	return x - floor(x)


func _draw_grid(rect: Rect2) -> void:
	var cell: float = 32.0
	var x: float = cell
	while x < rect.size.x:
		draw_line(Vector2(x, 0.0), Vector2(x, rect.size.y), grid_color, 1.0)
		x += cell
	var y: float = cell
	while y < rect.size.y:
		draw_line(Vector2(0.0, y), Vector2(rect.size.x, y), grid_color, 1.0)
		y += cell
	draw_rect(rect, grid_color.lightened(0.25), false, 2.0)


func _draw_text(position: Vector2, value: String) -> void:
	var font: Font = get_theme_default_font()
	if font != null:
		draw_string(font, position + Vector2(0.0, 14.0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, accent_color)
