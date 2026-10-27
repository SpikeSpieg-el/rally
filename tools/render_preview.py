"""Быстрый оффлайн-рендер трассы (проверка силуэта до запуска Godot).

Рисует землю и полотно в перспективе «от старта», с раскраской по высоте и
освещению. Не движок, но сразу видно: дорога на месте, склонов-стенок нет.

Запуск:  python3 tools/render_preview.py [out.png]
"""
import math
import sys

import stage_model as model

W, H = 1280, 720


def look_at(eye, target, up=(0.0, 1.0, 0.0)):
    fx = [target[k] - eye[k] for k in range(3)]
    n = math.sqrt(sum(v * v for v in fx)) or 1.0
    fx = [v / n for v in fx]
    right = [fx[1] * up[2] - fx[2] * up[1], fx[2] * up[0] - fx[0] * up[2], fx[0] * up[1] - fx[1] * up[0]]
    rn = math.sqrt(sum(v * v for v in right)) or 1.0
    right = [v / rn for v in right]
    upv = [right[1] * fx[2] - right[2] * fx[1], right[2] * fx[0] - right[0] * fx[2],
           right[0] * fx[1] - right[1] * fx[0]]
    return fx, right, upv


def project(p, eye, fx, right, upv, fov_scale):
    d = [p[0] - eye[0], p[1] - eye[1], p[2] - eye[2]]
    z = d[0] * fx[0] + d[1] * fx[1] + d[2] * fx[2]
    if z <= 0.5:
        return None
    x = (d[0] * right[0] + d[1] * right[1] + d[2] * right[2]) / z * fov_scale + W * 0.5
    y = H * 0.5 - (d[0] * upv[0] + d[1] * upv[1] + d[2] * upv[2]) / z * fov_scale
    return (x, y, z)


def main(out="/tmp/stage_preview.png"):
    from PIL import Image, ImageDraw
    stage = model.Stage()
    net = stage.net
    cfg = stage.cfg
    step = 2
    cols, rows, cell = net.cols, net.rows, net.cell
    rect = stage.rect

    verts = {}
    def vpos(gx, gz):
        key = (gx, gz)
        p = verts.get(key)
        if p is None:
            p = (rect[0] + gx * cell, stage.grid[gz * cols + gx], rect[1] + gz * cell)
            verts[key] = p
        return p

    mid = net.point_at(net.length * 0.55)
    start = mid
    eye = (mid[0] - 330.0, mid[1] + 300.0, mid[2] - 360.0)
    target = (mid[0] + 20.0, mid[1] - 10.0, mid[2] + 40.0)
    fx, right, upv = look_at(eye, target)
    fov = W * 0.9

    faces = []
    for gz in range(0, rows - 1 - step, step):
        for gx in range(0, cols - 1 - step, step):
            i00 = gz * cols + gx
            d = stage.dist[i00]
            if d < cfg["corridor"] * 0.9:
                continue
            p0 = vpos(gx, gz)
            p1 = vpos(gx + step, gz)
            p2 = vpos(gx, gz + step)
            p3 = vpos(gx + step, gz + step)
            for tri in ((p0, p1, p2), (p1, p3, p2)):
                pts = [project(p, eye, fx, right, upv, fov) for p in tri]
                if any(p is None for p in pts):
                    continue
                depth = sum(p[2] for p in pts) / 3.0
                h = (tri[0][1] + tri[1][1] + tri[2][1]) / 3.0
                # плоская нормаль → освещение
                ax = [tri[1][k] - tri[0][k] for k in range(3)]
                bx = [tri[2][k] - tri[0][k] for k in range(3)]
                nx = ax[1] * bx[2] - ax[2] * bx[1]
                ny = ax[2] * bx[0] - ax[0] * bx[2]
                nz = ax[0] * bx[1] - ax[1] * bx[0]
                nl = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
                light = max(0.0, (nx * 0.4 + ny * 0.8 + nz * 0.35) / nl)
                faces.append((depth, [(p[0], p[1]) for p in pts], h, light, False))

    # полотно дороги
    d = 1.0
    lane = cfg["corridor"]
    while d < net.length - 1.0:
        a = net.point_at(d)
        b = net.point_at(min(net.length, d + 2.0))
        da = net.direction_at(d)
        side = (da[2], 0.0, -da[0])
        quad = [
            (a[0] - side[0] * lane, a[1], a[2] - side[2] * lane),
            (a[0] + side[0] * lane, a[1], a[2] + side[2] * lane),
            (b[0] + side[0] * lane, b[1] + 0.05, b[2] + side[2] * lane),
            (b[0] - side[0] * lane, b[1] + 0.05, b[2] - side[2] * lane),
        ]
        pts = [project(p, eye, fx, right, upv, fov) for p in quad]
        if not all(pts):
            d += 2.0
            continue
        depth = min(p[2] for p in pts)
        faces.append((depth - 0.5, [(p[0], p[1]) for p in pts], a[1], 1.0, True))
        d += 2.0

    faces.sort(key=lambda f: -f[0])
    img = Image.new("RGB", (W, H), (150, 175, 200))
    draw = ImageDraw.Draw(img)
    for depth, pts, h, light, is_road in faces:
        fog = min(0.75, max(0.0, (depth - 250.0) / 900.0))
        if is_road:
            base = (120, 100, 78)
        else:
            t = max(0.0, min(1.0, (h + 20.0) / 70.0))
            base = (int(55 + 40 * t), int(95 + 55 * t), int(45 + 30 * t))
        r = int(base[0] * (0.55 + 0.65 * light) * (1 - fog) + 150 * fog)
        g = int(base[1] * (0.55 + 0.65 * light) * (1 - fog) + 175 * fog)
        b = int(base[2] * (0.55 + 0.65 * light) * (1 - fog) + 200 * fog)
        draw.polygon(pts, fill=(min(255, r), min(255, g), min(255, b)))
    img.save(out)
    print("saved", out, "faces", len(faces))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "/tmp/stage_preview.png")
