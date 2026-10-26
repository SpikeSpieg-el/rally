# Rally adaptation of Godot Easy Vehicle Physics (MIT).
# Base: https://github.com/L3w1s6/infinite-rally/tree/main/Addons/gevp
# See res://scripts/gevp/LICENSE for the original copyright and license.
class_name RallyCar
extends "res://scripts/gevp/vehicle.gd"

enum CameraMode { CHASE_3RD, HOOD, COCKPIT_1ST }
enum DrivetrainMode { AWD, RWD, FWD }

const COCKPIT_BASE_POSITION: Vector3 = Vector3(0.35, 0.98, -0.15)

@export_group("Rally Drivetrain")
@export_enum("AWD 38:62", "RWD 0:100", "FWD 100:0") var drivetrain_mode: int = DrivetrainMode.AWD
@export_range(0.0, 1.0, 0.01) var awd_front_torque: float = 0.38

@export_group("Action Camera")
@export var chase_distance: float = 5.8
@export var chase_height: float = 1.55
@export var chase_target_height: float = 0.75
@export var chase_lookahead: float = 2.2
@export_range(0.0, 1.0, 0.01) var chase_velocity_follow: float = 0.28
@export var chase_position_response: float = 7.5
@export var chase_yaw_response: float = 5.0
@export var chase_corner_offset: float = 0.38
@export var chase_collision_radius: float = 0.28
@export var chase_min_fov: float = 72.0
@export var chase_max_fov: float = 91.0

@export_group("Mouse Look")
@export var mouse_look_enabled: bool = true
@export_range(0.0005, 0.01, 0.0005) var mouse_sensitivity: float = 0.0025
@export var mouse_auto_return_delay: float = 1.5
@export var mouse_return_speed: float = 4.5
@export var chase_min_pitch_deg: float = -12.0
@export var chase_max_pitch_deg: float = 45.0
@export var inside_max_yaw_deg: float = 110.0
@export var inside_min_pitch_deg: float = -35.0
@export var inside_max_pitch_deg: float = 35.0

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

# Переменные для обзора мышью
var mouse_yaw: float = 0.0
var mouse_pitch: float = 0.0
var mouse_idle_timer: float = 10.0


func _ready() -> void:
	_configure_gevp()
	super._ready()
	_apply_drivetrain()
	motor_rpm = idle_rpm
	current_rpm = idle_rpm
	current_gear = 1
	requested_gear = 1
	_setup_gravel_particles()
	active_camera.top_level = true
	active_camera.global_transform = cam_chase.global_transform
	_reset_action_camera()
	
	if mouse_look_enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not mouse_look_enabled:
		return

	# Освобождение курсора по Esc (ui_cancel)
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Захват курсора по клику ЛКМ и сброс обзора по СКМ (колесику)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			mouse_yaw = 0.0
			mouse_pitch = 0.0

	# Обработка движения мыши
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_yaw -= event.relative.x * mouse_sensitivity
		mouse_pitch -= event.relative.y * mouse_sensitivity
		mouse_idle_timer = 0.0

		if camera_mode == CameraMode.CHASE_3RD:
			mouse_yaw = wrapf(mouse_yaw, -PI, PI)
			mouse_pitch = clampf(mouse_pitch, deg_to_rad(chase_min_pitch_deg), deg_to_rad(chase_max_pitch_deg))
		else:
			var max_yaw: float = deg_to_rad(inside_max_yaw_deg)
			mouse_yaw = clampf(mouse_yaw, -max_yaw, max_yaw)
			mouse_pitch = clampf(mouse_pitch, deg_to_rad(inside_min_pitch_deg), deg_to_rad(inside_max_pitch_deg))


# Central Honda-inspired rally hatch setup. Edit these values to tune the car;
# the accompanying RALLY_SETUP_RU.md explains each group and safe ranges.
func _configure_gevp() -> void:
	front_left_wheel = $Wheel_FL
	front_right_wheel = $Wheel_FR
	rear_left_wheel = $Wheel_RL
	rear_right_wheel = $Wheel_RR

	# Steering: mechanical Ackermann remains in GEVP; assists are deliberately mild.
	steering_speed = 4.2
	countersteer_speed = 9.0
	steering_speed_decay = 0.24
	steering_slip_assist = 0.30
	countersteer_assist = 0.20
	steering_exponent = 1.45
	max_steering_angle = deg_to_rad(35.0)
	front_steering_ratio = 1.0
	rear_steering_ratio = 0.0

	throttle_speed = 8.0
	braking_speed = 10.0
	front_brake_bias = 0.60
	traction_control_max_slip = 0.80

	# No artificial yaw/upright torque on a grounded car: suspension and tires do the work.
	enable_stability = false
	stability_yaw_engage_angle = 0.10
	stability_yaw_strength = 0.0
	stability_yaw_ground_multiplier = 1.0
	stability_upright_spring = 0.0
	stability_upright_damping = 0.0

	# Approximate 1.6T rally hatch, not a particular licensed Honda model.
	max_torque = 390.0
	max_rpm = 7600.0
	idle_rpm = 900.0
	motor_drag = 0.005
	motor_brake = 10.0
	motor_moment = 0.35
	clutch_out_rpm = 2700.0
	max_clutch_torque_ratio = 1.45
	torque_curve = Curve.new()
	torque_curve.add_point(Vector2(0.0, 0.46))
	torque_curve.add_point(Vector2(0.56, 1.0))
	torque_curve.add_point(Vector2(1.0, 0.72))

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

	# 1230 kg, slightly nose-heavy. CoG is about 0.47 m above the ground at rest.
	vehicle_mass = 1230.0
	front_weight_distribution = 0.56
	center_of_gravity_height_offset = -0.02
	inertia_multiplier = 1.0

	# Long-travel rally suspension: soft enough to articulate, damped enough to land.
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
	front_arb_ratio = 0.16
	rear_arb_ratio = 0.12
	front_camber = 0.012
	rear_camber = 0.012
	front_toe = 0.003
	rear_toe = 0.002
	front_bump_stop_multiplier = 1.2
	rear_bump_stop_multiplier = 1.2

	# Separate gravel/grass grip instead of using race-tarmac grip everywhere.
	contact_patch = 0.22
	braking_grip_multiplier = 1.25
	wheel_to_body_torque_multiplier = 0.5
	tire_stiffnesses = {"Road": 5.0, "Dirt": 2.2, "Grass": 1.4}
	coefficient_of_friction = {"Road": 1.50, "Dirt": 1.00, "Grass": 0.65}
	rolling_resistance = {"Road": 1.0, "Dirt": 1.8, "Grass": 2.8}
	lateral_grip_assist = {"Road": 0.0, "Dirt": 0.0, "Grass": 0.0}
	longitudinal_grip_ratio = {"Road": 0.70, "Dirt": 0.62, "Grass": 0.50}
	front_tire_radius = 0.35
	rear_tire_radius = 0.35
	front_tire_width = 245.0
	rear_tire_width = 245.0
	front_wheel_mass = 15.0
	rear_wheel_mass = 15.0

	coefficient_of_drag = 0.32
	air_density = 1.225
	frontal_area = 2.0


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("reset_car"):
		reset_to_spawn()
		return
	if Input.is_action_just_pressed("camera_switch"):
		camera_mode = (camera_mode + 1) % 3
		mouse_yaw = 0.0
		mouse_pitch = 0.0
		if camera_mode == CameraMode.CHASE_3RD:
			_reset_action_camera()
	if Input.is_action_just_pressed("drivetrain_switch"):
		set_drivetrain_mode((drivetrain_mode + 1) % 3)
	if Input.is_action_just_pressed("shift_up"):
		automatic_transmission = false
		manual_shift(1)
	elif Input.is_action_just_pressed("shift_down"):
		automatic_transmission = false
		manual_shift(-1)

	throttle_input = Input.get_action_strength("throttle")
	brake_input = Input.get_action_strength("brake")
	steer_input = Input.get_axis("steer_right", "steer_left")
	steering_input = steer_input
	handbrake_input = Input.get_action_strength("handbrake")

	super._physics_process(delta)
	_update_handbrake_grip(delta)

	speed_mps = Vector2(linear_velocity.x, linear_velocity.z).length()
	speed_kmh = speed_mps * 3.6
	current_rpm = motor_rpm
	manual_mode = not automatic_transmission
	_update_gravel_particles()

	if global_position.y < -20.0:
		reset_to_spawn()


func _process(delta: float) -> void:
	_update_cameras(delta)


func set_drivetrain_mode(mode: int) -> void:
	drivetrain_mode = clampi(mode, DrivetrainMode.AWD, DrivetrainMode.FWD)
	_apply_drivetrain()


func _apply_drivetrain() -> void:
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
		for wheel in axle.wheels:
			wheel.is_driven = axle.is_drive_axle
			if axle.is_drive_axle:
				drive_wheels.append(wheel)
				drive_axles_inertia += wheel.wheel_moment
				average_drive_wheel_radius += wheel.tire_radius
	average_drive_wheel_radius /= float(maxi(1, drive_wheels.size()))


func _update_handbrake_grip(delta: float) -> void:
	for wheel in rear_axle.wheels:
		var surface_grip: float = float(coefficient_of_friction.get(wheel.surface_type, 1.5))
		var target_grip: float = surface_grip * 0.50 if handbrake_input > 0.1 else surface_grip
		var response: float = 12.0 if handbrake_input > 0.1 else 3.5
		wheel.current_cof = lerpf(wheel.current_cof, target_grip, clampf(response * delta, 0.0, 1.0))


func _setup_gravel_particles() -> void:
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
	var rear_slip: float = 0.0
	var rear_contact: bool = false
	for wheel in rear_axle.wheels:
		rear_contact = rear_contact or wheel.is_colliding()
		rear_slip = maxf(rear_slip, absf(wheel.slip_vector.x) + absf(wheel.slip_vector.y))
	if handbrake_input > 0.1:
		rear_slip = maxf(rear_slip, 0.85)
	gravel_particles.emitting = rear_contact and speed_kmh > 8.0 and rear_slip > 0.32


func _update_cameras(delta: float) -> void:
	# Автоматический возврат камеры при бездействии мыши
	mouse_idle_timer += delta
	if mouse_auto_return_delay > 0.0 and mouse_idle_timer >= mouse_auto_return_delay:
		var return_weight: float = _response_weight(mouse_return_speed, delta)
		mouse_yaw = lerp_angle(mouse_yaw, 0.0, return_weight)
		mouse_pitch = lerpf(mouse_pitch, 0.0, return_weight)

	active_camera.top_level = camera_mode == CameraMode.CHASE_3RD
	match camera_mode:
		CameraMode.CHASE_3RD:
			_update_action_camera(delta)
		CameraMode.HOOD:
			cam_cockpit.position = COCKPIT_BASE_POSITION
			active_camera.global_transform = cam_hood.global_transform
			active_camera.rotate_object_local(Vector3.UP, mouse_yaw)
			active_camera.rotate_object_local(Vector3.RIGHT, mouse_pitch)
		CameraMode.COCKPIT_1ST:
			_update_cockpit_camera(delta)

	if camera_mode != CameraMode.CHASE_3RD:
		var target_fov: float = lerpf(70.0, 86.0, clampf(speed_kmh / 180.0, 0.0, 1.0))
		active_camera.fov = lerpf(active_camera.fov, target_fov, _response_weight(6.0, delta))
	previous_velocity = linear_velocity


func _update_action_camera(delta: float) -> void:
	var car_forward: Vector3 = global_transform.basis.z.normalized()
	var car_yaw: float = atan2(car_forward.x, car_forward.z)
	var desired_yaw: float = car_yaw
	var planar_velocity := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var planar_speed: float = planar_velocity.length()

	if planar_speed > 4.0 and planar_velocity.normalized().dot(car_forward) > 0.0:
		var velocity_yaw: float = atan2(planar_velocity.x, planar_velocity.z)
		var follow_amount: float = chase_velocity_follow * clampf((speed_kmh - 15.0) / 60.0, 0.0, 1.0)
		desired_yaw = lerp_angle(car_yaw, velocity_yaw, follow_amount)

	camera_yaw = lerp_angle(camera_yaw, desired_yaw, _response_weight(chase_yaw_response, delta))
	
	# Учет вращения мышью вокруг машины
	var effective_yaw: float = camera_yaw + mouse_yaw
	var is_freelooking: float = clampf(absf(mouse_yaw) * 2.0 + absf(mouse_pitch) * 2.0, 0.0, 1.0)
	
	var camera_forward := Vector3(sin(effective_yaw), 0.0, cos(effective_yaw))
	var camera_right: Vector3 = camera_forward.cross(Vector3.UP).normalized()
	var speed_factor: float = clampf(speed_kmh / 160.0, 0.0, 1.0)
	var target: Vector3 = global_position + Vector3(0.0, chase_target_height, 0.0)
	
	# Расчет орбиты с учетом вертикального угла мыши (mouse_pitch)
	var dist: float = chase_distance * lerpf(1.0, 1.08, speed_factor)
	var horiz_dist: float = dist * cos(mouse_pitch)
	var vert_offset: float = chase_height + dist * sin(mouse_pitch)
	
	var desired_position: Vector3 = target - camera_forward * horiz_dist
	desired_position += Vector3(0.0, vert_offset, 0.0)
	desired_position += camera_right * steer_input * chase_corner_offset * speed_factor * (1.0 - is_freelooking)

	if not camera_initialized:
		camera_position = desired_position
		camera_initialized = true
	else:
		# При активном вращении мышью камера реагирует быстрее, чтобы не было задержки (инпут-лага)
		var pos_resp: float = lerpf(chase_position_response, 25.0, is_freelooking)
		camera_position = camera_position.lerp(desired_position, _response_weight(pos_resp, delta))

	# Keep the action camera out of terrain and tree trunks without using a canned path.
	var query := PhysicsRayQueryParameters3D.create(target, camera_position, 1, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var hit_position: Vector3 = hit["position"]
		var hit_normal: Vector3 = hit["normal"]
		camera_position = hit_position + hit_normal * chase_collision_radius

	# Когда смотрим по сторонам мышью, фокусируемся на самой машине, а не на точке впереди неё
	var look_ahead_mult: float = 1.0 - is_freelooking
	var look_target: Vector3 = target + (camera_forward * chase_lookahead + planar_velocity * 0.06) * look_ahead_mult
	
	active_camera.global_position = camera_position
	if active_camera.global_position.distance_squared_to(look_target) > 0.001:
		active_camera.look_at(look_target, Vector3.UP)
		active_camera.rotate_object_local(Vector3(0.0, 0.0, 1.0), deg_to_rad(steer_input * 0.65) * speed_factor * look_ahead_mult)

	var target_fov: float = lerpf(chase_min_fov, chase_max_fov, speed_factor)
	active_camera.fov = lerpf(active_camera.fov, target_fov, _response_weight(5.0, delta))


func _update_cockpit_camera(delta: float) -> void:
	var safe_delta: float = maxf(delta, 0.0001)
	var local_accel: Vector3 = global_transform.basis.inverse() * ((linear_velocity - previous_velocity) / safe_delta)
	local_accel = local_accel.limit_length(80.0)
	var desired_offset := Vector3(
		clampf(-local_accel.x * 0.004, -0.09, 0.09),
		clampf(-local_accel.y * 0.0015, -0.04, 0.04),
		clampf(-local_accel.z * 0.003, -0.12, 0.12)
	)
	g_force_offset = g_force_offset.lerp(desired_offset, _response_weight(8.0, delta))
	cam_cockpit.position = COCKPIT_BASE_POSITION + g_force_offset
	active_camera.global_transform = cam_cockpit.global_transform
	
	# Поворот головы мышью внутри салона + наклон от руля
	active_camera.rotate_object_local(Vector3.UP, mouse_yaw)
	active_camera.rotate_object_local(Vector3.RIGHT, mouse_pitch)
	active_camera.rotate_object_local(Vector3(0.0, 0.0, 1.0), -true_steering_amount * 0.15)


func _reset_action_camera() -> void:
	mouse_yaw = 0.0
	mouse_pitch = 0.0
	var forward: Vector3 = spawn_transform.basis.z.normalized()
	camera_yaw = atan2(forward.x, forward.z)
	var target: Vector3 = global_position + Vector3(0.0, chase_target_height, 0.0)
	camera_position = target - forward * chase_distance + Vector3(0.0, chase_height, 0.0)
	camera_initialized = true
	active_camera.top_level = true
	active_camera.global_position = camera_position
	if camera_position.distance_squared_to(target) > 0.001:
		active_camera.look_at(target + forward * chase_lookahead, Vector3.UP)


func _response_weight(response: float, delta: float) -> float:
	return 1.0 - exp(-maxf(response, 0.0) * maxf(delta, 0.0))


func reset_to_spawn() -> void:
	global_transform = spawn_transform
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

	for wheel in wheel_array:
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
		wheel.current_cof = float(coefficient_of_friction.get(wheel.surface_type, 1.5))

	g_force_offset = Vector3.ZERO
	cam_cockpit.position = COCKPIT_BASE_POSITION
	gravel_particles.emitting = false
	_reset_action_camera()


func get_average_tire_slip() -> float:
	var total_slip: float = 0.0
	for wheel in wheel_array:
		total_slip += absf(wheel.slip_vector.x) + absf(wheel.slip_vector.y)
	return total_slip / float(maxi(1, wheel_array.size()))


func get_max_suspension_compression() -> float:
	var maximum: float = 0.0
	for wheel in wheel_array:
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
