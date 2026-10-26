## Мини-карта трассы в меню. Рисует тот же маршрут, который создаст
## scripts/rally_stage.gd: шпильки, дуги, шифты, КПП — один источник истины
## (scripts/data/rally_route.gd).
extends Control

const TrackConfigType = preload("res://scripts/data/rally_track_config.gd")
const RouteType = preload("res://scripts/data/rally_route.gd")

@export var background_color: Color = Color(0.025, 0.045, 0.065, 1.0)
@export var grid_color: Color = Color(0.10, 0.16, 0.19, 1.0)
@export var road_color: Color = Color(0.72, 0.58, 0.36, 1.0)
@export var accent_color: Color = Color(1.0, 0.58, 0.08, 1.0)
@export_range(2.0, 12.0, 0.5) var road_line_width: float = 5.0

var track: TrackConfigType = null
var seed_value: int = 1337
var random_stage: bool = false
var _route: Dictionary = {}


func set_track(new_track: TrackConfigType, new_seed: int, is_random: bool) -> void:
	track = new_track
	seed_value = maxi(1, absi(new_seed))
	random_stage = is_random
	if track != null:
		_route = RouteType.generate(track, seed_value, random_stage)
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, background_color)
	_draw_grid(rect)
	if track == null or not _route.has("points"):
		_draw_text(rect.get_center() - Vector2(80, 0), "НЕТ ДАННЫХ")
		return

	var points: PackedVector2Array = _route["points"]
	var bounds: Rect2 = _route["bounds"]
	var margin: float = 22.0
	var usable: Rect2 = Rect2(margin, margin, maxf(10.0, size.x - margin * 2.0), maxf(10.0, size.y - margin * 2.0))
	var pad: float = 16.0
	var bx: float = bounds.position.x - pad
	var by: float = bounds.position.y - pad
	var bw: float = bounds.size.x + pad * 2.0
	var bh: float = bounds.size.y + pad * 2.0
	var scale: float = minf(usable.size.x / maxf(bw, 1.0), usable.size.y / maxf(bh, 1.0))
	var offset := Vector2(
		usable.position.x + usable.size.x * 0.5 - (bx + bw * 0.5) * scale,
		usable.position.y + usable.size.y - (by + bh * 0.5) * scale
	)

	var screen_points := PackedVector2Array()
	for i in range(points.size()):
		screen_points.append(Vector2(points[i].x * scale + offset.x, points[i].y * scale + offset.y))

	draw_polyline(screen_points, road_color.darkened(0.55), road_line_width + 5.0, true)
	draw_polyline(screen_points, road_color, road_line_width, true)

	# Контрольные точки.
	var checkpoint_color := Color(0.95, 0.85, 0.20)
	for cp in _route["checkpoints"]:
		var p := Vector2(cp["pos"].x * scale + offset.x, cp["pos"].y * scale + offset.y)
		draw_rect(Rect2(p.x - 3.0, p.y - 3.0, 6.0, 6.0), checkpoint_color, true)

	# Деревья и камни — та же функция сида, что и у генератора сцены.
	for i in range(90):
		var u: float = _hash_unit(seed_value, 20.0 + float(i) * 1.7)
		var v: float = _hash_unit(seed_value, 90.0 + float(i) * 2.3)
		var x: float = bounds.position.x + u * bounds.size.x
		var z: float = bounds.position.y + v * bounds.size.y
		if _distance_to_route(x, z, bounds) < track.road_half_width * 1.4 + 3.0:
			continue
		var point := Vector2(x * scale + offset.x, z * scale + offset.y)
		draw_circle(point, 1.6, track.tree_color.lightened(0.35))

	var finish: Vector2 = screen_points[screen_points.size() - 1]
	var start: Vector2 = screen_points[0]
	draw_circle(start, 5.0, Color(0.2, 0.8, 1.0))
	draw_circle(finish, 5.0, accent_color)
	_draw_text(Vector2(margin, margin), "СТАРТ / ФИНИШ")
	_draw_text(Vector2(margin, size.y - 10.0), "SEED %d  •  %.0f м  •  %s" % [seed_value, track.length, track.surface_name])


## Приблизительное расстояние от точки до маршрута (по отрезкам сплайна,
## каждый 4-й отрезок — быстрая оценка для размещения деревьев).
func _distance_to_route(x: float, z: float, bounds: Rect2) -> float:
	var best: float = 9999.0
	var pts: PackedVector2Array = _route["points"]
	if pts.size() < 2:
		return best
	for i in range(0, pts.size() - 1, 4):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var ab: Vector2 = b - a
		if ab.length_squared() < 1.0e-6:
			continue
		var t: float = clampf(Vector2(x, z).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = mini(best, Vector2(x, z).distance_to(a + ab * t))
	return best


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
