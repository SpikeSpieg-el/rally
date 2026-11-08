## Дворники лобового стекла для вида из кабины. Геометрия живёт отдельной
## сценой `scenes/effects/windshield_wipers.tscn` (рукояти и щётки — узлы,
## правятся в редакторе), а скрипт только водит ими по стеклу:
##   * щётки стоят на месте, пока стекло чистое;
##   * как только на стекле появляется кровь — сам, без клавиш, запускает
##     цикл проходов (нужен вид из кабины, set_viewing от машины);
##   * каждый завершённый проход стирает долю крови через
##     RallyBloodFx.wipe_glass, пока стекло не станет чистым.
## В машину ставится узлом Wipers: его transform указывает на низ
## лобового стекла, пивоты внутри сцены уже наклонены под стекло.
@tool
class_name RallyWindshieldWipers
extends Node3D

@export_group("Движение")
## Угол щётки, прижатой к кромке («на месте»), °.
@export_range(45.0, 170.0, 1.0, "suffix:°") var park_degrees: float = 118.0
## Угол крайнего подъёма, ° (0 — щётка вдоль стекла вверх).
@export_range(-60.0, 45.0, 1.0, "suffix:°") var top_degrees: float = -12.0
## Сколько секунд занимает полный проход туда-обратно.
@export_range(0.2, 3.0, 0.05, "suffix:с") var pass_seconds: float = 0.7
## Проходов в цикле, пока кровь не ототрётся до конца.
@export_range(1, 12, 1) var passes_per_cycle: int = 5

@export_group("Стирание")
## Доля крови, которую убирает один проход.
@export_range(0.05, 1.0, 0.05) var wipe_per_pass: float = 0.5
## Пробный косметический проход каждые N секунд. 0 — только по крови.
## У сцены без машины (F6-превью) минимум 6 с, чтобы движение было видно.
@export_range(0.0, 120.0, 0.5, "suffix:с") var idle_interval: float = 0.0

@export_group("Узлы")
@export var left_path: NodePath = ^"WiperLeft"
@export var right_path: NodePath = ^"WiperRight"

var _car: Node3D = null
var _wiper_left: Node3D = null
var _wiper_right: Node3D = null
var _left_basis := Basis.IDENTITY
var _right_basis := Basis.IDENTITY
var _viewing: bool = false
var _sweeping: bool = false
var _cleaning: bool = false
var _pass_index: int = 0
var _sweep_phase: float = 0.0
var _idle_clock: float = 0.0


func _ready() -> void:
	_wiper_left = get_node_or_null(left_path) as Node3D
	_wiper_right = get_node_or_null(right_path) as Node3D
	if _wiper_left != null:
		_left_basis = _wiper_left.transform.basis
	if _wiper_right != null:
		_right_basis = _wiper_right.transform.basis
	_apply(deg_to_rad(park_degrees))
	set_process(not Engine.is_editor_hint())


## Вызывает машина: машина-хозяин нужна, чтобы найти пульт крови BloodFx.
func setup(car: Node3D) -> void:
	_car = car


## Вызывает машина: смотрим ли сейчас из кабины. Дворники стирают кровь
## только «в кадре» — переключились на вид сзади, щётки встают на место.
func set_viewing(on: bool) -> void:
	_viewing = on
	if not on:
		_idle_clock = 0.0
		if _sweeping:
			_park_now()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not _viewing and _car != null:
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
		# Полный проход туда-обратно завершён — стереть очередную долю.
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


## Угол в радианах: левая щётка с ним, правая — зеркально.
func _apply(angle: float) -> void:
	if _wiper_left != null:
		_wiper_left.transform.basis = _left_basis * Basis(Vector3.BACK, angle)
	if _wiper_right != null:
		_wiper_right.transform.basis = _right_basis * Basis(Vector3.BACK, -angle)


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
		return null
	return _car.get_node_or_null("BloodFx")
