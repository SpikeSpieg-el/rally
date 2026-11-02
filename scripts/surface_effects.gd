## Четыре независимые зоны загрязнения и выброс грунта из-под колёс.
## Оригинальные материалы/краска не заменяются; слой живёт только на кузове.
##
## Все скорости налипания, цвета брызг, размеры и пороги — в ресурсе
## RallyFxProfile (data/stage/default_fx_profile.tres). Код только читает.
extends Node

const DirtShader = preload("res://shaders/car_dirt.gdshader")
const SurfaceType = preload("res://scripts/road_surface.gd")
const FxProfileType = preload("res://scripts/data/rally_fx_profile.gd")

## Профиль эффектов из инспектора. Пусто — значения по умолчанию ресурса.
@export var fx: FxProfileType = null

var amounts := Vector4.ZERO
var damp := Vector4.ZERO
var snow_amounts := Vector4.ZERO
var _material: ShaderMaterial
var _sprays: Array[GPUParticles3D] = []
var _surface = SurfaceType.new()


func _p(name: String, fallback: float) -> float:
	return float(fx.get(name)) if fx != null else fallback


func _pc(name: String, fallback: Color) -> Color:
	return fx.get(name) as Color if fx != null else fallback


func install(car: Node3D) -> void:
	_material = ShaderMaterial.new()
	_material.shader = DirtShader
	var model := car.get_node_or_null("low poly lance evo")
	if model != null:
		for child in model.get_children():
			if child is MeshInstance3D and String(child.name).begins_with("Mitsubishi_Body"):
				child.material_overlay = _material
	var grain_segments: int = int(_p("spray_grain_segments", 4))
	for i in range(4):
		var spray := GPUParticles3D.new()
		spray.name = "WheelSoilSpray%d" % i
		spray.amount = int(_p("spray_amount", 36))
		spray.lifetime = _p("spray_lifetime", 0.55)
		spray.emitting = false
		spray.local_coords = false
		spray.visibility_aabb = AABB(Vector3(-12, -6, -12), Vector3(24, 18, 24))
		var process := ParticleProcessMaterial.new()
		process.direction = _pv("spray_direction", Vector3(0, 0.7, -1))
		process.spread = _p("spray_spread", 27.0)
		process.gravity = _pv("spray_gravity", Vector3(0, -9.8, 0))
		process.initial_velocity_min = _p("spray_speed_min", 1.5)
		process.initial_velocity_max = _p("spray_speed_max", 5.0)
		process.scale_min = _p("spray_scale_min", 0.4)
		process.scale_max = _p("spray_scale_max", 1.4)
		spray.process_material = process
		var grain := SphereMesh.new()
		grain.radius = _p("spray_grain_radius", 0.018)
		grain.height = _p("spray_grain_height", 0.036)
		grain.radial_segments = grain_segments
		grain.rings = 1
		var soil := StandardMaterial3D.new()
		soil.albedo_color = Color.WHITE
		soil.vertex_color_use_as_albedo = true
		soil.roughness = 1.0
		grain.material = soil
		spray.draw_pass_1 = grain
		car.add_child(spray)
		_sprays.append(spray)


func _pv(name: String, fallback: Vector3) -> Vector3:
	return fx.get(name) as Vector3 if fx != null else fallback


func accumulate(index: int, kind: String, wetness: float, speed: float, slip: float, delta: float) -> void:
	if index < 0 or index >= 4 or speed < _p("dirt_min_speed", 1.0) or delta <= 0.0:
		return
	if kind == "snow":
		var snow_work := _p("snow_rate", 0.025) * clampf(speed / 12.0, 0.0, 2.0) * (1.0 + minf(maxf(slip, 0.0), 2.0)) * delta
		snow_amounts[index] = clampf(snow_amounts[index] + snow_work, 0.0, 1.0)
		return
	if kind == "asphalt":
		return
	wetness = clampf(wetness, 0.0, 1.0)
	var base_rate: float = _p("gravel_dirt_rate", 0.018) if kind == "gravel" else _p("mud_dirt_rate", 0.045)
	var rate := base_rate * lerpf(_p("damp_dry_scale", 0.35), _p("damp_wet_scale", 1.8), wetness)
	var work := rate * clampf(speed / 12.0, 0.0, 2.0) * (1.0 + clampf(slip, 0.0, 2.0)) * delta
	amounts[index] = clampf(amounts[index] + work, 0.0, 1.0)
	damp[index] = clampf(damp[index] + work * wetness, 0.0, 1.0)


## Осадки воздействуют на уже нанесённый налёт даже когда машина стоит.
## Влажность полотна сама по себе не означает, что сейчас идёт дождь.
func update_weather(rain: float, snowfall: float, delta: float) -> void:
	if delta <= 0.0:
		return
	rain = clampf(rain, 0.0, 1.0)
	snowfall = clampf(snowfall, 0.0, 1.0)
	var wet_gain: float = _p("rain_wet_gain", 0.08)
	var dry_loss: float = _p("rain_dry_loss", 0.012)
	var wash: float = _p("rain_wash", 0.002)
	var snow_gain: float = _p("snow_gain", 0.015)
	var snow_wash: float = _p("snow_wash_by_rain", 0.025)
	var snow_melt: float = _p("snow_melt", 0.004)
	for i in range(4):
		damp[i] = move_toward(damp[i], rain, delta * (wet_gain if rain > damp[i] else dry_loss))
		amounts[i] = maxf(0.0, amounts[i] - rain * wash * delta)
		snow_amounts[i] = clampf(snow_amounts[i] + (snowfall * snow_gain - rain * snow_wash - (snow_melt if snowfall <= 0.0 else 0.0)) * delta, 0.0, 1.0)


func update(car: Node3D, wheels: Array, road_name: String, wetness: float, snow: float, delta: float, rain: float = 0.0, snowfall: float = 0.0) -> void:
	if _material == null:
		return
	update_weather(rain, snowfall, delta)
	var positions := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	var spring_scale: float = _p("dirt_center_spring_scale", 0.65)
	for i in range(mini(4, wheels.size())):
		var wheel = wheels[i]
		# Центры масок — на кузове, не на движущейся подвеске:
		# уже нанесённые пятна не сдвигаются на кочках.
		positions[i] = car.to_local(wheel.global_position) + Vector3.DOWN * wheel.spring_length * spring_scale
		var spray := _sprays[i]
		spray.emitting = false
		if not wheel.is_colliding() or wheel.last_collider == null or wheel.spring_force <= 0.0:
			continue
		var collider: Node = wheel.last_collider
		var grass := collider.is_in_group("Grass")
		if not grass and not collider.is_in_group("Dirt") and not collider.is_in_group("Road"):
			continue
		var kind: String = _surface.surface_kind(road_name, grass, snow)
		var speed: float = Vector2(wheel.local_velocity.x, wheel.local_velocity.z).length()
		var slip: float = wheel.slip_vector.length()
		accumulate(i, kind, wetness, speed, slip, delta)
		spray.global_position = wheel.last_collision_point + wheel.last_collision_normal * 0.05
		spray.emitting = kind != "asphalt" and speed > _p("spray_min_speed", 3.0) and (
			kind == "snow" or slip > _p("spray_slip_threshold", 0.18) or wetness > _p("spray_wet_threshold", 0.3)
		)
		var process := spray.process_material as ParticleProcessMaterial
		process.direction = Vector3(0, 0.7, -signf(wheel.local_velocity.z))
		process.initial_velocity_max = clampf(
			speed * _p("spray_speed_factor", 0.35) + slip * _p("spray_slip_bonus", 3.0),
			_p("spray_speed_floor", 2.0),
			_p("spray_speed_cap", 10.0)
		)
		process.color = _pc("spray_snow_color", Color(0.9, 0.94, 1.0)) if kind == "snow" else _pc("spray_dry_color", Color(0.36, 0.26, 0.15)).lerp(_pc("spray_wet_color", Color(0.12, 0.075, 0.035)), wetness)
	_material.set_shader_parameter("world_to_car", car.global_transform.affine_inverse())
	_material.set_shader_parameter("wheels", positions)
	_material.set_shader_parameter("dirt_amount", amounts)
	_material.set_shader_parameter("damp_amount", damp)
	_material.set_shader_parameter("snow_amount", snow_amounts)


func clear() -> void:
	amounts = Vector4.ZERO
	damp = Vector4.ZERO
	snow_amounts = Vector4.ZERO
	if _material != null:
		_material.set_shader_parameter("dirt_amount", amounts)
		_material.set_shader_parameter("damp_amount", damp)
		_material.set_shader_parameter("snow_amount", snow_amounts)
