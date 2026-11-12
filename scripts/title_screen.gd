## Вся разметка, стили и настройки фона лежат в title_screen.tscn.
extends Control

const InputSettings = preload("res://scripts/ui/input_settings.gd")
@export_file("*.tscn") var track_menu_scene := "res://scenes/main_menu.tscn"
@export_range(320, 1920, 10) var preview_max_width := 960
@export_range(180, 1080, 10) var preview_max_height := 540
@export_range(5.0, 60.0, 1.0, "suffix:fps") var preview_fps := 30.0
@onready var world_viewport: SubViewport = $WorldViewport
@onready var preview: TextureRect = $Preview
@onready var driver = $WorldViewport/MenuStage/Driver
@onready var start_button: Button = $Menu/Column/Actions/StartButton
@onready var testpad_button: Button = $Menu/Column/Actions/TestPadButton
@onready var settings_button: Button = $Menu/Column/Actions/SettingsButton
@onready var quit_button: Button = $Menu/Column/Actions/QuitButton
var input_settings = null
var _preview_clock := 0.0


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	preview.texture = world_viewport.get_texture()
	_resize_preview()
	get_viewport().size_changed.connect(_resize_preview)
	start_button.pressed.connect(_open_tracks)
	testpad_button.pressed.connect(_open_test_polygon)
	settings_button.pressed.connect(_open_settings)
	quit_button.pressed.connect(get_tree().quit)
	for button in [start_button, testpad_button, settings_button, quit_button]:
		button.mouse_entered.connect(button.grab_focus)
	# Кнопка есть только тогда, когда полигон прописан в конфиге игры.
	var game: Node = _game()
	testpad_button.visible = game != null and bool(game.call("has_test_polygon"))
	start_button.grab_focus()


func _process(delta: float) -> void:
	var brightness: float = driver.replay_fade
	preview.modulate = Color(brightness, brightness, brightness, 1.0)
	_preview_clock += delta
	var interval := 1.0 / maxf(preview_fps, 1.0)
	if _preview_clock >= interval:
		_preview_clock = fposmod(_preview_clock, interval)
		world_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _resize_preview() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var scale_factor := minf(float(preview_max_width) / viewport_size.x, float(preview_max_height) / viewport_size.y)
	world_viewport.size = Vector2i(maxi(1, roundi(viewport_size.x * scale_factor)), maxi(1, roundi(viewport_size.y * scale_factor)))
	world_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _open_tracks() -> void:
	get_tree().change_scene_to_file(track_menu_scene)


## Прямой вход в тест-полигон: ни выбора трассы, ни гаража — сразу заезд.
func _open_test_polygon() -> void:
	var game: Node = _game()
	if game != null and game.has_method("start_test_polygon"):
		game.call("start_test_polygon")


func _game() -> Node:
	return get_node_or_null("/root/RallyGame")


func _open_settings() -> void:
	if input_settings == null:
		input_settings = InputSettings.new()
		input_settings.name = "InputSettings"
		add_child(input_settings)
	input_settings.open()
