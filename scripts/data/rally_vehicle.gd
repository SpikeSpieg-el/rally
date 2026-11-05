## Одна машина игры: кузов, колёса, звук мотора и её пресеты.
## Физика, камеры, HUD и правила заезда остаются общими для всех машин —
## здесь лежит только то, что у машин действительно разное.
##
## Чтобы добавить машину, скопируйте data/vehicles/subaru.tres, поменяйте
## id, название и пути к модели/звуку. Код править не нужно.
@tool
class_name RallyVehicle
extends Resource

@export_group("Описание")
## Короткий идентификатор: попадает в сохранения и в поле vehicle_id машины.
@export var id: String = "mitsubishi"
@export var display_name: String = "MITSUBISHI LANCER EVOLUTION"
## Пресеты этой машины: id сетапов из data/rally_game_config.tres.
## Храним id, а не пути: пресет живёт в одном месте, и добавить машину —
## значит перечислить её сетапы, а не копировать ресурсы.
@export var setup_ids: PackedStringArray = []

@export_group("Кузов")
## Сцена с импортированной моделью кузова. Пусто — машина ездит на кузове
## сцены заезда (low poly lance evo), меняются только колёса.
@export_file("*.tscn") var model_scene: String = ""
## Узел внутри model_scene, который подставляется в машину. Пусто — корень.
@export var model_root: String = "Sketchfab_Scene"
## Спрятать кузов сцены заезда, когда установлена model_scene.
@export var hide_scene_body: bool = true
## Имена мешей колёс в model_scene в порядке FL, FR, RL, RR. Пусто — колёса
## сцены заезда остаются как есть (тогда меняется только кузов).
@export var wheel_names: Array[String] = []
## Прятать интерьер импортированной модели. Нужно, если у модели нет салона
## и он рисуется отдельно; салона в реестре нет — его делает автор сцены.
@export var hide_model_interior: bool = false

@export_group("Внешность")
## Красить кузов по пресету (цвет, ливрея, цвет дисков). У машины без
## Mitsubishi-разметки материалов выключите, иначе красить нечего.
@export var uses_livery_presets: bool = true

@export_group("Звук мотора")
## Папка с лупами engine_<об/мин>_<light|full>.wav. Пусто — audio/engine/.
@export_dir var engine_dir: String = ""
## Сетка оборотов, под которую запечены лупы. Пусто — сетка по умолчанию
## из scripts/engine_sound.gd (она же у Mitsubishi).
@export var engine_rpm_grid: Array[int] = []
## Папка с одиночными звуками (bov, pop, shift, start). Пусто — audio/vehicle/.
@export_dir var engine_events_dir: String = ""
## Поправка громкости банка, дБ: у машин разная плотность записи.
@export_range(-12.0, 6.0, 0.1) var engine_trim_db: float = 0.0
## Питч одиночных событий: ниже единицы — «утробнее» (боксер), выше — звонче.
@export_range(0.5, 2.0, 0.01) var engine_event_pitch: float = 1.0


## Пресеты машины, развёрнутые в ресурсы по id из конфига игры.
## Готовые сетапы машины лежат в одном списке конфига (см. all_setups).
func setups(config: Resource) -> Array[Resource]:
	var result: Array[Resource] = []
	if config == null:
		return result
	for id in setup_ids:
		var setup := config.find_setup(id)
		if setup != null:
			result.append(setup)
	return result


## Сетка оборотов с подстановкой значения по умолчанию.
func rpm_grid(fallback: Array) -> Array:
	return engine_rpm_grid if not engine_rpm_grid.is_empty() else fallback


## Папка лупов с подстановкой значения по умолчанию.
func loops_dir(fallback: String) -> String:
	return engine_dir if not engine_dir.is_empty() else fallback


## Папка одиночных звуков с подстановкой значения по умолчанию.
func events_dir(fallback: String) -> String:
	return engine_events_dir if not engine_events_dir.is_empty() else fallback
