## Семантические участки и пространственная сетка свободного места.
## Не зависит от порядка видов в библиотеке и не использует глобальный RNG.
class_name RallySceneryPlacement
extends RefCounted

const CELL_SIZE := 12.0
var occupied: Dictionary = {}

static func zone_at(distance: float, side_sign: float, seed_value: int) -> int:
	var block := int(floor(distance / 120.0))
	return int(posmod(hash(Vector3i(block, int(side_sign), seed_value)), 4))

static func allows(prop: RallyProp, zone: int) -> bool:
	match prop.category:
		RallyProp.Category.FOREST:
			return zone == 0
		RallyProp.Category.VEGETATION:
			return true
		RallyProp.Category.ROCKS:
			return zone == 1
		RallyProp.Category.FIELD, RallyProp.Category.FENCE:
			return zone == 2
		RallyProp.Category.RALLY:
			return zone == 3
	return false

func has_space(point: Vector3, radius: float) -> bool:
	var cell := Vector2i(floori(point.x / CELL_SIZE), floori(point.z / CELL_SIZE))
	# Радиусы ограничены размером ячейки при регистрации.
	for x in range(-2, 3):
		for z in range(-2, 3):
			for entry in occupied.get(cell + Vector2i(x, z), []):
				var delta := Vector2(point.x - entry.x, point.z - entry.y)
				if delta.length_squared() < pow(radius + entry.z, 2.0):
					return false
	return true

func reserve(point: Vector3, radius: float) -> void:
	var cell := Vector2i(floori(point.x / CELL_SIZE), floori(point.z / CELL_SIZE))
	if not occupied.has(cell):
		occupied[cell] = []
	occupied[cell].append(Vector3(point.x, point.z, radius))
