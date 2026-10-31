## Главное меню в духе классических Colin McRae Rally.
## Списки трасс и конфигураций берутся из res://data/rally_game_config.tres —
## чтобы добавить трассу, достаточно добавить ресурс в инспекторе.
extends Control

const GameConfigType = preload("res://scripts/data/rally_game_config.gd")
const TrackConfigType = preload("res://scripts/data/rally_track_config.gd")
const CarSetupType = preload("res://scripts/data/rally_car_setup.gd")
const WeatherType = preload("res://scripts/data/rally_weather_config.gd")
const ProfileType = preload("res://scripts/data/rally_track_profile.gd")
const StagePreviewType = preload("res://scripts/stage_preview.gd")
const GarageScene = preload("res://scenes/garage_menu.tscn")

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
var weather_buttons: Array[Button] = []
var profile_buttons: Array[Button] = []
var selected_track: int = 0
var selected_setup: int = 0
var selected_weather: int = 0
var selected_profile: int = 0
var controller_manager: Node = null
var garage = null

# Блок условий заезда строится кодом: так меню остаётся одним .tscn,
# а списки погоды/характеров растут вместе с конфигом.
var _conditions_box: VBoxContainer = null
var _seed_box: VBoxContainer = null
var _seed_edit: LineEdit = null
var _seed_status: Label = null
var _weather_flow: HFlowContainer = null
var _profile_flow: HFlowContainer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_resolve_config()
	_restore_selection()
	_build_buttons()
	_build_conditions_ui()
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
	selected_weather = clampi(config.default_weather_index, 0, maxi(0, config.weather_count() - 1))
	selected_profile = clampi(config.default_profile_index, 0, maxi(0, config.profile_count() - 1))
	if game != null:
		selected_track = clampi(int(game.get("track_index")), 0, maxi(0, config.track_count() - 1))
		selected_setup = clampi(int(game.get("setup_index")), 0, maxi(0, config.setup_count() - 1))
		selected_weather = clampi(int(game.get("weather_index")), 0, maxi(0, config.weather_count() - 1))
		selected_profile = clampi(int(game.get("profile_index")), 0, maxi(0, config.profile_count() - 1))


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


## Кнопка-«чип» для погоды, профиля и сида: мышью и с клавиатуры
## (фокус кликом), а для геймпада есть горячие клавиши F6/F7/F8.
func _make_choice_button(text: String, tip: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.custom_minimum_size = Vector2(0.0, 28.0)
	button.focus_mode = Control.FOCUS_CLICK
	button.add_theme_font_size_override("font_size", 13)
	button.pressed.connect(action)
	return button


## Погода, характер трассы и панель сида «Живой ленты». Строится кодом
## внутри левой колонки: число пресетов задаётся конфигом, менять .tscn
## при добавлении новой погоды не нужно.
func _build_conditions_ui() -> void:
	var left := get_node_or_null("Content/Body/Left") as VBoxContainer
	if left == null:
		return
	if _conditions_box != null:
		_conditions_box.queue_free()
		_conditions_box = null
	var box := VBoxContainer.new()
	box.name = "ConditionsBox"
	box.add_theme_constant_override("separation", 4)
	left.add_child(box)
	var button_row := left.get_node_or_null("ButtonRow")
	if button_row != null:
		left.move_child(box, button_row.get_index())
	_conditions_box = box

	# --- «Живая лента»: видимый и сохраняемый сид -------------------------
	_seed_box = VBoxContainer.new()
	_seed_box.name = "LiveSeedBox"
	_seed_box.add_theme_constant_override("separation", 2)
	box.add_child(_seed_box)
	var seed_title := Label.new()
	seed_title.text = "ЖИВАЯ ЛЕНТА · СИД ГЕНЕРАЦИИ"
	seed_title.add_theme_color_override("font_color", Color(1.0, 0.62, 0.12, 1.0))
	seed_title.add_theme_font_size_override("font_size", 15)
	_seed_box.add_child(seed_title)
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 6)
	_seed_box.add_child(seed_row)
	_seed_edit = LineEdit.new()
	_seed_edit.custom_minimum_size = Vector2(104.0, 28.0)
	_seed_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed_edit.tooltip_text = "Введите сид и нажмите «ПРИМЕНИТЬ» — трасса соберётся ровно по нему."
	_seed_edit.text_submitted.connect(_on_seed_submitted)
	seed_row.add_child(_seed_edit)
	seed_row.add_child(_make_choice_button(
		"ПРИМЕНИТЬ", "Собрать трассу по введённому сиду", _on_seed_apply_pressed
	))
	var reroll := _make_choice_button(
		"ПЕРЕГЕНЕРИРОВАТЬ",
		"Новая случайная трасса. Сид сохраняется — карту всегда можно вернуть.",
		_on_seed_reroll_pressed
	)
	reroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(reroll)
	seed_row.add_child(_make_choice_button(
		"КОПИЯ", "Скопировать сид в буфер обмена", _on_seed_copy_pressed
	))
	_seed_status = Label.new()
	_seed_status.add_theme_color_override("font_color", Color(0.55, 0.68, 0.78, 1.0))
	_seed_status.add_theme_font_size_override("font_size", 11)
	_seed_status.text = "Сид сохраняется в user://rally_conditions.cfg"
	_seed_box.add_child(_seed_status)

	# --- Погода ------------------------------------------------------------
	var weather_title := Label.new()
	weather_title.text = "ПОГОДА"
	weather_title.add_theme_color_override("font_color", Color(1.0, 0.62, 0.12, 1.0))
	weather_title.add_theme_font_size_override("font_size", 15)
	box.add_child(weather_title)
	_weather_flow = HFlowContainer.new()
	_weather_flow.add_theme_constant_override("h_separation", 4)
	_weather_flow.add_theme_constant_override("v_separation", 4)
	box.add_child(_weather_flow)
	weather_buttons.clear()
	for i in range(config.weather_count()):
		var preset: WeatherType = config.get_weather(i) as WeatherType
		if preset == null:
			continue
		var text: String = preset.short_name if not preset.short_name.is_empty() else preset.display_name
		var tip: String = "%s\n%s" % [preset.display_name, preset.description]
		var button := _make_choice_button(text, tip, _on_weather_pressed.bind(i))
		_weather_flow.add_child(button)
		weather_buttons.append(button)

	# --- Характер трассы ---------------------------------------------------
	var profile_title := Label.new()
	profile_title.text = "ХАРАКТЕР ТРАССЫ"
	profile_title.add_theme_color_override("font_color", Color(1.0, 0.62, 0.12, 1.0))
	profile_title.add_theme_font_size_override("font_size", 15)
	box.add_child(profile_title)
	_profile_flow = HFlowContainer.new()
	_profile_flow.add_theme_constant_override("h_separation", 4)
	_profile_flow.add_theme_constant_override("v_separation", 4)
	box.add_child(_profile_flow)
	profile_buttons.clear()
	for i in range(config.profile_count()):
		var preset: ProfileType = config.get_profile(i) as ProfileType
		if preset == null:
			continue
		var button := _make_choice_button(
			preset.display_name,
			"%s\n%s" % [preset.display_name, preset.description],
			_on_profile_pressed.bind(i)
		)
		_profile_flow.add_child(button)
		profile_buttons.append(button)


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
	_set_focus_neighbors(start_button, track_buttons[clampi(selected_track, 0, track_buttons.size() - 1)] if not track_buttons.is_empty() else null, track_buttons[0] if not track_buttons.is_empty() else null, quit_button, quit_button)
	_set_focus_neighbors(quit_button, track_buttons[clampi(selected_track, 0, track_buttons.size() - 1)] if not track_buttons.is_empty() else null, track_buttons[0] if not track_buttons.is_empty() else null, start_button, start_button)
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
	var setup_target: Button = start_button
	var track_target: Button = track_buttons[clampi(selected_track, 0, track_buttons.size() - 1)] if not track_buttons.is_empty() else null
	for button in track_buttons:
		if setup_target != null:
			button.focus_neighbor_right = button.get_path_to(setup_target)
	for button in setup_buttons:
		if track_target != null:
			button.focus_neighbor_top = button.get_path_to(track_target)
	if start_button != null and track_target != null:
		start_button.focus_neighbor_top = start_button.get_path_to(track_target)
	if quit_button != null and track_target != null:
		quit_button.focus_neighbor_top = quit_button.get_path_to(track_target)


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
		footer_label.text = "Геймпад: [%s/%s] трасса  •  [%s] гараж  •  [%s] выход  •  погода и сид — мышью" % [
			String(glyphs["dpad_up"]), String(glyphs["dpad_down"]),
			String(glyphs["accept"]), String(glyphs["cancel"]),
		]
	else:
		footer_label.text = "F1-F5 — трасса  •  F6 — погода  •  F7 — характер трассы  •  F8 — новый сид «Живой ленты».  Выбор сохраняется между заездами."


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
		track_buttons[i].modulate = (
			Color(1.0, 0.62, 0.12) if i == selected_track else Color(0.86, 0.90, 0.94)
		)
	for i in range(setup_buttons.size()):
		setup_buttons[i].modulate = (
			Color(1.0, 0.62, 0.12) if i == selected_setup else Color(0.86, 0.90, 0.94)
		)
	for i in range(weather_buttons.size()):
		weather_buttons[i].modulate = (
			Color(1.0, 0.75, 0.25) if i == selected_weather else Color(0.82, 0.86, 0.90)
		)
	for i in range(profile_buttons.size()):
		profile_buttons[i].modulate = (
			Color(1.0, 0.75, 0.25) if i == selected_profile else Color(0.82, 0.86, 0.90)
		)

	var track: TrackConfigType = config.get_track(selected_track) as TrackConfigType
	var setup: CarSetupType = config.get_setup(selected_setup) as CarSetupType
	var weather: WeatherType = config.get_weather(selected_weather) as WeatherType
	var profile: ProfileType = config.get_profile(selected_profile) as ProfileType
	if track == null:
		return
	_refresh_seed_panel(track)
	if preview != null and preview is StagePreviewType:
		preview.call("set_conditions", weather, profile)
		preview.call("set_track", track)
	if info_label != null:
		info_label.text = _track_info_text(track, setup, weather, profile)
	if setup != null:
		if power_bar != null:
			power_bar.value = setup.get_power_rating()
		if grip_bar != null:
			grip_bar.value = setup.get_grip_rating()
		if suspension_bar != null:
			suspension_bar.value = setup.get_suspension_rating()
	if best_label != null:
		var key: String = track.get_record_key()
		var game: Node = _get_game()
		if game != null:
			if game.has_method("record_key_for"):
				key = String(game.call("record_key_for", track))
			var best: float = float(game.call("get_best_time", key))
			var note: String = ""
			if _is_conditions_modified(weather, profile):
				note = "  •  %s" % _conditions_short(weather, profile)
			best_label.text = "ЛУЧШЕЕ ВРЕМЯ%s:  %s" % [
				note, _format_time(best) if best > 0.0 else "—"
			]
		else:
			best_label.text = "ЛУЧШЕЕ ВРЕМЯ:  —"
	_update_dynamic_focus()


## Карточка заезда: трасса + выбранные погода и характер полотна + мотор.
## Итоговые цифры (ширина, кочки, сцепление) уже перемножены — ровно те,
## с которыми начнётся заезд.
func _track_info_text(
	track: TrackConfigType, setup: CarSetupType, weather: WeatherType, profile: ProfileType
) -> String:
	var length_value: float = track.get_route_length()
	var length_line: String = "ДЛИНА: %.0f м" % length_value
	if length_value <= 0.0 and track.procedural:
		# трасса ещё не сплетена (кэш пуст): честный диапазон из конфига
		length_line = "ДЛИНА: %d–%d км" % [
			int(round(track.procedural_length_min / 1000.0)),
			int(round(track.procedural_length_max / 1000.0)),
		]
	elif length_value <= 0.0:
		length_line = "ДЛИНА: —"
	if track.procedural:
		length_line += "  •  СИД %d" % track.generation_seed
	var surface: String = track.surface_name
	var grip: float = track.grip_scale
	var width: float = track.road_half_width * 2.0
	var bumps_mm: float = track.bumps_amplitude * 1000.0
	var profile_line: String = "ПОКРЫТИЕ: %s" % surface
	if profile != null:
		if not profile.surface_name.is_empty():
			surface = profile.surface_name
		profile_line = "ПОКРЫТИЕ: %s  •  %s" % [surface, profile.display_name]
		grip *= profile.grip_scale
		width *= profile.road_width_scale
		bumps_mm *= profile.bumps_scale
	var weather_line: String = "ПОГОДА: как на трассе"
	if weather != null:
		weather_line = "ПОГОДА: %s" % weather.display_name
		var weather_summary: String = weather.get_summary()
		if not weather_summary.is_empty() and weather_summary != weather.display_name:
			weather_line += "  •  %s" % weather_summary
		grip *= weather.grip_scale
	var engine_line: String = "\nМАШИНА И НАСТРОЙКИ — В ГАРАЖЕ"
	return "%s\n\n%s\n\n%s\n%s\n%s\n" % [
		track.display_name,
		track.description,
		length_line,
		profile_line,
		weather_line,
	] + "ШИРИНА: %.1f м  •  КОЧКИ: %.0f мм\n" % [
		width, bumps_mm,
	] + "СЦЕПЛЕНИЕ: %.2f  •  СЛОЖНОСТЬ: %d/5\n" % [
		grip, track.difficulty,
	] + "ЦЕЛЬ: %s%s" % [
		_format_time(track.target_time),
		engine_line,
	]


func _is_conditions_modified(weather: WeatherType, profile: ProfileType) -> bool:
	if weather != null and String(weather.id) != "default":
		return true
	return profile != null and String(profile.id) != "gravel"


func _conditions_short(weather: WeatherType, profile: ProfileType) -> String:
	var parts := PackedStringArray()
	if weather != null:
		parts.append(weather.display_name)
	if profile != null:
		parts.append(profile.display_name)
	return " + ".join(parts)


## Панель сида видна только у «Живой ленты»: у ручных трасс сида нет.
func _refresh_seed_panel(track: TrackConfigType) -> void:
	if _seed_box == null:
		return
	var procedural: bool = track != null and track.procedural
	_seed_box.visible = procedural
	if not procedural:
		return
	if _seed_edit != null and not _seed_edit.has_focus():
		_seed_edit.text = str(track.generation_seed)


func _current_track() -> TrackConfigType:
	return config.get_track(selected_track) as TrackConfigType


func _on_weather_pressed(index: int) -> void:
	selected_weather = index
	_sync_conditions()
	_refresh()


func _on_profile_pressed(index: int) -> void:
	selected_profile = index
	_sync_conditions()
	_refresh()


func _on_seed_reroll_pressed() -> void:
	var track: TrackConfigType = _current_track()
	if track == null or not track.procedural:
		return
	var game: Node = _get_game()
	if game != null and game.has_method("reroll_live_seed"):
		game.call("reroll_live_seed", track)
	else:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		track.generation_seed = rng.randi_range(1, 999999999)
	if _seed_status != null:
		_seed_status.text = "Новый сид %d сохранён — трасса переплетается" % track.generation_seed
	_refresh()


func _on_seed_submitted(_text: String) -> void:
	_on_seed_apply_pressed()


func _on_seed_apply_pressed() -> void:
	var track: TrackConfigType = _current_track()
	if track == null or _seed_edit == null:
		return
	var text: String = _seed_edit.text.strip_edges()
	if not text.is_valid_int():
		if _seed_status != null:
			_seed_status.text = "Сид — целое число от 1 до 999 999 999"
		return
	var value: int = clampi(text.to_int(), 1, 999999999)
	if value == track.generation_seed:
		if _seed_status != null:
			_seed_status.text = "Этот сид уже активен"
		return
	track.generation_seed = value
	var game: Node = _get_game()
	if game != null and game.has_method("remember_live_seed"):
		game.call("remember_live_seed", track.id, value)
	if _seed_status != null:
		_seed_status.text = "Сид %d сохранён — эта трасса соберётся заново" % value
	_refresh()


func _on_seed_copy_pressed() -> void:
	var track: TrackConfigType = _current_track()
	if track == null:
		return
	DisplayServer.clipboard_set(str(track.generation_seed))
	if _seed_status != null:
		_seed_status.text = "Сид %d скопирован" % track.generation_seed


## Горячие клавиши меню: F1–F5 — трассы, F6 — погода, F7 — характер,
## F8 — новый сид «Живой ленты». Раньше F1–F5 были только в подписи.
func _input(event: InputEvent) -> void:
	if garage != null and garage.visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_F1:
			_select_track_shortcut(0)
		KEY_F2:
			_select_track_shortcut(1)
		KEY_F3:
			_select_track_shortcut(2)
		KEY_F4:
			_select_track_shortcut(3)
		KEY_F5:
			_select_track_shortcut(4)
		KEY_F6:
			_cycle_choice(true)
		KEY_F7:
			_cycle_choice(false)
		KEY_F8:
			_on_seed_reroll_pressed()
		_:
			return
	get_viewport().set_input_as_handled()


func _select_track_shortcut(index: int) -> void:
	if index < 0 or index >= track_buttons.size():
		return
	_on_track_pressed(index)
	track_buttons[index].grab_focus()


func _cycle_choice(weather_next: bool) -> void:
	if weather_next:
		if weather_buttons.is_empty():
			return
		_on_weather_pressed((selected_weather + 1) % weather_buttons.size())
		return
	if profile_buttons.is_empty():
		return
	_on_profile_pressed((selected_profile + 1) % profile_buttons.size())


func _format_time(seconds: float) -> String:
	return "%02d:%06.3f" % [floori(seconds / 60.0), fmod(seconds, 60.0)]


func _sync_game() -> void:
	var game: Node = _get_game()
	if game == null:
		return
	# Выбор применяется через select_*: они обновляют и индексы, и сами
	# ресурсы (current_track/current_setup/current_weather/current_profile),
	# а заодно сохраняют выбор в user://rally_conditions.cfg.
	game.call("select_track", selected_track)
	game.call("select_setup", selected_setup)
	game.call("select_weather", selected_weather)
	game.call("select_profile", selected_profile)


## Погода и профиль живут в RallyGame: сцена этапа берёт их оттуда.
func _sync_conditions() -> void:
	var game: Node = _get_game()
	if game == null:
		return
	game.call("select_weather", selected_weather)
	game.call("select_profile", selected_profile)


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
	if garage == null:
		garage = GarageScene.instantiate()
		garage.name = "Garage"
		add_child(garage)
		garage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		garage.back_requested.connect(_on_garage_back)
		garage.start_requested.connect(_on_garage_start)
	get_node("Content").hide()
	garage.open(config, selected_setup, _get_game())


func _on_garage_back() -> void:
	garage.hide()
	get_node("Content").show()
	_refresh()
	if start_button != null:
		start_button.grab_focus()


func _on_garage_start(index: int, tuned_setup: CarSetupType) -> void:
	selected_setup = index
	_sync_game()
	var game: Node = _get_game()
	if game != null:
		game.call("save_custom_setup", index, tuned_setup)
		game.call("start_race")
	else:
		get_tree().change_scene_to_file(config.stage_scene)


func _on_quit_pressed() -> void:
	get_tree().quit()
