## Конфигурация Lancer Evolution. Выбирается в меню перед стартом.
## Все параметры доступны в инспекторе: res://data/setups/*.tres
## Пустое/нулевое значение оставляет базовую настройку из scripts/rally_car.gd.
@tool
class_name RallyCarSetup
extends Resource

enum Drivetrain { AWD, RWD, FWD }

@export_group("Описание")
@export var id: String = "setup"
@export var display_name: String = "Конфигурация"
@export_multiline var description: String = "Описание конфигурации."
@export var body_color: Color = Color(1, 1, 1, 1)
@export var accent_color: Color = Color(1, 0.55, 0.05, 1)

@export_group("Мотор")
@export_range(100.0, 900.0, 1.0) var max_torque: float = 390.0
@export_range(3000.0, 10000.0, 10.0) var max_rpm: float = 7600.0
@export_range(1.0, 8.0, 0.01) var final_drive: float = 4.1
@export var gear_ratios: Array[float] = [3.6, 2.4, 1.75, 1.35, 1.08, 0.88]
## Необязательная кривая момента. Если пусто — используется базовая кривая.
@export var torque_curve: Curve = null
@export_range(-1.0, 4.0, 0.01) var traction_control_max_slip: float = 0.8

@export_group("Привод")
@export_enum("AWD", "RWD", "FWD") var drivetrain: int = Drivetrain.AWD
@export_range(0.0, 1.0, 0.01) var awd_front_torque: float = 0.38

@export_group("Масса и баланс")
@export_range(700.0, 2200.0, 1.0) var vehicle_mass: float = 1230.0
@export_range(0.35, 0.70, 0.01) var front_weight_distribution: float = 0.56
@export_range(-0.30, 0.30, 0.005) var center_of_gravity_height_offset: float = -0.10

@export_group("Подвеска")
@export_range(0.10, 0.60, 0.005) var front_spring_length: float = 0.30
@export_range(0.10, 0.60, 0.005) var rear_spring_length: float = 0.32
@export_range(0.30, 0.80, 0.01) var front_resting_ratio: float = 0.55
@export_range(0.30, 0.80, 0.01) var rear_resting_ratio: float = 0.55
@export_range(0.10, 1.20, 0.01) var front_damping_ratio: float = 0.46
@export_range(0.10, 1.20, 0.01) var rear_damping_ratio: float = 0.52
@export_range(0.0, 0.80, 0.01) var front_arb_ratio: float = 0.16
@export_range(0.0, 0.80, 0.01) var rear_arb_ratio: float = 0.12
@export_range(0.2, 2.5, 0.05) var bump_damp_multiplier: float = 0.75
@export_range(0.2, 2.5, 0.05) var rebound_damp_multiplier: float = 1.35

@export_group("Шины и руль")
## Физический радиус колеса в метрах. Визуальная модель масштабируется автоматически.
@export_range(0.20, 0.65, 0.001) var tire_radius: float = 0.438
@export_range(100.0, 400.0, 1.0) var tire_width: float = 245.0
@export_range(0.3, 2.5, 0.01) var grip_scale: float = 1.0
@export_range(0.3, 2.5, 0.01) var tire_stiffness_scale: float = 1.0
@export_range(0.3, 3.0, 0.01) var rolling_resistance_scale: float = 1.0
@export_range(10.0, 50.0, 0.5) var max_steering_angle_deg: float = 35.0

@export_group("Камера")
@export_range(3.0, 12.0, 0.1) var chase_distance: float = 5.8
@export_range(0.5, 4.0, 0.05) var chase_height: float = 1.55


func get_power_rating() -> float:
	return clampf(max_torque / 600.0, 0.0, 1.0)


func get_grip_rating() -> float:
	return clampf(grip_scale / 1.8, 0.0, 1.0)


func get_suspension_rating() -> float:
	return clampf((front_spring_length + rear_spring_length) / 0.9, 0.0, 1.0)
