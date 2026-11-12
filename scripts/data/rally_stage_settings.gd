## Настройки сцены заезда: редактор, PS1-экран, осадки, окружение.
##
## ЭТО «ПУЛЬТ» ЭФФЕКТОВ, КРОМЕ СКОРОСТИ: у ощущения скорости один пульт —
## узел `VisualEffects/Speed` (`scenes/effects/speed_effect.tscn`), общий для
## всех заездов. Файл по умолчанию —
## res://data/stage/default_stage_settings.tres: откройте его в инспекторе
## Godot и меняйте значения — сцена заезда читает их при сборке мира.
## Сцена может переопределить ресурс: у корня RallyStage есть поле `settings`.
##
## Правило для агентов: НЕ добавляйте новые числа в код сцены. Число, цвет,
## размер, скорость или порог эффекта — это @export в этом файле (или в
## RallyTrackConfig / RallyWeatherConfig / RallyFxProfile), а код только
## читает значение.
@tool
class_name RallyStageSettings
extends Resource

@export_group("Сборка и редактор")
## Пересобирать трассу сразу при открытии сцены в редакторе.
@export var preview_in_editor: bool = true
## Задержка авто-пересборки после последней правки кривой/настроек, сек.
@export_range(0.05, 5.0, 0.05) var auto_rebuild_delay: float = 0.45
## Ставить ассеты из Props на землю при каждой сборке.
@export var snap_props_on_build: bool = true
## Показывать отладочные цифры в HUD (шаг сетки земли и т.п.).
@export var show_debug_info: bool = false
## Применять point-фильтрацию текстур (PS1) к объектам сцены при заезде.
@export var apply_ps1_materials: bool = true

@export_group("PS1 / ретро-экран")
## Главный выключатель ретро-оформления (поверх `ps1_style` у трассы).
@export var ps1_enabled: bool = true
## Сила экранной PS1-стилизации (0 — без пикселизации и палитры).
@export_range(0.0, 1.0, 0.05) var retro_style_strength: float = 1.0
## Высота виртуального изображения мира; ширина следует соотношению сторон.
@export_range(180, 720, 1, "suffix:px") var retro_resolution_height: int = 270
## Лёгкая привязка вершин дороги и земли к экранной сетке (0 — без дрожания).
@export_range(0.0, 1.0, 0.05) var retro_vertex_snap: float = 0.15
## Бит на канал для экранной палитры поверх трассы. -1 — брать из трассы.
@export_range(-1, 8, 1) var retro_color_bits_override: int = -1

# Эффект скорости сюда НЕ относится: у него один пульт — узел
# `VisualEffects/Speed` (`scenes/effects/speed_effect.tscn`), общий для всех
# заездов. Поля ниже оставлены только чтобы старые .tres открывались без
# ошибок. `@export_storage` = значение читается из файла, но в инспекторе его
# нет: второго набора ползунков, который ни на что не влияет, больше нет.
# Разовый перенос старых чисел в узел — кнопка у корня этапа
# «Перенести старый ресурс в эффекты сцены».
@export_storage var speed_fx_enabled: bool = true
@export_storage var speed_effect_strength: float = 1.0
@export_storage var speed_fx_start_kmh: float = 55.0
@export_storage var speed_fx_full_kmh: float = 180.0
@export_storage var speed_blur_strength: float = 0.012
@export_storage var vignette_strength: float = 0.12
@export_storage var speed_blur_gain: float = 2.0
@export_storage var speed_cockpit_scale: float = 0.8
@export_storage var speed_edge_stretch: float = 0.02


@export_group("Осадки в мире")
## Выключатель мировых частиц (дождь/снег) без правки погодных пресетов.
@export var precipitation_enabled: bool = true
## Плотность мировых частиц осадков (множитель к пресету погоды).
@export_range(0.1, 2.0, 0.1) var precipitation_density: float = 1.0
## Сколько частиц при интенсивности 0 и 1 (дождь).
@export_range(1, 20000, 10) var rain_amount_min: int = 700
@export_range(1, 20000, 10) var rain_amount_max: int = 2400
## Сколько частиц при интенсивности 0 и 1 (снег).
@export_range(1, 20000, 10) var snow_amount_min: int = 500
@export_range(1, 20000, 10) var snow_amount_max: int = 1800
## Время жизни капли и снежинки, сек.
@export_range(0.2, 5.0, 0.05) var rain_lifetime: float = 1.15
@export_range(0.5, 12.0, 0.1) var snow_lifetime: float = 4.0
## Размер «штриха» дождя (x — толщина, y — длина), м.
@export var rain_streak_size: Vector2 = Vector2(0.02, 0.4)
## Размер снежинки, м.
@export var snow_flake_size: Vector2 = Vector2(0.07, 0.07)
## Цвет капель и снежинок (альфа — прозрачность).
@export var rain_color: Color = Color(0.70, 0.79, 0.90, 0.38)
@export var snow_color: Color = Color(0.94, 0.97, 1.00, 0.72)
## Гравитация и скорость падения.
@export var rain_gravity: Vector3 = Vector3(0.0, -12.0, 0.0)
@export_range(0.0, 80.0, 0.5) var rain_speed_min: float = 21.0
@export_range(0.0, 80.0, 0.5) var rain_speed_max: float = 29.0
@export var snow_gravity: Vector3 = Vector3(0.0, -1.6, 0.0)
@export_range(0.0, 20.0, 0.1) var snow_speed_min: float = 1.2
@export_range(0.0, 20.0, 0.1) var snow_speed_max: float = 3.0
@export_range(0.0, 90.0, 1.0) var rain_spread: float = 3.0
@export_range(0.0, 90.0, 1.0) var snow_spread: float = 25.0
@export_range(0.1, 4.0, 0.05) var rain_scale_min: float = 0.7
@export_range(0.1, 4.0, 0.05) var rain_scale_max: float = 1.25
@export_range(0.1, 4.0, 0.05) var snow_scale_min: float = 0.6
@export_range(0.1, 4.0, 0.05) var snow_scale_max: float = 1.6
## Куда «смотрит» ветер относительно камеры: скорость ветра пресета × этот сдвиг.
@export_range(0.0, 1.0, 0.001) var rain_wind_tilt: float = 0.008
@export_range(0.0, 1.0, 0.001) var snow_wind_tilt: float = 0.025
@export var rain_box_extents: Vector3 = Vector3(32.0, 9.0, 32.0)
@export var snow_box_extents: Vector3 = Vector3(28.0, 7.0, 28.0)
## Область, внутри которой живут осадки и за пределами которой их не рисуют.
@export var precipitation_aabb: AABB = AABB(Vector3(-90.0, -65.0, -90.0), Vector3(180.0, 115.0, 180.0))
## Область рождения новых частиц следует за машиной: шаг привязки, м.
@export_range(0.5, 40.0, 0.5) var anchor_grid: float = 8.0
## Высота области рождения над машиной, м.
@export_range(0.0, 60.0, 0.5) var anchor_height: float = 11.0
## Насколько область рождения сдвигается вперёд по скорости (0 — не сдвигать).
@export_range(0.0, 2.0, 0.01) var anchor_velocity_lead: float = 0.35
## Ограничение этого сдвига, м/с.
@export_range(0.0, 200.0, 1.0) var anchor_velocity_limit: float = 50.0

@export_group("Окружение и постобработка")
## Свечение (glow) в PS1-режиме и без него.
@export_range(0.0, 4.0, 0.01) var glow_intensity_ps1: float = 0.20
@export_range(0.0, 4.0, 0.01) var glow_intensity_normal: float = 0.45
@export_range(0.0, 1.0, 0.001) var glow_bloom_ps1: float = 0.005
@export_range(0.0, 1.0, 0.001) var glow_bloom_normal: float = 0.02
@export var ssao_enabled: bool = true
@export_range(0.1, 8.0, 0.1) var ssao_radius: float = 1.2
@export_range(0.0, 4.0, 0.05) var ssao_intensity: float = 1.0
@export_range(0.0, 200.0, 1.0) var volumetric_fog_length: float = 90.0
@export_range(0.0, 1.0, 0.01) var volumetric_fog_anisotropy: float = 0.35
@export var volumetric_fog_albedo: Color = Color(0.68, 0.73, 0.82)
## Насколько сильно дымка подмешивает цвет погоды (0 — не подмешивать).
@export_range(0.0, 1.0, 0.01) var volumetric_weather_tint: float = 0.4
## Насколько туман закрывает небо в густую погоду (границы авто-расчёта).
@export_range(0.0, 1.0, 0.01) var fog_sky_affect_min: float = 0.25
@export_range(0.0, 1.0, 0.01) var fog_sky_affect_max: float = 0.80
## Множитель «плотности» depth-тумана в PS1-режиме (1 — полностью).
@export_range(0.0, 1.0, 0.01) var fog_ps1_opacity: float = 1.0
## Кривая глубины тумана (1 — линейно).
@export_range(0.1, 4.0, 0.05) var fog_depth_curve: float = 1.0

@export_group("Время суток")
## Выбор «ДЕНЬ» или «НОЧЬ» в меню переворачивает освещение трассы только тогда,
## когда он отличается от её природного времени (night_mode). Эти поля —
## насколько сильно меняется свет при переходе.
## Дневной свет → ночь: солнце слабее и синее, окружение темнее.
@export_range(0.0, 1.0, 0.01) var night_sun_scale: float = 0.35
@export var night_sun_tint: Color = Color(0.6, 0.7, 1.0, 1.0)
## Насколько сильно солнце окрашивается в ночной тон (0 — не окрашивать).
@export_range(0.0, 1.0, 0.01) var night_sun_tint_strength: float = 0.7
@export_range(0.0, 2.0, 0.01) var night_ambient_scale: float = 0.55
## Ночной свет → день: солнце как на дневных трассах, окружение как у них же.
@export_range(0.2, 4.0, 0.05) var day_sun_energy: float = 1.4
@export var day_sun_color: Color = Color(1.0, 0.95, 0.82, 1.0)
@export_range(0.0, 3.0, 0.01) var day_ambient_energy: float = 0.85
## Цвета неба и окружения при переключении (как у штатных ночных и дневных трасс).
@export var night_sky_top: Color = Color(0.035, 0.045, 0.075, 1.0)
@export var night_sky_horizon: Color = Color(0.13, 0.16, 0.19, 1.0)
@export var night_ambient_color: Color = Color(0.48, 0.56, 0.72, 1.0)
@export var day_sky_top: Color = Color(0.2, 0.38, 0.6, 1.0)
@export var day_sky_horizon: Color = Color(0.75, 0.8, 0.85, 1.0)
@export var day_ambient_color: Color = Color(0.6, 0.63, 0.7, 1.0)
## Туман тоже переключается вместе со светом. Без этого дневная трасса,
## запущенная ночью, оставалась с белым туманом — кадр становился молочным,
## даже когда небо и солнце уже ночные.
@export var night_fog_color: Color = Color(0.16, 0.18, 0.2, 1.0)
@export var day_fog_color: Color = Color(0.72, 0.79, 0.88, 1.0)

@export_group("Материалы полотна и земли")
## Шероховатость земли и масштаб зерна её текстуры.
@export_range(0.0, 1.0, 0.01) var ground_surface_roughness: float = 0.97
@export_range(0.1, 6.0, 0.1) var ground_grain_scale: float = 2.4
## Шероховатость полотна и сила мелкого рельефа гравия.
@export_range(0.0, 1.0, 0.01) var road_roughness: float = 0.92
@export_range(0.0, 1.0, 0.01) var road_loose_relief: float = 1.0
## Сила рельефа полотна на асфальте (обычно почти ноль).
@export_range(0.0, 1.0, 0.01) var road_loose_relief_asphalt: float = 0.08
## Контраст камешков и накатанных колей.
@export_range(0.0, 0.5, 0.01) var road_detail_strength: float = 0.16
@export_range(0.0, 0.4, 0.01) var road_track_strength: float = 0.12

@export_group("Пятна и лужи на полотне")
## Декали поверх полотна: лужи, грязь, рыхлый гравий, снежный накат, лёд и
## трещины. Каждый вид полотна получает свой набор (RallyRoadDecalProfile),
## текстуры собираются из шума — см. scripts/road_decals.gd.
@export var road_decals_enabled: bool = true
## Предел числа пятен на трассу. 200 — примерно пятно на 10–20 м; больше — дороже кадр.
@export_range(0, 2000, 8) var road_decals_max: int = 200
## Множитель к плотности пятен из профилей вида полотна.
@export_range(0.0, 4.0, 0.05) var road_decals_density_scale: float = 1.0
## Во сколько раз пятна крупнее/мельче задуманного профилем.
@export_range(0.2, 3.0, 0.05) var road_decals_size_scale: float = 1.0
## Общая непрозрачность пятен (1 — как в профиле).
@export_range(0.0, 1.0, 0.01) var road_decals_opacity: float = 0.85
## Размер текстуры пятна: 160 — чётко и дёшево, 256 — мыло на близких планах нет.
@export_range(32, 512, 16) var road_decals_texture_size: int = 160
## Дальность, с которой пятна начинают гаснуть, м (0 — не гасить никогда).
@export_range(0.0, 400.0, 5.0) var road_decals_fade_begin: float = 90.0
@export_range(0.0, 200.0, 5.0) var road_decals_fade_length: float = 40.0
## Отмечать скользкие полосы физики лужами и рыхлой грязью в тех же местах.
@export var road_decals_mark_grip_zones: bool = true
## Карты нормалей (рельеф пятна). Выключить, если нужен максимум FPS.
@export var road_decals_use_normal_maps: bool = true
## Карта ORM: глянец луж и льда. Выключить, если нужен максимум FPS.
@export var road_decals_use_orm: bool = true
## Наборы пятен по видам полотна (data/stage/road_decals/*.tres). Каждый вид
## правится в инспекторе: пятна, цвета, шум, размеры, веса. Пусто — файлы
## читаются автоматически; виды, которых нет, добираются заводскими.
@export var road_decal_profiles: Array[Resource] = []

@export_group("Свои параметры шейдеров (максимальная правка без кода)")
## Параметры, которые применяются поверх заводских значений земли.
## Добавьте RallyShaderParameter, впишите имя uniform — и всё.
@export var ground_shader_overrides: Array[RallyShaderParameter] = []
## То же для полотна дороги (gravel_road.gdshader).
@export var road_shader_overrides: Array[RallyShaderParameter] = []
## То же для экранного пост-эффекта (speed_fx.gdshader).
@export var screen_shader_overrides: Array[RallyShaderParameter] = []

@export_group("Свои материалы")
## Если задан, используется вместо сгенерированного материала земли
## (сцена тоже может задать свой через ground_material_override).
@export var ground_material: Material = null
## То же для полотна дороги.
@export var road_material: Material = null

@export_group("Материалы процедурной обстановки")
## Включить ли PS1 point-фильтрацию у текстур обстановки.
@export var scenery_ps1_filter: bool = true
## Дальность отсечения крупных и мелких объектов обстановки, м.
@export_range(0.0, 2000.0, 10.0) var scenery_range_large: float = 420.0
@export_range(0.0, 1000.0, 5.0) var scenery_range_small: float = 240.0
## Запас на затухание дальности (fade margin).
@export_range(0.0, 200.0, 1.0) var scenery_range_margin: float = 35.0
## Три уровня геометрии у деревьев/камней: переключение по экранному размеру.
## LOD не меняет исходные сцены пропсов и их коллизии.
@export var scenery_lod_enabled: bool = true
## Больше 1 — сохранять подробный меш дальше, меньше 1 — упрощать раньше.
@export_range(0.1, 4.0, 0.1) var scenery_lod_bias: float = 1.0
## Размер пространственной ячейки MultiMesh, м (меньше — точнее отсечение).
@export_range(16.0, 512.0, 8.0) var scenery_cell_size: float = 128.0
## Разброс яркости объектов в ячейке (0 — все одинаковые).
@export_range(0.0, 1.0, 0.01) var scenery_shade_spread: float = 0.22
@export_range(0.0, 1.0, 0.01) var scenery_shade_base: float = 0.78
## Дальше какого отступа от кромки полотна лес перестаёт писать тень, м.
## Теневой проход — самое дорогое место густой обстановки, а вдали за туманом
## тени всё равно не разобрать. 0 — тени у всей обстановки.
@export_range(0.0, 500.0, 5.0) var scenery_shadow_max_offset: float = 55.0

@export_group("Скорость сборки карты")
## Во сколько раз реже берутся строки полотна для его КОЛЛИЗИИ (видимая
## лента всегда строится по `road_step`). 2 — вдвое меньше треугольников
## в физике дороги: на 9-метровых волнах ошибка меньше сантиметра, а сборка
## карты заметно быстрее. 1 — полная точность.
@export_range(1, 8, 1) var road_collider_row_stride: int = 2
## Во сколько раз реже берутся ячейки рельефа для его КОЛЛИЗИИ (видимый
## рельеф всегда строится по `terrain_cell`). 2 — вчетверо меньше
## треугольников в физике земли. 1 — полная точность.
@export_range(1, 8, 1) var terrain_collider_stride: int = 2


## Применить пользовательские параметры шейдера к материалу.
func apply_shader_overrides(material: ShaderMaterial, parameters: Array[RallyShaderParameter]) -> void:
	RallyShaderParameter.apply_all(material, parameters)


## Действует ли ретро-оформление для этой трассы.
func is_retro(track: Resource) -> bool:
	if not ps1_enabled or track == null:
		return false
	return bool(track.get("ps1_style"))


## Сколько бит палитры подавать в экранный шейдер.
func color_bits_for(track: Resource) -> int:
	if retro_color_bits_override >= 0:
		return retro_color_bits_override
	if track == null:
		return 0
	return int(track.get("color_banding"))


## Есть ли дизер тумана у трассы.
func dither_for(track: Resource) -> bool:
	return track != null and bool(track.get("dither_fog"))
