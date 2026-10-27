"""Authoring tool for the hand-made rally stage.

Builds the stage centre line out of straights / arcs, smooths the elevation
profile, then writes a Godot Curve3D resource (data/tracks/stage_forest_route.tres).

Edit SEGS below (or edit the curve by hand in Godot) and run:
    python3 tools/author_route.py
"""
import math

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

STEP = 0.25                 # sampling step while composing (m)
HEIGHT_WINDOW = 16.0        # elevation smoothing window (m)
CONTROL_SPACING = 65.0      # spacing of curve control points (m)
MAX_GRADE_DEG = 8.0        # safety limit for the authored profile

OUT_CURVE = "/home/user/rally/data/tracks/stage_forest_route.tres"


def compose():
    x = z = h = y = dist = 0.0
    pts = [(x, z, y)]                       # x, z, height
    for seg in SEGS:
        if seg[0] == "s":
            _, length, climb = seg
            n = max(2, int(length / STEP))
            for _ in range(n):
                d = length / n
                x += math.cos(h) * d
                z += math.sin(h) * d
                y += climb / n
                dist += d
                pts.append((x, z, y))
        else:
            _, radius, angle, climb, direction = seg
            ang = math.radians(angle)
            n = max(3, int(radius * ang / STEP))
            d_ang = ang / n
            for _ in range(n):
                h += direction * d_ang
                x += math.cos(h) * radius * d_ang
                z += math.sin(h) * radius * d_ang
                y += climb / n
                dist += radius * d_ang
                pts.append((x, z, y))
    return pts, dist


def smooth_heights(pts, window_m):
    """triangular moving average of the elevation, XZ untouched"""
    n = len(pts)
    radius = max(1, int(window_m / STEP))
    out = []
    for i in range(n):
        lo, hi = max(0, i - radius), min(n - 1, i + radius)
        acc = wsum = 0.0
        for j in range(lo, hi + 1):
            w = 1.0 - abs(j - i) / (radius + 1.0)
            acc += pts[j][2] * w
            wsum += w
        out.append((pts[i][0], pts[i][1], acc / wsum))
    return out


def limit_grade(pts, max_deg):
    """keep the profile under a maximum slope, both directions"""
    n = len(pts)
    g = math.tan(math.radians(max_deg))
    ys = [p[2] for p in pts]
    ds = [0.0]
    for i in range(1, n):
        ds.append(math.dist((pts[i - 1][0], pts[i - 1][1]), (pts[i][0], pts[i][1])))
    for i in range(1, n):
        ys[i] = min(max(ys[i], ys[i - 1] - g * ds[i]), ys[i - 1] + g * ds[i])
    for i in range(n - 2, -1, -1):
        ys[i] = min(max(ys[i], ys[i + 1] - g * ds[i + 1]), ys[i + 1] + g * ds[i + 1])
    return [(pts[i][0], pts[i][1], ys[i]) for i in range(n)]


def resample(pts, step):
    out = [pts[0]]
    acc = 0.0
    for i in range(1, len(pts)):
        acc += math.dist((pts[i - 1][0], pts[i - 1][1]), (pts[i][0], pts[i][1]))
        if acc >= step:
            out.append(pts[i])
            acc = 0.0
    if out[-1] != pts[-1]:
        out.append(pts[-1])
    return out


def stats(pts, step):
    worst_grade = 0.0
    for i in range(1, len(pts)):
        d = math.dist((pts[i - 1][0], pts[i - 1][1]), (pts[i][0], pts[i][1]))
        if d > 0.01:
            worst_grade = max(worst_grade, abs(pts[i][2] - pts[i - 1][2]) / d)
    min_gap = int(90.0 / step)
    best, where = 1e9, None
    for i in range(0, len(pts), 4):
        for j in range(i + min_gap, len(pts), 4):
            d = math.hypot(pts[i][0] - pts[j][0], pts[i][1] - pts[j][1])
            if d < best:
                best, where = d, (round(i * step), round(j * step))
    ys = [p[2] for p in pts]
    return {
        "grade": math.degrees(math.atan(worst_grade)),
        "clearance": best,
        "clearance_at": where,
        "height_min": min(ys),
        "height_max": max(ys),
    }


def write_curve(ctrl, path):
    """Catmull-Rom handles as Godot's packed curve data.

    ВАЖНО: Godot хранит point_in / point_out ОТНОСИТЕЛЬНО самой точки
    (Curve3D.set_point_in принимает смещение, а не мировую позицию).
    Абсолютные позиции здесь дают «спагетти» и длину в 10 раз больше.
    """
    n = len(ctrl)
    values = []
    for i in range(n):
        px, pz, py = ctrl[i]                 # x, z, height
        prev = ctrl[max(0, i - 1)]
        nxt = ctrl[min(n - 1, i + 1)]
        tx, tz, ty = nxt[0] - prev[0], nxt[1] - prev[1], nxt[2] - prev[2]
        tl = math.hypot(tx, tz) or 1.0
        hx, hz, hy = tx / tl, tz / tl, ty / tl
        seg_in = math.dist((prev[0], prev[1]), (px, pz)) if i > 0 else 0.0
        seg_out = math.dist((nxt[0], nxt[1]), (px, pz)) if i < n - 1 else 0.0
        hin = seg_in / 3.0
        hout = seg_out / 3.0
        pos = (px, py, pz)                   # Godot: x, y(height), z
        hin_v = (px - hx * hin, py - hy * hin, pz - hz * hin)
        hout_v = (px + hx * hout, py + hy * hout, pz + hz * hout)
        hin_rel = (hin_v[0] - px, hin_v[1] - py, hin_v[2] - pz)
        hout_rel = (hout_v[0] - px, hout_v[1] - py, hout_v[2] - pz)
        values.append("%.4f, %.4f, %.4f" % hin_rel)
        values.append("%.4f, %.4f, %.4f" % hout_rel)
        values.append("%.4f, %.4f, %.4f" % pos)
    text = (
        '[gd_resource type="Curve3D" format=3]\n\n'
        "[resource]\n"
        "bake_interval = 0.5\n"
        "_data = {\n"
        '"points": PackedVector3Array(%s),\n'
        '"tilts": PackedFloat32Array(%s)\n'
        "}\n"
        "point_count = %d\n" % (", ".join(values), ", ".join(["0"] * n), n)
    )
    with open(path, "w") as f:
        f.write(text)


def render(pts, path="/tmp/route_preview.png"):
    from PIL import Image, ImageDraw
    xs = [p[0] for p in pts]
    zs = [p[1] for p in pts]
    ys = [p[2] for p in pts]
    minx, maxx = min(xs) - 30, max(xs) + 30
    minz, maxz = min(zs) - 30, max(zs) + 30
    scale = 900.0 / max(maxx - minx, maxz - minz)
    W, H = int((maxx - minx) * scale), int((maxz - minz) * scale)
    img = Image.new("RGB", (W, H), (18, 22, 26))
    d = ImageDraw.Draw(img)
    for gx in range(int(minx // 100) * 100, int(maxx) + 100, 100):
        px = (gx - minx) * scale
        d.line([(px, 0), (px, H)], fill=(34, 40, 46))
    for gz in range(int(minz // 100) * 100, int(maxz) + 100, 100):
        py = (gz - minz) * scale
        d.line([(0, py), (W, py)], fill=(34, 40, 46))
    screen = [((p[0] - minx) * scale, (p[1] - minz) * scale) for p in pts]
    d.line(screen, fill=(150, 130, 105), width=7, joint="curve")
    lo, hi = min(ys), max(ys)
    for i in range(0, len(pts) - 1, 6):
        t = (ys[i] - lo) / max(hi - lo, 1e-6)
        col = (int(90 + 150 * t), int(200 - 90 * t), int(80 + 40 * (1 - t)))
        d.line([screen[i], screen[i + 1]], fill=col, width=4)
    for i in range(0, len(pts) - 40, 160):
        d.ellipse([screen[i][0] - 3, screen[i][1] - 3,
                   screen[i][0] + 3, screen[i][1] + 3], fill=(255, 220, 60))
    d.ellipse([screen[0][0] - 9, screen[0][1] - 9,
               screen[0][0] + 9, screen[0][1] + 9], fill=(60, 220, 255))
    d.ellipse([screen[-1][0] - 9, screen[-1][1] - 9,
               screen[-1][0] + 9, screen[-1][1] + 9], fill=(255, 90, 40))
    img.save(path)


def main():
    raw, length = compose()
    pts = resample(limit_grade(smooth_heights(raw, HEIGHT_WINDOW), MAX_GRADE_DEG), 1.0)
    ctrl = resample(pts, CONTROL_SPACING)
    s = stats(pts, 1.0)
    print("length      %.0f m" % length)
    print("control pts %d" % len(ctrl))
    print("self gap    %.1f m at %s" % (s["clearance"], s["clearance_at"]))
    print("height      %.1f .. %.1f m" % (s["height_min"], s["height_max"]))
    print("max grade   %.1f deg" % s["grade"])
    write_curve(ctrl, OUT_CURVE)
    render(pts)
    print("written     " + OUT_CURVE)


if __name__ == "__main__":
    main()
