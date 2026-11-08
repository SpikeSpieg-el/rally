## Один болельщик у дороги. Сцена `spectator_person.tscn` — пульт внешности,
## удара и крови: откройте её в Godot и правьте спрайт, хитбокс и поля ниже.
@tool
class_name RallySpectatorPerson
extends Node3D

const BloodFx = preload("res://scripts/effects/rally_blood_fx.gd")
const PuddleShader = preload("res://shaders/blood_puddle.gdshader")
const DEFAULT_JACKETS: Array[String] = [
	"res://textures/sprites/spectator_red.png",
	"res://textures/sprites/spectator_yellow.png",
	"res://textures/sprites/spectator_blue.png",
	"res://textures/sprites/spectator_green.png",
	"res://textures/sprites/spectator_orange.png",
	"res://textures/sprites/spectator_white.png",
]

@export_group("Внешность")
## Куртки для случайного выбора. Пусто — стандартный набор PNG в textures/sprites.
@export var jacket_textures: Array[Texture2D] = []
@export var randomize_jacket: bool = true
@export_range(0.01, 0.2, 0.001) var pixel_size_idle: float = 0.045
@export_range(8.0, 80.0, 1.0, "suffix:м") var cheer_range: float = 40.0
@export_range(0.0, 0.2, 0.005) var cheer_wave: float = 0.04
@export_range(0.0, 16.0, 0.1) var cheer_speed: float = 5.5

@export_group("Шаг на полотно")
## Если включено в сцене — человек всегда выходит навстречу. На трассе это
## ещё выставляет планировщик для «храбрых» точек.
@export var start_eager: bool = false
@export_range(0.0, 3.0, 0.05, "suffix:м") var step_in_meters: float = 0.85
@export_range(4.0, 80.0, 1.0, "suffix:м") var step_in_range: float = 32.0

@export_group("Удар")
@export_range(0.2, 3.0, 0.01, "suffix:м") var hit_half_width: float = 1.08
@export_range(0.5, 5.0, 0.01, "suffix:м") var hit_half_length: float = 2.30
@export_range(0.0, 30.0, 0.1, "suffix:м/с") var hit_min_speed: float = 4.0
@export var hit_height: Vector2 = Vector2(-0.2, 1.45)
@export_range(0.0, 2.0, 0.01, "suffix:м") var impact_height: float = 0.72

@export_group("После удара")
@export var blood_burst: PackedScene
## Сместить тело на полотно, м (к оси дороги). Иначе труп остаётся в траве.
@export_range(0.0, 6.0, 0.05, "suffix:м") var drag_onto_road: float = 2.6
## Протащить вдоль хода машины, м.
@export_range(0.0, 8.0, 0.05, "suffix:м") var drag_along_car: float = 1.8
## Размер лежащего спрайта: ~рост человека (40 px × pixel_size_idle).
@export_range(0.01, 0.25, 0.001) var flatten_pixel_size: float = 0.05
@export var flatten_color: Color = Color(0.32, 0.04, 0.05, 0.92)
@export_range(0.0, 180.0, 1.0, "suffix:°") var flatten_yaw_range: float = 55.0
## След-потёк чуть длиннее тела, но не в разы.
@export_range(0.01, 0.3, 0.001) var smear_pixel_size: float = 0.065
@export var smear_color: Color = Color(0.28, 0.02, 0.03, 0.78)
## Размер кровавой лужи на полотне, м (длина × ширина).
@export var puddle_extent: Vector2 = Vector2(1.5, 0.95)
@export var puddle_color: Color = Color(0.38, 0.02, 0.04, 0.82)
@export_range(0.0, 0.2, 0.005, "suffix:м") var ground_lift: float = 0.06
@export_range(0.0, 2000.0, 10.0) var nudge_impulse: float = 420.0
@export_range(0.5, 1.0, 0.01) var speed_keep: float = 0.97

var _stage: Node = null
var _cached_car: Node3D = null
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
	if start_eager:
		_eager = true
	if not Engine.is_editor_hint() and randomize_jacket:
		_randomize_jacket()
	set_physics_process(not Engine.is_editor_hint())


## stage — RallyStage (для поиска машины), eager — шаг на полотно навстречу,
## toward_road — горизонталь к оси трассы в мире.
func setup(stage: Node, eager: bool = false, toward_road: Vector3 = Vector3.ZERO) -> void:
	_stage = stage
	_eager = eager or start_eager
	_road_toward = toward_road
	_road_toward.y = 0.0
	if _road_toward.length() > 0.001:
		_road_toward = _road_toward.normalized()
	_home = position
	_rng.seed = int(Time.get_ticks_usec()) ^ int(get_instance_id()) ^ 17
	if randomize_jacket:
		_randomize_jacket()
	set_physics_process(not Engine.is_editor_hint())


func is_crushed() -> bool:
	return _crushed


func _randomize_jacket() -> void:
	if _sprite == null:
		_sprite = get_node_or_null("Sprite") as Sprite3D
	if _sprite == null:
		return
	var textures: Array[Texture2D] = []
	for texture in jacket_textures:
		if texture != null:
			textures.append(texture)
	if textures.is_empty():
		for path in DEFAULT_JACKETS:
			var loaded := load(path) as Texture2D
			if loaded != null:
				textures.append(loaded)
	if textures.is_empty():
		return
	_sprite.texture = textures[_rng.randi_range(0, textures.size() - 1)]


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _crushed or not visible:
		return
	_time += delta
	var car := _find_car()
	if car == null:
		return
	_cheer(car)
	if _eager:
		_step_toward_road(car)
	_try_hit(car)


func _cheer(car: Node3D) -> void:
	if _sprite == null:
		return
	var offset: Vector3 = car.global_position - global_position
	offset.y = 0.0
	var closeness: float = clampf(1.0 - offset.length() / maxf(cheer_range, 0.1), 0.0, 1.0)
	var wave: float = sin(_time * (cheer_speed + closeness * 7.0) + _phase)
	_sprite.pixel_size = pixel_size_idle * (1.0 + wave * (cheer_wave + closeness * 0.05))


func _step_toward_road(car: Node3D) -> void:
	if _road_toward.length() < 0.01:
		return
	var offset: Vector3 = car.global_position - global_position
	offset.y = 0.0
	var reach: float = clampf(1.0 - offset.length() / maxf(step_in_range, 0.1), 0.0, 1.0)
	var parent_node: Node3D = get_parent() as Node3D
	var world_home: Vector3 = global_position
	if parent_node != null:
		world_home = parent_node.to_global(_home)
	global_position = world_home + _road_toward * reach * step_in_meters


func _try_hit(car: Node3D) -> void:
	var speed: float = _car_speed(car)
	if speed < hit_min_speed:
		return
	var local_hit: Vector3 = car.to_local(global_position + Vector3(0.0, 0.7, 0.0))
	if absf(local_hit.x) > hit_half_width:
		return
	if absf(local_hit.z) > hit_half_length:
		return
	if local_hit.y < hit_height.x or local_hit.y > hit_height.y:
		return
	crush(car)


func _on_body_entered(body: Node) -> void:
	if _crushed or not visible:
		return
	var car := _resolve_car_from_body(body)
	if car != null and _car_speed(car) >= hit_min_speed:
		crush(car)


func _resolve_car_from_body(body: Node) -> Node3D:
	var cur: Node = body
	while cur != null:
		if cur is Node3D and (_car_speed(cur) > 0.0 or cur.has_method("splatter_blood") or cur.has_node("BloodFx")):
			return cur as Node3D
		cur = cur.get_parent()
	return body as Node3D


func crush(car: Node3D) -> void:
	if _crushed:
		return
	_crushed = true
	set_physics_process(false)
	_disable_hitbox()

	var pre_throw_pos: Vector3 = global_position
	var velocity: Vector3 = _car_velocity(car)
	var hit_world: Vector3 = _impact_point_on_car(car, pre_throw_pos)
	var burst_world: Vector3 = _burst_origin(car, pre_throw_pos)

	_throw_onto_road(velocity)
	_flatten(velocity)

	var spray_host: Node = car if car != null and is_instance_valid(car) else self
	BloodFx.spray(spray_host, burst_world, velocity, blood_burst)
	_apply_car_blood(car, hit_world, velocity)
	_nudge_car.call_deferred(car, velocity, pre_throw_pos)


func _apply_car_blood(car: Node3D, hit_world: Vector3, velocity: Vector3) -> void:
	if car == null or not is_instance_valid(car):
		return
	if car.has_method("splatter_blood"):
		car.call("splatter_blood", hit_world, velocity)
		return
	var fx := car.get_node_or_null("BloodFx")
	if fx == null:
		fx = car.find_child("BloodFx", true, false)
	if fx != null and fx.has_method("add_splat"):
		fx.call("add_splat", car, hit_world, velocity)


func _disable_hitbox() -> void:
	if _hitbox == null:
		return
	if _hitbox.body_entered.is_connected(_on_body_entered):
		_hitbox.body_entered.disconnect(_on_body_entered)
	_hitbox.set_deferred("monitoring", false)
	_hitbox.set_deferred("monitorable", false)


func _throw_onto_road(velocity: Vector3) -> void:
	var shift := Vector3.ZERO
	if _road_toward.length() > 0.01:
		shift += _road_toward * drag_onto_road
	var along: Vector3 = velocity
	along.y = 0.0
	if along.length() > 0.4:
		shift += along.normalized() * drag_along_car
	global_position += shift
	_snap_to_ground()


func _snap_to_ground() -> void:
	if _stage == null or not is_instance_valid(_stage):
		global_position.y += ground_lift
		return
	var x: float = global_position.x
	var z: float = global_position.z
	var y: float = global_position.y
	if _stage.has_method("surface_height_at"):
		y = float(_stage.call("surface_height_at", x, z))
	elif _stage.has_method("ground_height"):
		y = float(_stage.call("ground_height", x, z))
	global_position.y = y + ground_lift


## Реальная точка контакта с машиной (сохраняет точное смещение слева/по центру/справа
## для пятен на бампере, капоте и лобовом стекле).
func _impact_point_on_car(car: Node3D, world_pos: Vector3) -> Vector3:
	if car == null or not is_instance_valid(car):
		return world_pos + Vector3(0.0, impact_height, 0.0)
	var local_hit: Vector3 = car.to_local(world_pos + Vector3(0.0, clampf(impact_height, 0.45, 1.2), 0.0))
	local_hit.x = clampf(local_hit.x, -0.95, 0.95)
	local_hit.z = clampf(local_hit.z, -1.6, 2.1)
	return car.to_global(local_hit)


## Точка спавна облака GPU-частиц (чуть сбоку от кузова, чтобы частицы не гасли внутри коллизии).
func _burst_origin(car: Node3D, world_pos: Vector3 = global_position) -> Vector3:
	if car == null or not is_instance_valid(car):
		return world_pos + Vector3(0.0, impact_height, 0.0)
	var local_hit: Vector3 = car.to_local(world_pos + Vector3(0.0, 0.7, 0.0))
	var side: float = 1.35 if local_hit.x >= 0.0 else -1.35
	return car.to_global(Vector3(side, clampf(impact_height, 0.45, 1.2), clampf(local_hit.z, -1.6, 1.8)))


func _flatten(velocity: Vector3 = Vector3.ZERO) -> void:
	if _sprite == null:
		return
	var base_yaw: float = 0.0
	var flat_vel := Vector2(velocity.x, velocity.z)
	if flat_vel.length_squared() > 0.25:
		base_yaw = rad_to_deg(atan2(velocity.x, velocity.z))

	# 1. Один спрайт самого человека
	_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_sprite.no_depth_test = false
	_sprite.render_priority = 2
	_sprite.pixel_size = flatten_pixel_size
	_sprite.position = Vector3(0.0, 0.03, 0.0)
	_sprite.rotation_degrees = Vector3(-90.0, base_yaw + _rng.randf_range(-flatten_yaw_range, flatten_yaw_range), 0.0)
	_sprite.modulate = flatten_color

	# Убираем старый дубликат спрайта человека, если он был
	var old_smear := get_node_or_null("BloodSmear")
	if old_smear != null:
		old_smear.queue_free()

	# 2. Кровавая лужа и след протаскивания (без текстуры второго человека)
	_add_puddle(base_yaw)


func _add_puddle(base_yaw: float = 0.0) -> void:
	var puddle := get_node_or_null("BloodPuddle") as MeshInstance3D
	if puddle == null:
		puddle = MeshInstance3D.new()
		puddle.name = "BloodPuddle"
		add_child(puddle)
	var quad := QuadMesh.new()
	quad.size = puddle_extent
	var paint := ShaderMaterial.new()
	paint.shader = PuddleShader
	paint.set_shader_parameter("blood_color", puddle_color)
	quad.material = paint
	puddle.mesh = quad
	puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	puddle.position = Vector3(0.0, 0.015, 0.0)
	puddle.rotation_degrees = Vector3(-90.0, base_yaw + _rng.randf_range(-20.0, 20.0), 0.0)


func _nudge_car(car: Node3D, velocity: Vector3, impact_pos: Vector3) -> void:
	if car == null or not is_instance_valid(car) or not car is RigidBody3D:
		return
	var body := car as RigidBody3D
	var push: Vector3 = body.global_position - impact_pos
	push.y = 0.0
	if push.length() < 0.01:
		push = -velocity
	push.y = 0.0
	if push.length() < 0.01:
		return
	body.apply_central_impulse(push.normalized() * nudge_impulse)
	body.linear_velocity = body.linear_velocity * speed_keep


func _find_car() -> Node3D:
	if _stage != null and is_instance_valid(_stage):
		var candidate: Variant = _stage.get("car")
		if candidate is Node3D:
			return candidate as Node3D
	if _cached_car != null and is_instance_valid(_cached_car):
		return _cached_car
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		var found := tree.current_scene.find_child("*Car*", true, false) as Node3D
		if found != null:
			_cached_car = found
			return _cached_car
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
	if car is Node3D:
		var spd := _car_speed(car)
		if spd > 0.0:
			return (car as Node3D).global_transform.basis.z.normalized() * spd
	return Vector3.ZERO
