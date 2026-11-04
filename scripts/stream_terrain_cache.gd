## Bounded FIFO cache of terrain grid samples shared by consecutive tile jobs.
## Access belongs to exactly one worker (or the Web main thread), never both.
extends RefCounted

const LIMIT := 16384
var _values: Dictionary = {}
var _order: Array[Vector2i] = []
var _next: int = 0
var hits: int = 0
var misses: int = 0


func get_sample(key: Vector2i):
	if _values.has(key):
		hits += 1
		return _values[key]
	misses += 1
	return null


func put_sample(key: Vector2i, value: Vector3) -> void:
	if _values.has(key):
		_values[key] = value
		return
	if _order.size() < LIMIT:
		_order.append(key)
	else:
		_values.erase(_order[_next])
		_order[_next] = key
		_next = (_next + 1) % LIMIT
	_values[key] = value
