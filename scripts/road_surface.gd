## Локальное состояние грунта. Не меняет тяжёлую коллизионную сетку:
## глубина колеи учитывается в контакте подвески каждого колеса.
## Ограниченная разреженная сетка, билинейная выборка без новых raycast.
##
## Размер ячейки, предел памяти, глубины, влияние наката и колеи на сцепление —
## всё это поля RallyFxProfile (data/stage/default_fx_profile.tres).
extends RefCounted

const FxProfileType = preload("res://scripts/data/rally_fx_profile.gd")

const CELL_SIZE := 0.4
const MAX_CELLS := 24000

## Профиль физики грунта. Пусто — заводские значения.
var fx: FxProfileType = null
var cells: Dictionary = {}
var _order: Array[Vector2i] = []
var _head := 0


func _p(name: String, fallback: float) -> float:
	return float(fx.get(name)) if fx != null else fallback


func cell_size() -> float:
	return maxf(0.05, _p("surface_cell_size", CELL_SIZE))


func max_cells() -> int:
	return maxi(64, int(_p("surface_max_cells", MAX_CELLS)))


func surface_kind(name: String, grass: bool, snow: float) -> String:
	var lower := name.to_lower()
	if snow > 0.45 or "снег" in lower or "snow" in lower or "ice" in lower:
		return "snow"
	if grass:
		return "grass"
	if "асфальт" in lower or "asphalt" in lower or "tarmac" in lower:
		return "asphalt"
	if "гряз" in lower or "mud" in lower:
		return "mud"
	return "gravel"


func _weights(point: Vector3) -> Dictionary:
	var grid := Vector2(point.x, point.z) / cell_size()
	var base := Vector2i(floori(grid.x), floori(grid.y))
	var f := grid - Vector2(base)
	return {base: (1.0 - f.x) * (1.0 - f.y), base + Vector2i.RIGHT: f.x * (1.0 - f.y), base + Vector2i.DOWN: (1.0 - f.x) * f.y, base + Vector2i.ONE: f.x * f.y}


func sample(point: Vector3, kind: String, wetness: float) -> Dictionary:
	var state := Vector2.ZERO # x — уплотнение, y — разрыхление/колея
	if kind != "asphalt":
		var weights := _weights(point)
		for key in weights:
			state += Vector2(cells.get(key, Vector2.ZERO)) * float(weights[key])
	var soft := kind == "mud" or kind == "snow"
	var max_depth := _p("depth_soft", 0.065) if soft else _p("depth_firm", 0.018)
	if kind == "grass":
		max_depth = _p("depth_grass", 0.035)
	var depth_wet: float = lerpf(_p("depth_dry_scale", 0.6), _p("depth_wet_scale", 1.0), wetness)
	var depth := state.y * max_depth * depth_wet if kind != "snow" else state.y * max_depth
	# Накат сухого гравия держит лучше, мокрая колея — хуже.
	var packing_grip: float = _p("packing_grip_other", -0.10)
	if kind == "gravel":
		packing_grip = _p("packing_grip_gravel", 0.08)
	# Снег ведёт себя наоборот: укатанная линия «схватывается» и держит лучше
	# свежей каши, а не хуже (раньше снег получал общий минус, как грязь, — и
	# дорога становилась ледяной).
	if kind == "snow":
		packing_grip = _p("packing_grip_snow", 0.22)
	if kind == "asphalt":
		return {"grip": 1.0, "rolling": 1.0, "depth": 0.0, "compaction": 0.0}
	var rut_loss: float = lerpf(_p("rut_grip_loss_dry", 0.04), _p("rut_grip_loss_wet", 0.18), wetness)
	# Рыхлый снег тормозит машину куда меньше грязи: иначе колесо буксует на
	# месте и машина не может тронуться.
	var rut_rolling: float = _p("rut_rolling_soft", 1.8) if soft else _p("rut_rolling_firm", 0.7)
	if kind == "snow":
		rut_rolling = _p("rut_rolling_snow", 0.55)
	# Нижний предел сцепления: у снега он выше, чтобы колея не превращала
	# полотно в каток.
	var grip_floor: float = _p("grip_min", 0.65)
	if kind == "snow":
		grip_floor = _p("grip_min_snow", 0.82)
	var grip: float = clampf(
		1.0 + state.x * packing_grip - state.y * rut_loss, grip_floor, _p("grip_max", 1.12)
	)
	return {
		"grip": grip,
		"rolling": clampf(
			1.0 - state.x * _p("packing_rolling_gain", 0.16) + state.y * rut_rolling,
			_p("rolling_min", 0.8),
			_p("rolling_max", 2.8)
		),
		"depth": depth,
		"compaction": state.x,
	}


func imprint(point: Vector3, kind: String, load_ratio: float, slip: float, speed: float, delta: float) -> void:
	if kind == "asphalt" or speed < 0.3 or load_ratio <= 0.0 or delta <= 0.0:
		return
	# Нагрузка ограничена: удар после прыжка не создаёт мгновенную яму.
	var work := minf(delta, _p("imprint_delta_limit", 0.05)) \
		* clampf(load_ratio, 0.0, _p("imprint_load_limit", 2.5)) \
		* clampf(speed / maxf(0.01, _p("imprint_speed_scale", 5.0)), 0.0, _p("imprint_speed_limit", 2.0))
	var weights := _weights(point)
	var limit := max_cells()
	for key in weights:
		if weights[key] <= 0.00001:
			continue
		if not cells.has(key):
			if cells.size() >= limit:
				cells.erase(_order[_head])
				_head += 1
			cells[key] = Vector2.ZERO
			_order.append(key)
		var state: Vector2 = cells[key]
		var amount: float = work * weights[key]
		state.x = clampf(state.x + amount * _p("imprint_load_scale", 0.65), 0.0, 1.0)
		state.y = clampf(
			state.y + amount * (_p("imprint_slip_base", 0.12) + clampf(slip, 0.0, 2.0) * _p("imprint_slip_scale", 0.9)),
			0.0,
			1.0
		)
		cells[key] = state
	if _head > limit:
		_order = _order.slice(_head)
		_head = 0


func clear() -> void:
	cells.clear()
	_order.clear()
	_head = 0
