## Один болельщик у дороги: билборд, хитбокс и «раздавливание» при наезде.
##
## Сцена `spectator_person.tscn` — и одиночки на бровке, и люди в лагере.
## Этот скрипт только оживляет спрайт:
##   * случайная куртка;
##   * слишком храбрые фанаты делают шаг на полотно, когда машина близко;
##   * при ударе — плашмя на грунт, всплеск крови и пятно на кузове.
class_name RallySpectatorPerson
extends Node3D

const JACKETS: Array[String] = [
	"res://textures/sprites/spectator_red.png",
	"res://textures/sprites/spectator_yellow.png",
	"res://textures/sprites/spectator_blue.png",
	"res://textures/sprites/spectator_green.png",
	"res://textures/sprites/spectator_orange.png",
	"res://textures/sprites/spectator_white.png",
]
const BloodFx = preload("res://scripts/effects/rally_blood_fx.gd")
const HIT_HALF_WIDTH := 1.08
const HIT_HALF_LENGTH := 2.30
const HIT_MIN_SPEED := 4.0

var _stage: Node = null
var _eager: bool = false
var _road_toward: Vector3 = Vector3.ZERO
var _home: Vector3 = Vector3.ZERO
var _crushed: bool = false
var _phase: float = 0.0
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()
var _sprite: Sprite3D = null
var _hitbox: Area3D = null


func _ready() -> void:
	_sprite = get_node_or_null("Sprite") as Sprite3D
	_hitbox = get_node_or_null("Hitbox") as Area3D
	if _hitbox != null and not _hitbox.body_entered.is_connected(_on_body_entered):
		_hitbox.body_entered.connect(_on_body_entered)
	if _home == Vector3.ZERO:
		_home = position
	_rng.seed = int(Time.get_ticks_usec()) ^ int(get_instance_id())
	_phase = _rng.randf() * TAU
	set_physics_process(true)


## stage — RallyStage (для поиска машины), eager — шаг на полотно навстречу,
## toward_road — горизонталь к оси трассы в мире.
func setup(stage: Node, eager: bool = false, toward_road: Vector3 = Vector3.ZERO) -> void:
	_stage = stage
	_eager = eager
	_road_toward = toward_road
	_road_toward.y = 0.0
	if _road_toward.length() > 0.001:
		_road_toward = _road_toward.normalized()
	_home = position
	_rng.seed = int(Time.get_ticks_usec()) ^ int(get_instance_id()) ^ 17
	_randomize_jacket()
	set_physics_process(true)


func is_crushed() -> bool:
	return _crushed


func _randomize_jacket() -> void:
	if _sprite == null:
		_sprite = get_node_or_null("Sprite") as Sprite3D
	if _sprite == null or JACKETS.is_empty():
		return
	var path: String = JACKETS[_rng.randi_range(0, JACKETS.size() - 1)]
	var texture := load(path) as Texture2D
	if texture != null:
		_sprite.texture = texture


func _physics_process(delta: float) -> void:
	if _crushed or not visible:
		return
	_time += delta
	var car := _find_car()
	if car == null:
		return
	_cheer(car, delta)
	if _eager:
		_step_toward_road(car)
	_try_hit(car)


func _cheer(car: Node3D, _delta: float) -> void:
	if _sprite == null:
		return
	var offset: Vector3 = car.global_position - global_position
	offset.y = 0.0
	var near: float = clampf(1.0 - offset.length() / 40.0, 0.0, 1.0)
	var wave: float = sin(_time * (5.5 + near * 7.0) + _phase)
	_sprite.pixel_size = 0.045 * (1.0 + wave * (0.04 + near * 0.05))


func _step_toward_road(car: Node3D) -> void:
	if _road_toward.length() < 0.01:
		return
	var offset: Vector3 = car.global_position - global_position
	offset.y = 0.0
	var reach: float = clampf(1.0 - offset.length() / 32.0, 0.0, 1.0)
	# Храбрые болельщики выходят на бровку навстречу машине.
	var world_home: Vector3 = global_position - (position - _home)
	if get_parent() is Node3D:
		world_home = (get_parent() as Node3D).to_global(_home)
	global_position = world_home + _road_toward * reach * 0.85


func _try_hit(car: Node3D) -> void:
	var speed: float = _car_speed(car)
	if speed < HIT_MIN_SPEED:
		return
	var local_hit: Vector3 = car.to_local(global_position + Vector3(0.0, 0.7, 0.0))
	if absf(local_hit.x) > HIT_HALF_WIDTH:
		return
	if absf(local_hit.z) > HIT_HALF_LENGTH:
		return
	if local_hit.y < -0.2 or local_hit.y > 1.45:
		return
	crush(car)


func _on_body_entered(body: Node) -> void:
	if _crushed or not visible:
		return
	if body is Node3D:
		var as_node := body as Node3D
		if _car_speed(as_node) >= HIT_MIN_SPEED:
			crush(as_node)


func crush(car: Node3D) -> void:
	if _crushed:
		return
	_crushed = true
	set_physics_process(false)
	if _hitbox != null:
		_hitbox.monitoring = false
		_hitbox.monitorable = false
	_flatten()
	var impact: Vector3 = global_position + Vector3(0.0, 0.72, 0.0)
	var velocity: Vector3 = _car_velocity(car)
	BloodFx.spray(self, impact, velocity)
	if car != null and car.has_method("splatter_blood"):
		car.call("splatter_blood", impact, velocity)
	_nudge_car(car, velocity)


func _flatten() -> void:
	if _sprite == null:
		return
	_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_sprite.pixel_size = 0.052
	_sprite.position = Vector3(0.0, 0.035, 0.0)
	_sprite.rotation_degrees = Vector3(-90.0, _rng.randf_range(-55.0, 55.0), 0.0)
	_sprite.modulate = Color(0.32, 0.04, 0.05, 0.92)
	var smear := Sprite3D.new()
	smear.name = "BloodSmear"
	smear.texture = _sprite.texture
	smear.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	smear.pixel_size = 0.07
	smear.modulate = Color(0.28, 0.02, 0.03, 0.72)
	smear.position = Vector3(_rng.randf_range(-0.15, 0.15), 0.02, _rng.randf_range(-0.12, 0.12))
	smear.rotation_degrees = Vector3(-90.0, _rng.randf_range(-80.0, 80.0), 0.0)
	add_child(smear)


func _nudge_car(car: Node3D, velocity: Vector3) -> void:
	if car == null or not car is RigidBody3D:
		return
	var body := car as RigidBody3D
	var push: Vector3 = body.global_position - global_position
	push.y = 0.0
	if push.length() < 0.01:
		push = -velocity
	push.y = 0.0
	if push.length() < 0.01:
		return
	body.apply_central_impulse(push.normalized() * 420.0)
	body.linear_velocity = body.linear_velocity * 0.97


func _find_car() -> Node3D:
	if _stage != null and is_instance_valid(_stage):
		var candidate: Variant = _stage.get("car")
		if candidate is Node3D:
			return candidate as Node3D
	return null


func _car_speed(car: Node) -> float:
	if car == null:
		return 0.0
	var value: Variant = car.get("linear_velocity")
	if value is Vector3:
		return (value as Vector3).length()
	value = car.get("speed_mps")
	if value is float or value is int:
		return float(value)
	return 0.0


func _car_velocity(car: Node) -> Vector3:
	if car == null:
		return Vector3.ZERO
	var value: Variant = car.get("linear_velocity")
	if value is Vector3:
		return value as Vector3
	return Vector3.ZERO
