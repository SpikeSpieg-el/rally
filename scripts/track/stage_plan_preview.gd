## Генератор верхнего 2D-плана трассы (PNG «вид сверху») на чистом Image.
##
## Работает в редакторе Godot (без Python и без SubViewport/GPU — можно вызывать
## прямо из Студии трассы, пересборки этапа и headless-скриптов). Сохраняет
## PNG в `res://docs/previews/<имя>_stage_plan.png`, только если у ресурса
## `RallyTrackConfig` задана осевая линия `road_curve`.
@tool
class_name RallyStagePlanPreview
extends RefCounted

const DEFAULT_PREVIEWS_DIR := "res://docs/previews"
const DEFAULT_WIDTH_PX := 1100

const BG_COLOR := Color8(243, 241, 236)
const RIVER_BAND_COLOR := Color8(186, 213, 226)
const RIVER_AXIS_COLOR := Color8(96, 148, 176)
const BRIDGE_FILL_COLOR := Color8(255, 255, 255)
const BRIDGE_OUTLINE_COLOR := Color8(28, 28, 28)
const START_COLOR := Color8(32, 122, 52)
const FINISH_COLOR := Color8(150, 40, 34)
const TEXT_COLOR := Color8(60, 60, 60)
const BAR_COLOR := Color8(40, 40, 40)
const NOTE_COLOR := Color8(90, 100, 110)

const SCALE_CANDIDATES := [50, 100, 200, 250, 500, 1000, 2000, 5000, 10000, 20000]

## Растровый шрифт 5×7 (7 строк по 5 бит, старший бит слева) для текста на Image.
const GLYPHS_5X7 := {
	" ": [0, 0, 0, 0, 0, 0, 0],
	".": [0, 0, 0, 0, 0, 12, 12],
	",": [0, 0, 0, 0, 12, 4, 8],
	"-": [0, 0, 0, 30, 0, 0, 0],
	"—": [0, 0, 0, 31, 0, 0, 0],
	"/": [1, 2, 2, 4, 8, 8, 16],
	":": [0, 12, 12, 0, 12, 12, 0],
	"0": [14, 17, 19, 21, 25, 17, 14],
	"1": [4, 12, 4, 4, 4, 4, 14],
	"2": [14, 17, 1, 6, 8, 16, 31],
	"3": [30, 1, 1, 14, 1, 1, 30],
	"4": [2, 6, 10, 18, 31, 2, 2],
	"5": [31, 16, 30, 1, 1, 17, 14],
	"6": [6, 8, 16, 30, 17, 17, 14],
	"7": [31, 1, 2, 4, 8, 8, 8],
	"8": [14, 17, 17, 14, 17, 17, 14],
	"9": [14, 17, 17, 15, 1, 2, 12],
	"А": [14, 17, 17, 31, 17, 17, 17],
	"Б": [31, 16, 16, 30, 17, 17, 30],
	"В": [30, 17, 17, 30, 17, 17, 30],
	"Г": [31, 16, 16, 16, 16, 16, 16],
	"Д": [6, 10, 10, 10, 10, 31, 17],
	"Е": [31, 16, 16, 30, 16, 16, 31],
	"Ж": [21, 21, 14, 4, 14, 21, 21],
	"З": [14, 17, 1, 6, 1, 17, 14],
	"И": [17, 17, 19, 21, 25, 17, 17],
	"Й": [14, 0, 17, 19, 21, 25, 17],
	"К": [17, 18, 20, 24, 20, 18, 17],
	"Л": [7, 9, 9, 9, 9, 9, 17],
	"М": [17, 27, 21, 21, 17, 17, 17],
	"Н": [17, 17, 17, 31, 17, 17, 17],
	"О": [14, 17, 17, 17, 17, 17, 14],
	"П": [31, 17, 17, 17, 17, 17, 17],
	"Р": [30, 17, 17, 30, 16, 16, 16],
	"С": [14, 17, 16, 16, 16, 17, 14],
	"Т": [31, 4, 4, 4, 4, 4, 4],
	"У": [17, 17, 17, 15, 1, 17, 14],
	"Ф": [4, 14, 21, 21, 14, 4, 4],
	"Х": [17, 17, 10, 4, 10, 17, 17],
	"Ц": [17, 17, 17, 17, 17, 31, 1],
	"Ч": [17, 17, 17, 15, 1, 1, 1],
	"Ш": [21, 21, 21, 21, 21, 21, 31],
	"Щ": [21, 21, 21, 21, 21, 31, 1],
	"Ы": [17, 17, 29, 19, 19, 19, 29],
	"Ь": [16, 16, 30, 17, 17, 17, 30],
	"Э": [14, 17, 1, 15, 1, 17, 14],
	"Ю": [18, 21, 21, 29, 21, 21, 18],
	"Я": [15, 17, 17, 15, 5, 9, 17],
	"М_LOWER": [0, 0, 27, 21, 21, 17, 17],
	"К_LOWER": [0, 0, 18, 20, 24, 20, 18],
	"A": [14, 17, 17, 31, 17, 17, 17],
	"E": [31, 16, 16, 30, 16, 16, 31],
	"K": [17, 18, 20, 24, 20, 18, 17],
	"M": [17, 27, 21, 21, 17, 17, 17],
}


static func output_path_for_track(
	track: Resource,
	previews_dir: String = DEFAULT_PREVIEWS_DIR,
	fallback_stem: String = ""
) -> String:
	if track == null:
		return ""
	var stem: String = ""
	var res_path: String = track.resource_path
	if not res_path.is_empty():
		stem = res_path.get_file().get_basename()
	elif not fallback_stem.is_empty():
		stem = fallback_stem
	else:
		var track_id_raw: Variant = track.get("id")
		if track_id_raw != null:
			stem = String(track_id_raw).strip_edges()
	if stem.is_empty():
		return ""
	if stem.begins_with("stage_"):
		stem = stem.substr(6)
	if not stem.ends_with("_stage"):
		stem = stem + "_stage"
	var base_dir: String = DEFAULT_PREVIEWS_DIR if previews_dir.is_empty() else previews_dir
	return base_dir.path_join(stem + "_plan.png")


static func ensure_previews_dir(previews_dir: String) -> String:
	var abs_dir: String = _to_global_path(previews_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	if previews_dir == DEFAULT_PREVIEWS_DIR or previews_dir.ends_with("/docs/previews"):
		var gdignore_path: String = abs_dir.path_join(".gdignore")
		if not FileAccess.file_exists(gdignore_path):
			var file: FileAccess = FileAccess.open(gdignore_path, FileAccess.WRITE)
			if file != null:
				file.store_string("")
				file.close()
	return abs_dir


static func export_for_track(
	track: Resource,
	previews_dir: String = DEFAULT_PREVIEWS_DIR,
	width_px: int = DEFAULT_WIDTH_PX,
	explicit_out_path: String = "",
	fallback_stem: String = ""
) -> String:
	if track == null:
		return ""
	var raw_curve: Variant = track.get("road_curve")
	if not (raw_curve is Curve3D):
		return ""
	var target_path: String = explicit_out_path
	if target_path.is_empty():
		target_path = output_path_for_track(track, previews_dir, fallback_stem)
	if target_path.is_empty():
		return ""
	if target_path.begins_with("res://") and (OS.has_feature("standalone") or OS.has_feature("web")):
		return ""
	var img: Image = render_image(track, width_px)
	if img == null:
		return ""
	var parent_dir: String = target_path.get_base_dir()
	ensure_previews_dir(parent_dir)
	var abs_file: String = _to_global_path(target_path)
	var err: Error = img.save_png(abs_file)
	if err != OK:
		return ""
	return target_path


static func render_image(track: Resource, width_px: int = DEFAULT_WIDTH_PX) -> Image:
	if track == null:
		return null
	var raw_curve: Variant = track.get("road_curve")
	if not (raw_curve is Curve3D):
		return null
	var road_curve: Curve3D = raw_curve as Curve3D
	if road_curve.point_count < 2:
		return null
	var total_len: float = road_curve.get_baked_length()
	if total_len <= 1.0:
		return null

	var step: float = maxf(2.0, total_len / 2000.0) if total_len > 4000.0 else 2.0
	var count: int = clampi(int(ceil(total_len / step)) + 1, 2, 2400)
	var pts := PackedVector3Array()
	pts.resize(count)
	for i in range(count):
		var dist: float = total_len * float(i) / float(count - 1)
		pts[i] = road_curve.sample_baked(dist)

	var river_pts := PackedVector3Array()
	var river_width: float = 14.0
	var raw_river: Variant = track.get("river")
	if raw_river is Resource:
		var river_res: Resource = raw_river as Resource
		if bool(river_res.get("enabled")):
			var raw_water: Variant = river_res.get("water_curve")
			if raw_water is Curve3D:
				var water_curve: Curve3D = raw_water as Curve3D
				var water_len: float = water_curve.get_baked_length()
				if water_curve.point_count >= 2 and water_len > 1.0:
					var w_count: int = clampi(int(ceil(water_len / 4.0)) + 1, 2, 1200)
					river_pts.resize(w_count)
					for i in range(w_count):
						var w_dist: float = water_len * float(i) / float(w_count - 1)
						river_pts[i] = water_curve.sample_baked(w_dist)
					var raw_w: Variant = river_res.get("width_meters")
					if raw_w != null and float(raw_w) > 0.0:
						river_width = float(raw_w)

	var min_x: float = pts[0].x
	var max_x: float = pts[0].x
	var min_z: float = pts[0].z
	var max_z: float = pts[0].z
	var low_h: float = pts[0].y
	var high_h: float = pts[0].y
	for p in pts:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
		low_h = minf(low_h, p.y)
		high_h = maxf(high_h, p.y)

	var span_x: float = maxf(1.0, max_x - min_x)
	var span_z: float = maxf(1.0, max_z - min_z)
	var elev_span: float = high_h - low_h
	var pad_x: int = 60
	var top_pad: int = 78
	var bottom_pad: int = 76
	var clamped_w: int = maxi(480, width_px)
	var scale: float = float(clamped_w - 160) / maxf(span_x, span_z)
	var w: int = maxi(560, int(span_x * scale) + pad_x * 2)
	var h: int = maxi(360, int(span_z * scale) + top_pad + bottom_pad)
	var origin_x: float = float(pad_x) + (float(w - pad_x * 2) - span_x * scale) * 0.5
	var origin_y: float = float(top_pad) + (float(h - top_pad - bottom_pad) - span_z * scale) * 0.5

	var img: Image = Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	img.fill(BG_COLOR)

	# 1. Река (полоса воды + осевая).
	if river_pts.size() >= 2:
		var band: float = maxf(2.0, roundf(river_width * scale))
		var axis_w: float = maxf(1.0, floorf(band / 6.0))
		for i in range(river_pts.size() - 1):
			var rp0: Vector2 = _to_px(river_pts[i], min_x, min_z, origin_x, origin_y, scale)
			var rp1: Vector2 = _to_px(river_pts[i + 1], min_x, min_z, origin_x, origin_y, scale)
			_draw_line(img, rp0, rp1, band * 0.5, RIVER_BAND_COLOR)
		for i in range(river_pts.size() - 1):
			var ap0: Vector2 = _to_px(river_pts[i], min_x, min_z, origin_x, origin_y, scale)
			var ap1: Vector2 = _to_px(river_pts[i + 1], min_x, min_z, origin_x, origin_y, scale)
			_draw_line(img, ap0, ap1, axis_w * 0.5, RIVER_AXIS_COLOR)

	# 2. Дорога, раскрашенная по высоте.
	var route_px := PackedVector2Array()
	route_px.resize(pts.size())
	for i in range(pts.size()):
		route_px[i] = _to_px(pts[i], min_x, min_z, origin_x, origin_y, scale)
	for i in range(pts.size() - 1):
		var t: float = (pts[i].y - low_h) / elev_span if elev_span > 0.5 else 0.35
		_draw_line(img, route_px[i], route_px[i + 1], 1.5, _height_color(clampf(t, 0.0, 1.0)))

	# 3. Мосты вдоль осевой.
	var raw_bridges: Variant = track.get("bridges")
	var bridge_labels: Array[Vector2] = []
	if raw_bridges is Array:
		var bridges_arr: Array = raw_bridges as Array
		for entry in bridges_arr:
			if not (entry is Resource):
				continue
			var bridge: Resource = entry as Resource
			if not bool(bridge.get("enabled")):
				continue
			var bdist: float = clampf(float(bridge.get("distance")), 0.0, total_len)
			var bpos: Vector3 = road_curve.sample_baked(bdist)
			var bp: Vector2 = _to_px(bpos, min_x, min_z, origin_x, origin_y, scale)
			_draw_circle_outlined(img, bp, 9.0, BRIDGE_FILL_COLOR, BRIDGE_OUTLINE_COLOR, 2.0)
			var dy: float = -8.0
			for prev_lbl in bridge_labels:
				if absf(bp.x - prev_lbl.x) < 90.0 and absf((bp.y + dy) - prev_lbl.y) < 18.0:
					dy += 18.0
			bridge_labels.append(Vector2(bp.x, bp.y + dy))
			_draw_marker_label(img, bp.x, bp.y, "%d м" % roundi(bdist), BRIDGE_OUTLINE_COLOR, w, 2, false, dy)

	# 4. Старт и финиш (без наложения на линию и друг на друга).
	var sx: float = route_px[0].x
	var sy: float = route_px[0].y
	var fx: float = route_px[route_px.size() - 1].x
	var fy: float = route_px[route_px.size() - 1].y
	var near_pts := PackedVector2Array()
	var stride: int = maxi(1, route_px.size() / 600)
	for i in range(0, route_px.size(), stride):
		near_pts.append(route_px[i])

	var same_spot: bool = Vector2(sx, sy).distance_to(Vector2(fx, fy)) < 28.0
	if same_spot:
		_draw_circle_outlined(img, Vector2(sx, sy), 8.0, START_COLOR, BG_COLOR, 2.0)
		_draw_circle(img, Vector2(fx, fy), 4.0, FINISH_COLOR)
		_place_endpoint_label(img, sx, sy, "СТАРТ", START_COLOR, w, h, near_pts, -22.0, true)
		_place_endpoint_label(img, fx, fy, "ФИНИШ", FINISH_COLOR, w, h, near_pts, 7.0, true)
	else:
		_draw_circle_outlined(img, Vector2(sx, sy), 7.0, START_COLOR, BG_COLOR, 1.0)
		_place_endpoint_label(img, sx, sy, "СТАРТ", START_COLOR, w, h, near_pts, NAN, false)
		_draw_circle_outlined(img, Vector2(fx, fy), 7.0, FINISH_COLOR, BG_COLOR, 1.0)
		_place_endpoint_label(img, fx, fy, "ФИНИШ", FINISH_COLOR, w, h, near_pts, NAN, false)

	# 5. Легенда высот сверху.
	_draw_text(img, float(pad_x), 18.0, "ВЫСОТА, м", TEXT_COLOR, 2, false)
	var bar_x: int = pad_x + 116
	for i in range(240):
		var gt: float = float(i) / 239.0
		var col: Color = _height_color(gt)
		_fill_rect(img, bar_x + i, 20, bar_x + i + 1, 34, col)
	if elev_span <= 0.5:
		var flat_lbl: String = "%.0f м" % low_h
		var ftw: int = _text_width(flat_lbl, 2)
		_draw_text(img, float(bar_x + 120) - float(ftw) * 0.5, 39.0, flat_lbl, TEXT_COLOR, 2, false)
	else:
		var lo_lbl: String = "%.0f" % low_h
		var hi_lbl: String = "%.0f" % (low_h + elev_span)
		var hi_w: int = _text_width(hi_lbl, 2)
		_draw_text(img, float(bar_x), 39.0, lo_lbl, TEXT_COLOR, 2, false)
		_draw_text(img, float(bar_x + 240 - hi_w), 39.0, hi_lbl, TEXT_COLOR, 2, false)

	# 6. Масштабная линейка снизу.
	var bar_m: int = _pick_scale_bar_m(scale)
	var bar_len: int = maxi(20, roundi(float(bar_m) * scale))
	var bar_y: int = h - 26
	_fill_rect(img, pad_x, bar_y - 1, pad_x + bar_len, bar_y + 2, BAR_COLOR)
	var scale_lbl: String = _format_scale_label(bar_m)
	_draw_text(img, float(pad_x), float(bar_y - 20), scale_lbl, BAR_COLOR, 2, false)
	if river_pts.size() >= 2:
		var note: String = "РЕКА И МОСТЫ"
		if pad_x + bar_len + 36 + _text_width(note, 2) <= w - 16:
			_draw_text(img, float(pad_x + bar_len + 36), float(bar_y - 20), note, NOTE_COLOR, 2, false)

	return img


static func _to_global_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


static func _to_px(p: Vector3, min_x: float, min_z: float, ox: float, oy: float, scale: float) -> Vector2:
	return Vector2(ox + (p.x - min_x) * scale, oy + (p.z - min_z) * scale)


static func _height_color(t: float) -> Color:
	var c0 := Color8(56, 96, 190)
	var c1 := Color8(60, 180, 120)
	var c2 := Color8(232, 200, 70)
	var c3 := Color8(222, 74, 62)
	if t <= 0.35:
		return c0.lerp(c1, t / 0.35)
	if t <= 0.70:
		return c1.lerp(c2, (t - 0.35) / 0.35)
	return c2.lerp(c3, (t - 0.70) / 0.30)


static func _pick_scale_bar_m(scale: float) -> int:
	var target_px: float = 180.0
	var best_in_range: int = -1
	var best_in_diff: float = 1e12
	var best_any: int = int(SCALE_CANDIDATES[0])
	var best_any_diff: float = 1e12
	for m_raw in SCALE_CANDIDATES:
		var m: int = int(m_raw)
		var px_len: float = float(m) * scale
		var diff: float = absf(px_len - target_px)
		if px_len >= 80.0 and px_len <= 300.0 and diff < best_in_diff:
			best_in_diff = diff
			best_in_range = m
		if diff < best_any_diff:
			best_any_diff = diff
			best_any = m
	return best_in_range if best_in_range > 0 else best_any


static func _format_scale_label(meters: int) -> String:
	if meters >= 1000 and meters % 1000 == 0:
		return "%d км" % (meters / 1000)
	return "%d м" % meters


static func _blend_pixel(img: Image, x: int, y: int, color: Color, alpha: float) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height() or alpha <= 0.0:
		return
	if alpha >= 0.999:
		img.set_pixel(x, y, color)
		return
	var dst: Color = img.get_pixel(x, y)
	img.set_pixel(x, y, dst.lerp(color, alpha))


static func _fill_rect(img: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
	var lo_x: int = clampi(mini(x0, x1), 0, img.get_width())
	var hi_x: int = clampi(maxi(x0, x1), 0, img.get_width())
	var lo_y: int = clampi(mini(y0, y1), 0, img.get_height())
	var hi_y: int = clampi(maxi(y0, y1), 0, img.get_height())
	for py in range(lo_y, hi_y):
		for px in range(lo_x, hi_x):
			img.set_pixel(px, py, color)


static func _draw_line(img: Image, p0: Vector2, p1: Vector2, radius: float, color: Color) -> void:
	var rad: float = maxf(0.5, radius)
	var min_x: int = clampi(int(floorf(minf(p0.x, p1.x) - rad - 1.0)), 0, img.get_width() - 1)
	var max_x: int = clampi(int(ceilf(maxf(p0.x, p1.x) + rad + 1.0)), 0, img.get_width() - 1)
	var min_y: int = clampi(int(floorf(minf(p0.y, p1.y) - rad - 1.0)), 0, img.get_height() - 1)
	var max_y: int = clampi(int(ceilf(maxf(p0.y, p1.y) + rad + 1.0)), 0, img.get_height() - 1)
	var dx: float = p1.x - p0.x
	var dy: float = p1.y - p0.y
	var len_sq: float = dx * dx + dy * dy
	for py in range(min_y, max_y + 1):
		for px in range(min_x, max_x + 1):
			var dist: float = 0.0
			if len_sq > 1e-6:
				var t: float = clampf(((float(px) - p0.x) * dx + (float(py) - p0.y) * dy) / len_sq, 0.0, 1.0)
				var qx: float = p0.x + dx * t
				var qy: float = p0.y + dy * t
				dist = Vector2(float(px) - qx, float(py) - qy).length()
			else:
				dist = Vector2(float(px) - p0.x, float(py) - p0.y).length()
			if dist <= rad - 0.5:
				img.set_pixel(px, py, color)
			elif dist < rad + 0.5:
				_blend_pixel(img, px, py, color, rad + 0.5 - dist)


static func _draw_circle(img: Image, center: Vector2, radius: float, color: Color) -> void:
	var min_x: int = clampi(int(floorf(center.x - radius - 1.0)), 0, img.get_width() - 1)
	var max_x: int = clampi(int(ceilf(center.x + radius + 1.0)), 0, img.get_width() - 1)
	var min_y: int = clampi(int(floorf(center.y - radius - 1.0)), 0, img.get_height() - 1)
	var max_y: int = clampi(int(ceilf(center.y + radius + 1.0)), 0, img.get_height() - 1)
	for py in range(min_y, max_y + 1):
		for px in range(min_x, max_x + 1):
			var dist: float = Vector2(float(px), float(py)).distance_to(center)
			if dist <= radius - 0.5:
				img.set_pixel(px, py, color)
			elif dist < radius + 0.5:
				_blend_pixel(img, px, py, color, radius + 0.5 - dist)


static func _draw_circle_outlined(
	img: Image,
	center: Vector2,
	radius: float,
	fill_color: Color,
	outline_color: Color,
	outline_width: float
) -> void:
	var outer: float = radius + outline_width * 0.5
	var inner: float = radius - outline_width * 0.5
	var min_x: int = clampi(int(floorf(center.x - outer - 1.0)), 0, img.get_width() - 1)
	var max_x: int = clampi(int(ceilf(center.x + outer + 1.0)), 0, img.get_width() - 1)
	var min_y: int = clampi(int(floorf(center.y - outer - 1.0)), 0, img.get_height() - 1)
	var max_y: int = clampi(int(ceilf(center.y + outer + 1.0)), 0, img.get_height() - 1)
	for py in range(min_y, max_y + 1):
		for px in range(min_x, max_x + 1):
			var dist: float = Vector2(float(px), float(py)).distance_to(center)
			if dist >= inner - 0.5 and dist <= outer + 0.5:
				if dist <= outer - 0.5 and dist >= inner + 0.5:
					img.set_pixel(px, py, outline_color)
				elif dist > outer - 0.5:
					_blend_pixel(img, px, py, outline_color, maxf(0.0, outer + 0.5 - dist))
				else:
					img.set_pixel(px, py, fill_color)
					_blend_pixel(img, px, py, outline_color, maxf(0.0, dist - (inner - 0.5)))
			elif dist < inner - 0.5:
				img.set_pixel(px, py, fill_color)


static func _glyph_key(ch: String) -> String:
	if ch == "м":
		return "М_LOWER"
	if ch == "к":
		return "К_LOWER"
	var up: String = ch.to_upper()
	if GLYPHS_5X7.has(up):
		return up
	return ch


static func _text_width(text: String, glyph_scale: int, bold: bool = false) -> int:
	if text.is_empty():
		return 0
	var step_x: int = 6 * glyph_scale + (1 if bold else 0)
	return maxi(0, text.length() * step_x - glyph_scale)


static func _draw_text(
	img: Image,
	x: float,
	y: float,
	text: String,
	color: Color,
	glyph_scale: int = 2,
	bold: bool = false
) -> void:
	var cx: int = roundi(x)
	var cy: int = roundi(y)
	var step_x: int = 6 * glyph_scale + (1 if bold else 0)
	for i in range(text.length()):
		var key: String = _glyph_key(text.substr(i, 1))
		if GLYPHS_5X7.has(key):
			var rows: Array = GLYPHS_5X7[key]
			for ry in range(7):
				var bits: int = int(rows[ry])
				for rx in range(5):
					if ((bits >> (4 - rx)) & 1) != 0:
						var px_start: int = cx + rx * glyph_scale
						var py_start: int = cy + ry * glyph_scale
						_fill_rect(img, px_start, py_start, px_start + glyph_scale + (1 if bold else 0), py_start + glyph_scale, color)
		cx += step_x


static func _draw_marker_label(
	img: Image,
	x: float,
	y: float,
	text: String,
	color: Color,
	canvas_w: int,
	glyph_scale: int = 2,
	bold: bool = false,
	dy: float = -7.0
) -> void:
	var tw: int = _text_width(text, glyph_scale, bold)
	var tx: float = x + 11.0
	if tx + float(tw) > float(canvas_w - 12):
		tx = maxf(8.0, x - 11.0 - float(tw))
	_draw_text(img, tx, y + dy, text, color, glyph_scale, bold)


static func _rect_route_clearance(rx: float, ry: float, rw: float, rh: float, screen_pts: PackedVector2Array) -> float:
	var cx0: float = rx
	var cx1: float = rx + rw
	var cy0: float = ry
	var cy1: float = ry + rh
	var best: float = 1e12
	for p in screen_pts:
		var dx: float = maxf(cx0 - p.x, maxf(0.0, p.x - cx1))
		var dy: float = maxf(cy0 - p.y, maxf(0.0, p.y - cy1))
		var d_sq: float = dx * dx + dy * dy
		if d_sq < best:
			best = d_sq
	return sqrt(best)


static func _place_endpoint_label(
	img: Image,
	mx: float,
	my: float,
	text: String,
	color: Color,
	canvas_w: int,
	canvas_h: int,
	screen_pts: PackedVector2Array,
	prefer_dy: float,
	has_prefer_dy: bool
) -> void:
	var glyph_scale: int = 2
	var bold: bool = true
	var tw: float = float(_text_width(text, glyph_scale, bold))
	var th: float = 7.0 * float(glyph_scale)
	var offsets: Array[Vector2] = []
	if has_prefer_dy:
		offsets = [
			Vector2(11.0, prefer_dy),
			Vector2(-11.0 - tw, prefer_dy),
			Vector2(-tw * 0.5, prefer_dy),
		]
	else:
		offsets = [
			Vector2(10.0, -th - 7.0),
			Vector2(10.0, 9.0),
			Vector2(-11.0 - tw, -th * 0.5),
			Vector2(11.0, -th * 0.5),
			Vector2(-tw * 0.5, -th - 10.0),
			Vector2(-tw * 0.5, 11.0),
			Vector2(-11.0 - tw, -th - 6.0),
			Vector2(-11.0 - tw, 8.0),
		]

	var best_pos := Vector2.ZERO
	var has_best: bool = false
	var best_score: float = -1e12
	for offset in offsets:
		var rx: float = mx + offset.x
		var ry: float = my + offset.y
		if rx < 8.0 or rx + tw > float(canvas_w - 8):
			continue
		if ry < 62.0 or ry + th > float(canvas_h - 54):
			continue
		var clearance: float = _rect_route_clearance(rx, ry, tw, th, screen_pts)
		var marker_gap: float = maxf(
			maxf(mx - 10.0 - (rx + tw), rx - (mx + 10.0)),
			maxf(my - 10.0 - (ry + th), maxf(ry - (my + 10.0), 0.0))
		)
		var dist_penalty: float = Vector2(offset.x * 0.1, offset.y * 0.1).length() * 0.05
		var score: float = minf(clearance, 24.0) + minf(marker_gap, 12.0) * 0.5 - dist_penalty
		if score > best_score:
			best_score = score
			best_pos = Vector2(rx, ry)
			has_best = true
	if has_best:
		_draw_text(img, best_pos.x, best_pos.y, text, color, glyph_scale, bold)
	else:
		var fallback_dy: float = prefer_dy if has_prefer_dy else -7.0
		_draw_marker_label(img, mx, my, text, color, canvas_w, glyph_scale, bold, fallback_dy)
