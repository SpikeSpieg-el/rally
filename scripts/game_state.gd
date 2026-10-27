## Автозагрузка RallyGame. Держит выбор меню между сценами и рекорды.
## Карты больше не генерируются случайно: у каждой трассы свой ресурс
## (data/tracks/*.tres) и свой рекорд по id трассы.
extends Node

const GameConfigType = preload("res://scripts/data/rally_game_config.gd")

signal selection_changed
signal race_started

@export_file("*.tres") var config_path: String = "res://data/rally_game_config.tres"
@export var records_path: String = "user://rally_records.cfg"

var config: GameConfigType = null
var track_index: int = 0
var setup_index: int = 0
var current_track: Resource = null
var current_setup: Resource = null
var last_time: float = 0.0
var is_new_record: bool = false
var _records := ConfigFile.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_config()
	load_records()
	track_index = clampi(config.default_track_index, 0, maxi(0, config.track_count() - 1)) if config != null else 0
	setup_index = clampi(config.default_setup_index, 0, maxi(0, config.setup_count() - 1)) if config != null else 0
	current_track = config.get_track(track_index) if config != null else null
	current_setup = config.get_setup(setup_index) if config != null else null


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


func track_count() -> int:
	return config.track_count() if config != null else 0


func setup_count() -> int:
	return config.setup_count() if config != null else 0


func select_track(index: int) -> void:
	track_index = clampi(index, 0, maxi(0, track_count() - 1))
	current_track = get_track(track_index)
	selection_changed.emit()


func select_setup(index: int) -> void:
	setup_index = clampi(index, 0, maxi(0, setup_count() - 1))
	current_setup = get_setup(setup_index)
	selection_changed.emit()


func start_race() -> void:
	last_time = 0.0
	is_new_record = false
	get_tree().paused = false
	race_started.emit()
	var scene_path: String = config.stage_scene if config != null and not config.stage_scene.is_empty() else "res://scenes/rally_stage.tscn"
	call_deferred("_change_scene", scene_path)


func restart_race() -> void:
	start_race()


func goto_menu() -> void:
	get_tree().paused = false
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
