## Четыре независимые зоны загрязнения и выброс грунта из-под колёс.
## Оригинальные материалы/краска не заменяются; слой живёт только на кузове.
extends Node

const DirtShader = preload("res://shaders/car_dirt.gdshader")
const SurfaceType = preload("res://scripts/road_surface.gd")
var amounts := Vector4.ZERO
var damp := Vector4.ZERO
var snow_amounts := Vector4.ZERO
var _material: ShaderMaterial
var _sprays: Array[GPUParticles3D] = []
var _surface = SurfaceType.new()


func install(car: Node3D) -> void:
	_material = ShaderMaterial.new()
	_material.shader = DirtShader
	var model := car.get_node_or_null("low poly lance evo")
	if model != null:
		for child in model.get_children():
			if child is MeshInstance3D and String(child.name).begins_with("Mitsubishi_Body"):
				child.material_overlay = _material
	for i in range(4):
		var spray := GPUParticles3D.new()
		spray.name = "WheelSoilSpray%d" % i
		spray.amount = 36
		spray.lifetime = 0.55
		spray.emitting = false
		spray.local_coords = false
		spray.visibility_aabb = AABB(Vector3(-12, -6, -12), Vector3(24, 18, 24))
		var process := ParticleProcessMaterial.new()
		process.direction = Vector3(0, 0.7, -1)
		process.spread = 27.0
		process.gravity = Vector3(0, -9.8, 0)
		process.initial_velocity_min = 1.5
		process.initial_velocity_max = 5.0
		process.scale_min = 0.4
		process.scale_max = 1.4
		spray.process_material = process
		var grain := SphereMesh.new()
		grain.radius = 0.018
		grain.height = 0.036
		grain.radial_segments = 4
		grain.rings = 1
		var soil := StandardMaterial3D.new()
		soil.albedo_color = Color.WHITE
		soil.vertex_color_use_as_albedo = true
		soil.roughness = 1.0
		grain.material = soil
		spray.draw_pass_1 = grain
		car.add_child(spray)
		_sprays.append(spray)


func accumulate(index: int, kind: String, wetness: float, speed: float, slip: float, delta: float) -> void:
	if index < 0 or index >= 4 or speed < 1.0 or delta <= 0.0:
		return
	if kind == "snow":
		var snow_work := 0.025 * clampf(speed / 12.0, 0.0, 2.0) * (1.0 + minf(maxf(slip, 0.0), 2.0)) * delta
		snow_amounts[index] = clampf(snow_amounts[index] + snow_work, 0.0, 1.0)
		return
	if kind == "asphalt":
		return
	wetness = clampf(wetness, 0.0, 1.0)
	var rate := (0.018 if kind == "gravel" else 0.045) * lerpf(0.35, 1.8, wetness)
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
	for i in range(4):
		damp[i] = move_toward(damp[i], rain, delta * (0.08 if rain > damp[i] else 0.012))
		amounts[i] = maxf(0.0, amounts[i] - rain * 0.002 * delta)
		snow_amounts[i] = clampf(snow_amounts[i] + (snowfall * 0.015 - rain * 0.025 - (0.004 if snowfall <= 0.0 else 0.0)) * delta, 0.0, 1.0)


func update(car: Node3D, wheels: Array, road_name: String, wetness: float, snow: float, delta: float, rain: float = 0.0, snowfall: float = 0.0) -> void:
	if _material == null:
		return
	update_weather(rain, snowfall, delta)
	var positions := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	for i in range(mini(4, wheels.size())):
		var wheel = wheels[i]
		# Центры масок — на кузове, не на движущейся подвеске:
		# уже нанесённые пятна не сдвигаются на кочках.
		positions[i] = car.to_local(wheel.global_position) + Vector3.DOWN * wheel.spring_length * 0.65
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
		spray.emitting = kind != "asphalt" and speed > 3.0 and (kind == "snow" or slip > 0.18 or wetness > 0.3)
		var process := spray.process_material as ParticleProcessMaterial
		process.direction = Vector3(0, 0.7, -signf(wheel.local_velocity.z))
		process.initial_velocity_max = clampf(speed * 0.35 + slip * 3.0, 2.0, 10.0)
		process.color = Color(0.9, 0.94, 1.0) if kind == "snow" else Color(0.36, 0.26, 0.15).lerp(Color(0.12, 0.075, 0.035), wetness)
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
