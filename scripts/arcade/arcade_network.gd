## Растущая дорожная сеть аркадного режима: то же API, что у RoadNetwork
## (`point_at`, `direction_at`, `height_at_along`, `distance_to_road`,
## `along_road`), но дорога НЕ конечна.
##
## Зачем отдельный класс. `RoadNetwork` — это Curve3D, запечённый целиком:
## у бесконечной трассы кривая росла бы вместе с пробегом, и на 300-м км в
## памяти лежали бы все 300 км. Здесь геометрия берётся из `RallyArcadeRoad`
## по запросу, а кэш держит только окно вокруг машины: генератор O(1) на
## участок, память O(окно), а не O(пробег).
##
## Совместимость с этапом. `total_length` растёт по `ensure_length()`; этап
## спрашивает `point_at`/`height_at_along` в пределах `total_length`, поэтому
## финиш, мини-карта и стример продолжают работать без изменений — но только
## после того, как финиш отключён в конфиге аркадной трассы.
class_name RallyArcadeNetwork
extends RefCounted

const RoadType = preload("res://scripts/arcade/arcade_road.gd")

## Сколько метров за концом построенной дороги: нужен запас для запросов
## «чуть впереди» (камера, физика, стример), иначе на границе будет ноль.
const LOOKAHEAD_MARGIN: float = 400.0
## Шаг точек кэша, м. 2 м — тот же шаг, с которым генератор строит участки.
const STEP: float = 2.0

var track_seed: int = 0
## Пробег, до которого сеть «обеспечивает» дорогу.
var total_length: float = 0.0
var bounds: Rect2 = Rect2()

var _points := PackedVector3Array()
var _dists := PackedFloat32Array()
var _dirs := PackedVector3Array()
var _built_to: float = 0.0


func _init(seed_value: int = 0) -> void:
	track_seed = seed_value
	RoadType.reset(seed_value)
	var start: Dictionary = RoadType.leg_start_state(0, seed_value)
	_points.append(Vector3(float(start.x), RoadType.elevation_at(0.0, seed_value), float(start.z)))
	_dists.append(0.0)
	_dirs.append(Vector3(cos(float(start.heading)), 0.0, sin(float(start.heading))))
	ensure_length(0.0)


## Достроить геометрию до `distance` метров (с запасом LOOKAHEAD_MARGIN).
## Возвращает новое значение total_length.
func ensure_length(distance: float) -> float:
	var need: float = maxf(distance + LOOKAHEAD_MARGIN, total_length)
	if need > _built_to:
		_build_to(need)
	total_length = maxf(total_length, need)
	return total_length


func _build_to(distance: float) -> void:
	var leg_index: int = RoadType.leg_index_at(_built_to)
	while _built_to < distance:
		var built: RoadType.Leg = RoadType.leg(leg_index, track_seed)
		# Первая точка участка совпадает с уже записанной — пропускаем её,
		# иначе на стыке появится дубль с нулевым шагом.
		var first: int = 1 if _dists.size() > 0 and absf(built.along[0] - _built_to) < 0.001 else 0
		for i in range(first, built.points.size()):
			var d: float = built.along[i]
			if d <= _built_to + 0.001:
				continue
			_points.append(built.points[i])
			_dists.append(d)
			var prev: Vector3 = _points[_points.size() - 2]
			var here: Vector3 = built.points[i]
			var side: Vector3 = Vector3(here.x - prev.x, 0.0, here.z - prev.z)
			if side.length_squared() < 0.000001:
				side = _dirs[_dirs.size() - 1]
			_dirs.append(side.normalized())
		_built_to = float(built.end_along())
		leg_index += 1
	bounds = bounds.expand(_points[_points.size() - 1])


func built_metres() -> float:
	return _built_to


# --------------------------------------------------------------- запросы


func _index_at(distance: float) -> int:
	var high: int = _dists.size() - 1
	if high <= 0:
		return 0
	if distance <= 0.0:
		return 0
	if distance >= _dists[high]:
		return high
	var low: int = 0
	while low < high - 1:
		var mid: int = (low + high) >> 1
		if _dists[mid] <= distance:
			low = mid
		else:
			high = mid
	return low


func point_at(distance: float) -> Vector3:
	ensure_length(distance)
	if _points.is_empty():
		return Vector3.ZERO
	var i: int = _index_at(distance)
	var j: int = mini(i + 1, _points.size() - 1)
	var a: float = _dists[i]
	var b: float = _dists[j]
	var t: float = 0.0 if b <= a else clampf((distance - a) / (b - a), 0.0, 1.0)
	return _points[i].lerp(_points[j], t)


func height_at_along(distance: float) -> float:
	if _dists.is_empty():
		return 0.0
	# Высота — чистая функция километража: её не нужно достраивать, и она
	# определена даже «впереди» собранного меша.
	return RoadType.elevation_at(distance, track_seed)


func direction_at(distance: float) -> Vector3:
	ensure_length(distance)
	if _dirs.size() < 2:
		return Vector3.FORWARD
	var i: int = _index_at(distance)
	var k: int = maxi(0, i - 1)
	var j: int = mini(i + 2, _dirs.size() - 1)
	var dir: Vector3 = Vector3(_points[j].x - _points[k].x, 0.0, _points[j].z - _points[k].z)
	if dir.length_squared() < 0.000001:
		dir = _dirs[i]
	if dir.length_squared() < 0.000001:
		return Vector3.FORWARD
	return dir.normalized()


## Половина ширины полотна на километраже.
func half_width_at(distance: float) -> float:
	return RoadType.half_width_at(distance, track_seed)


## Ближайшая точка полотна: (distance, along). Перебор по кэшу ограничен
## окном вокруг подсказки — полный проход по 100 км дороги был бы недопустим.
## `hint` — прошлый километраж; без подсказки ищется по всему кэшу, что дорого
## и нужно только при телепорте.
func nearest(x: float, z: float, hint: float = -1.0) -> Vector2:
	ensure_length(maxf(hint, 0.0))
	if _points.size() < 2:
		return Vector2(0.0, 0.0)
	var best_d: float = INF
	var best_along: float = 0.0
	var step_index: int = maxi(1, int(20.0 / STEP))
	var low: int = 0
	var high: int = _points.size() - 1
	if hint >= 0.0:
		low = maxi(0, _index_at(hint) - 200)
		high = mini(_points.size() - 1, _index_at(hint) + 400)
	var i: int = low
	while i <= high:
		var p: Vector3 = _points[i]
		var d: float = Vector2(p.x - x, p.z - z).length_squared()
		if d < best_d:
			best_d = d
			best_along = _dists[i]
		i += step_index
	# Уточнение по соседям найденной точки — грубый шаг мог перескочить.
	var fine: int = _index_at(best_along)
	for j in range(maxi(0, fine - step_index), mini(_points.size(), fine + step_index + 1)):
		var p2: Vector3 = _points[j]
		var d2: float = Vector2(p2.x - x, p2.z - z).length_squared()
		if d2 < best_d:
			best_d = d2
			best_along = _dists[j]
	return Vector2(sqrt(best_d), best_along)


## Совместимость с RoadNetwork: расстояние до полотна.
func distance_to_road(x: float, z: float) -> float:
	return nearest(x, z, -1.0).x


## Совместимость с RoadNetwork: километраж ближайшей точки полотна.
func along_road(x: float, z: float) -> float:
	return nearest(x, z, -1.0).y


## Совместимость с RoadNetwork: база рельефа. У аркады региональный рельеф —
## это высота дороги, размытая по километражу: так земля рядом с полотном не
## «отваливается» вниз на серпантине, где полотно само поднимается.
func regional_height(x: float, z: float) -> float:
	var sample: Vector2 = nearest(x, z, -1.0)
	return RoadType.elevation_at(sample.y, track_seed)


## Ближайшая точка полотна: (distance, along). Перебор по кэшу ограничен
## окном вокруг подсказки — полный проход по 100 км дороги был бы недопустим.
## `hint` — прошлый километраж; без подсказки ищется по всему кэшу, что дорого
## и нужно только при телепорте.
func nearest(x: float, z: float, hint: float = -1.0) -> Vector2:
	ensure_length(maxf(hint, 0.0))
	if _points.size() < 2:
		return Vector2(0.0, 0.0)
	var best_d: float = INF
	var best_along: float = 0.0
	var step_index: int = maxi(1, int(20.0 / STEP))
	var low: int = 0
	var high: int = _points.size() - 1
	if hint >= 0.0:
		low = maxi(0, _index_at(hint) - 200)
		high = mini(_points.size() - 1, _index_at(hint) + 400)
	var i: int = low
	while i <= high:
		var p: Vector3 = _points[i]
		var d: float = Vector2(p.x - x, p.z - z).length_squared()
		if d < best_d:
			best_d = d
			best_along = _dists[i]
		i += step_index
	# Уточнение по соседям найденной точки — грубый шаг мог перескочить.
	var fine: int = _index_at(best_along)
	for j in range(maxi(0, fine - step_index), mini(_points.size(), fine + step_index + 1)):
		var p2: Vector3 = _points[j]
		var d2: float = Vector2(p2.x - x, p2.z - z).length_squared()
		if d2 < best_d:
			best_d = d2
			best_along = _dists[j]
	return Vector2(sqrt(best_d), best_along)


## Совместимость с RoadNetwork: расстояние до полотна.
func distance_to_road(x: float, z: float) -> float:
	return nearest(x, z, -1.0).x


## Совместимость с RoadNetwork: километраж ближайшей точки полотна.
func along_road(x: float, z: float) -> float:
	return nearest(x, z, -1.0).y


## Совместимость с RoadNetwork: база рельефа. У аркады региональный рельеф —
## это высота дороги, размытая по километражу: так земля рядом с полотном не
## «отваливается» вниз на серпантине, где полотно само поднимается.
func regional_height(x: float, z: float) -> float:
	var sample: Vector2 = nearest(x, z, -1.0)
	return RoadType.elevation_at(sample.y, track_seed)


## Снимок для рабочего потока: массивы только читаются, поэтому копировать их
## не нужно — новый объект делит их с этим (как `sparse_reader` у RoadNetwork).
## Собирается через `_from_shared`, а не через `new()`: конструктор достраивает
## дорогу под старт, а снимку это не нужно.
static func reader_of(source: RallyArcadeNetwork) -> RallyArcadeNetwork:
	var copy := RallyArcadeNetwork._from_shared()
	copy.track_seed = source.track_seed
	copy._points = source._points
	copy._dists = source._dists
	copy._dirs = source._dirs
	copy._built_to = source._built_to
	copy.total_length = source.total_length
	copy.bounds = source.bounds
	return copy


## Пустой объект без геометрии и без запросов к генератору.
static func _from_shared() -> RallyArcadeNetwork:
	var empty := RallyArcadeNetwork.new(0)
	return empty
