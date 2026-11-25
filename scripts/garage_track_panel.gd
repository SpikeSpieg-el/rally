## Условия заезда у 3D-витрины гаража: карточка трассы, погода, характер полотна,
## время суток, коробка передач и «Живая лента» (сид, марафон).
##
## Структура — в сцене scenes/garage_track_panel.tscn: каждый блок — обычный узел
## с понятным именем, его видно в дереве Godot и можно двигать в инспекторе.
## Скрипт только заполняет тексты из MenuLayout, цвета и отступы из UiTheme и
## строит кнопки-чипы из узла ChipTemplate (число пресетов задаёт конфиг).
##
## Трасса выбирается на 3D-доске гаража (GarageTrackBoard), которая вызывает
## select_track(). Каждое изменение сразу пишется в RallyGame (select_*), поэтому
## гараж, карта и заезд видят одно и то же.
class_name GarageTrackPanel
extends PanelContainer

const GameConfigType = preload("res://scripts/data/rally_game_config.gd")
const TrackConfigType = preload("res://scripts/data/rally_track_config.gd")
const CarSetupType = preload("res://scripts/data/rally_car_setup.gd")
const WeatherType = preload("res://scripts/data/rally_weather_config.gd")
const ProfileType = preload("res://scripts/data/rally_track_profile.gd")
const ArcadeSettingsType = preload("res://scripts/data/rally_arcade_settings.gd")
const StagePreviewType = preload("res://scripts/stage_preview.gd")
const GhostRecordingType = preload("res://scripts/ghost/ghost_recording.gd")
const UiThemeType = preload("res://scripts/data/rally_ui_theme.gd")
const MenuLayoutType = preload("res://scripts/data/rally_menu_layout.gd")

## Общие ресурсы: тема и тексты — те же, что у гаража (пусто — значения по умолчанию).
var config: GameConfigType = null
var game: Node = null
var ui_theme: UiThemeType = null
var menu_layout: MenuLayoutType = null

## Выбор условий (индексы RallyGame). Трасса — отдельно, см. select_track().
var selected_track: int = 0
var selected_weather: int = 0
var selected_profile: int = 0
## Время суток: 0 — как на трассе, 1 — утро, 2 — день, 3 — вечер, 4 — ночь.
var selected_time: int = 0
var selected_transmission: int = 0

var weather_buttons: Array[Button] = []
var profile_buttons: Array[Button] = []
var time_buttons: Array[Button] = []
var transmission_buttons: Array[Button] = []

var _built: bool = false
var _marathon_stages: int = 0

@onready var _column: VBoxContainer = $PanelScroll/Column
@onready var _heading: Label = $PanelScroll/Column/TracksHeading
@onready var _preview: Control = $PanelScroll/Column/StagePreview
@onready var _info_label: Label = $PanelScroll/Column/InfoLabel
@onready var _best_label: Label = $PanelScroll/Column/BestLabel
@onready var _conditions_box: VBoxContainer = $PanelScroll/Column/ConditionsBox
@onready var _seed_box: VBoxContainer = $PanelScroll/Column/ConditionsBox/LiveSeedBox
@onready var _seed_title: Label = $PanelScroll/Column/ConditionsBox/LiveSeedBox/SeedTitle
@onready var _seed_edit: LineEdit = $PanelScroll/Column/ConditionsBox/LiveSeedBox/SeedRow/SeedEdit
@onready var _apply_button: Button = $PanelScroll/Column/ConditionsBox/LiveSeedBox/SeedRow/ApplyButton
@onready var _reroll_button: Button = $PanelScroll/Column/ConditionsBox/LiveSeedBox/SeedRow/RerollButton
@onready var _copy_button: Button = $PanelScroll/Column/ConditionsBox/LiveSeedBox/SeedRow/CopyButton
@onready var _seed_status: Label = $PanelScroll/Column/ConditionsBox/LiveSeedBox/SeedStatus
@onready var _marathon_label: Label = $PanelScroll/Column/ConditionsBox/LiveSeedBox/MarathonRow/MarathonLabel
@onready var _marathon_choice: OptionButton = $PanelScroll/Column/ConditionsBox/LiveSeedBox/MarathonRow/MarathonChoice
@onready var _weather_title: Label = $PanelScroll/Column/ConditionsBox/WeatherTitle
@onready var _weather_flow: HFlowContainer = $PanelScroll/Column/ConditionsBox/WeatherFlow
@onready var _profile_title: Label = $PanelScroll/Column/ConditionsBox/ProfileTitle
@onready var _profile_flow: HFlowContainer = $PanelScroll/Column/ConditionsBox/ProfileFlow
@onready var _time_title: Label = $PanelScroll/Column/ConditionsBox/TimeTitle
@onready var _time_flow: HFlowContainer = $PanelScroll/Column/ConditionsBox/TimeFlow
@onready var _transmission_title: Label = $PanelScroll/Column/ConditionsBox/TransmissionTitle
@onready var _transmission_flow: HFlowContainer = $PanelScroll/Column/ConditionsBox/TransmissionFlow
@onready var _chip_template: Button = $ChipTemplate


func _ready() -> void:
	_seed_edit.text_submitted.connect(_on_seed_submitted)
	_apply_button.pressed.connect(_on_seed_apply_pressed)
	_reroll_button.pressed.connect(_on_seed_reroll_pressed)
	_copy_button.pressed.connect(_on_seed_copy_pressed)
	_marathon_choice.fit_to_longest_item = false
	_marathon_choice.add_item("ОДИН ЗАЕЗД · ВЫБРАННЫЙ СИД", 0)
	_marathon_choice.add_item("МАРАФОН · 3 СЛУЧАЙНЫХ ЭТАПА", 3)
	_marathon_choice.add_item("МАРАФОН · 5 СЛУЧАЙНЫХ ЭТАПОВ", 5)
	_marathon_choice.tooltip_text = "Марафон на суммарное время: каждый этап — новый случайный сид. Выбранная машина, погода и покрытие сохраняются."
	_marathon_choice.item_selected.connect(_on_marathon_selected)
	_chip_template.visible = false


## Подключить панель к данным. Гараж вызывает это при каждом открытии.
func open(game_config: GameConfigType, game_state: Node, theme_data: UiThemeType, menu_data: MenuLayoutType) -> void:
	config = game_config
	game = game_state
	if theme_data != null:
		ui_theme = theme_data
	if menu_data != null:
		menu_layout = menu_data
	if config == null:
		return
	if not _built:
		_built = true
		_apply_static_texts()
		_build_chips()
	_restore_selection()
	_refresh()


## Текущая трасса как ресурс (null, пока конфиг не подключён).
func selected_track_resource() -> TrackConfigType:
	return _current_track()


## Трасса выбрана на 3D-доске: запоминаем её, пишем в RallyGame и обновляем карточку.
func select_track(index: int) -> void:
	if config == null or index < 0 or index >= config.track_count():
		return
	selected_track = index
	_sync_track()
	_refresh()


## Перед стартом из гаража: зафиксировать трассу и условия; для марафона
## на «Живой ленте» заранее составить календарь этапов.
func prepare_race() -> void:
	_sync_track()
	_sync_conditions()
	var game_node: Node = _get_game()
	if game_node == null:
		return
	if game_node.has_method("clear_marathon"):
		game_node.call("clear_marathon")
	var track: TrackConfigType = _current_track()
	if _marathon_stages > 0 and track != null and track.procedural and game_node.has_method("begin_marathon"):
		game_node.call("begin_marathon", _marathon_stages)


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


func _get_game() -> Node:
	if game != null:
		return game
	return get_node_or_null("/root/RallyGame")


func _restore_selection() -> void:
	selected_track = clampi(config.default_track_index, 0, maxi(0, config.track_count() - 1))
	selected_weather = clampi(config.default_weather_index, 0, maxi(0, config.weather_count() - 1))
	selected_profile = clampi(config.default_profile_index, 0, maxi(0, config.profile_count() - 1))
	selected_time = 0
	selected_transmission = 0
	var game_node: Node = _get_game()
	if game_node != null:
		selected_track = clampi(int(game_node.get("track_index")), 0, maxi(0, config.track_count() - 1))
		selected_weather = clampi(int(game_node.get("weather_index")), 0, maxi(0, config.weather_count() - 1))
		selected_profile = clampi(int(game_node.get("profile_index")), 0, maxi(0, config.profile_count() - 1))
		selected_time = clampi(int(game_node.get("time_index")), 0, maxi(0, layout().time_labels.size() - 1))
		selected_transmission = clampi(
			int(game_node.get("transmission_index")), 0, maxi(0, layout().transmission_labels.size() - 1)
		)


## Тексты и цвета из MenuLayout и UiTheme. Один раз, при первом открытии.
func _apply_static_texts() -> void:
	var t := theme_cfg()
	var cfg := layout()
	_column.add_theme_constant_override("separation", t.block_separation)
	_heading.text = cfg.tracks_heading
	_heading.add_theme_color_override("font_color", t.accent_soft)
	_heading.add_theme_font_size_override("font_size", t.font_group)
	_info_label.add_theme_color_override("font_color", Color(0.9, 0.94, 0.98, 1.0))
	_info_label.add_theme_font_size_override("font_size", t.font_caption)
	_best_label.add_theme_color_override("font_color", Color(0.5, 0.95, 0.55, 1.0))
	_best_label.add_theme_font_size_override("font_size", t.font_button_small)

	_conditions_box.add_theme_constant_override("separation", t.chip_separation)
	_seed_box.add_theme_constant_override("separation", 2)
	_seed_title.text = cfg.seed_heading
	_style_group_title(_seed_title)
	var seed_row := _seed_edit.get_parent() as HBoxContainer
	seed_row.add_theme_constant_override("separation", t.chip_separation + 2)
	_seed_edit.custom_minimum_size = Vector2(float(t.seed_field_width), float(t.chip_height))
	_seed_edit.tooltip_text = cfg.seed_field_tip
	_style_chip(_apply_button, cfg.apply_button, cfg.seed_apply_tip)
	_style_chip(_reroll_button, cfg.reroll_button, cfg.seed_reroll_tip)
	_style_chip(_copy_button, cfg.copy_button, cfg.seed_copy_tip)
	_seed_status.add_theme_color_override("font_color", t.text_muted)
	_seed_status.add_theme_font_size_override("font_size", t.font_caption)
	_seed_status.text = cfg.seed_hint
	var marathon_row := _marathon_label.get_parent() as HBoxContainer
	marathon_row.add_theme_constant_override("separation", t.chip_separation)
	_marathon_label.text = "РЕЖИМ"
	_style_group_title(_marathon_label)

	_weather_title.text = cfg.weather_heading
	_profile_title.text = cfg.profile_heading
	_time_title.text = cfg.time_heading
	_transmission_title.text = cfg.transmission_heading
	for title in [_weather_title, _profile_title, _time_title, _transmission_title]:
		_style_group_title(title)
	for flow in [_weather_flow, _profile_flow, _time_flow, _transmission_flow]:
		flow.add_theme_constant_override("h_separation", t.chip_separation)
		flow.add_theme_constant_override("v_separation", t.chip_separation)


func _style_group_title(label: Label) -> void:
	var t := theme_cfg()
	label.add_theme_color_override("font_color", t.accent_soft)
	label.add_theme_font_size_override("font_size", t.font_group)


## Кнопки-чипы: текст, подсказка, высота и шрифт — из темы и конфига.
func _style_chip(button: Button, text: String, tip: String) -> void:
	var t := theme_cfg()
	button.text = text
	button.tooltip_text = tip
	button.custom_minimum_size = Vector2(0.0, t.chip_height)
	button.add_theme_font_size_override("font_size", t.font_chip)


## Новый чип — копия ChipTemplate (он задаёт фокус и сцену), подпись и действие из кода.
func _make_choice_button(parent: Container, text: String, tip: String, action: Callable) -> Button:
	var button := _chip_template.duplicate() as Button
	button.visible = true
	_style_chip(button, text, tip)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


## Погода, профиль, время и коробка: число чипов задаёт конфиг и MenuLayout.
func _build_chips() -> void:
	var cfg := layout()
	weather_buttons.clear()
	for i in range(config.weather_count()):
		var preset: WeatherType = config.get_weather(i) as WeatherType
		if preset == null:
			continue
		var text: String = preset.short_name if not preset.short_name.is_empty() else preset.display_name
		var tip: String = "%s\n%s" % [preset.display_name, preset.description]
		weather_buttons.append(_make_choice_button(_weather_flow, text, tip, _on_weather_pressed.bind(i)))

	profile_buttons.clear()
	for i in range(config.profile_count()):
		var preset: ProfileType = config.get_profile(i) as ProfileType
		if preset == null:
			continue
		profile_buttons.append(_make_choice_button(
			_profile_flow,
			preset.display_name,
			"%s\n%s" % [preset.display_name, preset.description],
			_on_profile_pressed.bind(i)
		))

	# Время суток: отдельно от погоды (день с дождём, ночь в тумане и т.д.).
	time_buttons.clear()
	for i in range(cfg.time_labels.size()):
		var tip: String = cfg.time_tips[i] if i < cfg.time_tips.size() else cfg.time_labels[i]
		time_buttons.append(_make_choice_button(_time_flow, cfg.time_labels[i], tip, _on_time_pressed.bind(i)))

	# Коробка передач: отдельный выбор игрока, не привязан к пресету машины.
	transmission_buttons.clear()
	for i in range(cfg.transmission_labels.size()):
		var tip: String = cfg.transmission_tips[i] if i < cfg.transmission_tips.size() else cfg.transmission_labels[i]
		transmission_buttons.append(_make_choice_button(
			_transmission_flow, cfg.transmission_labels[i], tip, _on_transmission_pressed.bind(i)
		))


func _on_marathon_selected(index: int) -> void:
	_marathon_stages = _marathon_choice.get_item_id(index)
	_seed_status.text = "Марафон: случайные трассы и общее время. Сид выше — для одиночного заезда." if _marathon_stages > 0 else layout().seed_hint


func _on_weather_pressed(index: int) -> void:
	selected_weather = index
	_sync_conditions()
	_refresh()


func _on_profile_pressed(index: int) -> void:
	selected_profile = index
	_sync_conditions()
	_refresh()


func _on_time_pressed(index: int) -> void:
	selected_time = index
	_sync_conditions()
	_refresh()


func _on_transmission_pressed(index: int) -> void:
	selected_transmission = index
	_sync_conditions()
	_refresh()


func _on_seed_reroll_pressed() -> void:
	var track: TrackConfigType = _current_track()
	if track == null or not track.procedural:
		return
	var game_node: Node = _get_game()
	if game_node != null and game_node.has_method("reroll_live_seed"):
		game_node.call("reroll_live_seed", track)
	else:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		track.generation_seed = rng.randi_range(layout().seed_min_value, layout().seed_max_value)
	if _seed_status != null:
		_seed_status.text = layout().seed_status_new % track.generation_seed
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
			_seed_status.text = layout().seed_status_invalid
		return
	var value: int = clampi(text.to_int(), layout().seed_min_value, layout().seed_max_value)
	if value == track.generation_seed:
		if _seed_status != null:
			_seed_status.text = layout().seed_status_same
		return
	track.generation_seed = value
	var game_node: Node = _get_game()
	if game_node != null and game_node.has_method("remember_live_seed"):
		game_node.call("remember_live_seed", track.id, value)
	if _seed_status != null:
		_seed_status.text = layout().seed_status_applied % value
	_refresh()


func _on_seed_copy_pressed() -> void:
	var track: TrackConfigType = _current_track()
	if track == null:
		return
	DisplayServer.clipboard_set(str(track.generation_seed))
	if _seed_status != null:
		_seed_status.text = layout().seed_status_copied % track.generation_seed


func _current_track() -> TrackConfigType:
	return config.get_track(selected_track) as TrackConfigType


## Погода, профиль, время суток и коробка живут в RallyGame: сцена этапа берёт их оттуда.
func _sync_conditions() -> void:
	var game_node: Node = _get_game()
	if game_node == null:
		return
	game_node.call("select_weather", selected_weather)
	game_node.call("select_profile", selected_profile)
	game_node.call("select_time", selected_time)
	game_node.call("select_transmission", selected_transmission)


## Карточка заезда: трасса + погода, характер полотна и время.
func _track_info_text(
	track: TrackConfigType, _setup: CarSetupType, weather: WeatherType, profile: ProfileType, time_choice: int
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
	# Аркадный генератор использует свой пульт геометрии поверх копии
	# RallyTrackConfig. Показываем итоговую ширину, а не устаревшие 10 м из
	# ресурса-носителя, иначе меню противоречит дороге в заезде.
	if track.id == "arcade_endless":
		var arcade_cfg := ResourceLoader.load("res://data/stage/default_arcade_settings.tres") as ArcadeSettingsType
		if arcade_cfg != null:
			width = arcade_cfg.road_half_width_override * 2.0 if arcade_cfg.road_half_width_override > 0.001 else width * arcade_cfg.road_width_scale
	var weather_line: String = "ПОГОДА: как на трассе"
	if weather != null:
		weather_line = "ПОГОДА: %s" % weather.display_name
		var weather_summary: String = weather.get_summary()
		if not weather_summary.is_empty() and weather_summary != weather.display_name:
			weather_line += "  •  %s" % weather_summary
		grip *= weather.grip_scale
	var resolved_time: int = WeatherType.resolve_time_choice(time_choice, weather, track.night_mode)
	var time_names: PackedStringArray = layout().time_mode_names
	var time_name_index: int = clampi(resolved_time - 1, 0, maxi(0, time_names.size() - 1))
	var time_name: String = time_names[time_name_index] if not time_names.is_empty() else (
		"НОЧЬ" if WeatherType.resolve_night_choice(time_choice, weather, track.night_mode) else "ДЕНЬ"
	)
	var time_line: String = "ВРЕМЯ: %s" % time_name
	if time_choice == 0:
		time_line += " (как на трассе)"
	var engine_line: String = ""
	return "%s\n\n%s\n\n%s\n%s\n%s\n%s\n" % [
		track.display_name,
		track.description,
		length_line,
		profile_line,
		weather_line,
		time_line,
	] + "ШИРИНА: %.1f м  •  КОЧКИ: %.0f мм\n" % [
		width, bumps_mm,
	] + "СЦЕПЛЕНИЕ: %.2f  •  СЛОЖНОСТЬ: %d/5\n" % [
		grip, track.difficulty,
	] + "ЦЕЛЬ: %s%s" % [
		_format_time(track.target_time),
		engine_line,
	]


func _is_conditions_modified(weather: WeatherType, profile: ProfileType, time_choice: int) -> bool:
	if time_choice != 0:
		return true
	if weather != null and String(weather.id) != "default":
		return true
	return profile != null and String(profile.id) != "gravel"


func _conditions_short(weather: WeatherType, profile: ProfileType, time_choice: int) -> String:
	var parts := PackedStringArray()
	if weather != null:
		parts.append(weather.display_name)
	if profile != null:
		parts.append(profile.display_name)
	if time_choice != 0 and time_choice < layout().time_labels.size():
		parts.append(layout().time_labels[time_choice])
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


func _format_time(seconds: float) -> String:
	return "%02d:%06.3f" % [floori(seconds / 60.0), fmod(seconds, 60.0)]


func _sync_track() -> void:
	var game_node: Node = _get_game()
	if game_node == null:
		return
	# select_track() обновляет и индекс, и ресурс current_track, и сохраняет выбор.
	game_node.call("select_track", selected_track)


## Перерисовать подсветку выбора, карточку и карту текущей трассы.
func _refresh() -> void:
	if config == null:
		return
	var t := theme_cfg()
	_paint_choices(weather_buttons, selected_weather, t)
	_paint_choices(profile_buttons, selected_profile, t)
	_paint_choices(time_buttons, selected_time, t)
	_paint_choices(transmission_buttons, selected_transmission, t)

	var track: TrackConfigType = _current_track()
	var weather: WeatherType = config.get_weather(selected_weather) as WeatherType
	var profile: ProfileType = config.get_profile(selected_profile) as ProfileType
	if track == null:
		return
	_refresh_seed_panel(track)
	if _preview != null and _preview is StagePreviewType:
		_preview.call("set_conditions", weather, profile)
		_preview.call("set_track", track)
	if _info_label != null:
		_info_label.text = _track_info_text(track, null, weather, profile, selected_time)
	if _best_label != null:
		var key: String = track.get_record_key()
		var game_node: Node = _get_game()
		if game_node != null:
			if game_node.has_method("record_key_for"):
				key = String(game_node.call("record_key_for", track))
			var best: float = float(game_node.call("get_best_time", key))
			var note: String = ""
			if _is_conditions_modified(weather, profile, selected_time):
				note = "  •  %s" % _conditions_short(weather, profile, selected_time)
			_best_label.text = layout().best_time_label % [
				note, _format_time(best) if best > 0.0 else "—"
			]
			var menu_veh_id: String = ""
			if game_node.has_method("get_race_vehicle_id"):
				menu_veh_id = String(game_node.call("get_race_vehicle_id"))
			if GhostRecordingType.has_saved_ghost(key, menu_veh_id, true) or GhostRecordingType.has_saved_ghost(key, menu_veh_id, false):
				_best_label.text += layout().ghost_available_badge
		else:
			_best_label.text = layout().best_time_empty


func _paint_choices(buttons: Array[Button], chosen: int, t: UiThemeType) -> void:
	for i in range(buttons.size()):
		buttons[i].modulate = t.condition_selected_color if i == chosen else t.condition_idle_color


## Подсветка на доске (наведение, стрелки): показать карточку и карту трассы,
## но ещё не записывать выбор в RallyGame — это делает select_track().
func preview_track(index: int) -> void:
	if config == null or index < 0 or index >= config.track_count():
		return
	if index == selected_track:
		return
	selected_track = index
	_refresh()
