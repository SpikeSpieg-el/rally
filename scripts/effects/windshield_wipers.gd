@tool
class_name RallyWindshieldWipers
extends Node3D

@export_group("Движение")
@export_range(-180.0, 180.0, 1.0, "suffix:°") var park_degrees: float = -82.0
@export_range(-180.0, 180.0, 1.0, "suffix:°") var top_degrees: float = 10.0
@export_range(0.2, 3.0, 0.05, "suffix:с") var pass_seconds: float = 0.7
@export_range(1, 12, 1) var passes_per_cycle: int = 5

@export_group("Стирание")
@export_range(0.05, 1.0, 0.05) var wipe_per_pass: float = 0.5
@export_range(0.0, 120.0, 0.5, "suffix:с") var idle_interval: float = 0.0

@export_group("Узлы")
@export var left_path: NodePath = ^"WiperLeft"
@export var right_path: NodePath = ^"WiperRight"

var _car: Node3D = null
var _wiper_left: Node3D = null
var _wiper_right: Node3D = null
var _viewing: bool = true
var _sweeping: bool = false
var _cleaning: bool = false
var _pass_index: int = 0
var _sweep_phase: float = 0.0
var _idle_clock: float = 0.0


func _ready() -> void:
	_wiper_left = get_node_or_null(left_path) as Node3D
	_wiper_right = get_node_or_null(right_path) as Node3D
	_apply(deg_to_rad(park_degrees))
	if not Engine.is_editor_hint():
		_auto_find_car()
	set_process(not Engine.is_editor_hint())


func setup(car: Node3D) -> void:
	_car = car


func set_viewing(on: bool) -> void:
	_viewing = on
	if not on:
		_idle_clock = 0.0
		if _sweeping:
			_park_now()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not _viewing:
		return
	if not _sweeping:
		if _blood_dirty():
			_begin(true)
			return
		var gap: float = idle_interval
		if _car == null:
			gap = maxf(idle_interval, 6.0)
		if gap <= 0.0:
			return
		_idle_clock += delta
		if _idle_clock < gap:
			return
		_begin(false)
		return
	_idle_clock = 0.0
	_sweep_phase += delta / maxf(pass_seconds, 0.05)
	if _sweep_phase >= 1.0:
		_sweep_phase = 0.0
		_pass_index += 1
		if _cleaning:
			_wipe_once()
		if _pass_index >= passes_per_cycle:
			if _cleaning and _blood_dirty():
				_pass_index = 0
			else:
				_park_now()
				return
	var swing: float = clampf(_sweep_phase * 2.0, 0.0, 2.0)
	var k: float = 1.0 - absf(swing - 1.0)
	k = k * k * (3.0 - 2.0 * k)
	_apply(lerpf(deg_to_rad(park_degrees), deg_to_rad(top_degrees), k))
	_notify_wiper_state(k, true, delta)


func _begin(cleaning: bool) -> void:
	_sweeping = true
	_cleaning = cleaning
	_pass_index = 0
	_sweep_phase = 0.0


func _park_now() -> void:
	_sweeping = false
	_cleaning = false
	_sweep_phase = 0.0
	_apply(deg_to_rad(park_degrees))
	_notify_wiper_state(0.0, false, 0.0)


func _apply(angle: float) -> void:
	if _wiper_left != null:
		_wiper_left.rotation = Vector3(0.0, 0.0, angle)
	if _wiper_right != null:
		_wiper_right.rotation = Vector3(0.0, 0.0, angle)


func _notify_wiper_state(k: float, active: bool, delta: float) -> void:
	var blood := _blood_fx()
	if blood != null and blood.has_method("set_wiper_state"):
		blood.call(
			"set_wiper_state",
			k,
			deg_to_rad(park_degrees),
			deg_to_rad(top_degrees),
			active,
			delta
		)


func _wipe_once() -> void:
	var blood := _blood_fx()
	if blood != null and blood.has_method("wipe_glass"):
		blood.call("wipe_glass", wipe_per_pass)


func _blood_dirty() -> bool:
	var blood := _blood_fx()
	if blood == null:
		return false
	return blood.has_method("glass_dirty") and bool(blood.call("glass_dirty"))


func _blood_fx() -> Node:
	if _car == null or not is_instance_valid(_car):
		_auto_find_car()
	if _car != null and is_instance_valid(_car):
		var fx := _car.get_node_or_null("BloodFx")
		if fx != null:
			return fx
		return _car.find_child("BloodFx", true, false)
	return null


func _auto_find_car() -> void:
	var p := get_parent()
	while p != null:
		if p is Node3D and (p.has_node("BloodFx") or p.has_node("Cameras") or p.has_node("RallyCockpit")):
			_car = p as Node3D
			return
		p = p.get_parent()
	if get_parent() is Node3D:
		_car = get_parent() as Node3D
