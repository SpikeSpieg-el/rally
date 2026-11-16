## Процедурная БЕСКОНЕЧНАЯ дорога для аркадного режима: двухполосный
## просёлок, который местами превращается в горный серпантин.
##
## Отличие от RallyTrackGenerator (раллийный спецучасток): здесь нет «финиша»
## и нет единственной кривой на всю трассу. Дорога режется на участки (legs)
## фиксированной длины, и каждый собирается независимо — только по своему
## индексу и сиду. Отсюда три свойства, ради которых это отдельный класс:
##   * генерация стоит O(один участок), а не O(вся трасса): можно ехать вечно;
##   * участок строится в любом порядке и в любой момент (стриминг чанками,
##     телепорт, отладочный прыжок на 50-й км);
##   * один сид и один километраж всегда дают одну и ту же точку — чанк,
##     построенный заново после выгрузки, встаёт ровно на место старого.
##
## ЧТО ЗАВИСИТ ОТ РАССТОЯНИЯ, А ЧТО ОТ СВЁРТКИ
## ------------------------------------------
## Высота и ширина полотна — чистые функции километража (`elevation_at`,
## `half_width_at`). Поэтому на стыке участков они совпадают по построению, а
## не «примерно»: сшивать их нечем и незачем.
##
## Высота — сумма трёх синусов. Их амплитуды нормируются на бюджет уклона
## 0.9·tg(7°), поэтому предел уклона гарантирован аналитически: никаких
## «прижимающих» проходов, которые могли бы увести конец участка не туда, где
## его ждёт следующий.
##
## Курс и координаты свёрткой не выражаются — их считает обход участка
## (`_walk_leg`). Чтобы стык не разъехался, обход ОДИН и тот же для сборки
## точек и для вычисления границы: `_domain_pieces` задаёт куски (прямые и
## дуги), а `_walk_leg` с `target == null` проходит их, ничего не записывая.
## Свёртка границы достраивается вперёд от ближайшей известной: без рекурсии
## (на 5000-м участке она переполнила бы стек) и без O(n²).
##
## Ширина полосы (половина) по доменам: серпантин 3.2, деревня 3.4, мост 3.0,
## разгон 4.4 м. Переход между доменами — внутри домена, поэтому на границе
## участков ширина непрерывна.
class_name RallyArcadeRoad
extends RefCounted

const LegType = preload("res://scripts/data/rally_arcade_leg.gd")

## Длина участка (чанка) генерации, м.
const LEG_LENGTH: float = 260.0
## Шаг «шагающего» построения, м.
const WALK_STEP: float = 2.0
## Предел уклона (градусы). Соблюдается автоматически, см. `_ensure_waves`.
const MAX_GRADE_DEG: float = 7.0
## Ширина полосы по умолчанию: две полосы по 3.6 плюс обочины.
const DEFAULT_HALF_WIDTH: float = 3.6
## Сколько участков держать в кэше. Кэш только ускоряет повторные запросы
## (возврат назад по трассе), на корректность не влияет.
const LEG_CACHE_LIMIT: int = 32
## Сколько границ участков помнить. Границы — это «ось» координат; при
## переполнении кэш сбрасывается, и цепочка достраивается заново.
const BOUNDARY_CACHE_LIMIT: int = 16384
## За сколько метров до смены домена ширина начинает перестраиваться.
const WIDTH_BLEND: float = 40.0

## Ось трассы: медленно качающийся «генеральный курс», к которому дорога
## подтягивается внутри каждого домена. Волны (длина, м; амплитуда, рад)
## ограничены, поэтому курс дороги всегда в пределах ±0.9 рад от стартового —
## иначе дорога на длинной дистанции свернулась бы сама в себя.
const AXIS_WAVES := [3400.0, 1250.0]
const AXIS_AMPLITUDES := [0.42, 0.16]
## Максимальный нетто-поворот одного домена ради сближения с осью, рад.
## Ось поворачивает медленно (~0.002 рад/м), так что на домен приходится
## 0.1–0.25 рад; ограничение — страховка, а не рабочий режим.
const MAX_DOMAIN_TURN: float = 0.45
## Ниже этого угла дуга не должна сжиматься при привязке поворота, рад.
const MIN_PINNED_SWEEP: float = 0.10
## Предел угла одной дуги, рад.
const MAX_SWEEP: float = 3.0

## Гармоники высотного профиля: (длина волны, м; амплитуда, м).
const WAVE_LENGTHS := [2200.0, 760.0, 380.0]
const WAVE_AMPLITUDES := [26.0, 4.0, 0.9]


## Один собранный участок.
class Leg:
	extends RefCounted
	var index: int = 0
	## Точки осевой линии ~каждые WALK_STEP метров (y — высота).
	var points: PackedVector3Array = PackedVector3Array()
	## Километраж от старта трассы для каждой точки.
	var along: PackedFloat32Array = PackedFloat32Array()
	## Половина ширины полотна в каждой точке.
	var half_width: PackedFloat32Array = PackedFloat32Array()
	## Домены участка и километраж их начала.
	var domains: Array = []
	var domain_starts: PackedFloat32Array = PackedFloat32Array()
	## Пешеходные переходы (километраж трассы).
	var crossings: PackedFloat32Array = PackedFloat32Array()
	## Дома деревни: Vector4(x, y — высота пола, z, yaw).
	var houses: Array = []
	## Граница участка: тот же вход для следующего.
	var end_x: float = 0.0
	var end_z: float = 0.0
	var end_heading: float = 0.0
	var end_height: float = 0.0
	var end_half_width: float = DEFAULT_HALF_WIDTH

	func start_along() -> float:
		return 0.0 if along.is_empty() else along[0]

	func end_along() -> float:
		return 0.0 if along.is_empty() else along[along.size() - 1]

	func domain_at(distance: float) -> int:
		var result: int = int(domains[0]) if not domains.is_empty() else 0
		for i in range(domain_starts.size()):
			if domain_starts[i] <= distance:
				result = int(domains[i])
		return result

	## Индекс точки, ближайшей к километражу (двоичный поиск).
	func index_at(distance: float) -> int:
		var low: int = 0
		var high: int = along.size() - 1
		if high <= 0:
			return 0
		if distance <= along[0]:
			return 0
		if distance >= along[high]:
			return high
		while low < high - 1:
			var mid: int = (low + high) >> 1
			if along[mid] <= distance:
				low = mid
			else:
				high = mid
		return low

	## Точка осевой линии с интерполяцией.
	func point_at(distance: float) -> Vector3:
		if points.is_empty():
			return Vector3.ZERO
		var i: int = index_at(distance)
		var j: int = mini(i + 1, points.size() - 1)
		var a: float = along[i]
		var b: float = along[j]
		var t: float = 0.0 if b <= a else clampf((distance - a) / (b - a), 0.0, 1.0)
		return points[i].lerp(points[j], t)

	## Горизонтальное направление (единичное).
	func direction_at(distance: float) -> Vector3:
		if points.size() < 2:
			return Vector3.FORWARD
		var i: int = index_at(distance)
		var k: int = maxi(0, i - 1)
		var j: int = mini(i + 2, points.size() - 1)
		if j <= k:
			j = mini(k + 1, points.size() - 1)
		var dir: Vector3 = Vector3(points[j].x - points[k].x, 0.0, points[j].z - points[k].z)
		if dir.length_squared() < 0.000001:
			return Vector3.FORWARD
		return dir.normalized()

	## Половина ширины полотна (интерполяция).
	func half_width_at(distance: float) -> float:
		if half_width.is_empty():
			return DEFAULT_HALF_WIDTH
		var i: int = index_at(distance)
		var j: int = mini(i + 1, half_width.size() - 1)
		var a: float = along[i]
		var b: float = along[j]
		var t: float = 0.0 if b <= a else clampf((distance - a) / (b - a), 0.0, 1.0)
		return lerpf(half_width[i], half_width[j], t)


## План участка: домены и их доли длины.
class Plan:
	extends RefCounted
	var domains: Array = []
	var fraction: PackedFloat32Array = PackedFloat32Array()

	func slots() -> int:
		return domains.size()

	func share(index: int) -> float:
		return fraction[index] if index < fraction.size() else 0.0

	func has(kind: int) -> bool:
		return domains.has(kind)


static var _leg_cache := {}
static var _cache_order: Array[int] = []
static var _cache_seed: int = 0x7fffffff
static var _boundary_cache := {}
static var _plan_cache := {}
static var _wave_seed: int = 0x7fffffff
static var _wave_len := PackedFloat32Array()
static var _wave_amp := PackedFloat32Array()
static var _wave_phase := PackedFloat32Array()
static var _axis_seed: int = 0x7fffffff
static var _axis_phase := PackedFloat32Array()


# ------------------------------------------------------------- детерминизм


## Детерминированный псевдошум [0,1). Тот же стиль, что у RallyRoadProfile:
## без RandomNumberGenerator, поэтому порядок вызовов не влияет на результат.
static func roll(index: int, seed_value: int, salt: int) -> float:
	var n: int = posmod(index, 1000003) * 92821 + posmod(seed_value, 1000003) * 68917 + salt * 2833
	n = posmod((n ^ (n >> 13)) * 127, 1000003)
	return float(n) / 1000003.0


static func roll_range(index: int, seed_value: int, salt: int, low: float, high: float) -> float:
	return lerpf(low, high, roll(index, seed_value, salt))


## Сброс кэшей при смене сида (новый заезд).
static func reset(seed_value: int) -> void:
	if seed_value == _cache_seed:
		return
	_leg_cache.clear()
	_cache_order.clear()
	_boundary_cache.clear()
	_plan_cache.clear()
	_cache_seed = seed_value
	_wave_seed = 0x7fffffff
	_axis_seed = 0x7fffffff
	_ensure_waves(seed_value)
	_ensure_axis(seed_value)


static func _store(cache: Dictionary, key: int, value: Variant) -> void:
	if cache.size() > 8192:
		cache.clear()
	cache[key] = value


# ------------------------------------------------------------ координаты


static func leg_index_at(distance: float) -> int:
	return floori(distance / LEG_LENGTH)


static func leg_start(leg_index: int) -> float:
	return float(leg_index) * LEG_LENGTH


## Курс на старте всей трассы: почти вдоль +Z, с лёгким случайным сносом.
static func initial_heading(seed_value: int) -> float:
	# Индекс отрицательный: roll_range ожидает int, и старт не должен
	# совпадать с «участком 0» по шуму.
	return roll_range(-1, seed_value, 7, -0.30, 0.30)


# --------------------------------------------------------------- профиль


## Бюджет уклона: 90 % от tg(7°). Оставшиеся 10 % — запас на дискретизацию.
static func _grade_budget() -> float:
	return 0.9 * tan(deg_to_rad(MAX_GRADE_DEG))


## Нормированные гармоники высот для сида. Сумма «наклонных амплитуд»
## A·2π/L ограничивается бюджетом уклона, поэтому производная профиля нигде
## не превышает 7° — и прижимать её не нужно.
static func _ensure_waves(seed_value: int) -> void:
	if seed_value == _wave_seed and _wave_len.size() > 0:
		return
	_wave_seed = seed_value
	_wave_len.clear()
	_wave_amp.clear()
	_wave_phase.clear()
	var slope_sum: float = 0.0
	for i in range(WAVE_LENGTHS.size()):
		var wavelength: float = float(WAVE_LENGTHS[i]) * roll_range(i, seed_value, 401, 0.88, 1.12)
		var amplitude: float = float(WAVE_AMPLITUDES[i]) * roll_range(i, seed_value, 402, 0.55, 1.0)
		_wave_len.append(wavelength)
		_wave_amp.append(amplitude)
		_wave_phase.append(roll_range(i, seed_value, 403, 0.0, TAU))
		slope_sum += amplitude * TAU / wavelength
	var scale: float = _grade_budget() / maxf(slope_sum, 0.000001)
	if scale < 1.0:
		for i in range(_wave_amp.size()):
			_wave_amp[i] = _wave_amp[i] * scale


## Высота полотна на километраже. Чистая функция: стык участков и повторная
## сборка чанка дают одно и то же значение.
static func elevation_at(distance: float, seed_value: int) -> float:
	_ensure_waves(seed_value)
	var height: float = 0.0
	for i in range(_wave_len.size()):
		height += _wave_amp[i] * sin(distance / _wave_len[i] * TAU + _wave_phase[i])
	return height


static func _ensure_axis(seed_value: int) -> void:
	if seed_value == _axis_seed and _axis_phase.size() > 0:
		return
	_axis_seed = seed_value
	_axis_phase.clear()
	for i in range(AXIS_WAVES.size()):
		_axis_phase.append(roll_range(i, seed_value, 411, 0.0, TAU))


## «Генеральный курс» трассы на километраже: ось, вокруг которой дорога
## гуляет. Медленная и ограниченная по амплитуде — этим трасса гарантированно
## не заворачивает назад и не пересекает сама себя.
static func axis_heading(distance: float, seed_value: int) -> float:
	_ensure_axis(seed_value)
	var heading: float = initial_heading(seed_value)
	for i in range(AXIS_WAVES.size()):
		heading += AXIS_AMPLITUDES[i] * sin(distance / float(AXIS_WAVES[i]) * TAU + _axis_phase[i])
	return heading


## «Целевая» ширина домена (половина полотна), м.
static func domain_half_width(domain: int, leg_index: int, seed_value: int) -> float:
	match domain:
		LegType.Kind.SERPENTINE:
			return clampf(3.2 * roll_range(leg_index, seed_value, 11, 0.94, 1.06), 2.9, 4.8)
		LegType.Kind.FAST:
			return 4.4
		LegType.Kind.VILLAGE:
			return 3.4
		LegType.Kind.BRIDGE:
			return 3.0
	return DEFAULT_HALF_WIDTH


## Ширина предыдущего домена (для плавного входа в текущий). На границе
## участков берётся последний домен предыдущего участка — поэтому ширина
## непрерывна и там.
static func _previous_half_width(leg_index: int, slot: int, seed_value: int) -> float:
	var plan := plan_for(leg_index, seed_value)
	if slot > 0:
		return domain_half_width(int(plan.domains[slot - 1]), leg_index, seed_value)
	if leg_index <= 0:
		return DEFAULT_HALF_WIDTH
	var previous := plan_for(leg_index - 1, seed_value)
	if previous.slots() == 0:
		return DEFAULT_HALF_WIDTH
	return domain_half_width(int(previous.domains[previous.slots() - 1]), leg_index - 1, seed_value)


## Половина ширины полотна на километраже. Чистая функция, как и высота.
static func half_width_at(distance: float, seed_value: int) -> float:
	var leg_index: int = leg_index_at(distance)
	var plan := plan_for(leg_index, seed_value)
	if plan.slots() == 0:
		return DEFAULT_HALF_WIDTH
	var local: float = distance - leg_start(leg_index)
	var cursor: float = 0.0
	for slot in range(plan.slots()):
		var slot_length: float = LEG_LENGTH * plan.share(slot)
		var inside: bool = local <= cursor + slot_length or slot == plan.slots() - 1
		if not inside:
			cursor += slot_length
			continue
		var goal: float = domain_half_width(int(plan.domains[slot]), leg_index, seed_value)
		var from: float = _previous_half_width(leg_index, slot, seed_value)
		# Окно перехода не длиннее половины домена: короткий домен успевает
		# прийти к своей ширине, поэтому на выходе значение всегда `goal`.
		var window: float = minf(WIDTH_BLEND, slot_length * 0.5)
		var blend: float = 1.0 if window <= 0.001 else clampf((local - cursor) / window, 0.0, 1.0)
		return lerpf(from, goal, smoothstep(0.0, 1.0, blend))
	return DEFAULT_HALF_WIDTH


# --------------------------------------------------------------- границы


static func plan_for(leg_index: int, seed_value: int) -> Plan:
	var key: int = leg_index * 131071 + (seed_value & 0xffff)
	if _plan_cache.has(key):
		return _plan_cache[key] as Plan
	var plan := Plan.new()
	plan.domains = LegType.plan(leg_index, seed_value)
	var total: float = 0.0
	for domain in plan.domains:
		total += LegType.domain_weight(int(domain))
	plan.fraction.resize(plan.domains.size())
	for i in range(plan.domains.size()):
		plan.fraction[i] = LegType.domain_weight(int(plan.domains[i])) / maxf(total, 0.001)
	_store(_plan_cache, key, plan)
	return plan


## Состояние на НАЧАЛЕ участка: точка и курс. Высота и ширина сюда не входят —
## они чистые функции километража и совпадают сами.
##
## Достраивается вперёд от ближайшей известной границы. Один и тот же участок
## проходится свёрткой не больше одного раза за сид, поэтому стоимость
## амортизированная O(1) на участок.
static func leg_start_state(leg_index: int, seed_value: int) -> Dictionary:
	if seed_value != _cache_seed:
		reset(seed_value)
	if leg_index <= 0:
		return {"x": 0.0, "z": 0.0, "heading": initial_heading(seed_value)}
	if _boundary_cache.has(leg_index):
		return _boundary_cache[leg_index]
	# `_boundary_cache[m]` — состояние на НАЧАЛЕ участка m, поэтому ищем
	# ближайшее известное начало среди 1..leg_index-1 и достраиваем вперёд.
	var known: int = leg_index - 1
	while known > 0 and not _boundary_cache.has(known):
		known -= 1
	var cursor: Dictionary = {"x": 0.0, "z": 0.0, "heading": initial_heading(seed_value)}
	if _boundary_cache.has(known):
		cursor = _boundary_cache[known]
	for n in range(known, leg_index):
		cursor = _fold_leg(n, seed_value, cursor)
		if _boundary_cache.size() >= BOUNDARY_CACHE_LIMIT:
			_boundary_cache.clear()
		_boundary_cache[n + 1] = cursor
	return cursor


## Прогон участка без записи точек: тот же обход, что и при сборке.
static func _fold_leg(leg_index: int, seed_value: int, start: Dictionary) -> Dictionary:
	var frame: Dictionary = _walk_leg(
		leg_index, seed_value,
		float(start.x), float(start.z), float(start.heading),
		null, leg_start(leg_index)
	)
	return {"x": float(frame.x), "z": float(frame.z), "heading": float(frame.heading)}


## Граница участка (== начало следующего): x, z, курс, высота, ширина.
static func leg_boundary(leg_index: int, seed_value: int) -> Dictionary:
	var state: Dictionary = leg_start_state(leg_index + 1, seed_value)
	var along: float = leg_start(leg_index + 1)
	return {
		"x": float(state.x), "z": float(state.z), "heading": float(state.heading),
		"height": elevation_at(along, seed_value),
		"half_width": half_width_at(along, seed_value),
	}


# ------------------------------------------------------------ сборка


## Собранный участок (из кэша или новый).
static func leg(leg_index: int, seed_value: int) -> Leg:
	if seed_value != _cache_seed:
		reset(seed_value)
	if _leg_cache.has(leg_index):
		return _leg_cache[leg_index] as Leg
	var built := _build_leg(leg_index, seed_value)
	_leg_cache[leg_index] = built
	_cache_order.append(leg_index)
	while _cache_order.size() > LEG_CACHE_LIMIT:
		var evicted: int = _cache_order.pop_front()
		_leg_cache.erase(evicted)
	return built


static func _build_leg(leg_index: int, seed_value: int) -> Leg:
	var result := Leg.new()
	result.index = leg_index
	var start: Dictionary = leg_start_state(leg_index, seed_value)
	var start_along: float = leg_start(leg_index)
	# Первая точка — ровно та же, что последняя у предыдущего участка:
	# координаты совпадают по свёртке, высота — по чистому профилю.
	result.points.append(Vector3(
		float(start.x), elevation_at(start_along, seed_value), float(start.z)
	))
	result.along.append(start_along)
	var walked: Dictionary = _walk_leg(
		leg_index, seed_value,
		float(start.x), float(start.z), float(start.heading),
		result, start_along
	)
	# Высота и ширина — функции километража, а не накопленные величины: они не
	# могут «уехать» и на стыке совпадают с соседним участком.
	for i in range(result.points.size()):
		var point: Vector3 = result.points[i]
		var distance: float = result.along[i]
		result.points[i] = Vector3(point.x, elevation_at(distance, seed_value), point.z)
		result.half_width.append(half_width_at(distance, seed_value))
	result.end_x = float(walked.x)
	result.end_z = float(walked.z)
	result.end_heading = float(walked.heading)
	result.end_height = elevation_at(leg_start(leg_index + 1), seed_value)
	result.end_half_width = half_width_at(leg_start(leg_index + 1), seed_value)
	_decorate(result, seed_value)
	return result


## Обход участка: пишет точки в `target` (если он есть) и всегда возвращает
## фактическое состояние на конце. Одна и та же арифметика для сборки и для
## свёртки границы — см. `_fold_leg`.
static func _walk_leg(
	leg_index: int, seed_value: int,
	start_x: float, start_z: float, start_heading: float,
	target: Leg, start_along: float
) -> Dictionary:
	var plan := plan_for(leg_index, seed_value)
	var x: float = start_x
	var z: float = start_z
	var heading: float = start_heading
	var along: float = start_along
	for slot in range(plan.slots()):
		var domain: int = int(plan.domains[slot])
		var length: float = LEG_LENGTH * plan.share(slot)
		if target != null:
			target.domains.append(domain)
			target.domain_starts.append(along)
		var frame: Dictionary = _emit_domain(
			domain, leg_index, seed_value, slot, length,
			x, z, heading, target, along
		)
		x = float(frame.x)
		z = float(frame.z)
		heading = float(frame.heading)
		along = float(frame.along)
	return {"x": x, "z": z, "heading": heading, "along": along}


## Куски (segments), из которых состоит домен. ОДИН источник правды и для
## сборки точек, и для свёртки границы: курс на выходе всегда совпадает с
## фактическим, поэтому стык чанков не разъезжается.
static func _domain_pieces(
	domain: int, leg_index: int, seed_value: int, slot: int, length: float
) -> Array:
	var pieces: Array = []
	match domain:
		LegType.Kind.SERPENTINE:
			# Сначала шпильки: длина их ДУГ (радиус × угол) заметно больше
			# предполагаемых 34 м на разворот, поэтому остаток длины делят
			# между собой уже площадки — по факту, а не по прикидке.
			# Чётное число шпилек — принципиально: они чередуют сторону, и
			# после пары «туда-обратно» дорога возвращается к прежнему курсу.
			# С нечётным серпантин всегда уходил бы в сторону на 150–170°, и
			# привязка к оси была бы вынуждена ломать сами шпильки.
			var hairpins: int = 2 * maxi(1, int(length / 150.0))
			var arcs: Array = []
			var arc_total: float = 0.0
			var direction: float = 1.0 if roll(leg_index * 7, seed_value, 311) < 0.5 else -1.0
			for i in range(hairpins):
				var radius: float = roll_range(leg_index * 7 + i, seed_value, 312, 12.0, 17.5)
				var sweep: float = deg_to_rad(roll_range(leg_index * 7 + i, seed_value, 313, 140.0, 172.0))
				# Угол дуги знаковый: направление поворота живёт в знаке, а не в
				# отдельном поле — при привязке к оси менять знак нельзя.
				arcs.append({"kind": "a", "radius": radius, "sweep": sweep * direction})
				arc_total += radius * absf(sweep)
				direction = -direction
			var shelf: float = clampf((length - arc_total) / float(hairpins + 1), 4.0, 34.0)
			pieces.append({"kind": "s", "length": shelf})
			for i in range(hairpins):
				pieces.append(arcs[i])
				var next_shelf: float = shelf if i < hairpins - 1 else shelf * 0.7
				pieces.append({"kind": "s", "length": next_shelf})
		LegType.Kind.BRIDGE:
			var bridge_dir: float = 1.0 if roll(leg_index, seed_value, 322) < 0.5 else -1.0
			var bridge_sweep: float = roll_range(leg_index, seed_value, 321, 0.10, 0.16) * bridge_dir
			pieces = [
				{"kind": "s", "length": length * 0.30},
				{"kind": "a", "radius": 200.0, "sweep": bridge_sweep},
				{"kind": "s", "length": length * 0.45},
				{"kind": "s", "length": length * 0.25},
			]
		_:
			# Просёлок/разгон/деревня — «связка» из дуг и прямых.
			var twist: float = 0.55
			if domain == LegType.Kind.FAST:
				twist = 0.24
			elif domain == LegType.Kind.VILLAGE:
				twist = 0.10
			var index: int = leg_index * 17 + slot * 5
			var cursor: float = 0.0
			# Дуги чередуются по стороне: дорога «гуляет» S-образно, а не
			# накапливает поворот в одну сторону (иначе за несколько доменов
			# она описала бы полный круг).
			var turn_side: float = 1.0 if roll(index, seed_value, 304) < 0.5 else -1.0
			while cursor < length - 1.0:
				var radius: float = roll_range(index, seed_value, 302, 62.0, 150.0)
				if domain == LegType.Kind.VILLAGE:
					radius = 240.0
				var sweep: float = roll_range(index, seed_value, 303, 0.22, 1.05) * (0.55 + twist)
				var sign_side: float = turn_side
				turn_side = -turn_side
				var straight: float = roll_range(index, seed_value, 305, 14.0, 58.0)
				if domain == LegType.Kind.VILLAGE:
					sweep = 0.16
					straight = length - cursor
				var arc_len: float = radius * sweep
				if cursor + arc_len + straight > length + 12.0:
					straight = maxf(0.0, length - cursor - arc_len)
				if straight > 0.0:
					pieces.append({"kind": "s", "length": straight})
					cursor += straight
				if arc_len > 0.001 and cursor < length:
					var use_sweep: float = sweep
					if cursor + arc_len > length:
						use_sweep = sweep * maxf(0.0, (length - cursor) / maxf(arc_len, 0.001))
					pieces.append({"kind": "a", "radius": radius, "sweep": use_sweep * sign_side})
					cursor += radius * absf(use_sweep)
				index += 1
				if domain == LegType.Kind.VILLAGE:
					break
	return _fit_length(pieces, length)


## Довести сумму кусков домена до ровно `length`: без этого участок
## «уезжает» на десятки метров, и километраж в HUD/очках перестаёт совпадать
## с реальной дорогой. Разница всегда уходит в последний прямой кусок
## (дугу резать нельзя — изменится курс на выходе).
static func _fit_length(pieces: Array, length: float) -> Array:
	var total: float = 0.0
	for piece in pieces:
		if piece.kind == "s":
			total += float(piece.length)
		else:
			total += float(piece.radius) * absf(float(piece.sweep))
	var diff: float = length - total
	if absf(diff) <= 0.01:
		return pieces
	if diff > 0.0:
		pieces.append({"kind": "s", "length": diff})
		return pieces
	# Не хватает: срезаем с конца по прямым кускам.
	var left: float = -diff
	for i in range(pieces.size() - 1, -1, -1):
		if pieces[i].kind != "s":
			continue
		var piece_length: float = float(pieces[i].length)
		var take: float = minf(piece_length, left)
		piece_length -= take
		left -= take
		if piece_length <= 0.01:
			pieces.remove_at(i)
		else:
			pieces[i]["length"] = piece_length
		if left <= 0.01:
			break
	return pieces


## Привязать нетто-поворот домена к `turn`, НЕ меняя длину пути.
##
## Каждая дуга описывает arc = R·|sweep| метров. Добавка угла `sweep` на
## величину δ пересчитывает радиус как R = arc/|sweep|, то есть дуга проходит
## те же метры, но с другим поворотом. Сумма добавок по домену равна `turn`,
## поэтому курс на выходе — ровно тот, который заказан, а стыки чанков и
## километраж не сдвигаются ни на сантиметр.
static func _pin_turn(pieces: Array, turn: float) -> void:
	var arcs: Array = []
	var net: float = 0.0
	var arc_total: float = 0.0
	for piece in pieces:
		if piece.kind != "a":
			continue
		var arc_length: float = float(piece.radius) * absf(float(piece.sweep))
		arcs.append(piece)
		net += float(piece.sweep)
		arc_total += arc_length
	if arcs.is_empty() or arc_total < 1.0:
		return
	var delta: float = turn - net
	# Два прохода: второй достаёт остаток, если первый упёрся в MIN_PINNED_SWEEP.
	for _pass in range(2):
		if absf(delta) < 0.0001:
			return
		var share_total: float = 0.0
		for piece in arcs:
			if absf(float(piece.sweep)) > MIN_PINNED_SWEEP:
				share_total += float(piece.radius) * absf(float(piece.sweep))
		if share_total < 0.001:
			return
		var used: float = 0.0
		for piece in arcs:
			var arc_length: float = float(piece.radius) * absf(float(piece.sweep))
			if absf(float(piece.sweep)) <= MIN_PINNED_SWEEP:
				continue
			var add: float = delta * arc_length / share_total
			var sweep: float = float(piece.sweep) + add
			var sign_before: float = signf(float(piece.sweep))
			if sign_before != 0.0 and signf(sweep) != sign_before:
				# Дуга не должна развернуться в другую сторону от добавки.
				sweep = sign_before * MIN_PINNED_SWEEP
			sweep = clampf(sweep, -MAX_SWEEP, MAX_SWEEP)
			used += sweep - float(piece.sweep)
			piece["sweep"] = sweep
			piece["radius"] = arc_length / maxf(absf(sweep), 0.0001)
		delta -= used
		if absf(delta) < 0.02:
			return
		# Остаток — в самую «щедрую» дугу (ей есть куда расти).
		var biggest: Dictionary = arcs[0]
		var biggest_arc: float = 0.0
		for piece in arcs:
			var arc_here: float = float(piece.radius) * absf(float(piece.sweep))
			if arc_here > biggest_arc:
				biggest_arc = arc_here
				biggest = piece
		var arc_length_big: float = biggest_arc
		var sweep_big: float = clampf(float(biggest.sweep) + delta, -MAX_SWEEP, MAX_SWEEP)
		delta -= sweep_big - float(biggest.sweep)
		biggest["sweep"] = sweep_big
		biggest["radius"] = arc_length_big / maxf(absf(sweep_big), 0.0001)


## Прогон кусков домена. Пишет точки в target (если он есть) и всегда
## возвращает фактическое состояние на конце.
static func _emit_domain(
	domain: int, leg_index: int, seed_value: int, slot: int, length: float,
	x: float, z: float, heading: float, target: Leg, along: float
) -> Dictionary:
	var pieces := _domain_pieces(domain, leg_index, seed_value, slot, length)
	# Нетто-поворот домена привязывается к оси трассы: после каждого домена
	# курс равен оси, поэтому на всей бесконечной дороге он остаётся в узком
	# конусе и дорога не может свернуться сама в себя.
	var wanted: float = axis_heading(along + length, seed_value)
	_pin_turn(pieces, clampf(wrapf(wanted - heading, -PI, PI), -MAX_DOMAIN_TURN, MAX_DOMAIN_TURN))
	var step: float = WALK_STEP
	for piece in pieces:
		if piece.kind == "s":
			var remaining: float = float(piece.length)
			while remaining > 0.0001:
				var straight_step: float = minf(step, remaining)
				x += cos(heading) * straight_step
				z += sin(heading) * straight_step
				along += straight_step
				remaining -= straight_step
				if target != null:
					target.points.append(Vector3(x, 0.0, z))
					target.along.append(along)
		else:
			var radius: float = maxf(6.0, float(piece.radius))
			var sweep: float = float(piece.sweep)
			var arc_length: float = radius * absf(sweep)
			var count: int = maxi(2, ceili(arc_length / step))
			var delta: float = sweep / float(count)
			var arc_step: float = radius * absf(delta)
			for _i in range(count):
				heading += delta
				x += cos(heading) * arc_step
				z += sin(heading) * arc_step
				along += arc_step
				if target != null:
					target.points.append(Vector3(x, 0.0, z))
					target.along.append(along)
	return {"x": x, "z": z, "heading": heading, "along": along}


## Деревня и переходы — после высот: дома ставятся на фактическую землю.
static func _decorate(target: Leg, seed_value: int) -> void:
	for slot in range(target.domains.size()):
		if int(target.domains[slot]) != LegType.Kind.VILLAGE:
			continue
		var start: float = target.domain_starts[slot]
		var end_along: float = target.end_along()
		if slot + 1 < target.domain_starts.size():
			end_along = target.domain_starts[slot + 1]
		_add_village(target, seed_value, start, end_along)


## Деревня: дома по сторонам и один пешеходный переход в середине проезда.
static func _add_village(target: Leg, seed_value: int, start: float, end_along: float) -> void:
	if end_along <= start + 4.0 or target.along.size() < 2:
		return
	target.crossings.append(lerpf(start, end_along, 0.5))
	var distance: float = start + 12.0
	var side: float = 1.0
	var house_index: int = 0
	while distance < end_along - 10.0:
		var point: Vector3 = target.point_at(distance)
		var dir: Vector3 = target.direction_at(distance)
		var right: Vector3 = Vector3(dir.z, 0.0, -dir.x)
		var setback: float = roll_range(house_index, seed_value, 331, 5.0, 9.0)
		var offset: float = target.half_width_at(distance) + setback
		var position: Vector3 = point + right * offset * side
		target.houses.append(Vector4(position.x, point.y, position.z, atan2(dir.x, dir.z) + side * 0.35))
		side = -side
		distance += roll_range(house_index, seed_value, 332, 17.0, 27.0)
		house_index += 1
