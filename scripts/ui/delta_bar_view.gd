## Полоса-индикатор живой дельты времени (от центра влево/вправо).
@tool
class_name RallyDeltaBarView
extends Control

var delta_seconds: float = 0.0:
	set(value):
		delta_seconds = value
		queue_redraw()
var max_seconds: float = 5.0:
	set(value):
		max_seconds = maxf(0.1, value)
		queue_redraw()
var neutral_threshold: float = 0.05:
	set(value):
		neutral_threshold = maxf(0.0, value)
		queue_redraw()
var ahead_fills_right: bool = true:
	set(value):
		ahead_fills_right = value
		queue_redraw()
var segmented: bool = true:
	set(value):
		segmented = value
		queue_redraw()
var segments_per_side: int = 10:
	set(value):
		segments_per_side = clampi(value, 2, 32)
		queue_redraw()
var segment_gap: float = 2.0:
	set(value):
		segment_gap = maxf(0.0, value)
		queue_redraw()
var pixel_mode: bool = false:
	set(value):
		pixel_mode = value
		queue_redraw()
var track_color: Color = Color(0.10, 0.13, 0.18, 0.90):
	set(value):
		track_color = value
		queue_redraw()
var border_color: Color = Color(1.0, 1.0, 1.0, 0.18):
	set(value):
		border_color = value
		queue_redraw()
var center_tick_color: Color = Color(1.0, 1.0, 1.0, 0.72):
	set(value):
		center_tick_color = value
		queue_redraw()
var ahead_color: Color = Color(0.24, 0.96, 0.56, 1.0):
	set(value):
		ahead_color = value
		queue_redraw()
var behind_color: Color = Color(1.0, 0.30, 0.22, 1.0):
	set(value):
		behind_color = value
		queue_redraw()
var neutral_color: Color = Color(0.92, 0.95, 1.0, 1.0):
	set(value):
		neutral_color = value
		queue_redraw()


func _draw() -> void:
	var w: float = self.size.x
	var h: float = self.size.y
	if w <= 2.0 or h <= 2.0:
		return

	var bg := StyleBoxFlat.new()
	bg.bg_color = track_color
	bg.border_color = border_color
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(0 if pixel_mode else 3)
	draw_style_box(bg, Rect2(Vector2.ZERO, Vector2(w, h)))

	var pad: float = 2.0
	var inner_h: float = maxf(2.0, h - pad * 2.0)
	var half_w: float = maxf(2.0, w * 0.5 - pad - 1.0)
	var center_x: float = w * 0.5

	var abs_d: float = absf(delta_seconds)
	var ratio: float = clampf(abs_d / maxf(0.1, max_seconds), 0.0, 1.0)
	var is_neutral: bool = abs_d <= neutral_threshold
	var is_ahead: bool = delta_seconds < 0.0
	var fill_col: Color = neutral_color if is_neutral else (ahead_color if is_ahead else behind_color)
	var go_right: bool = is_ahead if ahead_fills_right else (not is_ahead)

	if segmented:
		var seg_count: int = clampi(segments_per_side, 2, 32)
		var total_gaps: float = segment_gap * float(seg_count - 1)
		var seg_w: float = maxf(1.5, (half_w - total_gaps - 2.0) / float(seg_count))
		var lit_count: int = 0 if is_neutral else maxi(1, ceili(ratio * float(seg_count)))
		var inactive_col := Color(border_color.r, border_color.g, border_color.b, 0.10)
		for side_sign in [-1.0, 1.0]:
			var side_matches: bool = (not is_neutral) and ((side_sign > 0.0) == go_right)
			for idx in range(seg_count):
				var step_x: float = 2.0 + float(idx) * (seg_w + segment_gap)
				var sx: float = (center_x + step_x) if side_sign > 0.0 else (center_x - step_x - seg_w)
				var active: bool = side_matches and idx < lit_count
				var cell_col: Color = fill_col if active else inactive_col
				var cell_rect := Rect2(Vector2(sx, pad), Vector2(seg_w, inner_h))
				if pixel_mode:
					cell_rect.position = cell_rect.position.round()
					cell_rect.size = cell_rect.size.round()
				draw_rect(cell_rect, cell_col, true)
	else:
		if not is_neutral and ratio > 0.005:
			var fill_w: float = maxf(2.0, half_w * ratio)
			var fx: float = (center_x + 1.0) if go_right else (center_x - 1.0 - fill_w)
			draw_rect(Rect2(Vector2(fx, pad), Vector2(fill_w, inner_h)), fill_col, true)

	# Нулевая засечка по центру.
	draw_rect(Rect2(Vector2(center_x - 1.0, 0.0), Vector2(2.0, h)), center_tick_color, true)
