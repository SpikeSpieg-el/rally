## Стартовый экран: UI обновляется каждый кадр, 3D-превью — отдельно.
extends Control

const InputSettings = preload("res://scripts/ui/input_settings.gd")
const TRACK_MENU := "res://scenes/main_menu.tscn"
const RETRO_SHADER = preload("res://shaders/speed_fx.gdshader")
const ACCENT := Color(1.0, 0.58, 0.08)
const WHITE := Color(0.90, 0.94, 0.96)
const MUTED := Color(0.58, 0.70, 0.76)
const PREVIEW_INTERVAL := 1.0 / 30.0

@onready var world_viewport: SubViewport = $WorldViewport
@onready var drive: Node3D = $WorldViewport/TitleDrive
var input_settings = null
var start_button: Button
var preview: TextureRect
var _preview_clock := 0.0


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_preview()
	_build_ui()
	_resize_preview()
	get_viewport().size_changed.connect(_resize_preview)
	start_button.grab_focus()


func _process(delta: float) -> void:
	_preview_clock += delta
	if _preview_clock >= PREVIEW_INTERVAL:
		_preview_clock = fposmod(_preview_clock, PREVIEW_INTERVAL)
		# UPDATE_ONCE отделяет частоту тяжёлой 3D-сцены от отклика кнопок.
		world_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if preview != null:
		var brightness: float = drive.get("fade")
		preview.modulate = Color(brightness, brightness, brightness, 1.0)


func _resize_preview() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.y <= 0.0:
		return
	var aspect := viewport_size.x / viewport_size.y
	var height := mini(540, roundi(960.0 / maxf(aspect, 0.1)))
	world_viewport.size = Vector2i(maxi(1, roundi(float(height) * aspect)), maxi(1, height))
	world_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _build_preview() -> void:
	preview = TextureRect.new()
	preview.name = "Preview"
	preview.texture = world_viewport.get_texture()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_SCALE
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(preview)
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Тот же постэффект, что в игре, но только в маленьком SubViewport;
	# текст и кнопки остаются чёткими и не участвуют в screen-copy.
	var retro := ColorRect.new()
	retro.name = "RetroLook"
	retro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var retro_material := ShaderMaterial.new()
	retro_material.shader = RETRO_SHADER
	retro_material.set_shader_parameter("retro_strength", 0.85)
	retro_material.set_shader_parameter("resolution_y", 270.0)
	retro_material.set_shader_parameter("color_levels", 31.0)
	retro_material.set_shader_parameter("dither_strength", 0.7)
	retro_material.set_shader_parameter("speed_intensity", 0.0)
	retro_material.set_shader_parameter("vignette_strength", 0.12)
	retro.material = retro_material
	world_viewport.add_child(retro)
	retro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build_ui() -> void:
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient := ShaderMaterial.new()
	gradient.shader = load("res://shaders/title_gradient.gdshader")
	shade.material = gradient
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var accent_bar := ColorRect.new()
	accent_bar.color = ACCENT
	accent_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	accent_bar.anchor_right = 1.0
	accent_bar.offset_bottom = 6.0
	add_child(accent_bar)

	var margin := MarginContainer.new()
	margin.name = "Menu"
	margin.anchor_right = 0.39
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 78)
	margin.add_theme_constant_override("margin_top", 64)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_bottom", 55)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 0)
	margin.add_child(column)
	column.add_child(_label("RALLY 4.7     /     ГЛАВНОЕ МЕНЮ", 16, ACCENT))
	column.add_child(_spacer(0, true, 0.8))
	column.add_child(_label("ВРЕМЯ ВЫЙТИ НА СТАРТ", 16, ACCENT))
	column.add_child(_spacer(12))
	column.add_child(_label("RALLY", 92, WHITE))
	column.add_child(_label("СПЕЦУЧАСТОК ЖДЁТ", 20, MUTED))
	column.add_child(_spacer(23))
	var line := ColorRect.new()
	line.color = Color(0.75, 0.84, 0.88, 0.22)
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(line)
	column.add_child(_spacer(24))
	column.add_child(_label("Выбери трассу, подготовь машину\nи найди свой ритм на дороге.", 18, Color(0.72, 0.79, 0.81)))
	column.add_child(_spacer(37))
	start_button = _button("01   НАЧАТЬ ЗАЕЗД", true)
	start_button.name = "StartButton"
	start_button.pressed.connect(_open_tracks)
	column.add_child(start_button)
	column.add_child(_spacer(7))
	var settings := _button("02   НАСТРОЙКИ", false)
	settings.name = "SettingsButton"
	settings.pressed.connect(_open_settings)
	column.add_child(settings)
	column.add_child(_spacer(7))
	var quit := _button("03   ВЫХОД", false)
	quit.name = "QuitButton"
	quit.pressed.connect(get_tree().quit)
	column.add_child(quit)
	start_button.focus_neighbor_top = quit.get_path()
	start_button.focus_neighbor_bottom = settings.get_path()
	settings.focus_neighbor_top = start_button.get_path()
	settings.focus_neighbor_bottom = quit.get_path()
	quit.focus_neighbor_top = settings.get_path()
	quit.focus_neighbor_bottom = start_button.get_path()
	column.add_child(_spacer(0, true, 1.0))
	column.add_child(_label("ENTER  ВЫБРАТЬ     ↑ ↓  НАВИГАЦИЯ", 13, MUTED))


func _spacer(height: float, expand: bool = false, ratio: float = 1.0) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		spacer.size_flags_stretch_ratio = ratio
	return spacer


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
	button.custom_minimum_size = Vector2(0, 62)
	button.add_theme_font_size_override("font_size", 19)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.92, 0.42, 0.04) if primary else Color(0.09, 0.125, 0.16, 0.75)
	normal.content_margin_left = 22
	normal.content_margin_right = 20
	normal.border_width_left = 3
	normal.border_color = Color(1.0, 0.75, 0.25) if primary else Color(0.28, 0.38, 0.46)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1.0, 0.58, 0.08) if primary else Color(0.20, 0.26, 0.32, 0.95)
	hover.border_color = ACCENT
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color(1.0, 0.75, 0.25, 0.9)
	focus.set_border_width_all(1)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", Color(0.08, 0.08, 0.09) if primary else WHITE)
	button.add_theme_color_override("font_hover_color", Color(0.08, 0.08, 0.09) if primary else Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color(0.08, 0.08, 0.09) if primary else Color.WHITE)
	# Не оставляем фокус на старой кнопке, когда пользователь двигает мышь.
	button.mouse_entered.connect(button.grab_focus)
	return button


func _open_tracks() -> void:
	get_tree().change_scene_to_file(TRACK_MENU)


func _open_settings() -> void:
	if input_settings == null:
		input_settings = InputSettings.new()
		input_settings.name = "InputSettings"
		add_child(input_settings)
	input_settings.open()
