# Rally adaptation of Godot Easy Vehicle Physics (MIT).
# Base: https://github.com/L3w1s6/infinite-rally/tree/main/Addons/gevp
# See res://scripts/gevp/LICENSE for the original copyright and license.
class_name RallyCar
extends "res://scripts/gevp/vehicle.gd"

enum CameraMode { CHASE_3RD, HOOD, COCKPIT_1ST }
enum DrivetrainMode { AWD, RWD, FWD }

# Геометрия импортированной модели Lancer Evo: центр колеса и клиренс кузова.
const MODEL_WHEEL_CENTER_Y: float = 1.4588
const MODEL_BODY_GROUND_CLEARANCE: float = 0.063
const CarSetupType = preload("res://scripts/data/rally_car_setup.gd")
const WheelType = preload("res://scripts/gevp/wheel.gd")

# Базовое сцепление. Множители конфигурации машины и трассы применяются поверх.
# Шины начинают создавать боковую силу раньше и сохраняют тягу на гравии.
# Итоговые значения дополнительно зависят от сетапа и покрытия трассы.
const BASE_STIFFNESS := {"Road": 5.0, "Dirt": 3.8, "Grass": 2.6}
const BASE_COF := {"Road": 1.50, "Dirt": 1.25, "Grass": 1.0}
const BASE_ROLLING := {"Road": 1.0, "Dirt": 1.20, "Grass": 1.5}
const BASE_LATERAL := {"Road": 0.0, "Dirt": 0.04, "Grass": 0.06}
const BASE_LONGITUDINAL := {"Road": 0.90, "Dirt": 0.85, "Grass": 0.75}
## На какой скорости ещё можно включить задний ход из первой передачи.
const REVERSE_SHIFT_MAX_KMH: float = 15.0
## Базовое торможение двигателем. Сетап задаёт множитель к нему.
const BASE_MOTOR_BRAKE: float = 10.0

@export_group("Конфигурация Lancer Evo")
## Если назначено здесь — используется эта конфигурация (удобно при F6 на сцене машины).
@export var setup_override: CarSetupType = null
## Радиус импортированной 3D-модели колеса. Визуал масштабируется под физический радиус.
@export_range(0.10, 1.0, 0.001) var wheel_visual_radius: float = 0.438

@export_group("Rally Drivetrain")
@export_enum("AWD 38:62", "RWD 0:100", "FWD 100:0") var drivetrain_mode: int = DrivetrainMode.AWD
@export_range(0.0, 1.0, 0.01) var awd_front_torque: float = 0.38

@export_group("Управление на скорости")
## На скорости ограничиваем угол передних колёс, а не приклеиваем машину к дороге.
@export_range(0.1, 1.0, 0.01) var high_speed_steering_scale: float = 0.48
@export_range(0.0, 150.0, 1.0, "suffix:km/h") var steering_limit_start_kmh: float = 30.0
@export_range(20.0, 250.0, 1.0, "suffix:km/h") var steering_limit_full_kmh: float = 120.0

@export_group("Камера: общий обзор")
## Начальный вид; во время заезда переключается клавишей C.
@export_enum("Сзади", "Капот", "Кабина") var initial_camera_mode: int = CameraMode.CHASE_3RD
@export_range(45.0, 110.0, 1.0, "suffix:°") var hood_fov: float = 74.0
@export_range(45.0, 110.0, 1.0, "suffix:°") var cockpit_fov: float = 76.0
## Дополнительный угол обзора на скорости, 0 — постоянный FOV.
@export_range(0.0, 20.0, 0.5, "suffix:°") var inside_speed_fov_bonus: float = 5.0
## Смещение взгляда от ускорений: 0 — строго по маркеру CamCockpit.
@export_range(0.0, 1.0, 0.05) var cockpit_motion_strength: float = 0.35
@export_range(0.0, 10.0, 0.5, "suffix:°") var cockpit_roll_degrees: float = 2.0

@export_group("Action Camera")
## Если включено — позиция и ракурс камеры берутся напрямую из узла CamChase на сцене!
@export var use_cam_chase_from_scene: bool = true
@export var chase_distance: float = 5.8
@export var chase_height: float = 1.55
@export var chase_target_height: float = 0.0
@export var chase_lookahead: float = 2.2
@export_range(0.0, 1.0, 0.01) var chase_velocity_follow: float = 0.15
@export var chase_yaw_response: float = 8.0
## Боковое смещение камеры при повороте руля (0.0 = отключено, чтобы не было рывков).
@export var chase_corner_offset: float = 0.0
@export var chase_collision_radius: float = 0.28
@export_range(45.0, 110.0, 1.0, "suffix:°") var chase_min_fov: float = 72.0
@export_range(45.0, 120.0, 1.0, "suffix:°") var chase_max_fov: float = 80.0

@export_group("Mouse Look")
@export var mouse_look_enabled: bool = true
@export_range(0.0005, 0.01, 0.0005) var mouse_sensitivity: float = 0.0025
@export var mouse_auto_return_delay: float = 1.5
@export var mouse_return_speed: float = 4.5
@export var chase_min_pitch_deg: float = -5.0
@export var chase_max_pitch_deg: float = 45.0
@export var inside_max_yaw_deg: float = 110.0
@export var inside_min_pitch_deg: float = -35.0
@export var inside_max_pitch_deg: float = 35.0

@export_group("Контроллер")
## Скорость обзора правым стиком, градусов в секунду.
@export_range(30.0, 360.0, 5.0, "suffix:°/с") var gamepad_look_speed: float = 160.0
@export var gamepad_look_enabled: bool = true
@export var gamepad_rumble_enabled: bool = true
@export_range(0.0, 1.0, 0.05) var gamepad_rumble_on_shift: float = 0.30
@export_range(0.0, 1.0, 0.05) var gamepad_rumble_on_reset: float = 0.55


@onready var gravel_particles: GPUParticles3D = $GravelParticles
@onready var active_camera: Camera3D = $Cameras/ActiveCamera
@onready var cam_chase: Marker3D = $Cameras/CamChase
@onready var cam_hood: Marker3D = $Cameras/CamHood
@onready var cam_cockpit: Marker3D = $Cameras/CamCockpit

var spawn_transform: Transform3D = Transform3D.IDENTITY
var camera_mode: int = CameraMode.CHASE_3RD
var current_rpm: float = 900.0
var speed_mps: float = 0.0
var speed_kmh: float = 0.0
var steer_input: float = 0.0
var manual_mode: bool = false
var previous_velocity: Vector3 = Vector3.ZERO
var g_force_offset: Vector3 = Vector3.ZERO
var camera_yaw: float = 0.0
var camera_position: Vector3 = Vector3.ZERO
var camera_initialized: bool = false

# Переменные для сохранения точного ракурса CamChase со сцены
var _scene_chase_local_pos: Vector3 = Vector3(0.0, 1.55, -5.8)
var _scene_chase_look_dir_local: Vector3 = Vector3(0.0, -0.12, 1.0).normalized()
var _scene_pivot_height: float = 0.0
var _smoothed_cam_dist: float = 5.8
var _smoothed_slope_y: float = 0.0

# Переменные для обзора мышью
var mouse_yaw: float = 0.0
var mouse_pitch: float = 0.0
var smoothed_mouse_yaw: float = 0.0
var smoothed_mouse_pitch: float = 0.0
var mouse_idle_timer: float = 10.0

var active_setup: CarSetupType = null
var track_grip_scale: float = 1.0
var track_rolling_scale: float = 1.0
var track_offroad_grip: float = 0.6

## Необязательный «провайдер» точки сброса: сцена заезда подставляет сюда
## поиск ближайшей точки трассы, чтобы R возвращал машину на дорогу,
## а не на старт.
var reset_provider: Callable = Callable()

## Нижняя граница падения в мировых координатах. Сцена заезда может
## переопределить её через провайдер ниже: на сгенерированной трассе дорога
## уходит на десятки метров ниже нуля, и жёсткий порог −20 м бесконечно
## сбрасывал машину на одном месте.
var fall_limit_y: float = -20.0
## Необязательный провайдер нижней границы: считается от земли ПОД машиной,
## а не от абсолютного нуля мира.
var fall_limit_provider: Callable = Callable()


func _ready() -> void:
	if spawn_transform == Transform3D.IDENTITY:
		spawn_transform = global_transform

	_configure_gevp()
	_resolve_setup()
	if active_setup != null:
		apply_setup(active_setup)
	else:
		_adjust_wheel_mounts()

	super._ready()
	_apply_drivetrain()
	_refresh_grip_tuning()
	motor_rpm = idle_rpm
	current_rpm = idle_rpm
	current_gear = 1
	requested_gear = 1
	_setup_gravel_particles()
	_apply_visual_setup()

	# Считываем положение и угол наклона узла CamChase со сцены
	_capture_scene_camera_setup()

	camera_mode = clampi(initial_camera_mode, CameraMode.CHASE_3RD, CameraMode.COCKPIT_1ST)
	if active_camera != null:
		active_camera.top_level = (camera_mode == CameraMode.CHASE_3RD)
		active_camera.make_current()
		_reset_action_camera()
		_apply_initial_camera_fov()
		if camera_mode != CameraMode.CHASE_3RD:
			_update_cameras(0.0)

	if mouse_look_enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Запоминает, где стоит CamChase (и куда он смотрит) в редакторе Godot
func _capture_scene_camera_setup() -> void:
	var model: Node3D = get_node_or_null("low poly lance evo") as Node3D
	if model != null:
		_scene_pivot_height = model.position.y + MODEL_WHEEL_CENTER_Y + 0.35
	else:
		_scene_pivot_height = chase_target_height

	if not use_cam_chase_from_scene or cam_chase == null:
		_scene_chase_local_pos = Vector3(0.0, chase_height, -chase_distance)
		var fallback_target := Vector3(0.0, _scene_pivot_height + 0.15, chase_lookahead)
		_scene_chase_look_dir_local = (fallback_target - _scene_chase_local_pos).normalized()
		return

	_scene_chase_local_pos = to_local(cam_chase.global_position)

	var inv_car_basis: Basis = global_transform.basis.orthonormalized().inverse()
	var chase_fwd_local: Vector3 = (inv_car_basis * (-cam_chase.global_transform.basis.z)).normalized()
	var active_fwd_local: Vector3 = Vector3.ZERO
	if active_camera != null:
		active_fwd_local = (inv_car_basis * (-active_camera.global_transform.basis.z)).normalized()

	if chase_fwd_local.z > 0.2:
		_scene_chase_look_dir_local = chase_fwd_local
	elif active_fwd_local.z > 0.2:
		_scene_chase_look_dir_local = active_fwd_local
	else:
		var target_ahead_local := Vector3(0.0, _scene_pivot_height + 0.15, chase_lookahead)
		_scene_chase_look_dir_local = (target_ahead_local - _scene_chase_local_pos).normalized()


func _unhandled_input(event: InputEvent) -> void:
	if not mouse_look_enabled:
		return

	if event is InputEventKey and event.is_action_pressed("ui_cancel") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			recenter_look()

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_yaw -= event.relative.x * mouse_sensitivity
		mouse_idle_timer = 0.0

		if camera_mode == CameraMode.CHASE_3RD:
			mouse_pitch += event.relative.y * mouse_sensitivity
			mouse_yaw = wrapf(mouse_yaw, -PI, PI)
			mouse_pitch = clampf(mouse_pitch, deg_to_rad(chase_min_pitch_deg), deg_to_rad(chase_max_pitch_deg))
		else:
			mouse_pitch -= event.relative.y * mouse_sensitivity
			var max_yaw: float = deg_to_rad(inside_max_yaw_deg)
			mouse_yaw = clampf(mouse_yaw, -max_yaw, max_yaw)
			mouse_pitch = clampf(mouse_pitch, deg_to_rad(inside_min_pitch_deg), deg_to_rad(inside_max_pitch_deg))


func _configure_gevp() -> void:
	front_left_wheel = $Wheel_FL
	front_right_wheel = $Wheel_FR
	rear_left_wheel = $Wheel_RL
	rear_right_wheel = $Wheel_RR

	steering_speed = 6.0
	countersteer_speed = 9.0
	steering_speed_decay = 0.24
	steering_slip_assist = 0.38
	countersteer_assist = 0.25
	steering_exponent = 1.20
	max_steering_angle = deg_to_rad(35.0)
	front_steering_ratio = 1.0
	rear_steering_ratio = 0.0

	throttle_speed = 7.0
	braking_speed = 14.0
	front_brake_bias = 0.66
	# Задний ход включается только водителем (shift_down), а не удержанием тормоза.
	automatic_reverse_on_brake = false
	# TCS ограничивает пробуксовку плавно, не выключая тягу целиком.
	traction_control_max_slip = 0.65

	enable_stability = false
	stability_yaw_engage_angle = 0.10
	stability_yaw_strength = 0.0
	stability_yaw_ground_multiplier = 1.0
	stability_upright_spring = 0.0
	stability_upright_damping = 0.0

	max_torque = 470.0
	max_rpm = 7600.0
	idle_rpm = 900.0
	motor_drag = 0.004
	motor_brake = 10.0
	motor_moment = 0.30
	clutch_out_rpm = 2300.0
	max_clutch_torque_ratio = 1.65
	# Больше момента на низах: машине не хватало мощности на подъём.
	torque_curve = Curve.new()
	torque_curve.add_point(Vector2(0.0, 0.55))
	torque_curve.add_point(Vector2(0.50, 1.0))
	torque_curve.add_point(Vector2(1.0, 0.70))

	gear_ratios = [3.6, 2.4, 1.75, 1.35, 1.08, 0.88]
	final_drive = 4.1
	reverse_ratio = 3.4
	shift_time = 0.18
	automatic_transmission = true
	automatic_time_between_shifts = 700.0
	gear_inertia = 0.02

	front_torque_split = awd_front_torque
	variable_torque_split = false
	front_locking_differential_engage_torque = 120.0
	rear_locking_differential_engage_torque = 180.0
	front_torque_vectoring = 0.0
	rear_torque_vectoring = 0.0

	vehicle_mass = 1230.0
	# Смещение веса назад — меньше подрессорник под утюжком.
	front_weight_distribution = 0.53
	center_of_gravity_height_offset = -0.10
	inertia_multiplier = 1.0

	front_spring_length = 0.30
	rear_spring_length = 0.32
	front_resting_ratio = 0.55
	rear_resting_ratio = 0.55
	front_damping_ratio = 0.46
	rear_damping_ratio = 0.52
	front_bump_damp_multiplier = 0.75
	front_rebound_damp_multiplier = 1.35
	rear_bump_damp_multiplier = 0.75
	rear_rebound_damp_multiplier = 1.35
	front_arb_ratio = 0.13
	rear_arb_ratio = 0.10
	front_camber = 0.012
	rear_camber = 0.012
	front_toe = 0.003
	rear_toe = 0.002
	front_bump_stop_multiplier = 1.2
	rear_bump_stop_multiplier = 1.2

	contact_patch = 0.22
	braking_grip_multiplier = 1.05
	wheel_to_body_torque_multiplier = 0.6
	tire_stiffnesses = BASE_STIFFNESS.duplicate()
	coefficient_of_friction = BASE_COF.duplicate()
	rolling_resistance = BASE_ROLLING.duplicate()
	lateral_grip_assist = BASE_LATERAL.duplicate()
	longitudinal_grip_ratio = BASE_LONGITUDINAL.duplicate()
	front_tire_radius = 0.438
	rear_tire_radius = 0.438
	front_tire_width = 245.0
	rear_tire_width = 245.0
	front_wheel_mass = 15.0
	rear_wheel_mass = 15.0

	coefficient_of_drag = 0.28
	air_density = 1.225
	frontal_area = 1.9


func _resolve_setup() -> void:
	if setup_override != null:
		active_setup = setup_override
		return
	var game: Node = get_node_or_null("/root/RallyGame")
	if game == null:
		return
	var selected: Variant = game.get("current_setup")
	if selected is CarSetupType:
		active_setup = selected


func apply_setup(setup_resource: CarSetupType) -> void:
	if setup_resource == null:
		return
	active_setup = setup_resource
	drivetrain_mode = clampi(setup_resource.drivetrain, 0, 2)
	awd_front_torque = setup_resource.awd_front_torque
	max_torque = setup_resource.max_torque
	max_rpm = setup_resource.max_rpm
	# Холостой ход не может быть выше середины отсечки: иначе мотор «висит»
	# на оборотах и машина сама ползёт со старта.
	idle_rpm = clampf(setup_resource.idle_rpm, 500.0, max_rpm * 0.6)
	motor_brake = BASE_MOTOR_BRAKE * setup_resource.engine_brake_scale
	final_drive = setup_resource.final_drive
	if not setup_resource.gear_ratios.is_empty():
		gear_ratios = setup_resource.gear_ratios.duplicate()
	traction_control_max_slip = setup_resource.traction_control_max_slip
	var engine_curve: Curve = null
	if setup_resource.torque_curve != null:
		engine_curve = setup_resource.torque_curve.duplicate() as Curve
	else:
		# Пресет мотора может задать характер кривой без ручной Curve.
		engine_curve = setup_resource.build_torque_curve()
	if engine_curve != null:
		torque_curve = engine_curve
	vehicle_mass = setup_resource.vehicle_mass
	front_weight_distribution = setup_resource.front_weight_distribution
	center_of_gravity_height_offset = setup_resource.center_of_gravity_height_offset
	front_spring_length = setup_resource.front_spring_length
	rear_spring_length = setup_resource.rear_spring_length
	front_resting_ratio = setup_resource.front_resting_ratio
	rear_resting_ratio = setup_resource.rear_resting_ratio
	front_damping_ratio = setup_resource.front_damping_ratio
	rear_damping_ratio = setup_resource.rear_damping_ratio
	front_arb_ratio = setup_resource.front_arb_ratio
	rear_arb_ratio = setup_resource.rear_arb_ratio
	front_bump_damp_multiplier = setup_resource.bump_damp_multiplier
	rear_bump_damp_multiplier = setup_resource.bump_damp_multiplier
	front_rebound_damp_multiplier = setup_resource.rebound_damp_multiplier
	rear_rebound_damp_multiplier = setup_resource.rebound_damp_multiplier
	front_tire_radius = setup_resource.tire_radius
	rear_tire_radius = setup_resource.tire_radius
	front_tire_width = setup_resource.tire_width
	rear_tire_width = setup_resource.tire_width
	max_steering_angle = deg_to_rad(setup_resource.max_steering_angle_deg)
	if not use_cam_chase_from_scene:
		chase_distance = setup_resource.chase_distance
		chase_height = setup_resource.chase_height
	front_torque_split = awd_front_torque
	_adjust_wheel_mounts()

	if is_ready:
		initialize()
		_apply_drivetrain()
		_refresh_grip_tuning()
		_apply_visual_setup()
		_capture_scene_camera_setup()
	else:
		_refresh_grip_tuning()


func _adjust_wheel_mounts() -> void:
	var front_rest: float = front_spring_length * (1.0 - front_resting_ratio)
	var rear_rest: float = rear_spring_length * (1.0 - rear_resting_ratio)
	var front_y: float = front_tire_radius + front_rest - MODEL_BODY_GROUND_CLEARANCE
	var rear_y: float = rear_tire_radius + rear_rest - MODEL_BODY_GROUND_CLEARANCE
	for node in [front_left_wheel, front_right_wheel]:
		if node is Node3D:
			(node as Node3D).position.y = front_y
	for node in [rear_left_wheel, rear_right_wheel]:
		if node is Node3D:
			(node as Node3D).position.y = rear_y


func apply_track_grip(grip_scale: float, rolling_scale: float, offroad_grip: float = 0.6) -> void:
	track_grip_scale = maxf(0.05, grip_scale)
	track_rolling_scale = maxf(0.05, rolling_scale)
	track_offroad_grip = clampf(offroad_grip, 0.05, 1.0)
	_refresh_grip_tuning()


func _get_surface_cof(surface_name: String) -> float:
	if not surface_name.is_empty() and coefficient_of_friction.has(surface_name):
		return float(coefficient_of_friction[surface_name])
	if coefficient_of_friction.has("Dirt"):
		return float(coefficient_of_friction["Dirt"])
	return float(coefficient_of_friction.get("Road", 1.25))


func _refresh_grip_tuning() -> void:
	var grip: float = track_grip_scale
	var stiffness: float = 1.0
	var rolling: float = track_rolling_scale
	if active_setup != null:
		grip *= active_setup.grip_scale
		stiffness = active_setup.tire_stiffness_scale
		rolling *= active_setup.rolling_resistance_scale
	tire_stiffnesses = {}
	coefficient_of_friction = {}
	rolling_resistance = {}
	lateral_grip_assist = {}
	longitudinal_grip_ratio = {}
	for key in BASE_COF.keys():
		tire_stiffnesses[key] = float(BASE_STIFFNESS[key]) * stiffness
		# offroad_grip — отношение сцепления травы к гравийному полотну.
		var base_cof: float = float(BASE_COF["Dirt"]) * track_offroad_grip if key == "Grass" else float(BASE_COF[key])
		coefficient_of_friction[key] = base_cof * grip
		rolling_resistance[key] = float(BASE_ROLLING[key]) * rolling
		lateral_grip_assist[key] = float(BASE_LATERAL[key])
		longitudinal_grip_ratio[key] = float(BASE_LONGITUDINAL[key])
	for wheel: WheelType in wheel_array:
		wheel.tire_stiffnesses = tire_stiffnesses
		wheel.coefficient_of_friction = coefficient_of_friction
		wheel.rolling_resistance = rolling_resistance
		wheel.lateral_grip_assist = lateral_grip_assist
		wheel.longitudinal_grip_ratio = longitudinal_grip_ratio
		var surface: String = str(wheel.surface_type)
		if surface.is_empty() or not coefficient_of_friction.has(surface):
			surface = "Dirt"
		wheel.current_cof = float(coefficient_of_friction.get(surface, 1.0))
		wheel.current_rolling_resistance = float(rolling_resistance.get(surface, 1.0))
		wheel.current_lateral_grip_assist = float(lateral_grip_assist.get(surface, 0.0))
		wheel.current_longitudinal_grip_ratio = float(longitudinal_grip_ratio.get(surface, 0.5))
		wheel.current_tire_stiffness = 1000000.0 + 8000000.0 * float(tire_stiffnesses.get(surface, 1.0))
	# Сила тормозов рассчитывается по сцеплению и должна обновляться после
	# применения ресурса трассы, уже после инициализации колёс.
	if is_ready and not wheel_array.is_empty():
		calculate_brake_force()


func get_spawn_height_offset() -> float:
	var fl_wheel: Node3D = front_left_wheel
	if fl_wheel == null:
		fl_wheel = get_node_or_null("Wheel_FL") as Node3D
	if fl_wheel == null:
		return 0.1
	var rest_length: float = front_spring_length * (1.0 - front_resting_ratio)
	return rest_length + front_tire_radius - fl_wheel.position.y


func _apply_visual_setup() -> void:
	var safe_visual_radius: float = maxf(0.05, wheel_visual_radius)
	var front_scale: float = front_tire_radius / safe_visual_radius
	var rear_scale: float = rear_tire_radius / safe_visual_radius
	for wheel_name in ["Wheel_FL", "Wheel_FR"]:
		var wheel_node: Node = get_node_or_null(wheel_name)
		if wheel_node != null:
			var visual: Node3D = wheel_node.get_node_or_null("WheelVisual") as Node3D
			if visual != null:
				visual.scale = Vector3.ONE * front_scale
	for wheel_name in ["Wheel_RL", "Wheel_RR"]:
		var wheel_node: Node = get_node_or_null(wheel_name)
		if wheel_node != null:
			var visual: Node3D = wheel_node.get_node_or_null("WheelVisual") as Node3D
			if visual != null:
				visual.scale = Vector3.ONE * rear_scale

	var model: Node3D = get_node_or_null("low poly lance evo") as Node3D
	if model != null:
		model.position.y = front_tire_radius - MODEL_BODY_GROUND_CLEARANCE - MODEL_WHEEL_CENTER_Y
	if active_setup == null or model == null:
		return
	for child in model.get_children():
		if child is MeshInstance3D and String(child.name).begins_with("Mitsubishi_Body"):
			_tint_body_mesh(child as MeshInstance3D, active_setup.body_color)


func _tint_body_mesh(instance: MeshInstance3D, tint: Color) -> void:
	var source: Material = instance.material_override
	if source == null and instance.mesh != null and instance.mesh.get_surface_count() > 0:
		source = instance.mesh.surface_get_material(0)
	var material: StandardMaterial3D = null
	if source is StandardMaterial3D:
		material = source.duplicate() as StandardMaterial3D
	if material == null:
		material = StandardMaterial3D.new()
	material.albedo_color = tint
	instance.material_override = material


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("reset_car"):
		reset_to_spawn()
		return
	if Input.is_action_just_pressed("camera_switch"):
		camera_mode = (camera_mode + 1) % 3
		mouse_yaw = 0.0
		mouse_pitch = 0.0
		smoothed_mouse_yaw = 0.0
		smoothed_mouse_pitch = 0.0
		g_force_offset = Vector3.ZERO
		_apply_initial_camera_fov()
		if camera_mode == CameraMode.CHASE_3RD:
			_reset_action_camera()
	if Input.is_action_just_pressed("camera_recenter"):
		recenter_look()
	if Input.is_action_just_pressed("drivetrain_switch"):
		set_drivetrain_mode((drivetrain_mode + 1) % 3)

	_handle_gear_input()

	# W — всегда газ, S — всегда тормоз, в том числе на задней передаче.
	# На геймпаде триггеры и стик дополнительно проходят через мёртвую зону
	# и кривую отклика из ControllerManager (клавиатура остаётся как была).
	var controller := _controller_manager()
	if controller != null and controller.has_method("get_throttle_input"):
		throttle_input = float(controller.call("get_throttle_input"))
		brake_input = float(controller.call("get_brake_input"))
		steer_input = float(controller.call("get_steering_input"))
		handbrake_input = float(controller.call("get_handbrake_input"))
	else:
		throttle_input = Input.get_action_strength("throttle")
		brake_input = Input.get_action_strength("brake")
		steer_input = Input.get_axis("steer_right", "steer_left")
		handbrake_input = Input.get_action_strength("handbrake")
	var limit_end: float = maxf(steering_limit_full_kmh, steering_limit_start_kmh + 1.0)
	var steering_speed_blend: float = smoothstep(steering_limit_start_kmh, limit_end, speed_kmh)
	steering_input = steer_input * lerpf(1.0, high_speed_steering_scale, steering_speed_blend)

	_apply_gamepad_look(delta)
	super._physics_process(delta)
	_update_handbrake_grip(delta)

	var raw_speed_mps: float = Vector2(linear_velocity.x, linear_velocity.z).length()
	speed_mps = lerpf(speed_mps, raw_speed_mps, _response_weight(10.0, delta))
	speed_kmh = speed_mps * 3.6

	current_rpm = motor_rpm
	manual_mode = not automatic_transmission
	_update_gravel_particles()

	_update_cameras(delta)

	var fall_limit: float = fall_limit_y
	if fall_limit_provider.is_valid():
		var provided: Variant = fall_limit_provider.call()
		if provided is float or provided is int:
			fall_limit = float(provided)
	if global_position.y < fall_limit:
		reset_to_spawn()


func _handle_gear_input() -> void:
	if Input.is_action_just_pressed("shift_up"):
		# Из R или N — на первую. Передачи 1–6 остаются автоматическими.
		if current_gear <= 0:
			_select_gear(1)
		return
	if not Input.is_action_just_pressed("shift_down"):
		return
	# Задний ход — только осознанно и только на малой скорости.
	if current_gear == 0:
		_select_gear(-1)
	elif current_gear == 1 and speed_kmh < REVERSE_SHIFT_MAX_KMH:
		_select_gear(-1)


func _select_gear(target_gear: int) -> void:
	if target_gear == current_gear or is_shifting:
		return
	direction_request_active = false
	direction_target = 0
	# shift() принимает относительное изменение, поэтому считаем разницу.
	shift(target_gear - current_gear)
	_rumble(0.12, gamepad_rumble_on_shift, 0.08)


func set_drivetrain_mode(mode: int) -> void:
	drivetrain_mode = clampi(mode, DrivetrainMode.AWD, DrivetrainMode.FWD)
	_apply_drivetrain()


func _apply_drivetrain() -> void:
	if front_axle == null or rear_axle == null:
		return

	match drivetrain_mode:
		DrivetrainMode.AWD:
			front_torque_split = awd_front_torque
			front_locking_differential_engage_torque = 120.0
			rear_locking_differential_engage_torque = 180.0
		DrivetrainMode.RWD:
			front_torque_split = 0.0
			front_locking_differential_engage_torque = -1.0
			rear_locking_differential_engage_torque = 220.0
		DrivetrainMode.FWD:
			front_torque_split = 1.0
			front_locking_differential_engage_torque = 180.0
			rear_locking_differential_engage_torque = -1.0

	front_axle.is_drive_axle = drivetrain_mode != DrivetrainMode.RWD
	rear_axle.is_drive_axle = drivetrain_mode != DrivetrainMode.FWD
	front_axle.differential_lock_torque = front_locking_differential_engage_torque
	rear_axle.differential_lock_torque = rear_locking_differential_engage_torque

	drive_wheels.clear()
	drive_axles_inertia = 0.0
	average_drive_wheel_radius = 0.0
	for axle in axles:
		for wheel: WheelType in axle.wheels:
			wheel.is_driven = axle.is_drive_axle
			if axle.is_drive_axle:
				drive_wheels.append(wheel)
				drive_axles_inertia += wheel.wheel_moment
				average_drive_wheel_radius += wheel.tire_radius
	average_drive_wheel_radius /= float(maxi(1, drive_wheels.size()))


func _update_handbrake_grip(delta: float) -> void:
	if rear_axle == null:
		return
	for wheel: WheelType in rear_axle.wheels:
		var surface_grip: float = _get_surface_cof(str(wheel.surface_type))
		var target_grip: float = surface_grip * lerpf(1.0, 0.55, clampf(handbrake_input, 0.0, 1.0))
		var response: float = 16.0 if handbrake_input > 0.1 else 7.0
		wheel.current_cof = lerpf(wheel.current_cof, target_grip, clampf(response * delta, 0.0, 1.0))


func _setup_gravel_particles() -> void:
	if gravel_particles == null:
		return
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(0.78, 0.05, 0.24)
	process_material.direction = Vector3(0.0, 0.42, -1.0)
	process_material.spread = 32.0
	process_material.initial_velocity_min = 1.2
	process_material.initial_velocity_max = 4.2
	process_material.gravity = Vector3(0.0, -4.5, 0.0)
	process_material.scale_min = 0.45
	process_material.scale_max = 1.65
	process_material.color = Color(0.43, 0.35, 0.25, 0.48)
	gravel_particles.process_material = process_material

	var dust_material := StandardMaterial3D.new()
	dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_material.albedo_color = Color(0.48, 0.39, 0.29, 0.48)
	dust_material.roughness = 1.0
	var dust_mesh := SphereMesh.new()
	dust_mesh.radius = 0.11
	dust_mesh.height = 0.22
	dust_mesh.radial_segments = 6
	dust_mesh.rings = 3
	dust_mesh.surface_set_material(0, dust_material)
	gravel_particles.draw_pass_1 = dust_mesh
	gravel_particles.visibility_aabb = AABB(Vector3(-30.0, -15.0, -30.0), Vector3(60.0, 60.0, 60.0))
	gravel_particles.emitting = false


func _update_gravel_particles() -> void:
	if gravel_particles == null or rear_axle == null:
		return
	var rear_slip: float = 0.0
	var rear_contact: bool = false
	for wheel: WheelType in rear_axle.wheels:
		rear_contact = rear_contact or wheel.is_colliding()
		rear_slip = maxf(rear_slip, absf(wheel.slip_vector.x) + absf(wheel.slip_vector.y))
	if handbrake_input > 0.1:
		rear_slip = maxf(rear_slip, 0.85)
	gravel_particles.emitting = rear_contact and speed_kmh > 8.0 and rear_slip > 0.32


func _apply_initial_camera_fov() -> void:
	if active_camera == null:
		return
	var speed_factor: float = clampf(speed_kmh / 160.0, 0.0, 1.0)
	match camera_mode:
		CameraMode.CHASE_3RD:
			active_camera.fov = lerpf(chase_min_fov, chase_max_fov, speed_factor)
		CameraMode.HOOD:
			active_camera.fov = hood_fov + inside_speed_fov_bonus * clampf(speed_kmh / 180.0, 0.0, 1.0)
		CameraMode.COCKPIT_1ST:
			active_camera.fov = cockpit_fov + inside_speed_fov_bonus * clampf(speed_kmh / 180.0, 0.0, 1.0)


func _update_cameras(delta: float) -> void:
	if active_camera == null:
		return

	mouse_idle_timer += delta
	if mouse_auto_return_delay > 0.0 and mouse_idle_timer >= mouse_auto_return_delay:
		var return_weight: float = _response_weight(mouse_return_speed, delta)
		mouse_yaw = lerp_angle(mouse_yaw, 0.0, return_weight)
		mouse_pitch = lerpf(mouse_pitch, 0.0, return_weight)

	var look_smooth: float = 1.0 if delta <= 0.0 else _response_weight(18.0, delta)
	smoothed_mouse_yaw = lerp_angle(smoothed_mouse_yaw, mouse_yaw, look_smooth)
	smoothed_mouse_pitch = lerpf(smoothed_mouse_pitch, mouse_pitch, look_smooth)

	active_camera.top_level = (camera_mode == CameraMode.CHASE_3RD)
	match camera_mode:
		CameraMode.CHASE_3RD:
			_update_action_camera(delta)
		CameraMode.HOOD:
			if cam_hood != null:
				active_camera.global_transform = cam_hood.global_transform
				active_camera.rotate_object_local(Vector3.UP, smoothed_mouse_yaw)
				active_camera.rotate_object_local(Vector3.RIGHT, smoothed_mouse_pitch)
		CameraMode.COCKPIT_1ST:
			_update_cockpit_camera(delta)

	if camera_mode != CameraMode.CHASE_3RD:
		var base_fov: float = cockpit_fov if camera_mode == CameraMode.COCKPIT_1ST else hood_fov
		var target_fov: float = base_fov + inside_speed_fov_bonus * clampf(speed_kmh / 180.0, 0.0, 1.0)
		var fov_weight: float = 1.0 if delta <= 0.0 else _response_weight(6.0, delta)
		active_camera.fov = lerpf(active_camera.fov, target_fov, fov_weight)
	previous_velocity = linear_velocity


func _update_action_camera(delta: float) -> void:
	var car_forward: Vector3 = global_transform.basis.z.normalized()
	var car_yaw: float = camera_yaw
	if Vector2(car_forward.x, car_forward.z).length_squared() > 0.0001:
		car_yaw = atan2(car_forward.x, car_forward.z)

	var desired_yaw: float = car_yaw
	var planar_velocity := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var planar_speed: float = planar_velocity.length()

	if planar_speed > 4.0 and planar_velocity.normalized().dot(car_forward) > 0.0:
		var velocity_yaw: float = atan2(planar_velocity.x, planar_velocity.z)
		var follow_amount: float = chase_velocity_follow * clampf((speed_kmh - 15.0) / 60.0, 0.0, 1.0)
		desired_yaw = lerp_angle(car_yaw, velocity_yaw, follow_amount)

	if not camera_initialized or delta <= 0.0:
		camera_yaw = desired_yaw
		camera_initialized = true
	else:
		camera_yaw = lerp_angle(camera_yaw, desired_yaw, _response_weight(chase_yaw_response, delta))

	# Опорная точка привязана напрямую к кузову без отставания по координатам,
	# чтобы машина НИКОГДА не дёргалась и не "телепортировалась" в кадре при поворотах.
	var pivot: Vector3 = global_position + Vector3(0.0, _scene_pivot_height, 0.0)

	var effective_yaw: float = camera_yaw + smoothed_mouse_yaw
	var is_freelooking: float = clampf(absf(smoothed_mouse_yaw) * 1.5 + absf(smoothed_mouse_pitch) * 1.5, 0.0, 1.0)

	var camera_forward := Vector3(sin(effective_yaw), 0.0, cos(effective_yaw))
	# camera_local_x соответствует +basis.x машины (Vector3.UP x forward),
	# а camera_right — визуальному правому боку при взгляде вдоль camera_forward.
	var camera_local_x: Vector3 = Vector3.UP.cross(camera_forward).normalized()
	var camera_right: Vector3 = -camera_local_x
	var speed_factor: float = clampf(speed_kmh / 160.0, 0.0, 1.0)

	var base_back_dist: float = maxf(1.0, -_scene_chase_local_pos.z) if use_cam_chase_from_scene else chase_distance
	var base_height_diff: float = (_scene_chase_local_pos.y - _scene_pivot_height) if use_cam_chase_from_scene else (chase_height - _scene_pivot_height)
	var base_side_offset: float = _scene_chase_local_pos.x if use_cam_chase_from_scene else 0.0

	var base_elevation: float = atan2(base_height_diff, base_back_dist)
	var base_radius: float = Vector2(base_back_dist, base_height_diff).length()
	var desired_dist: float = base_radius * lerpf(1.0, 1.06, speed_factor)
	var total_pitch: float = clampf(
		base_elevation + smoothed_mouse_pitch,
		deg_to_rad(-10.0),
		deg_to_rad(75.0)
	)

	var orbit_dir: Vector3 = (-camera_forward * cos(total_pitch) + Vector3.UP * sin(total_pitch)).normalized()
	var side_vec: Vector3 = (
		camera_local_x * base_side_offset * (1.0 - is_freelooking)
		+ camera_right * true_steering_amount * chase_corner_offset * speed_factor * (1.0 - is_freelooking)
	)

	var ideal_cam_pos: Vector3 = pivot + orbit_dir * desired_dist + side_vec

	# Проверка стен: отключаем попадание луча в Area3D (триггеры/чекпоинты) и саму машину,
	# а дистанцию сглаживаем, чтобы камера не прыгала мгновенно.
	var query := PhysicsRayQueryParameters3D.create(pivot, ideal_cam_pos, 1, [get_rid()])
	query.collide_with_areas = false
	query.hit_from_inside = false
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	var target_dist: float = desired_dist
	if not hit.is_empty():
		var hit_dist: float = pivot.distance_to(hit["position"]) - chase_collision_radius
		target_dist = clampf(hit_dist, 1.2, desired_dist)

	if delta <= 0.0:
		_smoothed_cam_dist = target_dist
	else:
		var dist_speed: float = 25.0 if target_dist < _smoothed_cam_dist else 8.0
		_smoothed_cam_dist = lerpf(_smoothed_cam_dist, target_dist, _response_weight(dist_speed, delta))

	camera_position = pivot + orbit_dir * _smoothed_cam_dist + side_vec

	var min_cam_y: float = pivot.y - 0.35
	if camera_position.y < min_cam_y:
		camera_position.y = min_cam_y

	# Плавный учёт наклона машины на горках
	var target_slope_y: float = car_forward.y * 0.65
	if delta <= 0.0:
		_smoothed_slope_y = target_slope_y
	else:
		_smoothed_slope_y = lerpf(_smoothed_slope_y, target_slope_y, _response_weight(6.0, delta))

	# Точка взгляда всегда отсчитывается от стабильного центра (pivot),
	# а точка фокуса при обзоре мышью лежит ровно на пересечении луча взгляда CamChase
	# с центральной вертикальной осью машины — без клевка при начале движения мыши.
	var look_dist: float = base_back_dist + chase_lookahead
	var default_look_dir_world: Vector3 = (
		camera_forward * _scene_chase_look_dir_local.z
		+ Vector3.UP * (_scene_chase_look_dir_local.y + _smoothed_slope_y)
		+ camera_local_x * _scene_chase_look_dir_local.x
	).normalized()
	var ideal_unblocked_pos: Vector3 = (
		pivot
		- camera_forward * base_back_dist
		+ Vector3.UP * base_height_diff
		+ camera_local_x * base_side_offset * (1.0 - is_freelooking)
	)
	var default_look_target: Vector3 = ideal_unblocked_pos + default_look_dir_world * look_dist

	var ray_to_center_dist: float = base_back_dist / maxf(0.15, default_look_dir_world.dot(camera_forward))
	var freelook_focus_y: float = clampf(
		base_height_diff + default_look_dir_world.y * ray_to_center_dist,
		-0.6,
		1.5
	)
	var freelook_target: Vector3 = pivot + Vector3(0.0, freelook_focus_y, 0.0)
	var look_target: Vector3 = default_look_target.lerp(freelook_target, is_freelooking)

	active_camera.global_position = camera_position
	if active_camera.global_position.distance_squared_to(look_target) > 0.001:
		active_camera.look_at(look_target, Vector3.UP)

	var target_fov: float = lerpf(chase_min_fov, chase_max_fov, speed_factor)
	var fov_weight: float = 1.0 if delta <= 0.0 else _response_weight(5.0, delta)
	active_camera.fov = lerpf(active_camera.fov, target_fov, fov_weight)


func _update_cockpit_camera(delta: float) -> void:
	if cam_cockpit == null:
		return

	if delta <= 0.0 or is_zero_approx(cockpit_motion_strength):
		g_force_offset = Vector3.ZERO
	else:
		var safe_delta: float = maxf(delta, 0.0001)
		var local_accel: Vector3 = global_transform.basis.orthonormalized().inverse() * ((linear_velocity - previous_velocity) / safe_delta)
		local_accel = local_accel.limit_length(80.0)
		var desired_offset := Vector3(
			clampf(-local_accel.x * 0.004, -0.09, 0.09),
			clampf(-local_accel.y * 0.0015, -0.04, 0.04),
			clampf(-local_accel.z * 0.003, -0.12, 0.12)
		)
		g_force_offset = g_force_offset.lerp(desired_offset * cockpit_motion_strength, _response_weight(8.0, delta))

	# Маркер — источник истины: ни переключение вида, ни тряска его не двигают.
	# Смещение ускорения применяется только к камере в координатах кузова.
	active_camera.global_transform = cam_cockpit.global_transform
	active_camera.global_position += global_transform.basis * g_force_offset
	active_camera.rotate_object_local(Vector3.UP, smoothed_mouse_yaw)
	active_camera.rotate_object_local(Vector3.RIGHT, smoothed_mouse_pitch)
	active_camera.rotate_object_local(Vector3.FORWARD, true_steering_amount * deg_to_rad(cockpit_roll_degrees) * cockpit_motion_strength)


func _reset_action_camera() -> void:
	mouse_yaw = 0.0
	mouse_pitch = 0.0
	smoothed_mouse_yaw = 0.0
	smoothed_mouse_pitch = 0.0
	_smoothed_slope_y = 0.0
	var basis_to_use: Basis = global_transform.basis if is_inside_tree() else spawn_transform.basis
	var forward: Vector3 = basis_to_use.z.normalized()
	if Vector2(forward.x, forward.z).length_squared() > 0.0001:
		camera_yaw = atan2(forward.x, forward.z)
	else:
		camera_yaw = 0.0
	var pivot: Vector3 = global_position + Vector3(0.0, _scene_pivot_height, 0.0)

	var base_back_dist: float = maxf(1.0, -_scene_chase_local_pos.z) if use_cam_chase_from_scene else chase_distance
	var base_height_diff: float = (_scene_chase_local_pos.y - _scene_pivot_height) if use_cam_chase_from_scene else (chase_height - _scene_pivot_height)
	_smoothed_cam_dist = Vector2(base_back_dist, base_height_diff).length()

	if use_cam_chase_from_scene and cam_chase != null and is_inside_tree():
		camera_position = cam_chase.global_position
	else:
		camera_position = pivot - forward * chase_distance + Vector3(0.0, chase_height - _scene_pivot_height, 0.0)

	camera_initialized = true
	if active_camera == null:
		return

	active_camera.top_level = (camera_mode == CameraMode.CHASE_3RD)
	if camera_mode != CameraMode.CHASE_3RD:
		return

	active_camera.global_position = camera_position

	var local_x: Vector3 = Vector3.UP.cross(forward).normalized()
	var look_dir: Vector3 = (
		forward * _scene_chase_look_dir_local.z
		+ Vector3.UP * _scene_chase_look_dir_local.y
		+ local_x * _scene_chase_look_dir_local.x
	).normalized()
	var look_target: Vector3 = camera_position + look_dir * 10.0
	if camera_position.distance_squared_to(look_target) > 0.001:
		active_camera.look_at(look_target, Vector3.UP)


func _response_weight(response: float, delta: float) -> float:
	return 1.0 - exp(-maxf(response, 0.0) * maxf(delta, 0.0))


func _controller_manager() -> Node:
	return get_node_or_null("/root/ControllerManager")


func _rumble(weak: float, strong: float, duration: float = 0.12) -> void:
	if not gamepad_rumble_enabled:
		return
	var controller := _controller_manager()
	if controller != null and controller.has_method("rumble"):
		controller.call("rumble", weak, strong, duration)


## Правый стик двигает свободный обзор так же, как мышь, но с постоянной
## угловой скоростью. Работает в погоне и в видах из кабины/с капота.
func _apply_gamepad_look(delta: float) -> void:
	if not mouse_look_enabled or not gamepad_look_enabled:
		return
	var controller := _controller_manager()
	if controller == null or not controller.has_method("get_look_vector"):
		return
	if not bool(controller.get("gamepad_active")):
		return
	var look: Vector2 = controller.call("get_look_vector")
	if look.length_squared() < 0.0001:
		return

	var step: float = deg_to_rad(gamepad_look_speed) * maxf(delta, 0.0)
	mouse_yaw -= look.x * step
	mouse_idle_timer = 0.0
	if camera_mode == CameraMode.CHASE_3RD:
		mouse_pitch += look.y * step
		mouse_yaw = wrapf(mouse_yaw, -PI, PI)
		mouse_pitch = clampf(mouse_pitch, deg_to_rad(chase_min_pitch_deg), deg_to_rad(chase_max_pitch_deg))
	else:
		var max_yaw: float = deg_to_rad(inside_max_yaw_deg)
		mouse_pitch -= look.y * step
		mouse_yaw = clampf(mouse_yaw, -max_yaw, max_yaw)
		mouse_pitch = clampf(mouse_pitch, deg_to_rad(inside_min_pitch_deg), deg_to_rad(inside_max_pitch_deg))


## R3 / средняя кнопка мыши возвращают обзор в центр.
func recenter_look() -> void:
	mouse_yaw = 0.0
	mouse_pitch = 0.0
	smoothed_mouse_yaw = 0.0
	smoothed_mouse_pitch = 0.0
	mouse_idle_timer = 10.0


func reset_to_spawn() -> void:
	var target: Transform3D = spawn_transform
	if reset_provider.is_valid():
		var provided: Variant = reset_provider.call()
		if provided is Transform3D:
			target = provided
	global_transform = target
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = false
	previous_global_position = global_position
	previous_velocity = Vector3.ZERO
	local_velocity = Vector3.ZERO
	speed = 0.0
	speed_mps = 0.0
	speed_kmh = 0.0

	throttle_input = 0.0
	brake_input = 0.0
	steering_input = 0.0
	steer_input = 0.0
	handbrake_input = 0.0
	throttle_amount = 0.0
	brake_amount = 0.0
	brake_force = 0.0
	handbrake_force = 0.0
	steering_amount = 0.0
	true_steering_amount = 0.0
	torque_output = 0.0
	clutch_torque = 0.0
	is_braking = false
	enable_stability = false
	motor_rpm = idle_rpm
	current_rpm = idle_rpm
	current_gear = 1
	requested_gear = 1
	automatic_transmission = true
	manual_mode = false
	is_shifting = false
	need_clutch = true
	direction_request_active = false
	direction_target = 0
	delta_time = 0.0
	last_shift_delta_time = 0.0
	complete_shift_delta_time = 0.0

	for axle in axles:
		axle.rotation_split = 0.0
		axle.applied_split = 0.0
		axle.suspension_compression_left = 0.0
		axle.suspension_compression_right = 0.0

	for wheel: WheelType in wheel_array:
		wheel.spin = 0.0
		wheel.spin_velocity_diff = 0.0
		wheel.applied_torque = 0.0
		wheel.force_vector = Vector2.ZERO
		wheel.slip_vector = Vector2.ZERO
		wheel.spring_force = 0.0
		wheel.damping_force = 0.0
		wheel.antiroll_force = 0.0
		wheel.spring_current_length = wheel.spring_length
		wheel.max_spring_length = wheel.spring_length
		wheel.previous_compression = 0.0
		wheel.local_velocity = Vector3.ZERO
		wheel.previous_velocity = Vector3.ZERO
		wheel.previous_global_position = wheel.global_position
		wheel.abs_enable_time = 0.0
		wheel.limit_spin = false
		wheel.current_cof = _get_surface_cof(str(wheel.surface_type))
		wheel.force_raycast_update()

	g_force_offset = Vector3.ZERO
	if gravel_particles != null:
		gravel_particles.emitting = false
	_reset_action_camera()
	_apply_initial_camera_fov()
	if camera_mode != CameraMode.CHASE_3RD:
		_update_cameras(0.0)
	_rumble(0.35, gamepad_rumble_on_reset, 0.25)


func get_average_tire_slip() -> float:
	var total_slip: float = 0.0
	for wheel: WheelType in wheel_array:
		total_slip += absf(wheel.slip_vector.x) + absf(wheel.slip_vector.y)
	return total_slip / float(maxi(1, wheel_array.size()))


func get_max_suspension_compression() -> float:
	var maximum: float = 0.0
	for wheel: WheelType in wheel_array:
		if wheel.spring_length > 0.0:
			var compression: float = 1.0 - wheel.spring_current_length / wheel.spring_length
			maximum = maxf(maximum, compression)
	return clampf(maximum, 0.0, 1.0)


func get_drivetrain_label() -> String:
	match drivetrain_mode:
		DrivetrainMode.AWD:
			return "AWD %d:%d" % [roundi(awd_front_torque * 100.0), roundi((1.0 - awd_front_torque) * 100.0)]
		DrivetrainMode.RWD:
			return "RWD 0:100"
		DrivetrainMode.FWD:
			return "FWD 100:0"
	return ""


func get_gear_label() -> String:
	if current_gear == -1:
		return "R"
	if current_gear == 0:
		return "N"
	return str(current_gear)


func get_camera_label() -> String:
	match camera_mode:
		CameraMode.CHASE_3RD:
			return "ACTION 3RD"
		CameraMode.HOOD:
			return "КАПОТ"
		CameraMode.COCKPIT_1ST:
			return "КАБИНА"
	return ""
