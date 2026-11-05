## Профиль заполнения тематического участка. Все параметры доступны в инспекторе.
@tool
class_name RallySceneryBiome
extends Resource

@export var id: String = "forest"
@export var display_name: String = "Лес"
## Совместим с зонами RallySceneryPlacement: лес, скалы, поле, ралли.
@export_enum("Лес", "Скалы", "Поле", "Ралли") var zone: int = 0
@export_range(0.0, 4.0, 0.05) var cover_density: float = 1.0
@export var cover_size: Vector2 = Vector2(0.85, 1.15)
## Размер пятен в мировых метрах; плавный переход не привязан к чанкам.
@export_range(2.0, 100.0, 1.0) var patch_size: float = 18.0
## Минимальная плотность между пятнами: 1 — равномерное покрытие.
@export_range(0.0, 1.0, 0.05) var patch_floor: float = 0.3


func density_at(x: float, z: float, seed_value: int) -> float:
	var cell := Vector2(x, z) / maxf(2.0, patch_size)
	var base := Vector2i(floori(cell.x), floori(cell.y))
	var blend := Vector2(
		smoothstep(0.0, 1.0, cell.x - base.x), smoothstep(0.0, 1.0, cell.y - base.y)
	)
	var a := _noise(base, seed_value)
	var b := _noise(base + Vector2i(1, 0), seed_value)
	var c := _noise(base + Vector2i(0, 1), seed_value)
	var d := _noise(base + Vector2i.ONE, seed_value)
	return lerpf(patch_floor, 1.0, lerpf(lerpf(a, b, blend.x), lerpf(c, d, blend.x), blend.y))


func _noise(cell: Vector2i, seed_value: int) -> float:
	return float(posmod(hash(Vector3i(cell.x, cell.y, seed_value)), 65536)) / 65535.0
