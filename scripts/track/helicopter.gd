## Вертолёт над ночным этапом. Вся геометрия — в сцене
## scenes/props/helicopter.tscn (кузов, ротор, маячок, конус прожектора и
## сам SpotLight3D правятся в редакторе); этот скрипт только оживляет её:
## кружит вокруг якоря, крутит ротор и мигает красным маячком.
##
## Ни физики, ни теней: чистый фоновый силуэт в стиле PS1.
class_name RallyHelicopter
extends Node3D

var _anchor: Vector3 = Vector3.ZERO
var _radius: float = 130.0
var _height: float = 55.0
var _speed: float = 0.05
var _phase: float = 0.0
var _rotor: MeshInstance3D = null
var _beacon_material: StandardMaterial3D = null
var _time: float = 0.0


## anchor — точка над трассой, вокруг которой описываются круги.
## Вызывать после добавления сцены в дерево этапа.
func setup(anchor: Vector3, rng_seed: int) -> void:
	_anchor = anchor
	_phase = float(rng_seed % 628) * 0.01
	_rotor = get_node_or_null("Rotor") as MeshInstance3D
	var beacon := get_node_or_null("Beacon") as MeshInstance3D
	if beacon != null and beacon.mesh != null:
		var material := beacon.mesh.surface_get_material(0) as StandardMaterial3D
		if material != null:
			# Свой экземпляр материала: мигание не должно трогать сцену-ресурс.
			_beacon_material = material.duplicate() as StandardMaterial3D
			beacon.material_override = _beacon_material
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
