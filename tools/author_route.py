"""Authoring tool for the hand-made rally stage (ночной лес).

Builds the stage centre line out of straights / arcs, smooths the elevation
profile, then writes a Godot Curve3D resource (data/tracks/stage_forest_route.tres).

Математика записи кривой (монотонные касательные высоты, адаптивные
контрольные точки, проверка результата) живёт в tools/route_kit.py —
она общая для всех авторских трасс.

Edit SEGS below (or edit the curve by hand in Godot) and run:
    python3 tools/author_route.py
"""
import sys

sys.path.insert(0, "/home/user/rally/tools")
import route_kit as kit

# kind: "s" straight   (length, climb)
#       "a" arc        (radius, angle_deg, climb, direction)  dir +1 = right
SEGS = [
    ("s", 160.0, 0.0),                      # старт
    ("a", 110.0, 55.0, 6.0, +1),            # быстрая правая дуга
    ("s", 70.0, 3.0),
    ("a", 130.0, 45.0, 8.0, -1),            # длинная левая
    ("s", 60.0, 4.0),
    ("s", 45.0, 0.0),                       # полка перед шпилькой
    ("a", 16.0, 165.0, 0.0, +1),            # правая шпилька — ровная
    ("s", 45.0, 0.0),                       # полка после шпильки
    ("s", 150.0, 14.0),                     # подъём + стиральная доска
    ("a", 75.0, 70.0, -5.0, -1),            # левая дуга, спуск
    ("a", 90.0, 55.0, -6.0, +1),            # правая дуга
    ("s", 60.0, 0.0),
    ("a", 60.0, 50.0, 3.0, -1),             # поджимающая левая
    ("s", 90.0, 12.0),                      # подъём к гребню
    ("s", 30.0, -3.0),                      # трамплин: короткий сброс за гребнем
    ("s", 40.0, 0.0),                       # полка
    ("a", 15.0, 170.0, 0.0, -1),            # левая шпилька — ровная
    ("s", 40.0, 0.0),                       # полка
    ("s", 90.0, 6.0),
    ("a", 105.0, 80.0, -3.0, +1),           # гребень, правая дуга
    ("a", 95.0, 70.0, -12.0, -1),           # гребень, левая дуга
    ("s", 70.0, -5.0),
    ("a", 26.0, 40.0, -2.0, +1),            # шифт
    ("a", 26.0, 45.0, -1.0, -1),
    ("a", 26.0, 38.0, -1.0, +1),
    ("s", 90.0, -4.0),
    ("s", 40.0, 0.0),                       # полка
    ("a", 14.0, 168.0, 0.0, +1),            # закрывающая шпилька — ровная
    ("s", 40.0, 0.0),                       # полка
    ("s", 130.0, -6.0),
    ("a", 90.0, 50.0, -6.0, -1),
    ("s", 240.0, -8.0),                     # финишная прямая
]

OUT_CURVE = "/home/user/rally/data/tracks/stage_forest_route.tres"
MIN_CLEARANCE = 26.0        # мин. зазор между витками трассы (м)


def main():
    pts, length = kit.build_intent(SEGS)
    ctrl = kit.select_controls(pts)
    kit.write_curve(ctrl, OUT_CURVE)
    print("stage_forest (ночной лес)")
    print("  длина замысла    %.0f м" % length)
    print("  контрольных      %d" % len(ctrl))
    ok = kit.verify(OUT_CURVE, pts, min_clearance=MIN_CLEARANCE)
    kit.render(pts, "/tmp/route_forest.png")
    if not ok:
        raise SystemExit("ПРОВЕРКА НЕ ПРОШЛА: правь SEGS или параметры kit")
    print("written " + OUT_CURVE)


if __name__ == "__main__":
    main()
