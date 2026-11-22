## Выстрелы пламени из выхлопа турбомотора («антилаг»): сброс газа на высоких
## оборотах, хлопок вместе со звуком в выхлопе, переключение вверх, отсечка.
##
## Ресурс res://data/car/default_exhaust_flame.tres — правится в инспекторе:
## у корня RallyCar в сцене машины (поле `exhaust_flame_config`) или прямо в
## файле ресурса (FileSystem → data/car/). Картинка пламени — textures/fire.png.
##
## Где выхлоп, компонент находит сам: по маркерам Marker3D с именем,
## начинающимся на `outlet_marker_prefix` (поставьте их в сцене машины —
## это главнее всего), иначе по поверхностям модели с материалом «exhaust»,
## иначе — по `fallback_outlet`.
##
## Слой косметический: на мощность, физику и звук мотора не влияет.
@tool
class_name RallyExhaustFlameConfig
extends Resource

@export_group("Включение")
## Главный выключатель выстрелов пламени.
@export var enabled: bool = true
## Только у машин с турбиной (пресет мотора turbo = true), как и хлопки в звуке.
@export var turbo_only: bool = true
## Машины, у которых есть пламя (vehicle_id). Пусто — у всех.
@export var vehicle_ids: Array[String] = []
## Наименьшая пауза между выстрелами, с.
@export_range(0.02, 2.0, 0.01, "suffix:с") var cooldown_sec: float = 0.09

@export_group("Когда стреляет")
## Стрелять вместе с хлопком и сбросом турбины в звуке мотора (EngineAudio).
## Если звука нет, срабатывает собственная проверка сброса газа.
@export var sync_with_audio: bool = true
## Сброс газа: был газ не меньше этого…
@export_range(0.0, 1.0, 0.01) var lift_throttle_from: float = 0.5
## …и стал меньше этого.
@export_range(0.0, 1.0, 0.01) var lift_throttle_to: float = 0.1
## Обороты, ниже которых сброс газа не стреляет.
@export_range(1000.0, 9000.0, 50.0, "suffix:об/мин") var lift_min_rpm: float = 3000.0
## Очередь мелких выстрелов («треск антилага») после сброса газа.
@export var crackle_enabled: bool = true
## Сколько длится очередь после сброса газа, с.
@export_range(0.0, 5.0, 0.05, "suffix:с") var crackle_duration_sec: float = 1.1
## Сколько выстрелов в секунду в очереди (в среднем, случайно).
@export_range(0.0, 30.0, 0.5, "suffix:1/с") var crackle_rate_hz: float = 7.0
## Обороты, ниже которых очередь затихает.
@export_range(1000.0, 9000.0, 50.0, "suffix:об/мин") var crackle_min_rpm: float = 3600.0
## Сила мелкого выстрела относительно полного (0..1).
@export_range(0.05, 1.0, 0.01) var crackle_strength: float = 0.45
## Выстрел при переключении вверх под газом.
@export var upshift_enabled: bool = true
## С каких оборотов переключение вверх стреляет.
@export_range(1000.0, 9000.0, 50.0, "suffix:об/мин") var upshift_min_rpm: float = 5200.0
## Сила выстрела при переключении.
@export_range(0.05, 1.0, 0.01) var upshift_strength: float = 0.8
## Выстрелы на отсечке (мотор упёрся в ограничитель оборотов).
@export var limiter_enabled: bool = true
## Сколько выстрелов в секунду на отсечке.
@export_range(0.0, 30.0, 0.5, "suffix:1/с") var limiter_rate_hz: float = 6.0
## Сила выстрела на отсечке.
@export_range(0.05, 1.0, 0.01) var limiter_strength: float = 0.6

@export_group("Пламя")
## Текстура языка пламени: основание — снизу картинки, кончик — сверху.
@export var flame_texture: Texture2D = preload("res://textures/fire.png")
## Цвет пламени (умножается на текстуру, смешивание сложением).
@export var flame_color: Color = Color(1.0, 0.62, 0.26, 1.0)
## Цвет ядра у самого среза трубы.
@export var core_color: Color = Color(0.55, 0.7, 1.0, 1.0)
## Длина языка у полного выстрела, м (случайно в этих пределах).
@export var flame_length_m: Vector2 = Vector2(0.55, 0.95)
## Ширина языка относительно длины.
@export_range(0.1, 2.0, 0.01) var flame_width_ratio: float = 0.62
## Сколько живёт выстрел, с.
@export_range(0.02, 1.0, 0.01, "suffix:с") var flame_life_sec: float = 0.16
## Доля жизни, за которую язык вырастает до полной длины.
@export_range(0.05, 0.9, 0.01) var flame_grow_part: float = 0.25
## Яркость пламени (множитель цвета, >1 — пересвет).
@export_range(0.1, 6.0, 0.05) var flame_energy: float = 2.2
## Наклон струи вниз, градусы (трубы обычно смотрят чуть вниз).
@export_range(-45.0, 45.0, 0.5, "suffix:°") var flame_pitch_down_deg: float = 6.0
## Случайный разброс направления, градусы.
@export_range(0.0, 30.0, 0.5, "suffix:°") var flame_jitter_deg: float = 7.0
## Сдвиг основания языка от среза трубы назад, м.
@export_range(-0.3, 0.5, 0.005, "suffix:м") var flame_offset_m: float = 0.02
## Сколько одновременных языков на одну трубу.
@export_range(1, 8, 1) var flames_per_outlet: int = 3

@export_group("Огненный шар")
## Клубок огня у среза при сильном выстреле (частицы-билборды fire.png).
@export var fireball_enabled: bool = true
## Сколько частиц у полного выстрела.
@export_range(1, 32, 1) var fireball_amount: int = 6
## Размер частицы, м.
@export var fireball_size_m: Vector2 = Vector2(0.18, 0.36)
## Скорость разлёта назад, м/с.
@export_range(0.0, 20.0, 0.1, "suffix:м/с") var fireball_speed_mps: float = 3.5
## Время жизни частицы, с.
@export_range(0.02, 1.5, 0.01, "suffix:с") var fireball_life_sec: float = 0.22
## С какой силы выстрела появляется огненный шар (0..1).
@export_range(0.0, 1.0, 0.01) var fireball_min_strength: float = 0.6

@export_group("Вспышка света")
## Оранжевая вспышка, подсвечивающая бампер и дорогу.
@export var light_enabled: bool = true
@export var light_color: Color = Color(1.0, 0.55, 0.2, 1.0)
@export_range(0.0, 16.0, 0.1) var light_energy: float = 3.5
@export_range(0.5, 20.0, 0.1, "suffix:м") var light_range_m: float = 4.5
## Тени от вспышки (дороже).
@export var light_shadows: bool = false

@export_group("Где выхлоп")
## Маркеры в сцене машины: Marker3D (или любой Node3D), имя которых
## начинается с этого. Направление выстрела — локальная ось -Z маркера.
@export var outlet_marker_prefix: String = "ExhaustOutlet"
## Найти трубы по материалам модели (имя материала или поверхности).
@export var auto_detect: bool = true
## Слова в имени материала/поверхности трубы (без учёта регистра).
@export var material_keywords: Array[String] = ["exhaust"]
## Трубы ближе этого по ширине считаются одной, м.
@export_range(0.02, 1.0, 0.01, "suffix:м") var merge_distance_m: float = 0.12
## Свои точки труб в координатах машины (перед — +Z). Если заданы — главнее
## автоопределения (но не маркеров).
@export var manual_outlets: Array[Vector3] = []
## Если ничего не нашлось — одна труба здесь (координаты машины).
@export var fallback_outlet: Vector3 = Vector3(0.0, 0.45, -1.85)


## Работает ли пламя на машине vehicle_id с турбиной (turbo).
func applies_to(vehicle_id: String, turbo: bool) -> bool:
	if not enabled:
		return false
	if turbo_only and not turbo:
		return false
	return vehicle_ids.is_empty() or vehicle_ids.has(vehicle_id)
