## Индикатор FPS с поддержкой общего стиля RallyHudStyle и спрайтовых цифр.
##
## Заменяет встроенный GDScript в `rally_hud.tscn`: в пиксельном режиме
## рисует число FPS мелкими цифрами из атласа спидометра, сохраняя `text`
## ("60 FPS") синхронизированным для тестов и резервного отображения.
@tool
class_name RallyFpsCounter
extends Label

@export var hud_style: RallyHudStyle:
	set(v):
		if hud_style != null and hud_style.changed.is_connected(_on_hud_style_changed):
			hud_style.changed.disconnect(_on_hud_style_changed)
		hud_style = v
		if hud_style != null and not hud_style.changed.is_connected(_on_hud_style_changed):
			hud_style.changed.connect(_on_hud_style_changed)
		_refresh_style_state()

@export var use_sprite_digits: bool = true:
	set(v):
		use_sprite_digits = v
		_refresh_style_state()

@export var fps_good_color: Color = Color(0.35, 0.95, 0.62, 0.95)
@export var fps_warn_color: Color = Color(1.0, 0.78, 0.2, 0.95)
@export var fps_low_color: Color = Color(0.95, 0.35, 0.35, 0.95)
@export var preview_fps: int = 60

var _atlas: RallyHudSpriteAtlas = RallyHudSpriteAtlas.new()
var _last_fps: int = 60
var _sprite_active: bool = false


func _ready() -> void:
	_refresh_style_state()


func set_hud_style(style_res: RallyHudStyle) -> void:
	hud_style = style_res


func _on_hud_style_changed() -> void:
	_refresh_style_state()


func _refresh_style_state() -> void:
	var want_sprite := use_sprite_digits
	if hud_style != null:
		want_sprite = want_sprite and hud_style.is_pixel_mode() and hud_style.use_sprite_digits_for_fps
		add_theme_stylebox_override("normal", hud_style.make_hint_style())
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if hud_style.pixel_crisp_filtering else CanvasItem.TEXTURE_FILTER_LINEAR
	if want_sprite:
		if _atlas == null:
			_atlas = RallyHudSpriteAtlas.new()
		var sheet: Texture2D = hud_style.sprite_sheet if hud_style != null else null
		var keyout := int(hud_style.keyout_mode) if hud_style != null else int(RallyHudSpriteAtlas.KeyoutMode.AUTO)
		var pad := hud_style.slice_pad_px if hud_style != null else 2
		_sprite_active = _atlas.build(sheet, keyout, pad)
	else:
		_sprite_active = false
	_apply_fps_color(_last_fps)
	queue_redraw()


func _process(_delta: float) -> void:
	var fps_val := preview_fps if Engine.is_editor_hint() else int(Engine.get_frames_per_second())
	if fps_val == _last_fps and not text.is_empty():
		return
	_last_fps = fps_val
	text = "%d FPS" % fps_val
	_apply_fps_color(fps_val)
	if _sprite_active:
		queue_redraw()


func _apply_fps_color(fps_val: int) -> void:
	var col := _color_for_fps(fps_val)
	if _sprite_active:
		add_theme_color_override("font_color", Color(0.0, 0.0, 0.0, 0.0))
	else:
		add_theme_color_override("font_color", col)


func _color_for_fps(fps_val: int) -> Color:
	if fps_val >= 55:
		return fps_good_color
	if fps_val >= 30:
		return fps_warn_color
	return fps_low_color


func _draw() -> void:
	if not _sprite_active or _atlas == null or not _atlas.ready:
		return
	var ctrl_w := self.size.x
	var ctrl_h := self.size.y
	if ctrl_w <= 4.0 or ctrl_h <= 4.0:
		return
	var num_str := str(_last_fps)
	var max_dh := hud_style.fps_digit_height if hud_style != null else 18.0
	var digit_h := clampf(ctrl_h - 10.0, 10.0, max_dh)
	var digits_w := _atlas.measure_digits_width(num_str, digit_h, true, 1.5, 0.64)
	var tag_font := ThemeDB.fallback_font
	var tag_w := 26.0
	var total_w := digits_w + 5.0 + tag_w
	var start_x := maxf(6.0, (ctrl_w - total_w) * 0.5)
	var col := _color_for_fps(_last_fps)
	var y_top := maxf(2.0, (ctrl_h - digit_h) * 0.5)
	_atlas.draw_digits(self, num_str, Vector2(start_x, y_top), digit_h, true, col, false, 1.0, 1.5, 0.64)
	draw_string(tag_font, Vector2(start_x + digits_w + 5.0, ctrl_h * 0.5 + 4.0), "FPS", HORIZONTAL_ALIGNMENT_LEFT, tag_w, 10, Color(0.75, 0.85, 0.94, 0.88))
