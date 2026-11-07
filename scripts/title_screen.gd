## Первый экран перед выбором трассы.
extends Control

const InputSettings = preload("res://scripts/ui/input_settings.gd")
const TRACK_MENU := "res://scenes/main_menu.tscn"

var input_settings = null
var start_button: Button


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	start_button.grab_focus()


func _build_ui() -> void:
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient := ShaderMaterial.new()
	gradient.shader = load("res://shaders/title_gradient.gdshader")
	shade.material = gradient
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.name = "Menu"
	margin.anchor_right = 0.46
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 90)
	margin.add_theme_constant_override("margin_top", 62)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_bottom", 54)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	margin.add_child(column)
	column.add_child(_label("R / 47     •     RALLY EXPERIENCE", 15, Color(0.94, 0.62, 0.28)))
	var top_space := Control.new()
	top_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_space.size_flags_stretch_ratio = 0.65
	column.add_child(top_space)
	column.add_child(_label("ЗЕМЛЯ ПОД КОЛЁСАМИ", 16, Color(0.91, 0.68, 0.39)))
	var title := _label("RALLY", 98, Color(0.96, 0.96, 0.91))
	column.add_child(title)
	column.add_child(_label("КАЖДЫЙ ПОВОРОТ ИМЕЕТ ЗНАЧЕНИЕ", 15, Color(0.74, 0.79, 0.74)))
	var gap := Control.new()
	gap.custom_minimum_size.y = 52
	column.add_child(gap)
	start_button = _button("01    НАЧАТЬ ЗАЕЗД     →", true)
	start_button.name = "StartButton"
	start_button.pressed.connect(_open_tracks)
	column.add_child(start_button)
	var settings := _button("02    НАСТРОЙКИ", false)
	settings.name = "SettingsButton"
	settings.pressed.connect(_open_settings)
	column.add_child(settings)
	var quit := _button("03    ВЫХОД", false)
	quit.name = "QuitButton"
	quit.pressed.connect(get_tree().quit)
	column.add_child(quit)
	var bottom_space := Control.new()
	bottom_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(bottom_space)
	column.add_child(_label("RALLY 4.7   /   ГОТОВ К СТАРТУ", 13, Color(0.64, 0.69, 0.64)))
	var footer_gap := Control.new()
	footer_gap.custom_minimum_size.y = 9
	column.add_child(footer_gap)
	column.add_child(_label("ENTER  ВЫБРАТЬ     ↑ ↓  НАВИГАЦИЯ", 12, Color(0.49, 0.55, 0.50)))


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 66)
	button.add_theme_font_size_override("font_size", 19)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.89, 0.41, 0.14) if primary else Color(0.08, 0.11, 0.09, 0.45)
	normal.content_margin_left = 22
	normal.content_margin_right = 20
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1.0, 0.54, 0.22) if primary else Color(0.21, 0.27, 0.22, 0.9)
	hover.border_width_left = 4
	hover.border_color = Color(1.0, 0.61, 0.25)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", Color(0.09, 0.09, 0.07) if primary else Color(0.9, 0.92, 0.87))
	button.add_theme_color_override("font_hover_color", Color(0.09, 0.09, 0.07) if primary else Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color(0.09, 0.09, 0.07) if primary else Color.WHITE)
	return button


func _open_tracks() -> void:
	get_tree().change_scene_to_file(TRACK_MENU)


func _open_settings() -> void:
	if input_settings == null:
		input_settings = InputSettings.new()
		input_settings.name = "InputSettings"
		add_child(input_settings)
	input_settings.open()
