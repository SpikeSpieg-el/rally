"""Диагностика «впадин»: ищет провалы высоты на полотне и у дороги."""
import math
import sys

sys.path.insert(0, "/home/user/rally/tools")
import stage_model as model


def analyze(stage):
    net, cfg = stage.net, stage.cfg
    half, corridor = cfg["half"], cfg["corridor"]
    print("length %.0f m  half %.1f  corridor %.1f  cell %.1f" % (
        net.length, half, corridor, cfg["cell"]))

    # 1) Профиль высоты осевой линии: локальные впадины.
    #    Считаем кривизну профиля: где вторая производная сильно отрицательна
    #    на окне 30 м — там «яма».
    n = int(net.length)
    prof = [net.height_at_along(float(d)) for d in range(n + 1)]
    dips = []
    for i in range(15, n - 15):
        window = 12.0
        h0 = net.height_at_along(float(max(0, i - 25)))
        h1 = prof[i]
        h2 = net.height_at_along(float(min(n, i + 25)))
        # точка ниже хорды соседей => впадина
        chord = (h0 + h2) / 2.0
        if h1 < chord - 0.25:
            dips.append((i, h1 - chord))
    # группируем
    groups = []
    for d, depth in dips:
        if groups and d - groups[-1][-1][0] <= 30:
            groups[-1].append((d, depth))
        else:
            groups.append([(d, depth)])
    print("\n== Впадины профиля осевой (глубина по хорде 50м) ==")
    for g in groups:
        worst = min(g, key=lambda t: t[1])
        print("  км %4d  глубина %.2f м" % (worst[0], -worst[1]))

    # 2) Стык полотно/обочина: высота height_at() на обочине против
    #    высоты осевой на том же километре. Расхождение > 0.15 м = яма/бугор.
    print("\n== Стык полотна и обочины (|Δ| > 0.15 м) ==")
    bad = 0
    worst_all = 0.0
    for d10 in range(20, int(net.length) - 20, 10):
        p = net.point_at(float(d10))
        dirv = net.direction_at(float(d10))
        side = (dirv[2], -dirv[0])
        for lat in (half * 0.95, half * 1.05, corridor * 0.98):
            x = p[0] + side[0] * lat
            z = p[2] + side[1] * lat
            h = model.height(net, cfg, x, z)
            expect = p[1] - cfg["camber"] * (lat / corridor) ** 2
            diff = h - expect
            if abs(diff) > 0.15:
                bad += 1
                worst_all = max(worst_all, abs(diff))
                if bad <= 25:
                    print("  км %4d  lat %5.1f  Δ %+6.2f м" % (d10, lat, diff))
    print("  всего расхождений: %d (худшее %.2f м)" % (bad, worst_all))

    # 3) Земля под полотном против полотна: если земля выше — протыкание,
    #    ниже на > 0.5 — щель/впадина у кромки.
    print("\n== Земля у кромки (ground - полотно, |Δ| > 0.4 м) ==")
    bad = 0
    worst_all = 0.0
    for d10 in range(20, int(net.length) - 20, 10):
        p = net.point_at(float(d10))
        dirv = net.direction_at(float(d10))
        side = (dirv[2], -dirv[0])
        for lat in (corridor + 1.0, corridor + 2.5, corridor + 4.0):
            x = p[0] + side[0] * lat
            z = p[2] + side[1] * lat
            g = stage.ground(x, z)
            expect = p[1] - cfg["ditch"]
            diff = g - expect
            if abs(diff) > 0.4:
                bad += 1
                worst_all = max(worst_all, abs(diff))
                if bad <= 25:
                    print("  км %4d  lat %5.1f  Δ %+6.2f м" % (d10, lat, diff))
    print("  всего: %d (худшее %.2f м)" % (bad, worst_all))


if __name__ == "__main__":
    stage = model.Stage()
    analyze(stage)
