## Вся разметка, стили и настройки фона лежат в title_screen.tscn.
extends Control

const InputSettings = preload("res://scripts/ui/input_settings.gd")
const UiThemeType = preload("res://scripts/data/rally_ui_theme.gd")
const LayoutType = preload("res://scripts/ui/rally_screen_layout.gd")
@export_file("*.tscn") var track_menu_scene := "res://scenes/main_menu.tscn"
@export_range(320, 1920, 10) var preview_max_width := 960
@export_range(180, 1080, 10) var preview_max_height := 540
@export_range(5.0, 60.0, 1.0, "suffix:fps") var preview_fps := 30.0
## Web/mobile: фон-заставка обновляется реже и рендерится мельче. Это фон под
## затемнением, а не игровой кадр: 12 FPS и 720×405 неотличимы от 30 FPS,
## но стоят в 2–4 раза дешевле.
const LOW_POWER_PREVIEW_FPS := 12.0
const LOW_POWER_PREVIEW_WIDTH := 720
const LOW_POWER_PREVIEW_HEIGHT := 405
@onready var world_viewport: SubViewport = $WorldViewport
@onready var preview: TextureRect = $Preview
@onready var driver = $WorldViewport/MenuStage/Driver
@onready var start_button: Button = $Menu/Column/Actions/StartButton
@onready var testpad_button: Button = $Menu/Column/Actions/TestPadButton
@onready var settings_button: Button = $Menu/Column/Actions/SettingsButton
@onready var quit_button: Button = $Menu/Column/Actions/QuitButton
var input_settings = null
var vr_button: Button
var _preview_clock := 0.0
## Размеры шрифтов из .tscn: от них считаем крупность для телефона.
var _title_base_size: int = 104
var _button_base_sizes: Dictionary = {}
var _ui_theme: UiThemeType = null


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	preview.texture = world_viewport.get_texture()
	# Браузер/телефон: фон-заставка — это целый 3D-мир. На телефоне он
	# отъедает кадры у меню, а меню всё равно перекрывает его затемнением.
	# Режем частоту обновления (фон живой, но дешевле) и размер рендера.
	if OS.has_feature("web") or OS.has_feature("mobile"):
		preview_fps = minf(preview_fps, LOW_POWER_PREVIEW_FPS)
		preview_max_width = mini(preview_max_width, LOW_POWER_PREVIEW_WIDTH)
		preview_max_height = mini(preview_max_height, LOW_POWER_PREVIEW_HEIGHT)
	_ui_theme = _load_ui_theme()
	_cache_button_sizes()
	_apply_ui_scale()
	_resize_preview()
	get_viewport().size_changed.connect(_on_viewport_resized)
	start_button.pressed.connect(_open_tracks)
	testpad_button.pressed.connect(_open_test_polygon)
	settings_button.pressed.connect(_open_settings)
	quit_button.pressed.connect(get_tree().quit)
	for button in [start_button, testpad_button, settings_button, quit_button]:
		button.mouse_entered.connect(button.grab_focus)
	# Кнопка есть только тогда, когда полигон прописан в конфиге игры.
	var game: Node = _game()
	testpad_button.visible = game != null and bool(game.call("has_test_polygon"))
	vr_button = Button.new()
	vr_button.text = "РЕЖИМ: ПК (включить VR / OpenXR)"
	vr_button.pressed.connect(_toggle_vr)
	start_button.get_parent().add_child(vr_button)
	# Кнопка VR создана кодом уже после расчёта крупности — даём ей тот же
	# размер шрифта, что и остальным.
	_button_base_sizes[vr_button] = 17
	_apply_ui_scale()
	start_button.grab_focus()


func _process(delta: float) -> void:
	var brightness: float = driver.replay_fade
	preview.modulate = Color(brightness, brightness, brightness, 1.0)
	_preview_clock += delta
	var interval := 1.0 / maxf(preview_fps, 1.0)
	if _preview_clock >= interval:
		_preview_clock = fposmod(_preview_clock, interval)
		world_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Тема меню (никогда null): оттуда печать и крупность для телефона.
func _load_ui_theme() -> UiThemeType:
	if ResourceLoader.exists("res://data/ui/default_ui_theme.tres"):
		var loaded: Resource = ResourceLoader.load("res://data/ui/default_ui_theme.tres")
		if loaded is UiThemeType:
			return loaded as UiThemeType
	return UiThemeType.new()


## Запомнить «ПК-размеры» из сцены: крупность применяется как множитель от
## них, поэтому повторный вызов при повороте не растит текст второй раз.
func _cache_button_sizes() -> void:
	var title := get_node_or_null("Menu/Column/Title") as Label
	if title != null and title.has_theme_font_size_override("font_size"):
		_title_base_size = title.get_theme_font_size("font_size")
	for button in [start_button, testpad_button, settings_button, quit_button]:
		if button != null:
			_button_base_sizes[button] = button.get_theme_font_size("font_size")


## Телефон/браузер: заголовок и кнопки крупнее, иначе на ладони они читаются
## как подписи. Значение — шрифт, а не `scale`: текст остаётся резким.
func _apply_ui_scale() -> void:
	if _ui_theme == null:
		return
	var scale_amount: float = LayoutType.ui_scale()
	var title := get_node_or_null("Menu/Column/Title") as Label
	if title != null:
		title.add_theme_font_size_override("font_size", roundi(float(_title_base_size) * scale_amount))
	for button in _button_base_sizes.keys():
		var base_size: int = int(_button_base_sizes[button])
		var ctrl := button as Button
		if ctrl == null:
			continue
		ctrl.add_theme_font_size_override("font_size", roundi(float(base_size) * scale_amount))
		# На телефоне кнопки ещё и выше: палец не должен целиться в 60 px.
		if scale_amount > 1.0:
			var minimum: Vector2 = ctrl.custom_minimum_size
			minimum.y = roundf(maxf(minimum.y, 60.0) * scale_amount)
			ctrl.custom_minimum_size = minimum


func _on_viewport_resized() -> void:
	_resize_preview()
	_apply_ui_scale()


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

func _toggle_vr() -> void:
	if VRMode.requested:
		VRMode.stop()
		vr_button.text = "РЕЖИМ: ПК (включить VR / OpenXR)"
	elif VRMode.start():
		vr_button.text = "РЕЖИМ: VR (вернуться к ПК)"
	else:
		vr_button.text = "OpenXR не найден — подключите Pico 4 к SteamVR"
