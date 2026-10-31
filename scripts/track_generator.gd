## Генератор процедурной спецучастки «не на полный рандом».
##
## Дорога собирается из раллийных ПРИЁМОВ — быстрая дуга, связка, шпилька
## с ровными полками, шикан-шифт, гребень-трамплин, эссе — а не из случайных
## точек. Каждый приём перед добавлением проверяется:
##   * самозазор: новый кусок не подходит к существующей дороге ближе
##     min_gap метров (проверка по пространственному хэшу);
##   * не влез — параметры переразыгрываются, потом «побег» в сторону,
##     где свободнее, и только потом откат последних приёмов;
##   * профиль высот ограничен уклоном 8° и сглажен; трамплины — с
##     настоящим сбросом за гребнем, у шпилек — полки;
##   * трасса не убегает за горизонт (мягкая граница с доворотом к центру).
## Итог ещё раз ПРОВЕРЯЕТСЯ (зазор/уклон/радиус); неудачная сборка
## пересобирается с сидом+1. Один сид — одна и та же трасса, всегда.
##
## Это порт проверенного в числах прототипа tools/procedural_route.py:
## математика та же, счёт случайности свой (но детерминированный).
class_name RallyTrackGenerator
extends RefCounted

const STEP: float = 2.5             # шаг сэмплов приёмов (м)
const HASH_STRIDE: int = 2          # каждый второй сэмпл кладём в хэш (~5 м)
const CHECK_STRIDE: int = 2         # каждый второй сэмпл кандидата проверяем
const HASH_CELL: float = 48.0       # ячейка пространственного хэша (м)
const BRANCH_WINDOW: float = 90.0   # «своя» ветка: ближе этого км не считаем
const VAL_MIN_GAP: float = 24.0     # абсолютный предел «витки не слипаются»
const MAX_GRADE_DEG: float = 8.0    # предел уклона профиля
const MAX_ATTEMPTS: int = 6         # пересборок с сидом+1 до сдачи
const SMOOTH_WINDOW: float = 16.0   # окно сглаживания высот (м)

# Параметры контрольных точек кривой (те же, что в tools/route_kit.py).
const CTRL_MAX_GAP: float = 50.0
const CTRL_MIN_GAP: float = 14.0
const CTRL_SLOPE_TRIGGER: float = 0.0175   # tan(1°)
const CTRL_TURN_TRIGGER: float = 0.1745    # rad(10°)

## Кэш: сид+параметры -> готовая кривая. Меню рисует превью и заезд
## собирают ОДНУ и ту же трассу — генерация платится один раз.
static var _curve_cache := {}


## Ключ кэша для набора параметров (без сборки).
static func curve_cache_key(
	seed_value: int,
	length_min: float,
	length_max: float,
	min_radius: float,
	min_gap: float
) -> String:
	return "%d|%.0f|%.0f|%.1f|%.1f" % [seed_value, length_min, length_max, min_radius, min_gap]


## Кривая из кэша или null — метаданным (длина в меню) сборка не нужна.
static func cached_curve_for(
	seed_value: int,
	length_min: float,
	length_max: float,
	min_radius: float,
	min_gap: float
) -> Curve3D:
	var cached: Curve3D = _curve_cache.get(curve_cache_key(seed_value, length_min, length_max, min_radius, min_gap)) as Curve3D
	return cached


## Длина из кэша или 0.0 (дешёвая замена get_baked_length до сборки).
static func cached_length_for(
	seed_value: int,
	length_min: float,
	length_max: float,
	min_radius: float,
	min_gap: float
) -> float:
	var cached: Curve3D = cached_curve_for(seed_value, length_min, length_max, min_radius, min_gap)
	return 0.0 if cached == null else cached.get_baked_length()


## Главная точка входа: сид -> готовая Curve3D.
static func build_curve(
	seed_value: int,
	length_min: float,
	length_max: float,
	min_radius: float,
	min_gap: float
) -> Curve3D:
	var key := curve_cache_key(seed_value, length_min, length_max, min_radius, min_gap)
	if _curve_cache.has(key):
		return _curve_cache[key] as Curve3D
	var best_samples := PackedVector3Array()
	var best_score: float = -INF
	for attempt in range(MAX_ATTEMPTS):
		var builder := Builder.new(seed_value + attempt, length_min, length_max, min_radius, min_gap)
		var raw := builder.build()
		var dense := finalize(raw)
		var stats := validate(dense, min_radius)
		var length := xz_length(dense)
		var ok: bool = length >= length_min * 0.85 \
			and stats["gap"] >= VAL_MIN_GAP \
			and stats["grade"] <= tan(deg_to_rad(MAX_GRADE_DEG)) * 1.03 \
			and stats["radius"] >= min_radius * 0.8
		# «Лучшее из попыток» — на случай, когда ни одна не прошла целиком:
		# длиннее и с большим зазором лучше.
		var score: float = length * 0.001 + stats["gap"] * 0.1
		if score > best_score:
			best_score = score
			best_samples = dense
		if ok:
			break
	var curve := samples_to_curve(best_samples)
	_curve_cache[key] = curve
	return curve


## Сэмплы (x, высота, z) через каждые ~1 м — для превью и проверок.
static func build_samples(
	seed_value: int,
	length_min: float,
	length_max: float,
	min_radius: float,
	min_gap: float
) -> PackedVector3Array:
	var curve := build_curve(seed_value, length_min, length_max, min_radius, min_gap)
	var points := curve.get_baked_points()
	if points.is_empty():
		return PackedVector3Array()
	return points


# ---------------------------------------------------------------- математика
# Зеркала tools/route_kit.py. Точки везде Vector3(x, высота, z): план — .x/.z,
# высота — .y. Так их можно без перекладки отдать в Curve3D.


static func _plan(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()


static func xz_length(samples: PackedVector3Array) -> float:
	var acc := xz_distances(samples)
	return 0.0 if acc.is_empty() else acc[acc.size() - 1]


static func xz_distances(samples: PackedVector3Array) -> PackedFloat32Array:
	var acc := PackedFloat32Array()
	acc.resize(samples.size())
	if samples.is_empty():
		return acc
	acc[0] = 0.0
	for i in range(1, samples.size()):
		acc[i] = acc[i - 1] + _plan(samples[i - 1], samples[i])
	return acc


## Треугольное скользящее среднее высот; радиус — из ФАКТИЧЕСКОГО шага
## точек, поэтому окно всегда означает метры (см. route_kit.smooth_heights).
static func smooth_heights(samples: PackedVector3Array, window_m: float) -> PackedVector3Array:
	var n: int = samples.size()
	if n < 3:
		return samples
	var total := xz_length(samples)
	var spacing: float = maxf(0.000001, total / float(n - 1))
	var radius: int = maxi(1, int(round(window_m / spacing)))
	var out := PackedVector3Array()
	out.resize(n)
	for i in range(n):
		var lo: int = maxi(0, i - radius)
		var hi: int = mini(n - 1, i + radius)
		var acc: float = 0.0
		var wsum: float = 0.0
		for j in range(lo, hi + 1):
			var w: float = 1.0 - absf(float(j - i)) / float(radius + 1)
			acc += samples[j].y * w
			wsum += w
		var p: Vector3 = samples[i]
		out[i] = Vector3(p.x, acc / wsum, p.z)
	return out


## Уклон не круче max_deg в обе стороны.
static func limit_grade(samples: PackedVector3Array, max_deg: float) -> PackedVector3Array:
	var n: int = samples.size()
	if n < 2:
		return samples
	var g: float = tan(deg_to_rad(max_deg))
	var out := samples.duplicate()
	var ds := PackedFloat32Array()
	ds.resize(n)
	ds[0] = 0.0
	for i in range(1, n):
		ds[i] = _plan(out[i - 1], out[i])
	for i in range(1, n):
		out[i].y = clampf(out[i].y, out[i - 1].y - g * ds[i], out[i - 1].y + g * ds[i])
	for i in range(n - 2, -1, -1):
		out[i].y = clampf(out[i].y, out[i + 1].y - g * ds[i + 1], out[i + 1].y + g * ds[i + 1])
	return out


## Прореживание до шага step (метры), первая и последняя точки всегда остаются.
static func resample(samples: PackedVector3Array, step: float) -> PackedVector3Array:
	if samples.size() < 2:
		return samples
	var out := PackedVector3Array()
	out.append(samples[0])
	var acc: float = 0.0
	for i in range(1, samples.size()):
		acc += _plan(samples[i - 1], samples[i])
		if acc >= step:
			out.append(samples[i])
			acc = 0.0
	if out[out.size() - 1] != samples[samples.size() - 1]:
		out.append(samples[samples.size() - 1])
	return out


## Сглаживание + лимит уклона (то, что авторские трассы проходят до записи).
static func finalize(raw: PackedVector3Array) -> PackedVector3Array:
	return resample(limit_grade(smooth_heights(raw, SMOOTH_WINDOW), MAX_GRADE_DEG), 1.0)


## Уклон dh/dxz в точке i по окну ±half_window метров.
static func slope_at(samples: PackedVector3Array, acc: PackedFloat32Array, i: int, half_window: float = 8.0) -> float:
	var n: int = samples.size()
	var lo: int = i
	while lo > 0 and acc[i] - acc[lo] > half_window:
		lo -= 1
	var hi: int = i
	while hi < n - 1 and acc[hi] - acc[i] < half_window:
		hi += 1
	var span: float = acc[hi] - acc[lo]
	if span < 0.000001:
		return 0.0
	return (samples[hi].y - samples[lo].y) / span


## Адаптивные контрольные точки: не реже max_gap, плюс точки там, где
## меняется уклон или накопился поворот (полки, гребни, шифты, шпильки).
static func select_controls(samples: PackedVector3Array) -> PackedVector3Array:
	var n: int = samples.size()
	if n < 2:
		return samples
	var acc := xz_distances(samples)
	var ctrl := PackedVector3Array()
	ctrl.append(samples[0])
	var last_i: int = 0
	var last_slope: float = slope_at(samples, acc, 0)
	var turn_acc: float = 0.0
	for i in range(1, n):
		var head := _heading_of(samples, i)
		turn_acc += absf(_angle_delta(head, _heading_of(samples, i - 1)))
		var gap: float = acc[i] - acc[last_i]
		if gap < CTRL_MIN_GAP:
			continue
		var slope := slope_at(samples, acc, i)
		if gap >= CTRL_MAX_GAP or turn_acc >= CTRL_TURN_TRIGGER \
				or absf(slope - last_slope) >= CTRL_SLOPE_TRIGGER:
			ctrl.append(samples[i])
			last_i = i
			last_slope = slope
			turn_acc = 0.0
	if ctrl[ctrl.size() - 1] != samples[n - 1]:
		ctrl.append(samples[n - 1])
	return ctrl


static func _heading_of(samples: PackedVector3Array, i: int) -> float:
	if i <= 0:
		var first := Vector2(samples[1].x - samples[0].x, samples[1].z - samples[0].z)
		return atan2(first.y, first.x)
	var d := Vector2(samples[i].x - samples[i - 1].x, samples[i].z - samples[i - 1].z)
	if d.length_squared() < 0.000001:
		return _heading_of(samples, i - 1)
	return atan2(d.y, d.x)


static func _angle_delta(a: float, b: float) -> float:
	return atan2(sin(a - b), cos(a - b))


## Наклоны dh/dxz по Фричу—Карлсону: интерполяция не создаёт между
## контрольными точками новых бугров и впадин. Ровная полка остаётся ровной.
static func monotone_slopes(ctrl: PackedVector3Array) -> PackedFloat32Array:
	var n: int = ctrl.size()
	var acc := xz_distances(ctrl)
	var m := PackedFloat32Array()
	m.resize(n)
	if n < 2:
		return m
	var d := PackedFloat32Array()
	d.resize(n - 1)
	for i in range(n - 1):
		var span: float = maxf(0.000001, acc[i + 1] - acc[i])
		d[i] = (ctrl[i + 1].y - ctrl[i].y) / span
	for i in range(n):
		if i == 0:
			m[i] = d[0]
		elif i == n - 1:
			m[i] = d[n - 2]
		elif d[i - 1] * d[i] <= 0.0:
			m[i] = 0.0
		else:
			var h0: float = acc[i] - acc[i - 1]
			var h1: float = acc[i + 1] - acc[i]
			var w1: float = 2.0 * h1 + h0
			var w2: float = h1 + 2.0 * h0
			m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
	# страховочный клэмп: на каждом отрезке наклоны концов не дают кривой
	# выйти за пределы монотонности.
	for i in range(n - 1):
		if d[i] > 0.0:
			m[i] = clampf(m[i], 0.0, 3.0 * d[i])
			m[i + 1] = clampf(m[i + 1], 0.0, 3.0 * d[i])
		elif d[i] < 0.0:
			m[i] = clampf(m[i], 3.0 * d[i], 0.0)
			m[i + 1] = clampf(m[i + 1], 3.0 * d[i], 0.0)
	return m


## Сэмплы -> Curve3D. План: ручки по хорде «сосед → сосед», длина = треть
## расстояния. Высота: ручки по монотонным наклонам (никаких впадин).
static func samples_to_curve(samples: PackedVector3Array) -> Curve3D:
	var curve := Curve3D.new()
	var ctrl := select_controls(samples)
	var slopes := monotone_slopes(ctrl)
	var n: int = ctrl.size()
	for i in range(n):
		var p: Vector3 = ctrl[i]
		var prev: Vector3 = ctrl[maxi(0, i - 1)]
		var nxt: Vector3 = ctrl[mini(n - 1, i + 1)]
		var tangent := Vector2(nxt.x - prev.x, nxt.z - prev.z)
		var tl: float = maxf(tangent.length(), 0.0001)
		var dir := tangent / tl
		var slope: float = slopes[i]
		var seg_in: float = _plan(prev, p) if i > 0 else 0.0
		var seg_out: float = _plan(p, nxt) if i < n - 1 else 0.0
		var hin := Vector3(-dir.x * seg_in / 3.0, -slope * seg_in / 3.0, -dir.y * seg_in / 3.0)
		var hout := Vector3(dir.x * seg_out / 3.0, slope * seg_out / 3.0, dir.y * seg_out / 3.0)
		curve.add_point(Vector3(p.x, p.y, p.z), hin, hout)
	curve.bake_interval = 0.5
	return curve


## Финальная проверка: самозазор (по хэшу, O(n)), уклон, мин. радиус.
## Шаг проверки 4 м — как в прототипе (прототип валиден по 8 сидам).
static func validate(samples: PackedVector3Array, _min_radius: float) -> Dictionary:
	var acc := xz_distances(samples)
	var stride: int = 4
	var buckets := {}
	for i in range(0, samples.size(), stride):
		var p: Vector3 = samples[i]
		var key := Vector2i(floori(p.x / HASH_CELL), floori(p.z / HASH_CELL))
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(i)
	var worst: float = INF
	for i in range(0, samples.size(), stride):
		var p: Vector3 = samples[i]
		var ix: int = floori(p.x / HASH_CELL)
		var iz: int = floori(p.z / HASH_CELL)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var bucket: Array = buckets.get(Vector2i(ix + dx, iz + dz), [])
				for j in bucket:
					if absf(acc[i] - acc[j]) < BRANCH_WINDOW:
						continue
					var dist: float = Vector2(samples[i].x - samples[j].x, samples[i].z - samples[j].z).length()
					if dist < worst:
						worst = dist
	var grade: float = 0.0
	for i in range(1, samples.size()):
		var dxz: float = _plan(samples[i - 1], samples[i])
		if dxz > 0.01:
			grade = maxf(grade, absf(samples[i].y - samples[i - 1].y) / dxz)
	var min_r: float = INF
	var window: int = 8
	for i in range(window, samples.size() - window, 2):
		var p0: Vector3 = samples[i - window]
		var p1: Vector3 = samples[i]
		var p2: Vector3 = samples[i + window]
		var a: float = _plan(p0, p1)
		var b: float = _plan(p1, p2)
		var c: float = _plan(p0, p2)
		if a < 0.001 or b < 0.001:
			continue
		var area2: float = absf((p1.x - p0.x) * (p2.z - p0.z) - (p2.x - p0.x) * (p1.z - p0.z))
		if area2 < 0.000001:
			continue
		min_r = minf(min_r, a * b * c / (2.0 * area2))
	return {"gap": worst, "grade": grade, "radius": min_r}


# ---------------------------------------------------------------- строитель
## Плетёт трассу приёмами. Состояние: точки, курс, хэш занятости.
class Builder:
	extends RefCounted

	var rng := RandomNumberGenerator.new()
	var min_radius: float = 15.0
	var min_gap: float = 32.0
	var target: float = 9000.0
	var soft_radius: float = 1700.0

	var pts := PackedVector3Array()   # (x, высота, z)
	var acc := PackedFloat32Array()   # накопленный XZ-путь
	var heading: float = 0.0
	var total: float = 0.0
	var blocked: int = 0
	var _hash := {}                   # Vector2i -> Array[int]
	var _bucket_log: Array[Vector2i] = []


	func _init(seed_value: int, length_min: float, length_max: float, r_min: float, gap_min: float) -> void:
		rng.seed = seed_value
		min_radius = r_min
		min_gap = gap_min
		target = rng.randf_range(length_min, length_max)
		soft_radius = 800.0 + target * 0.10
		heading = rng.randf_range(0.0, TAU)
		pts.append(Vector3.ZERO)
		acc.append(0.0)


	# ------------------------------------------------------------ хэш
	func _hash_add(index: int) -> void:
		if index % RallyTrackGenerator.HASH_STRIDE != 0:
			return
		var p: Vector3 = pts[index]
		var key := Vector2i(floori(p.x / RallyTrackGenerator.HASH_CELL), floori(p.z / RallyTrackGenerator.HASH_CELL))
		if not _hash.has(key):
			_hash[key] = []
		_hash[key].append(index)
		_bucket_log.append(key)


	func _nearest_blocker(cand: PackedVector2Array, start_along: float) -> float:
		## Дистанция до ближайшей «чужой» дороги (INF — помех нет).
		var best: float = INF
		for k in range(0, cand.size(), RallyTrackGenerator.CHECK_STRIDE):
			var point: Vector2 = cand[k]
			var along_cand: float = start_along + float(k) * RallyTrackGenerator.STEP
			var ix: int = floori(point.x / RallyTrackGenerator.HASH_CELL)
			var iz: int = floori(point.y / RallyTrackGenerator.HASH_CELL)
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					var bucket: Array = _hash.get(Vector2i(ix + dx, iz + dz), [])
					for idx in bucket:
						if absf(acc[idx] - along_cand) < RallyTrackGenerator.BRANCH_WINDOW:
							continue
						var dist: float = Vector2(pts[idx].x - point.x, pts[idx].z - point.y).length()
						if dist < best:
							best = dist
		return best


	func _clearance_ok(cand: PackedVector2Array, start_along: float, gap: float) -> bool:
		return _nearest_blocker(cand, start_along) >= gap


	func _free_radius(x: float, z: float) -> float:
		## Расстояние от точки до ближайшей «чужой» дороги (радиус 2 ячейки).
		var best: float = 400.0
		var ix: int = floori(x / RallyTrackGenerator.HASH_CELL)
		var iz: int = floori(z / RallyTrackGenerator.HASH_CELL)
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				var bucket: Array = _hash.get(Vector2i(ix + dx, iz + dz), [])
				for idx in bucket:
					if absf(acc[idx] - total) < RallyTrackGenerator.BRANCH_WINDOW:
						continue
					var dist: float = Vector2(pts[idx].x - x, pts[idx].z - z).length()
					if dist < best:
						best = dist
		return best


	func _roomier_direction() -> int:
		## Куда впереди больше свободного места: +1 (влево) или -1 (вправо).
		var last: Vector3 = pts[pts.size() - 1]
		var best_sign: int = 1
		var best_score: float = -INF
		for sign_value in [-1, 1]:
			var h: float = heading + float(sign_value) * deg_to_rad(50.0)
			var px: float = last.x + cos(h) * 130.0
			var pz: float = last.z + sin(h) * 130.0
			var free: float = minf(_free_radius(px, pz), 160.0)
			var center: float = 2200.0 - minf(Vector2(px, pz).length(), 2200.0)
			var score: float = free + center * 0.03
			if score > best_score:
				best_score = score
				best_sign = sign_value
		return best_sign


	# ------------------------------------------------------------ приёмы
	func _near_edge() -> bool:
		var last: Vector3 = pts[pts.size() - 1]
		return Vector2(last.x, last.z).length() > soft_radius


	func _pick_direction() -> int:
		if _near_edge():
			return _roomier_direction()
		var last: Vector3 = pts[pts.size() - 1]
		if _free_radius(last.x, last.z) < 70.0:
			return _roomier_direction()
		return -1 if rng.randf() < 0.5 else 1


	## Сегменты: ["s", длина, подъём] и ["a", радиус, угол°, подъём, знак].
	func _feature(kind: String, grade: float) -> Array:
		if kind == "straight":
			var s_len: float = rng.randf_range(90.0, 240.0)
			if _near_edge():
				s_len *= 0.5
			return [["s", s_len, s_len * grade]]
		if kind == "arc_flow":
			var r_flow: float = rng.randf_range(55.0, 170.0)
			var a_flow: float = rng.randf_range(18.0, 75.0)
			var l_flow: float = r_flow * deg_to_rad(a_flow)
			return [["a", r_flow, a_flow, l_flow * grade, _pick_direction()]]
		if kind == "arc_tight":
			var r_tight: float = rng.randf_range(maxf(26.0, min_radius * 1.7), 55.0)
			var a_tight: float = rng.randf_range(40.0, 130.0)
			var l_tight: float = r_tight * deg_to_rad(a_tight)
			return [["a", r_tight, a_tight, l_tight * grade, _pick_direction()]]
		if kind == "hairpin":
			var r_hair: float = rng.randf_range(min_radius, min_radius + 4.0)
			var a_hair: float = rng.randf_range(150.0, 176.0)
			var dir_hair: int = _pick_direction()
			var shelf_in: float = rng.randf_range(38.0, 55.0)
			var shelf_out: float = rng.randf_range(38.0, 55.0)
			var l_hair: float = r_hair * deg_to_rad(a_hair)
			return [
				["s", shelf_in, shelf_in * grade * 0.3],
				["a", r_hair, a_hair, l_hair * grade * 0.15, dir_hair],
				["s", shelf_out, shelf_out * grade * 0.3],
			]
		if kind == "chicane":
			var segs_chic: Array = []
			var dir_chic: int = _pick_direction()
			for _i in range(3):
				var r_chic: float = rng.randf_range(22.0, 32.0)
				var a_chic: float = rng.randf_range(32.0, 46.0)
				segs_chic.append(["s", rng.randf_range(8.0, 16.0), 0.0])
				var l_chic: float = r_chic * deg_to_rad(a_chic)
				segs_chic.append(["a", r_chic, a_chic, l_chic * grade * 0.6, dir_chic])
				dir_chic = -dir_chic
			return segs_chic
		if kind == "crest":
			var run_in: float = rng.randf_range(60.0, 110.0)
			var face: float = rng.randf_range(22.0, 32.0)
			var run_out: float = rng.randf_range(55.0, 85.0)
			return [
				["s", run_in, run_in * maxf(grade, 0.025)],
				["s", face, -rng.randf_range(2.2, 3.4)],
				["s", run_out, 0.0],
			]
		if kind == "esses":
			var segs_ess: Array = []
			var dir_ess: int = _pick_direction()
			for _i in range(rng.randi_range(2, 3)):
				var r_ess: float = rng.randf_range(60.0, 120.0)
				var a_ess: float = rng.randf_range(25.0, 55.0)
				var l_ess: float = r_ess * deg_to_rad(a_ess)
				segs_ess.append(["a", r_ess, a_ess, l_ess * grade, dir_ess])
				dir_ess = -dir_ess
			return segs_ess
		return [["s", 60.0, 0.0]]


	# ------------------------------------------------------------ геометрия
	func _save_state() -> Array:
		return [pts.size(), heading, _bucket_log.size()]


	func _restore_state(state: Array) -> void:
		## Откат последнего приёма: точки, километраж, хэш, курс.
		var mark: int = state[0]
		var saved_heading: float = state[1]
		var log_mark: int = state[2]
		for key in _bucket_log.slice(log_mark):
			var bucket: Array = _hash.get(key, [])
			bucket = bucket.filter(func(index: int) -> bool: return index < mark)
			_hash[key] = bucket
		_bucket_log.resize(log_mark)
		pts.resize(mark)
		acc.resize(mark)
		heading = saved_heading
		total = acc[acc.size() - 1] if not acc.is_empty() else 0.0


	func _walk(segs: Array) -> PackedVector2Array:
		## Прогонка сегментов от текущего конца: только план (XZ).
		var last: Vector3 = pts[pts.size() - 1]
		var x: float = last.x
		var z: float = last.z
		var h: float = heading
		var out := PackedVector2Array()
		for seg in segs:
			if seg[0] == "s":
				var length: float = seg[1]
				var n: int = maxi(2, int(length / RallyTrackGenerator.STEP))
				var d: float = length / float(n)
				for _i in range(n):
					x += cos(h) * d
					z += sin(h) * d
					out.append(Vector2(x, z))
			else:
				var radius: float = seg[1]
				var angle: float = deg_to_rad(seg[2])
				var direction: int = seg[4]
				var n: int = maxi(3, int(radius * angle / RallyTrackGenerator.STEP))
				var d_ang: float = angle / float(n)
				var d: float = radius * d_ang
				for _i in range(n):
					h += direction * d_ang
					x += cos(h) * d
					z += sin(h) * d
					out.append(Vector2(x, z))
		return out


	func _advance(dx: float, dz: float, dh: float) -> void:
		var last: Vector3 = pts[pts.size() - 1]
		pts.append(Vector3(last.x + dx, last.y + dh, last.z + dz))
		acc.append(acc[acc.size() - 1] + Vector2(dx, dz).length())
		total = acc[acc.size() - 1]
		_hash_add(pts.size() - 1)


	func _emit(segs: Array) -> void:
		for seg in segs:
			if seg[0] == "s":
				var length: float = seg[1]
				var climb: float = seg[2]
				var n: int = maxi(2, int(length / RallyTrackGenerator.STEP))
				var d: float = length / float(n)
				for i in range(n):
					_advance(cos(heading) * d, sin(heading) * d, climb / float(n))
			else:
				var radius: float = seg[1]
				var angle: float = deg_to_rad(seg[2])
				var climb: float = seg[3]
				var direction: int = seg[4]
				var n: int = maxi(3, int(radius * angle / RallyTrackGenerator.STEP))
				var d_ang: float = angle / float(n)
				var d: float = radius * d_ang
				for i in range(n):
					heading += direction * d_ang
					_advance(cos(heading) * d, sin(heading) * d, climb / float(n))


	func _escape(grade: float) -> bool:
		## Приём не влез: поворот в сторону, где свободнее. Последний шанс —
		## чуть ослабленный зазор (28 м). Непроверенного ничего не добавляем.
		var away: int = _roomier_direction()
		for relax in [min_gap, 28.0]:
			for attempt in range(10):
				var angle: float = minf(50.0 + attempt * 14.0, 168.0)
				var radius: float = rng.randf_range(22.0, 60.0)
				for direction in [away, -away]:
					var seg := ["a", radius, angle, radius * deg_to_rad(angle) * grade * 0.4, direction]
					if _clearance_ok(_walk([seg]), total, relax):
						_emit([seg])
						return true
		return false


	func _try_feature(kind: String, grade: float) -> bool:
		for _attempt in range(6):
			var segs := _feature(kind, grade)
			if _clearance_ok(_walk(segs), total, min_gap):
				_emit(segs)
				return true
		blocked += 1
		return _escape(grade)


	# ------------------------------------------------------------ сборка
	func build() -> PackedVector3Array:
		_emit([["s", 130.0, 0.0]])            # старт — ровная прямая
		var grade: float = rng.randf_range(-0.02, 0.03)
		var kinds := [
			"straight", "arc_flow", "arc_flow", "arc_tight",
			"hairpin", "chicane", "crest", "esses",
		]
		var guard: int = 0
		var stuck: int = 0
		var backs: int = 0
		var history: Array = []
		while total < target - 300.0 and guard < 4000:
			guard += 1
			var kind: String = kinds[rng.randi_range(0, kinds.size() - 1)]
			var state := _save_state()
			if _try_feature(kind, grade):
				history.append(state)
				stuck = 0
			else:
				stuck += 1
				if stuck >= 2 and not history.is_empty():
					# замуровало: откатываем пару приёмов и пробуем иначе
					for _i in range(2):
						if not history.is_empty():
							_restore_state(history.pop_back())
					stuck = 0
					backs += 1
					if backs > 40:
						break
					continue
				if stuck >= 3:
					# откатываться нечем — финиш здесь, короткая трасса
					# лучше битой
					break
			grade = clampf(grade + rng.randf_range(-0.028, 0.028), -0.065, 0.065)
			# возврат к нулю: не даём профилю уехать в стратосферу
			var h_now: float = pts[pts.size() - 1].y
			if h_now > 70.0:
				grade = minf(grade, -0.012)
			elif h_now < -70.0:
				grade = maxf(grade, 0.012)
		# финиш: связка и ровные прямые (тоже с проверкой зазора)
		_try_feature("arc_flow", grade * 0.5)
		for _attempt in range(6):
			var tail := [["s", 120.0, 0.0], ["s", 150.0, 0.0]]
			if _clearance_ok(_walk(tail), total, min_gap):
				_emit(tail)
				break
			if not _try_feature("arc_tight", 0.0):
				break
		return pts
