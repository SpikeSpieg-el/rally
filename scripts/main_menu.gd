## Главное меню: заставка с кнопкой START, УПРАВЛЕНИЕ, НАЗАД, ВЫХОД и радио.
## Выбор трассы, условий и машины переехал в 3D-гараж (см. garage_menu.gd и
## garage_track_panel.gd): START открывает гараж, где трасса выбирается на доске.
extends Control

const GameConfigType = preload("res://scripts/data/rally_game_config.gd")
const CarSetupType = preload("res://scripts/data/rally_car_setup.gd")
const GarageScene = preload("res://scenes/garage_menu.tscn")
const InputSettings = preload("res://scripts/ui/input_settings.gd")
const UiThemeType = preload("res://scripts/data/rally_ui_theme.gd")
const MenuLayoutType = preload("res://scripts/data/rally_menu_layout.gd")
const LayoutType = preload("res://scripts/ui/rally_screen_layout.gd")

@export_group("Данные (инспектор)")
@export var config: GameConfigType = null
## Цвета и размеры шрифтов меню. Пусто — res://data/ui/default_ui_theme.tres.
@export var ui_theme: UiThemeType = null
## Тексты, подсказки и горячие клавиши меню. Пусто — default_menu_layout.tres.
@export var menu_layout: MenuLayoutType = null

@onready var title_label: Label = get_node_or_null("Content/Header/Title") as Label
@onready var subtitle_label: Label = get_node_or_null("Content/Header/Subtitle") as Label
@onready var start_button: Button = get_node_or_null("Content/Body/Left/ButtonRow/StartButton") as Button
@onready var back_button: Button = get_node_or_null("Content/Body/Left/ButtonRow/BackButton") as Button
@onready var quit_button: Button = get_node_or_null("Content/Body/Left/ButtonRow/QuitButton") as Button
@onready var controls_button: Button = get_node_or_null("Content/Body/Left/ButtonRow/ControlsButton") as Button
@onready var footer_label: Label = get_node_or_null("Content/Footer") as Label
@onready var content: Control = get_node_or_null("Content") as Control

var controller_manager: Node = null
var garage = null
var input_settings = null
## Машина, выбранная в гараже: индекс в списке сетапов текущей машины.
var selected_setup: int = 0
var _transitioning: bool = false
var _screen_tween: Tween = null
var _content_base_x: float = 0.0
var _garage_base_x: float = 0.0
## Портретная раскладка: одна колонка, правая часть скрыта.
var _portrait: bool = false
var _portrait_scroll: ScrollContainer = null

func theme_cfg() -> UiThemeType:
	if ui_theme == null:
		if ResourceLoader.exists("res://data/ui/default_ui_theme.tres"):
			ui_theme = ResourceLoader.load("res://data/ui/default_ui_theme.tres") as UiThemeType
		if ui_theme == null:
			ui_theme = UiThemeType.new()
	return ui_theme


func layout() -> MenuLayoutType:
	if menu_layout == null:
		if ResourceLoader.exists("res://data/ui/default_menu_layout.tres"):
			menu_layout = ResourceLoader.load("res://data/ui/default_menu_layout.tres") as MenuLayoutType
		if menu_layout == null:
			menu_layout = MenuLayoutType.new()
	return menu_layout


## Применить палитру и шрифты меню к настоящей сцене (а не копии стилей):
## заголовки, акцентная полоса, подписи и кнопки остаются узлами.
func _apply_theme() -> void:
	_apply_theme_colors(theme_cfg())


## Поворот телефона: меню пересобирает крупность и раскладку колонок.
func _on_viewport_resized() -> void:
	var wanted_scale: float = LayoutType.ui_scale()
	var was_portrait: bool = _portrait
	_portrait = LayoutType.is_portrait()
	if is_equal_approx(wanted_scale, theme_cfg().ui_scale) and _portrait == was_portrait:
		return
	theme_cfg().ui_scale = wanted_scale
	_apply_theme()
	var native := Theme.new()
	theme_cfg().apply_to(native)
	theme = native
	_refresh()
	_apply_portrait_stack()


## Прокрутка — ScrollContainer, который оборачивает левую колонку. Узлы не
## пересоздаются: колонка просто переезжает внутрь контейнера и обратно,
## поэтому ссылки на кнопки и фокус клавиатуры живут.
func _apply_portrait_stack() -> void:
	var body := get_node_or_null("Content/Body") as BoxContainer
	if body == null:
		return
	var left := get_node_or_null("Content/Body/Left") as Control
	var right := get_node_or_null("Content/Body/Right") as CanvasItem
	if right != null:
		right.visible = not _portrait
	if _portrait_scroll == null and left != null:
		_portrait_scroll = ScrollContainer.new()
		_portrait_scroll.name = "PortraitScroll"
		_portrait_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_portrait_scroll.follow_focus = true
		_portrait_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_portrait_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_child(_portrait_scroll)
	if _portrait_scroll == null or left == null:
		return
	var current_parent := left.get_parent()
	if _portrait and current_parent != _portrait_scroll:
		current_parent.remove_child(left)
		_portrait_scroll.add_child(left)
		_portrait_scroll.visible = true
	elif not _portrait and current_parent == _portrait_scroll:
		_portrait_scroll.remove_child(left)
		_portrait_scroll.visible = false
		body.add_child(left)
		body.move_child(left, 0)
	elif not _portrait:
		_portrait_scroll.visible = false


func _apply_theme_colors(t: UiThemeType) -> void:
	var background := get_node_or_null("Background") as ColorRect
	if background != null:
		background.color = t.background
	var bar := get_node_or_null("AccentBar") as ColorRect
	if bar != null:
		bar.color = t.accent
		bar.offset_bottom = float(t.accent_bar_height)
	# Поле content (см. @onready выше) уже указывает на этот узел: локальная
	# переменная с тем же именем только затеняла его.
	if content != null:
		content.offset_left = float(t.content_margin_horizontal)
		content.offset_top = float(t.content_margin_vertical)
		content.offset_right = -float(t.content_margin_horizontal)
		content.offset_bottom = -float(t.content_margin_bottom)
		content.add_theme_constant_override("separation", t.block_separation)
	if title_label != null:
		title_label.add_theme_font_size_override("font_size", t.font_title)
		title_label.add_theme_color_override("font_color", t.accent_alt)
	if subtitle_label != null:
		subtitle_label.add_theme_font_size_override("font_size", t.font_subtitle)
		subtitle_label.add_theme_color_override("font_color", t.text_secondary)
	for heading in ["TracksLabel", "SetupsLabel"]:
		var label := get_node_or_null("Content/Body/Left/" + heading) as Label
		if label != null:
			label.add_theme_font_size_override("font_size", t.font_section)
			label.add_theme_color_override("font_color", t.accent_soft)
	for button in [start_button, quit_button, controls_button, back_button]:
		if button != null:
			button.add_theme_font_size_override("font_size", t.font_button_small)
	# Заголовок RALLY крупный на ПК, а в узкой портретной колонке он растёт
	# медленнее остального UI: иначе «RALLY 4.7» шире экрана.
	if title_label != null:
		var title_size: int = roundi(float(t._font_title) * 0.82) if _portrait else t.font_title
		title_label.add_theme_font_size_override("font_size", title_size)
	if start_button != null:
		start_button.add_theme_stylebox_override("normal", t.button_style())
		start_button.add_theme_stylebox_override("hover", t.button_hover_style())
		start_button.add_theme_stylebox_override("pressed", t.button_hover_style())
	if footer_label != null:
		footer_label.add_theme_color_override("font_color", t.text_muted)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_resolve_config()
	# Телефон в альбоме: тема отдаёт крупные числа, `_apply_theme()` переносит их в сцену.
	theme_cfg().ui_scale = LayoutType.ui_scale()
	_apply_theme()
	if content != null:
		_content_base_x = content.position.x
	var native: Theme = Theme.new()
	theme_cfg().apply_to(native)
	theme = native
	_restore_selection()
	_connect_signals()
	_refresh()
	_portrait = LayoutType.is_portrait()
	_apply_portrait_stack()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_setup_controller()
	if start_button != null:
		start_button.grab_focus()


func _get_game() -> Node:
	return get_node_or_null("/root/RallyGame")


## Какая машина выбрана в гараже. От неё зависит список пресетов в меню:
## у Impreza свои настройки, у Lancer свои.
func _vehicle_id() -> String:
	var game := _get_game()
	var fallback := config.default_vehicle_id() if config != null else "mitsubishi"
	if game == null:
		return fallback
	var id := String(game.get("vehicle_id")) if game.get("vehicle_id") != null else fallback
	return id if config != null and config.has_vehicle(id) else fallback


func _resolve_config() -> void:
	if config != null:
		return
	var game: Node = _get_game()
	if game != null:
		var loaded: Variant = game.get("config")
		if loaded is GameConfigType:
			config = loaded
	if config == null:
		if ResourceLoader.exists("res://data/rally_game_config.tres"):
			var resource: Resource = ResourceLoader.load("res://data/rally_game_config.tres")
			if resource is GameConfigType:
				config = resource
	if config == null:
		config = GameConfigType.new()


## Машина и сетап берутся из RallyGame: гараж открывается с того же выбора.
func _restore_selection() -> void:
	var game: Node = _get_game()
	var vehicle := _vehicle_id()
	selected_setup = clampi(config.default_setup_index, 0, maxi(0, config.setup_count(vehicle) - 1))
	if game != null:
		selected_setup = clampi(
			int(game.get("setup_index")), 0, maxi(0, int(game.call("setup_count", vehicle)) - 1)
		)


func _connect_signals() -> void:
	if start_button != null and not start_button.pressed.is_connected(_on_start_pressed):
		start_button.pressed.connect(_on_start_pressed)
	if back_button != null and not back_button.pressed.is_connected(_on_back_to_title):
		back_button.pressed.connect(_on_back_to_title)
	if quit_button != null and not quit_button.pressed.is_connected(_on_quit_pressed):
		quit_button.pressed.connect(_on_quit_pressed)
	if controls_button != null and not controls_button.pressed.is_connected(_open_input_settings):
		controls_button.pressed.connect(_open_input_settings)


func _setup_controller() -> void:
	controller_manager = get_node_or_null("/root/ControllerManager")
	if controller_manager != null and controller_manager.has_signal("active_device_changed"):
		if not controller_manager.is_connected("active_device_changed", _on_input_device_changed):
			controller_manager.connect("active_device_changed", _on_input_device_changed)
	_update_footer()


func _on_input_device_changed(_gamepad_active: bool) -> void:
	_update_footer()


func _update_footer() -> void:
	if footer_label == null:
		return
	if controller_manager != null and bool(controller_manager.get("gamepad_active")) and controller_manager.has_method("get_glyphs"):
		var glyphs: Dictionary = controller_manager.call("get_glyphs")
		footer_label.text = layout().footer_gamepad % [
			String(glyphs["dpad_up"]), String(glyphs["dpad_down"]),
			String(glyphs["accept"]), String(glyphs["cancel"]),
		]
	else:
		footer_label.text = layout().footer_keyboard


func _refresh() -> void:
	if config == null:
		return
	if title_label != null:
		title_label.text = config.title
	if subtitle_label != null:
		subtitle_label.text = config.subtitle


func _unhandled_input(event: InputEvent) -> void:
	if _transitioning or (garage != null and garage.visible):
		return
	if input_settings != null and input_settings.blocks_actions():
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_to_title()


## Сетап уходит в RallyGame: гараж и заезд читают его оттуда.
func _sync_game() -> void:
	var game: Node = _get_game()
	if game == null:
		return
	game.call("select_setup", selected_setup)


func _kill_screen_tween() -> void:
	if _screen_tween != null and _screen_tween.is_running():
		_screen_tween.kill()
	_screen_tween = null


func _on_start_pressed() -> void:
	if _transitioning:
		return
	_transitioning = true
	_sync_game()
	if garage == null:
		garage = GarageScene.instantiate()
		garage.name = "Garage"
		add_child(garage)
		garage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_garage_base_x = garage.position.x
		garage.back_requested.connect(_on_garage_back)
		garage.controls_requested.connect(_open_input_settings)
		garage.setup_saved.connect(_on_garage_saved)
		garage.start_requested.connect(_on_garage_start)
	# Гараж не «всплывает» поверх меню: старый экран уходит по прозрачности
	# и легкому сдвигу, новый приходит ему на смену. Радио при этом не рвётся.
	_kill_screen_tween()
	garage.modulate.a = 0.0
	garage.position.x = _garage_base_x + 34.0
	content.visible = true
	content.modulate.a = 1.0
	content.position.x = _content_base_x
	garage.open(config, selected_setup, _get_game())
	_screen_tween = create_tween().set_parallel(true)
	_screen_tween.tween_property(content, "modulate:a", 0.0, 0.24)
	_screen_tween.tween_property(content, "position:x", _content_base_x - 24.0, 0.24)
	_screen_tween.tween_property(garage, "modulate:a", 1.0, 0.32)
	_screen_tween.tween_property(garage, "position:x", _garage_base_x, 0.32)
	await _screen_tween.finished
	content.visible = false
	_transitioning = false


func _open_input_settings() -> void:
	if _transitioning:
		return
	if input_settings == null:
		input_settings = InputSettings.new()
		input_settings.name = "InputSettings"
		add_child(input_settings)
	# Гараж мог быть добавлен позже окна; оно всегда должно лежать поверх.
	move_child(input_settings, get_child_count() - 1)
	input_settings.open()


func _on_garage_back() -> void:
	if _transitioning or garage == null:
		return
	_transitioning = true
	_kill_screen_tween()
	content.visible = true
	content.modulate.a = 0.0
	content.position.x = _content_base_x - 24.0
	garage.visible = true
	garage.modulate.a = 1.0
	garage.position.x = _garage_base_x
	_screen_tween = create_tween().set_parallel(true)
	_screen_tween.tween_property(content, "modulate:a", 1.0, 0.30)
	_screen_tween.tween_property(content, "position:x", _content_base_x, 0.30)
	_screen_tween.tween_property(garage, "modulate:a", 0.0, 0.24)
	_screen_tween.tween_property(garage, "position:x", _garage_base_x + 34.0, 0.24)
	await _screen_tween.finished
	garage.visible = false
	_refresh()
	if start_button != null:
		start_button.grab_focus()
	_transitioning = false


func _on_garage_saved(index: int) -> void:
	if _transitioning:
		return
	selected_setup = index
	_sync_game()


## Старт из гаража: трасса и условия уже записаны панелью гаража (prepare_race),
## здесь остаётся закрепить сетап именно того пресета, с которого нажали «Старт».
func _on_garage_start(index: int, tuned_setup: CarSetupType) -> void:
	if _transitioning:
		return
	selected_setup = index
	_sync_game()
	var game: Node = _get_game()
	if game != null:
		if garage != null:
			garage.prepare_race()
		game.set("current_setup", tuned_setup)
		game.call("start_race")
	else:
		var scene_path: String = config.stage_scene
		var chosen = garage.current_track() if garage != null else null
		if chosen != null and not chosen.stage_scene.is_empty():
			scene_path = chosen.stage_scene
		get_tree().change_scene_to_file(scene_path)


func _on_back_to_title() -> void:
	if not _transitioning:
		get_tree().change_scene_to_file("res://scenes/title_screen.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
