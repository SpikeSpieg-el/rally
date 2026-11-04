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
## Порог скорости, ниже которого кузов не пачкается, м/с.
@export_range(0.0, 10.0, 0.05) var dirt_min_speed: float = 1.0
## Скорость налипания на гравии, грязи и траве, ед/с.
@export_range(0.0, 0.5, 0.001) var gravel_dirt_rate: float = 0.018
@export_range(0.0, 0.5, 0.001) var mud_dirt_rate: float = 0.045
@export_range(0.0, 0.5, 0.001) var grass_dirt_rate: float = 0.008
## Влажность меняет скорость налипания (при 0 и 1).
@export_range(0.0, 4.0, 0.01) var damp_dry_scale: float = 0.35
@export_range(0.0, 4.0, 0.01) var damp_wet_scale: float = 1.8
## Скорость накопления снега, ед/с.
@export_range(0.0, 0.5, 0.001) var snow_rate: float = 0.025
## Скорость высыхания грязи под дождём и без него, ед/с.
@export_range(0.0, 1.0, 0.001) var rain_wet_gain: float = 0.08
@export_range(0.0, 1.0, 0.001) var rain_dry_loss: float = 0.012
@export_range(0.0, 1.0, 0.001) var rain_wash: float = 0.035
@export_range(0.0, 1.0, 0.001) var snow_gain: float = 0.035
@export_range(0.0, 1.0, 0.001) var snow_wash_by_rain: float = 0.035
@export_range(0.0, 1.0, 0.001) var snow_melt: float = 0.004
## Смещение центров «пятен» на кузове относительно подвески.
@export_range(0.0, 1.0, 0.01) var dirt_center_spring_scale: float = 0.65
## Габариты облака брызг из-под колеса (x, y, z).
@export var spray_amount: int = 36
@export_range(0.05, 5.0, 0.05) var spray_lifetime: float = 0.55
@export var spray_direction: Vector3 = Vector3(0.0, 0.7, -1.0)
@export_range(0.0, 90.0, 1.0) var spray_spread: float = 27.0
@export var spray_gravity: Vector3 = Vector3(0.0, -9.8, 0.0)
@export_range(0.0, 20.0, 0.05) var spray_speed_min: float = 1.5
@export_range(0.0, 40.0, 0.05) var spray_speed_max: float = 5.0
@export_range(0.1, 4.0, 0.05) var spray_scale_min: float = 0.4
@export_range(0.1, 4.0, 0.05) var spray_scale_max: float = 1.4
## Размер крупинки грунта, м.
@export_range(0.001, 0.2, 0.001) var spray_grain_radius: float = 0.018
@export_range(0.001, 0.4, 0.001) var spray_grain_height: float = 0.036
@export_range(1, 16, 1) var spray_grain_segments: int = 4
@export_range(0.0, 5.0, 0.01) var spray_speed_factor: float = 0.35
@export_range(0.0, 20.0, 0.01) var spray_slip_bonus: float = 3.0
@export_range(0.0, 100.0, 0.5) var spray_speed_floor: float = 2.0
@export_range(0.0, 100.0, 0.5) var spray_speed_cap: float = 10.0
@export_range(0.0, 30.0, 0.1) var spray_min_speed: float = 3.0
@export_range(0.0, 1.0, 0.01) var spray_slip_threshold: float = 0.18
@export_range(0.0, 1.0, 0.01) var spray_wet_threshold: float = 0.3
@export var spray_dry_color: Color = Color(0.36, 0.26, 0.15)
@export var spray_wet_color: Color = Color(0.12, 0.075, 0.035)
@export var spray_snow_color: Color = Color(0.90, 0.94, 1.0)

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
@export var dust_direction: Vector3 = Vector3(0.0, 0.42, -1.0)
@export_range(0.0, 90.0, 1.0) var dust_spread: float = 32.0
@export_range(0.0, 20.0, 0.05) var dust_speed_min: float = 1.2
@export_range(0.0, 40.0, 0.05) var dust_speed_max: float = 4.2
@export var dust_gravity: Vector3 = Vector3(0.0, -4.5, 0.0)
@export_range(0.1, 5.0, 0.05) var dust_scale_min: float = 0.45
@export_range(0.1, 5.0, 0.05) var dust_scale_max: float = 1.65
@export var dust_color: Color = Color(0.43, 0.35, 0.25, 0.48)
@export_range(0.001, 1.0, 0.001) var dust_radius: float = 0.11
@export_range(0.001, 2.0, 0.001) var dust_height: float = 0.22
@export_range(1, 16, 1) var dust_segments: int = 6
@export_range(1, 16, 1) var dust_rings: int = 3
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
@export_range(0.0, 1.0, 0.01) var zone_shader_contrast: float = 0.8
## Затемнение мокрой лужи и осветление сухой рыхлой полосы (шейдер полотна).
@export_range(0.0, 1.0, 0.01) var zone_wet_darken: float = 0.38
@export_range(0.0, 1.0, 0.01) var zone_dry_lighten: float = 0.28
## Глянец лужи (0 — матовая, 1 — зеркало).
@export_range(0.0, 1.0, 0.01) var zone_puddle_roughness: float = 0.18
@export_range(0.0, 1.0, 0.01) var zone_puddle_mix: float = 0.8

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
@export_range(0.0, 1.0, 0.01) var rut_grip_loss_dry: float = 0.04
@export_range(0.0, 1.0, 0.01) var rut_grip_loss_wet: float = 0.18
@export_range(0.0, 1.0, 0.01) var packing_rolling_gain: float = 0.16
@export_range(0.0, 5.0, 0.01) var rut_rolling_soft: float = 1.8
@export_range(0.0, 5.0, 0.01) var rut_rolling_firm: float = 0.7
## Пределы изменения сцепления и сопротивления качению.
@export_range(0.1, 3.0, 0.01) var grip_min: float = 0.65
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
