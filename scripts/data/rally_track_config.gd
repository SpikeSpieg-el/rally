## Описание одной трассы. Всё настраивается в инспекторе Godot:
## откройте любой файл из res://data/tracks/ и меняйте параметры.
## Никаких констант в коде генератора: он читает только этот ресурс.
class_name RallyTrackConfig
extends Resource

enum StageKind { FOREST, MOUNTAIN, SUSPENSION, RANGE, SNOW, COAST, DESERT }

@export_group("Описание")
@export var id: String = "track"
@export var display_name: String = "Трасса"
@export_multiline var description: String = "Описание трассы."
@export var surface_name: String = "Гравий"
@export_range(1, 5, 1) var difficulty: int = 3
## Эталонное время прохождения — для таблицы рекордов и HUD.
@export_range(20.0, 300.0, 1.0) var target_time: float = 90.0

@export_group("Тип трассы")
## Лес / Горы / Подвеска / Полигон / Снег / Побережье / Пустыня.
## Влияет только на набор параметров по умолчанию.
@export_enum("Лес", "Горы", "Подвеска", "Полигон", "Снег", "Побережье", "Пустыня") var kind: int = StageKind.FOREST
## Плоская трасса-полигон (ровная плоскость вместо высотного поля).
@export var flat: bool = false
## Длина маршрута в метрах. 1200–1600 — классическая длина спецучастка.
@export_range(200.0, 2400.0, 10.0) var length: float = 1400.0
@export_range(3.0, 12.0, 0.1) var road_half_width: float = 4.2
@export_range(0.0, 1.0, 0.01) var offroad_grip: float = 0.65

@export_group("Сид и случайность")
@export var map_seed: int = 1337
## Если включено — каждый заезд генерирует новый сид (режим «всегда случайно»).
@export var random_seed: bool = false
@export_range(0.0, 1.0, 0.01) var seed_variation: float = 0.55

@export_group("Маршрут — раллийные углы")
## Вероятность, что участок — поворот (0 = прямая, 1 = сплошные углы).
@export_range(0.0, 1.0, 0.01) var corner_density: float = 0.6
## Длина участков в метрах (каждый участок — один поворот или прямая).
@export_range(30.0, 220.0, 5.0) var segment_min: float = 60.0
@export_range(30.0, 220.0, 5.0) var segment_max: float = 140.0
## Размерность типов углов (доля среди всех поворотных участков).
@export_range(0.0, 1.0, 0.01) var hairpin_share: float = 0.28
@export_range(0.0, 1.0, 0.01) var sweeper_share: float = 0.34
@export_range(0.0, 1.0, 0.01) var chicane_share: float = 0.18
## Остальное — прямые и трамплины (полезно на равнинных трассах).
@export_range(0.0, 1.0, 0.01) var jump_share: float = 0.12
## Радиус и угол поворотов.
@export_range(8.0, 30.0, 1.0) var hairpin_radius_min: float = 11.0
@export_range(8.0, 30.0, 1.0) var hairpin_radius_max: float = 20.0
@export_range(120.0, 420.0, 10.0) var hairpin_angle_min: float = 150.0
@export_range(120.0, 180.0, 1.0) var hairpin_angle_max: float = 176.0
@export_range(40.0, 220.0, 5.0) var sweeper_radius_min: float = 55.0
@export_range(40.0, 220.0, 5.0) var sweeper_radius_max: float = 130.0
@export_range(15.0, 90.0, 1.0) var sweeper_angle_min: float = 25.0
@export_range(15.0, 90.0, 1.0) var sweeper_angle_max: float = 70.0
@export_range(8.0, 36.0, 1.0) var chicane_radius_min: float = 13.0
@export_range(8.0, 36.0, 1.0) var chicane_radius_max: float = 24.0
## Демо-режим «всегда одинаково»: углы не зависят от seed (для предпросмотра).
@export var corner_pattern_fixed: bool = false

@export_group("Рельеф")
@export_range(0.0, 8.0, 0.05) var hill_amplitude: float = 1.6
@export_range(0.005, 0.08, 0.001) var hill_frequency: float = 0.025
@export_range(0.0, 1.5, 0.01) var bump_amount: float = 0.4
@export_range(0.0, 1.0, 0.01) var whoops_amount: float = 0.12
@export_range(0.0, 3.0, 0.05) var crest_amount: float = 0.9
@export_range(0.0, 2.0, 0.05) var offroad_hills: float = 0.9

@export_group("Окружение")
@export_range(0, 400, 1) var tree_count: int = 140
@export_range(0, 120, 1) var rock_count: int = 22
@export_range(0, 160, 1) var bush_count: int = 60
## Указательные щиты у ключевых поворотов (стиль раллийных спецучастков).
@export_range(0, 40, 1) var sign_count: int = 10
@export_range(0, 40, 1) var slalom_cones: int = 0
@export_range(60.0, 250.0, 5.0) var scenery_radius: float = 150.0
@export_range(8.0, 40.0, 1.0) var road_clearance: float = 12.0
@export var tree_color: Color = Color(0.07, 0.25, 0.12)
@export var bush_color: Color = Color(0.12, 0.32, 0.14)
@export var rock_color: Color = Color(0.29, 0.31, 0.32)
@export var ground_color: Color = Color(0.10, 0.17, 0.07)
@export var ground_color_2: Color = Color(0.21, 0.26, 0.11)
@export var road_color: Color = Color(0.36, 0.29, 0.20)
@export var road_color_2: Color = Color(0.46, 0.38, 0.27)

@export_group("Погода и свет")
@export var sky_top_color: Color = Color(0.12, 0.27, 0.48)
@export var sky_horizon_color: Color = Color(0.65, 0.76, 0.86)
@export var fog_color: Color = Color(0.72, 0.79, 0.88)
## PS1-туман: жёсткие директричные границы (Colin McRae Rally 1/2).
@export_range(40.0, 300.0, 10.0) var fog_near: float = 130.0
@export_range(80.0, 600.0, 10.0) var fog_far: float = 320.0
@export_range(0.0, 4.0, 0.05) var sun_energy: float = 1.4
@export_range(-80.0, 80.0, 1.0) var sun_pitch: float = -32.0
@export_range(-180.0, 180.0, 1.0) var sun_yaw: float = 35.0

@export_group("Сцепление")
## Общий множитель сцепления. 1.0 — гравий, 0.55 — снег, 1.3 — асфальт.
@export_range(0.2, 2.0, 0.01) var grip_scale: float = 1.0
@export_range(0.2, 4.0, 0.01) var rolling_resistance_scale: float = 1.0

@export_group("Генерация сетки")
@export_range(65, 241, 2) var terrain_grid_size: int = 161
@export_range(0.4, 4.0, 0.1) var road_step: float = 1.0
@export var enable_speed_fx: bool = true

@export_group("Контрольные точки")
## Расстояние между контрольными КПП в метрах (0 = отключить).
@export_range(0.0, 600.0, 10.0) var checkpoint_interval: float = 350.0

@export_group("PS1-оформление (стиль Colin McRae Rally PS1)")
##master switch for the low-poly PS1 look.
@export var ps1_style: bool = true
## Faceted (flat-shaded) terrain — like PS1 polygons.
@export var flat_shading: bool = true
## Dithered distance fog — hard PS1 fog bands instead of smooth.
@export var dither_fog: bool = true
## Posterization: number of color levels per channel (0 = off).
@export_range(0, 8, 1) var color_banding: int = 5
## Red/white curbs on road edges (rally rumble strips).
@export var road_rumble: bool = true
## Flat gradient sky instead of curved dome.
@export var sky_flat: bool = true


func is_flat() -> bool:
	return flat or kind == StageKind.RANGE


func get_record_key(seed_value: int) -> String:
	if random_seed:
		return "%s_random" % id
	return "%s_%d" % [id, seed_value]


## Детерминированное число [0,1) из сида. Не зависит от RandomNumberGenerator,
## поэтому превью в меню рисует ровно ту же трассу, что и гоночная сцена.
static func hash_unit(seed_value: int, salt: float) -> float:
	var x: float = sin(float(absi(seed_value) % 100000) * 0.01723 + salt * 12.9898) * 43758.5453
	return x - floor(x)


## Детерминированный псевдошум [0,1) от координат — для gravel-ямочек вне дороги.
static func hash_noise(x: float, z: float) -> float:
	var s := sin(x * 12.9898 + z * 78.233) * 43758.5453
	return s - floor(s)
