## Участок бесконечной аркадной дороги: один «домен» генерации.
##
## Дорога не строится целиком — она нарезается на участки фиксированной
## длины (см. RallyArcadeRoad.LEG_LENGTH), и каждый участок получает свой
## характер. Границы участков выровнены по километражу, поэтому любой участок
## можно собрать отдельно, не зная предыдущих коэффициентов шума: это и есть
## чанковая генерация. Стыки сшиваются общими контрольными точками и
## нулевым уклоном на краях, поэтому шва не видно.
@tool
class_name RallyArcadeLeg
extends Resource

## Характер участка. Порядок — это же значение для `_pick_kind()`.
enum Kind {
	## Серпантин: серия шпилек с ровными полками на склоне (главный аттракцион).
	SERPENTINE,
	## Просёлок: узкая извилистая дорога среди полей и леса, плавные дуги.
	COUNTRY,
	## Деревня: короткий прямой проезд с домами по бокам и пешеходным переходом.
	VILLAGE,
	## Мост: прямая через овраг или реку, узкие перила.
	BRIDGE,
	## Быстрый участок: длинные широкие дуги для обгонов и разгона.
	FAST,
}

## Индекс участка от старта (0, 1, 2 …).
@export var index: int = 0
## Домены этого участка в порядке следования внутри него.
@export var domains: Array[Kind] = []
## Начало участка по километражу трассы, м.
@export var start_distance: float = 0.0
## Половина ширины полотна в начале и в конце участка, м. Переход между
## участками плавный: соседи берут общие граничные значения.
@export var half_width_start: float = 3.6
@export var half_width_end: float = 3.6
## Высота осевой линии в начале и в конце, м.
@export var height_start: float = 0.0
@export var height_end: float = 0.0
## Направление (курс) в начале и в конце, радианы.
@export var heading_start: float = 0.0
@export var heading_end: float = 0.0
## Перепад высот внутри участка: серпантин лезет на склон, просёлок — почти
## ровный. Знак — вверх/вниз.
@export var climb: float = 0.0
## Насколько участок «крутит»: 0 — прямая, 1 — плотный серпантин.
@export var twist: float = 0.5
## Пешеходные переходы внутри участка: километраж от начала участка.
@export var crossings: PackedFloat32Array = PackedFloat32Array()
## Населённые пункты по сторонам (деревня): позиции и поворот домов.
## Пусто у всех, кроме VILLAGE.
@export var houses: Array[Vector3] = []


## Домены по умолчанию для участка с этим индексом и сидом. Чистая функция:
## по одному индексу и сиду всегда получается один и тот же набор, поэтому
## левый и правый сосед могут предсказать границы друг друга.
static func plan(leg_index: int, seed_value: int) -> Array[Kind]:
	var result: Array[Kind] = []
	var roll: float = RallyArcadeRoad.roll(leg_index, seed_value, 101)
	# Серпантин — почти каждый третий-четвёртый участок: это «лицо» режима,
	# но между ними дорога должна дышать и разгоняться.
	if roll < 0.34:
		result.append(Kind.SERPENTINE)
	elif roll < 0.62:
		result.append(Kind.COUNTRY)
	elif roll < 0.80:
		result.append(Kind.FAST)
	else:
		result.append(Kind.VILLAGE)
	# Внутри участка — второй, более короткий домен. Серпантин не ставим
	# вторым: два подряд — это уже каша без разгона.
	var second_roll: float = RallyArcadeRoad.roll(leg_index, seed_value, 102)
	if result[0] == Kind.SERPENTINE:
		if second_roll < 0.55:
			result.append(Kind.COUNTRY)
	elif second_roll < 0.42:
		result.append(Kind.COUNTRY)
	elif second_roll < 0.72:
		result.append(Kind.FAST)
	elif second_roll < 0.90:
		result.append(Kind.VILLAGE)
	if result.has(Kind.VILLAGE) and second_roll > 0.55:
		# Деревня — это короткий проезд, второй домен пусть будет мостом:
		# он читается как «выехал из села на реку».
		result.append(Kind.BRIDGE)
	return result


## Доля участка, которую занимает домен (в сумме 1.0).
static func domain_weight(domain: Kind) -> float:
	match domain:
		Kind.SERPENTINE:
			return 0.62
		Kind.VILLAGE:
			return 0.16
		Kind.BRIDGE:
			return 0.14
		Kind.FAST:
			return 0.30
		_:
			return 0.38


static func kind_name(kind: Kind) -> String:
	match kind:
		Kind.SERPENTINE:
			return "СЕРПАНТИН"
		Kind.COUNTRY:
			return "ПРОСЁЛОК"
		Kind.VILLAGE:
			return "ДЕРЕВНЯ"
		Kind.BRIDGE:
			return "МОСТ"
		_:
			return "РАЗГОН"
