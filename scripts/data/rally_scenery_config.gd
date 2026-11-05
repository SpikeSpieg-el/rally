## Обстановка вдоль трассы: КАК часто и КАК плотно расставлять пропсы.
##
## Это НЕ замена ручным ассетам из Props/ManualProps — это генератор
## «фонового» леса вокруг полотна. Значения читаются при сборке мира, шаблон
## лежит в res://data/stage/default_scenery.tres, сцену можно переопределить
## полем `scenery` у корня RallyStage.
##
## ЧТО именно растёт — не здесь, а в библиотеке ассетов
## res://data/stage/default_prop_library.tres (RallyPropLibrary): там у каждого
## вида своя СЦЕНА (открывается и правится в редакторе), вес, размер и правила
## коллизии. Здесь — только раскладка: шаг, плотность, отступы и дальность.
@tool
class_name RallySceneryConfig
extends Resource

@export_group("Раскладка")
## Шаг сэмплирования вдоль трассы, м (меньше — плотнее, дороже).
@export_range(1.0, 40.0, 0.5) var sample_step: float = 7.0
## Отступ от начала и конца трассы, м.
@export_range(0.0, 200.0, 1.0) var start_margin: float = 6.0
@export_range(0.0, 200.0, 1.0) var end_margin: float = 6.0
## Сколько попыток на каждый шаг и каждый бок при плотности 1.0.
## Итог = попытки × плотность трассы × density_multiplier.
@export_range(1, 40, 1) var attempts_per_step: int = 3
## Доля удачных попыток (0–1): остальные отбрасываются, сохраняя «рваный» лес.
@export_range(0.0, 1.0, 0.01) var success_chance: float = 0.75
## Множитель плотности крупных объектов.
@export_range(0.1, 100.0, 0.5) var density_multiplier: float = 6.0
## Потолок попыток на один шаг (страховка от гигантских карт).
@export_range(1, 4000, 1) var max_attempts_per_step: int = 400
## Потолок объектов за одну сборку (0 — без потолка).
@export_range(0, 2000000, 1000) var max_instances: int = 400000
## Минимальный отступ от кромки полотна, м: свой для запечённых и обычных трасс.
@export_range(0.0, 60.0, 0.1) var min_offset_baked: float = 13.0
@export_range(0.0, 60.0, 0.1) var min_offset_plain: float = 4.5
## Максимальный отступ от кромки дорожного коридора, м (общий; у вида может быть свой меньше).
@export_range(1.0, 400.0, 1.0) var max_offset: float = 58.0
## Разброс вдоль дороги для одной попытки, м.
@export_range(0.0, 60.0, 0.1) var along_jitter: float = 3.2
## Разбрасывать попытки по всему шагу, а не только вокруг его середины:
## при большой плотности лес получается равномерным, без «сгустков» у шага.
@export var along_jitter_full_step: bool = true
## Запретная зона у чужого витка дороги сверх коридора, м.
@export_range(0.0, 60.0, 0.1) var road_clearance: float = 3.5
## Искусственный придорожный реквизит — редкий акцент, а не сплошной мусор.
@export_range(0.0, 1.0, 0.01) var roadside_prop_chance: float = 0.25

@export_group("Биомы заполнения")
## Длина тематического участка вдоль дороги; обе стороны выбирают зоны независимо.
@export_range(40.0, 2000.0, 10.0) var biome_length: float = 240.0
## Первый профиль с нужной зоной; пустой список сохраняет старую равномерную раскладку.
@export var biomes: Array[RallySceneryBiome] = []

@export_group("Подлесок-спутник")
## Id вида, который сажается рядом с «хозяином» (травяной пучок).
## Пусто — спутник не сажается. Сам вид при этом должен лежать в библиотеке.
@export var undergrowth_prop_id: String = ""
## Несколько видов травы для случайной смены спутников вокруг больших пропсов.
## Старое поле undergrowth_prop_id остаётся запасным вариантом, если список пуст.
@export var undergrowth_prop_ids: Array[String] = []
## Старый список id заполнения (совместимость). Новые виды автоматически
## подключаются флагом RallyProp.ground_cover в библиотеке, без правок этого списка.
@export var ground_cover_prop_ids: Array[String] = ["grass2", "grass3"]
## Отдельная плотность массового заполнения grass2/grass3.
@export_range(0.0, 40.0, 0.1) var ground_cover_density: float = 4.0
## Дополнительный слой только травы, отдельно от грибов и цветов.
@export_range(0.0, 40.0, 0.1) var extra_grass_density: float = 0.0
@export var extra_grass_prop_ids: Array[String] = ["grass2", "grass3"]
## Попыток заполнения на шаг трассы и сторону.
@export_range(0, 100, 1) var ground_cover_attempts_per_step: int = 12
## Доля успешных попыток заполнения.
@export_range(0.0, 1.0, 0.01) var ground_cover_success_chance: float = 0.85
## Диапазон размера спутника (множитель к его сцене).
@export var undergrowth_size: Vector2 = Vector2(0.60, 1.25)
## Дополнительный разброс ширины спутника.
@export_range(0.5, 3.0, 0.05) var undergrowth_width_factor: float = 1.3
## Радиус разброса спутника вокруг «хозяина», м.
@export_range(0.0, 10.0, 0.1) var undergrowth_spread: float = 1.4

@export_group("Прогресс загрузки")
## Сколько попыток расстановки успевать за один кадр, пока идёт полоса
## загрузки. Меньше — полоса двигается ровнее, но сборка дольше.
@export_range(500, 200000, 500) var progress_attempts_per_frame: int = 6000

@export_group("Материалы")
## Включать ли PS1 point-фильтрацию у текстур обстановки.
@export var ps1_filter: bool = true


## Сколько попыток делать на один шаг и бок при текущей плотности трассы.
func attempts_for(density: float) -> int:
	var scaled: float = float(attempts_per_step) * maxf(density, 0.0) * maxf(density_multiplier, 0.0)
	return clampi(ceili(scaled), 1, max_attempts_per_step)


## Доля удачных попыток: чтобы итоговое число объектов совпадало с
## attempts_for() × success_chance независимо от округления.
func attempt_chance_for(density: float, attempt_count: int) -> float:
	var scaled: float = float(attempts_per_step) * maxf(density, 0.0) * maxf(density_multiplier, 0.0) * success_chance
	return clampf(scaled / float(maxi(attempt_count, 1)), 0.0, 1.0)


func biome_for_zone(zone: int) -> RallySceneryBiome:
	for biome in biomes:
		if biome != null and biome.zone == zone:
			return biome
	return null
