## Общий атлас и рендерер спрайтов спидометра/HUD.
##
## Загружает спрайт-лист (ui_hud_r1_ru.png, русс/англ JPG или пользовательский),
## при необходимости вырезает белый/тёмный фон, кеширует обработанную текстуру
## и нарезает все элементы:
##   - дугу тахометра (0..8);
##   - три сегментные шкалы в правом верхнем углу (ступенчатую, блочную, широкую);
##   - крупные и мелкие пиксельные цифры 0..9;
##   - подписи ПЕРЕДАЧА / GEAR, км/ч / km/h, миль/ч / mph;
##   - плашки передач 1..5.
##
## Используется и в SpriteSpeedometer, и в GaugeBar / SpriteCounter при
## переделке остального HUD под единый стиль спидометра.
@tool
class_name RallyHudSpriteAtlas
extends RefCounted

const DEFAULT_SHEET_PATH := "res://scenes/ui/ui_hud_r1_ru.png"

enum KeyoutMode {
	AUTO = 0,
	NONE = 1,
	WHITE_BG = 2,
	DARK_BG = 3,
}

enum BarKind {
	STEPPED = 0,
	BLOCKS = 1,
	WIDE = 2,
}

## Общий процессный кеш: одинаковый лист с тем же keyout не перерабатывается
## заново для каждого виджета HUD (6 шкал телеметрии + спидометр + счётчики).
static var _texture_cache: Dictionary = {}

var tex: Texture2D = null
var tint_tex: Texture2D = null
var ready: bool = false
var tex_size: Vector2 = Vector2.ZERO
var source_key: String = ""

var arc_rect: Rect2 = Rect2()
var bar_stepped_rect: Rect2 = Rect2()
var bar_stepped_segments: Array[Rect2] = []
var bar_block_rect: Rect2 = Rect2()
var bar_block_segments: Array[Rect2] = []
var bar_wide_rect: Rect2 = Rect2()
var bar_wide_segments: Array[Rect2] = []

var big_digits: Array[Rect2] = []
var small_digits: Array[Rect2] = []
var word_gear: Rect2 = Rect2()
var unit_kmh: Rect2 = Rect2()
var unit_mph: Rect2 = Rect2()
var gear_items: Array[Rect2] = []


static func clear_cache() -> void:
	_texture_cache.clear()


static func resolve_sheet_texture(explicit_sheet: Texture2D = null) -> Texture2D:
	if explicit_sheet != null:
		return explicit_sheet
	var candidates := [
		DEFAULT_SHEET_PATH,
		"res://ui_hud_r1_ru.png",
		"res://assets/ui_hud_r1_ru.png",
		"res://assets/ui/ui_hud_r1_ru.png",
		"res://assets/textures/ui_hud_r1_ru.png",
		"res://textures/ui_hud_r1_ru.png",
		"res://sprites/ui_hud_r1_ru.png",
		"res://ui/ui_hud_r1_ru.png",
	]
	for p in candidates:
		if ResourceLoader.exists(p):
			var loaded: Texture2D = ResourceLoader.load(p) as Texture2D
			if loaded != null:
				return loaded
	var found := _find_file_recursive("res://", "ui_hud_r1_ru.png")
	if not found.is_empty():
		return ResourceLoader.load(found) as Texture2D
	return null


static func _find_file_recursive(dir_path: String, target_name: String) -> String:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ""
	dir.list_dir_begin()
	var item := dir.get_next()
	while not item.is_empty():
		if item.begins_with("."):
			item = dir.get_next()
			continue
		var full := dir_path.path_join(item)
		if dir.current_is_dir():
			var found := _find_file_recursive(full, target_name)
			if not found.is_empty():
				dir.list_dir_end()
				return found
		elif item.to_lower() == target_name.to_lower():
			dir.list_dir_end()
			return full
		item = dir.get_next()
	dir.list_dir_end()
	return ""


func build(sheet: Texture2D = null, keyout: int = KeyoutMode.AUTO, pad_px: int = 2, custom_regions: Dictionary = {}) -> bool:
	ready = false
	tex = null
	tint_tex = null
	tex_size = Vector2.ZERO
	big_digits.clear()
	small_digits.clear()
	gear_items.clear()
	bar_stepped_segments.clear()
	bar_block_segments.clear()
	bar_wide_segments.clear()

	var raw_tex: Texture2D = resolve_sheet_texture(sheet)
	if raw_tex == null:
		return false

	var key_base := raw_tex.resource_path if not raw_tex.resource_path.is_empty() else str(raw_tex.get_instance_id())
	source_key = "%s|%d" % [key_base, keyout]
	if _texture_cache.has(source_key):
		var cached: Dictionary = _texture_cache[source_key]
		var cached_tex: Texture2D = cached.get("tex", null) as Texture2D
		var cached_tint: Texture2D = cached.get("tint_tex", null) as Texture2D
		if cached_tex != null:
			tex = cached_tex
			tint_tex = cached_tint if cached_tint != null else cached_tex
	if tex == null:
		_prepare_textures(raw_tex, keyout)
		if tex != null:
			_texture_cache[source_key] = {
				"tex": tex,
				"tint_tex": tint_tex if tint_tex != null else tex,
			}

	if tex == null:
		return false
	tex_size = tex.get_size()
	if tex_size.x <= 1.0 or tex_size.y <= 1.0:
		return false

	_slice_regions(pad_px, custom_regions)
	return ready


func _prepare_textures(raw_tex: Texture2D, keyout: int) -> void:
	var img := raw_tex.get_image()
	if img == null:
		tex = raw_tex
		tint_tex = raw_tex
		return
	if img.is_compressed():
		img.decompress()

	var effective_keyout := keyout
	if effective_keyout == KeyoutMode.AUTO:
		effective_keyout = _detect_keyout_mode(img)

	var modified := false
	if effective_keyout == KeyoutMode.WHITE_BG:
		_flood_remove_white_bg(img)
		modified = true
	elif effective_keyout == KeyoutMode.DARK_BG:
		_flood_remove_dark_bg(img)
		modified = true

	if modified:
		tex = ImageTexture.create_from_image(img)
	else:
		tex = raw_tex

	# Готовим нейтральную версию верхних правых шкал: тогда красные/серые
	# сегменты можно чисто перекрашивать в любой цвет телеметрии (зелёный газ,
	# золотой руль, синяя подвеска, фиолетовая перегрузка).
	var tint_img := img.duplicate() as Image
	if tint_img != null:
		if tint_img.get_format() != Image.FORMAT_RGBA8:
			tint_img.convert(Image.FORMAT_RGBA8)
		_neutralize_bars_region(tint_img)
		tint_tex = ImageTexture.create_from_image(tint_img)
	else:
		tint_tex = tex


func _detect_keyout_mode(img: Image) -> int:
	var w := img.get_width()
	var h := img.get_height()
	if w < 2 or h < 2:
		return KeyoutMode.NONE
	var corners := [Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, h - 1), Vector2i(w - 1, h - 1)]
	var all_opaque := true
	var all_white := true
	var all_dark := true
	for pt in corners:
		var c := img.get_pixelv(pt)
		if c.a < 0.85:
			all_opaque = false
			break
		if minf(c.r, minf(c.g, c.b)) < 0.90:
			all_white = false
		var mx := maxf(c.r, maxf(c.g, c.b))
		var mn := minf(c.r, minf(c.g, c.b))
		if mx > 0.22 or (mx - mn) > 0.08 or mx < 0.03:
			all_dark = false
	if not all_opaque:
		return KeyoutMode.NONE
	if all_white:
		return KeyoutMode.WHITE_BG
	if all_dark:
		return KeyoutMode.DARK_BG
	return KeyoutMode.NONE


func _flood_remove_white_bg(img: Image) -> void:
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var visited := PackedByteArray()
	visited.resize(w * h)
	var queue: Array[Vector2i] = []
	for x in range(w):
		queue.append(Vector2i(x, 0))
		queue.append(Vector2i(x, h - 1))
	for y in range(1, h - 1):
		queue.append(Vector2i(0, y))
		queue.append(Vector2i(w - 1, y))
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		if p.x < 0 or p.x >= w or p.y < 0 or p.y >= h:
			continue
		var idx := p.y * w + p.x
		if visited[idx] != 0:
			continue
		visited[idx] = 1
		var c := img.get_pixel(p.x, p.y)
		if minf(c.r, minf(c.g, c.b)) >= 0.92:
			img.set_pixel(p.x, p.y, Color(c.r, c.g, c.b, 0.0))
			queue.append(Vector2i(p.x + 1, p.y))
			queue.append(Vector2i(p.x - 1, p.y))
			queue.append(Vector2i(p.x, p.y + 1))
			queue.append(Vector2i(p.x, p.y - 1))


func _flood_remove_dark_bg(img: Image) -> void:
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var bg := (
		img.get_pixel(0, 0)
		+ img.get_pixel(w - 1, 0)
		+ img.get_pixel(0, h - 1)
		+ img.get_pixel(w - 1, h - 1)
	) * 0.25
	var visited := PackedByteArray()
	visited.resize(w * h)
	var queue: Array[Vector2i] = []
	for x in range(w):
		queue.append(Vector2i(x, 0))
		queue.append(Vector2i(x, h - 1))
	for y in range(1, h - 1):
		queue.append(Vector2i(0, y))
		queue.append(Vector2i(w - 1, y))
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		if p.x < 0 or p.x >= w or p.y < 0 or p.y >= h:
			continue
		var idx := p.y * w + p.x
		if visited[idx] != 0:
			continue
		visited[idx] = 1
		var c := img.get_pixel(p.x, p.y)
		var mx := maxf(c.r, maxf(c.g, c.b))
		if mx >= 0.045 and absf(c.r - bg.r) <= 0.06 and absf(c.g - bg.g) <= 0.06 and absf(c.b - bg.b) <= 0.06:
			img.set_pixel(p.x, p.y, Color(c.r, c.g, c.b, 0.0))
			queue.append(Vector2i(p.x + 1, p.y))
			queue.append(Vector2i(p.x - 1, p.y))
			queue.append(Vector2i(p.x, p.y + 1))
			queue.append(Vector2i(p.x, p.y - 1))

	# Заодно очищаем замкнутые дырки внутри 0, 4, 6, 8, 9 и дуги.
	# Берём только пиксели цвета фона, у которых вокруг нет светлого края.
	var hole_queue: Array[Vector2i] = []
	for y in range(2, h - 2):
		for x in range(2, w - 2):
			var idx := y * w + x
			if visited[idx] != 0:
				continue
			var c := img.get_pixel(x, y)
			var mx := maxf(c.r, maxf(c.g, c.b))
			var mn := minf(c.r, minf(c.g, c.b))
			if mx >= 0.06 and mx <= 0.16 and (mx - mn) <= 0.04 and absf(c.r - bg.r) <= 0.045 and absf(c.g - bg.g) <= 0.045 and absf(c.b - bg.b) <= 0.045:
				var c_l := img.get_pixel(x - 1, y)
				var c_r := img.get_pixel(x + 1, y)
				var c_u := img.get_pixel(x, y - 1)
				var c_d := img.get_pixel(x, y + 1)
				var nb_max := maxf(
					maxf(maxf(c_l.r, maxf(c_l.g, c_l.b)), maxf(c_r.r, maxf(c_r.g, c_r.b))),
					maxf(maxf(c_u.r, maxf(c_u.g, c_u.b)), maxf(c_d.r, maxf(c_d.g, c_d.b)))
				)
				if nb_max <= 0.18:
					hole_queue.append(Vector2i(x, y))
	var h_head := 0
	while h_head < hole_queue.size():
		var p := hole_queue[h_head]
		h_head += 1
		if p.x < 0 or p.x >= w or p.y < 0 or p.y >= h:
			continue
		var idx := p.y * w + p.x
		if visited[idx] != 0:
			continue
		visited[idx] = 1
		var c := img.get_pixel(p.x, p.y)
		var mx := maxf(c.r, maxf(c.g, c.b))
		if mx >= 0.045 and absf(c.r - bg.r) <= 0.055 and absf(c.g - bg.g) <= 0.055 and absf(c.b - bg.b) <= 0.055:
			img.set_pixel(p.x, p.y, Color(c.r, c.g, c.b, 0.0))
			hole_queue.append(Vector2i(p.x + 1, p.y))
			hole_queue.append(Vector2i(p.x - 1, p.y))
			hole_queue.append(Vector2i(p.x, p.y + 1))
			hole_queue.append(Vector2i(p.x, p.y - 1))


func _neutralize_bars_region(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := clampi(int(0.44 * float(w)), 0, w)
	var y1 := clampi(int(0.43 * float(h)), 0, h)
	for y in range(0, y1):
		for x in range(x0, w):
			var c := img.get_pixel(x, y)
			if c.a < 0.05:
				continue
			var mx := maxf(c.r, maxf(c.g, c.b))
			if mx < 0.18:
				continue
			var mn := minf(c.r, minf(c.g, c.b))
			var v := 0.92 if (mx - mn) > 0.18 else clampf(mx * 1.9, 0.48, 0.92)
			img.set_pixel(x, y, Color(v, v, v, c.a))


func _is_solid(c: Color) -> bool:
	return c.a > 0.30


func _is_bright_solid(c: Color) -> bool:
	return c.a > 0.30 and maxf(c.r, maxf(c.g, c.b)) > 0.25


func _find_tight_rect(img: Image, search: Rect2i, pad_px: int = 2) -> Rect2:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := clampi(search.position.x, 0, w - 1)
	var y0 := clampi(search.position.y, 0, h - 1)
	var x1 := clampi(search.end.x, 0, w)
	var y1 := clampi(search.end.y, 0, h)
	var min_x := x1
	var min_y := y1
	var max_x := x0 - 1
	var max_y := y0 - 1
	for y in range(y0, y1):
		for x in range(x0, x1):
			if _is_solid(img.get_pixel(x, y)):
				if x < min_x:
					min_x = x
				if y < min_y:
					min_y = y
				if x > max_x:
					max_x = x
				if y > max_y:
					max_y = y
	if max_x < min_x:
		return Rect2(search.position.x, search.position.y, search.size.x, search.size.y)
	min_x = maxi(0, min_x - pad_px)
	min_y = maxi(0, min_y - pad_px)
	max_x = mini(w - 1, max_x + pad_px)
	max_y = mini(h - 1, max_y + pad_px)
	return Rect2(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _find_horizontal_runs(img: Image, search: Rect2i, expected_count: int, pad_px: int = 2, max_gap_px: int = -1, bright_only: bool = false) -> Array[Rect2]:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := clampi(search.position.x, 0, w - 1)
	var y0 := clampi(search.position.y, 0, h - 1)
	var x1 := clampi(search.end.x, 0, w)
	var y1 := clampi(search.end.y, 0, h)
	var span_w := maxi(1, x1 - x0)

	var active_cols := PackedByteArray()
	active_cols.resize(span_w)
	for x in range(x0, x1):
		for y in range(y0, y1):
			var px := img.get_pixel(x, y)
			if bright_only:
				if _is_bright_solid(px):
					active_cols[x - x0] = 1
					break
			elif _is_solid(px):
				active_cols[x - x0] = 1
				break

	var runs: Array[Vector2i] = []
	var in_run := false
	var run_start := 0
	var max_gap := max_gap_px if max_gap_px >= 0 else maxi(1, int(float(w) * 0.006))
	var gap := 0

	for i in range(active_cols.size()):
		if active_cols[i] == 1:
			if not in_run:
				in_run = true
				run_start = x0 + i
			gap = 0
		else:
			if in_run:
				gap += 1
				if gap > max_gap:
					runs.append(Vector2i(run_start, x0 + i - gap))
					in_run = false
	if in_run:
		runs.append(Vector2i(run_start, x1 - 1))

	var out: Array[Rect2] = []
	if expected_count <= 0 or runs.size() == expected_count:
		for r in runs:
			out.append(_find_tight_rect(img, Rect2i(r.x, y0, r.y - r.x + 1, y1 - y0), pad_px))
		return out

	var slot_w := float(x1 - x0) / float(expected_count)
	for i in range(expected_count):
		var sx := int(round(x0 + i * slot_w))
		var ex := int(round(x0 + (i + 1) * slot_w))
		out.append(_find_tight_rect(img, Rect2i(sx, y0, maxi(1, ex - sx), y1 - y0), pad_px))
	return out


func _norm_to_recti(norm: Rect2, w: float, h: float) -> Rect2i:
	return Rect2i(
		int(round(norm.position.x * w)),
		int(round(norm.position.y * h)),
		maxi(1, int(round(norm.size.x * w))),
		maxi(1, int(round(norm.size.y * h)))
	)


func _resolve_search_zone(custom_regions: Dictionary, key: String, fallback: Rect2, w: float, h: float) -> Rect2i:
	if custom_regions.has(key):
		var candidate: Variant = custom_regions.get(key, fallback)
		if candidate is Rect2 and (candidate as Rect2).size.x > 0.01 and (candidate as Rect2).size.y > 0.01:
			return _norm_to_recti(candidate as Rect2, w, h)
	return _norm_to_recti(fallback, w, h)


func _slice_regions(pad_px: int, custom_regions: Dictionary) -> void:
	var img := tex.get_image()
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	var w := float(img.get_width())
	var h := float(img.get_height())

	var arc_zone := _resolve_search_zone(custom_regions, "arc", Rect2(0.0, 0.0, 0.44, 0.425), w, h)
	arc_rect = _find_tight_rect(img, arc_zone, pad_px)

	var bar1_zone := _resolve_search_zone(custom_regions, "bar_stepped", Rect2(0.45, 0.03, 0.53, 0.125), w, h)
	bar_stepped_rect = _find_tight_rect(img, bar1_zone, pad_px)
	bar_stepped_segments = _find_horizontal_runs(img, bar1_zone, 0, pad_px, maxi(1, int(w * 0.0025)), true)
	if bar_stepped_segments.is_empty() and bar_stepped_rect.size.x > 4.0:
		bar_stepped_segments = _split_rect_segments(bar_stepped_rect, 11)

	var bar2_zone := _resolve_search_zone(custom_regions, "bar_blocks", Rect2(0.45, 0.165, 0.53, 0.12), w, h)
	bar_block_rect = _find_tight_rect(img, bar2_zone, pad_px)
	bar_block_segments = _find_horizontal_runs(img, bar2_zone, 0, pad_px, maxi(1, int(w * 0.0025)), true)
	if bar_block_segments.is_empty() and bar_block_rect.size.x > 4.0:
		bar_block_segments = _split_rect_segments(bar_block_rect, 11)

	var bar3_zone := _resolve_search_zone(custom_regions, "bar_wide", Rect2(0.45, 0.29, 0.53, 0.125), w, h)
	bar_wide_rect = _find_tight_rect(img, bar3_zone, pad_px)
	bar_wide_segments = _find_horizontal_runs(img, bar3_zone, 0, pad_px, maxi(1, int(w * 0.0025)), true)
	if bar_wide_segments.is_empty() and bar_wide_rect.size.x > 4.0:
		bar_wide_segments = _split_rect_segments(bar_wide_rect, 4)

	var big_zone := _resolve_search_zone(custom_regions, "big_digits", Rect2(0.01, 0.425, 0.98, 0.17), w, h)
	big_digits = _find_horizontal_runs(img, big_zone, 10, pad_px)

	var small_zone := _resolve_search_zone(custom_regions, "small_digits", Rect2(0.01, 0.605, 0.98, 0.105), w, h)
	small_digits = _find_horizontal_runs(img, small_zone, 10, pad_px)

	var labels_zone := _resolve_search_zone(custom_regions, "labels", Rect2(0.01, 0.72, 0.98, 0.135), w, h)
	var label_runs := _find_horizontal_runs(img, labels_zone, 0, pad_px, maxi(8, int(w * 0.018)))
	if label_runs.size() >= 3:
		word_gear = label_runs[0]
		unit_kmh = label_runs[1]
		unit_mph = label_runs[2]
	else:
		word_gear = _find_tight_rect(img, Rect2i(int(0.01 * w), int(0.72 * h), int(0.51 * w), int(0.135 * h)), pad_px)
		unit_kmh = _find_tight_rect(img, Rect2i(int(0.52 * w), int(0.72 * h), int(0.21 * w), int(0.135 * h)), pad_px)
		unit_mph = _find_tight_rect(img, Rect2i(int(0.73 * w), int(0.72 * h), int(0.26 * w), int(0.135 * h)), pad_px)

	var gears_zone := _resolve_search_zone(custom_regions, "gears", Rect2(0.01, 0.86, 0.98, 0.12), w, h)
	var gear_runs := _find_horizontal_runs(img, gears_zone, 0, pad_px, maxi(6, int(w * 0.016)))
	if gear_runs.size() == 5:
		gear_items = gear_runs
	else:
		var gear_splits := [0.01, 0.215, 0.405, 0.595, 0.785, 0.99]
		gear_items.clear()
		for i in range(5):
			var gx0 := int(gear_splits[i] * w)
			var gx1 := int(gear_splits[i + 1] * w)
			gear_items.append(_find_tight_rect(img, Rect2i(gx0, int(0.86 * h), gx1 - gx0, int(0.12 * h)), pad_px))

	ready = big_digits.size() == 10 and small_digits.size() == 10 and gear_items.size() == 5


func _split_rect_segments(src: Rect2, count: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var n := maxi(1, count)
	var seg_w := src.size.x / float(n)
	for i in range(n):
		out.append(Rect2(src.position.x + float(i) * seg_w, src.position.y, seg_w, src.size.y))
	return out


func arc_uv_rect() -> Vector4:
	if tex_size.x <= 1.0 or tex_size.y <= 1.0:
		return Vector4(0.0, 0.0, 0.44, 0.42)
	return Vector4(
		arc_rect.position.x / tex_size.x,
		arc_rect.position.y / tex_size.y,
		arc_rect.size.x / tex_size.x,
		arc_rect.size.y / tex_size.y
	)


func bar_segments_for(kind: int) -> Array[Rect2]:
	match kind:
		BarKind.STEPPED:
			return bar_stepped_segments
		BarKind.BLOCKS:
			return bar_block_segments
		BarKind.WIDE:
			return bar_wide_segments
	return bar_block_segments


func bar_rect_for(kind: int) -> Rect2:
	match kind:
		BarKind.STEPPED:
			return bar_stepped_rect
		BarKind.BLOCKS:
			return bar_block_rect
		BarKind.WIDE:
			return bar_wide_rect
	return bar_block_rect


func measure_digits_width(value_text: String, digit_h: float, use_small: bool = false, gap: float = 2.0, slot_aspect: float = 0.66) -> float:
	if value_text.is_empty():
		return 0.0
	var glyphs := small_digits if use_small else big_digits
	var slot_w := digit_h * slot_aspect
	var punct_w := maxf(4.0, digit_h * 0.28)
	var total := 0.0
	for i in range(value_text.length()):
		if i > 0:
			total += gap
		var ch := value_text[i]
		if ch >= "0" and ch <= "9":
			if glyphs.size() == 10:
				var src := glyphs[int(ch)]
				var dw := digit_h * (src.size.x / maxf(src.size.y, 1.0))
				total += maxf(slot_w, dw)
			else:
				total += slot_w
		elif ch == ":" or ch == "." or ch == ",":
			total += punct_w
		elif ch == " ":
			total += slot_w * 0.45
		else:
			total += slot_w * 0.72
	return total


## Отрисовать строку из цифр (и разделителей `:`, `.`, `-`, `+`, `/`)
## пиксельными спрайтами из атласа. Возвращает итоговую ширину в пикселях.
func draw_digits(
	canvas: CanvasItem,
	value_text: String,
	origin_pos: Vector2,
	digit_h: float,
	use_small: bool = false,
	tint: Color = Color.WHITE,
	dim_leading_zeros: bool = true,
	dim_alpha: float = 0.16,
	gap: float = 2.0,
	slot_aspect: float = 0.66,
	separator_tint: Color = Color.WHITE
) -> float:
	if not ready or tex == null or canvas == null or value_text.is_empty():
		return 0.0
	var glyphs := small_digits if use_small else big_digits
	if glyphs.size() < 10:
		return 0.0

	var first_nz := value_text.length()
	var last_digit_idx := -1
	for i in range(value_text.length()):
		var c := value_text[i]
		if c >= "0" and c <= "9":
			last_digit_idx = i
			if c != "0" and first_nz == value_text.length():
				first_nz = i
	if first_nz == value_text.length() and last_digit_idx >= 0:
		first_nz = last_digit_idx

	var slot_w := digit_h * slot_aspect
	var punct_w := maxf(4.0, digit_h * 0.28)
	var cursor_x := origin_pos.x
	var sep_base := separator_tint if separator_tint.a > 0.0 else tint

	for i in range(value_text.length()):
		var ch := value_text[i]
		if ch >= "0" and ch <= "9":
			var d := int(ch)
			var src := glyphs[d]
			var dw := digit_h * (src.size.x / maxf(src.size.y, 1.0))
			var col_w := maxf(slot_w, dw)
			var dx := cursor_x + (col_w - dw) * 0.5
			var col := tint
			if dim_leading_zeros and ch == "0" and i < first_nz:
				col = Color(tint.r, tint.g, tint.b, tint.a * dim_alpha)
			canvas.draw_texture_rect_region(tex, Rect2(dx, origin_pos.y, dw, digit_h), src, col)
			cursor_x += col_w + gap
		elif ch == ":":
			var dot_s := maxf(2.0, roundf(digit_h * 0.14))
			var cx := cursor_x + (punct_w - dot_s) * 0.5
			var col_dim := sep_base
			if dim_leading_zeros and i < first_nz:
				col_dim = Color(sep_base.r, sep_base.g, sep_base.b, sep_base.a * maxf(0.32, dim_alpha))
			_draw_pixel_dot(canvas, Rect2(cx, origin_pos.y + digit_h * 0.27, dot_s, dot_s), col_dim)
			_draw_pixel_dot(canvas, Rect2(cx, origin_pos.y + digit_h * 0.65, dot_s, dot_s), col_dim)
			cursor_x += punct_w + gap
		elif ch == "." or ch == ",":
			var dot_s := maxf(2.0, roundf(digit_h * 0.14))
			var cx := cursor_x + (punct_w - dot_s) * 0.5
			_draw_pixel_dot(canvas, Rect2(cx, origin_pos.y + digit_h - dot_s - 1.0, dot_s, dot_s), sep_base)
			cursor_x += punct_w + gap
		elif ch == "-":
			var bw := slot_w * 0.58
			var bh := maxf(2.0, roundf(digit_h * 0.13))
			_draw_pixel_dot(canvas, Rect2(cursor_x + (slot_w * 0.72 - bw) * 0.5, origin_pos.y + (digit_h - bh) * 0.5, bw, bh), sep_base)
			cursor_x += slot_w * 0.72 + gap
		elif ch == "+":
			var bw := slot_w * 0.56
			var bh := maxf(2.0, roundf(digit_h * 0.13))
			var cx := cursor_x + slot_w * 0.36
			var cy := origin_pos.y + digit_h * 0.5
			_draw_pixel_dot(canvas, Rect2(cx - bw * 0.5, cy - bh * 0.5, bw, bh), sep_base)
			_draw_pixel_dot(canvas, Rect2(cx - bh * 0.5, cy - bw * 0.5, bh, bw), sep_base)
			cursor_x += slot_w * 0.72 + gap
		elif ch == " ":
			cursor_x += slot_w * 0.45 + gap
		else:
			var font := ThemeDB.fallback_font
			canvas.draw_string(font, Vector2(cursor_x, origin_pos.y + digit_h * 0.85), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, int(digit_h * 0.82), tint)
			cursor_x += slot_w * 0.72 + gap
	return maxf(0.0, cursor_x - origin_pos.x - gap)


func _draw_pixel_dot(canvas: CanvasItem, rect: Rect2, col: Color) -> void:
	canvas.draw_rect(rect.grow(1.0), Color(0.0, 0.0, 0.0, col.a * 0.85))
	canvas.draw_rect(rect, col)


## Отрисовать сегментную шкалу (бар1 / бар2 / бар3) прямо из спрайт-листа.
func draw_segmented_bar(
	canvas: CanvasItem,
	rect: Rect2,
	ratio: float,
	bar_kind: int,
	active_col: Color,
	inactive_col: Color,
	hot_col: Color,
	hot_start: float = 0.78,
	preserve_sprite_colors: bool = false,
	centered: bool = false,
	signed_val: float = 0.0
) -> void:
	if not ready or tex == null or canvas == null or rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	var segs := bar_segments_for(bar_kind)
	var full_rect := bar_rect_for(bar_kind)
	var draw_tex: Texture2D = tex if preserve_sprite_colors else (tint_tex if tint_tex != null else tex)

	if segs.size() <= 1 or bar_kind == BarKind.WIDE:
		if full_rect.size.x <= 1.0 or full_rect.size.y <= 1.0:
			return
		var bg_tint := Color(1.0, 1.0, 1.0, 0.25) if preserve_sprite_colors else inactive_col
		canvas.draw_texture_rect_region(draw_tex, rect, full_rect, bg_tint)
		var fill_r := clampf(ratio, 0.0, 1.0)
		if fill_r > 0.005:
			var fg_dst := Rect2(rect.position, Vector2(rect.size.x * fill_r, rect.size.y))
			var fg_src := Rect2(full_rect.position, Vector2(full_rect.size.x * fill_r, full_rect.size.y))
			var fg_tint := Color.WHITE if preserve_sprite_colors else active_col.lerp(hot_col, smoothstep(hot_start, 1.0, fill_r))
			canvas.draw_texture_rect_region(draw_tex, fg_dst, fg_src, fg_tint)
		return

	var total_span_x := segs[segs.size() - 1].end.x - segs[0].position.x
	var min_y := full_rect.position.y
	var total_h := maxf(full_rect.size.y, 1.0)
	if total_span_x <= 1.0:
		return

	var count := segs.size()
	var center_idx := (count - 1) * 0.5
	var clamped_ratio := clampf(ratio, 0.0, 1.0)

	for i in range(count):
		var src := segs[i]
		var rel_x := (src.position.x - segs[0].position.x) / total_span_x
		var rel_w := src.size.x / total_span_x
		var rel_y := (src.position.y - min_y) / total_h
		var rel_h := src.size.y / total_h
		var dst := Rect2(
			rect.position.x + rel_x * rect.size.x,
			rect.position.y + rel_y * rect.size.y,
			maxf(1.0, rel_w * rect.size.x),
			maxf(1.0, rel_h * rect.size.y)
		)
		var seg_pos := float(i + 1) / float(count)
		var is_lit := false
		if centered:
			var signed_norm := clampf(signed_val, -1.0, 1.0)
			if absf(signed_norm) <= 0.02:
				is_lit = absi(i - int(round(center_idx))) == 0
			elif signed_norm > 0.0:
				var end_idx := center_idx + signed_norm * center_idx
				is_lit = float(i) >= center_idx and float(i) <= end_idx + 0.05
			else:
				var start_idx := center_idx + signed_norm * center_idx
				is_lit = float(i) <= center_idx and float(i) >= start_idx - 0.05
		else:
			is_lit = clamped_ratio >= (float(i) + 0.25) / float(count)

		var col: Color
		if is_lit:
			if preserve_sprite_colors:
				col = Color.WHITE
			elif seg_pos >= hot_start:
				col = active_col.lerp(hot_col, clampf((seg_pos - hot_start) / maxf(0.01, 1.0 - hot_start), 0.0, 1.0))
			else:
				col = active_col
		else:
			col = Color(0.55, 0.55, 0.55, 0.28) if preserve_sprite_colors else inactive_col
		canvas.draw_texture_rect_region(draw_tex, dst, src, col)
