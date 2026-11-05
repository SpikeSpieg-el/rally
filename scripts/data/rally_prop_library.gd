## Библиотека ассетов обстановки: список RallyProp, из которого сцена этапа
## набирает лес, кусты, камни и реквизит вдоль трассы.
##
## Файл по умолчанию — res://data/stage/default_prop_library.tres: откройте его
## в инспекторе Godot, поменяйте веса, размеры и состав — сцена читает библиотеку
## при сборке мира. Сцена этапа может подменить библиотеку полем `prop_library`
## у корня RallyStage.
##
## Порядок в списке = порядок в инспекторе. На расстановку он не влияет: вид
## выбирается «урной» по весам (RallyProp.weight).
@tool
class_name RallyPropLibrary
extends Resource

## Все виды обстановки. Вес 0 исключает вид из обычной урны, но не из заполнения.
@export var props: Array[RallyProp] = []


## Обычные пропсы со сценой и ненулевым весом; слой заполнения исключён.
func active_props() -> Array[RallyProp]:
	var out: Array[RallyProp] = []
	for prop in props:
		if prop == null or prop.scene == null or prop.weight <= 0.0 or prop.ground_cover:
			continue
		out.append(prop)
	return out


## Все виды со сценой — включая «спутников» с нулевым весом (трава, папоротник).
func spawnable_props() -> Array[RallyProp]:
	var out: Array[RallyProp] = []
	for prop in props:
		if prop == null or prop.scene == null:
			continue
		out.append(prop)
	return out


## Вид по id (первый найденный), null если такого нет.
func by_id(lookup: String) -> RallyProp:
	if lookup.is_empty():
		return null
	for prop in props:
		if prop != null and prop.id == lookup:
			return prop
	return null


## Сумма весов списка (для кумулятивного броска).
func total_weight(list: Array[RallyProp]) -> float:
	var total := 0.0
	for prop in list:
		total += prop.weight
	return total


## Какой вид выбрать по случайному числу roll в [0, 1).
func pick(list: Array[RallyProp], roll: float) -> RallyProp:
	var index: int = pick_index(list, roll)
	return null if index < 0 else list[index]


## То же, но сразу индексом: на десятках тысяч объектов поиск вида по
## объекту в списке был бы лишней работой. -1 — список пуст.
func pick_index(list: Array[RallyProp], roll: float) -> int:
	var total: float = total_weight(list)
	if list.is_empty() or total <= 0.0:
		return -1
	var value: float = clampf(roll, 0.0, 0.999999) * total
	for i in range(list.size()):
		value -= list[i].weight
		if value < 0.0:
			return i
	return list.size() - 1


## Единый список для генератора и прогрева стриминга. Старые id поддерживаются.
func ground_cover_props(legacy_ids: Array[String]) -> Array[RallyProp]:
	var out: Array[RallyProp] = []
	for prop in spawnable_props():
		if (prop.ground_cover or legacy_ids.has(prop.id)) and prop.cover_weight > 0.0:
			out.append(prop)
	return out

func pick_cover(list: Array[RallyProp], roll: float) -> RallyProp:
	var total := 0.0
	for prop in list:
		total += maxf(0.0, prop.cover_weight)
	if total <= 0.0:
		return null
	var value := clampf(roll, 0.0, 0.999999) * total
	for prop in list:
		value -= maxf(0.0, prop.cover_weight)
		if value < 0.0:
			return prop
	return null
