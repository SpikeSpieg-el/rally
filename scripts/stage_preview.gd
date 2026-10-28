## Мини-карта трассы в меню. Рисует ту же осевую линию (Curve3D), из которой
## строится заезд, — никакой отдельной «генерации для превью» больше нет.
## Процедурная трасса плетётся здесь же (с общим кэшем генератора), поэтому
## заезд стартует по уже готовой кривой.
extends Control

const TrackConfigType = preload("res://scripts/data/rally_track_config.gd")

## Трасса построена (кэш генератора заполнен) — меню может уточнить длину.
signal track_built(track: TrackConfigType)

@export var background_color: Color = Color(0.025, 0.045, 0.065, 1.0)
@export var grid_color: Color = Color(0.10, 0.16, 0.19, 1.0)
@export var road_color: Color = Color(0.72, 0.58, 0.36, 1.0)
@export var accent_color: Color = Color(1.0, 0.58, 0.08, 1.0)
@export_range(2.0, 12.0, 0.5) var road_line_width: float = 5.0

var track: TrackConfigType = null
var _points: PackedVector2Array = PackedVector2Array()
var _checkpoints: PackedVector2Array = PackedVector2Array()
var _length: float = 0.0
var _generating: bool = false


func set_track(new_track: TrackConfigType) -> void:
	track = new_track
	if track != null and track.procedural:
		# Плетение занимает секунды: сначала показываем статус, даём кадру
		# прорисоваться и только потом строим. Кэш общий с заездом, поэтому
		# второй раз это мгновенно.
		var had_curve: bool = track.get_metadata_curve() != null
		if had_curve:
			_generating = false
			_rebuild(true)
			queue_redraw()
			return
		_generating = true
		_points = PackedVector2Array()
		_checkpoints = PackedVector2Array()
		_length = 0.0
		queue_redraw()
		var tree := get_tree()
		if tree == null:
			return
		await tree.create_timer(0.05).timeout
		if track != new_track:
			# пока плелись, выбрали другую трассу
			return
		_rebuild(true)
		_generating = false
		queue_redraw()
		track_built.emit(track)
		return
	_generating = false
	_rebuild(false)
	queue_redraw()


## force_build: процедурную трассу строим по-настоящему (тяжело, но один раз);
## обычную — берём как есть. Метаданным без сборки хватает get_metadata_curve().
func _rebuild(force_build: bool) -> void:
	_points = PackedVector2Array()
	_checkpoints = PackedVector2Array()
	_length = 0.0
	if track == null:
		return
	var curve: Curve3D = track.get_effective_curve() if force_build else track.get_metadata_curve()
	if curve == null:
		return
	var baked: PackedVector3Array = curve.get_baked_points()
	for p in baked:
		_points.append(Vector2(p.x, p.z))
	_length = curve.get_baked_length()
	if track.checkpoint_interval > 0.0 and _length > 0.0:
		var d: float = track.checkpoint_interval
		while d < _length - 40.0:
			var p: Vector3 = curve.sample_baked(d)
			_checkpoints.append(Vector2(p.x, p.z))
			d += track.checkpoint_interval


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, background_color)
	_draw_grid(rect)
	if _points.size() < 2:
		if _generating:
			_draw_text(Vector2(16.0, 16.0), "ПЛЕТЁМ ТРАССУ…")
		else:
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
	var surface_line: String = track.surface_name if track != null else ""
	_draw_text(Vector2(margin, size.y - 24.0), "%.0f м  •  %s" % [_length, surface_line])


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
