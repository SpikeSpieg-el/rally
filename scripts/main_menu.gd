## Главное меню в духе классических Colin McRae Rally.
## Списки трасс и конфигураций берутся из res://data/rally_game_config.tres —
## чтобы добавить трассу, достаточно добавить ресурс в инспекторе.
extends Control

const GameConfigType = preload("res://scripts/data/rally_game_config.gd")
const TrackConfigType = preload("res://scripts/data/rally_track_config.gd")
const CarSetupType = preload("res://scripts/data/rally_car_setup.gd")
const StagePreviewType = preload("res://scripts/stage_preview.gd")

@export var config: GameConfigType = null

@onready var title_label: Label = get_node_or_null("Content/Header/Title") as Label
@onready var subtitle_label: Label = get_node_or_null("Content/Header/Subtitle") as Label
@onready var track_list: BoxContainer = get_node_or_null("Content/Body/Left/TrackList") as BoxContainer
@onready var setup_list: BoxContainer = get_node_or_null("Content/Body/Left/SetupList") as BoxContainer
@onready var start_button: Button = get_node_or_null("Content/Body/Left/ButtonRow/StartButton") as Button
@onready var quit_button: Button = get_node_or_null("Content/Body/Left/ButtonRow/QuitButton") as Button
@onready var preview: Control = get_node_or_null("Content/Body/Right/Preview") as Control
@onready var info_label: Label = get_node_or_null("Content/Body/Right/InfoLabel") as Label
@onready var power_bar: ProgressBar = get_node_or_null("Content/Body/Right/Stats/PowerBar") as ProgressBar
@onready var grip_bar: ProgressBar = get_node_or_null("Content/Body/Right/Stats/GripBar") as ProgressBar
@onready var suspension_bar: ProgressBar = get_node_or_null("Content/Body/Right/Stats/SuspensionBar") as ProgressBar
@onready var best_label: Label = get_node_or_null("Content/Body/Right/BestLabel") as Label
@onready var footer_label: Label = get_node_or_null("Content/Footer") as Label

var track_buttons: Array[Button] = []
var setup_buttons: Array[Button] = []
var selected_track: int = 0
var selected_setup: int = 0
var controller_manager: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_resolve_config()
	_restore_selection()
	_build_buttons()
	_connect_signals()
	_connect_focus_navigation()
	_refresh()
	_setup_controller()
	if start_button != null:
		start_button.grab_focus()


func _get_game() -> Node:
	return get_node_or_null("/root/RallyGame")


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


func _restore_selection() -> void:
	var game: Node = _get_game()
	selected_track = clampi(config.default_track_index, 0, maxi(0, config.track_count() - 1))
	selected_setup = clampi(config.default_setup_index, 0, maxi(0, config.setup_count() - 1))
	if game != null:
		selected_track = clampi(int(game.get("track_index")), 0, maxi(0, config.track_count() - 1))
		selected_setup = clampi(int(game.get("setup_index")), 0, maxi(0, config.setup_count() - 1))


func _build_buttons() -> void:
	if track_list != null:
		for child in track_list.get_children():
			child.queue_free()
		track_buttons.clear()
		for i in range(config.track_count()):
			var track: TrackConfigType = config.get_track(i) as TrackConfigType
			if track == null:
				continue
			var button := Button.new()
			button.name = "TrackButton_%d" % i
			button.text = "F%d   %s" % [i + 1, track.display_name]
			button.tooltip_text = track.description
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.custom_minimum_size = Vector2(0, 38)
			button.focus_mode = Control.FOCUS_ALL
			button.add_theme_font_size_override("font_size", 17)
			button.pressed.connect(_on_track_pressed.bind(i))
			track_list.add_child(button)
			track_buttons.append(button)
	if setup_list != null:
		for child in setup_list.get_children():
			child.queue_free()
		setup_buttons.clear()
		for i in range(config.setup_count()):
			var setup: CarSetupType = config.get_setup(i) as CarSetupType
			if setup == null:
				continue
			var button := Button.new()
			button.name = "SetupButton_%d" % i
			button.text = setup.display_name
			button.tooltip_text = setup.description
			button.custom_minimum_size = Vector2(0, 34)
			button.focus_mode = Control.FOCUS_ALL
			button.add_theme_font_size_override("font_size", 15)
			button.pressed.connect(_on_setup_pressed.bind(i))
			setup_list.add_child(button)
			setup_buttons.append(button)


func _connect_signals() -> void:
	if start_button != null and not start_button.pressed.is_connected(_on_start_pressed):
		start_button.pressed.connect(_on_start_pressed)
	if quit_button != null and not quit_button.pressed.is_connected(_on_quit_pressed):
		quit_button.pressed.connect(_on_quit_pressed)
	if preview != null and preview.has_signal("track_built"):
		if not preview.is_connected("track_built", _on_preview_track_built):
			preview.connect("track_built", _on_preview_track_built)


## Явные соседи фокуса: с геймпада по меню можно ходить D-pad/левым стиком,
## не полагаясь на то, как Godot угадает геометрию динамических кнопок.
func _connect_focus_navigation() -> void:
	for i in range(track_buttons.size()):
		var button := track_buttons[i]
		if not button.focus_entered.is_connected(_on_track_focused):
			button.focus_entered.connect(_on_track_focused.bind(i))
		_set_focus_neighbors(
			button,
			track_buttons[i - 1] if i > 0 else track_buttons[track_buttons.size() - 1],
			track_buttons[i + 1] if i + 1 < track_buttons.size() else start_button,
			null,
			setup_buttons[clampi(selected_setup, 0, setup_buttons.size() - 1)] if not setup_buttons.is_empty() else start_button
		)
	for i in range(setup_buttons.size()):
		var button := setup_buttons[i]
		if not button.focus_entered.is_connected(_on_setup_focused):
			button.focus_entered.connect(_on_setup_focused.bind(i))
		_set_focus_neighbors(
			button,
			track_buttons[clampi(selected_track, 0, track_buttons.size() - 1)] if not track_buttons.is_empty() else null,
			start_button,
			setup_buttons[i - 1] if i > 0 else setup_buttons[setup_buttons.size() - 1],
			setup_buttons[i + 1] if i + 1 < setup_buttons.size() else setup_buttons[0]
		)
	_set_focus_neighbors(start_button, _selected_setup_button(), track_buttons[0] if not track_buttons.is_empty() else null, quit_button, quit_button)
	_set_focus_neighbors(quit_button, _selected_setup_button(), track_buttons[0] if not track_buttons.is_empty() else null, start_button, start_button)
	_update_dynamic_focus()


func _set_focus_neighbors(control: Control, top: Control, bottom: Control, left: Control, right: Control) -> void:
	if control == null:
		return
	if top != null:
		control.focus_neighbor_top = control.get_path_to(top)
	if bottom != null:
		control.focus_neighbor_bottom = control.get_path_to(bottom)
	if left != null:
		control.focus_neighbor_left = control.get_path_to(left)
	if right != null:
		control.focus_neighbor_right = control.get_path_to(right)


## Соседи, которые зависят от текущего выбора трассы/конфигурации.
func _update_dynamic_focus() -> void:
	var setup_target := _selected_setup_button()
	var track_target: Button = track_buttons[clampi(selected_track, 0, track_buttons.size() - 1)] if not track_buttons.is_empty() else null
	for button in track_buttons:
		if setup_target != null:
			button.focus_neighbor_right = button.get_path_to(setup_target)
	for button in setup_buttons:
		if track_target != null:
			button.focus_neighbor_top = button.get_path_to(track_target)
	if start_button != null and setup_target != null:
		start_button.focus_neighbor_top = start_button.get_path_to(setup_target)
	if quit_button != null and setup_target != null:
		quit_button.focus_neighbor_top = quit_button.get_path_to(setup_target)


func _selected_setup_button() -> Button:
	if setup_buttons.is_empty():
		return null
	return setup_buttons[clampi(selected_setup, 0, setup_buttons.size() - 1)]


func _on_track_focused(index: int) -> void:
	if selected_track == index:
		return
	selected_track = index
	_sync_game()
	_refresh()


func _on_setup_focused(index: int) -> void:
	if selected_setup == index:
		return
	selected_setup = index
	_sync_game()
	_refresh()


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
		footer_label.text = "Геймпад: [%s/%s] трасса  •  [%s/%s] конфигурация  •  [%s] старт  •  [%s] выход  •  горячее подключение" % [
			String(glyphs["dpad_up"]), String(glyphs["dpad_down"]),
			String(glyphs["dpad_left"]), String(glyphs["dpad_right"]),
			String(glyphs["accept"]), String(glyphs["cancel"]),
		]
	else:
		footer_label.text = "Выбор трассы и конфигурации сохраняется между заездами.  F1-F5 — смена трассы, ESC — пауза, C — камера, V — привод."


## Превью закончило плести процедурную трассу — длина стала точной.
func _on_preview_track_built(built_track: TrackConfigType) -> void:
	# ВАЖНО: «x == y as T» парсер читает как «(x == y) as T» — приведение
	# bool к типу. Каст делаем отдельным присваиванием.
	var selected: TrackConfigType = config.get_track(selected_track) as TrackConfigType
	if built_track == selected:
		_refresh()


func _refresh() -> void:
	if title_label != null:
		title_label.text = config.title
	if subtitle_label != null:
		subtitle_label.text = config.subtitle

	for i in range(track_buttons.size()):
		var button: Button = track_buttons[i]
		button.modulate = Color(1.0, 0.62, 0.12) if i == selected_track else Color(0.86, 0.90, 0.94)
	for i in range(setup_buttons.size()):
		var button: Button = setup_buttons[i]
		button.modulate = Color(1.0, 0.62, 0.12) if i == selected_setup else Color(0.86, 0.90, 0.94)

	var track: TrackConfigType = config.get_track(selected_track) as TrackConfigType
	var setup: CarSetupType = config.get_setup(selected_setup) as CarSetupType
	if track == null:
		return
	if preview != null and preview is StagePreviewType:
		preview.call("set_track", track)
	if info_label != null:
		var length_value: float = track.get_route_length()
		var length_line: String = "ДЛИНА: %.0f м" % length_value
		if length_value <= 0.0 and track.procedural:
			# трасса ещё не сплетена (кэш пуст): честный диапазон из конфига
			length_line = "ДЛИНА: %d–%d км  •  СИД %d" % [
				int(round(track.procedural_length_min / 1000.0)),
				int(round(track.procedural_length_max / 1000.0)),
				track.generation_seed
			]
		info_label.text = "%s\n\n%s\n\n%s\nПОКРЫТИЕ: %s\nСЛОЖНОСТЬ: %d/5\nЦЕЛЬ: %s" % [
			track.display_name,
			track.description,
			length_line,
			track.surface_name,
			track.difficulty,
			_format_time(track.target_time)
		]
	if setup != null:
		if power_bar != null:
			power_bar.value = setup.get_power_rating()
		if grip_bar != null:
			grip_bar.value = setup.get_grip_rating()
		if suspension_bar != null:
			suspension_bar.value = setup.get_suspension_rating()
	if best_label != null:
		var best: float = 0.0
		var game: Node = _get_game()
		if game != null:
			best = float(game.call("get_best_time", track.get_record_key()))
		best_label.text = "ЛУЧШЕЕ ВРЕМЯ:  %s" % (_format_time(best) if best > 0.0 else "—")
	_update_dynamic_focus()


func _format_time(seconds: float) -> String:
	return "%02d:%06.3f" % [floori(seconds / 60.0), fmod(seconds, 60.0)]


func _sync_game() -> void:
	var game: Node = _get_game()
	if game == null:
		return
	game.set("track_index", selected_track)
	game.set("setup_index", selected_setup)
	game.call("select_setup", selected_setup)
	game.call("select_track", selected_track)


func _on_track_pressed(index: int) -> void:
	selected_track = index
	_sync_game()
	_refresh()


func _on_setup_pressed(index: int) -> void:
	selected_setup = index
	_sync_game()
	_refresh()


func _on_start_pressed() -> void:
	_sync_game()
	if controller_manager != null and controller_manager.has_method("rumble"):
		controller_manager.call("rumble", 0.35, 0.65, 0.2)
	var game: Node = _get_game()
	if game != null:
		game.call("start_race")
	else:
		get_tree().change_scene_to_file(config.stage_scene)


func _on_quit_pressed() -> void:
	get_tree().quit()
