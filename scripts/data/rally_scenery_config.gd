## Обстановка вдоль трассы: что и с какой плотностью растёт по обочинам.
##
## Это НЕ замена ручным ассетам из Props/ManualProps — это генератор «фонового»
## леса вокруг полотна. Значения читаются при сборке мира, шаблон лежит в
## res://data/stage/default_scenery.tres, сцену можно переопределить полем
## `scenery` у корня RallyStage.
##
## Плотность и частота задаются таблицей видов (kind_weights ниже в ресурсе):
## для каждого вида — доля в общем числе пятен, диапазон размера, высота
## посадки над землёй и Material3D-цвет. Хотите больше камней — поднимите
## вес `boulder` и опустите `fir`.
@tool
class_name RallySceneryConfig
extends Resource

## Виды обстановки. Порядок = порядок в интерфейсе, id должен совпадать с
## `_make_scenery_mesh(kind)` в rally_stage.gd.
const KINDS: PackedStringArray = ["fir", "pine", "bush", "boulder", "grass", "stump", "log"]

@export_group("Раскладка")
## Шаг сэмплирования вдоль трассы, м (меньше — плотнее, дороже).
@export_range(1.0, 40.0, 0.5) var sample_step: float = 7.0
## Отступ от начала и конца трассы, м.
@export_range(0.0, 200.0, 1.0) var start_margin: float = 6.0
@export_range(0.0, 200.0, 1.0) var end_margin: float = 6.0
## Попыток на каждый шаг и каждый бок (масштабируются плотностью трассы).
@export_range(1, 40, 1) var attempts_per_step: int = 3
## Доля удачных попыток на один шаг (0–1).
@export_range(0.0, 1.0, 0.01) var success_chance: float = 0.75
## Минимальный отступ от кромки полотна, м: свой для запечённых и обычных трасс.
@export_range(0.0, 60.0, 0.1) var min_offset_baked: float = 13.0
@export_range(0.0, 60.0, 0.1) var min_offset_plain: float = 4.5
## Максимальный отступ от кромки полотна, м.
@export_range(1.0, 400.0, 1.0) var max_offset: float = 58.0
## Разброс вдоль дороги для одной попытки, м.
@export_range(0.0, 60.0, 0.1) var along_jitter: float = 3.2
## Запретная зона у чужого витка дороги сверх коридора, м.
@export_range(0.0, 60.0, 0.1) var road_clearance: float = 3.5

@export_group("Деревья")
## Диапазон размера ели и пихты (множитель к базовому мешу).
@export var fir_size: Vector2 = Vector2(0.75, 1.75)
@export var pine_size: Vector2 = Vector2(0.80, 1.85)
## Высота «яруса» кроны над землёй (доля размера).
@export_range(0.0, 20.0, 0.1) var fir_crown_height: float = 4.0
@export_range(0.0, 20.0, 0.1) var pine_crown_height: float = 5.6
@export_range(0.0, 10.0, 0.05) var trunk_height: float = 1.15
## Стволы с коллизией: до какого отступа от дороги и через сколько метров.
@export_range(0.0, 200.0, 1.0) var collider_max_offset: float = 24.0
@export_range(0.0, 500.0, 1.0) var collider_spacing: float = 45.0
@export_range(0.0, 10.0, 0.05) var collider_radius: float = 0.45
@export_range(0.0, 30.0, 0.1) var collider_height: float = 9.0
@export_range(-5.0, 5.0, 0.01) var collider_y_offset: float = 0.0

@export_group("Кусты, камни, подлесок")
@export var bush_size: Vector2 = Vector2(0.65, 1.60)
@export var bush_width_jitter: Vector2 = Vector2(0.8, 1.3)
@export_range(0.0, 2.0, 0.01) var bush_height_factor: float = 0.45
@export var boulder_size: Vector2 = Vector2(0.55, 2.10)
@export var boulder_width_jitter: Vector2 = Vector2(0.7, 1.3)
@export var boulder_height_jitter: Vector2 = Vector2(0.6, 1.0)
@export_range(0.0, 2.0, 0.01) var boulder_height_factor: float = 0.55
@export var grass_size: Vector2 = Vector2(0.60, 1.25)
@export_range(0.0, 2.0, 0.01) var grass_height_factor: float = 0.18
@export_range(0.0, 2.0, 0.01) var grass_width_factor: float = 1.3
@export var stump_size: Vector2 = Vector2(0.60, 1.25)
@export_range(0.0, 2.0, 0.01) var stump_height_factor: float = 0.32
@export var log_size: Vector2 = Vector2(0.70, 1.35)
@export_range(0.0, 2.0, 0.01) var log_height_factor: float = 0.18
## Вероятность, что мелкий подлесок добавится рядом с крупным объектом.
@export_range(0.0, 1.0, 0.01) var undergrowth_chance: float = 0.75

@export_group("Вероятности видов (0 — вид не появляется)")
## Доли видов. Не обязаны давать ровно 1: код берёт кумулятивный бросок.
@export_range(0.0, 1.0, 0.01) var weight_fir: float = 0.30
@export_range(0.0, 1.0, 0.01) var weight_pine: float = 0.18
@export_range(0.0, 1.0, 0.01) var weight_bush: float = 0.23
@export_range(0.0, 1.0, 0.01) var weight_boulder: float = 0.13
@export_range(0.0, 1.0, 0.01) var weight_stump: float = 0.09
@export_range(0.0, 1.0, 0.01) var weight_log: float = 0.07

@export_group("Меши и материалы")
## Выключатель point-фильтрации текстур обстановки (PS1).
@export var ps1_filter: bool = true
@export_range(0.0, 1.0, 0.01) var roughness: float = 0.95
@export var fir_color: Color = Color(0.90, 1.00, 0.90)
@export var pine_color: Color = Color(0.75, 0.85, 0.80)
@export var grass_color: Color = Color(0.80, 0.95, 0.65)
@export var bush_color: Color = Color(1.00, 1.00, 0.90)
@export var trunk_color: Color = Color(0.78, 0.69, 0.58)
@export var boulder_color: Color = Color(0.85, 0.88, 0.90)
## Геометрия крон/стволов (radius/height/segments).
@export_range(0.1, 10.0, 0.05) var fir_radius: float = 1.70
@export_range(0.5, 30.0, 0.1) var fir_mesh_height: float = 6.50
@export_range(0.1, 10.0, 0.05) var pine_radius: float = 1.35
@export_range(0.5, 40.0, 0.1) var pine_mesh_height: float = 9.00
@export_range(3, 32, 1) var crown_segments: int = 7
@export_range(0.05, 2.0, 0.01) var trunk_top_radius: float = 0.22
@export_range(0.05, 2.0, 0.01) var trunk_bottom_radius: float = 0.32
@export_range(0.2, 20.0, 0.1) var trunk_mesh_height: float = 2.30
@export_range(0.05, 2.0, 0.01) var stump_top_radius: float = 0.30
@export_range(0.05, 2.0, 0.01) var stump_bottom_radius: float = 0.34
@export_range(0.1, 10.0, 0.05) var stump_mesh_height: float = 0.65
@export_range(0.1, 20.0, 0.1) var log_mesh_height: float = 2.80
@export_range(3, 32, 1) var wood_segments: int = 6
@export_range(0.05, 5.0, 0.01) var grass_radius: float = 0.55
@export_range(0.05, 5.0, 0.01) var grass_mesh_height: float = 0.55
@export_range(3, 24, 1) var grass_segments: int = 5
@export_range(0.1, 5.0, 0.01) var bush_radius: float = 0.95
@export_range(0.1, 10.0, 0.01) var bush_mesh_height: float = 1.50
@export_range(3, 24, 1) var bush_radial_segments: int = 6
@export_range(1, 12, 1) var bush_rings: int = 2
@export_range(0.1, 5.0, 0.01) var boulder_radius: float = 1.20
@export_range(0.1, 10.0, 0.01) var boulder_mesh_height: float = 2.10
@export_range(3, 24, 1) var boulder_radial_segments: int = 7
@export_range(1, 12, 1) var boulder_rings: int = 3


## Сумма весов видов (для кумулятивного броска).
func total_weight() -> float:
	return weight_fir + weight_pine + weight_bush + weight_boulder + weight_stump + weight_log


## Какой вид выбрать по случайному числу roll в [0, 1).
func pick_kind(roll: float) -> String:
	var total: float = total_weight()
	if total <= 0.0:
		return ""
	var value: float = clampf(roll, 0.0, 0.999999) * total
	var thresholds := {
		"fir": weight_fir,
		"pine": weight_pine,
		"bush": weight_bush,
		"boulder": weight_boulder,
		"stump": weight_stump,
		"log": weight_log,
	}
	for kind in KINDS:
		value -= float(thresholds.get(kind, 0.0))
		if value < 0.0:
			return kind
	return "log"
