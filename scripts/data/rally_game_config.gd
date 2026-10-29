## Главный список данных игры. Откройте res://data/rally_game_config.tres
## в инспекторе, чтобы добавить/убрать трассы и конфигурации машины.
## Порядок элементов в массивах = порядок в меню и горячие клавиши F1..F5.
@tool
class_name RallyGameConfig
extends Resource

@export_group("Меню")
@export var title: String = "RALLY 4.7"
@export var subtitle: String = "MITSUBISHI LANCER EVOLUTION"
@export var accent_color: Color = Color(1.0, 0.58, 0.08, 1)

@export_group("Списки")
## Массив ресурсов RallyTrackConfig (файлы из res://data/tracks/).
@export var tracks: Array[Resource] = []
## Массив ресурсов RallyCarSetup (файлы из res://data/setups/).
@export var car_setups: Array[Resource] = []
## Массив ресурсов RallyWeatherConfig (файлы из res://data/weather/).
@export var weather_presets: Array[Resource] = []
## Массив ресурсов RallyTrackProfile (файлы из res://data/profiles/).
@export var track_profiles: Array[Resource] = []

@export_group("Значения по умолчанию")
@export var default_track_index: int = 0
@export var default_setup_index: int = 0
@export var default_weather_index: int = 0
@export var default_profile_index: int = 0

@export_group("Сцены")
@export_file("*.tscn") var menu_scene: String = "res://scenes/main_menu.tscn"
@export_file("*.tscn") var stage_scene: String = "res://scenes/rally_stage.tscn"
@export var records_path: String = "user://rally_records.cfg"


func track_count() -> int:
	return tracks.size()


func setup_count() -> int:
	return car_setups.size()


func get_track(index: int) -> Resource:
	if tracks.is_empty():
		return null
	return tracks[clampi(index, 0, tracks.size() - 1)]


func get_setup(index: int) -> Resource:
	if car_setups.is_empty():
		return null
	return car_setups[clampi(index, 0, car_setups.size() - 1)]


func weather_count() -> int:
	return weather_presets.size()


func get_weather(index: int) -> Resource:
	if weather_presets.is_empty():
		return null
	return weather_presets[clampi(index, 0, weather_presets.size() - 1)]


func profile_count() -> int:
	return track_profiles.size()


func get_profile(index: int) -> Resource:
	if track_profiles.is_empty():
		return null
	return track_profiles[clampi(index, 0, track_profiles.size() - 1)]
