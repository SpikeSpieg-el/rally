## Вертолёт над ночным этапом: низкополигональный силуэт кружит вдалеке,
## мигает красным огоньком и шарит по земле конусом прожектора.
##
## Чистый фон: ни физики, ни света с тенями. Прожектор — фейковый
## полупрозрачный конус плюс один SpotLight3D без теней.
class_name RallyHelicopter
extends Node3D

var _anchor: Vector3 = Vector3.ZERO
var _radius: float = 130.0
var _height: float = 55.0
var _speed: float = 0.05
var _phase: float = 0.0
var _rotor: MeshInstance3D = null
var _beacon: MeshInstance3D = null
var _beacon_material: StandardMaterial3D = null
var _time: float = 0.0


func _box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = pos
	add_child(instance)
	return instance


## anchor — точка над трассой, вокруг которой описываются круги.
func setup(anchor: Vector3, rng_seed: int) -> void:
	_anchor = anchor
	_phase = float(rng_seed % 628) * 0.01
	var body_color := Color(0.16, 0.18, 0.20)
	_box(Vector3(2.2, 1.5, 4.6), Vector3.ZERO, body_color)
	_box(Vector3(0.5, 0.5, 4.2), Vector3(0.0, 0.35, -4.0), body_color)
	_box(Vector3(1.8, 0.9, 0.25), Vector3(0.0, 0.75, -6.0), body_color)
	_box(Vector3(1.9, 0.7, 1.6), Vector3(0.0, -0.15, 1.2), Color(0.35, 0.55, 0.65))
	_rotor = _box(Vector3(9.0, 0.06, 0.5), Vector3(0.0, 0.95, 0.3), Color(0.08, 0.08, 0.08))
	_beacon_material = StandardMaterial3D.new()
	_beacon_material.albedo_color = Color(1.0, 0.1, 0.08)
	_beacon_material.emission_enabled = true
	_beacon_material.emission = Color(1.0, 0.1, 0.08)
	_beacon_material.emission_energy_multiplier = 2.0
	var beacon_mesh := SphereMesh.new()
	beacon_mesh.radius = 0.22
	beacon_mesh.height = 0.44
	beacon_mesh.radial_segments = 6
	beacon_mesh.rings = 3
	beacon_mesh.surface_set_material(0, _beacon_material)
	_beacon = MeshInstance3D.new()
	_beacon.mesh = beacon_mesh
	_beacon.position = Vector3(0.0, 0.85, -1.5)
	add_child(_beacon)
	# Конус прожектора: фейковый объёмный луч в стиле PS1.
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.4
	cone_mesh.bottom_radius = 6.5
	cone_mesh.height = 34.0
	cone_mesh.radial_segments = 10
	var cone_material := StandardMaterial3D.new()
	cone_material.albedo_color = Color(1.0, 0.95, 0.75, 0.07)
	cone_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cone_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cone_material.cull_mode = BaseMaterial3D.CULL_MODE_DISABLED
	cone_mesh.surface_set_material(0, cone_material)
	var cone := MeshInstance3D.new()
	cone.mesh = cone_mesh
	cone.position = Vector3(2.5, -17.5, 1.5)
	cone.rotation.z = 0.12
	add_child(cone)
	var spot := SpotLight3D.new()
	spot.position = Vector3(2.5, -1.0, 1.5)
	spot.rotation_degrees = Vector3(-78.0, 0.0, 8.0)
	spot.light_color = Color(1.0, 0.95, 0.78)
	spot.light_energy = 1.2
	spot.spot_range = 70.0
	spot.spot_angle = 16.0
	spot.shadow_enabled = false
	add_child(spot)
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	_phase += delta * _speed
	var offset := Vector3(cos(_phase) * _radius, _height + sin(_time * 0.4) * 3.0, sin(_phase) * _radius)
	global_position = _anchor + offset
	# Нос — по касательной к кругу.
	rotation.y = -_phase
	if _rotor != null:
		_rotor.rotation.y += delta * 28.0
	if _beacon_material != null:
		var blink: float = 1.0 if fposmod(_time, 1.1) < 0.12 else 0.05
		_beacon_material.emission_energy_multiplier = 2.5 * blink
