## Автозагрузка RallyGame. Держит выбор меню между сценами и рекорды.
## Настраивается в project.godot -> Autoload; путь к конфигу можно заменить ниже.
extends Node

const GameConfigType = preload("res://scripts/data/rally_game_config.gd")

signal selection_changed
signal race_started

@export_file("*.tres") var config_path: String = "res://data/rally_game_config.tres"
@export var records_path: String = "user://rally_records.cfg"

var config: GameConfigType = null
var track_index: int = 0
var setup_index: int = 0
var random_mode: bool = false
var map_seed: int = 1337
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
	random_mode = config.start_random_mode if config != null else false
	current_track = config.get_track(track_index) if config != null else null
	current_setup = config.get_setup(setup_index) if config != null else null
	var start_seed: Variant = current_track.get("map_seed") if current_track != null else null
	map_seed = int(start_seed) if start_seed != null else 1337


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


func make_random_seed() -> int:
	randomize()
	return int(abs(randi() % 9999999)) + 1


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
	var track_seed: Variant = current_track.get("map_seed") if current_track != null else null
	if track_seed != null:
		map_seed = int(track_seed)
	selection_changed.emit()


func select_setup(index: int) -> void:
	setup_index = clampi(index, 0, maxi(0, setup_count() - 1))
	current_setup = get_setup(setup_index)
	selection_changed.emit()


func set_seed(value: int) -> void:
	map_seed = absi(value) + 1
	selection_changed.emit()


func set_random_mode(enabled: bool) -> void:
	random_mode = enabled
	selection_changed.emit()


## Новый сид перед каждым заездом в случайном режиме.
func prepare_race_seed() -> void:
	if random_mode or (current_track != null and bool(current_track.get("random_seed"))):
		map_seed = make_random_seed()


func start_race() -> void:
	prepare_race_seed()
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
