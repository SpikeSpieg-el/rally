"""Авторинг UK-участка «ЧЁРНАЯ ДОЛИНА»: трасса, река, мосты, ресурсы.

Участок задуман как один связный мир, а не как набор красивых чисел:

  * река — независимая осевая линия x = f(z) с меандрами и падением уровня
    строго вниз по течению;
  * дорога пересекает её РОВНО ДВА РАЗА и почти перпендикулярно: внизу —
    малым мостом (2.8 м над водой), наверху — большим (4.6 м над водой);
  * между мостами дорога полого лезет в гору серпантинами по восточному
    склону: длинный подъём, шпильки, слепые гребни;
  * покрытие чередуется: гравий → асфальт → гравий … (route_sections).

Скрипт детерминирован: один запуск — один и тот же участок.
Проверки в конце НЕ декоративные: они валят запуск, если мост оказался не
перпендикулярен реке, если дорога подходит к воде вне моста или если уровень
воды выше полотна.

Запуск:  python3 tools/author_england_stage.py
"""
import bisect
import math
import os
import random
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import make_prop_textures as uid_tool  # noqa: E402
import road_profile  # noqa: E402
import route_kit as kit  # noqa: E402
import stage_model as model  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROUTE_PATH = os.path.join(ROOT, "data/tracks/stage_england_route.tres")
RIVER_PATH = os.path.join(ROOT, "data/tracks/stage_england_river.tres")
TRACK_PATH = os.path.join(ROOT, "data/tracks/stage_england.tres")
SCENE_PATH = os.path.join(ROOT, "scenes/rally_stage_england.tscn")
BASE_SCENE = os.path.join(ROOT, "scenes/rally_stage.tscn")

SEED = 88421
TRACK_ID = "england_dark_valley"
RIVER_CX = 120.0
RIVER_A1 = 74.0
RIVER_F1 = 168.0
RIVER_A2 = 26.0
RIVER_F2 = 61.0
RIVER_PHASE = 1.3
RIVER_Z_START = -140.0
RIVER_Z_END = 1500.0
RIVER_STEP = 10.0
RIVER_UPSTREAM_GRADE = 0.045
RIVER_DOWNSTREAM_GRADE = 0.020
# Насколько вода должна сидеть НИЖЕ земли: русло режется только вниз, поэтому
# уровень выше рельефа — это висящее в небе зеркало и треугольные «простыни».
RIVER_SINK = 0.85
# Сетка рельефа для посадки воды — та же, что у движка (track.terrain_cell):
# региональный уровень строится из высоты дороги и сильно размывается, поэтому
# грубая сетка «съедает» высоту под мостом и вода падает на ровном месте.
RIVER_TERRAIN_CELL = 3.0

# Километраж переправ: задан планом трассы и осью реки, проверяется в verify().
START_HEIGHT = 10.0
SHELF_AMP = 0.6          # «полки» уклона, м
BRIDGE_FLAT = 30.0       # ровная площадка под настилом, м (настил 46 м)
BRIDGE_RAMP = 70.0       # плавный выход уклона на подходе, м
CROSSING_SMALL = 186.0
CROSSING_LARGE = 3378.0
CROSSING_LARGE_U = CROSSING_LARGE / 4706.0
SMALL_CLEARANCE = 2.8
LARGE_CLEARANCE = 4.6
SMALL_SPAN = 22.0
LARGE_SPAN = 46.0
# Участок должен остаться НЕ потоковым: авто-стриминг включается с 5 км.
MAX_ROUTE_LENGTH = 4800.0


# ------------------------------------------------------------------ река
def river_x(z):
    return (RIVER_CX
            + RIVER_A1 * math.sin(z / RIVER_F1)
            + RIVER_A2 * math.sin(z / RIVER_F2 + RIVER_PHASE))


def river_side(x, z):
    """Со знаком: слева/справа от реки. Пересечение — смена знака."""
    return x - river_x(z)


# ----------------------------------------------------------------- трасса
def build_path(rng):
    """План трассы: южная переправа, восточный подъём, северная переправа."""
    segs = []
    # 1. Пролог: старый гравийный подъезд к реке, лёгкий спуск.
    segs += [("s", 60.0, -1.0)]
    segs += [("a", 96.0, 42.0, -0.6, 1.0), ("s", 44.0, -0.4),
             ("a", 110.0, 38.0, -0.2, -1.0), ("s", 36.0, 0.0)]
    # 2. Перед малым мостом: ровный короткий выбег (мост нельзя брать в дуге).
    segs += [("a", 150.0, 26.0, 0.5, 1.0), ("s", 96.0, 0.4)]

    # 3. За мостом — техничная «лестница»: три разножки с узкими радиусами.
    for index in range(3):
        radius = rng.uniform(20.0, 28.0)
        segs += [("a", radius, rng.uniform(62.0, 78.0), 0.35, 1.0 if index % 2 == 0 else -1.0),
                 ("s", rng.uniform(30.0, 50.0), 0.5),
                 ("a", radius * rng.uniform(1.2, 1.6), rng.uniform(58.0, 74.0), 0.35,
                  -1.0 if index % 2 == 0 else 1.0),
                 ("s", rng.uniform(30.0, 48.0), 0.6)]
    # 4. Разворот на север и первый пологий километр подъёма.
    segs += [("a", 120.0, 64.0, 0.8, 1.0), ("s", 150.0, 2.2)]
    segs += [("a", 92.0, 46.0, 1.4, -1.0), ("s", 120.0, 3.2),
             ("a", 84.0, 52.0, 1.6, 1.0), ("s", 160.0, 4.0)]

    # 5. Серпантины: шпильки 180° с полками — «полого в гору», но зло.
    for index in range(4):
        radius = rng.uniform(19.0, 24.0)
        direction = 1.0 if index % 2 == 0 else -1.0
        segs += [("s", rng.uniform(70.0, 110.0), rng.uniform(2.6, 4.2)),
                 ("a", radius, 180.0, rng.uniform(2.4, 3.4), direction),
                 ("s", rng.uniform(60.0, 96.0), rng.uniform(2.2, 3.6)),
                 ("a", rng.uniform(48.0, 66.0), rng.uniform(52.0, 70.0), 1.6, -direction),
                 ("s", rng.uniform(80.0, 130.0), rng.uniform(3.0, 4.6)),
                 ("a", rng.uniform(44.0, 62.0), rng.uniform(46.0, 64.0), 1.4, direction)]

    # 6. Долгий шёлковый подъём к большому мосту: длинные дуги, газ в пол.
    segs += [("s", 120.0, 4.4), ("a", 130.0, 40.0, 2.2, 1.0), ("s", 170.0, 5.4)]
    segs += [("a", 104.0, 44.0, 2.6, -1.0), ("s", 150.0, 5.0)]
    segs += [("a", 140.0, 36.0, 1.8, 1.0), ("s", 130.0, 4.2)]

    # 7. Выход на большой мост: прямой участок и переправа на запад.
    segs += [("a", 160.0, 34.0, 1.6, -1.0), ("s", 120.0, 2.4),
             ("a", 180.0, 30.0, 0.8, 1.0), ("s", 100.0, 0.4)]
    # 8. Финиш за рекой: короткий спуск с гребня, чтобы последний поворот
    #    читался и не уводил карту ещё на полкилометра на север.
    segs += [("s", 70.0, -0.8), ("a", 120.0, 30.0, -1.2, 1.0)]
    return segs


def heights_for(points, marks=()):
    """Профиль высоты задаётся УКЛОНОМ, а не точками.

    Почему не монотонный подъём (как было раньше): региональный рельеф в игре
    строится ИЗ ВЫСОТЫ ДОРОГИ (широкое размытие, road_network._build_regional),
    значит профиль дороги — это и есть профиль местности. При монотонном
    подъёме 10 → 180 м северная переправа (3378 м трассы) попадала на
    135-метровое плато, а река, пересекающая трассу именно там, оказывалась
    на вершине «горы»: вода висела над землёй и рисовала треугольные
    простыни, а мост стоял на мелкой канаве на вершине.

    Теперь профиль: разгон → набор высоты на гребень → долгий спуск в долину
    реки → финишный подъём. Интегрируем уклон, потому что так мы точно
    управляем двумя вещами, которые ломали геометрию:
      * на подходах к переправам уклон ровно нулевой — жёсткий настил моста
        ложится на полотно без ступеньки на торце;
      * уклон меняется плавно — нет изломов, которые интерполяция кривой
        превращает в пики под 15 %.
    """
    count = len(points)
    if count < 3:
        return [(p[0], p[1], START_HEIGHT) for p in points]
    # (доля длины, уклон в м/м): разгон, гребень, спуск в долину, финиш.
    plan = ((0.044, 0.010), (0.435, 0.075), (CROSSING_LARGE_U, -0.080), (1.0, 0.078))
    grade = []
    for index in range(count):
        u = index / float(count - 1)
        value = plan[-1][1]
        for limit, slope in plan:
            if u <= limit:
                value = slope
                break
        grade.append(value)
    grade = box_smooth(grade, 18, 3)
    # Площадки под настилы: уклон ноль на пролёте и плавный выход на подходе.
    for mark in marks:
        for index in range(count):
            distance = abs(index - mark)
            if distance <= BRIDGE_FLAT:
                weight = 1.0
            elif distance < BRIDGE_FLAT + BRIDGE_RAMP:
                weight = 0.5 + 0.5 * math.cos(
                    math.pi * (distance - BRIDGE_FLAT) / BRIDGE_RAMP)
            else:
                continue
            grade[index] *= 1.0 - weight
    out = []
    height = START_HEIGHT
    for index, (x, z, _) in enumerate(points):
        height += grade[index]
        # Длинные «полки»: короткие всплески ±0,6 м, чтобы машина
        # разгружалась и снова садилась на подвеску.
        shelf = SHELF_AMP * math.sin(index / 233.0) * math.sin(index / 91.0 + 0.7)
        shelf *= road_profile.ease(index / 120.0) * road_profile.ease((count - index) / 160.0)
        out.append((x, z, height + shelf))
    return out


def compose_route():
    rng = random.Random(SEED)
    pts, _length = kit.compose(build_path(rng), step=1.0)
    profiled = heights_for(pts, [CROSSING_SMALL, CROSSING_LARGE])
    smoothed = kit.smooth_heights(profiled, 12.0)
    # Запас 1,1 % к лимиту теста (9,5 %): безье между контрольными точками
    # добавляет к уклону десятые доли процента.
    limited = kit.limit_grade(smoothed, 8.4)
    controls = kit.select_controls(limited, max_gap=26, min_gap=6, turn_trigger_deg=6)
    return controls


def write_route(controls):
    uid = uid_tool.godot_uid("res://data/tracks/stage_england_route.tres")
    kit.write_curve(controls, ROUTE_PATH, uid=uid)
    samples = model.sample_curve(model.load_curve(ROUTE_PATH), 1.0)
    points = [(p[0], p[2], p[1]) for p in samples]
    return points, kit.xz_distances(points)


# ------------------------------------------------------------------ мосты
def crossings(points, acc):
    """Все места, где дорога пересекает осевую линию реки."""
    found = []
    for i in range(1, len(points)):
        x0, z0, y0 = points[i - 1]
        x1, z1, y1 = points[i]
        s0 = river_side(x0, z0)
        s1 = river_side(x1, z1)
        if s0 * s1 > 0.0:
            continue
        s0 = s0 if s0 != 0.0 else 1e-6
        s1 = s1 if s1 != 0.0 else 1e-6
        t = abs(s0) / max(abs(s0) + abs(s1), 1e-9)
        found.append({
            "x": x0 + (x1 - x0) * t,
            "z": z0 + (z1 - z0) * t,
            "y": y0 + (y1 - y0) * t,
            "distance": acc[i - 1] + (acc[i] - acc[i - 1]) * t,
            "heading": math.atan2(z1 - z0, x1 - x0),
        })
    return found


def route_min_river_gap(points, acc, bridge_distances, window=60.0):
    """Минимальный зазор дороги от ОСИ реки вне зон переправ (м)."""
    worst = 1e9
    where = 0.0
    for (x, z, _y), distance in zip(points, acc):
        if any(abs(distance - d) < window for d in bridge_distances):
            continue
        gap = abs(river_side(x, z))
        if gap < worst:
            worst = gap
            where = distance
    return worst, where


def water_profile(small, large):
    """Уровень воды по z: монотонно вниз по течению (с севера на юг)."""
    y_small = small["y"] - SMALL_CLEARANCE
    y_large = large["y"] - LARGE_CLEARANCE
    z_small = small["z"]
    z_large = large["z"]
    if z_large <= z_small:
        raise SystemExit("Большой мост должен стоять выше по течению (z больше).")

    def level(z):
        if z >= z_large:
            return y_large + (z - z_large) * RIVER_UPSTREAM_GRADE
        if z >= z_small:
            t = (z_large - z) / max(z_large - z_small, 1e-6)
            smooth = t * t * (3.0 - 2.0 * t) * 0.35 + t * 0.65
            return y_large + (y_small - y_large) * smooth
        return y_small - (z_small - z) * RIVER_DOWNSTREAM_GRADE

    return level


def nearest_on_route(route, acc, x, z):
    """Точное расстояние до осевой линии и километраж: (d, along).

    Грубая сетка поля дорог (12-15 м) у моста врёт на метры — а именно там
    вода ближе всего к полотну, поэтому расстояние считаем по отрезкам.
    """
    best_d = 1e9
    best_along = 0.0
    for i in range(len(route) - 1):
        a = route[i]
        b = route[i + 1]
        abx = b[0] - a[0]
        abz = b[2] - a[2]
        l2 = abx * abx + abz * abz
        t = 0.0
        if l2 > 1e-9:
            t = max(0.0, min(1.0, ((x - a[0]) * abx + (z - a[2]) * abz) / l2))
        d = math.hypot(x - (a[0] + abx * t), z - (a[2] + abz * t))
        if d < best_d:
            best_d = d
            best_along = acc[i] + (acc[i + 1] - acc[i]) * t
    return best_d, best_along


def terrain_sampler():
    """Высоты движка без реки: та же функция, что _road_shoulder_height().

    Нужна, чтобы уровень воды садился в рельеф при авторинге, а не только
    на этапе сборки мира: иначе кривую в редакторе видно висящей в воздухе.
    """
    cfg = model.read_track(TRACK_PATH)
    route = model.sample_curve(model.load_curve(ROUTE_PATH), 2.0)
    acc = [0.0]
    for a, b in zip(route, route[1:]):
        acc.append(acc[-1] + math.dist((a[0], a[2]), (b[0], b[2])))
    cfg["route_length"] = acc[-1]
    xs = [p[0] for p in route]
    zs = [p[2] for p in route]
    margin = cfg["margin"]
    rect = (min(xs) - margin, min(zs) - margin,
            max(xs) - min(xs) + 2.0 * margin, max(zs) - min(zs) + 2.0 * margin)
    net = model.Net(route, rect, RIVER_TERRAIN_CELL)
    corridor = cfg["corridor"]
    max_slope = math.tan(math.radians(max(6.0, cfg["emb_slope"])))

    def sampler(x, z):
        distance, along = nearest_on_route(route, acc, x, z)
        i = min(len(route) - 2, int(along / max(acc[-1], 1e-6) * (len(route) - 1)))
        t = along / max(acc[-1], 1e-6) * (len(route) - 1) - i
        road_y = route[i][1] + (route[i + 1][1] - route[i][1]) * max(0.0, min(1.0, t))
        fade = model.smoothstep(cfg["fade_start"], cfg["fade_start"] + cfg["fade_len"], distance)
        base = net.regional_height(x, z) + model.hills(x, z) * fade
        blend = max(cfg["emb_min"], min(cfg["emb_max"], abs(road_y - base) / max(max_slope, 0.05)))
        s = model.smoothstep(corridor, corridor + blend, distance)
        height = base + (road_y - base) * (1.0 - s)
        near = 1.0 - s
        if near > 0.001:
            lateral = max(0.0, min(1.0, distance / max(corridor, 0.01)))
            height -= cfg["camber"] * lateral * lateral * near
            height += model.bumps(along, cfg) * near
        return height

    return sampler


def box_smooth(values, radius, passes):
    """Скользящее среднее по списку — с краями, без смещения фазы."""
    out = list(values)
    for _pass in range(passes):
        source = list(out)
        for i in range(len(out)):
            lo = max(0, i - radius)
            hi = min(len(out), i + radius + 1)
            out[i] = sum(source[lo:hi]) / float(hi - lo)
    return out


def river_levels(small, large, zs, ground):
    """Уровень воды по рельефу, а не по формуле «между мостами».

    Региональный рельеф в игре строится из высоты дороги и сильно размывается,
    поэтому у реки вдали от переправ своя высота, не связанная с высотой
    настила. Раньше вода задавалась дугой между двумя мостами и уходила в небо
    над землёй на десятки метров — это и были треугольные «простыни».

    Здесь вода ищется как самая высокая ГЛАДКАЯ линия, которая везде не
    поднимается выше земли на RIVER_SINK (релаксация: сглаживание + срез).
    Под мостами дополнительно прорезается ванна с гарантированным просветом.
    """
    if ground is None:
        formula = water_profile(small, large)
        return [formula(z) for z in zs]
    limits = [ground(river_x(z), z) - RIVER_SINK for z in zs]
    level = list(limits)
    # Сглаживание со срезом: вода остаётся гладкой там, где земля это
    # позволяет, и ложится на землю там, где рельеф резко падает.
    for _step in range(14):
        level = box_smooth(level, 2, 1)
        for i in range(len(level)):
            level[i] = min(level[i], limits[i])
    # У мостов вода обязана стоять ровно на расчётном просвете: иначе опоры
    # висят в воздухе (если ниже) или река подтапливает настил (если выше).
    # Под настилом — плоское «корыто»: контрольные точки кривой прореживаются
    # до 24 м, и на дуге безье дно V-профиля всплывало на полметра.
    for hit, clearance, flat, reach in ((small, SMALL_CLEARANCE, 30.0, 80.0),
                                        (large, LARGE_CLEARANCE, 34.0, 95.0)):
        target = hit["y"] - clearance
        for i, z in enumerate(zs):
            distance = abs(z - hit["z"])
            if distance <= flat:
                weight = 1.0
            elif distance < reach:
                weight = 0.5 + 0.5 * math.cos(
                    math.pi * (distance - flat) / (reach - flat))
            else:
                continue
            level[i] = level[i] * (1.0 - weight) + target * weight
    for i in range(len(level)):
        level[i] = min(level[i], limits[i])
    return level


def sink_water(points, terrain):
    """Опустить воду до земли (никогда не поднимать) и убрать ступеньки."""
    dropped = 0
    worst = 0.0
    for point in points:
        limit = terrain(point[0], point[1]) - RIVER_SINK
        if point[2] > limit:
            worst = max(worst, point[2] - limit)
            point[2] = limit
            dropped += 1
    for _pass in range(3):
        for i in range(1, len(points) - 1):
            average = (points[i - 1][2] + points[i][2] * 2.0 + points[i + 1][2]) * 0.25
            if average < points[i][2]:
                points[i][2] = average
    return dropped, worst


def write_river(small, large, terrain=None):
    zs = []
    z = RIVER_Z_END
    while z >= RIVER_Z_START:
        zs.append(z)
        z -= RIVER_STEP
    levels = river_levels(small, large, zs, terrain)
    points = [[river_x(z), z, y] for z, y in zip(zs, levels)]
    if terrain is not None and len(levels) > 2:
        drops = [abs(levels[i] - levels[i + 1]) / RIVER_STEP for i in range(len(levels) - 1)]
        steep = sum(1 for d in drops if d > 0.25)
        print("Профиль воды: %.1f … %.1f м, уклон до %.0f%%, крутых участков %d из %d"
              % (min(levels), max(levels), max(drops) * 100.0, steep, len(drops)))
    # Отдельная «подрезка по земле» здесь больше не нужна: river_levels()
    # уже гарантирует воду ниже рельефа. Дополнительное сглаживание только
    # съедало плоское корыто под мостом (вода всплывала на 0.4 м).
    controls = kit.select_controls([tuple(p) for p in points], max_gap=24, min_gap=8,
                                    turn_trigger_deg=5)
    uid = uid_tool.godot_uid("res://data/tracks/stage_england_river.tres")
    kit.write_curve(controls, RIVER_PATH, uid=uid)
    # Финальный профиль — по записанным точкам, а не по исходной формуле:
    # проверки должны видеть то, что реально попало в ресурс.
    ordered = sorted(points, key=lambda p: p[1])

    def final_level(distance_z):
        zs = [p[1] for p in ordered]
        if distance_z <= zs[0]:
            return ordered[0][2]
        if distance_z >= zs[-1]:
            return ordered[-1][2]
        i = bisect.bisect_left(zs, distance_z)
        a, b = ordered[i - 1], ordered[i]
        span = b[1] - a[1]
        t = 0.0 if abs(span) < 1e-6 else (distance_z - a[1]) / span
        return a[2] + (b[2] - a[2]) * t

    return final_level


def river_curve_samples():
    return model.sample_curve(model.load_curve(RIVER_PATH), 2.0)


def water_margin_at(x, z, water_y, road_y):
    return road_y - water_y


# --------------------------------------------------------------- ресурсы
def color(r, g, b):
    return "Color(%s, 1)" % ", ".join("%.4f" % v for v in (r, g, b))


def vec2(x, y):
    return "Vector2(%.4f, %.4f)" % (x, y)


def vec3(x, y, z):
    return "Vector3(%.4f, %.4f, %.4f)" % (x, y, z)


SECTIONS = [
    (0.0, "Размокший гравий у переправы", "Гравий", 4.1, (0.20, 0.17, 0.13), 1.00, 1.00, 220.0),
    (560.0, "Асфальт: полка над водой", "Асфальт", 3.8, (0.17, 0.18, 0.20), 1.28, 0.92, 60.0),
    (1150.0, "Гравий: техничная лестница", "Гравий", 3.4, (0.24, 0.20, 0.15), 0.90, 1.10, 50.0),
    (1900.0, "Асфальт: шпильки в гору", "Асфальт", 3.6, (0.15, 0.16, 0.18), 1.20, 0.95, 45.0),
    (2650.0, "Гравий: спуск с гребня", "Гравий", 3.3, (0.26, 0.22, 0.16), 0.86, 1.15, 40.0),
    (3250.0, "Асфальт: спуск к большому мосту", "Асфальт", 3.9, (0.16, 0.17, 0.19), 1.30, 0.90, 55.0),
    (3560.0, "Гравий за большой водой: в гору", "Гравий", 3.5, (0.25, 0.21, 0.15), 0.92, 1.08, 60.0),
    (4100.0, "Асфальт: финишный гребень", "Асфальт", 3.7, (0.15, 0.16, 0.18), 1.22, 0.92, 70.0),
]


def track_text(route_uid, river_uid, small, large):
    track_uid = uid_tool.godot_uid("res://data/tracks/stage_england.tres")
    lines = []
    lines.append('[gd_resource type="Resource" script_class="RallyTrackConfig" format=3 uid="%s"]' % track_uid)
    lines.append("")
    lines.append('[ext_resource type="Script" path="res://scripts/data/rally_track_config.gd" id="track"]')
    lines.append('[ext_resource type="Curve3D" uid="%s" path="res://data/tracks/stage_england_route.tres" id="curve"]' % route_uid)
    lines.append('[ext_resource type="Curve3D" uid="%s" path="res://data/tracks/stage_england_river.tres" id="river_curve"]' % river_uid)
    lines.append('[ext_resource type="Script" path="res://scripts/data/rally_river_config.gd" id="river"]')
    lines.append('[ext_resource type="Script" path="res://scripts/data/rally_bridge_placement.gd" id="bridge"]')
    lines.append('[ext_resource type="Script" path="res://scripts/data/rally_route_section.gd" id="section"]')
    lines.append("")
    for index, (start, title, surface, half, tint, grip, rolling, transition) in enumerate(SECTIONS):
        lines.append('[sub_resource type="Resource" id="Section_%d"]' % index)
        lines.append('script = ExtResource("section")')
        if start > 0.0:
            lines.append("start_distance = %.1f" % start)
        lines.append('title = "%s"' % title)
        lines.append('surface_name = "%s"' % surface)
        lines.append("half_width = %.1f" % half)
        lines.append("road_color = %s" % color(*tint))
        lines.append("grip = %.2f" % grip)
        lines.append("rolling = %.2f" % rolling)
        lines.append("transition_length = %.1f" % transition)
        lines.append("")
    lines.append('[sub_resource type="Resource" id="River"]')
    lines.append('script = ExtResource("river")')
    lines.append("enabled = true")
    lines.append('water_curve = ExtResource("river_curve")')
    lines.append("half_width = 7.0")
    lines.append("bank_width = 9.5")
    lines.append("bed_depth = 2.1")
    lines.append("road_keep_zone = 16.0")
    lines.append("sample_step = 3.0")
    lines.append("shallow_color = %s" % color(0.055, 0.075, 0.070))
    lines.append("deep_color = %s" % color(0.012, 0.020, 0.022))
    lines.append("foam_color = %s" % color(0.52, 0.58, 0.56))
    lines.append("flow_speed = 1.25")
    lines.append("foam_amount = 0.42")
    lines.append("foam_width = 2.6")
    lines.append("gloss = 0.62")
    lines.append("opacity = 0.92")
    lines.append("wave_height = 0.08")
    lines.append("ripple_scale = 0.62")
    lines.append("surface_drop = 0.06")
    lines.append('bank_rock_prop_id = "river_bank_rock"')
    lines.append("bank_rock_spacing = 7.5")
    lines.append("bank_rock_lateral = 1.3")
    lines.append("bank_rock_chance = 0.72")
    lines.append('bank_wall_prop_id = "dry_stone_wall"')
    lines.append("bank_wall_spacing = 6.0")
    lines.append("bank_wall_lateral = 5.5")
    lines.append("bank_wall_chance = 0.22")
    lines.append("bank_wall_margin = 60.0")
    lines.append("")
    for name, hit, clearance, prop, open_radius, channel_scale, widen_radius, title in (
        ("BridgeSmall", small, SMALL_CLEARANCE, "bridge_small", SMALL_SPAN * 0.5 + 2.0, 1.0, 12.0,
         "Малый мост: дуб на камне"),
        ("BridgeLarge", large, LARGE_CLEARANCE, "bridge_large", LARGE_SPAN * 0.5 + 2.0, 1.10, 34.0,
         "Большой мост: три опоры и две арки"),
    ):
        lines.append('[sub_resource type="Resource" id="%s"]' % name)
        lines.append('script = ExtResource("bridge")')
        lines.append('display_name = "%s"' % title)
        lines.append("distance = %.1f" % hit["distance"])
        lines.append('prop_id = "%s"' % prop)
        lines.append("open_radius = %.1f" % open_radius)
        lines.append("deck_offset = -0.07")
        lines.append("channel_scale = %.2f" % channel_scale)
        lines.append("channel_scale_radius = %.1f" % widen_radius)
        lines.append("water_clearance = %.1f" % clearance)
        lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("track")')
    lines.append('id = "%s"' % TRACK_ID)
    lines.append('display_name = "ЧЁРНАЯ ДОЛИНА · АНГЛИЯ"')
    lines.append(
        'description = "Ночной английский спецучасток: мокрый гравий вперемешку с узким '
        'асфальтом, малый дубовый мост над ледяной рекой, потом длинный пологий подъём '
        'серпантинами к большому каменному мосту в две арки. Слепые гребни, перепады и '
        'плотный лес по обе стороны — ошибка стоит кузова."'
    )
    lines.append('surface_name = "Гравий"')
    lines.append("difficulty = 5")
    lines.append("target_time = 318.0")
    lines.append("road_curve = ExtResource(\"curve\")")
    lines.append("road_half_width = 3.9")
    lines.append("road_shoulder = 1.2")
    lines.append("road_step = 1.4")
    lines.append("road_camber = 0.09")
    lines.append("offroad_grip = 0.55")
    lines.append("route_sections = Array[ExtResource(\"section\")]([%s])"
                 % ", ".join('SubResource("Section_%d")' % i for i in range(len(SECTIONS))))
    lines.append("river = SubResource(\"River\")")
    lines.append("bridges = Array[ExtResource(\"bridge\")]([SubResource(\"BridgeSmall\"), SubResource(\"BridgeLarge\")])")
    lines.append("terrain_margin = 100.0")
    lines.append("terrain_cell = 3.0")
    lines.append("terrain_seed = 88421")
    lines.append("hills_height = 26.0")
    lines.append("hills_frequency = 0.0042")
    lines.append("ridge_height = 18.0")
    lines.append("ridge_frequency = 0.0016")
    lines.append("hills_fade_start = 12.0")
    lines.append("hills_fade_length = 60.0")
    lines.append("max_terrain_slope_deg = 42.0")
    lines.append("road_ditch_depth = 0.55")
    lines.append("detail_height = 0.35")
    lines.append("detail_frequency = 0.11")
    lines.append("embankment_slope_deg = 30.0")
    lines.append("embankment_min_width = 4.0")
    lines.append("embankment_max_width = 30.0")
    lines.append("road_feature_height = 2.3")
    lines.append("road_feature_spacing = 250.0")
    lines.append("bumps_amplitude = 0.11")
    lines.append("bumps_wavelength = 8.0")
    lines.append("bumps_roughness = 0.05")
    lines.append("use_baked_props = false")
    lines.append("procedural_scenery = true")
    lines.append("scenery_density = 1.65")
    lines.append("spawn_route_markers = true")
    lines.append("spawn_edge_posts = true")
    lines.append("checkpoint_interval = 700.0")
    lines.append("ground_color = %s" % color(0.055, 0.075, 0.045))
    lines.append("ground_color_2 = %s" % color(0.10, 0.13, 0.075))
    lines.append("rock_color = %s" % color(0.20, 0.21, 0.21))
    lines.append("road_color = %s" % color(0.20, 0.17, 0.13))
    lines.append("road_color_2 = %s" % color(0.29, 0.24, 0.19))
    lines.append("shoulder_color = %s" % color(0.17, 0.14, 0.10))
    lines.append("edge_post_color = %s" % color(0.80, 0.14, 0.10))
    lines.append("sky_top_color = %s" % color(0.006, 0.008, 0.014))
    lines.append("sky_horizon_color = %s" % color(0.020, 0.026, 0.032))
    lines.append("fog_color = %s" % color(0.035, 0.042, 0.050))
    lines.append("fog_near = 24.0")
    lines.append("fog_far = 130.0")
    lines.append("night_mode = true")
    lines.append("star_intensity = 0.18")
    lines.append("sun_color = %s" % color(0.42, 0.50, 0.68))
    lines.append("ambient_color = %s" % color(0.10, 0.13, 0.18))
    lines.append("ambient_energy = 0.10")
    lines.append("exposure = 1.15")
    lines.append("fog_density = 0.0100")
    lines.append("volumetric_fog = true")
    lines.append("volumetric_fog_density = 0.012")
    lines.append("screen_space_ao = true")
    lines.append("sun_energy = 0.16")
    lines.append("sun_pitch = -58.0")
    lines.append("sun_yaw = 130.0")
    lines.append("grip_scale = 0.92")
    lines.append("rolling_resistance_scale = 1.06")
    lines.append("ps1_style = true")
    lines.append("flat_shading = true")
    lines.append("dither_fog = true")
    lines.append("color_banding = 5")
    lines.append("sky_flat = true")
    lines.append("enable_speed_fx = true")
    lines.append('stage_scene = "res://scenes/rally_stage_england.tscn"')
    return "\n".join(lines) + "\n"


def scene_text():
    with open(BASE_SCENE, encoding="utf-8") as handle:
        text = handle.read()
    header, _sep, body = text.partition("\n[node ")
    blocks = ["[node " + chunk for chunk in body.split("\n[node ")]
    kept = []
    for block in blocks:
        parent = re.search(r'parent="([^"]+)"', block)
        if parent and parent.group(1).split("/")[0] in ("Props", "ManualProps", "StudioProps"):
            continue
        kept.append(block)
    body = "\n".join(kept)
    scene_uid = uid_tool.godot_uid("res://scenes/rally_stage_england.tscn")
    header = re.sub(r"\[gd_scene format=3[^\]]*\]",
                    '[gd_scene format=3 uid="%s"]' % scene_uid, header)
    route_uid = uid_tool.godot_uid("res://data/tracks/stage_england_route.tres")
    header = re.sub(r'\[ext_resource type="Curve3D"[^\]]*id="4_route"\]',
                    '[ext_resource type="Curve3D" uid="%s" '
                    'path="res://data/tracks/stage_england_route.tres" id="4_route"]' % route_uid,
                    header)
    track_uid = uid_tool.godot_uid("res://data/tracks/stage_england.tres")
    added = ('[ext_resource type="Resource" uid="%s" path="res://data/tracks/stage_england.tres" '
             'id="track_england"]' % track_uid)
    header = header.replace('[ext_resource type="Script" uid="uid://bxev3gfr3ewld" '
                            'path="res://scripts/rally_stage.gd" id="1_stage"]',
                            '[ext_resource type="Script" uid="uid://bxev3gfr3ewld" '
                            'path="res://scripts/rally_stage.gd" id="1_stage"]\n' + added)
    # Своя трасса и своя сцена: заезд всегда открывает этот участок.
    body = body.replace('prop_library = ExtResource("13_props")',
                        'prop_library = ExtResource("13_props")\ntrack_override = ExtResource("track_england")')
    # Деревья лесной трассы больше не нужны — убираем их ext_resource.
    for dead in ("pine_tree", "fir_tree", "bush", "boulder"):
        header = re.sub(r'\[ext_resource type="PackedScene"[^\]]*id="%s"\]\n' % dead, "", header)
    header = re.sub(r'\[ext_resource type="PackedScene"[^\]]*path="res://scenes/props/(pine_tree|fir_tree|bush|boulder)\.tscn" id="[^"]+"\]\n', "", header)
    return header.rstrip("\n") + "\n\n" + body.lstrip("\n")


# --------------------------------------------------------------- проверки
def verify(small, large, points, acc, level):
    problems = []
    gap, where = route_min_river_gap(points, acc, [small["distance"], large["distance"]])
    if gap < 24.0:
        problems.append("дорога подходит к оси реки на %.1f м (%.0f м трассы)" % (gap, where))
    for name, hit, clearance in (("малый", small, SMALL_CLEARANCE), ("большой", large, LARGE_CLEARANCE)):
        # Перпендикулярность: направление дороги против нормали реки.
        slope = (river_x(hit["z"] + 1.0) - river_x(hit["z"] - 1.0)) * 0.5
        tangent = (slope, 1.0)
        norm = math.hypot(*tangent)
        cos = abs((tangent[0] * math.cos(hit["heading"]) + tangent[1] * math.sin(hit["heading"])) / norm)
        angle = math.degrees(math.acos(min(1.0, cos)))
        if angle < 40.0:
            problems.append("%s мост пересекает реку под углом %.0f° (нужно не меньше 40°)"
                            % (name, angle))
        else:
            print("  %s мост: угол к реке %.0f°" % (name, angle))
        margin = hit["y"] - level(hit["z"])
        if margin < clearance - 0.2:
            problems.append("%s мост: вода в %.1f м под полотном (нужно %.1f)" % (name, margin, clearance))
    worst = 1e9
    # Уровень воды вдоль реки: проверяем, что у обоих мостов он ниже полотна.
    for name, hit, clearance in (("малый", small, SMALL_CLEARANCE), ("большой", large, LARGE_CLEARANCE)):
        curve = [(p[0], p[2], p[1]) for p in river_curve_samples()]
        best = min(curve, key=lambda p: (p[0] - hit["x"]) ** 2 + (p[1] - hit["z"]) ** 2)
        margin = hit["y"] - best[2]
        if margin < clearance - 0.5:
            problems.append("%s мост: кривая реки дала %.2f м просвета (нужно %.1f)"
                            % (name, margin, clearance))
        worst = min(worst, margin)
    return problems, gap, worst


def main():
    controls = compose_route()
    points, acc = write_route(controls)
    length = acc[-1]
    print("Трасса: %.0f м (лимит %.0f), контрольных точек %d" % (length, MAX_ROUTE_LENGTH, len(controls)))
    if length > MAX_ROUTE_LENGTH:
        raise SystemExit("Трасса длиннее %.0f м — включится потоковый мир." % MAX_ROUTE_LENGTH)
    heights = [p[2] for p in points]
    print("Высоты: %.1f … %.1f м (подъём %.0f м)" % (min(heights), max(heights), max(heights) - min(heights)))
    found = crossings(points, acc)
    print("Пересечений реки: %d" % len(found))
    for hit in found:
        print("  %.0f м  z=%.0f  высота %.1f" % (hit["distance"], hit["z"], hit["y"]))
    if len(found) != 2:
        raise SystemExit("Ожидалось ровно две переправы через реку.")
    small, large = sorted(found, key=lambda hit: hit["y"])
    level = write_river(small, large, terrain_sampler())
    problems, gap, worst_margin = verify(small, large, points, acc, level)
    print("Зазор дороги от оси реки вне мостов: %.0f м" % gap)
    print("Просвет под мостами: вода %.1f / %.1f м ниже полотна (мин %.2f)" % (
        small["y"] - level(small["z"]), large["y"] - level(large["z"]), worst_margin))
    if problems:
        for problem in problems:
            print("  ПРОБЛЕМА: " + problem)
        raise SystemExit("Проверки не пройдены.")
    route_uid = uid_tool.godot_uid("res://data/tracks/stage_england_route.tres")
    river_uid = uid_tool.godot_uid("res://data/tracks/stage_england_river.tres")
    with open(TRACK_PATH, "w", encoding="utf-8") as handle:
        handle.write(track_text(route_uid, river_uid, small, large))
    with open(SCENE_PATH, "w", encoding="utf-8") as handle:
        handle.write(scene_text())
    print("Готово: %s, %s, %s" % (
        os.path.relpath(ROUTE_PATH, ROOT), os.path.relpath(RIVER_PATH, ROOT),
        os.path.relpath(TRACK_PATH, ROOT)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
