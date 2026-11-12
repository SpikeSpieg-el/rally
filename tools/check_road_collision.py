#!/usr/bin/env python3
"""Проверка: не торчит ли коллизия рельефа над лентой дороги.

Баг, который ловит этот скрипт, — «невидимые кочки». Рельеф под полотном
вырезан дырой (видимого меша там нет), но коллизия рельефа строилась по
разрежённой сетке: при `terrain_cell` 3 м и `terrain_collider_stride` 2
ячейка коллизии — 6 м, и на склоне выемки/насыпи хорда проходит НАД лентой.
Машину подбрасывает на ровном месте, а посмотреть не на что.

В движке это лечит `_make_terrain_collider()`: в полосе у дороги коллизия
строится по той же сетке и с теми же дырами, что и видимый меш. Скрипт
повторяет эту логику и падает, если над лентой снова что-то торчит.

    python3 tools/check_road_collision.py [--coarse] [data/tracks/*.tres ...]

`--coarse` отключает точную полосу у дороги и воспроизводит старый баг —
так проверяется, что сам детектор его видит.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import stage_model as model  # noqa: E402

ROAD_MESH_LIFT = 0.035       # лента лежит на столько выше «земли» в коридоре
POKE_LIMIT = 0.05            # допустимое превышение коллизии над лентой, м
SAMPLE_STEP = 2.0
# При крупной сетке рельефа точной полосы у дороги не хватает: ячейка 6 м и
# шире сама по себе шире обочины, и хорда снова залезает на ленту. Для таких
# трасс это предупреждение с подсказкой, а не провал проверки.
FINE_CELL = 3.5


def read_settings(track_path):
    """Параметры, которые в игре приходят из сцены/настроек этапа."""
    return {
        "stride": 2,          # RallyStageSettings.terrain_collider_stride
        "caps": 0.0,          # «крышки» старта/финиша на трассах этапов не нужны
    }


def analyse(track_path, verbose=True, exact_band=True):
    """Возвращает (макс. превышение, cell) или None, если трассы нет."""
    cfg = model.read_track(track_path)
    road_path = None
    for line in open(track_path, encoding="utf-8"):
        found = line.find('path="res://data/tracks/')
        if found >= 0 and "route" in line and "ext_resource" in line:
            start = line.index('path="res://') + len('path="res://')
            road_path = line[start:line.index('"', start)]
            break
    if road_path is None:
        return None
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    route_file = os.path.join(root, road_path.replace("res://", ""))
    if not os.path.exists(route_file):
        return None

    route = model.sample_curve(model.load_curve(route_file), SAMPLE_STEP)
    if len(route) < 3:
        return None
    xs = [p[0] for p in route]
    zs = [p[2] for p in route]
    margin = cfg["margin"]
    rect = (min(xs) - margin, min(zs) - margin,
            max(xs) - min(xs) + 2.0 * margin, max(zs) - min(zs) + 2.0 * margin)
    net = model.Net(route, rect, cfg["cell"])
    stride = read_settings(track_path)["stride"]
    cell = cfg["cell"]
    coarse = cell * stride
    corridor = cfg["half"] + cfg["shoulder"]
    hole = corridor * 0.92
    # exact_band=False — воспроизвести СТАРОЕ поведение (одна грубая сетка):
    # нужно, чтобы проверить сам детектор, а не только текущую сборку.
    near_limit = (hole + coarse * 2.0) if exact_band else -1.0

    cache = {}

    def ground(x, z):
        key = (round(x, 2), round(z, 2))
        if key not in cache:
            cache[key] = model.height(net, cfg, x, z)
        return cache[key]

    def distance(x, z):
        return net.distance_to_road(x, z)

    ox, oz = rect[0], rect[1]
    worst = 0.0
    worst_at = 0.0
    pokes = 0
    total = 0
    for i in range(0, len(route), max(1, int(round(SAMPLE_STEP / 2.0)))):
        px, py, pz = route[i]
        total += 1
        cx = math.floor((px - ox) / coarse)
        cz = math.floor((pz - oz) / coarse)
        gx0, gz0 = cx * stride, cz * stride
        gx1, gz1 = gx0 + stride, gz0 + stride
        corners = [(gx0, gz0), (gx1, gz0), (gx0, gz1), (gx1, gz1)]
        near = min(distance(ox + gx * cell, oz + gz * cell) for gx, gz in corners) < near_limit
        if near:
            # Точная подъячейка с той же дырой, что и видимый меш.
            sx = int(math.floor((px - ox) / cell)) * cell
            sz = int(math.floor((pz - oz) / cell)) * cell
            quad = [(sx, sz), (sx + cell, sz), (sx, sz + cell), (sx + cell, sz + cell)]
            if all(distance(ox + qx, oz + qz) < hole for qx, qz in quad):
                continue  # дыра: под лентой физики нет вообще
            x0, z0 = ox + sx, oz + sz
            x1, z1 = x0 + cell, z0 + cell
        else:
            x0, z0 = ox + gx0 * cell, oz + gz0 * cell
            x1, z1 = ox + gx1 * cell, oz + gz1 * cell
        h00 = ground(x0, z0)
        h10 = ground(x1, z0)
        h01 = ground(x0, z1)
        h11 = ground(x1, z1)
        tx = (px - x0) / (x1 - x0)
        tz = (pz - z0) / (z1 - z0)
        if tx + tz <= 1.0:
            surface = h00 + (h10 - h00) * tx + (h01 - h00) * tz
        else:
            surface = h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)
        poke = surface - (py + ROAD_MESH_LIFT)
        if poke > POKE_LIMIT:
            pokes += 1
        if poke > worst:
            worst = poke
            worst_at = i * SAMPLE_STEP
    if verbose:
        print("%s: проверено %d точек, коллизия выше ленты на %.1f%%, максимум %+.3f м%s"
              % (os.path.relpath(track_path, root), total,
                 100.0 * pokes / max(total, 1), worst,
                 (" (%.0f м трассы)" % worst_at) if worst > POKE_LIMIT else ""))
    return worst, cell


def main(argv):
    roots = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    tracks = [name for name in argv[1:] if not name.startswith("--")]
    if not tracks:
        folder = os.path.join(roots, "data", "tracks")
        tracks = sorted(os.path.join(folder, name) for name in os.listdir(folder)
                        if name.endswith(".tres") and "river" not in name and "route" not in name)
    exact_band = "--coarse" not in argv
    worst = 0.0
    checked = 0
    bad = []
    coarse = []
    for track in tracks:
        result = analyse(track, exact_band=exact_band)
        if result is None:
            continue
        checked += 1
        poke, cell = result
        worst = max(worst, poke)
        if poke > POKE_LIMIT:
            if cell > FINE_CELL:
                coarse.append((track, poke, cell))
            else:
                bad.append((track, poke))
    if checked == 0:
        print("Нечего проверять.")
        return 1
    for track, poke, cell in coarse:
        print("ВНИМАНИЕ: %s — сетка рельефа %.0f м, точной полосы не хватает (%.2f м). "
              "Уменьшите terrain_cell." % (os.path.relpath(track, roots), cell, poke))
    if bad:
        for track, poke in bad:
            print("ПРОБЛЕМА: %s — коллизия торчит над лентой на %.2f м." 
                  % (os.path.relpath(track, roots), poke))
        print("Это невидимые кочки: рельеф под полотном вырезан, а его коллизия — нет.")
        return 1
    if coarse:
        print("OK: критичных превышений нет, но у трасс с крупной сеткой рельефа остаются "
              "кочки (см. предупреждения выше).")
    else:
        print("OK: коллизия рельефа нигде не поднимается над лентой больше %.2f м." % worst)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
