## Одна машина игры: её игровая сцена, пресеты и звук мотора.
## Физика, камеры, HUD и правила заезда общие для всех машин — здесь лежит
## только то, что у машин действительно разное.
##
## Новая машина = новая сцена res://scenes/rally_car*.tscn. Её не нужно
## регистрировать: игра находит такие сцены сама (см. car_models.gd). Этот ресурс
## нужен, только чтобы задать звук, пресеты или имя.
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
@export var setup_ids: Array[String] = []

@export_group("Игровая сцена")
## Игровая сцена машины: кузов, колёса, кабина и физика. Заезд и гараж берут её.
@export_file("*.tscn") var race_scene: String = ""

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
	# find_setup() объявлен в RallyGameConfig, а параметр здесь — Resource:
	# без явного типа GDScript не может вывести тип и падает на компиляции.
	for id in setup_ids:
		var setup: Resource = config.call("find_setup", id)
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
