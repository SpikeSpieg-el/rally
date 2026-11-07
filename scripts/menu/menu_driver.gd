## Запись/воспроизведение входа настоящей RallyCar; без перемещения по кривой.
extends Node

const Recording = preload("res://scripts/menu/menu_recording.gd")

enum Mode { AUTO, PLAYBACK, RECORD }
@export var mode: Mode = Mode.PLAYBACK
## Готовая запись в проекте. Если её нет, читается запись из user://.
@export var recording: Recording
@export_file("*.tres", "*.res") var recording_path := "user://menu_drive.tres"
## Включайте только если пользовательская запись сделана для текущей трассы.
@export var allow_user_recording_fallback := true
@export_range(1.0, 180.0, 1.0, "suffix:s") var max_record_seconds := 180.0
@export_range(0.0, 3.0, 0.1, "suffix:s") var replay_fade_seconds := 0.6
@export_group("Автопилот (если записи нет)")
@export_range(5.0, 80.0, 1.0, "suffix:km/h") var target_speed := 30.0
@export_range(3.0, 40.0, 0.5, "suffix:m") var lookahead := 12.0
@export_range(0.1, 8.0, 0.1) var steering_gain := 2.3
@export_range(0.0, 1.0, 0.05) var max_throttle := 0.65
@export_range(1.0, 100.0, 1.0, "suffix:m") var reset_distance := 35.0

@onready var car = get_node("../RallyCar")
@onready var route: Path3D = get_node("../Track") as Path3D
var throttle := 0.0
var brake := 0.0
var steering := 0.0
var handbrake := 0.0
var _time := 0.0
var _frames := PackedFloat32Array()
var _is_recording := false
var _source: Recording
var _last_frame := -1
var replay_fade := 1.0


func _ready() -> void:
	# Эта нода должна подавать вход до шага физики RallyCar.
	process_physics_priority = -100
	if recording != null and recording.valid():
		_source = recording
	elif allow_user_recording_fallback and not recording_path.is_empty() and ResourceLoader.exists(recording_path):
		var loaded := ResourceLoader.load(recording_path) as Recording
		if loaded != null and loaded.valid():
			_source = loaded
	if mode == Mode.PLAYBACK:
		if _source == null:
			print("MenuDriver: записи нет, используется физический автопилот. Запишите заезд в режиме RECORD (F9).")
		else:
			# Запись начинается из того же сброшенного состояния, что и F9.
			car.reset_to_spawn()


func _unhandled_key_input(event: InputEvent) -> void:
	if mode == Mode.RECORD and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F7:
		if _is_recording:
			finish_recording()
		else:
			begin_recording()
		get_viewport().set_input_as_handled()


func begin_recording() -> void:
	_frames.clear()
	_time = 0.0
	car.reset_to_spawn()
	_is_recording = true
	print("MenuDriver: запись начата. F9 — сохранить.")


func finish_recording() -> void:
	_is_recording = false
	if _frames.is_empty():
		return
	var result := Recording.new()
	result.physics_fps = Engine.physics_ticks_per_second
	result.frames = _frames.duplicate()
	var error := ResourceSaver.save(result, recording_path)
	if error == OK:
		_source = result
		print("MenuDriver: запись сохранена: ", ProjectSettings.globalize_path(recording_path))
	else:
		push_error("MenuDriver: не удалось сохранить запись (%s): %s" % [error, recording_path])


func _physics_process(delta: float) -> void:
	if mode != Mode.PLAYBACK or _source == null:
		replay_fade = 1.0
	if mode == Mode.RECORD:
		_read_player()
	elif mode == Mode.PLAYBACK and _source != null:
		_play(delta)
	else:
		_auto_drive()
	# Авторинг может записывать как действия игрока, так и физический
	# автопилот. В режиме проигрывания запись не перезаписывается.
	if _is_recording and mode != Mode.PLAYBACK:
		_frames.append_array(PackedFloat32Array([throttle, brake, steering, handbrake]))
		_time += delta
		if _time >= max_record_seconds:
			finish_recording()


func _read_player() -> void:
	var manager := get_node_or_null("/root/ControllerManager")
	if manager != null:
		throttle = float(manager.call("get_throttle_input"))
		brake = float(manager.call("get_brake_input"))
		steering = float(manager.call("get_steering_input"))
		handbrake = float(manager.call("get_handbrake_input"))
	else:
		throttle = Input.get_action_strength("throttle")
		brake = Input.get_action_strength("brake")
		steering = Input.get_axis("steer_right", "steer_left")
		handbrake = Input.get_action_strength("handbrake")


func _play(delta: float) -> void:
	var count := _source.frame_count()
	# Сумма шагов delta не всегда представима точно: без эпсилон-коррекции
	# индекс иногда повторял кадр и сбивал физическое воспроизведение.
	var frame := int(_time * float(_source.physics_fps) + 0.0001)
	if frame >= count:
		_time = 0.0
		frame = 0
		car.reset_to_spawn()
	_last_frame = frame
	var duration := float(count) / float(_source.physics_fps)
	if replay_fade_seconds > 0.0:
		replay_fade = minf(smoothstep(0.0, replay_fade_seconds, _time), smoothstep(0.0, replay_fade_seconds, duration - _time))
	else:
		replay_fade = 1.0
	var index := frame * 4
	throttle = _source.frames[index]
	brake = _source.frames[index + 1]
	steering = _source.frames[index + 2]
	handbrake = _source.frames[index + 3]
	_time += delta


func _auto_drive() -> void:
	var curve := route.curve
	if curve == null or curve.get_baked_length() <= 1.0:
		throttle = 0.0
		brake = 1.0
		return
	var local_position := route.to_local(car.global_position)
	var closest := curve.get_closest_offset(local_position)
	var near := curve.sample_baked(closest, true)
	if local_position.distance_to(near) > reset_distance or car.global_position.y < -10.0:
		car.reset_to_spawn()
		return
	var distance := fposmod(closest + lookahead, curve.get_baked_length())
	var target: Vector3 = car.to_local(route.to_global(curve.sample_baked(distance, true)))
	steering = clampf(target.x / maxf(lookahead, 1.0) * steering_gain, -1.0, 1.0)
	throttle = clampf((target_speed - car.speed_kmh) * 0.08, 0.0, max_throttle)
	brake = clampf((car.speed_kmh - target_speed - 3.0) * 0.07, 0.0, 0.6)
	handbrake = 0.0


func get_throttle_input() -> float: return throttle
func get_brake_input() -> float: return brake
func get_steering_input() -> float: return steering
func get_handbrake_input() -> float: return handbrake
func get_clutch_input() -> float: return 0.0
