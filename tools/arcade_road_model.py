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
DEFAULT_HALF_WIDTH = 3.6
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


def roll(index, seed, salt):
    n = (index % 1000003) * 92821 + (seed % 1000003) * 68917 + salt * 2833
    n = ((n ^ (n >> 13)) * 127) % 1000003
    return n / 1000003.0


def roll_range(index, seed, salt, low, high):
    return low + (high - low) * roll(index, seed, salt)


def wrapf(value, low, high):
    span = high - low
    return (value - low) % span + low


# ------------------------------------------------------------------ план


def plan(seed, leg):
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


def initial_heading(seed):
    return roll_range(-1, seed, 7, -0.30, 0.30)


def axis_heading(distance, seed):
    heading = initial_heading(seed)
    for i, wavelength in enumerate(AXIS_WAVES):
        heading += AXIS_AMPLITUDES[i] * math.sin(distance / wavelength * math.tau + axis_phase(seed)[i])
    return heading


# --------------------------------------------------------------- ширина


def domain_half_width(domain, leg, seed):
    if domain == SERPENTINE:
        return min(4.8, max(2.9, 3.2 * roll_range(leg, seed, 11, 0.94, 1.06)))
    if domain == FAST:
        return 4.4
    if domain == VILLAGE:
        return 3.4
    if domain == BRIDGE:
        return 3.0
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
        hairpins = 2 * max(1, int(length / 150.0))
        arcs = []
        arc_total = 0.0
        direction = 1.0 if roll(leg * 7, seed, 311) < 0.5 else -1.0
        for i in range(hairpins):
            radius = roll_range(leg * 7 + i, seed, 312, 12.0, 17.5)
            sweep = math.radians(roll_range(leg * 7 + i, seed, 313, 140.0, 172.0))
            arcs.append(('a', radius, sweep * direction))
            arc_total += radius * abs(sweep)
            direction = -direction
        shelf = max(4.0, min(34.0, (length - arc_total) / (hairpins + 1)))
        out.append(('s', shelf))
        for i in range(hairpins):
            out.append(arcs[i])
            out.append(('s', shelf if i < hairpins - 1 else shelf * 0.7))
    elif domain == BRIDGE:
        bridge_dir = 1.0 if roll(leg, seed, 322) < 0.5 else -1.0
        sweep = roll_range(leg, seed, 321, 0.10, 0.16) * bridge_dir
        out = [('s', length * 0.30), ('a', 200.0, sweep),
               ('s', length * 0.45), ('s', length * 0.25)]
    else:
        twist = 0.55
        if domain == FAST:
            twist = 0.24
        elif domain == VILLAGE:
            twist = 0.10
        index = leg * 17 + slot * 5
        cursor = 0.0
        turn_side = 1.0 if roll(index, seed, 304) < 0.5 else -1.0
        while cursor < length - 1.0:
            radius = roll_range(index, seed, 302, 62.0, 150.0)
            if domain == VILLAGE:
                radius = 240.0
            sweep = roll_range(index, seed, 303, 0.22, 1.05) * (0.55 + twist)
            side = turn_side
            turn_side = -turn_side
            straight = roll_range(index, seed, 305, 14.0, 58.0)
            if domain == VILLAGE:
                sweep = 0.16
                straight = length - cursor
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
                out.append(('a', radius, use * side))
                cursor += radius * abs(use)
            index += 1
            if domain == VILLAGE:
                break
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


def pin_turn(items, turn):
    arcs = [p for p in items if p[0] == 'a']
    if not arcs:
        return items
    net = sum(p[2] for p in arcs)
    arc_total = sum(p[1] * abs(p[2]) for p in arcs)
    if arc_total < 1.0:
        return items
    delta = turn - net
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
            sign = 1.0 if p[2] >= 0.0 else -1.0
            if sign * sweep < 0.0:
                sweep = sign * MIN_PINNED_SWEEP
            sweep = max(-MAX_SWEEP, min(MAX_SWEEP, sweep))
            used += sweep - p[2]
            updated.append(('a', arc_len / max(abs(sweep), 1e-4), sweep))
        arcs = updated
        delta -= used
        if abs(delta) < 0.02:
            break
        biggest = max(arcs, key=lambda p: p[1] * abs(p[2]))
        arc_len = biggest[1] * abs(biggest[2])
        sweep = max(-MAX_SWEEP, min(MAX_SWEEP, biggest[2] + delta))
        delta -= sweep - biggest[2]
        arcs = [('a', arc_len / max(abs(sweep), 1e-4), sweep) if p is biggest else p
                for p in arcs]
    result = []
    rest = iter(arcs)
    for p in items:
        result.append(next(rest) if p[0] == 'a' else p)
    return result


def emit_domain(domain, leg, seed, slot, length, x, z, heading, along, points):
    items = pieces(domain, leg, seed, slot, length)
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
