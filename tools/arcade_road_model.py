"""Численный прототип аркадного генератора (`scripts/arcade/arcade_road.gd`).

Тот же алгоритм, что в GDScript, но на Python — чтобы проверять инварианты
без Godot: стыки чанков, длину участка, предел уклона, непрерывность ширины и
(самое важное) отсутствие самопересечений на длинной дистанции.

Зачем копия, а не вызов GDScript: движка в CI нет, headless-режим недоступен, а
геометрия бесконечной дороги — это ровно та часть, которую глазами в игре не
проверишь. Копия обязана совпадать с оригиналом по формулам: если меняется
`arcade_road.gd`, меняется и этот файл (иначе тест проверяет не то, что
играет).

Запуск: python3 tools/arcade_road_model.py [сид]
"""
import math

LEG_LENGTH = 260.0
WALK_STEP = 2.0
MAX_GRADE_DEG = 7.0
DEFAULT_HALF_WIDTH = 5.0
WIDTH_BLEND = 40.0
WAVE_LENGTHS = (2200.0, 760.0, 380.0)
WAVE_AMPLITUDES = (26.0, 4.0, 0.9)
AXIS_WAVES = (3400.0, 1250.0)
AXIS_AMPLITUDES = (0.42, 0.16)
MAX_DOMAIN_TURN = 0.45
MIN_PINNED_SWEEP = 0.10
MAX_SWEEP = 3.0

SERPENTINE, COUNTRY, VILLAGE, BRIDGE, FAST = 0, 1, 2, 3, 4
DOMAIN_WEIGHTS = {SERPENTINE: 0.62, VILLAGE: 0.16, BRIDGE: 0.14, FAST: 0.30}
DEFAULT_WEIGHT = 0.38


_M63 = (1 << 63) - 1


def roll(index, seed, salt):
    """Детерминированный шум [0,1).

    Точная копия GDScript-версии (int в Godot — знаковый 64-битный, умножение
    переполняется с оборотом). После каждой ступени финализатора splitmix64
    маскируем 63 бита: тогда все сдвиги вправо идут по неотрицательному
    числу и арифметический сдвиг GDScript совпадает с логическим в Python.

    Прежняя версия сводилась к почти арифметической прогрессии по индексу
    (соседние индексы отличались на постоянный шаг ≈ 0.21 по модулю 1),
    поэтому радиусы/углы кусков шли «пилой», и дорога повторяла один и тот
    же ритм из раза в раз.
    """
    n = (index % 1000003) * 92821 + (seed % 1000003) * 68917 + salt * 2833
    n = ((n ^ (n >> 30)) * 0xbf58476d1ce4e5b9) & _M63
    n = ((n ^ (n >> 27)) * 0x94d049bb133111eb) & _M63
    n = (n ^ (n >> 31)) & _M63
    return (n & 0xffffffff) / 4294967296.0


def roll_range(index, seed, salt, low, high):
    return low + (high - low) * roll(index, seed, salt)


def wrapf(value, low, high):
    span = high - low
    return (value - low) % span + low


# ------------------------------------------------------------------ план


def plan(seed, leg):
    if leg < 0:
        # Виртуальный участок «до старта» нужен только для непрерывности
        # ширины на километре 0: пусть это будет нейтральный просёлок.
        return [COUNTRY]
    first = roll(leg, seed, 101)
    if first < 0.34:
        domains = [SERPENTINE]
    elif first < 0.62:
        domains = [COUNTRY]
    elif first < 0.80:
        domains = [FAST]
    else:
        domains = [VILLAGE]
    second = roll(leg, seed, 102)
    if domains[0] == SERPENTINE:
        if second < 0.55:
            domains.append(COUNTRY)
    elif second < 0.42:
        domains.append(COUNTRY)
    elif second < 0.72:
        domains.append(FAST)
    elif second < 0.90:
        domains.append(VILLAGE)
    if VILLAGE in domains and second > 0.55:
        domains.append(BRIDGE)
    return domains


def domain_weight(domain):
    return DOMAIN_WEIGHTS.get(domain, DEFAULT_WEIGHT)


def shares(seed, leg):
    domains = plan(seed, leg)
    total = sum(domain_weight(kind) for kind in domains)
    return [(kind, domain_weight(kind) / max(total, 0.001)) for kind in domains]


_CACHE = {}


def _cached(seed):
    return _CACHE.setdefault(seed, {'waves': None, 'axis': None, 'start': {}})


def waves(seed):
    state = _cached(seed)
    if state['waves'] is not None:
        return state['waves']
    data = []
    slope_sum = 0.0
    for i, length in enumerate(WAVE_LENGTHS):
        wavelength = length * roll_range(i, seed, 401, 0.88, 1.12)
        amplitude = WAVE_AMPLITUDES[i] * roll_range(i, seed, 402, 0.55, 1.0)
        data.append([wavelength, amplitude, roll_range(i, seed, 403, 0.0, math.tau)])
        slope_sum += amplitude * math.tau / wavelength
    budget = 0.9 * math.tan(math.radians(MAX_GRADE_DEG))
    scale = budget / max(slope_sum, 1e-6)
    if scale < 1.0:
        for item in data:
            item[1] *= scale
    state['waves'] = data
    return data


def elevation_at(distance, seed):
    return sum(a * math.sin(distance / length * math.tau + phase)
               for length, a, phase in waves(seed))


def elevation_slope(distance, seed):
    return sum(a * math.tau / length * math.cos(distance / length * math.tau + phase)
               for length, a, phase in waves(seed))


def axis_phase(seed):
    state = _cached(seed)
    if state['axis'] is None:
        state['axis'] = [roll_range(i, seed, 411, 0.0, math.tau) for i in range(len(AXIS_WAVES))]
    return state['axis']


def axis_waves(seed):
    """Длины волн оси, подмешанные сидом: без этого макро-S дороги повторялся
    строго каждые 3400 м на любом сиде."""
    state = _cached(seed)
    if state.get('axis_waves') is None:
        state['axis_waves'] = [
            AXIS_WAVES[i] * roll_range(i, seed, 412, 0.82, 1.18)
            for i in range(len(AXIS_WAVES))
        ]
    return state['axis_waves']


def initial_heading(seed):
    return roll_range(-1, seed, 7, -0.30, 0.30)


def axis_heading(distance, seed):
    heading = initial_heading(seed)
    for i, wavelength in enumerate(axis_waves(seed)):
        heading += AXIS_AMPLITUDES[i] * math.sin(distance / wavelength * math.tau + axis_phase(seed)[i])
    return heading


# --------------------------------------------------------------- ширина


def domain_half_width(domain, leg, seed):
    if domain == SERPENTINE:
        return min(5.4, max(4.3, 4.6 * roll_range(leg, seed, 11, 0.94, 1.08)))
    if domain == FAST:
        return 5.8
    if domain == VILLAGE:
        return 4.8
    if domain == BRIDGE:
        return 4.5
    return DEFAULT_HALF_WIDTH


def previous_half_width(leg, slot, seed):
    domains = plan(seed, leg)
    if slot > 0:
        return domain_half_width(domains[slot - 1], leg, seed)
    if leg <= 0:
        return DEFAULT_HALF_WIDTH
    before = plan(seed, leg - 1)
    if not before:
        return DEFAULT_HALF_WIDTH
    return domain_half_width(before[-1], leg - 1, seed)


def half_width_at(distance, seed):
    leg = int(math.floor(distance / LEG_LENGTH))
    domains = plan(seed, leg)
    if not domains:
        return DEFAULT_HALF_WIDTH
    local = distance - leg * LEG_LENGTH
    total = sum(domain_weight(kind) for kind in domains)
    cursor = 0.0
    for slot, kind in enumerate(domains):
        slot_length = LEG_LENGTH * (domain_weight(kind) / max(total, 0.001))
        inside = local <= cursor + slot_length or slot == len(domains) - 1
        if not inside:
            cursor += slot_length
            continue
        goal = domain_half_width(kind, leg, seed)
        start = previous_half_width(leg, slot, seed)
        window = min(WIDTH_BLEND, slot_length * 0.5)
        blend = 1.0 if window <= 0.001 else min(1.0, max(0.0, (local - cursor) / window))
        smooth = blend * blend * (3.0 - 2.0 * blend)
        return start + (goal - start) * smooth
    return DEFAULT_HALF_WIDTH


# -------------------------------------------------------------- геометрия


def pieces(domain, leg, seed, slot, length):
    out = []
    if domain == SERPENTINE:
        # Число шпилек зависит от длины домена И от сида: раньше их было
        # всегда ровно две (int(260/150) = 1), и каждый серпантин выглядел
        # как одна и та же заготовка.
        pair_step = roll_range(leg * 7 + 3, seed, 314, 110.0, 190.0)
        pairs = max(1, min(4, int(length / max(pair_step, 1.0))))
        hairpins = 2 * pairs
        arcs = []
        arc_total = 0.0
        direction = 1.0 if roll(leg * 7, seed, 311) < 0.5 else -1.0
        for i in range(hairpins):
            radius = roll_range(leg * 7 + i, seed, 312, 12.5, 19.5)
            sweep = math.radians(roll_range(leg * 7 + i, seed, 313, 118.0, 176.0))
            arcs.append(('a', radius, sweep * direction))
            arc_total += radius * abs(sweep)
            direction = -direction
        base_shelf = max(4.0, min(34.0, (length - arc_total) / (hairpins + 1)))
        out.append(('s', base_shelf))
        for i in range(hairpins):
            out.append(arcs[i])
            # Полки между шпильками тоже разные: у каждой своя длина.
            factor = roll_range(leg * 7 + 31 + i, seed, 315, 0.55, 1.5)
            shelf = max(4.0, min(34.0, base_shelf * factor))
            out.append(('s', shelf if i < hairpins - 1 else shelf * 0.7))
    elif domain == BRIDGE:
        # Мосты раньше были клонами: радиус всегда 200, изгиб 0.10–0.16 и
        # одно и то же деление 30/45/25.
        bridge_dir = 1.0 if roll(leg, seed, 322) < 0.5 else -1.0
        radius = roll_range(leg, seed, 323, 130.0, 260.0)
        sweep = roll_range(leg, seed, 321, 0.06, 0.17) * bridge_dir
        first = length * roll_range(leg, seed, 324, 0.22, 0.36)
        second = length * roll_range(leg, seed, 325, 0.40, 0.55)
        out = [('s', first), ('a', radius, sweep),
               ('s', second), ('s', max(0.0, length - first - second))]
    elif domain == VILLAGE:
        # Деревня — не одна идеальная прямая: 1–3 прямых с лёгкими
        # чередующимися дугами. Бюджет дуг ограничен долей длины, чтобы
        # суммарная длина всегда собиралась в ровно `length`.
        bends = 1 + int(roll(leg * 13, seed, 316) * 3.0)
        side = 1.0 if roll(leg * 13, seed, 317) < 0.5 else -1.0
        radius = 240.0
        arc_budget = 0.0
        sweeps = []
        for i in range(bends):
            sweep = roll_range(leg * 13 + i, seed, 318, 0.05, 0.16) * side
            sweeps.append(sweep)
            arc_budget += radius * abs(sweep)
            side = -side
        cap = length * 0.35
        if arc_budget > cap and arc_budget > 0.001:
            scale = cap / arc_budget
            sweeps = [s * scale for s in sweeps]
            arc_budget = cap
        straight_len = max(6.0, (length - arc_budget) / float(bends))
        for i in range(bends):
            out.append(('s', straight_len))
            out.append(('a', radius, sweeps[i]))
    else:
        twist = 0.55
        if domain == FAST:
            twist = 0.24
        index = leg * 17 + slot * 5
        cursor = 0.0
        turn_side = 1.0 if roll(index, seed, 304) < 0.5 else -1.0
        # «Характер» участка: у одного просёлка дуги шире и длиннее, у
        # другого — частые короткие. Раньше диапазон радиусов был один и
        # тот же на всех участках.
        radius_scale = roll_range(leg, seed, 306, 0.72, 1.35)
        before = 0.0
        while cursor < length - 1.0:
            radius = roll_range(index, seed, 302, 62.0, 150.0) * radius_scale
            radius = max(40.0, min(240.0, radius))
            sweep = roll_range(index, seed, 303, 0.20, 1.10) * (0.55 + twist)
            side = turn_side
            turn_side = -turn_side
            straight = roll_range(index, seed, 305, 14.0, 58.0)
            arc_len = radius * sweep
            if cursor + arc_len + straight > length + 12.0:
                straight = max(0.0, length - cursor - arc_len)
            if straight > 0.0:
                out.append(('s', straight))
                cursor += straight
            if arc_len > 0.001 and cursor < length:
                use = sweep
                if cursor + arc_len > length:
                    use = sweep * max(0.0, (length - cursor) / max(arc_len, 0.001))
                tail = radius * abs(use)
                if tail >= 12.0:
                    # Обрезанный «огрызок» дуги (меньше 12 м) даёт вырожденно
                    # малый радиус при балансировке пар — лучше оставить
                    # место прямиком, его добьёт fit_length.
                    out.append(('a', radius, use * side))
                    cursor += tail
            index += 1
            if before == cursor:
                # Ничего не уместилось — дальше только нули, выходим.
                break
            before = cursor
    return fit_length(out, length)


def fit_length(items, length):
    total = sum(p[1] if p[0] == 's' else p[1] * abs(p[2]) for p in items)
    diff = length - total
    items = list(items)
    if abs(diff) <= 0.01:
        return items
    if diff > 0.0:
        items.append(('s', diff))
        return items
    left = -diff
    for i in range(len(items) - 1, -1, -1):
        if items[i][0] != 's':
            continue
        keep = items[i][1]
        take = min(keep, left)
        keep -= take
        left -= take
        if keep <= 0.01:
            items.pop(i)
        else:
            items[i] = ('s', keep)
        if left <= 0.01:
            break
    return items


def balance_arcs(items):
    """Выравнивание встречных пар дуг по модулю угла.

    Идея: S-изгиб из двух дуг с равными |углами| даёт почти нулевой
    нетто-поворот, поэтому `_pin_turn` всегда сходится (он докручивает
    курс в пределах ±0.45 рад). Без выравнивания одна дуга пары могла
    быть в разы круче другой, и привязка к оси не успевала.

    Правила:
      * пары берутся последовательно: следующая встречная дуга закрывает
        предыдущую;
      * внутри пары углы усредняются (знаки сохраняются);
      * длина дуги сохраняется: радиус = длина / |угол|;
      * радиус зажат снизу 6 м (emit всё равно поднимает радиус до 6 —
        а это ломало точную длину участка);
      * |угол| не опускается ниже 0.11 рад, иначе `_pin_turn` считает
        дугу замороженной и не может ею докрутить;
      * крутая одиночная дуга (|угол| > 0.45 рад) не может быть докручена
        полномочиями `_pin_turn` — расщепляем её на встречную пару
        половин угла: длина сохраняется, радиус не меняется, нетто ≈ 0.
    """
    MIN_R = 6.0
    MIN_SWEEP = 0.11

    arcs = [i for i, p in enumerate(items) if p[0] == 'a']
    if not arcs:
        return items

    # Группируем дуги по знаку: встречная дуга закрывает предыдущую.
    groups = []
    current = [arcs[0]]
    for i in arcs[1:]:
        if items[i][2] * items[current[-1]][2] < 0.0:
            current.append(i)
        else:
            groups.append(current)
            current = [i]
    groups.append(current)

    # Действия по «первому» индексу: ('pair', b, mean, знак a, знак b)
    # либо ('split', radius, sweep). Вторые индексы пар пропускаются.
    actions = {}
    skip = set()
    for group in groups:
        if len(group) == 2:
            a, b = group
            len_a = items[a][1] * abs(items[a][2])
            len_b = items[b][1] * abs(items[b][2])
            # Общий угол пары: ниже 0.11 (иначе pin_turn дугу не тронет),
            # ниже длины/6 (иначе радиус < 6 м) и ниже 2.6 рад — потолок
            # MAX_SWEEP=3.0 нужен как запас на докрутку ±0.45 рад.
            mean = min(0.5 * (abs(items[a][2]) + abs(items[b][2])),
                       min(len_a, len_b) / MIN_R, 2.6)
            actions[a] = ('pair', b, mean,
                          1.0 if items[a][2] >= 0.0 else -1.0,
                          1.0 if items[b][2] >= 0.0 else -1.0)
            skip.add(b)
        else:
            for i in group:
                p = items[i]
                arc_len = p[1] * abs(p[2])
                if abs(p[2]) <= 0.45:
                    # Спокойная одиночная дуга: сохраняем форму, только
                    # снимая вырожденные радиусы/углы.
                    sweep = max(MIN_SWEEP, min(arc_len / MIN_R, abs(p[2])))
                    radius = max(MIN_R, arc_len / sweep)
                    items[i] = ('a', radius, math.copysign(sweep, p[2]))
                else:
                    # Расщепление на встречную пару: каждый кусок — половина
                    # длины и половина угла, радиус тот же.
                    half_len = arc_len * 0.5
                    sweep = max(MIN_SWEEP, min(0.5 * abs(p[2]), half_len / MIN_R))
                    radius = max(MIN_R, half_len / sweep)
                    sign = 1.0 if p[2] >= 0.0 else -1.0
                    actions[i] = ('split', radius, sweep * sign)

    result = []
    for idx, p in enumerate(items):
        if idx in skip:
            continue
        action = actions.get(idx)
        if action is None:
            result.append(p)
        elif action[0] == 'pair':
            _, b, mean, sign_a, sign_b = action
            len_a = p[1] * abs(p[2])
            len_b = items[b][1] * abs(items[b][2])
            common = max(MIN_SWEEP, mean)
            result.append(('a', max(MIN_R, len_a / common),
                           math.copysign(common, sign_a)))
            result.append(('a', max(MIN_R, len_b / common),
                           math.copysign(common, sign_b)))
        else:
            _, radius, sweep = action
            result.append(('a', radius, sweep))
            result.append(('a', radius, -sweep))
    items[:] = result
    return items


def pin_turn(items, turn):
    arcs = [p for p in items if p[0] == 'a']
    if not arcs:
        return items
    net = sum(p[2] for p in arcs)
    arc_total = sum(p[1] * abs(p[2]) for p in arcs)
    if arc_total < 1.0:
        return items
    delta = turn - net
    # Минимальный |угол| после докрутки: нулевой угол означал бы радиус
    # в бесконечность и исчезнувший кусок дороги, а 0.02 рад оставляют
    # длину дуги и позволяют дуге сменить знак (нужно одиночным дугам).
    MIN_ACTIVE = 0.02
    for _ in range(2):
        if abs(delta) < 1e-4:
            break
        share = sum(p[1] * abs(p[2]) for p in arcs if abs(p[2]) > MIN_PINNED_SWEEP)
        if share < 1e-3:
            break
        used = 0.0
        updated = []
        for p in arcs:
            arc_len = p[1] * abs(p[2])
            if abs(p[2]) <= MIN_PINNED_SWEEP:
                updated.append(p)
                continue
            sweep = p[2] + delta * arc_len / share
            if abs(sweep) < MIN_ACTIVE:
                sweep = MIN_ACTIVE if sweep >= 0.0 else -MIN_ACTIVE
            sweep = max(-MAX_SWEEP, min(MAX_SWEEP, sweep))
            used += sweep - p[2]
            updated.append(('a', arc_len / max(abs(sweep), MIN_ACTIVE), sweep))
        arcs = updated
        delta -= used
        if abs(delta) < 0.02:
            break
        biggest = max(arcs, key=lambda p: p[1] * abs(p[2]))
        arc_len = biggest[1] * abs(biggest[2])
        sweep = max(-MAX_SWEEP, min(MAX_SWEEP, biggest[2] + delta))
        if abs(sweep) < MIN_ACTIVE:
            sweep = MIN_ACTIVE if sweep >= 0.0 else -MIN_ACTIVE
        delta -= sweep - biggest[2]
        arcs = [('a', arc_len / max(abs(sweep), MIN_ACTIVE), sweep) if p is biggest else p
                for p in arcs]
    result = []
    rest = iter(arcs)
    for p in items:
        result.append(next(rest) if p[0] == 'a' else p)
    return result


def emit_domain(domain, leg, seed, slot, length, x, z, heading, along, points):
    items = pieces(domain, leg, seed, slot, length)
    items = balance_arcs(items)
    items = pin_turn(items, wrapf(axis_heading(along + length, seed) - heading, -math.pi, math.pi))
    for p in items:
        if p[0] == 's':
            remaining = p[1]
            while remaining > 1e-4:
                step = min(WALK_STEP, remaining)
                x += math.cos(heading) * step
                z += math.sin(heading) * step
                along += step
                remaining -= step
                if points is not None:
                    points.append((x, z, along))
        else:
            radius = max(6.0, p[1])
            sweep = p[2]
            arc_len = radius * abs(sweep)
            count = max(2, int(math.ceil(arc_len / WALK_STEP)))
            delta = sweep / count
            step = radius * abs(delta)
            for _ in range(count):
                heading += delta
                x += math.cos(heading) * step
                z += math.sin(heading) * step
                along += step
                if points is not None:
                    points.append((x, z, along))
    return x, z, heading, along


def walk_leg(leg, seed, points=None):
    """Обход участка от известного начала (без рекурсии)."""
    if leg <= 0:
        x, z, heading = 0.0, 0.0, initial_heading(seed)
    else:
        x, z, heading = start_state(leg, seed)
    along = leg * LEG_LENGTH
    if points is not None:
        points.append((x, z, along))
    for slot, (kind, share) in enumerate(shares(seed, leg)):
        x, z, heading, along = emit_domain(kind, leg, seed, slot, LEG_LENGTH * share,
                                           x, z, heading, along, points)
    return x, z, heading, along


def start_state(leg, seed):
    """Состояние на НАЧАЛЕ участка: кэш `_boundary_cache[n]` в GDScript."""
    if leg <= 0:
        return (0.0, 0.0, initial_heading(seed))
    cache = _cached(seed)['start']
    if leg in cache:
        return cache[leg]
    known = leg - 1
    while known > 0 and known not in cache:
        known -= 1
    cursor = cache.get(known, (0.0, 0.0, initial_heading(seed)))
    for n in range(known, leg):
        x, z, heading, _ = walk_leg_raw(n, seed)
        cursor = (x, z, heading)
        cache[n + 1] = cursor
    return cursor


def walk_leg_raw(leg, seed):
    x, z, heading = start_state(leg, seed) if leg > 0 else (0.0, 0.0, initial_heading(seed))
    along = leg * LEG_LENGTH
    for slot, (kind, share) in enumerate(shares(seed, leg)):
        x, z, heading, along = emit_domain(kind, leg, seed, slot, LEG_LENGTH * share,
                                           x, z, heading, along, None)
    return x, z, heading, along


def build_leg(leg, seed):
    points = []
    walk_leg(leg, seed, points)
    return points, start_state(leg + 1, seed)
