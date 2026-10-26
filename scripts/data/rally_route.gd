## Генератор маршрута трассы. Классический раллийский спецучасток:
## шпильки (hairpin), длинные дуги (sweeper), шифты (chicane),
## трамплины и слепые гребни — как в Colin McRae Rally / V-Rally.
##
## Один источник истины: и гоночная сцена (scripts/rally_stage.gd),
## и мини-карта в меню (scripts/stage_preview.gd) используют один результат.
## Детерминированный: один сид → один маршрут, без скрытого рандома.
class_name RallyRoute
extends RefCounted

## Тип участка маршрута.
enum Kind { STRAIGHT, SWEEPER, HAIRPIN, CHICANE, JUMP }

## Плотность разбивки маршрута (м между точками).
const SAMPLE_STEP: float = 0.5

## Сгенерировать маршрут.
## Возвращает словарь:
##   points      — PackedVector2Array (x, z), плотная разбивка 0.5 м
##   tangents    — PackedVector2Array, единичные касательные
##   bounds      — Rect2, прямоугольник покрытия маршрута
##   length      — итоговая длина маршрута (м)
##   features    — Array[Dictionary], участки рельефа (crest/whoop/bump/jump)
##   checkpoints — Array[Dictionary], контрольные точки {pos, tangent, idx}
##   seed_used   — int, сид, который занял лучший маршрут
static func generate(track: RallyTrackConfig, seed_value: int, always_random: bool) -> Dictionary:
	var best: Dictionary
	var best_score: float = 1.0e30
	# seed_variation: мелкая детерминированная вариация сида,
	# одинаковая для сцены и мини-карты.
	var base_seed := seed_value
	if not always_random:
		base_seed = maxi(1, int(float(base_seed) * (1.0 + (track.seed_variation - 0.5) * 0.35)) + 7)
	# Несколько попыток сида: выбираем маршрут с меньшим самопересечением.
	for attempt in range(12):
		var seed := maxi(1, base_seed + attempt * 137 + 11)
		var result: Dictionary = _build_once(track, seed, always_random)
		var score: float = _overlap_score(result["points"], track.road_half_width)
		if score < best_score:
			best_score = score
			best = result
			best["seed_used"] = seed
		if best_score <= 0.0:
			break
	return best


## Считать «стекло»: пары точек, ближе которых к SiD, чем ширина дороги.
## Точки ближе 12 м по маршруту — соседние, их игнорируем.
static func _overlap_score(points: PackedVector2Array, half_width: float) -> float:
	if points.size() < 8:
		return 1.0e30
	var cell_size: float = maxf(4.0, half_width * 2.0)
	var grid := Dictionary()
	var min_gap: int = 24  # 12 м по маршруту
	for i in range(points.size()):
		var p: Vector2 = points[i]
		var cx := int(floor(p.x / cell_size))
		var cz := int(floor(p.y / cell_size))
		for gx in range(cx - 2, cx + 3):
			for gz in range(cz - 2, cz + 3):
				var key := Vector2i(gx, gz)
				if not grid.has(key):
					grid[key] = PackedInt32Array()
				(grid[key] as PackedInt32Array).append(i)
	var limit: float = (half_width * 2.0 + 1.0) * (half_width * 2.0 + 1.0)
	var count: int = 0
	for i in range(points.size()):
		var p: Vector2 = points[i]
		var cx := int(floor(p.x / cell_size))
		var cz := int(floor(p.y / cell_size))
		for gx in range(cx - 1, cx + 2):
			for gz in range(cz - 1, cz + 2):
				var key := Vector2i(gx, gz)
				if not grid.has(key):
					continue
				for j in (grid[key] as PackedInt32Array):
					if absi(i - j) < min_gap:
						continue
					if p.distance_squared_to(points[j]) < limit:
						count += 1
	return float(count)


## Сгенерировать маршрут одним сидом.
static func _build_once(track: RallyTrackConfig, seed: int, always_random: bool) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var points := PackedVector2Array()
	var tangents := PackedVector2Array()
	var features: Array = []

	if track.is_flat():
		return _build_flat(track)

	var total: float = track.length
	var pos := Vector2.ZERO
	# Начальное направление — лёгкий разброс, чтобы старты не были ровными.
	var heading: float = rng.randf_range(-0.28, 0.28)
	var remaining: float = total
	var pattern_offset: float = 0.0
	if track.corner_pattern_fixed:
		pattern_offset = float(absi(seed) % 31) * 0.13

	while remaining > 50.0:
		# Резерв для финального прямого отрезка финиша.
		var budget: float = remaining - 50.0
		var seg_len: float = rng.randf_range(track.segment_min, track.segment_max)
		seg_len = minf(seg_len, budget)
		var kind: int = _pick_kind(track, rng, pattern_offset)
		var res: Array = _emit_segment(track, rng, kind, seg_len, pos, heading, points, tangents, features)
		pos = res[0]
		heading = res[1]
		remaining -= res[2]
	# Финишный прямой — чтобы финишный КПП был ровным.
	if remaining > 0.0:
		_emit_segment(track, rng, Kind.STRAIGHT, remaining, pos, heading, points, tangents, features)

	_finalize_features(track, rng, points, features)
	var bounds := Rect2(0.0, 0.0, 0.0, 0.0)
	for i in range(points.size()):
		bounds = bounds.expand(points[i])
	var checkpoints: Array = []
	if track.checkpoint_interval > 0.0 and points.size() > 40:
		_build_checkpoints(track, points, checkpoints)
	return {
		"points": points,
		"tangents": tangents,
		"bounds": bounds,
		"length": track.length,
		"features": features,
		"checkpoints": checkpoints,
	}


## Плоская прямая (Polygon/Range): маршрут по оси Z, без углов.
static func _build_flat(track: RallyTrackConfig) -> Dictionary:
	var points := PackedVector2Array()
	var tangents := PackedVector2Array()
	var length: float = track.length
	var count := maxi(2, ceili(length / SAMPLE_STEP))
	for i in range(count):
		var t: float = float(i) / float(count - 1)
		points.append(Vector2(0.0, -length * 0.5 + t * length))
		tangents.append(Vector2(0.0, 1.0))
	var checkpoints: Array = []
	if track.checkpoint_interval > 0.0:
		_build_checkpoints(track, points, checkpoints)
	return {
		"points": points,
		"tangents": tangents,
		"bounds": Rect2(-1.0, -length * 0.5 - 1.0, 1.0, length * 0.5 + 1.0),		"length": length,
		"features": [],
		"checkpoints": checkpoints,
	}


## Выбрать тип участка.
static func _pick_kind(track: RallyTrackConfig, rng: RandomNumberGenerator, pattern_offset: float) -> int:
	var roll := rng.randf()
	if track.corner_pattern_fixed:
		roll = RallyTrackConfig.hash_unit(12345, pattern_offset)
	if roll > track.corner_density:
		return Kind.STRAIGHT
	var corner_roll := rng.randf()
	var hairpin_p: float = track.hairpin_share
	var sweeper_p: float = hairpin_p + track.sweeper_share
	var chicane_p: float = sweeper_p + track.chicane_share
	if corner_roll < hairpin_p:
		return Kind.HAIRPIN
	if corner_roll < sweeper_p:
		return Kind.SWEEPER
	if corner_roll < chicane_p:
		return Kind.CHICANE
	return Kind.JUMP


## Набрать точки одного участка. Возвращает [pos, heading, used_length].
static func _emit_segment(
	track: RallyTrackConfig,
	rng: RandomNumberGenerator,
	kind: int,
	seg_len: float,
	pos: Vector2,
	heading: float,
	points: PackedVector2Array,
	tangents: PackedVector2Array,
	features: Array
) -> Array:
	match kind:
		Kind.STRAIGHT, Kind.JUMP:
			return _emit_straight(track, rng, kind, seg_len, pos, heading, points, tangents, features)
		Kind.SWEEPER:
			return _emit_sweeper(track, rng, seg_len, pos, heading, points, tangents)
		Kind.HAIRPIN:
			return _emit_hairpin(track, rng, seg_len, pos, heading, points, tangents)
		Kind.CHICANE:
			return _emit_chicane(track, rng, seg_len, pos, heading, points, tangents)
	return _emit_straight(track, rng, Kind.STRAIGHT, seg_len, pos, heading, points, tangents, features)


static func _emit_straight(
	track: RallyTrackConfig,
	rng: RandomNumberGenerator,
	kind: int,
	seg_len: float,
	pos: Vector2,
	heading: float,
	points: PackedVector2Array,
	tangents: PackedVector2Array,
	features: Array
) -> Array:
	var dir := Vector2(cos(heading), sin(heading))
	var steps := maxi(1, ceili(seg_len / SAMPLE_STEP))
	var step_len: float = seg_len / float(steps)
	var p := pos
	for i in range(steps):
		p += dir * step_len
		points.append(p)
		tangents.append(dir)
	if kind == Kind.JUMP:
		# Трамплин: кочка на рельефе в конце прямой.
		features.append({
			"kind_tag": "jump",
			"pos": p,
			"tangent": dir,
			"strength": track.bump_amount * 1.5,
			"width": 3.2,
		})
	return [p, heading, seg_len]


static func _emit_sweeper(
	track: RallyTrackConfig,
	rng: RandomNumberGenerator,
	seg_len: float,
	pos: Vector2,
	heading: float,
	points: PackedVector2Array,
	tangents: PackedVector2Array
) -> Array:
	var radius: float = rng.randf_range(track.sweeper_radius_min, track.sweeper_radius_max)
	var angle_deg: float = rng.randf_range(track.sweeper_angle_min, track.sweeper_angle_max)
	var angle: float = deg_to_rad(angle_deg)
	var turn_len: float = radius * angle
	if turn_len > seg_len:
		# Угол ограничен доступной длиной участка.
		angle = seg_len / radius
		turn_len = seg_len
	var sign: float = 1.0 if rng.randf() > 0.5 else -1.0
	var p := pos
	var h := heading
	var steps := maxi(2, ceili(turn_len / SAMPLE_STEP))
	var d_theta: float = angle / float(steps)
	for i in range(steps):
		h += sign * d_theta
		var step_len: float = radius * absf(d_theta)
		var dir := Vector2(cos(h), sin(h))
		p += dir * step_len
		points.append(p)
		tangents.append(dir)
	return [p, h, turn_len]


static func _emit_hairpin(
	track: RallyTrackConfig,
	rng: RandomNumberGenerator,
	seg_len: float,
	pos: Vector2,
	heading: float,
	points: PackedVector2Array,
	tangents: PackedVector2Array
) -> Array:
	var radius: float = rng.randf_range(track.hairpin_radius_min, track.hairpin_radius_max)
	var angle_deg: float = rng.randf_range(track.hairpin_angle_min, track.hairpin_angle_max)
	var angle: float = deg_to_rad(angle_deg)
	var turn_len: float = radius * angle
	if turn_len > seg_len:
		angle = seg_len / radius
		turn_len = seg_len
	var sign: float = 1.0 if rng.randf() > 0.5 else -1.0
	var p := pos
	var h := heading
	var steps := maxi(2, ceili(turn_len / SAMPLE_STEP))
	var d_theta: float = angle / float(steps)
	for i in range(steps):
		h += sign * d_theta
		var step_len: float = radius * absf(d_theta)
		var dir := Vector2(cos(h), sin(h))
		p += dir * step_len
		points.append(p)
		tangents.append(dir)
	return [p, h, turn_len]


static func _emit_chicane(
	track: RallyTrackConfig,
	rng: RandomNumberGenerator,
	seg_len: float,
	pos: Vector2,
	heading: float,
	points: PackedVector2Array,
	tangents: PackedVector2Array
) -> Array:
	# Три короткие дуги: лево-право-лево (классический шифт).
	var a1: float = deg_to_rad(rng.randf_range(25.0, 45.0))
	var a2: float = deg_to_rad(rng.randf_range(35.0, 58.0))
	var a3: float = deg_to_rad(rng.randf_range(25.0, 45.0))
	var radius: float = rng.randf_range(track.chicane_radius_min, track.chicane_radius_max)
	var needed: float = radius * (a1 + a2 + a3)
	# Если шифт слишком длинный — равномерно качаем углы.
	if needed > seg_len:
		var scale: float = seg_len / needed
		a1 *= scale
		a2 *= scale
		a3 *= scale
	var p := pos
	var h := heading
	var turns := [a1, -a2, a3]
	for t in turns:
		var steps := maxi(2, ceili(radius * absf(t) / SAMPLE_STEP))
		var d_theta: float = t / float(steps)
		for i in range(steps):
			h += d_theta
			var step_len: float = radius * absf(d_theta)
			var dir := Vector2(cos(h), sin(h))
			p += dir * step_len
			points.append(p)
			tangents.append(dir)
	return [p, h, radius * (absf(a1) + absf(a2) + absf(a3))]


## Заполнить рельефные участки (гребень, серпентина, кочка, трамплин)
## и привязать их к расстоянию по маршруту.
static func _finalize_features(track: RallyTrackConfig, rng: RandomNumberGenerator, points: PackedVector2Array, features: Array) -> void:
	if points.size() < 20:
		return
	var total: float = track.length
	# Трамплины с «pos»: привязка к расстоянию по маршруту.
	for feature in features:
		if feature.has("pos"):
			var best_i: int = 0
			var best_d2: float = 1.0e30
			for i in range(points.size()):
				var d2: float = points[i].distance_squared_to(feature["pos"])
				if d2 < best_d2:
					best_d2 = d2
					best_i = i
			feature["route_dist"] = float(best_i) * SAMPLE_STEP
			feature.erase("pos")
			feature.erase("tangent")
	# Гребени (1–2): слепые подъёмы в стиле горных ралли.
	var crest_count: int = 2 if track.crest_amount > 1.2 else 1
	for i in range(crest_count):
		var dist: float = rng.randf_range(total * 0.2, total * 0.85)
		features.append({
			"kind_tag": "crest",
			"route_dist": dist,
			"strength": track.crest_amount,
			"width": 7.0,
		})
	# Серпентины (whoops): 1–2 участка с серией частых кочек.
	var whoop_count: int = 1 if track.whoops_amount > 0.05 else 0
	if track.whoops_amount > 0.25:
		whoop_count = 2
	for i in range(whoop_count):
		var dist: float = rng.randf_range(total * 0.15, total * 0.9)
		features.append({
			"kind_tag": "whoop",
			"route_dist": dist,
			"length": rng.randf_range(35.0, 60.0),
			"strength": track.whoops_amount,
		})
	# Кочки (смещены в сторону дороги).
	var bump_count: int = 4 + int(rng.randi() % 5)
	for i in range(bump_count):
		var dist: float = rng.randf_range(total * 0.08, total * 0.92)
		features.append({
			"kind_tag": "bump",
			"route_dist": dist,
			"strength": track.bump_amount * rng.randf_range(0.5, 1.4),
			"width": rng.randf_range(2.0, 4.5),
			"side": 1.0 if rng.randf() > 0.5 else -1.0,
		})


static func _build_checkpoints(track: RallyTrackConfig, points: PackedVector2Array, checkpoints: Array) -> void:
	var interval: float = track.checkpoint_interval
	var dist: float = interval * 0.5
	while dist < track.length - 30.0:
		var idx: int = clampi(int(dist / SAMPLE_STEP), 0, points.size() - 1)
		checkpoints.append({"idx": idx, "pos": points[idx]})
		dist += interval
	# Касательные из соседних точек.
	for cp in checkpoints:
		var i: int = int(cp["idx"])
		var tangent := points[i + 1] - points[i] if i + 1 < points.size() else points[i] - points[i - 1]
		if tangent.length() > 0.001:
			tangent = tangent.normalized()
		else:
			tangent = Vector2(0.0, 1.0)
		cp["tangent"] = tangent


## Высотный профиль маршрута (высота по рейсу в метрах).
## profile[i] = высота в точке i*SAMPLE_STEP. Считается только по центру дороги:
## кочки со смещением (kind_tag == "bump") учитываются в _terrain_height
## через латеральное расстояние.
static func build_profile(track: RallyTrackConfig, points: PackedVector2Array, features: Array, rng_phase: Vector2) -> PackedFloat32Array:
	var profile := PackedFloat32Array()
	var count: int = points.size()
	if count == 0:
		return profile
	profile.resize(count)
	for i in range(count):
		var rd: float = float(i) * SAMPLE_STEP
		var h: float = 0.0
		# Rolling hills по маршруту.
		h += track.hill_amplitude * sin(rd * track.hill_frequency + rng_phase.x)
		h += track.hill_amplitude * 0.42 * sin(rd * track.hill_frequency * 2.7 + rng_phase.y)
		h += track.hill_amplitude * 0.28 * sin(rd * track.hill_frequency * 0.43 + rng_phase.x * 0.7)
		for feature in features:
			var tag: String = feature.get("kind_tag", "")
			if tag == "crest" or tag == "jump":
				var fdist: float = float(feature["route_dist"])
				var strength: float = float(feature["strength"])
				var width: float = float(feature["width"])
				h += strength * exp(-pow((rd - fdist) / width, 2.0))
			elif tag == "whoop":
				var start: float = float(feature["route_dist"])
				var length: float = float(feature["length"])
				if rd > start and rd < start + length:
					h += float(feature["strength"]) * sin((rd - start) * TAU / 4.5)
			# Кочки (kind_tag == "bump") — не в профиле, см. _terrain_height.
		profile[i] = h
	return profile


## Фазовые сдвиги холмов — одинаковые для сцены и мини-карты.
static func route_phases(track: RallyTrackConfig, seed_value: int) -> Vector2:
	return Vector2(
		RallyTrackConfig.hash_unit(seed_value, 6.0) * TAU,
		RallyTrackConfig.hash_unit(seed_value, 7.0) * TAU
	)
