## Описание спецучастка. Это ЕДИНСТВЕННЫЙ ресурс, который задаёт карту:
## осевую линию дороги (Curve3D), рельеф вокруг неё, ассеты, погоду и сцепление.
## Откройте data/tracks/stage_forest.tres в инспекторе Godot — всё ниже
## редактируется без единой строчки кода.
@tool
class_name RallyTrackConfig
extends Resource

@export_group("Описание")
@export var id: String = "stage"
@export var display_name: String = "Спецучасток"
@export_multiline var description: String = "Описание трассы."
@export var surface_name: String = "Гравий"
@export_range(1, 5, 1) var difficulty: int = 3
## Эталонное время прохождения — для HUD и таблицы рекордов.
@export_range(20.0, 2400.0, 1.0) var target_time: float = 150.0

@export_group("Дорога")
## Осевая линия трассы. Точки: X/Z — план, Y — высота.
## Редактируется прямо в инспекторе: Curve3D → Points, или горями/ручками
## в окне 3D. Формула высоты дороги и земли общая, поэтому полотно никогда
## не «клипает» сквозь рельеф.
@export var road_curve: Curve3D = null
## Половина ширины полотна (м). 4.0–4.6 — узкий раллийный спецучасток.
@export_range(2.0, 10.0, 0.1) var road_half_width: float = 4.2
## Грунтовая обочина, которая считается частью полотна (м).
@export_range(0.0, 5.0, 0.1) var road_shoulder: float = 1.3
## Шаг триангуляции полотна вдоль трассы (м). При включённых кочках полотно
## дробится мельче (≈10 строк на длину волны), чтобы волна была гладкой.
@export_range(0.5, 4.0, 0.1) var road_step: float = 1.5
## Поперечный уклон полотна (крен к обочинам), м.
@export_range(0.0, 0.4, 0.01) var road_camber: float = 0.07
## Сцепление травы относительно гравийного полотна: 0.9 = 90 % сцепления дороги.
@export_range(0.05, 1.0, 0.01) var offroad_grip: float = 0.6

@export_group("Рельеф")
## Сколько метров земли генерировать вокруг трассы с каждой стороны.
@export_range(40.0, 400.0, 5.0) var terrain_margin: float = 120.0
## Шаг сетки рельефа (м). 1.5 — красиво, 3.0 — быстро.
@export_range(1.0, 6.0, 0.25) var terrain_cell: float = 2.0
## Сид шума рельефа (меняется — меняется только рисунок холмов).
@export var terrain_seed: int = 2024
## Высота «фоновых» холмов вокруг дороги, м.
@export_range(0.0, 80.0, 0.5) var hills_height: float = 14.0
@export_range(0.0005, 0.05, 0.0005) var hills_frequency: float = 0.0045
## Горные гребни поверх холмов (0 = равнина).
@export_range(0.0, 80.0, 0.5) var ridge_height: float = 10.0
@export_range(0.0005, 0.05, 0.0005) var ridge_frequency: float = 0.0018
## С какого расстояния от дороги начинают расти холмы и насколько плавно.
@export_range(0.0, 100.0, 1.0) var hills_fade_start: float = 14.0
@export_range(10.0, 300.0, 1.0) var hills_fade_length: float = 70.0
## Максимальный склон земли (градусы). Страховка от «стенок» у шпилек.
@export_range(20.0, 75.0, 1.0) var max_terrain_slope_deg: float = 45.0
## Глубина кювета вдоль кромки дороги, м. Земля под полотном и у обочины
## опускается на эту величину, поэтому дорога физически не может «проткнуть»
## рельеф. 0 — выключить (тогда возможны стыки на крутых косогорах).
@export_range(0.0, 2.0, 0.05) var road_ditch_depth: float = 0.6
## Мелкая «шершавость» земли, м (вне дороги).
@export_range(0.0, 3.0, 0.01) var detail_height: float = 0.35
@export_range(0.01, 1.0, 0.001) var detail_frequency: float = 0.09
## Какие склоны может иметь насыпь/выемка у дороги (градусы).
@export_range(10.0, 55.0, 1.0) var embankment_slope_deg: float = 30.0
## Минимальная и максимальная ширина перехода от полотна к рельефу (м).
@export_range(1.0, 40.0, 0.5) var embankment_min_width: float = 4.0
@export_range(4.0, 120.0, 1.0) var embankment_max_width: float = 34.0

@export_group("Неровности полотна (кочки/стиральная доска)")
## Амплитуда продольных неровностей полотна, м. 0 — идеально ровный асфальт.
## Держите её небольшой (5–6 см): это профиль дороги, а не трамплин.
@export_range(0.0, 0.6, 0.01) var bumps_amplitude: float = 0.05
## Длина волны неровностей (м). Меньше ~8 м на низкополигональном полотне
## читается как «гармошка», поэтому по умолчанию — длинные мягкие волны.
@export_range(4.0, 30.0, 0.1) var bumps_wavelength: float = 9.0
## Глубина «ямочной» тряски поверх волн, м (тоже низкочастотной, ~10 м).
@export_range(0.0, 0.4, 0.01) var bumps_roughness: float = 0.015
## Насколько шершавость гасит волну (0 — ровные полосы по всей ширине).
@export_range(0.0, 1.0, 0.01) var bumps_cross: float = 0.25

@export_group("Ассеты")
## Устарело: ассеты теперь живут узлами в сцене (узел Props).
@export var props: Array[Resource] = []
## Использовать запечённые в сцену ассеты узла Props (они расставлены
## вдоль кривой ночной лесной трассы). Для остальных трасс выключено —
## их обстановка генерируется автоматически.
@export var use_baked_props: bool = true
## Генерировать живой лес/камни/кусты вдоль дороги (для трасс без
## запечённых ассетов). Плотность — scenery_density.
@export var procedural_scenery: bool = false
## Плотность генерируемой обстановки: 0.5 — редко, 1.0 — стандарт, 1.5 — глухо.
@export_range(0.0, 2.0, 0.05) var scenery_density: float = 1.0
## Автоматические ворота старт/финиш и маркеры обочины.
@export var spawn_route_markers: bool = true
## Красно-белые столбики по обочинам (классика ралли).
@export var spawn_edge_posts: bool = true
## Расстояние между контрольными арками (м), 0 — отключить.
@export_range(0.0, 900.0, 10.0) var checkpoint_interval: float = 400.0
## Ставить ворота КП (жёлтые). Сами ворота — часть сгенерированной геометрии.
@export var spawn_checkpoints: bool = true

@export_group("Генерация трассы (процедурная)")
## Трасса собирается сама при каждом заходе: серпантины, полки, трамплины —
## по грамматике раллийных участков, с лимитом уклона и самозазором,
## а не «полный рандом». road_curve при этом не используется.
@export var procedural: bool = false
## Сид генерации: один и тот же сид — одна и та же трасса (рекорды честные).
@export var generation_seed: int = 20261028
## Новый сид при каждом выходе на старт (каждый заезд — новая трасса).
@export var reroll_seed_each_visit: bool = false
## Целевая длина генерируемой трассы (м).
@export_range(2000.0, 20000.0, 100.0) var procedural_length_min: float = 8000.0
@export_range(2000.0, 20000.0, 100.0) var procedural_length_max: float = 12000.0
## Минимальный радиус поворота генератора (м): 15 — шпильки возможны.
@export_range(10.0, 60.0, 1.0) var procedural_min_radius: float = 15.0
## Минимальный зазор между витками генерируемой трассы (м).
@export_range(20.0, 80.0, 1.0) var procedural_min_gap: float = 32.0

@export_group("Трава, земля, полотно — цвета")
@export var ground_color: Color = Color(0.10, 0.17, 0.07)
@export var ground_color_2: Color = Color(0.21, 0.26, 0.11)
@export var rock_color: Color = Color(0.29, 0.31, 0.32)
@export var road_color: Color = Color(0.34, 0.28, 0.19)
@export var road_color_2: Color = Color(0.45, 0.37, 0.26)
@export var shoulder_color: Color = Color(0.31, 0.25, 0.17)
@export var edge_post_color: Color = Color(0.88, 0.14, 0.10)

@export_group("Небо, свет, туман")
@export var sky_top_color: Color = Color(0.12, 0.27, 0.48)
@export var sky_horizon_color: Color = Color(0.65, 0.76, 0.86)
@export var fog_color: Color = Color(0.72, 0.79, 0.88)
## Дистанции для опционального PS1-дизер-тумана.
@export_range(40.0, 600.0, 10.0) var fog_near: float = 140.0
@export_range(80.0, 900.0, 10.0) var fog_far: float = 360.0
## Ночная трасса использует звёздное небо и лунный свет вместо дневного неба.
@export var night_mode: bool = false
@export_range(0.0, 2.0, 0.05) var star_intensity: float = 0.8
@export var sun_color: Color = Color(1.0, 0.96, 0.85)
@export var ambient_color: Color = Color(0.55, 0.61, 0.72)
@export_range(0.0, 2.0, 0.05) var ambient_energy: float = 0.8
@export_range(0.2, 3.0, 0.05) var exposure: float = 1.05
@export_range(0.0, 0.05, 0.0001) var fog_density: float = 0.0032
## Объёмный туман делает видимыми лучи фар (Forward+; можно выключить для FPS).
@export var volumetric_fog: bool = false
@export_range(0.0, 0.05, 0.0001) var volumetric_fog_density: float = 0.003
@export var screen_space_ao: bool = true
@export_range(0.0, 4.0, 0.05) var sun_energy: float = 1.4
@export_range(-80.0, 80.0, 1.0) var sun_pitch: float = -32.0
@export_range(-180.0, 180.0, 1.0) var sun_yaw: float = 35.0

@export_group("Сцепление покрытия")
## 1.0 — гравий, 0.55 — снег, 1.3 — асфальт.
@export_range(0.2, 2.0, 0.01) var grip_scale: float = 1.0
@export_range(0.2, 4.0, 0.01) var rolling_resistance_scale: float = 1.0

@export_group("PS1-оформление (стиль Colin McRae Rally PS1)")
@export var ps1_style: bool = true
## Плоские (фасетные) полигоны земли.
@export var flat_shading: bool = true
## Жёсткий дизер-туман.
@export var dither_fog: bool = true
## Постеризация палитры (0 — выкл).
@export_range(0, 8, 1) var color_banding: int = 5
## Плоское небо-градиент.
@export var sky_flat: bool = true
@export var enable_speed_fx: bool = true


## Осевая линия, которую надо строить: для процедурной трассы кривая
## собирается генератором (и кладётся в кэш), иначе — road_curve.
## ВНИМАНИЕ: для procedural это тяжёлая операция (секунды) — вызывать
## при загрузке заезда, а не из метаданных (см. get_metadata_curve).
func get_effective_curve() -> Curve3D:
	if procedural:
		return RallyTrackGenerator.build_curve(
			generation_seed,
			procedural_length_min,
			procedural_length_max,
			procedural_min_radius,
			procedural_min_gap
		)
	return road_curve


## Осевая линия для метаданных (меню, длина, габариты): БЕЗ генерации.
## Процедурная трасса отдаёт кривую, только если она уже в кэше.
func get_metadata_curve() -> Curve3D:
	if procedural:
		return RallyTrackGenerator.cached_curve_for(
			generation_seed,
			procedural_length_min,
			procedural_length_max,
			procedural_min_radius,
			procedural_min_gap
		)
	return road_curve


## Габарит трассы в плане (x, z) с учётом поля вокруг.
func get_route_bounds() -> Rect2:
	var curve: Curve3D = get_metadata_curve()
	if curve == null:
		return Rect2(Vector2.ZERO, Vector2(64, 64))
	var points: PackedVector3Array = curve.get_baked_points()
	if points.is_empty():
		return Rect2(Vector2.ZERO, Vector2(64, 64))
	var min_x: float = INF
	var min_z: float = INF
	var max_x: float = -INF
	var max_z: float = -INF
	for p in points:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	return Rect2(Vector2(min_x, min_z), Vector2(max_x - min_x, max_z - min_z))


## Прямоугольник, который покрывает вся карта (трасса + поле).
func get_terrain_rect() -> Rect2:
	var route: Rect2 = get_route_bounds()
	var margin: float = terrain_margin
	return Rect2(
		route.position - Vector2(margin, margin),
		route.size + Vector2(margin * 2.0, margin * 2.0)
	)


## Длина осевой линии (м). Для процедурной трассы — только из кэша
## (0.0, пока трасса ни разу не построена), чтобы меню не запускало
## генерацию втихую.
func get_route_length() -> float:
	var curve: Curve3D = get_metadata_curve()
	if curve == null:
		return 0.0
	return curve.get_baked_length()


func get_record_key() -> String:
	# У процедурной трассы рекорды считаются по сиду: другой сид — другая
	# трасса, подсказывать ей чужое лучшее время было бы жульничеством.
	if procedural:
		return "%s_%d" % [id, generation_seed]
	return id


## Детерминированный псевдошум [0,1) от координат — земля, обочины.
static func hash_noise(x: float, z: float) -> float:
	var s := sin(x * 12.9898 + z * 78.233) * 43758.5453
	return s - floor(s)
