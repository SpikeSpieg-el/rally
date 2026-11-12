## Один мост на трассе: где стоит модульная сцена моста и какой участок
## реки он перекрывает.
##
## Мост — это обычная сцена из scenes/props/, зарегистрированная в
## RallyPropLibrary. Локальная ось X пропса направлена ВДОЛЬ дороги,
## начало координат — верх настила по центру пролёта.
@tool
class_name RallyBridgePlacement
extends Resource

@export_group("Мост")
## Выключить мост, не удаляя ресурс.
@export var enabled: bool = true
## Понятное имя для инспектора и проверок (например «малый мост у мельницы»).
@export var display_name: String = ""
## Метры от старта трассы до центра моста.
@export_range(0.0, 20000.0, 0.5) var distance: float = 0.0
## Id моста в RallyPropLibrary (например bridge_small / bridge_large).
@export var prop_id: String = "bridge_large"

@export_group("Пролёт и настил")
## Половина открытого пролёта вдоль дороги, м: внутри этого радиуса рельеф
## не держит насыпь, и русло проходит под настилом без «плотины».
@export_range(2.0, 40.0, 0.5) var open_radius: float = 14.0
## Сдвиг настила по высоте от полотна дороги, м (настил чуть ниже гравия).
@export_range(-2.0, 1.0, 0.01) var deck_offset: float = -0.07
## Доворот моста вокруг вертикали, градусы.
@export_range(-30.0, 30.0, 0.5) var yaw_offset_deg: float = 0.0

@export_group("Река под мостом")
## Во сколько раз русло шире под этим мостом (большой мост — над широкой водой).
@export_range(1.0, 4.0, 0.01) var channel_scale: float = 1.0
## Радиус сглаживания расширения русла, м.
@export_range(2.0, 120.0, 0.5) var channel_scale_radius: float = 24.0
## Минимальный просвет от полотна до воды, м. Используется проверками
## (тесты/генератор) и предупреждением при сборке мира.
@export_range(0.5, 20.0, 0.1) var water_clearance: float = 3.0
