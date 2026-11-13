## Ползунок телеметрии. При `centered` заполнение растёт от центра влево/вправо,
## иначе от левого края. Поддерживает единый стиль HUD: плавный векторный,
## дискретные пиксельные блоки или спрайтовые шкалы из атласа спидометра.
@tool
class_name GaugeBar
extends Control

enum DisplayStyle {
	AUTO_FROM_HUD_STYLE = 0,
	SMOOTH_SOLID = 1,
	PIXEL_SOLID = 2,
	SPRITE_STEPPED = 3,
	SPRITE_BLOCKS = 4,
	SPRITE_WIDE = 5,
}

@export var hud_style: RallyHudStyle:
	set(v):
		if hud_style != null and hud_style.changed.is_connected(_on_hud_style_changed):
			hud_style.changed.disconnect(_on_hud_style_changed)
		hud_style = v
		if hud_style != null and not hud_style.changed.is_connected(_on_hud_style_changed):
			hud_style.changed.connect(_on_hud_style_changed)
		_refresh_style_state()

@export var display_style: DisplayStyle = DisplayStyle.AUTO_FROM_HUD_STYLE:
	set(v):
		display_style = v
		_refresh_style_state()

@export var bar_color: Color = Color(0.30, 0.90, 0.42, 1.0):
	set(v):
		bar_color = v
		queue_redraw()

@export var bg_color: Color = Color(1.0, 1.0, 1.0, 0.08):
	set(v):
		bg_color = v
		queue_redraw()

@export var center_color: Color = Color(1.0, 1.0, 1.0, 0.4):
	set(v):
		center_color = v
		queue_redraw()

@export var hot_color: Color = Color(1.0, 0.28, 0.24, 1.0):
	set(v):
		hot_color = v
		queue_redraw()

@export_range(0.5, 1.0, 0.02) var hot_start: float = 0.85

@export var centered: bool = true:
	set(v):
		centered = v
		queue_redraw()

@export var round_corners: bool = true:
	set(v):
		round_corners = v
		queue_redraw()

@export_range(4, 24, 1) var pixel_segments: int = 11:
	set(v):
		pixel_segments = clampi(v, 4, 24)
		queue_redraw()

@export var show_pixel_border: bool = false:
	set(v):
		show_pixel_border = v
		queue_redraw()

@export var border_color: Color = Color(0.30, 0.58, 0.84, 0.55):
	set(v):
		border_color = v
		queue_redraw()

@export var sprite_sheet: Texture2D:
	set(v):
		sprite_sheet = v
		_refresh_style_state()

var value: float = 0.0
var _atlas: RallyHudSpriteAtlas = null
var _atlas_ok: bool = false


func _ready() -> void:
	_refresh_style_state()


func set_hud_style(style_res: RallyHudStyle) -> void:
	hud_style = style_res


func set_value(new_value: float) -> void:
	value = new_value
	queue_redraw()


func _on_hud_style_changed() -> void:
	_refresh_style_state()


func _effective_style() -> int:
	if display_style != DisplayStyle.AUTO_FROM_HUD_STYLE:
		return int(display_style)
	if hud_style == null:
		return int(DisplayStyle.SMOOTH_SOLID)
	if not hud_style.is_pixel_mode():
		return int(DisplayStyle.SMOOTH_SOLID)
	match hud_style.gauge_style_mode:
		RallyHudStyle.GaugeStyleMode.VECTOR:
			return int(DisplayStyle.SMOOTH_SOLID)
		RallyHudStyle.GaugeStyleMode.PIXEL_SEGMENTED:
			return int(DisplayStyle.PIXEL_SOLID)
		RallyHudStyle.GaugeStyleMode.SPRITE_STEPPED:
			return int(DisplayStyle.SPRITE_STEPPED)
		RallyHudStyle.GaugeStyleMode.SPRITE_BLOCKS:
			return int(DisplayStyle.SPRITE_BLOCKS)
		RallyHudStyle.GaugeStyleMode.SPRITE_WIDE:
			return int(DisplayStyle.SPRITE_WIDE)
	return int(DisplayStyle.PIXEL_SOLID)


func _refresh_style_state() -> void:
	var eff := _effective_style()
	if hud_style != null and hud_style.is_pixel_mode():
		bg_color = hud_style.gauge_inactive_color
		border_color = Color(hud_style.panel_border_color.r, hud_style.panel_border_color.g, hud_style.panel_border_color.b, 0.45)
		show_pixel_border = true
		round_corners = false
		pixel_segments = hud_style.gauge_segments
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if hud_style.pixel_crisp_filtering else CanvasItem.TEXTURE_FILTER_LINEAR
	elif hud_style != null:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		show_pixel_border = false

	var wants_sprite := eff == int(DisplayStyle.SPRITE_STEPPED) or eff == int(DisplayStyle.SPRITE_BLOCKS) or eff == int(DisplayStyle.SPRITE_WIDE)
	if wants_sprite:
		if _atlas == null:
			_atlas = RallyHudSpriteAtlas.new()
		var sheet: Texture2D = sprite_sheet if sprite_sheet != null else (hud_style.sprite_sheet if hud_style != null else null)
		var keyout := int(hud_style.keyout_mode) if hud_style != null else int(RallyHudSpriteAtlas.KeyoutMode.AUTO)
		var pad := hud_style.slice_pad_px if hud_style != null else 2
		_atlas_ok = _atlas.build(sheet, keyout, pad)
	else:
		_atlas_ok = false
	queue_redraw()


func _radius() -> int:
	if not round_corners:
		return 0
	return mini(4, int(self.size.y * 0.5))


func _trough_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.set_corner_radius_all(_radius())
	return style


func _fill_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bar_color
	style.set_corner_radius_all(_radius())
	return style


func _draw() -> void:
	var ctrl_w := self.size.x
	var ctrl_h := self.size.y
	if ctrl_w <= 1.0 or ctrl_h <= 1.0:
		return
	var rect := Rect2(Vector2.ZERO, Vector2(ctrl_w, ctrl_h))
	var eff := _effective_style()

	var wants_sprite := eff == int(DisplayStyle.SPRITE_STEPPED) or eff == int(DisplayStyle.SPRITE_BLOCKS) or eff == int(DisplayStyle.SPRITE_WIDE)
	if wants_sprite and _atlas_ok and _atlas != null:
		draw_rect(rect, bg_color, true)
		var kind := RallyHudSpriteAtlas.BarKind.BLOCKS
		if eff == int(DisplayStyle.SPRITE_STEPPED):
			kind = RallyHudSpriteAtlas.BarKind.STEPPED
		elif eff == int(DisplayStyle.SPRITE_WIDE):
			kind = RallyHudSpriteAtlas.BarKind.WIDE
		var inner := Rect2(1.0, 1.0, maxf(1.0, ctrl_w - 2.0), maxf(1.0, ctrl_h - 2.0))
		var preserve := hud_style.gauge_preserve_sprite_colors if hud_style != null else false
		_atlas.draw_segmented_bar(
			self,
			inner,
			absf(value),
			kind,
			bar_color,
			Color(bg_color.r + 0.12, bg_color.g + 0.14, bg_color.b + 0.18, 0.32),
			hot_color,
			hot_start,
			preserve,
			centered,
			value
		)
		if show_pixel_border:
			draw_rect(rect, border_color, false, 1.0)
		if centered:
			draw_line(Vector2(ctrl_w * 0.5, 0.0), Vector2(ctrl_w * 0.5, ctrl_h), center_color, 1.5)
		return

	if eff == int(DisplayStyle.PIXEL_SOLID):
		draw_rect(rect, bg_color, true)
		_draw_pixel_segments(rect)
		if show_pixel_border:
			draw_rect(rect, border_color, false, 1.0)
		if centered:
			draw_line(Vector2(ctrl_w * 0.5, 0.0), Vector2(ctrl_w * 0.5, ctrl_h), center_color, 1.5)
		return

	draw_style_box(_trough_style(), rect)

	var fill := clampf(absf(value), 0.0, 1.0)
	if fill > 0.005:
		var fill_rect: Rect2
		if centered:
			var half_w := ctrl_w * 0.5
			var w := half_w * fill
			if value >= 0.0:
				fill_rect = Rect2(half_w, 0.0, w, ctrl_h)
			else:
				fill_rect = Rect2(half_w - w, 0.0, w, ctrl_h)
		else:
			fill_rect = Rect2(0.0, 0.0, ctrl_w * fill, ctrl_h)
		draw_style_box(_fill_style(), fill_rect)

	if centered:
		draw_line(
			Vector2(ctrl_w * 0.5, 0.0),
			Vector2(ctrl_w * 0.5, ctrl_h),
			center_color, 1.5
		)


func _draw_pixel_segments(rect: Rect2) -> void:
	var count := maxi(4, pixel_segments)
	var gap := 2.0
	var inner_w := maxf(4.0, rect.size.x - 4.0)
	var seg_w := maxf(2.0, (inner_w - gap * float(count - 1)) / float(count))
	var seg_h := maxf(2.0, rect.size.y - 2.0)
	var dim_col := Color(bar_color.r * 0.35, bar_color.g * 0.35, bar_color.b * 0.35, 0.25)
	var center_idx := (count - 1) * 0.5
	var clamped := clampf(absf(value), 0.0, 1.0)
	for i in range(count):
		var sx := rect.position.x + 2.0 + float(i) * (seg_w + gap)
		var is_lit := false
		if centered:
			var signed_v := clampf(value, -1.0, 1.0)
			if absf(signed_v) <= 0.02:
				is_lit = absi(i - int(round(center_idx))) == 0
			elif signed_v > 0.0:
				is_lit = float(i) >= center_idx and float(i) <= center_idx + signed_v * center_idx + 0.05
			else:
				is_lit = float(i) <= center_idx and float(i) >= center_idx + signed_v * center_idx - 0.05
		else:
			is_lit = clamped >= (float(i) + 0.25) / float(count)
		var col := bar_color if is_lit else dim_col
		draw_rect(Rect2(sx, rect.position.y + 1.0, seg_w, seg_h), col, true)
