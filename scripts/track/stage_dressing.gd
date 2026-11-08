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
