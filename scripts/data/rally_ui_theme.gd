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
##
## Крупность для телефона/браузера. Разрешение телефона высокое, а канва
## проекта — 1080 px по короткой стороне, поэтому «нормальные» для ПК 15–17 px
## на ладони читаются как подпись под микроскопом. Множители (см.
## `RallyScreenLayout`) берутся здесь, а НЕ через `scale` узлов и не через
## уменьшение разрешения канвы: растянутая канва мылит шрифты, крупные
## шрифты остаются резкими при любом DPI.
@tool
class_name RallyUiTheme
extends Resource

const LayoutType = preload("res://scripts/ui/rally_screen_layout.gd")

## Множитель крупности UI для телефона/браузера. 1.0 — размеры как в этом
## ресурсе (ПК). Меню выставляют значение из RallyScreenLayout в `_ready()`
## ДО сборки кнопок, поэтому все чтения `font_*`/`*_height` уже возвращают
## крупные числа. Это множитель чисел, а не `Control.scale`: текст остаётся
## резким, просто нарисован крупнее.
var ui_scale: float = 1.0

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
@export_range(8, 96, 1) var _font_title: int = 52
@export_range(8, 96, 1) var _font_subtitle: int = 20
@export_range(8, 96, 1) var _font_section: int = 18
@export_range(8, 96, 1) var _font_group: int = 15
@export_range(8, 96, 1) var _font_button: int = 17
@export_range(8, 96, 1) var _font_button_small: int = 15
@export_range(8, 96, 1) var _font_chip: int = 13
@export_range(8, 96, 1) var _font_caption: int = 11
@export_range(8, 96, 1) var _font_overlay_title: int = 28
@export_range(8, 96, 1) var _font_overlay_label: int = 16
@export_range(8, 96, 1) var _font_overlay_note: int = 14
@export_range(8, 96, 1) var _font_hud_label: int = 13
@export_range(8, 96, 1) var _font_hud_value: int = 15
@export_range(8, 96, 1) var _font_hud_small: int = 12

@export_group("Размеры и отступы (px)")
@export_range(0, 80, 1) var _accent_bar_height: int = 7
@export_range(0, 200, 1) var _content_margin_horizontal: int = 36
@export_range(0, 200, 1) var _content_margin_vertical: int = 26
@export_range(0, 200, 1) var _content_margin_bottom: int = 22
@export_range(0, 64, 1) var _block_separation: int = 12
@export_range(0, 64, 1) var _item_separation: int = 8
@export_range(0, 64, 1) var _chip_separation: int = 4
@export_range(0, 200, 1) var _track_button_height: int = 38
@export_range(0, 200, 1) var _setup_button_height: int = 34
@export_range(0, 200, 1) var _chip_height: int = 28
@export_range(0, 400, 1) var _seed_field_width: int = 104
@export_range(0, 1920, 1) var _overlay_min_width: int = 920
@export_range(0, 1080, 1) var _overlay_min_height: int = 820
@export_range(0, 400, 1) var _overlay_button_width: int = 200
@export_range(0, 400, 1) var _overlay_button_height: int = 44
@export_range(0, 400, 1) var _overlay_reset_button_width: int = 230
@export_range(0, 400, 1) var _overlay_close_button_width: int = 180
@export_range(0, 200, 1) var _overlay_margin_left: int = 12
@export_range(0, 200, 1) var _overlay_margin_right: int = 24
@export_range(0, 200, 1) var _overlay_margin_vertical: int = 14
@export_range(0, 200, 1) var _overlay_separation: int = 10
@export_range(0, 200, 1) var _row_separation: int = 8
@export_range(0, 200, 1) var _binding_button_width: int = 170
@export_range(0, 200, 1) var _binding_button_height: int = 38
@export_range(0, 200, 1) var _garage_slider_height: int = 26
@export_range(0, 200, 1) var _garage_picker_width: int = 140
@export_range(0, 200, 1) var _garage_picker_height: int = 36
@export_range(0, 400, 1) var _garage_choice_width: int = 215
@export_range(0, 200, 1) var _garage_note_size: int = 13
@export_range(0, 64, 1) var _garage_group_separation: int = 11
@export_range(0, 200, 1) var _controller_row_height: int = 24
@export_range(0, 400, 1) var _controller_label_width: int = 175
@export_range(0, 200, 1) var _controller_value_width: int = 48
@export_range(0, 200, 1) var _controller_button_width: int = 86
@export_range(0, 200, 1) var _controller_button_height: int = 28
@export_range(0, 200, 1) var _controller_lightbar_height: int = 30
@export_range(0, 64, 1) var _controller_separation: int = 4

@export_group("Стили кнопок и панелей")
@export_range(0, 40, 1) var _button_margin_horizontal: int = 12
@export_range(0, 40, 1) var _button_margin_vertical: int = 6
@export_range(0, 40, 1) var _start_button_margin_horizontal: int = 16
@export_range(0, 40, 1) var _start_button_margin_vertical: int = 12
@export_range(0, 20, 1) var _border_width: int = 1
@export_range(0, 20, 1) var _border_width_strong: int = 2
@export_range(0, 40, 1) var _corner_radius: int = 6
@export var button_color: Color = Color(0.09, 0.125, 0.16, 1.0)
@export var button_hover_color: Color = Color(0.2, 0.26, 0.32, 1.0)
@export var start_button_color: Color = Color(0.92, 0.42, 0.04, 1.0)
@export var start_button_border: Color = Color(1.0, 0.82, 0.28, 1.0)
@export var hud_panel_color: Color = Color(0.03, 0.05, 0.07, 0.72)
@export var hud_border_color: Color = Color(1.0, 1.0, 1.0, 0.12)




# --- Доступ с учётом крупности: меню читают `font_*`/`*_height`, ---
# --- а «базовые» числа остаются в `_font_*`/`_..._height` для инспектора. ---

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var font_title: int:
	get:
		return maxi(1, roundi(float(_font_title) * ui_scale))
	set(value):
		_font_title = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var font_subtitle: int:
	get:
		return maxi(1, roundi(float(_font_subtitle) * ui_scale))
	set(value):
		_font_subtitle = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var font_section: int:
	get:
		return maxi(1, roundi(float(_font_section) * ui_scale))
	set(value):
		_font_section = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var font_group: int:
	get:
		return maxi(1, roundi(float(_font_group) * ui_scale))
	set(value):
		_font_group = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var font_button: int:
	get:
		return maxi(1, roundi(float(_font_button) * ui_scale))
	set(value):
		_font_button = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var font_button_small: int:
	get:
		return maxi(1, roundi(float(_font_button_small) * ui_scale))
	set(value):
		_font_button_small = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var font_chip: int:
	get:
		return maxi(1, roundi(float(_font_chip) * ui_scale))
	set(value):
		_font_chip = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var font_caption: int:
	get:
		return maxi(1, roundi(float(_font_caption) * ui_scale))
	set(value):
		_font_caption = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var font_overlay_title: int:
	get:
		return maxi(1, roundi(float(_font_overlay_title) * ui_scale))
	set(value):
		_font_overlay_title = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var font_overlay_label: int:
	get:
		return maxi(1, roundi(float(_font_overlay_label) * ui_scale))
	set(value):
		_font_overlay_label = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var font_overlay_note: int:
	get:
		return maxi(1, roundi(float(_font_overlay_note) * ui_scale))
	set(value):
		_font_overlay_note = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var font_hud_label: int:
	get:
		return maxi(1, roundi(float(_font_hud_label) * ui_scale))
	set(value):
		_font_hud_label = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var font_hud_value: int:
	get:
		return maxi(1, roundi(float(_font_hud_value) * ui_scale))
	set(value):
		_font_hud_value = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var font_hud_small: int:
	get:
		return maxi(1, roundi(float(_font_hud_small) * ui_scale))
	set(value):
		_font_hud_small = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var accent_bar_height: int:
	get:
		return maxi(1, roundi(float(_accent_bar_height) * ui_scale))
	set(value):
		_accent_bar_height = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var content_margin_horizontal: int:
	get:
		return maxi(1, roundi(float(_content_margin_horizontal) * ui_scale))
	set(value):
		_content_margin_horizontal = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var content_margin_vertical: int:
	get:
		return maxi(1, roundi(float(_content_margin_vertical) * ui_scale))
	set(value):
		_content_margin_vertical = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var content_margin_bottom: int:
	get:
		return maxi(1, roundi(float(_content_margin_bottom) * ui_scale))
	set(value):
		_content_margin_bottom = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var block_separation: int:
	get:
		return maxi(1, roundi(float(_block_separation) * ui_scale))
	set(value):
		_block_separation = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var item_separation: int:
	get:
		return maxi(1, roundi(float(_item_separation) * ui_scale))
	set(value):
		_item_separation = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var chip_separation: int:
	get:
		return maxi(1, roundi(float(_chip_separation) * ui_scale))
	set(value):
		_chip_separation = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var track_button_height: int:
	get:
		return maxi(1, roundi(float(_track_button_height) * ui_scale))
	set(value):
		_track_button_height = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var setup_button_height: int:
	get:
		return maxi(1, roundi(float(_setup_button_height) * ui_scale))
	set(value):
		_setup_button_height = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var chip_height: int:
	get:
		return maxi(1, roundi(float(_chip_height) * ui_scale))
	set(value):
		_chip_height = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var seed_field_width: int:
	get:
		return maxi(1, roundi(float(_seed_field_width) * ui_scale))
	set(value):
		_seed_field_width = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var overlay_min_width: int:
	get:
		return maxi(1, roundi(float(_overlay_min_width) * ui_scale))
	set(value):
		_overlay_min_width = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var overlay_min_height: int:
	get:
		return maxi(1, roundi(float(_overlay_min_height) * ui_scale))
	set(value):
		_overlay_min_height = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var overlay_button_width: int:
	get:
		return maxi(1, roundi(float(_overlay_button_width) * ui_scale))
	set(value):
		_overlay_button_width = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var overlay_button_height: int:
	get:
		return maxi(1, roundi(float(_overlay_button_height) * ui_scale))
	set(value):
		_overlay_button_height = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var overlay_reset_button_width: int:
	get:
		return maxi(1, roundi(float(_overlay_reset_button_width) * ui_scale))
	set(value):
		_overlay_reset_button_width = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var overlay_close_button_width: int:
	get:
		return maxi(1, roundi(float(_overlay_close_button_width) * ui_scale))
	set(value):
		_overlay_close_button_width = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var overlay_margin_left: int:
	get:
		return maxi(1, roundi(float(_overlay_margin_left) * ui_scale))
	set(value):
		_overlay_margin_left = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var overlay_margin_right: int:
	get:
		return maxi(1, roundi(float(_overlay_margin_right) * ui_scale))
	set(value):
		_overlay_margin_right = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var overlay_margin_vertical: int:
	get:
		return maxi(1, roundi(float(_overlay_margin_vertical) * ui_scale))
	set(value):
		_overlay_margin_vertical = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var overlay_separation: int:
	get:
		return maxi(1, roundi(float(_overlay_separation) * ui_scale))
	set(value):
		_overlay_separation = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var row_separation: int:
	get:
		return maxi(1, roundi(float(_row_separation) * ui_scale))
	set(value):
		_row_separation = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var binding_button_width: int:
	get:
		return maxi(1, roundi(float(_binding_button_width) * ui_scale))
	set(value):
		_binding_button_width = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var binding_button_height: int:
	get:
		return maxi(1, roundi(float(_binding_button_height) * ui_scale))
	set(value):
		_binding_button_height = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var garage_slider_height: int:
	get:
		return maxi(1, roundi(float(_garage_slider_height) * ui_scale))
	set(value):
		_garage_slider_height = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var garage_picker_width: int:
	get:
		return maxi(1, roundi(float(_garage_picker_width) * ui_scale))
	set(value):
		_garage_picker_width = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var garage_picker_height: int:
	get:
		return maxi(1, roundi(float(_garage_picker_height) * ui_scale))
	set(value):
		_garage_picker_height = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var garage_choice_width: int:
	get:
		return maxi(1, roundi(float(_garage_choice_width) * ui_scale))
	set(value):
		_garage_choice_width = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var garage_note_size: int:
	get:
		return maxi(1, roundi(float(_garage_note_size) * ui_scale))
	set(value):
		_garage_note_size = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var garage_group_separation: int:
	get:
		return maxi(1, roundi(float(_garage_group_separation) * ui_scale))
	set(value):
		_garage_group_separation = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var controller_row_height: int:
	get:
		return maxi(1, roundi(float(_controller_row_height) * ui_scale))
	set(value):
		_controller_row_height = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var controller_label_width: int:
	get:
		return maxi(1, roundi(float(_controller_label_width) * ui_scale))
	set(value):
		_controller_label_width = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var controller_value_width: int:
	get:
		return maxi(1, roundi(float(_controller_value_width) * ui_scale))
	set(value):
		_controller_value_width = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var controller_button_width: int:
	get:
		return maxi(1, roundi(float(_controller_button_width) * ui_scale))
	set(value):
		_controller_button_width = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var controller_button_height: int:
	get:
		return maxi(1, roundi(float(_controller_button_height) * ui_scale))
	set(value):
		_controller_button_height = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var controller_lightbar_height: int:
	get:
		return maxi(1, roundi(float(_controller_lightbar_height) * ui_scale))
	set(value):
		_controller_lightbar_height = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var controller_separation: int:
	get:
		return maxi(1, roundi(float(_controller_separation) * ui_scale))
	set(value):
		_controller_separation = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var button_margin_horizontal: int:
	get:
		return maxi(1, roundi(float(_button_margin_horizontal) * ui_scale))
	set(value):
		_button_margin_horizontal = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var button_margin_vertical: int:
	get:
		return maxi(1, roundi(float(_button_margin_vertical) * ui_scale))
	set(value):
		_button_margin_vertical = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var start_button_margin_horizontal: int:
	get:
		return maxi(1, roundi(float(_start_button_margin_horizontal) * ui_scale))
	set(value):
		_start_button_margin_horizontal = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var start_button_margin_vertical: int:
	get:
		return maxi(1, roundi(float(_start_button_margin_vertical) * ui_scale))
	set(value):
		_start_button_margin_vertical = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var border_width: int:
	get:
		return maxi(1, roundi(float(_border_width) * ui_scale))
	set(value):
		_border_width = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var border_width_strong: int:
	get:
		return maxi(1, roundi(float(_border_width_strong) * ui_scale))
	set(value):
		_border_width_strong = value

## Крупность UI: размер в «базовых» px × `ui_scale` (1.0 на ПК).
var corner_radius: int:
	get:
		return maxi(1, roundi(float(_corner_radius) * ui_scale))
	set(value):
		_corner_radius = value

## Размер шрифта с учётом крупности: удобно для мест, где размер приходит
## числом из .tscn (титульный экран), а не полем темы.
func scaled_font(base_size: int) -> int:
	return maxi(1, roundi(float(base_size) * ui_scale))


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
