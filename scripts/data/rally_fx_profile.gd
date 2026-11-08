## Пульт эффектов: следы шин, комья грунта, пыль из-под колёс, загрязнение
## кузова, «живые» скользкие полосы и физика грунта (колея/накат).
##
## Всё, что раньше было константами в tire_marks.gd, surface_effects.gd,
## road_surface.gd и rally_stage.gd/live_surface_grip, теперь живёт здесь.
## Файл по умолчанию — res://data/stage/default_fx_profile.tres.
## Сцену можно переопределить полем `fx_profile` у корня RallyStage.
##
## ВАЖНО для агентов: не возвращайте числа обратно в код. Новый параметр
## эффекта — новый @export здесь, и код читает его с дефолтом.
@tool
class_name RallyFxProfile
extends Resource

@export_group("Сила и производительность")
## Множитель общего числа частиц эффектов колёс: 1 — заводской, 2 — вдвое гуще.
@export_range(0.0, 4.0, 0.05) var fx_intensity: float = 1.0
## Сколько раз в секунду пересчитывать частицы из состояния колеса.
@export_range(10.0, 60.0, 1.0) var fx_update_hz: float = 30.0
@export var fx_physics_fps: int = 60
## Светящиеся точки на поднятых частицах: «солнечная пыль» на сквозняке.
@export var fx_sparkle_enabled: bool = true
@export_range(0.0, 2.0, 0.01) var fx_sparkle_strength: float = 0.16
@export var fx_sparkle_color: Color = Color(1.0, 0.86, 0.58, 1.0)
@export_range(0.0, 3.0, 0.05) var fx_sparkle_emission: float = 0.85

@export_group("Следы шин")
## Сколько отрезков хранит один буфер (больше — длиннее следы, дороже).
@export_range(16, 2048, 16) var chunk_size: int = 128
## Сколько буферов в кольце (общая длина следа ≈ chunk_size × count).
@export_range(1, 64, 1) var chunk_count: int = 16
## Минимальное и максимальное расстояние между точками следа, м.
@export_range(0.02, 2.0, 0.01) var min_distance: float = 0.18
@export_range(0.5, 20.0, 0.1) var max_distance: float = 5.0
## Как часто пересобирать меш следа, сек.
@export_range(0.01, 1.0, 0.01) var flush_interval: float = 0.08
## Шаг комочков грунта вдоль следа, м.
@export_range(0.05, 5.0, 0.05) var soil_spacing: float = 0.7
## Порог «рыхлости», ниже которого комочки не рисуются.
@export_range(0.0, 1.0, 0.01) var min_looseness: float = 0.25
## Скорость, ниже которой следы не пишутся, м/с.
@export_range(0.0, 10.0, 0.05) var min_speed: float = 0.8
## Порог скольжения для «сильного» тёмного следа.
@export_range(0.01, 3.0, 0.01) var slip_start: float = 0.18
@export_range(0.05, 5.0, 0.01) var slip_full: float = 0.8
## Прозрачность слабого и сильного следа (0–1).
@export_range(0.0, 1.0, 0.01) var alpha_min: float = 0.07
@export_range(0.0, 1.0, 0.01) var alpha_max: float = 0.38
@export_range(0.0, 1.0, 0.01) var alpha_asphalt_scale: float = 0.5
@export_range(0.0, 1.0, 0.01) var alpha_limit: float = 0.55
@export_range(0.0, 1.0, 0.01) var rut_alpha_bonus: float = 0.2
@export_range(0.0, 1.0, 0.01) var alpha_cutoff: float = 0.025
## Пределы ширины шины при переводе в метры (мм → м), м.
@export_range(0.01, 2.0, 0.01) var tire_width_min_m: float = 0.12
@export_range(0.01, 2.0, 0.01) var tire_width_max_m: float = 0.45
## Ширина следа = ширина шины (мм) / 1000 × этот множитель.
@export_range(0.0, 2.0, 0.01) var width_scale: float = 1.0
@export_range(0.0, 2.0, 0.01) var rut_width_bonus: float = 0.3
## Высота «комочка» над землёй, м (чтобы не проваливался).
@export_range(0.0, 0.1, 0.001) var surface_offset: float = 0.012
## Нормирующая глубина колеи для визуального утолщения следа, м.
@export_range(0.001, 0.3, 0.001) var rut_depth_scale: float = 0.065
## Порог снега, при котором след считается снежным.
@export_range(0.0, 1.0, 0.01) var snow_track_threshold: float = 0.45
## Масштаб комочков грунта (радиус min/max), м.
@export_range(0.001, 0.2, 0.001) var soil_radius_min: float = 0.012
@export_range(0.001, 0.3, 0.001) var soil_radius_max: float = 0.028
@export_range(0.0, 0.1, 0.001) var soil_height: float = 0.035
@export_range(0.0, 0.1, 0.001) var soil_offset: float = 0.010
@export_range(0.5, 3.0, 0.05) var soil_side_min: float = 0.85
@export_range(0.5, 3.0, 0.05) var soil_side_max: float = 1.15

@export_group("Цвета следов и комьев")
@export var asphalt_mark_color: Color = Color(0.035, 0.030, 0.027)
@export var grass_mark_color: Color = Color(0.180, 0.140, 0.075)
@export var mud_mark_color: Color = Color(0.130, 0.085, 0.050)
@export var snow_mark_color: Color = Color(0.420, 0.480, 0.510)
@export var gravel_mark_color: Color = Color(0.220, 0.170, 0.120)
## Куда темнеет комок грунта при мокрой дороге.
@export var wet_soil_color: Color = Color(0.12, 0.075, 0.035)
@export_range(0.0, 1.0, 0.01) var soil_lighten: float = 0.18
@export_range(0.0, 1.0, 0.01) var soil_wet_darken: float = 0.6

@export_group("Грязь и пыль на кузове")
## Какие меши кузова пачкаются: префиксы имён. Пусто — старый список из кода.
@export var dirt_body_prefixes: PackedStringArray = PackedStringArray(["Mitsubishi_Body"])
## Меши, которые грязь не трогает (стёкла, фары, салон, диски).
@export var dirt_body_skip: PackedStringArray = PackedStringArray(
	["glass", "light", "window", "interior", "wheel", "tire", "hub"]
)
## Цвет сухой пыли на кузове и снежного налёта.
@export var dirt_color: Color = Color(0.32, 0.235, 0.14, 1.0)
@export var body_snow_color: Color = Color(0.80, 0.85, 0.90, 1.0)
## Насколько густо кузов покрывается пылью (1 — заводской вид).
@export_range(0.2, 3.0, 0.05) var body_coverage: float = 1.35
## Мягкость краёв пятен: больше — грязь расползается плавнее.
@export_range(0.1, 2.0, 0.05) var body_edge_softness: float = 0.85
## Общая сила слоя грязи и снега поверх уже заданной физики налипания.
@export_range(0.0, 3.0, 0.05) var body_dirt_buildup: float = 1.0
@export_range(0.0, 3.0, 0.05) var body_snow_buildup: float = 0.6
## Непрозрачность слоя при полном налипании (1 — почти сплошная грязь).
@export_range(0.0, 1.0, 0.01) var body_alpha: float = 0.92
## Насколько далеко от колеса расходится пятно по кузову (1 — заводской вид).
@export_range(0.2, 3.0, 0.05) var body_spread: float = 1.0
## Порог скорости, ниже которого кузов не пачкается, м/с.
@export_range(0.0, 10.0, 0.05) var dirt_min_speed: float = 1.0
## Скорость налипания на гравии, грязи и траве, ед/с.
@export_range(0.0, 0.5, 0.001) var gravel_dirt_rate: float = 0.004
@export_range(0.0, 0.5, 0.001) var mud_dirt_rate: float = 0.008
@export_range(0.0, 0.5, 0.001) var grass_dirt_rate: float = 0.003
## Влажность меняет скорость налипания (при 0 и 1).
@export_range(0.0, 4.0, 0.01) var damp_dry_scale: float = 0.35
@export_range(0.0, 4.0, 0.01) var damp_wet_scale: float = 1.3
## Скорость накопления снега, ед/с.
@export_range(0.0, 0.5, 0.001) var snow_rate: float = 0.005
## Скорость высыхания грязи под дождём и без него, ед/с.
@export_range(0.0, 1.0, 0.001) var rain_wet_gain: float = 0.08
@export_range(0.0, 1.0, 0.001) var rain_dry_loss: float = 0.012
@export_range(0.0, 1.0, 0.001) var rain_wash: float = 0.035
@export_range(0.0, 1.0, 0.001) var snow_gain: float = 0.006
@export_range(0.0, 1.0, 0.001) var snow_wash_by_rain: float = 0.035
@export_range(0.0, 1.0, 0.001) var snow_melt: float = 0.004
## Смещение центров «пятен» на кузове относительно подвески.
@export_range(0.0, 1.0, 0.01) var dirt_center_spring_scale: float = 0.65


@export_group("Брызги из-под колеса (общие)")
## Резервное направление выброса для старых ресурсов без профилей покрытий.
@export var spray_direction: Vector3 = Vector3(0.0, 0.7, -1.0)
## Размер крупинки грунта, м.
@export_range(0.001, 0.2, 0.001) var spray_grain_radius: float = 0.018
@export_range(0.001, 0.4, 0.001) var spray_grain_height: float = 0.036
@export_range(1, 16, 1) var spray_grain_segments: int = 4
## Сколько колец у зерна комья (2 — самый дешёвый вид «крупинки»).
@export_range(1, 8, 1) var spray_grain_rings: int = 2
@export_range(0.0, 30.0, 0.1) var spray_min_speed: float = 3.0
@export_range(0.0, 1.0, 0.01) var spray_slip_threshold: float = 0.18
@export_range(0.0, 1.0, 0.01) var spray_wet_threshold: float = 0.3
@export var spray_dry_color: Color = Color(0.36, 0.26, 0.15)
@export var spray_wet_color: Color = Color(0.12, 0.075, 0.035)
@export var spray_snow_color: Color = Color(0.90, 0.94, 1.0)

@export_group("Дым и облака над колесом")
## Высота точки выброса над точкой контакта шины, м.
@export_range(0.0, 1.0, 0.01) var foam_height: float = 0.09
## Сколько живёт клуб и насколько он вырастает за жизнь.
@export_range(0.2, 6.0, 0.05) var foam_lifetime: float = 1.35
@export_range(1.0, 6.0, 0.05) var foam_growth: float = 2.4
## Радиус пятна рождения клубов как доля размера клуба (1 — по всему клубу).
@export_range(0.05, 2.0, 0.01) var foam_emission_radius: float = 0.55
## Размер клуба (радиус базовой меш-плоскости), м.
## Размер клуба: сторона квада = foam_size × 2, и на пике жизни клуб ещё
## растёт в foam_scale_max × particle_scale × foam_growth раз. Держите итог
## около 1–1.8 м: клуб крупнее машины рождается под аркой и читается как
## «пыль сквозь кузов», потому что камера видит его центр ближе к себе, чем
## боковину. Проверяется в tools/check_project.py::check_puff_size.
@export_range(0.02, 2.0, 0.005) var foam_size: float = 0.165
@export_range(0.1, 4.0, 0.05) var foam_scale_min: float = 0.55
@export_range(0.1, 4.0, 0.05) var foam_scale_max: float = 1.35
## Куда и с какой силой летят клубы (направление в будущее движения дороги).
## Вертикальный подброс намеренно небольшой: клуб должен подниматься выбросом
## и сразу оседать, а не висеть над колесом.
@export var foam_direction: Vector3 = Vector3(0.0, 0.42, 0.6)
@export_range(0.0, 90.0, 1.0) var foam_spread: float = 42.0
@export_range(0.0, 20.0, 0.05) var foam_speed_min: float = 0.4
@export_range(0.0, 40.0, 0.05) var foam_speed_max: float = 2.4
## Гравитация клубов: выброс поднимает облако, а тяжесть возвращает его к земле.
## Слишком слабая гравитация вместе с демпфированием давала «невесомые»
## клубы, замирающие в воздухе.
@export var foam_gravity: Vector3 = Vector3(0.0, -2.8, 0.0)
## Сколько всего клубов на одно колесо (база; уровни и покрытия масштабируют).
@export_range(1, 600, 1) var foam_amount: int = 52
## Во сколько раз клубы гуще на мокром покрытии и сколько даёт мокрота.
@export_range(0.0, 4.0, 0.05) var foam_wet_boost: float = 1.7
@export_range(0.0, 1.0, 0.01) var foam_alpha: float = 0.42
## Есть ли у клубов светящиеся пылинки внутри.
@export var foam_sparkle: bool = true
## Клубы принимают свет (false — простой непрозрачный по свету цвет, дешевле).
@export var foam_lit: bool = false
## Сколько своего света у клубов (видно на снегу и в тени).
@export_range(0.0, 2.0, 0.01) var foam_emission: float = 0.18
## Насколько клубы сплющены по вертикали (0 — шар, 1 — плоский блин).
@export_range(0.0, 1.0, 0.01) var foam_flatness: float = 0.35
## Скорость вращения клубов вокруг своей оси, °/с.
@export_range(0.0, 180.0, 1.0) var foam_spin: float = 35.0
## Клубы закручивает турбулентностью: 0 — ровные шары, 3 — клубящаяся стена.
@export_range(0.0, 4.0, 0.05) var foam_turbulence: float = 1.6
## Масштаб турбулентных завихрений: меньше — крупные вихри, больше — мелкая рябь.
@export_range(0.5, 20.0, 0.1) var foam_turbulence_scale: float = 4.5
## Замедление клубов: 0 — летят до конца, 3 — быстро повисают в воздухе.
## Держим умеренным: сильное демпфирование гасит скорость и оставляет пыль
## висеть на месте, как в невесомости, а нулевое превращает клуб в снаряд.
@export_range(0.0, 5.0, 0.05) var foam_damping_min: float = 0.2
@export_range(0.0, 5.0, 0.05) var foam_damping_max: float = 0.7
## Разброс жизни клубов: 0 — все гаснут одновременно, 1 — вразнобой.
@export_range(0.0, 1.0, 0.01) var foam_lifetime_randomness: float = 0.35

@export_group("Комья и капли из-под колеса")
## Сколько живёт комок и насколько отличается по размеру.
@export_range(0.1, 4.0, 0.05) var grit_lifetime: float = 0.95
@export_range(0.0, 90.0, 1.0) var grit_spread: float = 42.0
## Начальная скорость комьев. Не «выстрел»: комок должен выпрыгивать
## из-под колеса и быстро терять скорость в воздухе.
@export_range(0.0, 40.0, 0.05) var grit_speed_min: float = 0.7
@export_range(0.0, 60.0, 0.05) var grit_speed_max: float = 3.6
## Тяжесть комьев: настоящая баллистика, комья падают на землю.
@export var grit_gravity: Vector3 = Vector3(0.0, -11.0, 0.0)
## Сопротивление воздуха: без него круглые крупинки летят ровными
## траекториями, как пули. С торможением они «клюют» вниз и падают.
@export_range(0.0, 5.0, 0.05) var grit_damping_min: float = 0.5
@export_range(0.0, 5.0, 0.05) var grit_damping_max: float = 1.4
@export_range(0.5, 4.0, 0.05) var grit_scale_min: float = 0.55
@export_range(0.5, 6.0, 0.05) var grit_scale_max: float = 2.2
## Сколько всего комьев на одно колесо (уровни и покрытия масштабируют).
@export_range(1, 600, 1) var grit_amount: int = 68
## Светятся ли отлетающие капли/комья собственным бликом (вода и снег — да).
@export_range(0.0, 1.0, 0.01) var grit_specular: float = 0.35
## Крупинки «загораются» на солнце: подсветка вершинных цветов частиц.
@export_range(0.0, 2.0, 0.01) var grit_light_boost: float = 0.22
## Разброс жизни комьев: комья не исчезают все разом.
@export_range(0.0, 1.0, 0.01) var grit_lifetime_randomness: float = 0.5
## Скорость вращения комьев в полёте, °/с.
@export_range(0.0, 360.0, 1.0) var grit_spin: float = 0.0

@export_group("Разлёт частиц по колёсам")
## Первые секунды после выброса частица ещё идёт по инерции машины.
@export_range(0.0, 1.0, 0.01) var inherit_velocity_ratio: float = 0.35
## Поток воздуха сдувает пыль назад относительно машины.
@export_range(0.0, 3.0, 0.05) var wind_pull: float = 0.55
## Пыль разлетается в стороны от колеса (0 — строго по ходу, больше — шире).
@export_range(0.0, 2.0, 0.01) var side_splay: float = 0.35
## Насколько источник вынесен наружу от центра колеса, м. 0 — ровно под
## колесом, 0.12 — у внешней боковины шины. Большие значения уводили пыль
## в сторону от колеса и читались как «эффект не из-под машины».
@export_range(0.0, 3.0, 0.01) var spawn_outward: float = 0.12
## Насколько источник сдвинут назад по ходу движения, м: пыль летит за машину.
## Оставляем почти нулевым, чтобы частицы рождались у пятна контакта шины.
@export_range(0.0, 3.0, 0.01) var spawn_behind: float = 0.05
## Насколько выброс усиливается на повороте руля.
@export_range(0.0, 3.0, 0.05) var steer_boost: float = 0.8
## Вклад ручника: машина боком — самый зрелищный шлейф.
@export_range(0.0, 3.0, 0.05) var handbrake_boost: float = 1.0

@export_group("Отдельные эффекты покрытий")
## Включает эффекты контакта шин с гравием, грязью, травой, снегом и асфальтом.
@export var surface_fx_enabled: bool = true
## По одному RallySurfaceFxProfile на каждый тип: у каждого свои цвета и три уровня.
@export var surface_fx_profiles: Array[RallySurfaceFxProfile] = []

@export_group("Пыль из-под задних колёс")
@export var dust_enabled: bool = true
@export_range(0, 5000, 1) var dust_amount: int = 64
@export_range(0.05, 5.0, 0.05) var dust_lifetime: float = 0.9
@export var dust_emission_extents: Vector3 = Vector3(0.78, 0.05, 0.24)
@export var dust_direction: Vector3 = Vector3(0.0, 0.34, -1.0)
@export_range(0.0, 90.0, 1.0) var dust_spread: float = 32.0
@export_range(0.0, 20.0, 0.05) var dust_speed_min: float = 0.9
@export_range(0.0, 40.0, 0.05) var dust_speed_max: float = 3.2
@export var dust_gravity: Vector3 = Vector3(0.0, -6.5, 0.0)
@export_range(0.1, 5.0, 0.05) var dust_scale_min: float = 0.45
@export_range(0.1, 5.0, 0.05) var dust_scale_max: float = 1.65
@export var dust_color: Color = Color(0.43, 0.35, 0.25, 0.55)
## Сплющенность облака по вертикали (0 — шар, 1 — плоский блин).
@export_range(0.0, 1.0, 0.01) var dust_flatness: float = 0.4
## Вращение клубов облака в полёте, °/с.
@export_range(0.0, 180.0, 1.0) var dust_spin: float = 25.0
## Масштаб завихрений: меньше — крупные вихри, больше — мелкая рябь.
@export_range(0.5, 20.0, 0.1) var dust_turbulence_scale: float = 3.5
## Сила влияния завихрений на частицу (доля от скорости).
@export_range(0.0, 1.0, 0.01) var dust_turbulence_influence: float = 0.22
## Разброс жизни облака и его торможение в воздухе.
@export_range(0.0, 1.0, 0.01) var dust_lifetime_randomness: float = 0.4
@export_range(0.0, 5.0, 0.05) var dust_damping_min: float = 0.25
@export_range(0.0, 5.0, 0.05) var dust_damping_max: float = 0.7
## Насколько облако за кормой раздувается за жизнь частицы.
@export_range(1.0, 6.0, 0.05) var dust_growth: float = 2.8
## Завихрения в шлейфе: 0 — ровный поток, 3 — клубящаяся стена пыли.
@export_range(0.0, 4.0, 0.05) var dust_turbulence: float = 1.8
@export_range(0.001, 1.0, 0.001) var dust_radius: float = 0.11
@export_range(0.0, 100.0, 0.5) var dust_min_speed_kmh: float = 8.0
@export_range(0.0, 3.0, 0.01) var dust_slip_threshold: float = 0.32
@export_range(0.0, 1.0, 0.01) var dust_handbrake_slip: float = 0.85
@export var dust_aabb: AABB = AABB(Vector3(-30.0, -15.0, -30.0), Vector3(60.0, 60.0, 60.0))

@export_group("Скользкие полосы на трассе")
## Включать локальные скользкие участки (они видны и в шейдере полотна).
@export var grip_zones_enabled: bool = true
## С какого метра начинаются полосы и за сколько метров до финиша кончаются.
@export_range(0.0, 1000.0, 5.0) var zone_start: float = 150.0
@export_range(0.0, 1000.0, 5.0) var zone_end_margin: float = 40.0
## Длина «ячейки» полос, м.
@export_range(20.0, 1000.0, 5.0) var zone_period: float = 240.0
## Размер лужи вдоль и поперёк, м.
@export_range(0.5, 50.0, 0.5) var zone_length: float = 20.0
@export_range(0.1, 10.0, 0.1) var zone_half_width: float = 1.5
## Насколько сильно падает сцепление в полосе (0 — ровно, 0.5 — скользко).
@export_range(0.0, 0.9, 0.01) var zone_grip_loss_strong: float = 0.20
@export_range(0.0, 0.9, 0.01) var zone_grip_loss_weak: float = 0.13
## Поперечное смещение лужи от оси (доля полуширины полотна, но не больше лимита).
@export_range(0.0, 1.0, 0.01) var zone_lateral_fraction: float = 0.45
@export_range(0.0, 5.0, 0.1) var zone_lateral_limit: float = 1.5
## Ширина полосы в шейдере (метры от центра лужи).
@export_range(0.1, 10.0, 0.1) var zone_shader_half_width: float = 1.5
## Плавные границы лужи в шейдере, м.
@export_range(0.0, 5.0, 0.1) var zone_shader_softness: float = 0.7
@export_range(0.0, 5.0, 0.1) var zone_shader_fade: float = 3.0
## Насколько шейдер затемняет/осветляет полосу.
## Насколько шейдер полотна рисует полосу сам. Полосы теперь отмечают декали
## (RoadDecals), поэтому в шейдере остаётся слабый мокрый след: 0 — не рисовать.
@export_range(0.0, 1.0, 0.01) var zone_shader_contrast: float = 0.28
## Затемнение мокрой лужи и осветление сухой рыхлой полосы (шейдер полотна).
@export_range(0.0, 1.0, 0.01) var zone_wet_darken: float = 0.38
@export_range(0.0, 1.0, 0.01) var zone_dry_lighten: float = 0.28
## Глянец лужи (0 — матовая, 1 — зеркало).
@export_range(0.0, 1.0, 0.01) var zone_puddle_roughness: float = 0.18
@export_range(0.0, 1.0, 0.01) var zone_puddle_mix: float = 0.35

@export_group("Физика грунта (колея и накат)")
## Размер ячейки памяти грунта, м.
@export_range(0.05, 5.0, 0.05) var surface_cell_size: float = 0.4
## Максимум ячеек (память ограничена кольцом вытеснения).
@export_range(64, 200000, 256) var surface_max_cells: int = 24000
## Максимальная глубина колеи: мягкий грунт/снег и плотный/трава, м.
@export_range(0.0, 0.5, 0.001) var depth_soft: float = 0.065
@export_range(0.0, 0.5, 0.001) var depth_firm: float = 0.018
@export_range(0.0, 0.5, 0.001) var depth_grass: float = 0.035
## Насколько глубина зависит от влажности (при 0 и 1).
@export_range(0.0, 2.0, 0.01) var depth_dry_scale: float = 0.6
@export_range(0.0, 2.0, 0.01) var depth_wet_scale: float = 1.0
## Влияние наката и колеи на сцепление.
@export_range(-1.0, 1.0, 0.01) var packing_grip_gravel: float = 0.08
@export_range(-1.0, 1.0, 0.01) var packing_grip_other: float = -0.10
## Снег: укатанная линия «схватывается» и держит ЛУЧШЕ свежей каши, поэтому
## знак положительный (у грязи накат, наоборот, скользит).
@export_range(-1.0, 1.0, 0.01) var packing_grip_snow: float = 0.22
@export_range(0.0, 1.0, 0.01) var rut_grip_loss_dry: float = 0.04
@export_range(0.0, 1.0, 0.01) var rut_grip_loss_wet: float = 0.18
@export_range(0.0, 1.0, 0.01) var packing_rolling_gain: float = 0.16
@export_range(0.0, 5.0, 0.01) var rut_rolling_soft: float = 1.8
@export_range(0.0, 5.0, 0.01) var rut_rolling_firm: float = 0.7
## Снег: рыхлая колея тормозит слабее грязи, иначе машина буксует на месте.
@export_range(0.0, 5.0, 0.01) var rut_rolling_snow: float = 0.55
## Пределы изменения сцепления и сопротивления качению.
@export_range(0.1, 3.0, 0.01) var grip_min: float = 0.65
## Нижний предел сцепления на снегу: дорога, а не каток.
@export_range(0.1, 1.5, 0.01) var grip_min_snow: float = 0.82
@export_range(0.1, 3.0, 0.01) var grip_max: float = 1.12
@export_range(0.1, 5.0, 0.01) var rolling_min: float = 0.8
@export_range(0.1, 5.0, 0.01) var rolling_max: float = 2.8
## Сколько «работы» оставляет отпечаток (нагрузка/скорость/скольжение).
@export_range(0.0, 1.0, 0.001) var imprint_load_scale: float = 0.65
@export_range(0.0, 1.0, 0.001) var imprint_slip_base: float = 0.12
@export_range(0.0, 2.0, 0.001) var imprint_slip_scale: float = 0.9
@export_range(0.0, 10.0, 0.01) var imprint_speed_scale: float = 5.0
@export_range(0.0, 2.0, 0.01) var imprint_load_limit: float = 2.5
@export_range(0.0, 2.0, 0.01) var imprint_speed_limit: float = 2.0
@export_range(0.0, 0.2, 0.001) var imprint_delta_limit: float = 0.05
