## Отрисовка «Студии трассы» в 3D-вьюпорте.
##
## Рисуем не 3D-мешами, а 2D-слоем поверх вьюпорта: так разметку видно сквозь
## деревья и рельеф, толщина линий не зависит от масштаба, а текст остаётся
## резким. Мир не трогаем вообще — это и есть «мгновенный предпросмотр»:
## тянешь точку, и полотно с поворотами перерисовывается сразу, без пересборки
## 600 ассетов и 1200×900 меша земли.
##
## Все цвета, кегли, шаги и тексты приходят из RallyTrackStudioSettings.
extends RefCounted

const Analysis = preload("res://scripts/track/route_analysis.gd")
const SettingsType = preload("res://scripts/data/rally_track_studio_settings.gd")
const Modes = preload("res://addons/rally_track_studio/studio_modes.gd")

var _overlay: Control = null
var _studio = null
var _camera: Camera3D = null
var _st: SettingsType = null
var _font: Font = null
var _panel_style: StyleBoxFlat = null

# Кэш проекций: пока камера и трасса не менялись, пересчитывать 1800 выборок
# на каждую перерисовку (а её просят на каждое движение мыши) бессмысленно.
var _cache_valid := false
var _cache_key := 0
var _cache_count := 0
var _cache_screen := PackedVector2Array()
var _cache_left := PackedVector2Array()
var _cache_right := PackedVector2Array()
var _cache_visible := PackedByteArray()
var _cache_depth := PackedFloat32Array()


func draw_all(overlay: Control, studio, camera: Camera3D, settings: SettingsType) -> void:
	_overlay = overlay
	_studio = studio
	_camera = camera
	_st = settings
	if _font == null:
		_font = ThemeDB.fallback_font
	if _font == null:
		return
	if _panel_style == null:
		_panel_style = StyleBoxFlat.new()
		_panel_style.set_corner_radius_all(7)
		_panel_style.set_border_width_all(1)
	studio.hud_rect = Rect2()
	studio.warnings_rect = Rect2()
	studio.profile_rect = Rect2()
	var points: PackedVector3Array = studio.samples.get("points", PackedVector3Array())
	if points.size() < 2 or not studio.route_ready:
		_draw_empty(studio)
		return
	var count: int = points.size()
	var dists: PackedFloat32Array = studio.samples.get("distances", PackedFloat32Array())
	var key: int = hash([
		hash(camera.global_transform), hash(camera.get_camera_projection()),
		int(studio.overlay_size.x), int(studio.overlay_size.y),
		int(studio.route_version), count
	])
	if not (_cache_valid and key == _cache_key and _cache_count == count):
		_project_samples(camera, studio, points, dists)
		_cache_valid = true
		_cache_key = key
		_cache_count = count
	var screen: PackedVector2Array = _cache_screen
	var left_edge: PackedVector2Array = _cache_left
	var right_edge: PackedVector2Array = _cache_right
	var visible: PackedByteArray = _cache_visible
	var depth: PackedFloat32Array = _cache_depth
	if _st.show_ribbon:
		_draw_ribbon(studio, screen, left_edge, right_edge, visible, depth, dists)
	_draw_edges(left_edge, right_edge, visible, depth)
	_draw_dashes(screen, visible, depth, dists)
	if _st.show_direction:
		_draw_direction(points, visible, dists)
	if _st.show_km:
		_draw_km(studio, points, visible)
	if studio.mode == Modes.Mode.ROAD:
		_draw_sections(studio, points, visible)
	if _st.show_pace_notes:
		_draw_corners(studio)
	var markers: Array = studio.zone_markers()
	_draw_zones(studio, markers)
	if _st.show_warnings:
		_draw_warning_markers(studio)
	if studio.mode == Modes.Mode.ROUTE:
		_draw_handles(studio)
	if studio.mode == Modes.Mode.PROPS and studio.hover_brush_valid:
		_draw_brush(studio)
	if studio.mode == Modes.Mode.ROUTE and studio.hover_new_valid:
		_draw_new_point(studio)
	_draw_selection(studio)
	if _st.show_cursor:
		_draw_cursor(studio)
	if _st.show_profile:
		_draw_profile(studio, markers)
	if _st.show_hud:
		_draw_hud(studio)
		_draw_warnings_panel(studio)


# ------------------------------------------------------------------ помощники

func _font_size() -> int:
	return _st.font_size


func _small_size() -> int:
	return _st.small_font_size


func _inside(screen: Vector2) -> bool:
	return screen.x > -200.0 and screen.y > -200.0 \
		and screen.x < _overlay.size.x + 200.0 and screen.y < _overlay.size.y + 200.0


## Точка пригодна для отрисовки: конечные числа и не «улетела» за экран.
##
## Проекция точки рядом с камерой даёт координаты в тысячи пикселей, и
## draw_colored_polygon() рисует из них гигантские клинья — это и были
## артефакты, заливавшие пол-вьюпорта.
func _in_picture(point: Vector2) -> bool:
	if not is_finite(point.x) or not is_finite(point.y):
		return false
	var limit: Vector2 = _overlay.size * 3.0 + Vector2(400.0, 400.0)
	return absf(point.x) <= limit.x and absf(point.y) <= limit.y


func _tri_area(a: Vector2, b: Vector2, c: Vector2) -> float:
	return 0.5 * ((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x))


## Выпуклый ли четырёхугольник. «Бабочка» (полотно сложилось на шпильке или
## стрелка повёрнута ребром) — не полигон для триангуляции: Godot печатает
## «Invalid polygon data» на каждый кадр.
func _quad_is_convex(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	# Знаки поворотов на всех четырёх углах должны совпадать.
	var first: float = (b - a).cross(c - b)
	if is_zero_approx(first):
		return false
	var second: float = (c - b).cross(d - c)
	if is_zero_approx(second):
		return false
	var third: float = (d - c).cross(a - d)
	if is_zero_approx(third):
		return false
	var fourth: float = (a - d).cross(b - a)
	if is_zero_approx(fourth):
		return false
	var positive: bool = first > 0.0
	if (second > 0.0) != positive or (third > 0.0) != positive or (fourth > 0.0) != positive:
		return false
	return true


## Четырёхугольник полотна. Вырожденные (площадь ~0) и вывернутые полигоны
## Godot не триангулирует и сыплет «Invalid polygon data, triangulation
## failed» на каждый кадр — поэтому фильтруем и выравниваем обход.
func _draw_quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
	if not (_in_picture(a) and _in_picture(b) and _in_picture(c) and _in_picture(d)):
		return
	if not _quad_is_convex(a, b, c, d):
		return
	var area: float = _tri_area(a, b, c) + _tri_area(a, c, d)
	if absf(area) < _st.min_polygon_area:
		return
	if area < 0.0:
		_overlay.draw_colored_polygon(PackedVector2Array([d, c, b, a]), color)
		return
	_overlay.draw_colored_polygon(PackedVector2Array([a, b, c, d]), color)


func _draw_triangle(a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	if not (_in_picture(a) and _in_picture(b) and _in_picture(c)):
		return
	var area: float = _tri_area(a, b, c)
	if absf(area) < _st.min_polygon_area:
		return
	if area < 0.0:
		_overlay.draw_colored_polygon(PackedVector2Array([c, b, a]), color)
		return
	_overlay.draw_colored_polygon(PackedVector2Array([a, b, c]), color)


func _fade(value: float) -> float:
	return clampf(1.0 - value / maxf(50.0, _st.fade_distance), _st.far_alpha_floor, 1.0)


func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * clampf(alpha, 0.0, 1.0))


func _text(at: Vector2, value: String, color: Color, size: int = -1) -> void:
	var used: int = size if size > 0 else _font_size()
	_overlay.draw_string(_font, at + Vector2(1.0, 1.0), value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, used, _st.shadow_color)
	_overlay.draw_string(_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, used, color)


func _text_width(value: String, size: int = -1) -> float:
	var used: int = size if size > 0 else _font_size()
	return _font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, used).x


func _text_centered(center: Vector2, value: String, color: Color, size: int = -1) -> void:
	var used: int = size if size > 0 else _font_size()
	var measured := _font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, used)
	_text(center - Vector2(measured.x * 0.5, -measured.y * 0.28), value, color, used)


func _panel(rect: Rect2, border: Color, fill: Color) -> void:
	_panel_style.bg_color = fill
	_panel_style.border_color = border
	_panel_style.shadow_color = _st.shadow_color
	_panel_style.shadow_size = 8
	_overlay.draw_style_box(_panel_style, rect)


func _badge(center: Vector2, radius: float, fill: Color, border: Color) -> void:
	_overlay.draw_circle(center, radius, fill)
	_overlay.draw_arc(center, radius, 0.0, TAU, 24, border, 1.4, true)


func _wrap(value: String, max_width: float, size: int) -> PackedStringArray:
	var words := value.split(" ", false)
	var lines := PackedStringArray()
	var current := ""
	for word in words:
		var probe := word if current.is_empty() else current + " " + word
		if _text_width(probe, size) > max_width and not current.is_empty():
			lines.append(current)
			current = word
		else:
			current = probe
	if not current.is_empty():
		lines.append(current)
	return lines


func _index_for_distance(studio, distance: float) -> int:
	var points: PackedVector3Array = studio.samples.get("points", PackedVector3Array())
	if points.is_empty():
		return 0
	var step: float = maxf(0.25, float(studio.samples.get("step", 1.0)))
	return clampi(int(round(distance / step)), 0, points.size() - 1)


func _dir_for_distance(studio, distance: float) -> Vector3:
	var points: PackedVector3Array = studio.samples.get("points", PackedVector3Array())
	return Analysis.direction_at(points, _index_for_distance(studio, distance))


func _world_for_distance(studio, distance: float) -> Vector3:
	return Analysis.point_at_distance(studio.samples, distance)


func _severity_color(severity: int) -> Color:
	if severity <= 2:
		return _st.danger_color
	if severity <= 4:
		return _st.warning_color
	return _st.ok_color


# ------------------------------------------------------------------ полотно

func _draw_ribbon(studio, screen: PackedVector2Array, left_edge: PackedVector2Array,
		right_edge: PackedVector2Array, visible: PackedByteArray, depth: PackedFloat32Array,
		dists: PackedFloat32Array) -> void:
	# Шаг по выборке: на длинной трассе 2-метровые полоски на экране уже
	# неразличимы, а каждая — отдельный вызов триангуляции. 700 квадов хватает.
	var count: int = screen.size()
	var stride: int = maxi(1, int(ceil(float(count) / 700.0)))
	var i: int = 0
	while i + stride < count:
		var j: int = i + stride
		if visible[i] != 0 and visible[j] != 0:
			var alpha: float = _st.ribbon_alpha * _fade(depth[i])
			if alpha > 0.01:
				var color: Color = studio.surface_color(dists[i]) if i < dists.size() else _st.road_edge_color
				_draw_quad(left_edge[i], right_edge[i], right_edge[j], left_edge[j], _with_alpha(color, alpha))
		i = j


func _draw_edges(left_edge: PackedVector2Array, right_edge: PackedVector2Array,
		visible: PackedByteArray, depth: PackedFloat32Array) -> void:
	_draw_runs(left_edge, visible, depth, _st.road_edge_color, _st.edge_width)
	_draw_runs(right_edge, visible, depth, _st.road_edge_color, _st.edge_width)


func _draw_runs(edge: PackedVector2Array, visible: PackedByteArray, depth: PackedFloat32Array,
		color: Color, line_px: float) -> void:
	var run := PackedVector2Array()
	var run_alpha: float = 1.0
	for i in range(edge.size()):
		var ok: bool = visible[i] == 1 and _inside(edge[i])
		if ok:
			if run.is_empty():
				run_alpha = _fade(depth[i])
			run.append(edge[i])
		else:
			if run.size() > 1:
				_overlay.draw_polyline(run, _with_alpha(color, run_alpha), line_px, true)
			run = PackedVector2Array()
	if run.size() > 1:
		_overlay.draw_polyline(run, _with_alpha(color, run_alpha), line_px, true)


func _draw_dashes(screen: PackedVector2Array, visible: PackedByteArray,
		depth: PackedFloat32Array, dists: PackedFloat32Array) -> void:
	var period: float = maxf(2.0, _st.dash_period)
	var dash: float = clampf(_st.dash_length, 0.5, period)
	for i in range(screen.size() - 1):
		if visible[i] == 0 or visible[i + 1] == 0:
			continue
		var distance: float = dists[i] if i < dists.size() else 0.0
		if fposmod(distance, period) > dash:
			continue
		if not (_in_picture(screen[i]) and _in_picture(screen[i + 1])):
			continue
		var alpha: float = _fade(depth[i]) * 0.9
		if alpha <= 0.05:
			continue
		_overlay.draw_line(screen[i], screen[i + 1], _with_alpha(_st.center_line_color, alpha), _st.line_width, true)


func _draw_direction(points: PackedVector3Array, visible: PackedByteArray, dists: PackedFloat32Array) -> void:
	var step: float = maxf(10.0, _st.direction_step)
	var distance: float = step
	while distance < float(_studio.length):
		var index := _index_for_distance(_studio, distance)
		if index < points.size() and visible[index] == 1:
			var point: Vector3 = points[index]
			var dir: Vector3 = Analysis.direction_at(points, index)
			var side := Vector3(dir.z, 0.0, -dir.x)
			var tip: Vector2 = _studio.project_point(_camera, point + dir * 5.0)
			var back: Vector2 = _studio.project_point(_camera, point - dir * 3.0)
			var left: Vector2 = _studio.project_point(_camera, point + side * 1.7)
			var right: Vector2 = _studio.project_point(_camera, point - side * 1.7)
			if _inside(tip) and _inside(back):
				var color := _with_alpha(_st.road_edge_color, 0.55 * _fade(_camera.global_position.distance_to(point)))
				_draw_quad(tip, left, back, right, color)
		distance += step


# ------------------------------------------------------------------ километраж

func _draw_km(studio, points: PackedVector3Array, visible: PackedByteArray) -> void:
	var tick_step: float = maxf(5.0, _st.km_tick_interval)
	var label_step: float = maxf(tick_step, _st.km_label_interval)
	var distance: float = 0.0
	while distance <= studio.length + 0.5:
		var index := _index_for_distance(studio, distance)
		if index < points.size() and visible[index] == 1:
			var point: Vector3 = points[index]
			var dir: Vector3 = Analysis.direction_at(points, index)
			var side := Vector3(dir.z, 0.0, -dir.x)
			var half: float = studio.half_width_at(distance) + 1.0
			var a: Vector2 = studio.project_point(_camera, point + side * half)
			var b: Vector2 = studio.project_point(_camera, point - side * half)
			if _inside(a) and _inside(b):
				var alpha: float = _fade(_camera.global_position.distance_to(point))
				var major: bool = is_zero_approx(fposmod(distance, label_step))
				var color := _with_alpha(_st.muted_color, alpha * (0.95 if major else 0.5))
				_overlay.draw_line(a, b, color, _st.line_width if major else 1.0, true)
				if major:
					var label := "%.1f км" % (distance / 1000.0) if distance >= 100.0 else "старт"
					var at: Vector2 = (a + b) * 0.5 + Vector2(6.0, -6.0)
					_text(at, label, _with_alpha(_st.text_color, alpha), _small_size())
		distance += tick_step


# ------------------------------------------------------------------ участки

func _draw_sections(studio, points: PackedVector3Array, visible: PackedByteArray) -> void:
	if studio.track == null:
		return
	var sections: Array = studio.track.route_sections
	for i in range(sections.size()):
		var section: Resource = sections[i]
		if section == null:
			continue
		var distance := float(section.get("start_distance"))
		if distance < 0.0 or distance > studio.length:
			continue
		var index := _index_for_distance(studio, distance)
		if index >= points.size() or visible[index] == 0:
			continue
		var point: Vector3 = points[index]
		var dir: Vector3 = Analysis.direction_at(points, index)
		var side := Vector3(dir.z, 0.0, -dir.x)
		var half: float = studio.half_width_at(distance) + 2.0
		var a: Vector2 = studio.project_point(_camera, point + side * half)
		var b: Vector2 = studio.project_point(_camera, point - side * half)
		if not (_in_picture(a) and _in_picture(b)):
			continue
		var raw_color = section.get("road_color")
		var tint: Color = _st.road_edge_color
		if raw_color is Color:
			tint = raw_color
		_overlay.draw_line(a, b, _with_alpha(tint, 1.0), _st.edge_width + 1.0, true)
		var title := "%s · %.1f м" % [String(section.get("surface_name")), float(section.get("half_width")) * 2.0]
		_text((a + b) * 0.5 + Vector2(6.0, -8.0), title, _with_alpha(_st.text_color, 0.9), _small_size())
	# ручки ширины
	var step: float = maxf(5.0, _st.width_handle_step)
	var distance: float = 0.0
	while distance <= studio.length:
		var index := _index_for_distance(studio, distance)
		if index < points.size() and visible[index] == 1:
			var point: Vector3 = points[index]
			var dir: Vector3 = Analysis.direction_at(points, index)
			var side := Vector3(dir.z, 0.0, -dir.x)
			var half: float = studio.half_width_at(distance)
			for which in [-1, 1]:
				# studio — намеренно нетипизированный параметр (иначе цикл
				# preload между studio.gd и studio_view.gd), поэтому тип
				# результата указываем явно: GDScript не выводит его сам.
				var at: Vector2 = studio.project_point(_camera, point + side * half * float(which))
				if _inside(at):
					_overlay.draw_circle(at, 3.5, _st.road_edge_color)
					_overlay.draw_arc(at, 4.5, 0.0, TAU, 12, _with_alpha(_st.panel_bg, 0.9), 1.2, true)
		distance += step


# ------------------------------------------------------------------ повороты и предупреждения

func _draw_corners(studio) -> void:
	var last_label := Vector2(-10000.0, -10000.0)
	for corner in studio.corners:
		var apex: Vector3 = corner.get("apex", Vector3.ZERO)
		if _camera.is_position_behind(apex):
			continue
		var at: Vector2 = studio.project_point(_camera, apex)
		if not _inside(at):
			continue
		if at.distance_to(last_label) < _st.corner_label_gap_px:
			continue
		last_label = at
		var severity := int(corner.get("severity", 4))
		var direction := int(corner.get("direction", 1))
		var color := _severity_color(severity)
		var letter := "Л" if direction > 0 else "П"
		var radius: float = _st.corner_badge_radius
		_badge(at, radius, _with_alpha(_st.panel_bg, 0.92), color)
		_text_centered(at, letter + str(severity), color, _small_size() + 1)
		var radius_m := float(corner.get("radius", 0.0))
		if radius_m > 0.0 and _st.show_warnings:
			_text(at + Vector2(radius + 4.0, 4.0), "R %.0f" % radius_m, _with_alpha(_st.muted_color, 0.9), _small_size() - 1)


func _draw_warning_markers(studio) -> void:
	for warning in studio.warnings:
		var distance := float(warning.get("distance", 0.0))
		var world := _world_for_distance(studio, distance)
		if _camera.is_position_behind(world):
			continue
		var at: Vector2 = studio.project_point(_camera, world)
		if not _inside(at):
			continue
		var color: Color = _st.danger_color if int(warning.get("severity", 1)) >= 2 else _st.warning_color
		var icon: float = _st.warning_icon_radius
		_draw_triangle(
			at + Vector2(0.0, -icon),
			at + Vector2(icon * 0.86, icon * 0.72),
			at + Vector2(-icon * 0.86, icon * 0.72),
			_with_alpha(color, 0.92)
		)
		_overlay.draw_line(at + Vector2(0.0, -2.0), at + Vector2(0.0, 1.5), _st.panel_bg, 1.4, false)
		_overlay.draw_circle(at + Vector2(0.0, 3.2), 0.8, _st.panel_bg)


# ------------------------------------------------------------------ зоны

func _draw_zones(studio, markers: Array) -> void:
	for marker in markers:
		var distance := float(marker.get("distance", 0.0))
		var kind := String(marker.get("kind", ""))
		var index := int(marker.get("index", 0))
		var world := _world_for_distance(studio, distance)
		if _camera.is_position_behind(world):
			continue
		var dir := _dir_for_distance(studio, distance)
		var side := Vector3(dir.z, 0.0, -dir.x)
		var half: float = studio.half_width_at(distance) + _st.zone_half_width_extra
		var a: Vector2 = studio.project_point(_camera, world + side * half)
		var b: Vector2 = studio.project_point(_camera, world - side * half)
		if not _inside(a) or not _inside(b):
			continue
		var color := _st.checkpoint_color
		var title := "КП %d" % (index + 1)
		if kind == "start":
			color = _st.start_color
			title = "СТАРТ"
		elif kind == "finish":
			color = _st.finish_color
			title = "ФИНИШ"
		var width: float = _st.edge_width + (_st.zone_extra_width if studio.mode == Modes.Mode.ZONES else 0.0)
		_overlay.draw_line(a, b, color, width, true)
		var flag: float = _st.zone_flag_height
		_overlay.draw_line(a, a + Vector2(0.0, -flag), color, width, true)
		_overlay.draw_line(b, b + Vector2(0.0, -flag), color, width, true)
		var label_pos: Vector2 = (a + b) * 0.5 + Vector2(0.0, -flag - 6.0)
		_text_centered(label_pos, title, color, _small_size())
		if studio.mode == Modes.Mode.ZONES:
			var km := "%.2f км" % (distance / 1000.0)
			_text_centered(label_pos + Vector2(0.0, 14.0), km, _with_alpha(_st.muted_color, 0.95), _small_size() - 1)


# ------------------------------------------------------------------ ручки и курсор

func _draw_handles(studio) -> void:
	if studio.curve == null:
		return
	for i in range(studio.curve.point_count):
		var world: Vector3 = studio.curve.get_point_position(i)
		if _camera.is_position_behind(world):
			continue
		var at: Vector2 = studio.project_point(_camera, world)
		if not _inside(at):
			continue
		var selected: bool = i == studio.selected_control
		var hovered: bool = i == studio.hover_control
		var color: Color = _st.selection_color if selected else _st.road_edge_color
		if hovered:
			color = _st.hover_color
		var radius: float = _st.handle_dot_radius + (2.0 if (selected or hovered) else 0.0)
		_overlay.draw_circle(at, radius, _with_alpha(color, 0.95))
		_overlay.draw_arc(at, radius + 2.0, 0.0, TAU, 18, _with_alpha(_st.panel_bg, 0.9), 1.6, true)
		if selected:
			_overlay.draw_arc(at, radius + 5.0, 0.0, TAU, 20, _with_alpha(_st.selection_color, 0.8), 1.0, true)


func _draw_new_point(studio) -> void:
	if _camera.is_position_behind(studio.hover_new_point):
		return
	var at: Vector2 = studio.project_point(_camera, studio.hover_new_point)
	if not _inside(at):
		return
	_overlay.draw_arc(at, 9.0, 0.0, TAU, 20, _with_alpha(_st.hover_color, 0.85), 1.4, true)
	_overlay.draw_line(at + Vector2(-9.0, 0.0), at + Vector2(9.0, 0.0), _with_alpha(_st.hover_color, 0.7), 1.0, true)
	_overlay.draw_line(at + Vector2(0.0, -9.0), at + Vector2(0.0, 9.0), _with_alpha(_st.hover_color, 0.7), 1.0, true)


func _draw_selection(studio) -> void:
	if studio.selected_distance < 0.0 or studio.length <= 0.0:
		return
	var world := _world_for_distance(studio, studio.selected_distance)
	if _camera.is_position_behind(world):
		return
	var at: Vector2 = studio.project_point(_camera, world)
	if not _inside(at):
		return
	var top: Vector2 = studio.project_point(_camera, world + Vector3.UP * 4.0)
	_overlay.draw_line(at, top, _with_alpha(_st.selection_color, 0.45), 1.0, true)
	_overlay.draw_arc(top, 5.0, 0.0, TAU, 16, _with_alpha(_st.selection_color, 0.9), 1.4, true)


func _draw_brush(studio) -> void:
	var radius: float = maxf(1.0, studio.settings.brush_radius)
	var center: Vector3 = studio.hover_brush
	var dir: Vector3 = _dir_for_distance(studio, studio.hover_distance if studio.hover_valid else 0.0)
	var side := Vector3(dir.z, 0.0, -dir.x)
	var at: Vector2 = studio.project_point(_camera, center)
	var edge: Vector2 = studio.project_point(_camera, center + side * radius)
	var pixels: float = maxf(8.0, at.distance_to(edge))
	var color: Color = _st.hover_color if not Input.is_key_pressed(KEY_SHIFT) else _st.danger_color
	for i in range(0, 360, 20):
		var angle := deg_to_rad(float(i))
		var angle_end := angle + deg_to_rad(12.0)
		_overlay.draw_arc(at, pixels, angle, angle_end, 4, _with_alpha(color, 0.8), 1.4, true)
	_overlay.draw_circle(at, 2.0, color)
	_text(at + Vector2(pixels * 0.75, -pixels * 0.75), "кисть %.0f м" % radius, _with_alpha(_st.muted_color, 0.95), _small_size())


func _draw_cursor(studio) -> void:
	if not studio.hover_valid:
		return
	var lines: Array = []
	lines.append("%.0f м · %.2f км" % [studio.hover_distance, studio.hover_distance / 1000.0])
	var radius := _local_radius(studio.hover_distance)
	if radius > 0.0:
		lines.append("радиус ≈ %.0f м" % radius)
	var width_line := "ширина %.1f м" % (studio.half_width_at(studio.hover_distance) * 2.0)
	lines.append(width_line)
	var pad: float = 7.0
	var width: float = 0.0
	for line in lines:
		width = maxf(width, _text_width(String(line), _small_size()))
	var box := Rect2(studio.mouse_pos + Vector2(18.0, 14.0),
		Vector2(width + pad * 2.0, pad * 2.0 + float(lines.size()) * (_small_size() + 4.0)))
	if box.position.x + box.size.x > _overlay.size.x - 6.0:
		box.position.x = studio.mouse_pos.x - box.size.x - 12.0
	if box.position.y + box.size.y > _overlay.size.y - 6.0:
		box.position.y = studio.mouse_pos.y - box.size.y - 12.0
	# Простая заливка вместо StyleBoxFlat с тенью: подсказка ездит за мышью,
	# а тень перерисовывается на каждом движении курсора.
	_overlay.draw_rect(box, _st.panel_bg)
	_overlay.draw_rect(box, _st.road_edge_color, false, 1.0)
	_overlay.draw_circle(studio.mouse_pos + Vector2(8.0, 6.0), 2.5, _st.hover_color)
	var y: float = box.position.y + pad + _small_size()
	var first := true
	for line in lines:
		var color: Color = _st.accent_color if first else _st.text_color
		_text(Vector2(box.position.x + pad, y), String(line), color, _small_size())
		y += _small_size() + 4.0
		first = false


func _local_radius(distance: float) -> float:
	var studio = _studio
	if studio.length <= 0.0:
		return 0.0
	var window: float = maxf(4.0, _st.corner_window * 0.5)
	var a_dist: float = clampf(distance - window, 0.0, studio.length)
	var b_dist: float = clampf(distance + window, 0.0, studio.length)
	if b_dist - a_dist < 1.0:
		return 0.0
	var points: PackedVector3Array = studio.samples.get("points", PackedVector3Array())
	var a_dir: Vector3 = Analysis.direction_at(points, _index_for_distance(studio, a_dist))
	var b_dir: Vector3 = Analysis.direction_at(points, _index_for_distance(studio, b_dist))
	var turn: float = absf(Analysis.signed_turn(a_dir, b_dir))
	if turn < 0.0005:
		return 0.0
	return (b_dist - a_dist) / turn


# ------------------------------------------------------------------ профиль

func _bin_x(inner: Rect2, index: int, count: int) -> float:
	if count < 2:
		return inner.position.x
	return inner.position.x + inner.size.x * (float(index) / float(count - 1))


func _bin_y(inner: Rect2, baseline: float, value: float, low: float, span: float) -> float:
	return baseline - inner.size.y * clampf((value - low) / span, 0.0, 1.0)


func _draw_profile(studio, markers: Array) -> void:
	var area: Vector2 = _overlay.size
	var height: float = minf(_st.profile_height, area.y * 0.34)
	var rect := Rect2(
		_st.panel_margin,
		area.y - height - _st.panel_margin,
		area.x - _st.panel_margin * 2.0,
		height
	)
	if rect.size.x < 80.0 or rect.size.y < 40.0:
		return
	studio.profile_rect = rect
	_panel(rect, _st.panel_border, _st.panel_bg)
	var inner := Rect2(rect.position + Vector2(12.0, 12.0), rect.size - Vector2(24.0, 34.0))
	if inner.size.x < 20.0 or inner.size.y < 10.0:
		return
	var bins: int = clampi(int(inner.size.x / 4.0), 32, 512)
	var data: Dictionary = Analysis.profile(studio.samples, bins)
	var values: PackedFloat32Array = data.get("values", PackedFloat32Array())
	if values.size() < 2:
		return
	var low: float = float(data.get("min", 0.0))
	var high: float = float(data.get("max", 0.0))
	var span: float = maxf(1.0, high - low)
	var baseline: float = inner.position.y + inner.size.y
	var top_y: float = inner.position.y
	# Заливка профиля — столбики-трапеции, а не один полигон на 500 вершин.
	# Godot триангулирует многоугольник отсечением ушей за O(n²): на 500 точках
	# это миллионы проверок в каждом кадре (отсюда тормоза), а на ровных
	# участках профиля появляются коллинеарные вершины, и триангуляция падает
	# с «Invalid polygon data» на каждую перерисовку. Трапеция всегда выпуклая.
	var fill_color: Color = _with_alpha(_st.accent_color, 0.14)
	var columns: int = values.size() - 1
	var stride: int = maxi(1, int(ceil(float(columns) / float(_st.profile_fill_max_quads))))
	var column: int = 0
	while column < columns:
		var next: int = mini(columns, column + stride)
		var x0: float = _bin_x(inner, column, values.size())
		var x1: float = _bin_x(inner, next, values.size())
		_draw_quad(
			Vector2(x0, baseline),
			Vector2(x0, _bin_y(inner, baseline, values[column], low, span)),
			Vector2(x1, _bin_y(inner, baseline, values[next], low, span)),
			Vector2(x1, baseline),
			fill_color
		)
		column = next
	var line := PackedVector2Array()
	for i in range(values.size()):
		var t: float = float(i) / float(values.size() - 1)
		var x: float = inner.position.x + inner.size.x * t
		var y: float = baseline - inner.size.y * clampf((values[i] - low) / span, 0.0, 1.0)
		line.append(Vector2(x, y))
	if line.size() > 1:
		_overlay.draw_polyline(line, _with_alpha(_st.accent_color, 0.95), 1.6, true)
	_text(Vector2(inner.position.x, top_y - 2.0), "%.0f м" % high, _with_alpha(_st.muted_color, 0.9), _small_size() - 1)
	_text(Vector2(inner.position.x, baseline + 9.0), "%.0f м" % low, _with_alpha(_st.muted_color, 0.9), _small_size() - 1)
	# полоса покрытий
	var band := Rect2(inner.position.x, baseline + 4.0, inner.size.x, 5.0)
	var bands: Array = Analysis.section_bands(studio.track, studio.length, _st.road_edge_color)
	for entry in bands:
		var start: float = float(entry.get("start", 0.0))
		var end: float = float(entry.get("end", studio.length))
		if end <= start:
			continue
		var x0: float = inner.position.x + inner.size.x * clampf(start / maxf(studio.length, 0.001), 0.0, 1.0)
		var x1: float = inner.position.x + inner.size.x * clampf(end / maxf(studio.length, 0.001), 0.0, 1.0)
		var raw_color = entry.get("color")
		var tint: Color = _st.road_edge_color
		if raw_color is Color:
			tint = raw_color
		_overlay.draw_rect(Rect2(x0, band.position.y, maxf(1.0, x1 - x0), band.size.y), tint)
		if x1 - x0 > 70.0:
			_text(Vector2(x0 + 4.0, band.position.y + band.size.y + 11.0),
				String(entry.get("title", "")), _with_alpha(_st.muted_color, 0.95), _small_size() - 1)
	# насечки километража
	var km_step: float = maxf(50.0, _st.km_label_interval)
	var km: float = 0.0
	while km <= studio.length:
		var x: float = inner.position.x + inner.size.x * (km / maxf(studio.length, 0.001))
		_overlay.draw_line(Vector2(x, inner.position.y), Vector2(x, baseline), _with_alpha(_st.muted_color, 0.18), 1.0, false)
		if km > 0.0:
			_text(Vector2(x + 3.0, inner.position.y + 10.0), "%.1f" % (km / 1000.0), _with_alpha(_st.muted_color, 0.7), _small_size() - 2)
		km += km_step
	# повороты
	for corner in studio.corners:
		var distance: float = float(corner.get("distance", 0.0))
		var x: float = inner.position.x + inner.size.x * clampf(distance / maxf(studio.length, 0.001), 0.0, 1.0)
		var color: Color = _severity_color(int(corner.get("severity", 4)))
		_overlay.draw_line(Vector2(x, baseline - 8.0), Vector2(x, baseline), _with_alpha(color, 0.85), 2.0, true)
	# зоны
	for marker in markers:
		var distance: float = float(marker.get("distance", 0.0))
		var x: float = inner.position.x + inner.size.x * clampf(distance / maxf(studio.length, 0.001), 0.0, 1.0)
		var kind := String(marker.get("kind", ""))
		var color: Color = _st.checkpoint_color
		if kind == "start":
			color = _st.start_color
		elif kind == "finish":
			color = _st.finish_color
		_draw_triangle(
			Vector2(x, top_y + 4.0),
			Vector2(x + 4.0, top_y - 3.0),
			Vector2(x - 4.0, top_y - 3.0),
			color
		)
		_overlay.draw_line(Vector2(x, top_y + 4.0), Vector2(x, baseline), _with_alpha(color, 0.35), 1.0, false)
	# курсор
	var cursor_distance: float = studio.hover_distance if studio.hover_valid else studio.selected_distance
	if cursor_distance >= 0.0:
		var x: float = inner.position.x + inner.size.x * clampf(cursor_distance / maxf(studio.length, 0.001), 0.0, 1.0)
		_overlay.draw_line(Vector2(x, top_y - 4.0), Vector2(x, baseline + 10.0), _st.selection_color, 1.2, true)
		var label := "%.0f м" % cursor_distance
		var label_x: float = clampf(x - _text_width(label, _small_size()) * 0.5, inner.position.x, inner.position.x + inner.size.x - 40.0)
		_text(Vector2(label_x, top_y - 6.0), label, _st.selection_color, _small_size())


# ------------------------------------------------------------------ HUD

func _draw_hud(studio) -> void:
	var margin: float = _st.panel_margin
	var width: float = _st.panel_width
	var lines: Array = []
	lines.append({"text": _st.title_text, "color": _st.accent_color, "size": _font_size() + 2, "height": _font_size() + 8.0})
	var title := "трасса не задана"
	if studio.track != null:
		title = String(studio.track.display_name)
	lines.append({"text": title, "color": _st.text_color, "size": _small_size(), "height": _small_size() + 8.0})
	lines.append({"text": "", "color": _st.muted_color, "size": 0, "height": 8.0})
	var length_km: float = studio.length / 1000.0
	lines.append({"text": "ДЛИНА  %.2f км  ·  %.0f м" % [length_km, studio.length], "color": _st.text_color, "size": _font_size(), "height": _font_size() + 5.0})
	var corners_count := int(studio.stats.get("corners", 0))
	var min_radius := float(studio.stats.get("min_radius", 0.0))
	lines.append({"text": "ПОВОРОТЫ %d   ·   МИН R %.0f м" % [corners_count, min_radius], "color": _st.text_color, "size": _font_size(), "height": _font_size() + 5.0})
	var max_grade := float(studio.stats.get("max_grade", 0.0))
	var seconds := float(studio.stats.get("seconds", 0.0))
	lines.append({"text": "УКЛОН %.1f %%   ·   ВРЕМЯ ≈ %s" % [max_grade, _format_time(seconds)], "color": _st.text_color, "size": _font_size(), "height": _font_size() + 5.0})
	var status_color: Color = _st.ok_color
	var status_text: String = _st.text_built
	if studio.building:
		status_color = _st.warning_color
		status_text = _st.text_building
	elif studio.needs_rebuild:
		status_color = _st.warning_color
		status_text = _st.text_dirty
	elif studio.last_build_seconds > 0.01:
		status_text = _st.text_built
	lines.append({"text": status_text, "color": status_color, "size": _small_size(), "height": _small_size() + 7.0})
	lines.append({"text": "", "color": _st.muted_color, "size": 0, "height": 8.0})
	lines.append({"text": studio.mode_name(), "color": _st.accent_color, "size": _font_size(), "height": _font_size() + 7.0})
	var hint_width: float = width - 24.0
	if _st.show_hints:
		var hints: PackedStringArray = _mode_hints(studio)
		for hint in hints:
			for wrapped in _wrap(hint, hint_width, _small_size()):
				lines.append({"text": wrapped, "color": _st.muted_color, "size": _small_size(), "height": _small_size() + 4.0})
	var height_total: float = 16.0
	for line in lines:
		height_total += float(line.get("height", 16.0))
	var rect := Rect2(Vector2(margin, margin), Vector2(width, height_total))
	studio.hud_rect = rect
	_panel(rect, _st.panel_border, _st.panel_bg)
	var y: float = rect.position.y + 14.0
	for line in lines:
		var text := String(line.get("text", ""))
		var used := int(line.get("size", 0))
		var color: Color = line.get("color", _st.text_color)
		if text.is_empty():
			_overlay.draw_line(Vector2(rect.position.x + 12.0, y + 3.0),
				Vector2(rect.position.x + rect.size.x - 12.0, y + 3.0), _with_alpha(_st.muted_color, 0.35), 1.0, false)
		else:
			_text(Vector2(rect.position.x + 12.0, y + float(used)), text, color, used)
		y += float(line.get("height", 16.0))
	# линейка режимов
	var modes_y: float = rect.position.y + rect.size.y + 8.0
	var chip_x: float = rect.position.x
	for i in range(_st.mode_names.size()):
		var label: String = _st.mode_names[i]
		var chip_w: float = _text_width(label, _small_size()) + 16.0
		var chip := Rect2(Vector2(chip_x, modes_y), Vector2(chip_w, 22.0))
		var selected: bool = i == studio.mode
		_panel(chip, _st.accent_color if selected else _with_alpha(_st.muted_color, 0.5),
			_with_alpha(_st.accent_color, 0.18) if selected else _with_alpha(_st.panel_bg, 0.92))
		_text_centered(chip.position + chip.size * 0.5 + Vector2(0.0, -1.0), label,
			_st.accent_color if selected else _st.muted_color, _small_size())
		chip_x += chip_w + 6.0


func _mode_hints(studio) -> PackedStringArray:
	var current: int = int(studio.mode)
	if current == Modes.Mode.ROAD:
		return _st.hints_road
	if current == Modes.Mode.PROPS:
		return _st.hints_props
	if current == Modes.Mode.ZONES:
		return _st.hints_zones
	return _st.hints_route


func _format_time(seconds: float) -> String:
	if seconds <= 0.0:
		return "—"
	var total := int(round(seconds))
	var minutes: int = total / 60
	var rest: int = total % 60
	return "%d:%02d" % [minutes, rest]


func _draw_warnings_panel(studio) -> void:
	if studio.warnings.is_empty():
		return
	var limit: int = 5
	var shown: int = mini(limit, studio.warnings.size())
	if shown <= 0:
		return
	var width: float = 250.0
	var height: float = 14.0 + float(shown) * (_small_size() + 7.0) + 12.0
	var rect := Rect2(Vector2(_overlay.size.x - width - _st.panel_margin, _st.panel_margin), Vector2(width, height))
	studio.warnings_rect = rect
	_panel(rect, _with_alpha(_st.danger_color, 0.85), _st.panel_bg)
	_text(Vector2(rect.position.x + 10.0, rect.position.y + 12.0 + _small_size()), "ПРОВЕРЬТЕ", _st.danger_color, _small_size())
	var y: float = rect.position.y + 12.0 + _small_size() + 8.0
	for i in range(shown):
		var warning: Dictionary = studio.warnings[i]
		var distance: float = float(warning.get("distance", 0.0))
		var text := "%s · %.2f км" % [String(warning.get("text", "")), distance / 1000.0]
		var color: Color = _st.danger_color if int(warning.get("severity", 1)) >= 2 else _st.warning_color
		_overlay.draw_circle(Vector2(rect.position.x + 13.0, y - 3.0), 2.5, color)
		_text(Vector2(rect.position.x + 20.0, y), text, _st.text_color, _small_size())
		y += _small_size() + 7.0
	if studio.warnings.size() > shown:
		_text(Vector2(rect.position.x + 20.0, y), "и ещё %d…" % (studio.warnings.size() - shown), _with_alpha(_st.muted_color, 0.8), _small_size() - 1)


## Пересчитать экранные координаты выборок: сначала отсечение по фрустуму
## (дёшево), потом unproject_position (дорого). Раньше проецировались все
## выборки трассы, включая те, что за спиной камеры.
func _project_samples(camera: Camera3D, studio, points: PackedVector3Array,
		dists: PackedFloat32Array) -> void:
	var count: int = points.size()
	_cache_screen.resize(count)
	_cache_left.resize(count)
	_cache_right.resize(count)
	_cache_visible.resize(count)
	_cache_depth.resize(count)
	var cam_pos: Vector3 = camera.global_position
	for i in range(count):
		_cache_visible[i] = 0
		var point: Vector3 = points[i]
		if not camera.is_position_in_frustum(point):
			continue
		var projected: Vector2 = studio.project_point(camera, point)
		if not _in_picture(projected):
			continue
		var distance: float = dists[i] if i < dists.size() else 0.0
		var dir: Vector3 = Analysis.direction_at(points, i)
		var side := Vector3(dir.z, 0.0, -dir.x)
		var half: float = studio.half_width_at(distance)
		_cache_screen[i] = projected
		_cache_left[i] = studio.project_point(camera, point + side * half)
		_cache_right[i] = studio.project_point(camera, point - side * half)
		_cache_depth[i] = cam_pos.distance_to(point)
		_cache_visible[i] = 1


func _draw_empty(studio) -> void:
	var text: String = _st.text_no_stage
	if studio.stage != null:
		text = _st.text_no_route
	var at: Vector2 = _overlay.size * 0.5
	var width: float = _text_width(text, _font_size()) + 32.0
	var rect := Rect2(at - Vector2(width * 0.5, 22.0), Vector2(width, 44.0))
	studio.hud_rect = rect
	_panel(rect, _st.panel_border, _st.panel_bg)
	_text_centered(at + Vector2(0.0, 5.0), text, _st.text_color, _font_size())
