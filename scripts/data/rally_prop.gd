## Один тип объекта на трассе: дерево, камень, куст, столбик, щит…
## Создайте ресурс: правая кнопка в FileSystem → Новый ресурс → RallyProp.
## Примеры: res://data/props/*.tres
##
## Режимы расстановки:
##   ВДОЛЬ ДОРОГИ — объекты идут вдоль обочины с заданным шагом (деревья,
##                  столбики, щиты). Позиция берётся из осевой линии.
##   ПО КАРТЕ      — равномерный «посев» по всей карте, но не ближе
##                  road_clearance к дороге (камни, кусты в поле).
class_name RallyProp
extends Resource

enum Mode { ALONG_ROAD, SCATTER }
enum Side { BOTH, LEFT, RIGHT }

@export_group("Внешний вид")
@export var display_name: String = "Объект"
## Меш объекта (дерево, камень, столбик…). Можно оставить пустым, если задана сцена.
@export var mesh: Mesh = null
## Готовая сцена (например, ваш .tscn с деревом). Приоритетнее mesh.
@export var scene: PackedScene = null
## Материал (необязательно): заменяет материал меша.
@export var material: Material = null

@export_group("Расстановка")
@export var mode: int = Mode.ALONG_ROAD
## Сколько объектов поставить. 0 — посчитать автоматически по шагу.
@export_range(0, 2000, 1) var count: int = 0
## Шаг вдоль дороги (м) — для режима ВДОЛЬ ДОРОГИ.
@export_range(1.0, 200.0, 0.5) var spacing: float = 18.0
## Ширина «полосы» расстановки, м (расстояние от края полотна).
@export_range(0.0, 200.0, 0.5) var lateral_min: float = 8.0
@export_range(0.0, 200.0, 0.5) var lateral_max: float = 26.0
## С какой стороны ставить.
@export var side: int = Side.BOTH
## Случайный сдвиг вдоль дороги (м), чтобы не было «строя».
@export_range(0.0, 60.0, 0.5) var along_jitter: float = 5.0
## Режим ПО КАРТЕ: минимальное расстояние до дороги (м).
@export_range(2.0, 200.0, 0.5) var road_clearance: float = 14.0
## Режим ПО КАРТЕ: радиус пятна вокруг центра карты (0 — вся карта).
@export_range(0.0, 800.0, 5.0) var scatter_radius: float = 0.0

@export_group("Вариация")
@export_range(0.1, 4.0, 0.05) var scale_min: float = 0.85
@export_range(0.1, 4.0, 0.05) var scale_max: float = 1.25
## Растянуть объект по высоте (ёлки выше, кусты ниже).
@export_range(0.2, 3.0, 0.05) var scale_y: float = 1.0
## Случайный поворот вокруг вертикали.
@export var random_yaw: bool = true
## Развернуть объект вдоль дороги (щиты, столбики, ворота). Приоритетнее random_yaw.
@export var face_road: bool = false
## Доворот после face_road, градусы (180 — лицом к едущим).
@export_range(-180.0, 180.0, 1.0) var face_road_offset_deg: float = 180.0
## Наклонять объект по склону (деревья — да, столбики — нет).
@export var align_to_slope: bool = false
@export_range(0.0, 1.0, 0.05) var align_to_slope_amount: float = 0.7
## Смещение по высоте (усадить в землю: -0.1).
@export_range(-3.0, 3.0, 0.01) var y_offset: float = 0.0

@export_group("Коллизия")
@export var collision: bool = false
@export_range(0.05, 4.0, 0.05) var collision_radius: float = 0.35
@export_range(0.2, 12.0, 0.1) var collision_height: float = 2.4


func is_valid() -> bool:
	return mesh != null or scene != null
