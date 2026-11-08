## Пятна крови на кузове. Сцена `scenes/effects/blood_stains.tscn` — пульт:
## цвет, блеск, размер пятна, какие меши пачкать. Всплеск частиц живёт отдельно
## в `scenes/effects/blood_burst.tscn` и инстансируется при ударе.
@tool
class_name RallyBloodFx
extends Node

const BloodShader = preload("res://shaders/car_blood.gdshader")
const DEFAULT_BURST := "res://scenes/effects/blood_burst.tscn"
const SPLAT_CAP := 8

@export_group("Вкл и цвет")
@export var enabled: bool = true
@export var blood_color: Color = Color(0.40, 0.025, 0.04, 1.0)
@export_range(0.0, 1.0, 0.01) var blood_gloss: float = 0.42
@export_multiline var description: String = "Пятна на кузове после удара. Всплеск — сцена Blood Burst."

@export_group("Всплеск")
## Сцена GPU-частиц. Пусто — res://scenes/effects/blood_burst.tscn.
@export var burst_scene: PackedScene

@export_group("Какие меши пачкать")
@export var body_prefixes: PackedStringArray = PackedStringArray(["Mitsubishi_Body"])
@export var body_skip: PackedStringArray = PackedStringArray(
	["wheel", "glass", "window", "light", "disc", "tire", "cabin", "seat", "mirror"]
)

@export_group("Размер пятна от скорости")
## Непрозрачность: x при низкой скорости, y добавка за м/с.
@export var amount_from_speed: Vector2 = Vector2(0.62, 0.014)
@export var radius_from_speed: Vector2 = Vector2(0.20, 0.005)
@export var stretch_from_speed: Vector2 = Vector2(1.15, 0.045)
@export var amount_limits: Vector2 = Vector2(0.5, 1.0)
@export var radius_limits: Vector2 = Vector2(0.16, 0.58)
@export var stretch_limits: Vector2 = Vector2(1.1, 3.6)

@export_group("Куда класть на кузове")
@export var splat_min: Vector3 = Vector3(-0.98, 0.10, -2.20)
@export var splat_max: Vector3 = Vector3(0.98, 1.08, 2.20)

var _material: ShaderMaterial
var _splat_pos: Array[Vector3] = []
var _splat_dir: Array[Vector3] = []
var _splat_data: Array[Vector4] = []
var _next_splat: int = 0
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


func add_splat(car: Node3D, world_point: Vector3, world_velocity: Vector3) -> void:
	if not enabled:
		return
	if _material == null:
		install(car)
	var local_point: Vector3 = car.to_local(world_point)
	local_point.x = clampf(local_point.x, splat_min.x, splat_max.x)
	local_point.y = clampf(local_point.y, splat_min.y, splat_max.y)
	local_point.z = clampf(local_point.z, splat_min.z, splat_max.z)
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
		clampf(amount_from_speed.x + speed * amount_from_speed.y, amount_limits.x, amount_limits.y),
		clampf(radius_from_speed.x + speed * radius_from_speed.y, radius_limits.x, radius_limits.y),
		clampf(stretch_from_speed.x + speed * stretch_from_speed.y, stretch_limits.x, stretch_limits.y),
		_rng.randf() * 31.0
	)
	_write_look()
	_write_splats()
	_attach_to_body(car)


func update(car: Node3D) -> void:
	if _material == null or car == null:
		return
	_material.set_shader_parameter("world_to_car", car.global_transform.affine_inverse())


## Одноразовый всплеск из сцены blood_burst. scene — переопределение с человека.
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
	burst.top_level = true
	burst.global_position = world_point
	if burst.has_method("play"):
		burst.call("play", world_velocity)


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
