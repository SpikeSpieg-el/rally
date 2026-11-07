## Перечень пролётов — дочерние узлы Shot в порядке дерева сцены.
extends Node3D

const Driver = preload("res://scripts/menu/menu_driver.gd")

@export_range(0.0, 4.0, 0.1, "suffix:s") var blend_time := 1.5
@export var follow_during_recording := true
@export var recording_camera_offset := Vector3(0, 5, -11)
## При полёте над холмами камера не уходит под землю; отключается в инспекторе.
@export var keep_above_terrain := true
@export_range(0.1, 10.0, 0.1, "suffix:m") var terrain_clearance := 2.0
@onready var car: Node3D = get_node("../RallyCar")
@onready var driver = get_node("../Driver")
@onready var camera: Camera3D = $Camera3D
@onready var shots: Node = $Shots
var _shot_index := 0
var _shot_time := 0.0
var _previous_position := Vector3.ZERO
var _previous_target := Vector3.ZERO
var _last_target := Vector3.ZERO
var _blend_elapsed := 0.0


func _ready() -> void:
	camera.make_current()
	if shots.get_child_count() > 0:
		var shot = shots.get_child(0)
		camera.global_position = _above_ground(shot.camera_position(0.0, car))
		_last_target = _framed_target(shot, camera.global_position)
		camera.look_at(_last_target, Vector3.UP)
		camera.fov = shot.fov


func _process(delta: float) -> void:
	if follow_during_recording and driver.mode == Driver.Mode.RECORD:
		var offset := car.global_transform.basis.orthonormalized() * recording_camera_offset
		camera.global_position = _above_ground(camera.global_position.lerp(car.global_position + offset, 1.0 - exp(-4.0 * delta)))
		_last_target = car.global_position + Vector3.UP
		camera.look_at(_last_target, Vector3.UP)
		return
	if shots.get_child_count() == 0:
		return
	var shot = shots.get_child(_shot_index)
	_shot_time += delta
	if _shot_time >= maxf(shot.duration, 0.1):
		_shot_time = 0.0
		_previous_position = camera.global_position
		_previous_target = _last_target
		_blend_elapsed = 0.0
		_shot_index = (_shot_index + 1) % shots.get_child_count()
		shot = shots.get_child(_shot_index)
	var t: float = clampf(_shot_time / maxf(shot.duration, 0.1), 0.0, 1.0)
	var camera_pos: Vector3 = shot.camera_position(t, car)
	var target: Vector3 = _framed_target(shot, camera_pos)
	if _shot_time < blend_time and blend_time > 0.0 and _previous_target != Vector3.ZERO:
		_blend_elapsed += delta
		var weight := smoothstep(0.0, 1.0, clampf(_blend_elapsed / blend_time, 0.0, 1.0))
		camera_pos = _previous_position.lerp(camera_pos, weight)
		target = _previous_target.lerp(target, weight)
	camera.global_position = _above_ground(camera_pos)
	_last_target = target
	if camera.global_position.distance_squared_to(target) > 0.01:
		camera.look_at(target, Vector3.UP)
	camera.fov = lerpf(camera.fov, float(shot.fov), 1.0 - exp(-3.0 * delta))


func _framed_target(shot, camera_pos: Vector3) -> Vector3:
	var aim: Vector3 = shot.target_position(car)
	var direction := (aim - camera_pos).normalized()
	var right := direction.cross(Vector3.UP).normalized()
	return aim - right * float(shot.framing_offset)


func _above_ground(world_position: Vector3) -> Vector3:
	if not keep_above_terrain:
		return world_position
	var terrain = get_node_or_null("../Ground")
	if terrain == null or not terrain.has_method("ground_height"):
		return world_position
	var local: Vector3 = terrain.to_local(world_position)
	var ground_y: float = terrain.ground_height(local.x, local.z)
	var ground_world: Vector3 = terrain.to_global(Vector3(local.x, ground_y, local.z))
	world_position.y = maxf(world_position.y, ground_world.y + terrain_clearance)
	return world_position
