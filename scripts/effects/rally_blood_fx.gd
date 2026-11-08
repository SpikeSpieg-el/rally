## Пятна крови на кузове, бампере и стекле. Сцена `scenes/effects/blood_stains.tscn` —
## пульт: цвет, блеск, размер пятна, какие меши пачкать. Всплеск частиц живёт
## отдельно в `scenes/effects/blood_burst.tscn` и инстансируется при ударе.
@tool
class_name RallyBloodFx
extends Node

const BloodShader = preload("res://shaders/car_blood.gdshader")
const DEFAULT_BURST := "res://scenes/effects/blood_burst.tscn"
const SPLAT_CAP := 8
const DECAL_CAP := 12
const BLOCKER_NAME := "BloodParticleBlocker"
const GLASS_NAME := "BloodGlassSmear"
const LAYER_NAME := "BloodLayer"

@export_group("Вкл и цвет")
@export var enabled: bool = true
@export var blood_color: Color = Color(0.40, 0.025, 0.04, 1.0)
@export_range(0.0, 1.0, 0.01) var blood_gloss: float = 0.42
@export_multiline var description: String = "Пятна на бампере, кузове и стекле. Всплеск — сцена Blood Burst."

@export_group("Всплеск")
## Сцена GPU-частиц. Пусто — res://scenes/effects/blood_burst.tscn.
@export var burst_scene: PackedScene

@export_group("Какие меши пачкать")
@export var body_prefixes: PackedStringArray = PackedStringArray(["Mitsubishi_Body"])
## Стёкла и зеркала не пропускаем — на них тоже нужны следы.
@export var body_skip: PackedStringArray = PackedStringArray(
	["wheel", "light", "disc", "tire", "cabin", "seat", "interior", "cockpit", "charm", "robe"]
)

@export_group("Размер пятна от скорости")
## Непрозрачность: x при низкой скорости, y добавка за м/с.
@export var amount_from_speed: Vector2 = Vector2(0.82, 0.012)
@export var radius_from_speed: Vector2 = Vector2(0.34, 0.007)
@export var stretch_from_speed: Vector2 = Vector2(1.25, 0.04)
@export var amount_limits: Vector2 = Vector2(0.65, 1.0)
@export var radius_limits: Vector2 = Vector2(0.28, 0.82)
@export var stretch_limits: Vector2 = Vector2(1.15, 3.4)

@export_group("Куда класть на кузове")
@export var splat_min: Vector3 = Vector3(-1.05, 0.08, -2.20)
@export var splat_max: Vector3 = Vector3(1.05, 1.38, 2.35)
@export var bumper_point: Vector3 = Vector3(0.0, 0.34, 2.08)
@export var hood_point: Vector3 = Vector3(0.0, 0.62, 1.48)
@export var glass_point: Vector3 = Vector3(0.0, 1.14, 0.96)
@export var glass_extent: Vector2 = Vector2(1.15, 0.52)

var _material: ShaderMaterial
var _splat_pos: Array[Vector3] = []
var _splat_dir: Array[Vector3] = []
var _splat_data: Array[Vector4] = []
var _next_splat: int = 0
var _decals: Array[Decal] = []
var _next_decal: int = 0
var _stain_tex: Texture2D
var _rng := RandomNumberGenerator.new()


func install(car: Node3D) -> void:
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
	_write_look()
	_write_splats()
	_attach_to_body(car)
	ensure_particle_blocker(car)


func add_splat(car: Node3D, world_point: Vector3, world_velocity: Vector3) -> void:
	if not enabled:
		return
	if _material == null:
		install(car)
	var local_hit: Vector3 = car.to_local(world_point)
	local_hit.x = clampf(local_hit.x, splat_min.x, splat_max.x)
	local_hit.y = clampf(local_hit.y, splat_min.y, splat_max.y)
	local_hit.z = clampf(local_hit.z, splat_min.z, splat_max.z)
	var local_dir: Vector3 = car.global_transform.basis.inverse() * world_velocity
	if local_dir.length() < 0.4:
		local_dir = Vector3(local_hit.x, 0.12, 1.0)
	local_dir = local_dir.normalized()
	var speed: float = world_velocity.length()
	var amount: float = clampf(amount_from_speed.x + speed * amount_from_speed.y, amount_limits.x, amount_limits.y)
	var radius: float = clampf(radius_from_speed.x + speed * radius_from_speed.y, radius_limits.x, radius_limits.y)
	var stretch: float = clampf(stretch_from_speed.x + speed * stretch_from_speed.y, stretch_limits.x, stretch_limits.y)
	var side: float = clampf(local_hit.x, -0.45, 0.45)
	# Несколько следов с одного удара: бок, бампер, капот, стекло.
	_store_splat(local_hit, local_dir, amount, radius, stretch)
	_store_splat(Vector3(side * 0.55, bumper_point.y, bumper_point.z), Vector3(0.0, 0.12, 1.0), amount, radius * 1.15, stretch * 0.85)
	_store_splat(Vector3(side * 0.4, hood_point.y, hood_point.z), Vector3(0.0, 0.35, 0.8), amount * 0.9, radius * 1.05, stretch)
	_store_splat(Vector3(side * 0.28, glass_point.y, glass_point.z), Vector3(0.0, 0.45, 0.7), amount * 0.95, radius * 1.2, stretch * 0.7)
	_write_look()
	_write_splats()
	_attach_to_body(car)
	_add_decal(car, local_hit, Vector3(-local_hit.x, 0.1, -local_hit.z), radius * 1.6)
	_add_decal(car, Vector3(side * 0.45, bumper_point.y, bumper_point.z), Vector3(0.0, 0.08, -1.0), radius * 1.8)
	_add_decal(car, Vector3(side * 0.3, hood_point.y, hood_point.z), Vector3(0.0, -1.0, -0.15), radius * 1.5)
	_add_decal(car, Vector3(side * 0.22, glass_point.y, glass_point.z), Vector3(0.0, -0.2, -1.0), radius * 1.7)
	_ensure_glass_smear(car, side)


func update(car: Node3D) -> void:
	if _material == null or car == null:
		return
	_material.set_shader_parameter("world_to_car", car.global_transform.affine_inverse())


## Одноразовый всплеск из сцены blood_burst. scene — переопределение с человека.
## host — машина: облако едет с ней и прячется о коллизию кузова.
static func spray(host: Node, world_point: Vector3, world_velocity: Vector3, scene: PackedScene = null) -> void:
	if host == null or not is_instance_valid(host):
		return
	var packed: PackedScene = scene
	if packed == null and ResourceLoader.exists(DEFAULT_BURST):
		packed = load(DEFAULT_BURST) as PackedScene
	if packed == null:
		return
	var burst := packed.instantiate() as Node3D
	if burst == null:
		return
	host.add_child(burst)
	burst.top_level = false
	burst.global_position = world_point
	if host is Node3D:
		ensure_particle_blocker(host as Node3D)
	var away := Vector3.ZERO
	if host is Node3D:
		away = world_point - (host as Node3D).global_position
	if burst.has_method("play"):
		burst.call("play", world_velocity, away)


static func ensure_particle_blocker(car: Node3D) -> void:
	if car == null or not is_instance_valid(car):
		return
	if car.get_node_or_null(BLOCKER_NAME) != null:
		return
	var blocker := GPUParticlesCollisionBox3D.new()
	blocker.name = BLOCKER_NAME
	# Чуть уже точки выброса сбоку (±1.35 м), чтобы капли не гасли в момент удара.
	blocker.size = Vector3(1.85, 1.35, 4.35)
	blocker.position = Vector3(0.0, 0.52, 0.05)
	car.add_child(blocker)


func _store_splat(local_point: Vector3, local_dir: Vector3, amount: float, radius: float, stretch: float) -> void:
	var point: Vector3 = Vector3(
		clampf(local_point.x, splat_min.x, splat_max.x),
		clampf(local_point.y, splat_min.y, splat_max.y),
		clampf(local_point.z, splat_min.z, splat_max.z)
	)
	var direction: Vector3 = local_dir
	if direction.length() < 0.2:
		direction = Vector3(0.0, 0.15, 1.0)
	direction = direction.normalized()
	var index: int = _next_splat
	_next_splat = (_next_splat + 1) % SPLAT_CAP
	_splat_pos[index] = point
	_splat_dir[index] = direction
	_splat_data[index] = Vector4(amount, radius, stretch, _rng.randf() * 31.0)


func _write_look() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("blood_color", Vector3(blood_color.r, blood_color.g, blood_color.b))
	_material.set_shader_parameter("blood_gloss", blood_gloss)


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
		var layer := mesh.get_node_or_null(LAYER_NAME) as MeshInstance3D
		if layer == null:
			layer = MeshInstance3D.new()
			layer.name = LAYER_NAME
			mesh.add_child(layer)
			layer.mesh = mesh.mesh
			layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			layer.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			layer.position = Vector3.ZERO
			layer.rotation = Vector3.ZERO
			layer.scale = Vector3.ONE
			layer.extra_cull_margin = 0.45
		layer.material_override = _material


func _add_decal(car: Node3D, local_point: Vector3, into: Vector3, span: float) -> void:
	if car == null:
		return
	var inward: Vector3 = into
	if inward.length() < 0.08:
		inward = Vector3(0.0, 0.0, -1.0)
	inward = inward.normalized()
	var decal: Decal
	if _decals.size() < DECAL_CAP:
		decal = Decal.new()
		decal.name = "BloodDecal%d" % _decals.size()
		decal.texture_albedo = _stain_texture()
		decal.cull_mask = 0xFFFFF
		car.add_child(decal)
		_decals.append(decal)
	else:
		decal = _decals[_next_decal]
		_next_decal = (_next_decal + 1) % _decals.size()
	decal.modulate = Color(blood_color.r, blood_color.g, blood_color.b, 0.92)
	decal.albedo_mix = 0.9
	decal.normal_fade = 0.55
	decal.upper_fade = 0.35
	decal.lower_fade = 0.35
	var y_axis: Vector3 = -inward
	var x_axis: Vector3 = y_axis.cross(Vector3.UP)
	if x_axis.length_squared() < 0.04:
		x_axis = y_axis.cross(Vector3.FORWARD)
	x_axis = x_axis.normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	decal.transform = Transform3D(Basis(x_axis, y_axis, z_axis), local_point - inward * 0.1)
	var extent: float = clampf(span, 0.45, 1.35)
	decal.size = Vector3(extent, 0.42, extent * 0.72)


func _ensure_glass_smear(car: Node3D, local_x: float) -> void:
	var smear := car.get_node_or_null(GLASS_NAME) as MeshInstance3D
	if smear == null:
		smear = MeshInstance3D.new()
		smear.name = GLASS_NAME
		var quad := QuadMesh.new()
		quad.size = glass_extent
		var paint := ShaderMaterial.new()
		paint.shader = load("res://shaders/blood_puddle.gdshader") as Shader
		quad.material = paint
		smear.mesh = quad
		smear.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		smear.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		car.add_child(smear)
	var paint_mat := (smear.mesh as QuadMesh).material as ShaderMaterial
	if paint_mat != null:
		paint_mat.set_shader_parameter(
			"blood_color",
			Color(blood_color.r, blood_color.g, blood_color.b, 0.7)
		)
	smear.position = Vector3(clampf(local_x, -0.38, 0.38), glass_point.y, glass_point.z)
	smear.rotation_degrees = Vector3(-16.0, 0.0, 0.0)


func _stain_texture() -> Texture2D:
	if _stain_tex != null:
		return _stain_tex
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.2, 0.55, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.45, 0.03, 0.045, 0.95),
		Color(0.34, 0.02, 0.03, 0.72),
		Color(0.2, 0.01, 0.02, 0.28),
		Color(0.08, 0.0, 0.0, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	_stain_tex = tex
	return _stain_tex


func _body_meshes(car: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	_collect_meshes(car, car, result)
	return result


func _collect_meshes(node: Node, car: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if String(mesh_node.name) != LAYER_NAME and String(mesh_node.name) != GLASS_NAME:
			if not _is_skipped(mesh_node, car):
				var mesh_id := String(mesh_node.name)
				var matches := body_prefixes.is_empty()
				for prefix in body_prefixes:
					if mesh_id.begins_with(String(prefix)):
						matches = true
						break
				if matches or mesh_node.material_overlay != null:
					result.append(mesh_node)
	for child in node.get_children():
		_collect_meshes(child, car, result)


func _is_skipped(mesh_node: Node, car: Node) -> bool:
	var cursor: Node = mesh_node
	while cursor != null and cursor != car:
		var part := String(cursor.name).to_lower()
		for token in body_skip:
			if part.find(String(token)) >= 0:
				return true
		cursor = cursor.get_parent()
	return false
