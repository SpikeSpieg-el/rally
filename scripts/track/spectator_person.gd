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
## 0.10 давал останки вдвое выше роста — «огромные» тела на полотне.
@export_range(0.01, 0.25, 0.001) var flatten_pixel_size: float = 0.05
@export var flatten_color: Color = Color(0.32, 0.04, 0.05, 0.92)
@export_range(0.0, 180.0, 1.0, "suffix:°") var flatten_yaw_range: float = 55.0
## След-потёк чуть длиннее тела, но не в разы (0.16 давал ~10 м полосу).
@export_range(0.01, 0.3, 0.001) var smear_pixel_size: float = 0.065
@export var smear_color: Color = Color(0.28, 0.02, 0.03, 0.78)
## Размер кровавой лужи на полотне, м (длина × ширина).
@export var puddle_extent: Vector2 = Vector2(1.5, 0.95)
@export var puddle_color: Color = Color(0.38, 0.02, 0.04, 0.82)
@export_range(0.0, 0.2, 0.005, "suffix:м") var ground_lift: float = 0.06
@export_range(0.0, 2000.0, 10.0) var nudge_impulse: float = 420.0
@export_range(0.5, 1.0, 0.01) var speed_keep: float = 0.97

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
	if start_eager:
		_eager = true
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
	if body is Node3D:
		var as_node := body as Node3D
		if _car_speed(as_node) >= hit_min_speed:
			crush(as_node)


func crush(car: Node3D) -> void:
	if _crushed:
		return
	_crushed = true
	set_physics_process(false)
	_disable_hitbox()
	var velocity: Vector3 = _car_velocity(car)
	var impact: Vector3 = _burst_origin(car)
	_throw_onto_road(velocity)
	_flatten()
	var spray_host: Node = car if car != null and is_instance_valid(car) else self
	BloodFx.spray(spray_host, impact, velocity, blood_burst)
	if car != null and car.has_method("splatter_blood"):
		car.call("splatter_blood", impact, velocity)
	_nudge_car.call_deferred(car, velocity)


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
	# surface_height_at — верх НАРИСОВАННОЙ поверхности (полотно над кюветом).
	# Обычный ground_height под дорогой отдаёт дно кювета, и останки тонули
	# под мешем асфальта: их было видно только на траве.
	if _stage.has_method("surface_height_at"):
		y = float(_stage.call("surface_height_at", x, z))
	elif _stage.has_method("ground_height"):
		y = float(_stage.call("ground_height", x, z))
	global_position.y = y + ground_lift


func _burst_origin(car: Node3D) -> Vector3:
	if car == null or not is_instance_valid(car):
		return global_position + Vector3(0.0, impact_height, 0.0)
	# Снаружи кузова, с той стороны, где человек: иначе частицы рождаются
	# внутри меша и «проходят насквозь», их не видно.
	var local_hit: Vector3 = car.to_local(global_position + Vector3(0.0, 0.7, 0.0))
	var side: float = 1.35 if local_hit.x >= 0.0 else -1.35
	return car.to_global(Vector3(side, clampf(impact_height, 0.45, 1.2), clampf(local_hit.z, -1.6, 1.8)))


func _flatten() -> void:
	if _sprite == null:
		return
	_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_sprite.no_depth_test = false
	_sprite.render_priority = 2
	_sprite.pixel_size = flatten_pixel_size
	_sprite.position = Vector3(0.0, 0.02, 0.0)
	_sprite.rotation_degrees = Vector3(-90.0, _rng.randf_range(-flatten_yaw_range, flatten_yaw_range), 0.0)
	_sprite.modulate = flatten_color
	var smear := Sprite3D.new()
	smear.name = "BloodSmear"
	smear.texture = _sprite.texture
	smear.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	smear.no_depth_test = false
	smear.render_priority = 2
	smear.pixel_size = smear_pixel_size
	smear.modulate = smear_color
	smear.position = Vector3(_rng.randf_range(-0.25, 0.25), 0.015, _rng.randf_range(-0.2, 0.2))
	smear.rotation_degrees = Vector3(-90.0, _rng.randf_range(-80.0, 80.0), 0.0)
	add_child(smear)
	_add_puddle()


func _add_puddle() -> void:
	var puddle := MeshInstance3D.new()
	puddle.name = "BloodPuddle"
	var quad := QuadMesh.new()
	quad.size = puddle_extent
	var paint := ShaderMaterial.new()
	paint.shader = PuddleShader
	paint.set_shader_parameter("blood_color", puddle_color)
	quad.material = paint
	puddle.mesh = quad
	puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	puddle.position = Vector3(0.0, 0.03, 0.4)
	puddle.rotation_degrees = Vector3(-90.0, _rng.randf_range(-25.0, 25.0), 0.0)
	add_child(puddle)


func _nudge_car(car: Node3D, velocity: Vector3) -> void:
	if car == null or not is_instance_valid(car) or not car is RigidBody3D:
		return
	var body := car as RigidBody3D
	var push: Vector3 = body.global_position - global_position
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
