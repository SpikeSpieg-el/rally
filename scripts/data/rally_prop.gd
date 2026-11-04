## Один вид обстановки: КАКУЮ сцену ставить и КАК её ставить.
##
## Раньше лес, кусты и камни собирались прямо в коде rally_stage.gd — открыть
## и поправить такой ассет в редакторе было нельзя. Теперь каждый вид — это
## обычная сцена из scenes/props/ плюс правила расстановки здесь. Хотите новый
## пропс: соберите сцену, добавьте RallyProp в библиотеку
## (data/stage/default_prop_library.tres) — и он поедет в процедурный лес.
##
## Сцена пропса должна стоять «на земле»: начало координат — точка касания
## грунта, всё остальное поднято над нулём внутри сцены. Тогда множитель
## размера из `size` масштабирует пропс целиком, а не утапливает его в землю.
@tool
class_name RallyProp
extends Resource

@export_group("Ассет")
## Короткий id латиницей (как имя файла сцены). По нему вид ищется в коде и
## в поле `undergrowth_prop_id` конфига обстановки.
@export var id: String = ""
## Понятное название для инспектора (по-русски).
@export var display_name: String = ""
## Сцена ассета: открывается и правится в редакторе как обычный объект.
## Перед расстановкой сцена один раз «запекается» в MultiMesh, поэтому её
## меши и материалы — ровно то, что видно в заезде.
@export var scene: PackedScene = null
## Доля в общей «урне» видов. 0 — вид не расставляется сам (но может быть
## спутником, см. `undergrowth_prop_id` в RallySceneryConfig).
@export_range(0.0, 10.0, 0.01) var weight: float = 1.0

@export_group("Размер и поворот")
## Диапазон множителя размера (x — минимум, y — максимум).
@export var size: Vector2 = Vector2(0.8, 1.4)
## Дополнительный разброс ширины по осям X и Z.
@export var width_jitter: Vector2 = Vector2(0.9, 1.1)
## Дополнительный разброс высоты по оси Y.
@export var height_jitter: Vector2 = Vector2(0.9, 1.1)
## Дополнительный подъём над землёй, м (умножается на размер).
@export var y_offset: float = 0.0
## Случайный поворот вокруг вертикали (у заборов и щитов имеет смысл выключить).
@export var random_yaw: bool = true

@export_group("Где растёт")
## Предельный отступ от осевой линии, м. 0 — как у остальных (cfg.max_offset).
## Маленькое значение сажает «реквизит» (мешки, покрышки, щиты) ближе к дороге.
@export_range(0.0, 400.0, 1.0) var max_offset: float = 0.0

@export_group("Тень и мелочь")
## Мелкий объект: не отбрасывает тень и пропадает раньше крупного.
@export var small: bool = false
## Шанс посадить рядом спутника (трава, папоротник — id в конфиге обстановки).
@export_range(0.0, 1.0, 0.01) var undergrowth_chance: float = 0.0

@export_group("Коллизия")
## В пределах скольки метров от кромки полотна ставить коллизию. 0 — без
## коллизии: сквозь кусты и траву машина проезжает.
@export_range(0.0, 200.0, 1.0) var collider_max_offset: float = 0.0
## Минимальный шаг между коллизиями вдоль трассы, м.
@export_range(0.0, 500.0, 1.0) var collider_spacing: float = 45.0
@export_range(0.05, 5.0, 0.05) var collider_radius: float = 0.45
@export_range(0.5, 40.0, 0.1) var collider_height: float = 9.0
@export_range(-5.0, 5.0, 0.01) var collider_y_offset: float = 0.0


## Нужен ли этому виду физический ствол.
func has_collider() -> bool:
	return collider_max_offset > 0.0


## Имя группы в дереве Generated/Scenery: `fir_tree` → `FirTree`.
func group_name() -> String:
	if id.is_empty():
		return "Props"
	var out := ""
	for part in id.split("_"):
		if part.is_empty():
			continue
		out += part.substr(0, 1).to_upper() + part.substr(1)
	return out if not out.is_empty() else "Props"
