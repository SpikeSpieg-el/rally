## Конфигурация Lancer Evolution. Выбирается в меню перед стартом.
## Все параметры доступны в инспекторе: res://data/setups/*.tres
## Пустое/нулевое значение оставляет базовую настройку из scripts/rally_car.gd.
@tool
class_name RallyCarSetup
extends Resource

enum Drivetrain { AWD, RWD, FWD }
enum Transmission { AUTOMATIC, MANUAL, MANUAL_CLUTCH }
## Форма кривой момента:
## CUSTOM — берётся поле torque_curve этого ресурса;
## TURBO_PUNCH — полка с середины и спад к отсечке (турбо);
## ATMO_LINEAR — ровный рост до красной зоны (атмо);
## HIGH_REV — «злой» мотор, всё в верхах.
enum TorqueShape { CUSTOM, TURBO_PUNCH, ATMO_LINEAR, HIGH_REV }

@export_group("Описание")
@export var id: String = "setup"
@export var display_name: String = "Конфигурация"
@export_multiline var description: String = "Описание конфигурации."
@export var body_color: Color = Color(1, 1, 1, 1)
@export var accent_color: Color = Color(1, 0.55, 0.05, 1)

@export_group("Внешность")
@export_enum("Ралли", "Itasha неон", "Itasha зелёная") var livery: int = 0
@export_enum("Заводское", "Глянец", "Матовый", "Металлик") var paint_finish: int = 0
## Тонируется общая текстура всего колеса, а не только диска.
@export var wheel_color: Color = Color.WHITE
@export var headlight_color: Color = Color(1.0, 0.91, 0.76, 1.0)
@export_range(0.0, 12.0, 0.25) var headlight_energy: float = 8.0

@export_group("Мотор")
## Название мотора для карточки в меню: «4G63T · 2.0 TURBO».
@export var engine_name: String = ""
@export_range(100.0, 900.0, 1.0) var max_torque: float = 470.0
@export_range(3000.0, 10000.0, 10.0) var max_rpm: float = 7600.0
@export_range(500.0, 2000.0, 10.0) var idle_rpm: float = 900.0
## Характер кривой момента: турбо-полка, атмо-линейка или высокие обороты.
@export_enum("Своя кривая", "Турбо-полка", "Атмо-линейка", "Высокие обороты")
var torque_shape: int = TorqueShape.TURBO_PUNCH
## Необязательная кривая момента. Если пусто — строится по torque_shape.
@export var torque_curve: Curve = null
## Торможение двигателем относительно базы (1.0 — как в машине сцены).
@export_range(0.2, 3.0, 0.05) var engine_brake_scale: float = 1.0
## Турбина: сброс газа даёт blow-off и хлопки в выхлопе. У атмо этого нет.
@export var turbo: bool = true
@export_range(1.0, 8.0, 0.01) var final_drive: float = 4.1
@export var gear_ratios: Array[float] = [3.6, 2.4, 1.75, 1.35, 1.08, 0.88]
@export_range(-1.0, 4.0, 0.01) var traction_control_max_slip: float = 0.65

@export_group("Привод")
## В ручном режиме с педалью сцепление управляется водителем.
@export_enum("Автомат", "Ручная", "Ручная + сцепление") var transmission_mode: int = Transmission.AUTOMATIC
@export_enum("AWD", "RWD", "FWD") var drivetrain: int = Drivetrain.AWD
@export_range(0.0, 1.0, 0.01) var awd_front_torque: float = 0.38

@export_group("Масса и баланс")
@export_range(700.0, 2200.0, 1.0) var vehicle_mass: float = 1230.0
@export_range(0.35, 0.70, 0.01) var front_weight_distribution: float = 0.53
@export_range(-0.30, 0.30, 0.005) var center_of_gravity_height_offset: float = -0.10

@export_group("Подвеска")
@export_range(0.10, 0.60, 0.005) var front_spring_length: float = 0.30
@export_range(0.10, 0.60, 0.005) var rear_spring_length: float = 0.32
@export_range(0.30, 0.80, 0.01) var front_resting_ratio: float = 0.55
@export_range(0.30, 0.80, 0.01) var rear_resting_ratio: float = 0.55
@export_range(0.10, 1.20, 0.01) var front_damping_ratio: float = 0.46
@export_range(0.10, 1.20, 0.01) var rear_damping_ratio: float = 0.52
@export_range(0.0, 0.80, 0.01) var front_arb_ratio: float = 0.13
@export_range(0.0, 0.80, 0.01) var rear_arb_ratio: float = 0.10
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

@export_group("Тормоза")
@export_range(0.4, 1.6, 0.05) var brake_force_multiplier: float = 1.0
@export_range(0.30, 0.80, 0.01) var front_brake_bias: float = 0.66

@export_group("Камера")
@export_range(3.0, 12.0, 0.1) var chase_distance: float = 5.8
@export_range(0.5, 4.0, 0.05) var chase_height: float = 1.55


## Кривая момента по выбранному характеру. Возвращает null для CUSTOM:
## тогда используется поле torque_curve (или базовая кривая машины).
## По оси X — доля оборотов от max_rpm, по Y — доля max_torque.
func build_torque_curve() -> Curve:
	var points := PackedVector2Array()
	match torque_shape:
		TorqueShape.TURBO_PUNCH:
			# Турбо просыпается к 2800–3200 об/мин, дальше ровная полка
			# и мягкий спад к отсечке.
			points = PackedVector2Array([
				Vector2(0.0, 0.58), Vector2(0.22, 0.72), Vector2(0.38, 0.94),
				Vector2(0.55, 1.0), Vector2(0.75, 0.9), Vector2(0.9, 0.76),
				Vector2(1.0, 0.58),
			])
		TorqueShape.ATMO_LINEAR:
			# Атмосферник: момент растёт почти линейно до самой отсечки.
			points = PackedVector2Array([
				Vector2(0.0, 0.42), Vector2(0.3, 0.62), Vector2(0.55, 0.79),
				Vector2(0.8, 0.94), Vector2(0.95, 1.0), Vector2(1.0, 0.98),
			])
		TorqueShape.HIGH_REV:
			# «Злой» мотор: внизу пусто, весь момент в верхах.
			points = PackedVector2Array([
				Vector2(0.0, 0.3), Vector2(0.25, 0.45), Vector2(0.5, 0.66),
				Vector2(0.72, 0.88), Vector2(0.9, 1.0), Vector2(1.0, 0.9),
			])
		_:
			return null
	var curve := Curve.new()
	for point in points:
		curve.add_point(point)
	return curve


## Строка для меню: «4G63T · 2.0 TURBO · 470 Нм · 7600 об/мин».
func get_engine_summary() -> String:
	var name_text: String = engine_name if not engine_name.is_empty() else "LANCER EVOLUTION"
	return "%s  •  %d Нм  •  %d об/мин%s" % [
		name_text, int(round(max_torque)), int(round(max_rpm)), "  •  TURBO" if turbo else "",
	]


func get_drivetrain_name() -> String:
	match drivetrain:
		Drivetrain.RWD:
			return "RWD"
		Drivetrain.FWD:
			return "FWD"
		_:
			return "AWD"


func get_transmission_name() -> String:
	match transmission_mode:
		Transmission.MANUAL:
			return "РУЧНАЯ"
		Transmission.MANUAL_CLUTCH:
			return "РУЧНАЯ + СЦЕПЛЕНИЕ"
		_:
			return "АВТОМАТ"


func get_power_rating() -> float:
	return clampf(max_torque / 600.0, 0.0, 1.0)


func get_grip_rating() -> float:
	return clampf(grip_scale / 1.8, 0.0, 1.0)


func get_suspension_rating() -> float:
	return clampf((front_spring_length + rear_spring_length) / 0.9, 0.0, 1.0)
