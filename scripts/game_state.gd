## Автозагрузка RallyGame. Держит выбор меню между сценами и рекорды.
## Карты больше не генерируются случайно: у каждой трассы свой ресурс
## (data/tracks/*.tres) и свой рекорд по id трассы.
##
## Здесь же живут ПОГОДА, ХАРАКТЕР ТРАССЫ и сид «Живой ленты»:
##   * погода и профиль полотна выбираются в меню и запоминаются в
##     user://rally_conditions.cfg;
##   * сид процедурной трассы сохраняется там же, поэтому «перегенерировать»
##     можно сколько угодно — последний сид переживёт перезапуск игры,
##     а трасса по нему всегда собирается заново один в один.
extends Node

const GameConfigType = preload("res://scripts/data/rally_game_config.gd")
const CarSetupType = preload("res://scripts/data/rally_car_setup.gd")
const CarCustomization = preload("res://scripts/car_customization.gd")

signal selection_changed
signal race_started
## Изменилась погода или характер трассы.
signal conditions_changed
## У «Живой ленты» сменился и сохранён сид генерации.
signal live_seed_changed(track_id: String, seed_value: int)

@export_file("*.tres") var config_path: String = "res://data/rally_game_config.tres"
@export var records_path: String = "user://rally_records.cfg"
## Настройки условий заезда и сохранённые сиды. Не в res:// — файл пишется
## во время игры (в экспортированной сборке res:// только для чтения).
@export var conditions_path: String = "user://rally_conditions.cfg"

var config: GameConfigType = null
var track_index: int = 0
var setup_index: int = 0
var weather_index: int = 0
var profile_index: int = 0
var current_track: Resource = null
var current_setup: Resource = null
var current_weather: Resource = null
var current_profile: Resource = null
var last_time: float = 0.0
var is_new_record: bool = false
## Только заезд, запущенный из меню, подменяет сценический setup_override.
## При прямом F6 настройки машины, назначенные в сцене, остаются приоритетными.
var _race_uses_selected_setup: bool = false
var _records := ConfigFile.new()
var _conditions := ConfigFile.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_config()
	load_records()
	load_conditions()
	track_index = clampi(config.default_track_index, 0, maxi(0, config.track_count() - 1)) if config != null else 0
	setup_index = clampi(config.default_setup_index, 0, maxi(0, config.setup_count() - 1)) if config != null else 0
	weather_index = 0
	profile_index = 0
	if config != null:
		weather_index = clampi(
			config.default_weather_index, 0, maxi(0, config.weather_count() - 1)
		)
		profile_index = clampi(
			config.default_profile_index, 0, maxi(0, config.profile_count() - 1)
		)
	_restore_saved_selection()
	_apply_saved_live_seeds()


func load_config() -> void:
	if config != null:
		return
	if ResourceLoader.exists(config_path):
		var loaded: Resource = ResourceLoader.load(config_path)
		if loaded is GameConfigType:
			config = loaded
			if not config.records_path.is_empty():
				records_path = config.records_path
	if config == null:
		config = GameConfigType.new()


func load_records() -> void:
	_records.clear()
	_records.load(records_path)


func save_records() -> void:
	_records.save(records_path)


# ------------------------------------------------------- условия и сиды


func load_conditions() -> void:
	_conditions.clear()
	_conditions.load(conditions_path)


func save_conditions() -> Error:
	return _conditions.save(conditions_path)


## Выбор из прошлой сессии (трасса, сетап, погода, профиль) — если он есть.
func _restore_saved_selection() -> void:
	if _conditions.has_section("selection"):
		track_index = clampi(
			int(_conditions.get_value("selection", "track_index", track_index)),
			0, maxi(0, track_count() - 1)
		)
		setup_index = clampi(
			int(_conditions.get_value("selection", "setup_index", setup_index)),
			0, maxi(0, setup_count() - 1)
		)
		weather_index = clampi(
			int(_conditions.get_value("selection", "weather_index", weather_index)),
			0, maxi(0, weather_count() - 1)
		)
		profile_index = clampi(
			int(_conditions.get_value("selection", "profile_index", profile_index)),
			0, maxi(0, profile_count() - 1)
		)
	current_track = get_track(track_index)
	current_setup = get_custom_setup(setup_index)
	current_weather = get_weather(weather_index)
	current_profile = get_profile(profile_index)


func _save_selection() -> void:
	_conditions.set_value("selection", "track_index", track_index)
	_conditions.set_value("selection", "setup_index", setup_index)
	_conditions.set_value("selection", "weather_index", weather_index)
	_conditions.set_value("selection", "profile_index", profile_index)
	save_conditions()


## Сид, который был сохранён для этой трассы (или fallback).
func get_saved_seed(track_id: String, fallback: int) -> int:
	if track_id.is_empty():
		return fallback
	return int(_conditions.get_value("seeds", track_id, fallback))


## Запомнить сид «Живой ленты». Именно этот вызов делает сид «сохранённым»:
## при следующем запуске трасса соберётся из него же.
func remember_live_seed(track_id: String, seed_value: int) -> void:
	if track_id.is_empty():
		return
	_conditions.set_value("seeds", track_id, seed_value)
	save_conditions()
	live_seed_changed.emit(track_id, seed_value)


## Наложить сохранённый сид на ресурс процедурной трассы.
func apply_saved_seed(track: Resource) -> void:
	if track == null:
		return
	if not bool(track.get("procedural")):
		return
	var track_id: String = String(track.get("id"))
	var current: int = int(track.get("generation_seed"))
	track.set("generation_seed", get_saved_seed(track_id, current))


func _apply_saved_live_seeds() -> void:
	if config == null:
		return
	for track in config.tracks:
		apply_saved_seed(track)


## Новый случайный сид для процедурной трассы. Сид сразу сохраняется,
## поэтому «перегенерировать» не теряет карту: её всегда можно вернуть.
func reroll_live_seed(track: Resource) -> int:
	if track == null:
		return 0
	var current: int = int(track.get("generation_seed"))
	var value: int = current
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# Один и тот же сид не выдаём дважды подряд: иначе кнопка «не работает».
	for attempt in range(8):
		value = rng.randi_range(1, 999999999)
		if value != current:
			break
	track.set("generation_seed", value)
	remember_live_seed(String(track.get("id")), value)
	return value


func get_best_time(key: String) -> float:
	return float(_records.get_value("records", key, 0.0))


## Возвращает true, если это новый рекорд.
func submit_time(key: String, time: float) -> bool:
	var best: float = get_best_time(key)
	if time <= 0.0 or (best > 0.0 and time >= best):
		return false
	_records.set_value("records", key, time)
	save_records()
	return true


## Рекорд на контрольной точке (split). Ключ: "<track_id>_cp<i>".
func submit_split(key: String, time: float) -> bool:
	var best: float = get_best_split(key)
	if time <= 0.0 or (best > 0.0 and time >= best):
		return false
	_records.set_value("splits", key, time)
	save_records()
	return true


func get_best_split(key: String) -> float:
	return float(_records.get_value("splits", key, 0.0))


func get_track(index: int) -> Resource:
	return config.get_track(index) if config != null else null


func get_setup(index: int) -> Resource:
	return config.get_setup(index) if config != null else null


func get_weather(index: int) -> Resource:
	return config.get_weather(index) if config != null else null


func get_profile(index: int) -> Resource:
	return config.get_profile(index) if config != null else null


func track_count() -> int:
	return config.track_count() if config != null else 0


func setup_count() -> int:
	return config.setup_count() if config != null else 0


func weather_count() -> int:
	return config.weather_count() if config != null else 0


func profile_count() -> int:
	return config.profile_count() if config != null else 0


func select_track(index: int) -> void:
	track_index = clampi(index, 0, maxi(0, track_count() - 1))
	current_track = get_track(track_index)
	_save_selection()
	selection_changed.emit()


func select_setup(index: int) -> void:
	setup_index = clampi(index, 0, maxi(0, setup_count() - 1))
	current_setup = get_custom_setup(setup_index)
	_save_selection()
	selection_changed.emit()


## Персональная копия пресета; старые ключи читаются по той же схеме,
## недостающие или некорректные значения берутся из оригинального .tres.
func get_custom_setup(index: int) -> CarSetupType:
	var base := get_setup(index) as CarSetupType
	if base == null:
		return null
	var result := base.duplicate(true) as CarSetupType
	CarCustomization.read_setup(_conditions, "garage_" + base.id, result, base)
	return result


func save_custom_setup(index: int, setup: CarSetupType) -> bool:
	return save_custom_setups({index: setup})


## Сохраняем все открытые черновики за одну запись, сохраняя условия и рекорды.
## При ошибке файловой системы рабочий конфиг и текущий сетап не меняются.
func save_custom_setups(setups: Dictionary) -> bool:
	var staged := ConfigFile.new()
	for section in _conditions.get_sections():
		for key in _conditions.get_section_keys(section):
			staged.set_value(section, key, _conditions.get_value(section, key))
	for index in setups:
		if not index is int or index < 0 or index >= setup_count():
			return false
		var base := get_setup(index) as CarSetupType
		var setup := setups[index] as CarSetupType
		if base == null or setup == null:
			return false
		var safe := CarCustomization.normalized_setup(setup, base)
		CarCustomization.write_setup(staged, "garage_" + base.id, safe)
	var error := staged.save(conditions_path)
	if error != OK:
		push_warning("Не удалось сохранить настройки гаража: %s" % error_string(error))
		return false
	_conditions = staged
	current_setup = get_custom_setup(setup_index)
	selection_changed.emit()
	return true


func select_weather(index: int) -> void:
	weather_index = clampi(index, 0, maxi(0, weather_count() - 1))
	current_weather = get_weather(weather_index)
	_save_selection()
	conditions_changed.emit()


func select_profile(index: int) -> void:
	profile_index = clampi(index, 0, maxi(0, profile_count() - 1))
	current_profile = get_profile(profile_index)
	_save_selection()
	conditions_changed.emit()


## Ключ рекорда с учётом условий: на одном и том же спецучастке мокрая
## глина и сухой асфальт — разные заезды, и рекорды у них разные.
func record_key_for(track: Resource) -> String:
	if track == null:
		return ""
	var base: String = ""
	if track.has_method("get_record_key"):
		base = String(track.call("get_record_key"))
	else:
		base = String(track.get("id"))
	var weather_id: String = conditions_id(current_weather)
	var profile_id: String = conditions_id(current_profile)
	if weather_id == "default" and profile_id == "gravel":
		# Нейтральные условия — прежний ключ без приставки: рекорды,
		# поставленные до появления погоды, остаются на месте.
		return base
	return "%s|%s|%s" % [base, weather_id, profile_id]


static func conditions_id(resource: Resource) -> String:
	if resource == null:
		return "default"
	var value: String = String(resource.get("id"))
	return value if not value.is_empty() else "default"


func get_race_setup_override() -> CarSetupType:
	if not _race_uses_selected_setup:
		return null
	return current_setup as CarSetupType


func start_race() -> void:
	_race_uses_selected_setup = true
	last_time = 0.0
	is_new_record = false
	get_tree().paused = false
	race_started.emit()
	var track_name: String = ""
	if current_track != null:
		track_name = current_track.get("display_name")
	begin_loading(track_name)
	# Пара кадров, чтобы экран загрузки успел отрисоваться ПЕРЕД тяжёлым
	# _ready() сцены этапа: иначе пользователь видел бы застывшее меню.
	await get_tree().process_frame
	await get_tree().process_frame
	var scene_path: String = config.stage_scene if config != null and not config.stage_scene.is_empty() else "res://scenes/rally_stage.tscn"
	call_deferred("_change_scene", scene_path)


func restart_race() -> void:
	start_race()


func goto_menu() -> void:
	_race_uses_selected_setup = false
	get_tree().paused = false
	finish_loading()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var scene_path: String = config.menu_scene if config != null and not config.menu_scene.is_empty() else "res://scenes/main_menu.tscn"
	call_deferred("_change_scene", scene_path)


func quit_game() -> void:
	get_tree().paused = false
	get_tree().quit()


func _change_scene(scene_path: String) -> void:
	if not ResourceLoader.exists(scene_path):
		push_error("RallyGame: сцена не найдена: " + scene_path)
		return
	get_tree().change_scene_to_file(scene_path)


# ---------------------------------------------------------------- загрузка

## Экран загрузки живёт на этом autoload, поэтому переживает смену сцены:
## его видно и между меню и заездом, пока мир этапа генерируется по кадрам.
var _loading_root: CanvasLayer = null
var _loading_title: Label = null
var _loading_track: Label = null
var _loading_status: Label = null
var _loading_bar: ProgressBar = null


func _build_loading_screen() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.012, 0.022, 0.032, 1.0)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var eyebrow := Label.new()
	eyebrow.text = "RALLY  •  ЗАГРУЗКА"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_color_override("font_color", Color(0.98, 0.45, 0.06, 1.0))
	eyebrow.add_theme_font_size_override("font_size", 13)
	box.add_child(eyebrow)

	_loading_title = Label.new()
	_loading_title.text = "ГЕНЕРАЦИЯ СПЕЦУЧАСТКА"
	_loading_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_title.add_theme_color_override("font_color", Color(0.96, 0.97, 0.99, 1.0))
	_loading_title.add_theme_font_size_override("font_size", 30)
	box.add_child(_loading_title)

	_loading_track = Label.new()
	_loading_track.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_track.add_theme_color_override("font_color", Color(0.62, 0.73, 0.83, 1.0))
	_loading_track.add_theme_font_size_override("font_size", 16)
	box.add_child(_loading_track)

	var progress_row := HBoxContainer.new()
	progress_row.add_theme_constant_override("separation", 12)
	box.add_child(progress_row)

	_loading_bar = ProgressBar.new()
	_loading_bar.custom_minimum_size = Vector2(420.0, 18.0)
	_loading_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loading_bar.min_value = 0.0
	_loading_bar.max_value = 1.0
	_loading_bar.step = 0.001
	_loading_bar.show_percentage = false
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.05, 0.075, 0.10, 1.0)
	bar_bg.set_border_width_all(1)
	bar_bg.border_color = Color(0.32, 0.42, 0.52, 0.6)
	bar_bg.set_corner_radius_all(6)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.98, 0.45, 0.06, 1.0)
	bar_fill.set_corner_radius_all(6)
	_loading_bar.add_theme_stylebox_override("background", bar_bg)
	_loading_bar.add_theme_stylebox_override("fill", bar_fill)
	progress_row.add_child(_loading_bar)

	var percent := Label.new()
	percent.name = "Percent"
	percent.custom_minimum_size.x = 44.0
	percent.add_theme_color_override("font_color", Color(0.68, 0.78, 0.86, 1.0))
	percent.add_theme_font_size_override("font_size", 13)
	percent.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	percent.text = "0 %"
	_loading_bar.set_meta("percent_label", percent)
	progress_row.add_child(percent)

	_loading_status = Label.new()
	_loading_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_status.add_theme_color_override("font_color", Color(0.55, 0.66, 0.76, 1.0))
	_loading_status.add_theme_font_size_override("font_size", 14)
	box.add_child(_loading_status)

	var note := Label.new()
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_color_override("font_color", Color(0.45, 0.55, 0.64, 0.8))
	note.add_theme_font_size_override("font_size", 12)
	note.text = "Трасса строится прямо сейчас — машина встанет на линию старта."
	box.add_child(note)
	_loading_root = layer
	add_child(_loading_root)


func begin_loading(track_name: String = "") -> void:
	if _loading_root == null:
		_build_loading_screen()
	get_tree().paused = false
	_loading_root.visible = true
	if _loading_track != null:
		_loading_track.text = String(track_name).to_upper()
	set_loading_progress(0.0, "Подготовка данных трассы…")


func set_loading_progress(value: float, status: String) -> void:
	if _loading_root == null or not _loading_root.visible:
		return
	if _loading_bar != null:
		_loading_bar.value = clampf(value, 0.0, 1.0)
		var percent: Label = _loading_bar.get_meta("percent_label", null)
		if percent != null:
			percent.text = "%d %%" % int(round(_loading_bar.value * 100.0))
	if _loading_status != null and not status.is_empty():
		_loading_status.text = status


func finish_loading() -> void:
	if _loading_root != null:
		_loading_root.visible = false
