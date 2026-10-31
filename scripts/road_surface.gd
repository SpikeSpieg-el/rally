## Локальное состояние грунта. Не меняет тяжёлую коллизионную сетку:
## глубина колеи учитывается в контакте подвески каждого колеса.
## Ограниченная разреженная сетка, билинейная выборка без новых raycast.
extends RefCounted

const CELL_SIZE := 0.4
const MAX_CELLS := 24000
var cells: Dictionary = {}
var _order: Array[Vector2i] = []
var _head := 0


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
	var grid := Vector2(point.x, point.z) / CELL_SIZE
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
	var max_depth := 0.065 if soft else 0.018
	if kind == "grass":
		max_depth = 0.035
	var depth := state.y * max_depth * lerpf(0.6, 1.0, wetness) if kind != "snow" else state.y * max_depth
	# Накат сухого гравия держит лучше, мокрая колея и укатанный снег — хуже.
	var packing_grip := 0.08 if kind == "gravel" else -0.10
	if kind == "asphalt":
		return {"grip": 1.0, "rolling": 1.0, "depth": 0.0, "compaction": 0.0}
	return {
		"grip": clampf(1.0 + state.x * packing_grip - state.y * lerpf(0.04, 0.18, wetness), 0.65, 1.12),
		"rolling": clampf(1.0 - state.x * 0.16 + state.y * (1.8 if soft else 0.7), 0.8, 2.8),
		"depth": depth,
		"compaction": state.x,
	}


func imprint(point: Vector3, kind: String, load_ratio: float, slip: float, speed: float, delta: float) -> void:
	if kind == "asphalt" or speed < 0.3 or load_ratio <= 0.0 or delta <= 0.0:
		return
	# Нагрузка ограничена: удар после прыжка не создаёт мгновенную яму.
	var work := minf(delta, 0.05) * clampf(load_ratio, 0.0, 2.5) * clampf(speed / 5.0, 0.0, 2.0)
	var weights := _weights(point)
	for key in weights:
		if weights[key] <= 0.00001:
			continue
		if not cells.has(key):
			if cells.size() >= MAX_CELLS:
				cells.erase(_order[_head])
				_head += 1
			cells[key] = Vector2.ZERO
			_order.append(key)
		var state: Vector2 = cells[key]
		var amount: float = work * weights[key]
		state.x = clampf(state.x + amount * 0.65, 0.0, 1.0)
		state.y = clampf(state.y + amount * (0.12 + clampf(slip, 0.0, 2.0) * 0.9), 0.0, 1.0)
		cells[key] = state
	if _head > MAX_CELLS:
		_order = _order.slice(_head)
		_head = 0


func clear() -> void:
	cells.clear()
	_order.clear()
	_head = 0
