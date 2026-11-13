## Контроллер 3D-приборов и органов управления в кабине (`RallyCockpit`).
##
## Синхронизирует с живыми данными `RallyCar`, активным `RallyCarSetup`,
## `RallyStage` и `SpriteSpeedometer`:
##   - реальные обороты `current_rpm`, отсечку `max_rpm` и блинкеры `ShiftLights`;
##   - сглаженную скорость `speed_kmh` с теми же единицами (`KM/H` / `MPH`) и масштабом, что в HUD;
##   - строковую передачу `get_gear_label()` (`R / N / 1..6`), а также режим КПП и привода;
##   - руль, газ, тормоз, сцепление (`PedalClutchPivot`), ручник и ход кулисы;
##   - штурманский трипмастер (`TripmasterLabel`): этап, таймер, пройденную дистанцию и сетап.
@tool
class_name RallyCockpit
extends Node3D

const KMH_TO_MPH := 0.621371

@export_group("Органы управления")
@export var max_steering_wheel_angle_deg: float = 420.0
@export var steer_smooth_speed: float = 12.0
@export var pedal_smooth_speed: float = 15.0
@export var handbrake_smooth_speed: float = 14.0
@export var gas_max_deg: float = 18.0
@export var brake_max_deg: float = 14.0
@export var clutch_max_deg: float = 16.0
@export var handbrake_max_deg: float = 24.0
@export var shifter_kick_deg: float = 12.0
@export var shifter_return_speed: float = 6.0

@export_group("Синхронизация приборки и UI")
## Брать единицы измерения (KM/H или MPH), масштаб скорости и порог отсечки из HUD-спидометра.
@export var sync_units_with_hud: bool = true
## Показывать на экране MoTeC активную КПП/привод и лимит оборотов выбранного сетапа.
@export var show_setup_mode_in_motec: bool = true
## Обновлять экран штурмана (TripmasterLabel) временем, дистанцией этапа и именем сетапа.
@export var sync_tripmaster_with_stage: bool = true
@export var use_mph: bool = false
@export_range(0.25, 3.0, 0.01) var speed_scale: float = 1.0
@export_range(0.2, 0.9, 0.01) var shift_light_start_ratio: float = 0.55
@export_range(0.6, 1.0, 0.01) var shift_light_end_ratio: float = 0.96
@export_range(0.5, 0.99, 0.01) var redline_ratio: float = 0.86

@export_group("Цвета дисплеев")
@export var gear_normal_color: Color = Color(1.0, 0.92, 0.2, 1.0)
@export var gear_redline_color: Color = Color(1.0, 0.24, 0.16, 1.0)
@export var speed_color: Color = Color(0.85, 0.98, 1.0, 1.0)
@export var rpm_normal_color: Color = Color(0.6, 0.9, 1.0, 1.0)
@export var rpm_redline_color: Color = Color(1.0, 0.30, 0.20, 1.0)
@export var mode_info_color: Color = Color(0.96, 0.74, 0.28, 1.0)
@export var stalled_color: Color = Color(1.0, 0.28, 0.18, 1.0)
@export var tripmaster_color: Color = Color(1.0, 0.55, 0.1, 1.0)

var steering_pivot: Node3D = null
var handbrake_pivot: Node3D = null
var shifter_pivot: Node3D = null
var pedal_gas: Node3D = null
var pedal_brake: Node3D = null
var pedal_clutch: Node3D = null

var motec_display: Node3D = null
var gear_label: Label3D = null
var speed_label: Label3D = null
var rpm_label: Label3D = null
var mode_label: Label3D = null
var limit_label: Label3D = null
var shift_lights: Node3D = null
var tripmaster_label: Label3D = null

var _car: Node = null
var _stage: Node = null
var _speedometer: Node = null
var _current_steer: float = 0.0
var _last_gear: String = "N"
var _shifter_kick: float = 0.0
var _blink_clock: float = 0.0


func _ready() -> void:
	_cache_nodes()
	_resolve_links()
	if not Engine.is_editor_hint():
		_ensure_motec_corner_labels()
	sync_dashboard(0.0)


func _cache_nodes() -> void:
	steering_pivot = get_node_or_null("Dashboard/SteeringColumn/SteeringWheelPivot") as Node3D
	handbrake_pivot = get_node_or_null("Controls/HandbrakeBase/HandbrakePivot") as Node3D
	shifter_pivot = get_node_or_null("Controls/ShifterBase/ShifterPivot") as Node3D
	pedal_gas = get_node_or_null("Controls/PedalBox/PedalGasPivot") as Node3D
	pedal_brake = get_node_or_null("Controls/PedalBox/PedalBrakePivot") as Node3D
	pedal_clutch = get_node_or_null("Controls/PedalBox/PedalClutchPivot") as Node3D
	motec_display = get_node_or_null("Dashboard/MotecDisplay") as Node3D
	gear_label = get_node_or_null("Dashboard/MotecDisplay/GearLabel") as Label3D
	speed_label = get_node_or_null("Dashboard/MotecDisplay/SpeedLabel") as Label3D
	rpm_label = get_node_or_null("Dashboard/MotecDisplay/RPMLabel") as Label3D
	mode_label = get_node_or_null("Dashboard/MotecDisplay/ModeLabel") as Label3D
	limit_label = get_node_or_null("Dashboard/MotecDisplay/LimitLabel") as Label3D
	shift_lights = get_node_or_null("Dashboard/MotecDisplay/ShiftLights") as Node3D
	tripmaster_label = get_node_or_null("Dashboard/CoDriverTripmaster/TripmasterLabel") as Label3D


func _ensure_motec_corner_labels() -> void:
	if motec_display == null or not show_setup_mode_in_motec:
		return
	if mode_label == null:
		mode_label = _make_motec_label("ModeLabel", Vector3(0.055, 0.020, -0.02), 13, 0.00072, mode_info_color)
	if limit_label == null:
		limit_label = _make_motec_label("LimitLabel", Vector3(-0.055, -0.026, -0.02), 13, 0.00072, rpm_normal_color)


func _make_motec_label(node_title: String, at: Vector3, font_sz: int, px_sz: float, col: Color) -> Label3D:
	var lbl := Label3D.new()
	lbl.name = node_title
	lbl.position = at
	lbl.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	lbl.pixel_size = px_sz
	lbl.font_size = font_sz
	lbl.outline_size = 3
	lbl.modulate = col
	motec_display.add_child(lbl)
	return lbl


func _resolve_links() -> void:
	if _car == null or not is_instance_valid(_car):
		var parent_node: Node = get_parent()
		while parent_node != null:
			if "camera_mode" in parent_node and "current_rpm" in parent_node:
				_car = parent_node
				break
			if parent_node is RigidBody3D and _car == null:
				_car = parent_node
			parent_node = parent_node.get_parent()
		if _car == null and is_inside_tree():
			var tree := get_tree()
			if tree != null:
				var cars := tree.get_nodes_in_group("rally_car")
				if not cars.is_empty():
					_car = cars[0]

	if _stage == null or not is_instance_valid(_stage):
		var cur: Node = _car.get_parent() if _car != null else get_parent()
		while cur != null:
			if "track" in cur and "stage_time" in cur:
				_stage = cur
				break
			cur = cur.get_parent()
		if _stage == null and is_inside_tree():
			var tree := get_tree()
			if tree != null:
				var stages := tree.get_nodes_in_group("rally_stage")
				if not stages.is_empty():
					_stage = stages[0]

	if (_speedometer == null or not is_instance_valid(_speedometer)) and _stage != null and "sprite_speedometer" in _stage:
		var sp_var: Variant = _stage.get("sprite_speedometer")
		if sp_var is Node:
			_speedometer = sp_var as Node


func bind_vehicle(car_node: Node, stage_node: Node = null, speedo_node: Node = null) -> void:
	_car = car_node
	if stage_node != null:
		_stage = stage_node
	if speedo_node != null:
		_speedometer = speedo_node


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_blink_clock += delta
	_resolve_links()
	sync_dashboard(delta)


func sync_dashboard(delta: float) -> void:
	var snap: Dictionary = compute_telemetry_snapshot()

	# 1. Руль
	var target_steer: float = float(snap["steer"])
	if delta > 0.0:
		_current_steer = lerpf(_current_steer, target_steer, clampf(delta * steer_smooth_speed, 0.0, 1.0))
	else:
		_current_steer = target_steer
	if steering_pivot != null:
		steering_pivot.rotation.z = deg_to_rad(-_current_steer * (max_steering_wheel_angle_deg * 0.5))

	# 2. Педали (газ, тормоз, сцепление) и ручник
	var throttle_val: float = float(snap["throttle"])
	var brake_val: float = float(snap["brake"])
	var clutch_val: float = float(snap["clutch"])
	var handbrake_val: float = float(snap["handbrake"])
	var p_weight: float = clampf(delta * pedal_smooth_speed, 0.0, 1.0) if delta > 0.0 else 1.0
	var hb_weight: float = clampf(delta * handbrake_smooth_speed, 0.0, 1.0) if delta > 0.0 else 1.0

	if pedal_gas != null:
		pedal_gas.rotation.x = lerpf(pedal_gas.rotation.x, deg_to_rad(throttle_val * gas_max_deg), p_weight)
	if pedal_brake != null:
		pedal_brake.rotation.x = lerpf(pedal_brake.rotation.x, deg_to_rad(brake_val * brake_max_deg), p_weight)
	if pedal_clutch != null:
		pedal_clutch.rotation.x = lerpf(pedal_clutch.rotation.x, deg_to_rad(clutch_val * clutch_max_deg), p_weight)
	if handbrake_pivot != null:
		handbrake_pivot.rotation.x = lerpf(handbrake_pivot.rotation.x, deg_to_rad(-handbrake_val * handbrake_max_deg), hb_weight)

	# 3. Рычаг КПП и передача
	var gear_str: String = str(snap["gear"])
	if gear_str != _last_gear:
		_last_gear = gear_str
		_shifter_kick = 1.0
	_shifter_kick = move_toward(_shifter_kick, 0.0, maxf(delta, 0.0) * shifter_return_speed)
	if shifter_pivot != null:
		shifter_pivot.rotation.x = deg_to_rad(-_shifter_kick * shifter_kick_deg)

	# 4. Дисплей MoTeC
	var redline_on: bool = bool(snap["is_redline"])
	var stalled: bool = bool(snap["stalled"])
	var rpm_val: float = float(snap["rpm"])
	var max_r: float = float(snap["max_rpm"])
	var active_redline_ratio: float = float(snap["redline_ratio"])

	if gear_label != null:
		gear_label.text = gear_str
		gear_label.modulate = gear_redline_color if (redline_on or stalled) else gear_normal_color
	if speed_label != null:
		speed_label.text = str(snap["speed_text"])
		speed_label.modulate = speed_color
	if rpm_label != null:
		rpm_label.text = str(snap["rpm_text"])
		rpm_label.modulate = rpm_redline_color if redline_on else rpm_normal_color
	if mode_label != null:
		mode_label.visible = show_setup_mode_in_motec
		mode_label.text = str(snap["mode_text"])
		mode_label.modulate = stalled_color if stalled else mode_info_color
	if limit_label != null:
		limit_label.visible = show_setup_mode_in_motec
		limit_label.text = str(snap["limit_text"])
		limit_label.modulate = rpm_redline_color if redline_on else rpm_normal_color

	# 5. Shift-lights по реальному max_rpm и красной зоне сетапа
	if shift_lights != null:
		var start_rpm: float = max_r * shift_light_start_ratio
		var end_rpm: float = maxf(start_rpm + 100.0, max_r * shift_light_end_ratio)
		var ratio: float = clampf(inverse_lerp(start_rpm, end_rpm, rpm_val), 0.0, 1.0)
		var led_count: int = shift_lights.get_child_count()
		var flash_on: bool = true
		if redline_on or rpm_val >= max_r * active_redline_ratio:
			flash_on = int(floor(_blink_clock * 14.0)) % 2 == 0
		for i in range(led_count):
			var led := shift_lights.get_child(i) as MeshInstance3D
			if led != null:
				if redline_on:
					led.visible = flash_on
				else:
					var threshold: float = float(i + 1) / float(maxi(1, led_count))
					led.visible = ratio >= threshold

	# 6. Трипмастер штурмана
	if tripmaster_label != null and sync_tripmaster_with_stage:
		tripmaster_label.text = str(snap["tripmaster_text"])
		tripmaster_label.modulate = tripmaster_color
		tripmaster_label.pixel_size = 0.00088
		tripmaster_label.font_size = 18


func compute_telemetry_snapshot() -> Dictionary:
	var mph_active: bool = use_mph
	var scale_val: float = speed_scale
	var red_ratio: float = redline_ratio
	var red_rpm_override: float = 0.0

	if sync_units_with_hud and _speedometer != null and is_instance_valid(_speedometer):
		if "speed_units" in _speedometer:
			mph_active = int(_speedometer.get("speed_units")) == 1
		if "speed_scale" in _speedometer:
			scale_val = maxf(0.1, float(_speedometer.get("speed_scale")))
		if "redline_ratio" in _speedometer:
			red_ratio = clampf(float(_speedometer.get("redline_ratio")), 0.5, 0.99)
		if "redline_rpm" in _speedometer:
			red_rpm_override = maxf(0.0, float(_speedometer.get("redline_rpm")))

	var raw_speed_kmh: float = 0.0
	var rpm_val: float = 900.0
	var max_r: float = 7600.0
	var redline_on: bool = false
	var stalled: bool = false
	var gear_str: String = "N"
	var steer_val: float = 0.0
	var throttle_val: float = 0.0
	var brake_val: float = 0.0
	var clutch_val: float = 0.0
	var handbrake_val: float = 0.0
	var trans_short: String = ""
	var drive_short: String = ""
	var setup_name: String = ""

	if _car != null and is_instance_valid(_car):
		if "speed_kmh" in _car:
			raw_speed_kmh = maxf(0.0, float(_car.get("speed_kmh")))
		elif _car is RigidBody3D:
			raw_speed_kmh = (_car as RigidBody3D).linear_velocity.length() * 3.6

		if "current_rpm" in _car:
			rpm_val = maxf(0.0, float(_car.get("current_rpm")))
		elif "motor_rpm" in _car:
			rpm_val = maxf(0.0, float(_car.get("motor_rpm")))

		if "max_rpm" in _car:
			max_r = maxf(1000.0, float(_car.get("max_rpm")))

		if "engine_stalled" in _car:
			stalled = bool(_car.get("engine_stalled"))

		if "motor_is_redline" in _car:
			redline_on = bool(_car.get("motor_is_redline"))
		if not redline_on:
			if red_rpm_override > 0.0:
				redline_on = rpm_val >= red_rpm_override
			else:
				redline_on = (rpm_val / max_r) >= red_ratio

		if _car.has_method("get_gear_label"):
			gear_str = str(_car.call("get_gear_label"))
		elif "current_gear" in _car:
			var g_raw: int = int(_car.get("current_gear"))
			if g_raw == -1:
				gear_str = "R"
			elif g_raw == 0:
				gear_str = "N"
			else:
				gear_str = str(g_raw)

		if "steering_amount" in _car:
			steer_val = clampf(float(_car.get("steering_amount")), -1.0, 1.0)
		elif "steer_input" in _car:
			steer_val = clampf(float(_car.get("steer_input")), -1.0, 1.0)
		elif "steering_input" in _car:
			steer_val = clampf(float(_car.get("steering_input")), -1.0, 1.0)

		if "throttle_amount" in _car:
			throttle_val = clampf(float(_car.get("throttle_amount")), 0.0, 1.0)
		elif "throttle_input" in _car:
			throttle_val = clampf(float(_car.get("throttle_input")), 0.0, 1.0)

		if "brake_amount" in _car:
			brake_val = clampf(float(_car.get("brake_amount")), 0.0, 1.0)
		elif "brake_input" in _car:
			brake_val = clampf(float(_car.get("brake_input")), 0.0, 1.0)

		if "clutch_amount" in _car:
			clutch_val = clampf(float(_car.get("clutch_amount")), 0.0, 1.0)
		elif "clutch_input" in _car:
			clutch_val = clampf(float(_car.get("clutch_input")), 0.0, 1.0)

		if "handbrake_input" in _car:
			handbrake_val = clampf(float(_car.get("handbrake_input")), 0.0, 1.0)

		if _car.has_method("get_transmission_label"):
			trans_short = str(_car.call("get_transmission_label")).replace(" + ", "+")
		if _car.has_method("get_drivetrain_label"):
			drive_short = str(_car.call("get_drivetrain_label")).split(" ")[0]
		if "active_setup" in _car:
			var active_s: Variant = _car.get("active_setup")
			if active_s is Resource and "display_name" in active_s:
				setup_name = str(active_s.get("display_name"))
	else:
		if InputMap.has_action("steer_left") and InputMap.has_action("steer_right"):
			steer_val = Input.get_axis("steer_right", "steer_left")
		elif InputMap.has_action("ui_left") and InputMap.has_action("ui_right"):
			steer_val = Input.get_axis("ui_right", "ui_left")
		if InputMap.has_action("throttle"):
			throttle_val = Input.get_action_strength("throttle")
		elif InputMap.has_action("ui_up"):
			throttle_val = Input.get_action_strength("ui_up")
		if InputMap.has_action("brake"):
			brake_val = Input.get_action_strength("brake")
		elif InputMap.has_action("ui_down"):
			brake_val = Input.get_action_strength("ui_down")
		if InputMap.has_action("clutch"):
			clutch_val = Input.get_action_strength("clutch")
		if InputMap.has_action("handbrake"):
			handbrake_val = Input.get_action_strength("handbrake")
		elif InputMap.has_action("ui_accept"):
			handbrake_val = Input.get_action_strength("ui_accept")

	var converted_speed: float = raw_speed_kmh * scale_val
	var unit_suffix: String = "KM/H"
	if mph_active:
		converted_speed *= KMH_TO_MPH
		unit_suffix = "MPH"
	var display_speed: int = int(round(maxf(0.0, converted_speed)))
	var speed_text: String = "%03d %s" % [display_speed, unit_suffix]
	var rpm_text: String = "%04d RPM" % roundi(rpm_val)

	var mode_text: String = ""
	if stalled:
		mode_text = "ЗАГЛОХ!"
	elif not trans_short.is_empty() and not drive_short.is_empty():
		mode_text = "%s • %s" % [trans_short, drive_short]
	elif not trans_short.is_empty():
		mode_text = trans_short
	elif not drive_short.is_empty():
		mode_text = drive_short

	var limit_text: String = "REDLINE!" if redline_on else ("MAX %d" % roundi(max_r))
	var tripmaster_text: String = _build_tripmaster_text(setup_name, max_r)

	return {
		"speed_display": display_speed,
		"speed_text": speed_text,
		"rpm": rpm_val,
		"rpm_text": rpm_text,
		"max_rpm": max_r,
		"redline_ratio": red_ratio,
		"is_redline": redline_on,
		"stalled": stalled,
		"gear": gear_str,
		"steer": steer_val,
		"throttle": throttle_val,
		"brake": brake_val,
		"clutch": clutch_val,
		"handbrake": handbrake_val,
		"mode_text": mode_text,
		"limit_text": limit_text,
		"setup_name": setup_name,
		"tripmaster_text": tripmaster_text,
	}


func _build_tripmaster_text(setup_name: String, max_r: float) -> String:
	var stage_title: String = "STAGE 01"
	var elapsed_sec: float = 0.0
	var finished_flag: bool = false
	var along_km: float = 0.0
	var total_km: float = 0.0

	if _stage != null and is_instance_valid(_stage):
		if "stage_time" in _stage:
			elapsed_sec = maxf(0.0, float(_stage.get("stage_time")))
		if "stage_finished" in _stage:
			finished_flag = bool(_stage.get("stage_finished"))
		var track_var: Variant = _stage.get("track") if "track" in _stage else null
		if track_var is Resource and "display_name" in track_var:
			var t_name: String = str(track_var.get("display_name"))
			if not t_name.is_empty():
				stage_title = t_name
		var net_var: Variant = _stage.get("network") if "network" in _stage else null
		if net_var != null:
			if "total_length" in net_var:
				total_km = maxf(0.0, float(net_var.get("total_length")) / 1000.0)
			if _car is Node3D and _stage is Node3D and net_var.has_method("along_road"):
				var local_p: Vector3 = (_stage as Node3D).to_local((_car as Node3D).global_position)
				along_km = clampf(float(net_var.call("along_road", local_p.x, local_p.z)) / 1000.0, 0.0, maxf(total_km, 0.0))

	var mins: int = floori(elapsed_sec / 60.0)
	var secs: float = fmod(elapsed_sec, 60.0)
	var time_str: String = "%s%02d:%05.2f" % ["FIN " if finished_flag else "", mins, secs]
	var dist_str: String = ("%.2f/%.2f KM" % [along_km, total_km]) if total_km > 0.0 else ("%.2f KM" % along_km)
	var line1: String = _short_text(stage_title, 18)
	var line2: String = "%s • %s" % [time_str, dist_str]
	if setup_name.is_empty():
		return "%s\n%s" % [line1, line2]
	var line3: String = "%s • %d" % [_short_text(setup_name, 14), roundi(max_r)]
	return "%s\n%s\n%s" % [line1, line2, line3]


func _short_text(src: String, limit: int) -> String:
	if src.length() <= limit:
		return src
	return src.substr(0, maxi(1, limit - 1)) + "…"
