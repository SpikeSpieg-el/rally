## Полный пульт аркадного режима: геометрия дороги, трафик, пешеходы,
## очки, строгий HP, окружение и рекорды.
##
## Файл по умолчанию — `res://data/stage/default_arcade_settings.tres`.
## Откройте его в инспекторе Godot (или выберите в корневом узле
## `RallyArcadeStage -> arcade_settings` в `scenes/rally_arcade.tscn`) и
## меняйте любые значения без правки кода.
@tool
class_name RallyArcadeSettings
extends Resource

@export_group("Дорога аркады")
## Коэффициент ширины относительно `RallyTrackConfig.road_half_width`.
## Аркада по умолчанию заметно шире обычного спецучастка: значение 1.25
## даёт около 12,5 м полотна при базовой полуширине 5 м.
@export_range(0.80, 2.00, 0.05) var road_width_scale: float = 1.25
## Явная полуширина полотна. 0 — брать ширину трассы и умножать на
## `road_width_scale`; ненулевое значение полностью заменяет этот расчёт.
@export_range(0.0, 12.0, 0.1, "suffix:м") var road_half_width_override: float = 0.0
## Масштабы ширины для разных доменов бесконечной дороги.
@export_range(0.70, 1.30, 0.01) var serpentine_width_scale: float = 0.98
@export_range(0.70, 1.30, 0.01) var country_width_scale: float = 1.00
@export_range(0.70, 1.30, 0.01) var village_width_scale: float = 1.05
@export_range(0.70, 1.30, 0.01) var bridge_width_scale: float = 0.96
@export_range(0.70, 1.50, 0.01) var fast_width_scale: float = 1.18
## Длина плавного перехода между ширинами доменов, м.
@export_range(0.0, 120.0, 1.0, "suffix:м") var width_transition_m: float = 40.0
## Поперечная геометрия. Эти значения раньше были константами в меше и
## поэтому не настраивались вместе с аркадой.
@export_range(0.0, 2.0, 0.05) var road_shoulder_scale: float = 1.0
## Ненулевое значение полностью заменяет ширину обочины трассы.
@export_range(0.0, 5.0, 0.05, "suffix:м") var road_shoulder_override: float = 0.0
@export_range(0.0, 4.0, 0.05, "suffix:м") var road_edge_band: float = 1.1
@export_range(0.0, 0.4, 0.01, "suffix:м") var road_camber: float = 0.07
@export_range(0.0, 2.0, 0.05, "suffix:м") var road_ditch_depth: float = 0.5
@export_range(0.0, 20.0, 0.5, "suffix:м") var verge_width: float = 8.0
@export_range(0.0, 0.5, 0.01, "suffix:м") var road_lift: float = 0.04
## Шаг строк сетки дороги. Меньше — ровнее меш, больше — дешевле.
@export_range(1.0, 6.0, 0.25, "suffix:м") var road_mesh_row_step: float = 2.5

@export_group("Трафик")
## Включить живой двухсторонний трафик на дороге.
@export var traffic_enabled: bool = true
## Количество активных машин трафика вокруг игрока.
@export_range(0, 24, 1) var traffic_count: int = 10
## Минимальная и максимальная дистанция спавна впереди игрока, м.
@export_range(40.0, 400.0, 5.0, "suffix:м") var traffic_spawn_min_m: float = 105.0
@export_range(80.0, 600.0, 5.0, "suffix:м") var traffic_spawn_max_m: float = 315.0
## Дистанция удаления ушедшего трафика позади и впереди, м.
@export_range(40.0, 300.0, 5.0, "suffix:м") var traffic_despawn_behind_m: float = 115.0
@export_range(120.0, 700.0, 5.0, "suffix:м") var traffic_despawn_ahead_m: float = 360.0
## Минимальный зазор при спавне в одной полосе, м.
@export_range(15.0, 120.0, 1.0, "suffix:м") var traffic_min_separation_m: float = 42.0
## Смещение центра полосы (доля от полуширины дороги, 0.5 — середина своей полосы).
@export_range(0.25, 0.75, 0.01) var traffic_lane_fraction: float = 0.50
## Базовый разброс крейсерской скорости трафика, м/с.
@export_range(4.0, 35.0, 0.5, "suffix:м/с") var traffic_min_speed_mps: float = 10.5
@export_range(4.0, 40.0, 0.5, "suffix:м/с") var traffic_max_speed_mps: float = 15.5
## Пределы скорости по доменам, м/с.
@export_range(3.0, 30.0, 0.5, "suffix:м/с") var traffic_village_speed_mps: float = 9.5
@export_range(3.0, 30.0, 0.5, "suffix:м/с") var traffic_serpentine_speed_mps: float = 10.5
@export_range(3.0, 35.0, 0.5, "suffix:м/с") var traffic_bridge_speed_mps: float = 12.5
@export_range(5.0, 45.0, 0.5, "suffix:м/с") var traffic_fast_speed_mps: float = 17.5
## Скорость в крутой шпильке, м/с.
@export_range(2.0, 20.0, 0.5, "suffix:м/с") var traffic_hairpin_speed_mps: float = 6.5
## Ускорение и торможение трафика, м/с².
@export_range(1.0, 15.0, 0.2) var traffic_accel_rate: float = 3.2
@export_range(2.0, 25.0, 0.5) var traffic_brake_rate: float = 11.5
@export_range(4.0, 35.0, 0.5) var traffic_emergency_brake_rate: float = 16.5
## Насколько сильно трафик прижимается к обочине, уступая дорогу (0..1).
@export_range(0.0, 1.0, 0.05) var traffic_yield_strength: float = 0.90
## Дальность и яркость фар трафика ночью.
@export_range(10.0, 100.0, 1.0, "suffix:м") var traffic_headlight_range: float = 42.0
@export_range(0.0, 16.0, 0.2) var traffic_headlight_energy: float = 5.5
## Палитра цветов кузова для процедурных машин трафика.
@export var traffic_livery_colors: Array[Color] = [
	Color(0.76, 0.78, 0.80, 1.0),
	Color(0.16, 0.28, 0.44, 1.0),
	Color(0.62, 0.16, 0.14, 1.0),
	Color(0.18, 0.34, 0.22, 1.0),
	Color(0.78, 0.64, 0.22, 1.0),
	Color(0.32, 0.34, 0.38, 1.0),
	Color(0.84, 0.82, 0.74, 1.0),
	Color(0.22, 0.20, 0.26, 1.0),
]
## Необязательный список кастомных сцен (.tscn) для машин трафика;
## если пусто — собираются встроенные седан, хэтчбек и фургон.
@export var traffic_body_scenes: Array[PackedScene] = []

@export_group("Пешеходы и переходы")
## Включить пешеходов на деревенских «зебрах».
@export var pedestrians_enabled: bool = true
## Сцена пешехода (по умолчанию spectator_person.tscn).
@export var pedestrian_scene: PackedScene = null
## Сколько пешеходов на одном переходе.
@export_range(0, 8, 1) var pedestrians_min_per_crossing: int = 2
@export_range(0, 8, 1) var pedestrians_max_per_crossing: int = 3
## Скорость шага пешеходов, м/с.
@export_range(0.5, 6.0, 0.05, "suffix:м/с") var pedestrian_walk_speed_min: float = 1.55
@export_range(0.5, 6.0, 0.05, "suffix:м/с") var pedestrian_walk_speed_max: float = 2.35
## Минимальная скорость машины для наезда на пешехода, м/с.
@export_range(1.0, 20.0, 0.5, "suffix:м/с") var pedestrian_hit_min_speed_mps: float = 4.0
## Дистанция предупреждения о переходе, м.
@export_range(20.0, 180.0, 2.0, "suffix:м") var pedestrian_warning_distance_m: float = 78.0
## Максимальная скорость для бонуса за аккуратный проезд перехода, м/с.
@export_range(5.0, 40.0, 0.5, "suffix:м/с") var crosswalk_courtesy_max_speed_mps: float = 20.0

@export_group("Очки и прочность (HP)")
## Стартовая и максимальная прочность машины (без самовосстановления).
@export_range(10.0, 500.0, 5.0) var max_hp: float = 100.0
## Порог скорости на дороге, с которого идут очки за чистую езду, м/с.
@export_range(3.0, 40.0, 0.5, "suffix:м/с") var speed_score_threshold_mps: float = 13.5
## Скорость набора очков за скорость.
@export_range(0.1, 20.0, 0.1) var speed_score_rate: float = 2.8
## За сколько секунд чистой езды множитель растёт на +0.5.
@export_range(3.0, 60.0, 1.0, "suffix:с") var multiplier_step_seconds: float = 15.0
## Максимальный множитель очков.
@export_range(1.0, 10.0, 0.5) var multiplier_max: float = 3.0
## Базовые очки за события.
@export_range(0, 5000, 10) var overtake_points: int = 250
@export_range(0, 5000, 10) var near_miss_points: int = 150
@export_range(0, 5000, 10) var crosswalk_courtesy_points: int = 150
@export_range(100.0, 5000.0, 50.0, "suffix:м") var milestone_distance_m: float = 500.0
@export_range(0, 5000, 10) var milestone_bonus_points: int = 300
## Порог резкого падения скорости (м/с за кадр физики) и урон о мир/отбойники.
@export_range(1.5, 25.0, 0.1, "suffix:м/с") var crash_min_dv_mps: float = 4.6
@export_range(0.2, 10.0, 0.05) var crash_damage_scale: float = 2.35
@export_range(1.0, 100.0, 1.0) var crash_damage_min: float = 6.0
@export_range(5.0, 100.0, 1.0) var crash_damage_max: float = 42.0
## Урон при столкновении с трафиком.
@export_range(0.2, 10.0, 0.05) var traffic_impact_scale: float = 1.45
@export_range(1.0, 100.0, 1.0) var traffic_impact_min: float = 8.0
@export_range(5.0, 100.0, 1.0) var traffic_impact_max: float = 46.0
## Штраф за наезд на пешехода и за возврат на трассу.
@export_range(0.0, 100.0, 1.0) var pedestrian_hit_damage: float = 35.0
@export_range(0, 5000, 50) var pedestrian_hit_penalty: int = 500
@export_range(0.0, 100.0, 1.0) var rescue_damage: float = 12.0
## Пауза неуязвимости после удара, сек.
@export_range(0.1, 3.0, 0.05, "suffix:с") var damage_cooldown_sec: float = 0.65

@export_group("Мир, полосы и рекорды")
## Доля полуширины полотна для спавна игрока (0.5 — центр полосы).
@export_range(0.20, 0.75, 0.01) var player_lane_fraction: float = 0.50
## Включать расстановку декора и бесконечный рельеф.
@export var scenery_enabled: bool = true
@export var terrain_enabled: bool = true
## Длительность показа уведомлений вверху экрана, сек.
@export_range(0.5, 8.0, 0.1, "suffix:с") var alert_duration_sec: float = 2.4
## Файл таблицы рекордов и число строк.
@export var records_path: String = "user://arcade_records.cfg"
@export_range(1, 20, 1) var leaderboard_size: int = 5
