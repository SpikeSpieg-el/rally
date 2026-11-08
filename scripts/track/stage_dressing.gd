## Чистый планировщик оформления спецучастка: ГДЕ ставить зрителей, ленты,
## тормозные таблички, ЛЭП и туман — без единого узла сцены.
##
## Здесь только детерминированная математика по километражу и списку
## поворотов RallyRouteAnalysis.find_corners(). Поэтому файл проверяется
## headless-тестом tests/stage_dressing.gd без сборки мира, а RallyStage
## лишь превращает план в низкополигональную геометрию в стиле PS1.
##
## Зачем отдельный класс: раньше обстановка сыпалась вдоль трассы с одной
## плотностью («шум Перлина по грядкам»), а гоночной инфраструктуры не было
## вовсе. Планировщик даёт три вещи:
##   * кластеризацию леса — пустые поляны чередуются с непроглядными
##     зарослями (cluster_factor);
##   * «островки жизни» — зрители стоят не по одному в лесу, а лагерями
##     на внешних радиусах интересных поворотов (select_spectator_corners);
##   * ритм — линия ЛЭП и пятна тумана в низинах, чтобы у 3–4 км трассы
##     появились запоминающиеся ориентиры.
class_name RallyStageDressing
extends RefCounted

## Длина блока кластерного шума, м. Поляна/заросли — не точки, а участки.
const CLUSTER_BLOCK_M := 110.0
## Ниже этого значения кластерного шума крупных пропсов нет совсем (поляна).
const CLUSTER_CLEARING := 0.30
## Ширина перехода «поляна → заросли».
const CLUSTER_RAMP := 0.45


## Детерминированный хэш 0..1 по двум целым (без глобального RNG: один сид —
## одна и та же трасса в меню, в заезде и в тестах).
static func hash01(a: int, b: int) -> float:
	var value: int = a * 374761393 + b * 668265263
	value = (value ^ (value >> 13)) * 1274126177
	value = value ^ (value >> 16)
	return float(value & 0xffffff) / float(0x1000000)


## Гладкий одномерный шум по километражу: значения на границах блоков
## хэшируются, между ними — smoothstep-интерполяция.
static func cluster_noise(distance: float, seed_value: int) -> float:
	var scaled: float = maxf(distance, 0.0) / CLUSTER_BLOCK_M
	var block: int = int(floor(scaled))
	var frac: float = scaled - float(block)
	var smooth: float = frac * frac * (3.0 - 2.0 * frac)
	return lerpf(hash01(block, seed_value), hash01(block + 1, seed_value), smooth)


## Множитель плотности крупных пропсов: 0 на полянах, до ~1.8 в зарослях.
## Среднее по трассе близко к 0.8, поэтому общее число объектов не взрывается:
## лес просто перестаёт быть равномерным.
static func cluster_factor(distance: float, seed_value: int) -> float:
	var noise_value: float = cluster_noise(distance, seed_value)
	var t: float = clampf((noise_value - CLUSTER_CLEARING) / CLUSTER_RAMP, 0.0, 1.0)
	return t * t * 1.8


## Дистанции тормозных табличек перед поворотом: классические 150/100/50,
## но табличка не ставится раньше старта трассы и не позже входа в поворот.
static func braking_marker_distances(corner_distance: float, track_length: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for back in [150.0, 100.0, 50.0]:
		var distance: float = corner_distance - back
		if distance > 30.0 and distance < track_length - 60.0:
			result.append(distance)
	return result


## Повороты, достойные зрителей: крутые (severity <= 3) и не чаще min_spacing.
## Возвращает подмножество входных словарей RallyRouteAnalysis (порядок —
## по километражу), не больше max_count.
static func select_spectator_corners(corners: Array, min_spacing: float, max_count: int) -> Array:
	var result: Array = []
	var last_distance: float = -100000.0
	for corner in corners:
		if result.size() >= max_count:
			break
		if int(corner.get("severity", 6)) > 3:
			continue
		var distance: float = float(corner.get("distance", 0.0))
		if distance - last_distance < min_spacing:
			continue
		last_distance = distance
		result.append(corner)
	return result


## Участки линии ЛЭП вдоль трассы: два отрезка по 500–800 м на разной
## стороне, не у самого старта/финиша. Каждый элемент — Dictionary:
## start, end, side (+1.0/-1.0).
static func powerline_ranges(track_length: float, seed_value: int) -> Array:
	var result: Array = []
	if track_length < 900.0:
		return result
	var first_start: float = track_length * lerpf(0.10, 0.20, hash01(seed_value, 11))
	var first_length: float = lerpf(500.0, 800.0, hash01(seed_value, 12))
	result.append({
		"start": first_start,
		"end": minf(first_start + first_length, track_length - 150.0),
		"side": 1.0 if hash01(seed_value, 13) > 0.5 else -1.0,
	})
	var second_start: float = track_length * lerpf(0.55, 0.68, hash01(seed_value, 14))
	var second_length: float = lerpf(500.0, 750.0, hash01(seed_value, 15))
	if second_start > first_start + first_length + 250.0:
		result.append({
			"start": second_start,
			"end": minf(second_start + second_length, track_length - 150.0),
			"side": -float(result[0].get("side", 1.0)),
		})
	return result


## Низины для пятен тумана: локальные минимумы высоты осевой линии не чаще
## min_spacing. points/distances — выборка RallyRouteAnalysis.sample_curve().
static func fog_distances(points: PackedVector3Array, distances: PackedFloat32Array, min_spacing: float, window: int) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	var count: int = mini(points.size(), distances.size())
	if count < window * 2 + 3:
		return result
	var last: float = -100000.0
	for i in range(window, count - window):
		var height: float = points[i].y
		var is_min: bool = true
		for j in range(1, window + 1):
			if points[i - j].y < height - 0.4 or points[i + j].y < height - 0.4:
				is_min = false
				break
		if not is_min:
			continue
		# Низина обязана быть настоящей впадиной, а не шумом на ровном месте.
		if points[i - window].y - height < 2.5 and points[i + window].y - height < 2.5:
			continue
		if distances[i] - last < min_spacing:
			continue
		last = distances[i]
		result.append(distances[i])
	return result


## Километраж «сюжетных» точек: домик лесника с брёвнами и разбитая машина
## соперника. Доли длины хэшируются от сида, но точки разнесены и не лезут
## на старт/финиш.
static func landmark_distance(track_length: float, seed_value: int, salt: int, low: float, high: float) -> float:
	if track_length <= 0.0:
		return 0.0
	return track_length * lerpf(low, high, hash01(seed_value, salt))


## Слишком храбрые болельщики на бровке: стоят по бокам дороги, часть —
## почти на полотне. Каждый элемент — Dictionary: distance, side (+1/-1),
## eager (шаг навстречу машине), inset (смещение от кромки, м; минус —
## на полотно).
static func roadside_fans(track_length: float, seed_value: int, spacing: float, max_count: int, options: Dictionary = {}) -> Array:
	var result: Array = []
	if track_length < 200.0 or spacing <= 1.0 or max_count <= 0:
		return result
	var start_margin: float = float(options.get("start_margin", 70.0))
	var end_margin: float = float(options.get("end_margin", 110.0))
	var keep_chance: float = float(options.get("keep_chance", 0.68))
	var spacing_scale: Vector2 = options.get("spacing_scale", Vector2(0.72, 1.38)) as Vector2
	var both_chance: float = float(options.get("both_sides_chance", 0.45))
	var both_offset: float = float(options.get("both_offset", 1.2))
	var eager_chance: float = float(options.get("eager_chance", 0.42))
	var tarmac_chance: float = float(options.get("tarmac_chance", 0.14))
	var inset_range: Vector2 = options.get("inset", Vector2(0.45, 1.7)) as Vector2
	var eager_inset: Vector2 = options.get("eager_inset", Vector2(-0.55, 0.45)) as Vector2
	var tarmac_inset: Vector2 = options.get("tarmac_inset", Vector2(-1.35, -0.65)) as Vector2
	var other_inset: Vector2 = options.get("other_inset", Vector2(0.55, 1.8)) as Vector2
	var other_eager_inset: Vector2 = options.get("other_eager_inset", Vector2(-0.45, 0.50)) as Vector2
	var other_eager_chance: float = float(options.get("other_eager_chance", 0.38))
	var cursor: float = start_margin
	var guard: int = 0
	while cursor < track_length - end_margin and result.size() < max_count and guard < 4000:
		guard += 1
		var salt: int = int(round(cursor * 10.0))
		var keep: float = hash01(salt, seed_value + 91)
		if keep > (1.0 - keep_chance):
			var side: float = 1.0 if hash01(salt, seed_value + 92) > 0.5 else -1.0
			var eager: bool = hash01(salt, seed_value + 93) > (1.0 - eager_chance)
			var inset: float = lerpf(inset_range.x, inset_range.y, hash01(salt, seed_value + 94))
			if eager:
				inset = lerpf(eager_inset.x, eager_inset.y, hash01(salt, seed_value + 95))
			if hash01(salt, seed_value + 101) > (1.0 - tarmac_chance):
				eager = true
				inset = lerpf(tarmac_inset.x, tarmac_inset.y, hash01(salt, seed_value + 102))
			result.append({
				"distance": cursor,
				"side": side,
				"eager": eager,
				"inset": inset,
			})
			if result.size() < max_count and hash01(salt, seed_value + 96) > (1.0 - both_chance):
				var other_eager: bool = hash01(salt, seed_value + 97) > (1.0 - other_eager_chance)
				var far_inset: float = lerpf(other_inset.x, other_inset.y, hash01(salt, seed_value + 98))
				if other_eager:
					far_inset = lerpf(other_eager_inset.x, other_eager_inset.y, hash01(salt, seed_value + 99))
				result.append({
					"distance": cursor + both_offset,
					"side": -side,
					"eager": other_eager,
					"inset": far_inset,
				})
		cursor += spacing * lerpf(spacing_scale.x, spacing_scale.y, hash01(salt, seed_value + 100))
	return result
