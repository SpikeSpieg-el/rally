## Четыре независимых зоны загрязнения и эффекты контакта шин с разными покрытиями.
## Кузов получает отдельный процедурный слой; краска не заменяется.
##
## Цвета, уровни и поведение брызг/пыли лежат в RallySurfaceFxProfile,
## а общий профиль RallyFxProfile задаёт базовую плотность и погоду.
extends Node

const DirtShader = preload("res://shaders/car_dirt.gdshader")
const SurfaceType = preload("res://scripts/road_surface.gd")
const FxProfileType = preload("res://scripts/data/rally_fx_profile.gd")
const SurfaceFxProfileType = preload("res://scripts/data/rally_surface_fx_profile.gd")
const SURFACE_KINDS: Array[String] = ["gravel", "mud", "grass", "snow", "asphalt"]

## Профиль эффектов из инспектора. Пусто — значения по умолчанию ресурса.
@export var fx: FxProfileType = null

var amounts := Vector4.ZERO
var damp := Vector4.ZERO
var snow_amounts := Vector4.ZERO
var _material: ShaderMaterial
var _sprays: Array[GPUParticles3D] = []
var _spray_kinds: Array[String] = ["", "", "", ""]
var _profiles: Dictionary = {}
var _surface = SurfaceType.new()
var _rng := RandomNumberGenerator.new()


func _p(name: String, fallback: float) -> float:
	return float(fx.get(name)) if fx != null else fallback


func _pc(name: String, fallback: Color) -> Color:
	return fx.get(name) as Color if fx != null else fallback


func _pv(name: String, fallback: Vector3) -> Vector3:
	return fx.get(name) as Vector3 if fx != null else fallback


func install(car: Node3D) -> void:
	_load_surface_profiles()
	_rng.seed = int(Time.get_ticks_usec()) ^ int(car.get_instance_id())
	_material = ShaderMaterial.new()
	_material.shader = DirtShader
	_material.set_shader_parameter(
		"pattern_seed",
		Vector3(
			_rng.randf_range(-31.0, 31.0),
			_rng.randf_range(-31.0, 31.0),
			_rng.randf_range(-31.0, 31.0)
		)
	)
	var model := car.get_node_or_null("low poly lance evo")
	if model != null:
		for child in model.get_children():
			if child is MeshInstance3D and String(child.name).begins_with("Mitsubishi_Body"):
				child.material_overlay = _material
	var grain_segments: int = int(_p("spray_grain_segments", 4))
	for i in range(4):
		var spray := GPUParticles3D.new()
		spray.name = "WheelSurfaceFX%d" % i
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
		soil.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		soil.albedo_color = Color.WHITE
		soil.vertex_color_use_as_albedo = true
		soil.roughness = 1.0
		grain.material = soil
		spray.draw_pass_1 = grain
		car.add_child(spray)
		_sprays.append(spray)


func _load_surface_profiles() -> void:
	_profiles.clear()
	if fx != null:
		for entry in fx.surface_fx_profiles:
			var profile := entry as SurfaceFxProfileType
			if profile != null:
				_profiles[profile.kind_name()] = profile
	for kind in SURFACE_KINDS:
		if not _profiles.has(kind):
			_profiles[kind] = _fallback_profile(kind)


## Совместимые значения на случай старой/custom FX-ресурса без профилей покрытий.
func _fallback_profile(kind: String) -> RallySurfaceFxProfile:
	var profile := SurfaceFxProfileType.new() as RallySurfaceFxProfile
	match kind:
		"gravel":
			profile.kind = SurfaceFxProfileType.Kind.GRAVEL
			profile.dry_color = _pc("spray_dry_color", profile.dry_color)
			profile.wet_color = _pc("spray_wet_color", profile.wet_color)
		"mud":
			profile.kind = SurfaceFxProfileType.Kind.MUD
			profile.dry_color = Color(0.31, 0.22, 0.14, 0.82)
			profile.wet_color = Color(0.12, 0.075, 0.04, 0.94)
			profile.gravity_scale = Vector3(0.8, 1.0, 0.8)
			profile.amount_scale = 1.1
			profile.particle_scale = 1.3
			profile.grain_scale = 1.45
			profile.speed_weight = 0.62
			profile.wet_weight = 0.38
		"grass":
			profile.kind = SurfaceFxProfileType.Kind.GRASS
			profile.dry_color = Color(0.34, 0.31, 0.17, 0.68)
			profile.wet_color = Color(0.2, 0.18, 0.1, 0.78)
			profile.amount_scale = 0.62
			profile.lifetime_scale = 0.78
			profile.spread_scale = 1.3
			profile.velocity_scale = 0.82
			profile.particle_scale = 0.78
			profile.grain_scale = 0.72
			profile.speed_weight = 0.48
			profile.slip_weight = 0.78
		"snow":
			profile.kind = SurfaceFxProfileType.Kind.SNOW
			profile.dry_color = _pc("spray_snow_color", Color(0.9, 0.95, 1.0, 0.78))
			profile.wet_color = profile.dry_color
			profile.gravity_scale = Vector3(0.18, 0.1, 0.18)
			profile.direction = Vector3(0, 0.9, 1)
			profile.lifetime_scale = 1.55
			profile.spread_scale = 1.45
			profile.velocity_scale = 0.88
			profile.particle_scale = 1.25
			profile.grain_scale = 0.68
			profile.speed_weight = 0.65
			profile.slip_weight = 0.9
		"asphalt":
			profile.kind = SurfaceFxProfileType.Kind.ASPHALT
			profile.dry_color = Color(0.24, 0.27, 0.3, 0.36)
			profile.wet_color = Color(0.72, 0.82, 0.92, 0.62)
			profile.gravity_scale = Vector3(0.08, 0.035, 0.08)
			profile.direction = Vector3(0, 0.28, 1)
			profile.amount_scale = 0.68
			profile.lifetime_scale = 1.4
			profile.spread_scale = 1.55
			profile.velocity_scale = 0.62
			profile.particle_scale = 1.55
			profile.speed_weight = 0.0
			profile.slip_weight = 1.0
			profile.wet_weight = 0.92
			profile.speed_start_kmh = 10.0
			profile.speed_full_kmh = 88.0
			profile.slip_start = 0.2
			profile.slip_full = 0.72
	# Старые общие пороги используются только для запасных профилей.
	profile.speed_start_kmh = maxf(
		profile.speed_start_kmh, _p("spray_min_speed", 3.0) * 3.6
	)
	profile.slip_start = maxf(
		profile.slip_start, _p("spray_slip_threshold", profile.slip_start)
	)
	var wet_threshold: float = clampf(_p("spray_wet_threshold", 0.3), 0.01, 1.0)
	profile.wet_weight = maxf(
		profile.wet_weight, profile.level_1_threshold / wet_threshold
	)
	return profile


func profile_for_kind(kind: String) -> RallySurfaceFxProfile:
	if _profiles.is_empty():
		_load_surface_profiles()
	return _profiles.get(kind, _profiles.get("gravel")) as RallySurfaceFxProfile


func effect_level_for(kind: String, speed_kmh: float, slip: float, wetness: float) -> int:
	var profile := profile_for_kind(kind)
	return profile.level_for(speed_kmh, slip, wetness) if profile != null else 0


## Поверхность конкретного колеса с учётом участка трассы, а не только общего пресета.
func kind_for_wheel(wheel: Object, road_name: String, snow: float) -> String:
	var cached_kind: String = str(wheel.get("surface_kind"))
	if not cached_kind.is_empty():
		return cached_kind
	var collider := wheel.get("last_collider") as Node
	if collider == null:
		return ""
	var grass: bool = collider.is_in_group("Grass")
	if not grass and not collider.is_in_group("Dirt") and not collider.is_in_group("Road"):
		return ""
	var stage: Node = get_parent().get_parent() if get_parent() != null else null
	if stage != null and stage.has_method("surface_kind_at"):
		return str(stage.call("surface_kind_at", wheel.get("last_collision_point"), grass))
	return _surface.surface_kind(road_name, grass, snow)


func _configure_spray_profile(
	spray: GPUParticles3D, index: int, profile: RallySurfaceFxProfile
) -> void:
	_spray_kinds[index] = profile.kind_name()
	spray.name = "WheelSurfaceFX_%s_%d" % [profile.kind_name().capitalize(), index]
	spray.amount = maxi(1, roundi(_p("spray_amount", 36.0) * profile.amount_scale))
	spray.lifetime = maxf(0.05, _p("spray_lifetime", 0.55) * profile.lifetime_scale)
	var process := spray.process_material as ParticleProcessMaterial
	if process != null:
		var gravity := _pv("spray_gravity", Vector3(0, -9.8, 0))
		process.direction = profile.direction
		process.spread = clampf(_p("spray_spread", 27.0) * profile.spread_scale, 0.0, 90.0)
		process.gravity = Vector3(
			gravity.x * profile.gravity_scale.x,
			gravity.y * profile.gravity_scale.y,
			gravity.z * profile.gravity_scale.z
		)
		process.scale_min = _p("spray_scale_min", 0.4) * profile.particle_scale
		process.scale_max = _p("spray_scale_max", 1.4) * profile.particle_scale
		process.initial_velocity_min = _p("spray_speed_min", 1.5) * profile.velocity_scale
		process.initial_velocity_max = _p("spray_speed_max", 5.0) * profile.velocity_scale
	var grain := spray.draw_pass_1 as SphereMesh
	if grain != null:
		grain.radius = _p("spray_grain_radius", 0.018) * profile.grain_scale
		grain.height = _p("spray_grain_height", 0.036) * profile.grain_scale


func accumulate(
	index: int, kind: String, wetness: float, speed: float, slip: float, delta: float
) -> void:
	if index < 0 or index >= 4 or speed < _p("dirt_min_speed", 1.0) or delta <= 0.0:
		return
	if kind == "snow":
		var snow_work := (
			_p("snow_rate", 0.025)
			* clampf(speed / 12.0, 0.0, 2.0)
			* (1.0 + minf(maxf(slip, 0.0), 2.0))
			* delta
		)
		snow_amounts[index] = clampf(snow_amounts[index] + snow_work, 0.0, 1.0)
		return
	if kind == "asphalt":
		return
	wetness = clampf(wetness, 0.0, 1.0)
	var base_rate: float = _p("mud_dirt_rate", 0.045)
	if kind == "gravel":
		base_rate = _p("gravel_dirt_rate", 0.018)
	elif kind == "grass":
		base_rate = _p("grass_dirt_rate", 0.008)
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
	var wash: float = _p("rain_wash", 0.035)
	var snow_gain: float = _p("snow_gain", 0.035)
	var snow_wash: float = _p("snow_wash_by_rain", 0.035)
	var snow_melt: float = _p("snow_melt", 0.004)
	for i in range(4):
		damp[i] = move_toward(damp[i], rain, delta * (wet_gain if rain > damp[i] else dry_loss))
		amounts[i] = maxf(0.0, amounts[i] - rain * wash * delta)
		var snow_delta: float = snowfall * snow_gain - rain * snow_wash
		if snowfall <= 0.0:
			snow_delta -= snow_melt
		snow_amounts[i] = clampf(snow_amounts[i] + snow_delta * delta, 0.0, 1.0)


func update(
	car: Node3D,
	wheels: Array,
	road_name: String,
	wetness: float,
	snow: float,
	delta: float,
	rain: float = 0.0,
	snowfall: float = 0.0
) -> void:
	if _material == null:
		return
	update_weather(rain, snowfall, delta)
	var positions := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	var spring_scale: float = _p("dirt_center_spring_scale", 0.65)
	for spray in _sprays:
		spray.emitting = false
	for i in range(mini(4, wheels.size())):
		var wheel = wheels[i]
		# Центры масок — на кузове, не на движущейся подвеске:
		# уже нанесённые пятна не сдвигаются на кочках.
		positions[i] = (
			car.to_local(wheel.global_position) + Vector3.DOWN * wheel.spring_length * spring_scale
		)
		if not wheel.is_colliding() or wheel.last_collider == null or wheel.spring_force <= 0.0:
			continue
		var collider: Node = wheel.last_collider
		var grass := collider.is_in_group("Grass")
		if not grass and not collider.is_in_group("Dirt") and not collider.is_in_group("Road"):
			continue
		var kind: String = kind_for_wheel(wheel, road_name, snow)
		var speed: float = Vector2(wheel.local_velocity.x, wheel.local_velocity.z).length()
		var slip: float = wheel.slip_vector.length()
		accumulate(i, kind, wetness, speed, slip, delta)
		if kind.is_empty():
			continue
		var profile := profile_for_kind(kind)
		if profile == null:
			continue
		var spray := _sprays[i]
		if _spray_kinds[i] != kind:
			_configure_spray_profile(spray, i, profile)
		if fx != null and not fx.surface_fx_enabled:
			continue
		if speed < _p("spray_min_speed", 3.0):
			continue
		var level: int = profile.level_for(speed * 3.6, slip, wetness)
		if level <= 0:
			continue
		spray.global_position = wheel.last_collision_point + wheel.last_collision_normal * 0.05
		spray.amount_ratio = profile.amount_ratio_for_level(level)
		spray.emitting = spray.amount_ratio > 0.0
		var process := spray.process_material as ParticleProcessMaterial
		if process != null:
			var velocity_tier: float = profile.velocity_scale_for_level(level)
			var base_min: float = (
				_p("spray_speed_min", 1.5) * profile.velocity_scale * velocity_tier
			)
			var base_max: float = (
				(_p("spray_speed_max", 5.0) + speed * _p("spray_speed_factor", 0.35))
				* profile.velocity_scale
				* velocity_tier
			)
			process.direction = Vector3(
				profile.direction.x,
				profile.direction.y,
				(
					-absf(profile.direction.z)
					* (
						signf(wheel.local_velocity.z)
						if not is_zero_approx(wheel.local_velocity.z)
						else 1.0
					)
				)
			)
			process.initial_velocity_min = base_min
			process.initial_velocity_max = clampf(
				base_max + slip * _p("spray_slip_bonus", 3.0),
				_p("spray_speed_floor", 2.0),
				_p("spray_speed_cap", 10.0)
			)
			process.color = profile.color_for_wetness(wetness)
	_material.set_shader_parameter("world_to_car", car.global_transform.affine_inverse())
	_material.set_shader_parameter("wheels", positions)
	_material.set_shader_parameter("dirt_amount", amounts)
	_material.set_shader_parameter("damp_amount", damp)
	_material.set_shader_parameter("snow_amount", snow_amounts)


func clear() -> void:
	amounts = Vector4.ZERO
	damp = Vector4.ZERO
	snow_amounts = Vector4.ZERO
	for spray in _sprays:
		spray.emitting = false
	if _material != null:
		_material.set_shader_parameter("dirt_amount", amounts)
		_material.set_shader_parameter("damp_amount", damp)
		_material.set_shader_parameter("snow_amount", snow_amounts)
