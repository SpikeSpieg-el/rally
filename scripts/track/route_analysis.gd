## Числовая «анатомия» трассы для редактора и предпросмотра.
##
## Здесь нет ни одной настройки: пороги приходят аргументами из
## RallyTrackStudioSettings. Класс считается только по Curve3D и поэтому
## проверяется headless-тестом `tests/track_studio.gd` без открытия редактора.
##
## Зачем отдельный класс: и разметка в 3D-вьюпорте, и полоса профиля, и
## подписи поворотов должны считать кривизну, уклон и зазоры ОДИНАКОВО.
## Дублирование формул в рисовании и в тестах уже приводило к тому, что
## «предупреждение есть, а поворота нет».
@tool
class_name RallyRouteAnalysis
extends RefCounted

const EPSILON := 0.0001


## Плотная выборка осевой линии.
## Возвращает Dictionary:
##   points: PackedVector3Array — мировые точки;
##   distances: PackedFloat32Array — километраж каждой точки;
##   length: float — полная длина;
##   step: float — фактический шаг выборки.
static func sample_curve(curve: Curve3D, step: float, max_samples: int) -> Dictionary:
	var result: Dictionary = {
		"points": PackedVector3Array(),
		"distances": PackedFloat32Array(),
		"length": 0.0,
		"step": maxf(0.25, step),
	}
	if curve == null or curve.point_count < 2:
		return result
	var length: float = curve.get_baked_length()
	if length <= EPSILON:
		return result
	var wanted: int = int(ceil(length / maxf(0.25, step))) + 1
	var count: int = clampi(wanted, 8, maxi(8, max_samples))
	var effective: float = length / float(count - 1)
	var points := PackedVector3Array()
	var dists := PackedFloat32Array()
	points.resize(count)
	dists.resize(count)
	for i in range(count):
		var offset: float = effective * float(i)
		points[i] = curve.sample_baked(offset, true)
		dists[i] = offset
	result["points"] = points
	result["distances"] = dists
	result["length"] = length
	result["step"] = effective
	return result


## Единичное направление в плане (XZ) в точке выборки.
static func direction_at(points: PackedVector3Array, index: int) -> Vector3:
	var count: int = points.size()
	if count < 2:
		return Vector3.FORWARD
	var a: Vector3 = points[clampi(index - 1, 0, count - 1)]
	var b: Vector3 = points[clampi(index + 1, 0, count - 1)]
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if dir.length() < EPSILON:
		return Vector3.FORWARD
	return dir.normalized()


## Знаковый поворот между направлениями: >0 — влево, <0 — вправо.
static func signed_turn(from_dir: Vector3, to_dir: Vector3) -> float:
	return atan2(from_dir.cross(to_dir).y, from_dir.dot(to_dir))


## Раллийная оценка поворота: 6 — пологий, 1 — шпилька.
static func severity_for(angle_deg: float, min_angle_deg: float, max_angle_deg: float) -> int:
	var span: float = maxf(1.0, max_angle_deg - min_angle_deg)
	var t: float = clampf((angle_deg - min_angle_deg) / span, 0.0, 1.0)
	return int(round(lerpf(6.0, 1.0, t)))


## Повороты трассы. Каждый элемент — Dictionary:
##   distance — вход в поворот (м);
##   apex — точка на середине дуги;
##   angle — суммарный угол, градусы;
##   direction — +1 влево, -1 вправо;
##   radius — средний радиус дуги, м;
##   grade — средний уклон дуги, %;
##   severity — 1..6.
static func find_corners(
	samples: Dictionary,
	window_m: float,
	threshold_deg: float,
	min_angle_deg: float,
	max_angle_deg: float
) -> Array:
	var result: Array = []
	var points: PackedVector3Array = samples.get("points", PackedVector3Array())
	var dists: PackedFloat32Array = samples.get("distances", PackedFloat32Array())
	var count: int = points.size()
	if count < 7:
		return result
	var step: float = maxf(0.25, float(samples.get("step", 1.0)))
	var half: int = maxi(1, int(round(window_m * 0.5 / step)))
	var threshold: float = deg_to_rad(threshold_deg)
	var turns := PackedFloat32Array()
	turns.resize(count)
	for i in range(count):
		var a: Vector3 = direction_at(points, maxi(0, i - half))
		var b: Vector3 = direction_at(points, mini(count - 1, i + half))
		turns[i] = signed_turn(a, b)
	var runs: Array = []
	var opened: int = -1
	for i in range(count):
		var active: bool = absf(turns[i]) >= threshold
		if active and opened < 0:
			opened = i
		elif not active and opened >= 0:
			runs.append(Vector2i(opened, i - 1))
			opened = -1
	if opened >= 0:
		runs.append(Vector2i(opened, count - 1))
	if runs.is_empty():
		return result
	# Склеиваем близкие сгустки: длинная дуга не должна превращаться в
	# «Л4, Л4, Л4» из-за дрожания кривизны.
	var merged: Array = []
	var gap_samples: int = maxi(1, int(round(window_m / step)))
	for run in runs:
		if merged.is_empty():
			merged.append(run)
			continue
		var last: Vector2i = merged[merged.size() - 1]
		if int(run.x) - int(last.y) <= gap_samples:
			merged[merged.size() - 1] = Vector2i(last.x, int(run.y))
		else:
			merged.append(run)
	var last_distance: float = -100000.0
	for run in merged:
		var first: int = maxi(1, int(run.x) - half)
		var last_index: int = mini(count - 2, int(run.y) + half)
		if last_index <= first:
			continue
		var total: float = 0.0
		for i in range(first, last_index + 1):
			var a: Vector3 = direction_at(points, i - 1)
			var b: Vector3 = direction_at(points, i + 1)
			total += signed_turn(a, b)
		var angle_deg: float = absf(rad_to_deg(total))
		if angle_deg < min_angle_deg:
			continue
		var arc: float = dists[last_index] - dists[first]
		if arc < step * 2.0:
			continue
		var entry: float = dists[first]
		if entry - last_distance < window_m * 0.5:
			continue
		last_distance = entry
		var mid: int = int((first + last_index) * 0.5)
		result.append({
			"distance": entry,
			"apex": points[mid],
			"angle": angle_deg,
			"direction": 1 if total >= 0.0 else -1,
			"radius": arc / maxf(absf(total), 0.0005),
			"grade": (points[last_index].y - points[first].y) / maxf(arc, EPSILON) * 100.0,
			"severity": severity_for(angle_deg, min_angle_deg, max_angle_deg),
		})
	return result


## Предупреждения по трассе: узкий радиус, крутой уклон, близкие витки.
## Каждый элемент — Dictionary: distance, text, kind, severity (0..2).
static func find_warnings(
	samples: Dictionary,
	corners: Array,
	min_radius: float,
	max_grade: float,
	min_gap: float,
	along_margin: float
) -> Array:
	var result: Array = []
	for corner in corners:
		var radius: float = float(corner.get("radius", 1000.0))
		if radius < min_radius:
			result.append({
				"distance": float(corner.get("distance", 0.0)),
				"text": "узкий радиус: %.0f м" % radius,
				"kind": "radius",
				"severity": 2,
			})
	result.append_array(_grade_warnings(samples, max_grade))
	result.append_array(_gap_warnings(samples, min_gap, along_margin))
	result.sort_custom(func(a, b): return float(a.get("distance", 0.0)) < float(b.get("distance", 0.0)))
	return result


static func _grade_warnings(samples: Dictionary, max_grade: float) -> Array:
	var result: Array = []
	var points: PackedVector3Array = samples.get("points", PackedVector3Array())
	var dists: PackedFloat32Array = samples.get("distances", PackedFloat32Array())
	var count: int = points.size()
	if count < 9:
		return result
	var last_reported: float = -100000.0
	var stride: int = maxi(1, int(count / 600))
	for i in range(4, count - 4, stride):
		var span: float = dists[i + 3] - dists[i - 3]
		if span < 1.0:
			continue
		var grade: float = (points[i + 3].y - points[i - 3].y) / span * 100.0
		if absf(grade) <= max_grade:
			continue
		if dists[i] - last_reported < 40.0:
			continue
		last_reported = dists[i]
		result.append({
			"distance": dists[i],
			"text": "уклон %+.0f %%" % grade,
			"kind": "grade",
			"severity": 1,
		})
	return result


## Витки, которые проходят ближе min_gap друг к другу, но далеко по
## километражу. Именно так находят «стенку» между ногами шпильки.
static func _gap_warnings(samples: Dictionary, min_gap: float, along_margin: float) -> Array:
	var result: Array = []
	var points: PackedVector3Array = samples.get("points", PackedVector3Array())
	var dists: PackedFloat32Array = samples.get("distances", PackedFloat32Array())
	var count: int = points.size()
	if count < 8 or min_gap <= 0.0:
		return result
	var cell: float = maxf(4.0, min_gap)
	var buckets: Dictionary = {}
	for i in range(count):
		var key := Vector2i(floori(points[i].x / cell), floori(points[i].z / cell))
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(i)
	var reported: Array = []
	for i in range(count):
		var key := Vector2i(floori(points[i].x / cell), floori(points[i].z / cell))
		for ox in range(-1, 2):
			for oz in range(-1, 2):
				var probe := Vector2i(key.x + ox, key.y + oz)
				if not buckets.has(probe):
					continue
				for j in buckets[probe]:
					if int(j) <= i:
						continue
					if absf(dists[j] - dists[i]) < along_margin:
						continue
					var dx: float = points[j].x - points[i].x
					var dz: float = points[j].z - points[i].z
					if dx * dx + dz * dz > min_gap * min_gap:
						continue
					if _already_reported(reported, dists[i]):
						break
					reported.append(dists[i])
					result.append({
						"distance": dists[i],
						"text": "витки ближе %.0f м" % min_gap,
						"kind": "gap",
						"severity": 2,
					})
	return result


static func _already_reported(reported: Array, distance: float) -> bool:
	for value in reported:
		if absf(float(value) - distance) < 25.0:
			return true
	return false


## Ближайшая точка выборки к мировой точке (в плане).
## Возвращает Dictionary: index, distance, gap, offset (знак — сторона).
static func nearest(samples: Dictionary, world_point: Vector3) -> Dictionary:
	var points: PackedVector3Array = samples.get("points", PackedVector3Array())
	var dists: PackedFloat32Array = samples.get("distances", PackedFloat32Array())
	var best: int = -1
	var best_sq: float = INF
	for i in range(points.size()):
		var dx: float = points[i].x - world_point.x
		var dz: float = points[i].z - world_point.z
		var sq: float = dx * dx + dz * dz
		if sq < best_sq:
			best_sq = sq
			best = i
	if best < 0:
		return {"index": -1, "distance": 0.0, "gap": INF, "offset": 0.0}
	var dir: Vector3 = direction_at(points, best)
	var side := Vector3(dir.z, 0.0, -dir.x)
	var offset: float = (world_point - points[best]).dot(side)
	return {
		"index": best,
		"distance": dists[best],
		"gap": sqrt(best_sq),
		"offset": offset,
	}


## Точка на осевой линии по километражу (с линейной интерполяцией выборки).
static func point_at_distance(samples: Dictionary, distance: float) -> Vector3:
	var points: PackedVector3Array = samples.get("points", PackedVector3Array())
	var dists: PackedFloat32Array = samples.get("distances", PackedFloat32Array())
	var count: int = points.size()
	if count == 0:
		return Vector3.ZERO
	var step: float = maxf(0.25, float(samples.get("step", 1.0)))
	var raw: float = clampf(distance / step, 0.0, float(count - 1))
	var index: int = clampi(int(floor(raw)), 0, count - 1)
	var next: int = mini(index + 1, count - 1)
	var blend: float = clampf(raw - float(index), 0.0, 1.0)
	if index == next:
		return points[index]
	return points[index].lerp(points[next], blend)


## Профиль высот для полосы внизу вьюпорта.
## Возвращает Dictionary: values (равномерные бины), min, max.
static func profile(samples: Dictionary, bins: int) -> Dictionary:
	var values := PackedFloat32Array()
	var points: PackedVector3Array = samples.get("points", PackedVector3Array())
	var count: int = points.size()
	var size: int = maxi(2, bins)
	if count < 2:
		values.resize(size)
		return {"values": values, "min": 0.0, "max": 0.0}
	var low: float = INF
	var high: float = -INF
	values.resize(size)
	for i in range(size):
		var raw: float = float(i) / float(size - 1) * float(count - 1)
		var index: int = clampi(int(round(raw)), 0, count - 1)
		var value: float = points[index].y
		values[i] = value
		low = minf(low, value)
		high = maxf(high, value)
	return {"values": values, "min": low, "max": high}


## Сводка для HUD: длина, набор высоты, сброс, максимум уклона, время.
static func stats(samples: Dictionary, corners: Array, speed_kmh: float) -> Dictionary:
	var points: PackedVector3Array = samples.get("points", PackedVector3Array())
	var dists: PackedFloat32Array = samples.get("distances", PackedFloat32Array())
	var length: float = float(samples.get("length", 0.0))
	var gain: float = 0.0
	var loss: float = 0.0
	var max_grade: float = 0.0
	for i in range(1, points.size()):
		var dy: float = points[i].y - points[i - 1].y
		var ds: float = maxf(dists[i] - dists[i - 1], EPSILON)
		if dy > 0.0:
			gain += dy
		else:
			loss -= dy
		max_grade = maxf(max_grade, absf(dy / ds) * 100.0)
	var min_radius: float = 0.0
	for corner in corners:
		var radius: float = float(corner.get("radius", 0.0))
		if radius > 0.0 and (min_radius <= 0.0 or radius < min_radius):
			min_radius = radius
	var speed: float = maxf(5.0, speed_kmh) / 3.6
	return {
		"length": length,
		"gain": gain,
		"loss": loss,
		"max_grade": max_grade,
		"min_radius": min_radius,
		"corners": corners.size(),
		"seconds": length / speed if length > 0.0 else 0.0,
	}


## Индекс покрытия по его названию (для палитры HUD).
static func surface_index(surface_name: String, names: PackedStringArray) -> int:
	for i in range(names.size()):
		if names[i] == surface_name:
			return i
	return 0


## Полоса покрытий вдоль трассы для полосы профиля.
## Каждый элемент — Dictionary: start, end, color, title.
static func section_bands(track: Resource, length: float, fallback: Color) -> Array:
	var bands: Array = []
	if track == null or length <= 0.0:
		bands.append({"start": 0.0, "end": length, "color": fallback, "title": ""})
		return bands
	var sections: Array = []
	var raw = track.get("route_sections")
	if raw is Array:
		sections = raw
	var track_color = track.get("road_color")
	if sections.is_empty():
		var color: Color = fallback
		if track_color is Color:
			color = track_color
		bands.append({
			"start": 0.0,
			"end": length,
			"color": color,
			"title": String(track.get("surface_name")),
		})
		return bands
	var ordered: Array = []
	for section in sections:
		if section != null:
			ordered.append(section)
	ordered.sort_custom(func(a, b): return float(a.get("start_distance")) < float(b.get("start_distance")))
	for i in range(ordered.size()):
		var section: Resource = ordered[i]
		var band_color = section.get("road_color")
		var start: float = float(section.get("start_distance"))
		var end: float = length
		if i + 1 < ordered.size():
			end = float(ordered[i + 1].get("start_distance"))
		bands.append({
			"start": clampf(start, 0.0, length),
			"end": clampf(maxf(start, end), 0.0, length),
			"color": band_color if band_color is Color else fallback,
			"title": String(section.get("surface_name")),
		})
	return bands

