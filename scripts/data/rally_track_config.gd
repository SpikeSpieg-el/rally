## Описание одной трассы. Всё настраивается в инспекторе Godot:
## откройте любой файл из res://data/tracks/ и меняйте параметры.
## Никаких констант в коде генератора: он читает только этот ресурс.
class_name RallyTrackConfig
extends Resource

enum StageKind { FOREST, MOUNTAIN, SUSPENSION, RANGE, SNOW }

@export_group("Описание")
@export var id: String = "track"
@export var display_name: String = "Трасса"
@export_multiline var description: String = "Описание трассы."
@export var surface_name: String = "Гравий"
@export_range(1, 5, 1) var difficulty: int = 3
@export var target_time: float = 90.0

@export_group("Тип трассы")
## Лес / Горы / Подвеска / Полигон / Снег. Влияет только на набор параметров.
@export_enum("Лес", "Горы", "Подвеска", "Полигон", "Снег") var kind: int = StageKind.FOREST
## Плоская трасса-полигон (ровная плоскость вместо высотного поля).
@export var flat: bool = false
@export_range(200.0, 1600.0, 10.0) var length: float = 700.0
@export_range(3.0, 12.0, 0.1) var road_half_width: float = 4.2
@export_range(0.0, 1.0, 0.01) var offroad_grip: float = 0.65

@export_group("Сид и случайность")
@export var map_seed: int = 1337
## Если включено — каждый заезд генерирует новый сид (режим «всегда случайно»).
@export var random_seed: bool = false
@export_range(0.0, 1.0, 0.01) var seed_variation: float = 0.55

@export_group("Форма дороги")
@export_range(0.0, 30.0, 0.1) var curve_amplitude: float = 11.0
@export_range(0.005, 0.08, 0.001) var curve_frequency: float = 0.026
@export_range(0.0, 1.0, 0.01) var curve_roughness: float = 0.45
@export_range(0.0, 20.0, 0.1) var secondary_curve_amplitude: float = 5.0

@export_group("Рельеф")
@export_range(0.0, 6.0, 0.05) var hill_amplitude: float = 1.4
@export_range(0.005, 0.08, 0.001) var hill_frequency: float = 0.025
@export_range(0.0, 1.5, 0.01) var bump_amount: float = 0.35
@export_range(0.0, 1.0, 0.01) var whoops_amount: float = 0.12
@export_range(0.0, 3.0, 0.05) var crest_amount: float = 0.8
@export_range(0.0, 2.0, 0.05) var offroad_hills: float = 0.9

@export_group("Окружение")
@export_range(0, 400, 1) var tree_count: int = 140
@export_range(0, 120, 1) var rock_count: int = 22
@export_range(0, 40, 1) var slalom_cones: int = 0
@export_range(60.0, 250.0, 5.0) var scenery_radius: float = 150.0
@export_range(8.0, 40.0, 1.0) var road_clearance: float = 12.0
@export var tree_color: Color = Color(0.07, 0.25, 0.12)
@export var rock_color: Color = Color(0.29, 0.31, 0.32)
@export var ground_color: Color = Color(0.10, 0.17, 0.07)
@export var ground_color_2: Color = Color(0.21, 0.26, 0.11)
@export var road_color: Color = Color(0.36, 0.29, 0.20)
@export var road_color_2: Color = Color(0.46, 0.38, 0.27)

@export_group("Погода и свет")
@export var sky_top_color: Color = Color(0.12, 0.27, 0.48)
@export var sky_horizon_color: Color = Color(0.65, 0.76, 0.86)
@export var fog_color: Color = Color(0.72, 0.79, 0.88)
@export_range(0.0, 0.02, 0.0001) var fog_density: float = 0.0012
@export_range(0.0, 4.0, 0.05) var sun_energy: float = 1.4
@export_range(-80.0, 80.0, 1.0) var sun_pitch: float = -32.0
@export_range(-180.0, 180.0, 1.0) var sun_yaw: float = 35.0

@export_group("Сцепление")
## Общий множитель сцепления. 1.0 — гравий, 0.55 — снег, 1.3 — асфальт.
@export_range(0.2, 2.0, 0.01) var grip_scale: float = 1.0
@export_range(0.2, 4.0, 0.01) var rolling_resistance_scale: float = 1.0

@export_group("Генерация сетки")
@export_range(65, 241, 2) var terrain_grid_size: int = 141
@export_range(0.5, 4.0, 0.05) var road_step: float = 1.5
@export var enable_speed_fx: bool = true


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


## Возвращает [амплитуды, частоты, фазы] изгибов дороги. Используется и
## генератором сцены, и шейдером земли, и мини-картой в меню.
func get_route_parameters(seed_value: int, always_random: bool) -> Array:
	var variation: float = 1.0
	if not always_random:
		variation = 1.0 + (seed_variation - 0.5) * 0.35
	var amp := Vector3(
		curve_amplitude * variation,
		secondary_curve_amplitude * lerpf(0.65, 1.35, hash_unit(seed_value, 1.0)),
		curve_amplitude * curve_roughness * lerpf(0.10, 0.42, hash_unit(seed_value, 2.0))
	)
	var freq := Vector3(
		curve_frequency * lerpf(0.85, 1.15, hash_unit(seed_value, 3.0)),
		curve_frequency * lerpf(2.1, 2.8, hash_unit(seed_value, 4.0)),
		curve_frequency * lerpf(0.35, 0.62, hash_unit(seed_value, 5.0))
	)
	var phase := Vector3(
		hash_unit(seed_value, 6.0) * TAU,
		hash_unit(seed_value, 7.0) * TAU,
		hash_unit(seed_value, 8.0) * TAU
	)
	if not always_random:
		phase = Vector3(
			float(absi(seed_value) % 97) / 97.0 * TAU,
			float(absi(seed_value) % 131) / 131.0 * TAU,
			float(absi(seed_value) % 53) / 53.0 * TAU
		)
	return [amp, freq, phase]


## Центр дороги по Z — та же формула, что в шейдере forest_ground.gdshader.
func route_center(z: float, params: Array) -> float:
	if is_flat():
		return 0.0
	var amp: Vector3 = params[0]
	var freq: Vector3 = params[1]
	var phase: Vector3 = params[2]
	return amp.x * sin(z * freq.x + phase.x) \
		+ amp.y * sin(z * freq.y + phase.y) \
		+ amp.z * sin(z * freq.z + phase.z)
