## Река спецучастка: осевая линия русла, вода, берега.
##
## Это отдельный «пульт» карты. Река живёт в мировых координатах (Y осевой
## линии — УРОВЕНЬ ВОДЫ), поэтому её не надо пересчитывать при правке дороги:
## дорога пересекает реку там, где её пересекает, а мосты ставятся отдельным
## списком (RallyBridgePlacement) на конкретных метрах трассы.
##
## Правило для агентов: числа реки не живут в коде — только здесь.
@tool
class_name RallyRiverConfig
extends Resource

@export_group("Осевая линия")
## Включить реку на этой трассе. Пусто/выключено — прежнее поведение.
@export var enabled: bool = false
## Осевая линия русла в мировых координатах: X/Z — план, Y — уровень воды.
## Строится генератором трассы или руками в 3D-окне (Curve3D).
@export var water_curve: Curve3D = null

@export_group("Русло и берега")
## Половина ширины водного зеркала, м.
@export_range(1.0, 60.0, 0.5) var half_width: float = 7.0
## Ширина откоса от воды до естественного рельефа, м.
@export_range(0.5, 80.0, 0.5) var bank_width: float = 9.0
## Глубина воды от зеркала до дна, м.
@export_range(0.2, 12.0, 0.1) var bed_depth: float = 2.0
## Насколько близко к дороге русло можно прорезать без моста, м.
## Внутри этой зоны рельеф держит насыпь полотна, а не провал.
@export_range(0.0, 60.0, 0.5) var road_keep_zone: float = 16.0
## Шаг выборки осевой линии для сетки воды и запросов высоты, м.
@export_range(1.0, 16.0, 0.5) var sample_step: float = 4.0

@export_group("Вода")
@export var shallow_color: Color = Color(0.055, 0.075, 0.070, 1.0)
@export var deep_color: Color = Color(0.012, 0.020, 0.022, 1.0)
@export var foam_color: Color = Color(0.52, 0.58, 0.56, 1.0)
## Насколько быстро бежит рябь вдоль течения.
@export_range(0.0, 8.0, 0.05) var flow_speed: float = 1.4
## Количество пены у берегов и на камнях (0 — чистая вода).
@export_range(0.0, 1.0, 0.01) var foam_amount: float = 0.45
## Ширина пенной полосы у берега, м.
@export_range(0.2, 20.0, 0.1) var foam_width: float = 2.4
## Глянец воды: 0 — матовая, 1 — зеркало.
@export_range(0.0, 1.0, 0.01) var gloss: float = 0.55
## Непрозрачность воды (1 — совсем не видно дна).
@export_range(0.0, 1.0, 0.01) var opacity: float = 0.88
## Высота мелкой волны на зеркале, м.
@export_range(0.0, 1.0, 0.01) var wave_height: float = 0.07
## Масштаб рисунка волны (больше — мельче рябь).
@export_range(0.05, 4.0, 0.05) var ripple_scale: float = 0.55
## Насколько зеркало воды опущено ниже уровня из осевой линии, м.
@export_range(0.0, 1.0, 0.01) var surface_drop: float = 0.05

@export_group("Берега: камни и стены")
## Вид камней на берегу (id из RallyPropLibrary). Пусто — не ставить.
@export var bank_rock_prop_id: String = "river_bank_rock"
## Средний шаг камней вдоль русла, м.
@export_range(2.0, 80.0, 0.5) var bank_rock_spacing: float = 8.0
## Насколько камень вынесен от кромки воды к берегу, м.
@export_range(0.0, 30.0, 0.5) var bank_rock_lateral: float = 1.4
## Вероятность поставить камень в слоте.
@export_range(0.0, 1.0, 0.01) var bank_rock_chance: float = 0.7
## Вид подпорной стенки на берегу (UK dry-stone). Пусто — не ставить.
@export var bank_wall_prop_id: String = "dry_stone_wall"
## Шаг модулей стенки вдоль русла, м (модуль — 3 м, растягивается).
@export_range(0.0, 200.0, 0.5) var bank_wall_spacing: float = 6.0
## Отступ стенки от кромки воды вверх по берегу, м.
@export_range(0.0, 40.0, 0.5) var bank_wall_lateral: float = 5.0
## Какая часть русла получает стенку (0 — нигде).
@export_range(0.0, 1.0, 0.01) var bank_wall_chance: float = 0.0
## Первые и последние метры русла без стенки, м.
@export_range(0.0, 500.0, 1.0) var bank_wall_margin: float = 40.0
