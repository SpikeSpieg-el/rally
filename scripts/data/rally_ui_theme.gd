## Палитра и типографика всех меню и HUD.
##
## Меню больше не «зашивают» цвета и размеры шрифтов в коде: каждый экран
## берёт их отсюда (файл res://data/ui/default_ui_theme.tres). Хотите другой
## акцент, крупнее заголовки, ярче выбранный пункт — правьте ресурс в
## инспекторе, код трогать не нужно.
##
## Экран может переопределить тему своим полем `ui_theme` (у MainMenu,
## GarageMenu, InputSettings и оверлеев HUD такие поля есть); меню при этом
## ещё и собирает из неё native-тему Godot, чтобы стили достались всем
## вложенным контролам.
@tool
class_name RallyUiTheme
extends Resource

@export_group("Общие цвета")
@export var background: Color = Color(0.018, 0.031, 0.046, 1.0)
@export var panel_background: Color = Color(0.035, 0.055, 0.075, 0.99)
@export var accent: Color = Color(1.0, 0.58, 0.08, 1.0)
@export var accent_soft: Color = Color(1.0, 0.62, 0.12, 1.0)
@export var accent_alt: Color = Color(1.0, 0.75, 0.25, 1.0)
@export var text_primary: Color = Color(0.86, 0.90, 0.94, 1.0)
@export var text_secondary: Color = Color(0.62, 0.76, 0.86, 1.0)
@export var text_muted: Color = Color(0.55, 0.68, 0.78, 1.0)
@export var text_value: Color = Color(1.0, 0.68, 0.28, 1.0)
@export var border: Color = Color(0.28, 0.38, 0.46, 1.0)
@export var border_accent: Color = Color(0.95, 0.47, 0.11, 1.0)
@export var overlay_backdrop: Color = Color(0.005, 0.009, 0.015, 0.88)
@export var selection_color: Color = Color(1.0, 0.62, 0.12, 1.0)
@export var idle_color: Color = Color(0.86, 0.90, 0.94, 1.0)
@export var condition_selected_color: Color = Color(1.0, 0.75, 0.25, 1.0)
@export var condition_idle_color: Color = Color(0.82, 0.86, 0.90, 1.0)

@export_group("Шрифты (px)")
@export_range(8, 96, 1) var font_title: int = 52
@export_range(8, 96, 1) var font_subtitle: int = 20
@export_range(8, 96, 1) var font_section: int = 18
@export_range(8, 96, 1) var font_group: int = 15
@export_range(8, 96, 1) var font_button: int = 17
@export_range(8, 96, 1) var font_button_small: int = 15
@export_range(8, 96, 1) var font_chip: int = 13
@export_range(8, 96, 1) var font_caption: int = 11
@export_range(8, 96, 1) var font_overlay_title: int = 28
@export_range(8, 96, 1) var font_overlay_label: int = 16
@export_range(8, 96, 1) var font_overlay_note: int = 14
@export_range(8, 96, 1) var font_hud_label: int = 13
@export_range(8, 96, 1) var font_hud_value: int = 15
@export_range(8, 96, 1) var font_hud_small: int = 12

@export_group("Размеры и отступы (px)")
@export_range(0, 80, 1) var accent_bar_height: int = 7
@export_range(0, 200, 1) var content_margin_horizontal: int = 36
@export_range(0, 200, 1) var content_margin_vertical: int = 26
@export_range(0, 200, 1) var content_margin_bottom: int = 22
@export_range(0, 64, 1) var block_separation: int = 12
@export_range(0, 64, 1) var item_separation: int = 8
@export_range(0, 64, 1) var chip_separation: int = 4
@export_range(0, 200, 1) var track_button_height: int = 38
@export_range(0, 200, 1) var setup_button_height: int = 34
@export_range(0, 200, 1) var chip_height: int = 28
@export_range(0, 400, 1) var seed_field_width: int = 104
@export_range(0, 400, 1) var overlay_min_width: int = 920
@export_range(0, 600, 1) var overlay_min_height: int = 820
@export_range(0, 400, 1) var overlay_button_width: int = 200
@export_range(0, 400, 1) var overlay_button_height: int = 44
@export_range(0, 400, 1) var overlay_reset_button_width: int = 230
@export_range(0, 400, 1) var overlay_close_button_width: int = 180
@export_range(0, 200, 1) var overlay_margin_left: int = 12
@export_range(0, 200, 1) var overlay_margin_right: int = 24
@export_range(0, 200, 1) var overlay_margin_vertical: int = 14
@export_range(0, 200, 1) var overlay_separation: int = 10
@export_range(0, 200, 1) var row_separation: int = 8
@export_range(0, 200, 1) var binding_button_width: int = 170
@export_range(0, 200, 1) var binding_button_height: int = 38
@export_range(0, 200, 1) var garage_slider_height: int = 26
@export_range(0, 200, 1) var garage_picker_width: int = 140
@export_range(0, 200, 1) var garage_picker_height: int = 36
@export_range(0, 400, 1) var garage_choice_width: int = 215
@export_range(0, 200, 1) var garage_note_size: int = 13
@export_range(0, 64, 1) var garage_group_separation: int = 11
@export_range(0, 200, 1) var controller_row_height: int = 24
@export_range(0, 400, 1) var controller_label_width: int = 175
@export_range(0, 200, 1) var controller_value_width: int = 48
@export_range(0, 200, 1) var controller_button_width: int = 86
@export_range(0, 200, 1) var controller_button_height: int = 28
@export_range(0, 200, 1) var controller_lightbar_height: int = 30
@export_range(0, 64, 1) var controller_separation: int = 4

@export_group("Стили кнопок и панелей")
@export_range(0, 40, 1) var button_margin_horizontal: int = 12
@export_range(0, 40, 1) var button_margin_vertical: int = 6
@export_range(0, 40, 1) var start_button_margin_horizontal: int = 16
@export_range(0, 40, 1) var start_button_margin_vertical: int = 12
@export_range(0, 20, 1) var border_width: int = 1
@export_range(0, 20, 1) var border_width_strong: int = 2
@export_range(0, 40, 1) var corner_radius: int = 6
@export var button_color: Color = Color(0.09, 0.125, 0.16, 1.0)
@export var button_hover_color: Color = Color(0.2, 0.26, 0.32, 1.0)
@export var start_button_color: Color = Color(0.92, 0.42, 0.04, 1.0)
@export var start_button_border: Color = Color(1.0, 0.82, 0.28, 1.0)
@export var hud_panel_color: Color = Color(0.03, 0.05, 0.07, 0.72)
@export var hud_border_color: Color = Color(1.0, 1.0, 1.0, 0.12)


## Готовый StyleBoxFlat для обычной кнопки.
func button_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.content_margin_left = float(button_margin_horizontal)
	style.content_margin_right = float(button_margin_horizontal)
	style.content_margin_top = float(button_margin_vertical)
	style.content_margin_bottom = float(button_margin_vertical)
	style.bg_color = button_color
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	return style


## StyleBoxFlat «наведение/фокус» — акцентная рамка.
func button_hover_style() -> StyleBoxFlat:
	var style := button_style()
	style.bg_color = button_hover_color
	style.border_color = accent_soft
	return style


## StyleBoxFlat кнопки «СТАРТ».
func start_button_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.content_margin_left = float(start_button_margin_horizontal)
	style.content_margin_right = float(start_button_margin_horizontal)
	style.content_margin_top = float(start_button_margin_vertical)
	style.content_margin_bottom = float(start_button_margin_vertical)
	style.bg_color = start_button_color
	style.border_color = start_button_border
	style.set_border_width_all(border_width_strong)
	style.set_corner_radius_all(corner_radius)
	return style


## StyleBoxFlat панели HUD/оверлея.
func panel_style(fill: Color = Color(0, 0, 0, 0), line: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = hud_panel_color if fill.a <= 0.0 else fill
	style.border_color = hud_border_color if line.a <= 0.0 else line
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	return style


## Применить палитру к теме Godot: базовые цвета/размеры подхватят все
## дочерние контролы, у которых нет собственных override.
func apply_to(theme: Theme) -> void:
	if theme == null:
		return
	theme.set_color("font_color", "Label", text_primary)
	theme.set_color("font_color", "Button", text_primary)
	theme.set_color("font_hover_color", "Button", accent_alt)
	theme.set_color("font_focus_color", "Button", accent_alt)
	theme.set_color("font_color", "CheckBox", text_primary)
	theme.set_color("font_color", "CheckButton", text_primary)
	theme.set_color("font_color", "OptionButton", text_primary)
	theme.set_font_size("font_size", "Label", font_group)
	theme.set_font_size("font_size", "Button", font_button_small)
	theme.set_stylebox("normal", "Button", button_style())
	theme.set_stylebox("hover", "Button", button_hover_style())
	theme.set_stylebox("pressed", "Button", start_button_style())
	theme.set_stylebox("focus", "Button", button_hover_style())
