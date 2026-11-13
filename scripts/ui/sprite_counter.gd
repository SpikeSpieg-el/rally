## Универсальный пиксельный счётчик на базе цифр из спрайт-листа спидометра.
##
## Используется для таймера заезда (00:00.000), сплит-дельт, счётчика FPS,
## номеров чекпоинтов и прочих цифровых индикаторов HUD в едином стиле со
## SpriteSpeedometer. При отсутствии атласа отображает чистый резервный текст.
@tool
class_name SpriteCounter
extends Control

@export var hud_style: RallyHudStyle:
	set(v):
		if hud_style != null and hud_style.changed.is_connected(_on_hud_style_changed):
			hud_style.changed.disconnect(_on_hud_style_changed)
		hud_style = v
		if hud_style != null and not hud_style.changed.is_connected(_on_hud_style_changed):
			hud_style.changed.connect(_on_hud_style_changed)
		_apply_hud_style()
		rebuild_atlas()
		queue_redraw()

@export var text: String = "00:00.000":
	set(v):
		if text == v:
			return
		text = v
		queue_redraw()

@export var use_small_digits: bool = false:
	set(v):
		use_small_digits = v
		queue_redraw()

@export var dim_leading_zeros: bool = false:
	set(v):
		dim_leading_zeros = v
		queue_redraw()

@export_range(0.0, 1.0, 0.02) var leading_zero_alpha: float = 0.24:
	set(v):
		leading_zero_alpha = v
		queue_redraw()

@export var tint_color: Color = Color(0.95, 0.98, 1.0, 1.0):
	set(v):
		tint_color = v
		queue_redraw()

@export var separator_color: Color = Color(1.0, 0.55, 0.16, 1.0):
	set(v):
		separator_color = v
		queue_redraw()

@export var alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER:
	set(v):
		alignment = v
		queue_redraw()

@export_range(8.0, 96.0, 1.0) var digit_height_px: float = 28.0:
	set(v):
		digit_height_px = v
		queue_redraw()

@export var auto_fit_height: bool = true:
	set(v):
		auto_fit_height = v
		queue_redraw()

@export_range(0.45, 0.9, 0.01) var digit_slot_aspect: float = 0.64:
	set(v):
		digit_slot_aspect = v
		queue_redraw()

@export_range(0.0, 12.0, 0.5) var digit_gap_px: float = 2.0:
	set(v):
		digit_gap_px = v
		queue_redraw()

@export var sprite_sheet: Texture2D:
	set(v):
		sprite_sheet = v
		rebuild_atlas()
		queue_redraw()

@export var bg_keyout: RallyHudSpriteAtlas.KeyoutMode = RallyHudSpriteAtlas.KeyoutMode.AUTO:
	set(v):
		bg_keyout = v
		rebuild_atlas()
		queue_redraw()

@export var pixel_filter: bool = true:
	set(v):
		pixel_filter = v
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if pixel_filter else CanvasItem.TEXTURE_FILTER_LINEAR
		queue_redraw()

var _atlas: RallyHudSpriteAtlas = RallyHudSpriteAtlas.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if pixel_filter else CanvasItem.TEXTURE_FILTER_LINEAR
	_apply_hud_style()
	rebuild_atlas()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func set_hud_style(style_res: RallyHudStyle) -> void:
	hud_style = style_res


func set_value_text(new_text: String) -> void:
	text = new_text


func is_atlas_ready() -> bool:
	return _atlas != null and _atlas.ready


func rebuild_atlas() -> bool:
	if _atlas == null:
		_atlas = RallyHudSpriteAtlas.new()
	var sheet_to_use: Texture2D = sprite_sheet
	var keyout_to_use: int = int(bg_keyout)
	var pad_to_use: int = 2
	if sheet_to_use == null and hud_style != null:
		sheet_to_use = hud_style.sprite_sheet
		keyout_to_use = int(hud_style.keyout_mode)
		pad_to_use = hud_style.slice_pad_px
	return _atlas.build(sheet_to_use, keyout_to_use, pad_to_use)


func _on_hud_style_changed() -> void:
	_apply_hud_style()
	rebuild_atlas()
	queue_redraw()


func _apply_hud_style() -> void:
	if hud_style == null:
		return
	tint_color = hud_style.text_primary_color
	separator_color = hud_style.panel_accent_color
	leading_zero_alpha = hud_style.dim_zero_alpha
	digit_gap_px = hud_style.digit_gap
	digit_slot_aspect = hud_style.digit_slot_aspect
	pixel_filter = hud_style.pixel_crisp_filtering


func _draw() -> void:
	var ctrl_w := self.size.x
	var ctrl_h := self.size.y
	if ctrl_w <= 2.0 or ctrl_h <= 2.0 or text.is_empty():
		return

	var d_h := digit_height_px
	if auto_fit_height:
		d_h = clampf(ctrl_h - 4.0, 10.0, digit_height_px)

	if _atlas == null or not _atlas.ready:
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(0.0, ctrl_h * 0.78), text, alignment, ctrl_w, int(d_h * 0.9), tint_color)
		return

	var total_w := _atlas.measure_digits_width(text, d_h, use_small_digits, digit_gap_px, digit_slot_aspect)
	if total_w > ctrl_w - 4.0 and total_w > 1.0:
		d_h *= (ctrl_w - 4.0) / total_w
		total_w = _atlas.measure_digits_width(text, d_h, use_small_digits, digit_gap_px, digit_slot_aspect)

	var draw_x := 0.0
	if alignment == HORIZONTAL_ALIGNMENT_CENTER:
		draw_x = maxf(0.0, (ctrl_w - total_w) * 0.5)
	elif alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		draw_x = maxf(0.0, ctrl_w - total_w)
	var draw_y := maxf(0.0, (ctrl_h - d_h) * 0.5)

	_atlas.draw_digits(
		self,
		text,
		Vector2(draw_x, draw_y),
		d_h,
		use_small_digits,
		tint_color,
		dim_leading_zeros,
		leading_zero_alpha,
		digit_gap_px,
		digit_slot_aspect,
		separator_color
	)
