## Кровь после сбитого зрителя: короткий GPU-всплеск в мире и пятна на кузове.
##
## Пятна — отдельный проход поверх слоя грязи (`material_overlay.next_pass`),
## поэтому уже налипшая пыль не пропадает, а кровь остаётся на лаке, пока
## живёт эта машина. Всплеск — одноразовые GPUParticles3D с гравитацией:
## капли падают, туман растворяется.
class_name RallyBloodFx
extends Node

const BloodShader = preload("res://shaders/car_blood.gdshader")
const DustFx = preload("res://scripts/effects/rally_dust_fx.gd")
const SPLAT_CAP := 8
const SKIP_PARTS: Array[String] = [
	"wheel", "glass", "window", "light", "disc", "tire", "cabin", "seat", "mirror",
]

var _material: ShaderMaterial
var _splat_pos: Array[Vector3] = []
var _splat_dir: Array[Vector3] = []
var _splat_data: Array[Vector4] = []
var _next_splat: int = 0
var _rng := RandomNumberGenerator.new()
var _car: Node3D = null


func install(car: Node3D) -> void:
	_car = car
	_rng.seed = int(Time.get_ticks_usec()) ^ int(car.get_instance_id()) ^ 911
	_splat_pos.resize(SPLAT_CAP)
	_splat_dir.resize(SPLAT_CAP)
	_splat_data.resize(SPLAT_CAP)
	for i in range(SPLAT_CAP):
		_splat_pos[i] = Vector3.ZERO
		_splat_dir[i] = Vector3(0.0, 0.0, 1.0)
		_splat_data[i] = Vector4.ZERO
	_material = ShaderMaterial.new()
	_material.shader = BloodShader
	_material.set_shader_parameter("world_to_car", car.global_transform.affine_inverse())
	_material.set_shader_parameter("blood_color", Vector3(0.40, 0.025, 0.04))
	_write_splats()
	_attach_to_body(car)


func add_splat(car: Node3D, world_point: Vector3, world_velocity: Vector3) -> void:
	if _material == null:
		install(car)
	var local_point: Vector3 = car.to_local(world_point)
	local_point.x = clampf(local_point.x, -0.98, 0.98)
	local_point.y = clampf(local_point.y, 0.10, 1.08)
	local_point.z = clampf(local_point.z, -2.20, 2.20)
	var local_dir: Vector3 = car.global_transform.basis.inverse() * world_velocity
	if local_dir.length() < 0.4:
		local_dir = Vector3(local_point.x, 0.12, 1.0)
	local_dir = local_dir.normalized()
	var speed: float = world_velocity.length()
	var index: int = _next_splat
	_next_splat = (_next_splat + 1) % SPLAT_CAP
	_splat_pos[index] = local_point
	_splat_dir[index] = local_dir
	_splat_data[index] = Vector4(
		clampf(0.62 + speed * 0.014, 0.5, 1.0),
		clampf(0.20 + speed * 0.005, 0.16, 0.58),
		clampf(1.15 + speed * 0.045, 1.1, 3.6),
		_rng.randf() * 31.0
	)
	_write_splats()
	_attach_to_body(car)


func update(car: Node3D) -> void:
	if _material == null or car == null:
		return
	_material.set_shader_parameter("world_to_car", car.global_transform.affine_inverse())


## Одноразовый всплеск капель и тумана в мире. Хост — зритель или этап:
## вместе с чанком пропадает и эффект.
static func spray(host: Node, world_point: Vector3, world_velocity: Vector3) -> void:
	if host == null or not is_instance_valid(host):
		return
	var root := Node3D.new()
	root.name = "BloodSpray"
	var speed: float = clampf(world_velocity.length(), 4.0, 55.0)
	var heading: Vector3 = world_velocity
	if heading.length() < 0.4:
		heading = Vector3(0.0, 1.0, 0.0)
	heading = heading.normalized()
	var droplets := _make_droplets(heading, speed)
	var mist := _make_mist(heading, speed)
	root.add_child(droplets)
	root.add_child(mist)
	host.add_child(root)
	root.top_level = true
	root.global_position = world_point
	droplets.restart()
	mist.restart()
	var timer := Timer.new()
	timer.wait_time = 2.4
	timer.one_shot = true
	timer.timeout.connect(root.queue_free)
	root.add_child(timer)
	timer.start()


func _write_splats() -> void:
	if _material == null:
		return
	var positions := PackedVector3Array()
	var directions := PackedVector3Array()
	var data := PackedVector4Array()
	positions.resize(SPLAT_CAP)
	directions.resize(SPLAT_CAP)
	data.resize(SPLAT_CAP)
	for i in range(SPLAT_CAP):
		positions[i] = _splat_pos[i] if i < _splat_pos.size() else Vector3.ZERO
		directions[i] = _splat_dir[i] if i < _splat_dir.size() else Vector3(0.0, 0.0, 1.0)
		data[i] = _splat_data[i] if i < _splat_data.size() else Vector4.ZERO
	_material.set_shader_parameter("splat_pos", positions)
	_material.set_shader_parameter("splat_dir", directions)
	_material.set_shader_parameter("splat_data", data)


func _attach_to_body(car: Node) -> void:
	if _material == null:
		return
	for mesh in _body_meshes(car):
		var overlay: Material = mesh.material_overlay
		if overlay == null:
			mesh.material_overlay = _material
			continue
		if overlay == _material:
			continue
		var pass_material: Material = overlay
		while pass_material.next_pass != null and pass_material.next_pass != _material:
			pass_material = pass_material.next_pass
		if pass_material.next_pass != _material:
			pass_material.next_pass = _material


func _body_meshes(car: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	_collect_meshes(car, car, result)
	return result


func _collect_meshes(node: Node, car: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if not _is_skipped(mesh_node, car):
			var mesh_id := String(mesh_node.name)
			if mesh_id.begins_with("Mitsubishi_Body") or mesh_node.material_overlay != null:
				result.append(mesh_node)
	for child in node.get_children():
		_collect_meshes(child, car, result)


func _is_skipped(mesh_node: Node, car: Node) -> bool:
	var cursor: Node = mesh_node
	while cursor != null and cursor != car:
		var part := String(cursor.name).to_lower()
		for token in SKIP_PARTS:
			if part.find(token) >= 0:
				return true
		cursor = cursor.get_parent()
	return false


static func _make_droplets(heading: Vector3, speed: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "BloodDroplets"
	particles.amount = 48
	particles.lifetime = 1.15
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.randomness = 0.55
	particles.local_coords = false
	particles.emitting = true
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-6, -4, -6), Vector3(12, 10, 12))
	particles.extra_cull_margin = 6.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.028
	mesh.height = 0.046
	mesh.radial_segments = 5
	mesh.rings = 2
	var draw := StandardMaterial3D.new()
	draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw.albedo_color = Color(0.48, 0.03, 0.05, 1.0)
	draw.roughness = 0.22
	draw.metallic_specular = 0.55
	draw.vertex_color_use_as_albedo = true
	draw.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = draw
	particles.draw_pass_1 = mesh
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.22
	process.direction = heading + Vector3(0.0, 0.55, 0.0)
	process.spread = 48.0
	process.initial_velocity_min = 2.4 + speed * 0.12
	process.initial_velocity_max = 6.5 + speed * 0.28
	process.gravity = Vector3(0.0, -18.0, 0.0)
	process.damping_min = 0.8
	process.damping_max = 2.4
	process.scale_min = 0.35
	process.scale_max = 1.35
	process.color = Color(0.46, 0.025, 0.04, 1.0)
	process.color_ramp = _blood_fade()
	process.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
	particles.process_material = process
	return particles


static func _make_mist(heading: Vector3, speed: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "BloodMist"
	particles.amount = 18
	particles.lifetime = 0.85
	particles.one_shot = true
	particles.explosiveness = 0.92
	particles.randomness = 0.4
	particles.local_coords = false
	particles.emitting = true
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	particles.visibility_aabb = AABB(Vector3(-5, -3, -5), Vector3(10, 8, 10))
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.34, 0.34)
	var draw := StandardMaterial3D.new()
	draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw.albedo_color = Color(0.38, 0.02, 0.04, 1.0)
	draw.albedo_texture = DustFx.puff_texture()
	draw.vertex_color_use_as_albedo = true
	draw.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = draw
	particles.draw_pass_1 = mesh
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.18
	process.direction = heading + Vector3(0.0, 0.35, 0.0)
	process.spread = 70.0
	process.initial_velocity_min = 0.6 + speed * 0.03
	process.initial_velocity_max = 2.2 + speed * 0.08
	process.gravity = Vector3(0.0, -1.6, 0.0)
	process.scale_min = 0.7
	process.scale_max = 1.8
	process.scale_curve = DustFx.growth_curve(2.4)
	process.color = Color(0.32, 0.02, 0.035, 1.0)
	process.color_ramp = DustFx.fade_ramp()
	particles.process_material = process
	return particles


static func _blood_fade() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.55, 0.04, 0.06, 1.0))
	gradient.set_color(1, Color(0.18, 0.01, 0.02, 0.0))
	gradient.add_point(0.55, Color(0.38, 0.02, 0.04, 0.85))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 128
	return texture
