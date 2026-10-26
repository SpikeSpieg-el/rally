## Мини-карта трассы в меню. Рисует ту же осевую линию (Curve3D), из которой
## строится заезд, — никакой отдельной «генерации для превью» больше нет.
extends Control

const TrackConfigType = preload("res://scripts/data/rally_track_config.gd")

@export var background_color: Color = Color(0.025, 0.045, 0.065, 1.0)
@export var grid_color: Color = Color(0.10, 0.16, 0.19, 1.0)
@export var road_color: Color = Color(0.72, 0.58, 0.36, 1.0)
@export var accent_color: Color = Color(1.0, 0.58, 0.08, 1.0)
@export_range(2.0, 12.0, 0.5) var road_line_width: float = 5.0

var track: TrackConfigType = null
var _points: PackedVector2Array = PackedVector2Array()
var _checkpoints: PackedVector2Array = PackedVector2Array()
var _length: float = 0.0


func set_track(new_track: TrackConfigType) -> void:
	track = new_track
	_rebuild()
	queue_redraw()


func _rebuild() -> void:
	_points = PackedVector2Array()
	_checkpoints = PackedVector2Array()
	_length = 0.0
	if track == null or track.road_curve == null:
		return
	var baked: PackedVector3Array = track.road_curve.get_baked_points()
	for p in baked:
		_points.append(Vector2(p.x, p.z))
	_length = track.road_curve.get_baked_length()
	if track.checkpoint_interval > 0.0 and _length > 0.0:
		var d: float = track.checkpoint_interval
		while d < _length - 40.0:
			var p: Vector3 = track.road_curve.sample_baked(d)
			_checkpoints.append(Vector2(p.x, p.z))
			d += track.checkpoint_interval


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, background_color)
	_draw_grid(rect)
	if _points.size() < 2:
		_draw_text(Vector2(16.0, 16.0), "НЕТ ОСЕВОЙ ЛИНИИ")
		return

	var min_x: float = INF
	var min_z: float = INF
	var max_x: float = -INF
	var max_z: float = -INF
	for p in _points:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.y)
		max_z = maxf(max_z, p.y)
	var margin: float = 26.0
	var usable := Rect2(margin, margin, maxf(10.0, size.x - margin * 2.0), maxf(10.0, size.y - margin * 2.0))
	var pad: float = 14.0
	var span_x: float = maxf(1.0, max_x - min_x + pad * 2.0)
	var span_z: float = maxf(1.0, max_z - min_z + pad * 2.0)
	var scale: float = minf(usable.size.x / span_x, usable.size.y / span_z)
	var offset := Vector2(
		usable.position.x + usable.size.x * 0.5 - (min_x - pad + span_x * 0.5) * scale,
		usable.position.y + usable.size.y * 0.5 - (min_z - pad + span_z * 0.5) * scale
	)
	var screen := PackedVector2Array()
	for p in _points:
		screen.append(Vector2(p.x * scale + offset.x, p.y * scale + offset.y))

	draw_polyline(screen, road_color.darkened(0.55), road_line_width + 5.0, true)
	draw_polyline(screen, road_color, road_line_width, true)

	for cp in _checkpoints:
		var point := Vector2(cp.x * scale + offset.x, cp.y * scale + offset.y)
		draw_rect(Rect2(point.x - 3.0, point.y - 3.0, 6.0, 6.0), Color(0.95, 0.85, 0.20), true)

	var start: Vector2 = screen[0]
	var finish: Vector2 = screen[screen.size() - 1]
	draw_circle(start, 5.5, Color(0.2, 0.8, 1.0))
	draw_circle(finish, 5.5, accent_color)
	_draw_text(Vector2(margin, margin - 12.0), "СТАРТ / ФИНИШ")
	_draw_text(Vector2(margin, size.y - 24.0), "%.0f м  •  %s" % [_length, track.surface_name])


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
