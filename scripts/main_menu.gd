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

var track_buttons: Array[Button] = []
var setup_buttons: Array[Button] = []
var selected_track: int = 0
var selected_setup: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_resolve_config()
	_restore_selection()
	_build_buttons()
	_connect_signals()
	_refresh()


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
		info_label.text = "%s\n\n%s\n\nДЛИНА: %.0f м\nПОКРЫТИЕ: %s\nСЛОЖНОСТЬ: %d/5\nЦЕЛЬ: %s" % [
			track.display_name,
			track.description,
			track.get_route_length(),
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
	var game: Node = _get_game()
	if game != null:
		game.call("start_race")
	else:
		get_tree().change_scene_to_file(config.stage_scene)


func _on_quit_pressed() -> void:
	get_tree().quit()
