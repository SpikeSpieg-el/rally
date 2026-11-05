## Детерминированная раскладка отбойника; не зависит от RNG, биомов и чанков.
class_name RallyGuardrailPlacement
extends RefCounted

const SECTION_LENGTH := 3.0


## Знак нормали к дороге на ВНЕШНЕЙ стороне поворота. 0 — не крутой поворот.
static func outer_side(network, distance: float, lookahead: float, threshold_deg: float) -> float:
	var start: float = maxf(0.0, distance - lookahead * 0.5)
	var end: float = minf(network.total_length, distance + lookahead * 0.5)
	var previous: Vector3 = network.direction_at(start)
	var turn := 0.0
	# Суммирование малых углов не переворачивает сторону на шпильке >180°.
	var steps: int = maxi(1, ceili((end - start) / 4.0))
	for i in range(1, steps + 1):
		var direction: Vector3 = network.direction_at(lerpf(start, end, float(i) / steps))
		var a: float = atan2(previous.x, previous.z)
		var b: float = atan2(direction.x, direction.z)
		turn += atan2(sin(b - a), cos(b - a))
		previous = direction
	if absf(turn) < deg_to_rad(threshold_deg):
		return 0.0
	# В S-связке соседняя шпилька не должна выбрать внутреннюю сторону
	# текущей дуги. Прямой заход допускаем, противоположный изгиб пропускаем.
	var before: Vector3 = network.direction_at(maxf(0.0, distance - 4.0))
	var after: Vector3 = network.direction_at(minf(network.total_length, distance + 4.0))
	var local_angle: float = atan2(after.x, after.z) - atan2(before.x, before.z)
	var local_turn: float = atan2(sin(local_angle), cos(local_angle))
	if absf(local_turn) > deg_to_rad(2.0) and local_turn * turn < 0.0:
		return 0.0
	return -signf(turn)


## Расстояние от КРАЯ ПОЛОТНА, а не от оси или края декоративного коридора.
static func offset_point(
	network, track, distance: float, side_sign: float, offset: float
) -> Vector3:
	var direction: Vector3 = network.direction_at(distance)
	var side := Vector3(direction.z, 0.0, -direction.x)
	return network.point_at(distance) + side * side_sign * (track.half_width_at(distance) + offset)


## Секции привязаны к глобальному километражу. Владелец — чанк с началом секции.
## Последняя секция может чуть заходить в следующий чанк, без дублей и щелей.
static func segment_ids(
	length: float, step: float, margin: float, start: float, end: float
) -> Array:
	var limit: float = length - margin if end < 0.0 else minf(end, length - margin)
	var first: int = ceili(maxf(margin, start) / maxf(0.5, step))
	var last: int = ceili(maxf(0.0, limit) / maxf(0.5, step))
	return range(first, maxi(first, last))


## Ось X растягивает трёхметровую секцию между двумя точками грунта.
## Y остаётся вертикальной: стойки не заваливаются даже на подъёме.
static func span_transform(a: Vector3, b: Vector3) -> Transform3D:
	var delta := b - a
	var across := Vector3(-delta.z, 0.0, delta.x).normalized()
	return Transform3D(Basis(delta / SECTION_LENGTH, Vector3.UP, across), (a + b) * 0.5)


## Физике нужна ортонормальная база, без сдвига/масштабирования визуала.
static func collision_transform(a: Vector3, b: Vector3) -> Transform3D:
	var along := (b - a).normalized()
	var across := Vector3(-along.z, 0.0, along.x).normalized()
	return Transform3D(Basis(along, across.cross(along), across), (a + b) * 0.5 + Vector3.UP * 0.55)
