## Главный список данных игры. Откройте res://data/rally_game_config.tres
## в инспекторе, чтобы добавить/убрать трассы и конфигурации машины.
## Порядок элементов в массивах = порядок в меню. Горячие клавиши F1..F5
## (`track_hotkey_count`) достаются первым пяти трассам.
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
## Машины игры: кузов, колёса, звук мотора и пресеты каждой
## (res://data/vehicles/*.tres). Первая машина — машина по умолчанию.
## Добавить новую = положить новый .tres, код править не нужно.
@export var vehicles: Array[Resource] = []
## Все готовые пресеты игры (файлы из res://data/setups/). Машина ссылается
## на нужные ей по id (RallyVehicle.setup_ids), поэтому один пресет может
## достаться нескольким машинам без копирования файла.
@export var all_setups: Array[Resource] = []
## Массив ресурсов RallyWeatherConfig (файлы из res://data/weather/).
@export var weather_presets: Array[Resource] = []
## Массив ресурсов RallyTrackProfile (файлы из res://data/profiles/).
@export var track_profiles: Array[Resource] = []

@export_group("Значения по умолчанию")
@export var default_track_index: int = 0
@export var default_setup_index: int = 0
@export var default_weather_index: int = 0
@export var default_profile_index: int = 0

@export_group("Тест-полигон")
## Лёгкая кольцевая трасса для проверки эффектов, погоды, камеры и пропсов
## (data/tracks/stage_testpad.tres). На неё ведёт отдельная кнопка главного
## экрана: заезд начинается без выбора трассы и без гаража. Пусто — кнопки нет.
@export var test_track: Resource = null

@export_group("Сцены")
@export_file("*.tscn") var menu_scene: String = "res://scenes/main_menu.tscn"
@export_file("*.tscn") var stage_scene: String = "res://scenes/rally_stage.tscn"
@export var records_path: String = "user://rally_records.cfg"


func track_count() -> int:
	return tracks.size()


## Идентификатор машины по умолчанию: первая в списке (обычно Mitsubishi).
func default_vehicle_id() -> String:
	if vehicles.is_empty():
		return "mitsubishi"
	return String((vehicles[0] as RallyVehicle).id)


## Все идентификаторы машин в порядке меню.
func vehicle_ids() -> Array[String]:
	var ids: Array[String] = []
	for resource in vehicles:
		var vehicle := resource as RallyVehicle
		if vehicle != null and not vehicle.id.is_empty():
			ids.append(vehicle.id)
	return ids


## Ресурс машины по идентификатору. Неизвестный id — машина по умолчанию:
## сохранение со старой машиной не должно ронять меню.
func vehicle(vehicle_id: String) -> RallyVehicle:
	var fallback: RallyVehicle = vehicles[0] as RallyVehicle if not vehicles.is_empty() else null
	for resource in vehicles:
		var candidate := resource as RallyVehicle
		if candidate != null and candidate.id == vehicle_id:
			return candidate
	return fallback


func has_vehicle(vehicle_id: String) -> bool:
	for resource in vehicles:
		var candidate := resource as RallyVehicle
		if candidate != null and candidate.id == vehicle_id:
			return true
	return false


## Пресет по его id — независимо от того, какой машине он принадлежит.
func find_setup(setup_id: String) -> Resource:
	for resource in all_setups:
		var setup := resource as RallyCarSetup
		if setup != null and setup.id == setup_id:
			return setup
	return null


## Список пресетов выбранной машины. Неизвестный id — список машины по
## умолчанию, поэтому старые вызовы без аргумента видят те же 10 пунктов.
func setups_for(vehicle_id: String = "") -> Array:
	var target := vehicle_id if not vehicle_id.is_empty() else default_vehicle_id()
	var selected := vehicle(target)
	return selected.setups(self) if selected != null else []


func setup_count(vehicle_id: String = "") -> int:
	return setups_for(vehicle_id).size()


func get_track(index: int) -> Resource:
	if tracks.is_empty():
		return null
	return tracks[clampi(index, 0, tracks.size() - 1)]


func get_setup(index: int, vehicle_id: String = "") -> Resource:
	var list := setups_for(vehicle_id)
	if list.is_empty():
		return null
	return list[clampi(index, 0, list.size() - 1)]


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
