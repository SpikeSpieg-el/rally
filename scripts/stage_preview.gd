## Мини-карта и «живая лента» трассы в меню.
##
## Рисует ту же осевую линию (Curve3D), из которой строится заезд, — никакой
## отдельной «генерации для превью» нет. Под картой идёт НАСТОЯЩАЯ лента:
## профиль высот по километражу, раскрашенный под выбранную трассу и погоду.
##
## Процедурная «Живая лента» плетётся здесь же (с общим кэшем генератора),
## поэтому заезд стартует по уже готовой кривой. Ключ генерации включает
## сид: нажали «перегенерировать» — превью честно переплетает карту,
## а старые ленты остаются в кэше и возвращаются мгновенно.
extends Control

const TrackConfigType = preload("res://scripts/data/rally_track_config.gd")
const WeatherType = preload("res://scripts/data/rally_weather_config.gd")
const ProfileType = preload("res://scripts/data/rally_track_profile.gd")

## Трасса построена (кэш генератора заполнен) — меню может уточнить длину.
signal track_built(track: TrackConfigType)

@export var background_color: Color = Color(0.025, 0.045, 0.065, 1.0)
@export var grid_color: Color = Color(0.10, 0.16, 0.19, 1.0)
@export var road_color: Color = Color(0.72, 0.58, 0.36, 1.0)
@export var accent_color: Color = Color(1.0, 0.58, 0.08, 1.0)
@export_range(2.0, 12.0, 0.5) var road_line_width: float = 5.0
## Высота ленты профиля внизу превью, px. 0 — не рисовать.
@export_range(0.0, 120.0, 1.0) var profile_tape_height: float = 52.0

var track: TrackConfigType = null
var weather: WeatherType = null
var profile: ProfileType = null
var _points: PackedVector2Array = PackedVector2Array()
var _checkpoints: PackedVector2Array = PackedVector2Array()
var _heights := PackedFloat32Array()
var _length: float = 0.0
var _generating: bool = false
var _generating_key: String = ""
var _built_key: String = ""
var _default_road_color := Color(0.72, 0.58, 0.36, 1.0)


func _ready() -> void:
	_default_road_color = road_color


## Условия заезда влияют на вид превью: асфальт серый, снег светлый,
## дождливое небо приглушает фон. Сама геометрия не меняется.
func set_conditions(new_weather: WeatherType, new_profile: ProfileType) -> void:
	weather = new_weather
	profile = new_profile
	if profile != null and profile.override_road_colors:
		road_color = profile.road_color
	else:
		road_color = _default_road_color
	queue_redraw()


func set_track(new_track: TrackConfigType) -> void:
	track = new_track
	if track == null:
		_points = PackedVector2Array()
		_checkpoints = PackedVector2Array()
		_heights.clear()
		_length = 0.0
		_generating = false
		queue_redraw()
		return
	if track.procedural:
		var key := _track_key(track)
		if key == _built_key:
			# Эта же трасса уже сплетена (возможно, только что) — только перерисовать.
			queue_redraw()
			return
		if _generating and key == _generating_key:
			# Уже плетём ровно эту трассу: второй await не нужен.
			return
		if track.get_metadata_curve() != null:
			_built_key = key
			_generating = false
			_rebuild(true)
			queue_redraw()
			return
		# Плетение занимает секунды: сначала статус, даём кадру прорисоваться.
		_generating = true
		_generating_key = key
		_points = PackedVector2Array()
		_checkpoints = PackedVector2Array()
		_heights.clear()
		_length = 0.0
		queue_redraw()
		var tree := get_tree()
		if tree == null:
			return
		await tree.create_timer(0.05).timeout
		_generating = false
		_generating_key = ""
		if track != new_track or _track_key(track) != key:
			# пока ждали кадр, выбрали другую трассу или новый сид
			return
		_rebuild(true)
		_built_key = key
		queue_redraw()
		track_built.emit(track)
		return
	_generating = false
	_built_key = _track_key(track)
	_rebuild(false)
	queue_redraw()


## Ключ «эта трасса с этим сидом и этими параметрами». По нему меню понимает,
## надо ли переплетать карту после кнопки «перегенерировать».
func _track_key(source: TrackConfigType) -> String:
	if source == null:
		return ""
	return "%s|%d|%.0f|%.0f|%.1f|%.1f" % [
		source.id,
		source.generation_seed,
		source.procedural_length_min,
		source.procedural_length_max,
		source.procedural_min_radius,
		source.procedural_min_gap,
	]


## force_build: процедурную трассу строим по-настоящему (тяжело, но один раз);
## обычную — берём как есть. Метаданным без сборки хватает get_metadata_curve().
func _rebuild(force_build: bool) -> void:
	_points = PackedVector2Array()
	_checkpoints = PackedVector2Array()
	_heights.clear()
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
	_build_height_tape(curve)
	if track.checkpoint_interval > 0.0 and _length > 0.0:
		var d: float = track.checkpoint_interval
		while d < _length - 40.0:
			var p: Vector3 = curve.sample_baked(d)
			_checkpoints.append(Vector2(p.x, p.z))
			d += track.checkpoint_interval


## Лента профиля: высота осевой линии через каждые ~50 м.
func _build_height_tape(curve: Curve3D) -> void:
	_heights.clear()
	var length: float = curve.get_baked_length()
	if length <= 1.0:
		return
	var samples: int = clampi(int(length / 50.0), 24, 220)
	for i in range(samples):
		var distance: float = length * float(i) / float(maxi(1, samples - 1))
		_heights.append(curve.sample_baked(distance).y)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, _background_color())
	_draw_grid(rect)
	if _points.size() < 2:
		if _generating:
			_draw_text(Vector2(16.0, 16.0), "ПЛЕТЁМ ТРАССУ…")
		else:
			_draw_text(Vector2(16.0, 16.0), "НЕТ ОСЕВОЙ ЛИНИИ")
		_draw_status_line()
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
	var tape_space: float = 0.0
	if profile_tape_height > 0.0:
		tape_space = profile_tape_height + 18.0
	var usable := Rect2(
		margin,
		margin,
		maxf(10.0, size.x - margin * 2.0),
		maxf(10.0, size.y - margin * 2.0 - tape_space)
	)
	var pad: float = 14.0
	var span_x: float = maxf(1.0, max_x - min_x + pad * 2.0)
	var span_z: float = maxf(1.0, max_z - min_z + pad * 2.0)
	var map_scale: float = minf(usable.size.x / span_x, usable.size.y / span_z)
	var offset := Vector2(
		usable.position.x + usable.size.x * 0.5 - (min_x - pad + span_x * 0.5) * map_scale,
		usable.position.y + usable.size.y * 0.5 - (min_z - pad + span_z * 0.5) * map_scale
	)
	var screen := PackedVector2Array()
	for p in _points:
		screen.append(Vector2(p.x * map_scale + offset.x, p.y * map_scale + offset.y))

	draw_polyline(screen, road_color.darkened(0.55), road_line_width + 5.0, true)
	draw_polyline(screen, road_color, road_line_width, true)

	for cp in _checkpoints:
		var point := Vector2(cp.x * map_scale + offset.x, cp.y * map_scale + offset.y)
		draw_rect(Rect2(point.x - 3.0, point.y - 3.0, 6.0, 6.0), Color(0.95, 0.85, 0.20), true)

	var start: Vector2 = screen[0]
	var finish: Vector2 = screen[screen.size() - 1]
	draw_circle(start, 5.5, Color(0.2, 0.8, 1.0))
	draw_circle(finish, 5.5, accent_color)
	_draw_text(Vector2(margin, margin - 12.0), "СТАРТ / ФИНИШ")
	if profile_tape_height > 0.0:
		_draw_height_tape(Rect2(margin, size.y - profile_tape_height - 24.0,
			maxf(40.0, size.x - margin * 2.0), profile_tape_height))
	_draw_status_line()


## Цвет неба с поправкой погоды — та же формула, что и в заезде
## (rally_stage.gd::_weather_sky_color), чтобы фон превью не спорил с небом
## на старте: подмешать тон пресета и обесцветить.
func _weather_sky_color(base: Color) -> Color:
	var result: Color = base.lerp(weather.sky_tint, weather.sky_tint_strength)
	if weather.sky_desaturation > 0.0:
		var luminance: float = result.get_luminance()
		result = result.lerp(
			Color(luminance, luminance, luminance, result.a), weather.sky_desaturation
		)
	return result


func _background_color() -> Color:
	if weather == null or String(weather.id) == "default":
		return background_color
	# Горизонт неба живёт в конфиге трассы; у погоды есть только её тон.
	var horizon: Color = track.sky_horizon_color if track != null else weather.sky_tint
	return background_color.lerp(_weather_sky_color(horizon), 0.10)


## Нижняя «живая лента»: профиль высот по всей длине трассы.
func _draw_height_tape(rect: Rect2) -> void:
	if _heights.size() < 2 or rect.size.x < 40.0:
		return
	draw_rect(rect, Color(0.03, 0.06, 0.08, 0.85))
	draw_rect(rect, grid_color.lightened(0.25), false, 1.0)
	var min_h: float = _heights[0]
	var max_h: float = _heights[0]
	for h in _heights:
		min_h = minf(min_h, h)
		max_h = maxf(max_h, h)
	var span: float = maxf(4.0, max_h - min_h)
	var tape_points := PackedVector2Array()
	for i in range(_heights.size()):
		var t: float = float(i) / float(_heights.size() - 1)
		var x: float = rect.position.x + 4.0 + t * (rect.size.x - 8.0)
		var y: float = rect.end.y - 4.0 - ((_heights[i] - min_h) / span) * (rect.size.y - 8.0)
		tape_points.append(Vector2(x, y))
	# Заливка под лентой — «земля», поверх — сама линия профиля.
	var fill := tape_points.duplicate()
	fill.append(Vector2(rect.end.x - 4.0, rect.end.y - 4.0))
	fill.append(Vector2(rect.position.x + 4.0, rect.end.y - 4.0))
	draw_colored_polygon(fill, road_color.darkened(0.45))
	draw_polyline(tape_points, accent_color, 2.0, true)
	var font: Font = get_theme_default_font()
	if font != null:
		var label := "ПЕРЕПАД %.0f М  •  %.0f—%.0f М" % [max_h - min_h, min_h, max_h]
		draw_string(
			font, Vector2(rect.position.x + 6.0, rect.position.y - 4.0),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, accent_color
		)


func _draw_status_line() -> void:
	if track == null:
		return
	var surface_line: String = track.surface_name
	if profile != null and not profile.surface_name.is_empty():
		surface_line = profile.surface_name
	var parts := PackedStringArray()
	if _length > 0.0:
		parts.append("%.0f м" % _length)
	else:
		parts.append("ДЛИНА ?")
	parts.append(surface_line)
	if weather != null:
		parts.append(weather.get_summary())
	if track.procedural:
		parts.append("СИД %d" % track.generation_seed)
	_draw_text(Vector2(26.0, size.y - 20.0), "  •  ".join(parts))


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


func _draw_text(pos: Vector2, value: String) -> void:
	var font: Font = get_theme_default_font()
	if font != null:
		draw_string(font, pos + Vector2(0.0, 14.0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, accent_color)
