## Единый стиль HUD в эстетике пиксельного спидометра (подготовка к полному
## переделыванию всего HUD и общий пульт оформления панелей/шкал).
##
## Файл по умолчанию: res://data/ui/default_hud_style.tres.
## Пока `hud_mode == CLASSIC_GLASS` (и `RallyHud.theme_mode == KEEP_SCENE`),
## существующий стеклянно-оранжевый HUD остаётся нетронутым; переключение на
## `SPEEDOMETER_PIXEL` применяет единую палитру, пиксельные рамки и
## сегментные/спрайтовые шкалы ко всему HUD.
@tool
class_name RallyHudStyle
extends Resource

const DEFAULT_STYLE_PATH := "res://data/ui/default_hud_style.tres"
const DEFAULT_SPRITE_SHEET_PATH := "res://scenes/ui/ui_hud_r1_ru.png"

enum HudMode {
	CLASSIC_GLASS = 0,
	SPEEDOMETER_PIXEL = 1,
}

enum KeyoutMode {
	AUTO = 0,
	NONE = 1,
	WHITE_BG = 2,
	DARK_BG = 3,
}

enum GaugeStyleMode {
	VECTOR = 0,
	PIXEL_SEGMENTED = 1,
	SPRITE_STEPPED = 2,
	SPRITE_BLOCKS = 3,
	SPRITE_WIDE = 4,
}

@export_group("Стиль и спрайт-лист")
## Общий режим оформления HUD (стекло по умолчанию или пиксельный стиль спидометра).
@export var hud_mode: HudMode = HudMode.CLASSIC_GLASS:
	set(value):
		hud_mode = value
		emit_changed()
## Общий спрайт-лист для спидометра, шкал телеметрии и цифровых счётчиков HUD.
@export var sprite_sheet: Texture2D = null:
	set(value):
		sprite_sheet = value
		emit_changed()
## Режим удаления фона спрайт-листа (AUTO понимает прозрачный PNG, белый и тёмный JPG).
@export var keyout_mode: KeyoutMode = KeyoutMode.AUTO:
	set(value):
		keyout_mode = value
		emit_changed()
## Пиксельная фильтрация спрайтов без мыла.
@export var pixel_crisp_filtering: bool = true:
	set(value):
		pixel_crisp_filtering = value
		emit_changed()
## Запас (в px) вокруг вырезанных глифов и сегментов при нарезке листа.
@export_range(0, 8, 1) var slice_pad_px: int = 2:
	set(value):
		slice_pad_px = value
		emit_changed()

@export_group("Палитра и рамки панелей")
@export var panel_bg_color: Color = Color(0.03, 0.04, 0.06, 0.88):
	set(value):
		panel_bg_color = value
		emit_changed()
@export var panel_border_color: Color = Color(0.92, 0.94, 0.98, 0.85):
	set(value):
		panel_border_color = value
		emit_changed()
@export var panel_accent_color: Color = Color(1.0, 0.45, 0.05, 1.0):
	set(value):
		panel_accent_color = value
		emit_changed()
@export var accent_warm_color: Color = Color(1.0, 0.78, 0.22, 1.0):
	set(value):
		accent_warm_color = value
		emit_changed()
@export var accent_hot_color: Color = Color(1.0, 0.14, 0.06, 1.0):
	set(value):
		accent_hot_color = value
		emit_changed()
@export var text_primary_color: Color = Color(1.0, 1.0, 1.0, 1.0):
	set(value):
		text_primary_color = value
		emit_changed()
@export var text_secondary_color: Color = Color(0.80, 0.88, 0.96, 0.90):
	set(value):
		text_secondary_color = value
		emit_changed()
@export var outline_color: Color = Color(0.0, 0.0, 0.0, 0.92):
	set(value):
		outline_color = value
		emit_changed()
@export_range(0.0, 1.0, 0.02) var dim_zero_alpha: float = 0.16:
	set(value):
		dim_zero_alpha = value
		emit_changed()
@export_range(0, 8, 1) var border_width: int = 2:
	set(value):
		border_width = value
		emit_changed()
@export_range(0, 12, 1) var accent_border_width: int = 4:
	set(value):
		accent_border_width = value
		emit_changed()
@export_range(0, 24, 1) var corner_radius: int = 2:
	set(value):
		corner_radius = value
		emit_changed()
@export var panel_skew: Vector2 = Vector2.ZERO:
	set(value):
		panel_skew = value
		emit_changed()
@export var content_margin: Vector2 = Vector2(14.0, 8.0):
	set(value):
		content_margin = value
		emit_changed()
@export var shadow_color: Color = Color(0.0, 0.0, 0.0, 0.55):
	set(value):
		shadow_color = value
		emit_changed()
@export_range(0, 32, 1) var shadow_size: int = 6:
	set(value):
		shadow_size = value
		emit_changed()

@export_group("Шкалы телеметрии")
@export var gauge_style_mode: GaugeStyleMode = GaugeStyleMode.PIXEL_SEGMENTED:
	set(value):
		gauge_style_mode = value
		emit_changed()
@export_range(3, 24, 1) var gauge_segments: int = 11:
	set(value):
		gauge_segments = value
		emit_changed()
@export_range(0.0, 10.0, 0.5) var gauge_segment_gap: float = 2.0:
	set(value):
		gauge_segment_gap = value
		emit_changed()
@export var gauge_inactive_color: Color = Color(0.20, 0.24, 0.30, 0.58):
	set(value):
		gauge_inactive_color = value
		emit_changed()
@export var gauge_preserve_sprite_colors: bool = false:
	set(value):
		gauge_preserve_sprite_colors = value
		emit_changed()

@export_group("Спрайтовые счётчики HUD")
@export var use_sprite_digits_for_timer: bool = false:
	set(value):
		use_sprite_digits_for_timer = value
		emit_changed()
@export var use_sprite_digits_for_fps: bool = false:
	set(value):
		use_sprite_digits_for_fps = value
		emit_changed()
@export_range(10.0, 64.0, 1.0) var timer_digit_height: float = 34.0:
	set(value):
		timer_digit_height = value
		emit_changed()
@export_range(8.0, 40.0, 1.0) var fps_digit_height: float = 16.0:
	set(value):
		fps_digit_height = value
		emit_changed()
@export_range(0.0, 12.0, 0.5) var digit_gap: float = 2.0:
	set(value):
		digit_gap = value
		emit_changed()
@export_range(0.4, 1.2, 0.02) var digit_slot_aspect: float = 0.66:
	set(value):
		digit_slot_aspect = value
		emit_changed()


static func load_default() -> Resource:
	if ResourceLoader.exists(DEFAULT_STYLE_PATH):
		var loaded: Resource = ResourceLoader.load(DEFAULT_STYLE_PATH)
		if loaded != null:
			return loaded
	return load("res://scripts/data/rally_hud_style.gd").new()


func is_pixel_mode() -> bool:
	return hud_mode == HudMode.SPEEDOMETER_PIXEL


func effective_sprite_sheet() -> Texture2D:
	if sprite_sheet != null:
		return sprite_sheet
	if ResourceLoader.exists(DEFAULT_SPRITE_SHEET_PATH):
		return ResourceLoader.load(DEFAULT_SPRITE_SHEET_PATH) as Texture2D
	return null


func make_panel_style(left_accent: bool = false, top_accent: bool = false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.content_margin_left = content_margin.x
	box.content_margin_right = content_margin.x
	box.content_margin_top = content_margin.y
	box.content_margin_bottom = content_margin.y
	box.bg_color = panel_bg_color
	box.skew = panel_skew
	box.border_color = panel_accent_color if (left_accent or top_accent) else panel_border_color
	box.set_border_width_all(border_width)
	if left_accent:
		box.border_width_left = maxi(border_width, accent_border_width)
	if top_accent:
		box.border_width_top = maxi(border_width, accent_border_width)
	box.set_corner_radius_all(corner_radius)
	box.shadow_color = shadow_color
	box.shadow_size = shadow_size
	box.shadow_offset = Vector2(0.0, 3.0)
	return box


func make_hint_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 6.0
	box.content_margin_bottom = 6.0
	box.bg_color = Color(panel_bg_color.r, panel_bg_color.g, panel_bg_color.b, minf(panel_bg_color.a, 0.82))
	box.border_color = Color(panel_border_color.r, panel_border_color.g, panel_border_color.b, 0.45)
	box.set_border_width_all(maxi(1, border_width - 1))
	box.set_corner_radius_all(corner_radius)
	return box


func make_button_style(state: String) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.content_margin_left = 18.0
	box.content_margin_right = 18.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	box.skew = panel_skew
	box.set_corner_radius_all(corner_radius)
	match state:
		"hover":
			box.bg_color = panel_accent_color
			box.border_color = accent_warm_color
			box.set_border_width_all(border_width)
			box.border_width_left = maxi(border_width, accent_border_width)
		"pressed":
			box.bg_color = panel_accent_color.darkened(0.18)
			box.border_color = text_primary_color
			box.set_border_width_all(border_width)
		"focus":
			box.draw_center = false
			box.border_color = accent_warm_color
			box.set_border_width_all(border_width)
		_:
			box.bg_color = Color(panel_bg_color.r * 2.2, panel_bg_color.g * 2.2, panel_bg_color.b * 2.2, 0.94)
			box.border_color = panel_border_color
			box.set_border_width_all(border_width)
			box.border_width_left = maxi(border_width, accent_border_width)
	return box
