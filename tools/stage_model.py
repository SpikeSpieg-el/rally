"""Точная Python-модель того, что строит rally_stage.gd.

Нужна, чтобы запекать ассеты в сцену (`tools/bake_stage_scene.py`) по той же
математике высот, что и движок: та же функция height_at(), тот же кювет,
тот же лимит склонов и та же триангуляция сетки.

Запуск отдельно не нужен — используется как модуль.
"""
import math
import re

ROOT = "/home/user/rally"
CURVE = ROOT + "/data/tracks/stage_forest_route.tres"
TRACK = ROOT + "/data/tracks/stage_forest.tres"
FAR = 100000.0


# ---------------------------------------------------------------- конфиг
def read_track(path=TRACK):
    text = open(path).read()
    cfg = {}

    def num(key, default):
        m = re.search(r"^%s = (-?[\d.]+)" % key, text, re.M)
        return float(m.group(1)) if m else default

    cfg["half"] = num("road_half_width", 5.0)
    cfg["shoulder"] = num("road_shoulder", 2.0)
    cfg["camber"] = num("road_camber", 0.08)
    cfg["step"] = num("road_step", 1.5)
    cfg["cell"] = num("terrain_cell", 2.0)
    cfg["margin"] = num("terrain_margin", 130.0)
    cfg["emb_slope"] = num("embankment_slope_deg", 22.0)
    cfg["emb_min"] = num("embankment_min_width", 5.0)
    cfg["emb_max"] = num("embankment_max_width", 40.0)
    cfg["fade_start"] = num("hills_fade_start", 14.0)
    cfg["fade_len"] = num("hills_fade_length", 70.0)
    cfg["max_slope"] = num("max_terrain_slope_deg", 32.0)
    cfg["ditch"] = num("road_ditch_depth", 0.3)
    cfg["bump_amp"] = num("bumps_amplitude", 0.0)
    cfg["bump_wl"] = num("bumps_wavelength", 12.0)
    cfg["bump_rough"] = num("bumps_roughness", 0.0)
    cfg["bump_cross"] = num("bumps_cross", 0.0)
    cfg["corridor"] = cfg["half"] + cfg["shoulder"]
    return cfg


# ---------------------------------------------------------------- кривая
def load_curve(path=CURVE):
    """Точки Curve3D: (point_in, point_out, position) в мировых координатах."""
    text = open(path).read()
    pts = re.search(r'"points": PackedVector3Array\(([^)]*)\)', text, re.S).group(1)
    nums = [float(v) for v in pts.replace("\n", " ").split(",") if v.strip()]
    out = []
    for i in range(0, len(nums), 9):
        h_in = nums[i:i + 3]
        h_out = nums[i + 3:i + 6]
        pos = nums[i + 6:i + 9]
        out.append((tuple(pos[k] + h_in[k] for k in range(3)),
                    tuple(pos[k] + h_out[k] for k in range(3)),
                    tuple(pos)))
    return out


def bez(p0, c0, c1, p1, t):
    u = 1.0 - t
    return tuple(u ** 3 * p0[k] + 3 * u * u * t * c0[k] + 3 * u * t * t * c1[k] + t ** 3 * p1[k]
                 for k in range(3))


def sample_curve(ctrl, step=1.0):
    """Как Curve3D.sample_baked: равномерная выборка по длине дуги."""
    raw = []
    for i in range(len(ctrl) - 1):
        p0, c0, p1, c1 = ctrl[i][2], ctrl[i][1], ctrl[i + 1][2], ctrl[i + 1][0]
        approx = math.dist((p0[0], p0[2]), (p1[0], p1[2])) * 1.1 + 4.0
        n = max(2, int(approx / 0.3))
        for k in range(n):
            raw.append(bez(p0, c0, c1, p1, k / n))
    raw.append(ctrl[-1][2])
    lens = [0.0]
    for i in range(1, len(raw)):
        lens.append(lens[-1] + math.dist((raw[i][0], raw[i][2]), (raw[i - 1][0], raw[i - 1][2])))
    total = lens[-1]
    count = max(2, int(math.ceil(total / step)) + 1)
    out, j = [], 0
    for i in range(count):
        d = min(total, i * total / (count - 1))
        while j < len(lens) - 2 and lens[j + 1] < d:
            j += 1
        span = max(1e-6, lens[j + 1] - lens[j])
        t = max(0.0, min(1.0, (d - lens[j]) / span))
        out.append(tuple(raw[j][k] + (raw[j + 1][k] - raw[j][k]) * t for k in range(3)))
    return out


# ---------------------------------------------------------------- сеть дороги
class Net:
    def __init__(self, samples, rect, cell):
        self.s = samples
        self.rect = rect
        self.cell = cell
        self.cols = int(math.ceil(rect[2] / cell)) + 1
        self.rows = int(math.ceil(rect[3] / cell)) + 1
        self.dists = [0.0]
        for i in range(1, len(samples)):
            self.dists.append(self.dists[-1] + math.dist(
                (samples[i][0], samples[i][2]), (samples[i - 1][0], samples[i - 1][2])))
        self.length = self.dists[-1]
        self._field()
        self._regional()

    @staticmethod
    def nearest(p, a, b, da, db):
        abx, abz = b[0] - a[0], b[1] - a[1]
        l2 = abx * abx + abz * abz
        if l2 < 1e-9:
            return math.hypot(p[0] - a[0], p[1] - a[1]), da
        t = max(0.0, min(1.0, ((p[0] - a[0]) * abx + (p[1] - a[1]) * abz) / l2))
        return (math.hypot(p[0] - (a[0] + abx * t), p[1] - (a[1] + abz * t)),
                da + (db - da) * t)

    def _field(self):
        cols, rows, cell = self.cols, self.rows, self.cell
        ox, oz = self.rect[0], self.rect[1]
        dist = [FAR] * (cols * rows)
        along = [0.0] * (cols * rows)
        site = [-1] * (cols * rows)
        segs = len(self.s) - 1
        for i in range(segs):
            a = (self.s[i][0], self.s[i][2])
            b = (self.s[i + 1][0], self.s[i + 1][2])
            lox = max(0, int(math.floor((min(a[0], b[0]) - ox) / cell)) - 1)
            hix = min(cols - 1, int(math.ceil((max(a[0], b[0]) - ox) / cell)) + 1)
            loz = max(0, int(math.floor((min(a[1], b[1]) - oz) / cell)) - 1)
            hiz = min(rows - 1, int(math.ceil((max(a[1], b[1]) - oz) / cell)) + 1)
            for gz in range(loz, hiz + 1):
                pz = oz + gz * cell
                for gx in range(lox, hix + 1):
                    idx = gz * cols + gx
                    d, al = self.nearest((ox + gx * cell, pz), a, b, self.dists[i], self.dists[i + 1])
                    if d < dist[idx]:
                        dist[idx], along[idx], site[idx] = d, al, i
        offs = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)]
        for rev in (False, True):
            for sz in range(rows):
                gz = rows - 1 - sz if rev else sz
                for sx in range(cols):
                    gx = cols - 1 - sx if rev else sx
                    idx = gz * cols + gx
                    best, bs = dist[idx], site[idx]
                    for dx, dz in offs:
                        nx, nz = gx + dx, gz + dz
                        if nx < 0 or nz < 0 or nx >= cols or nz >= rows:
                            continue
                        ni = nz * cols + nx
                        if site[ni] < 0:
                            continue
                        st = cell if (dx == 0 or dz == 0) else cell * 1.4142135
                        if dist[ni] + st < best:
                            best, bs = dist[ni] + st, site[ni]
                    dist[idx], site[idx] = best, bs
        window, refine_limit = 5, 90.0
        for gz in range(rows):
            pz = oz + gz * cell
            for gx in range(cols):
                idx = gz * cols + gx
                st = site[idx]
                if st < 0 or dist[idx] > refine_limit:
                    continue
                p = (ox + gx * cell, pz)
                bd, ba = dist[idx], along[idx]
                for k in range(max(0, st - window), min(segs, st + window + 1)):
                    a = (self.s[k][0], self.s[k][2])
                    b = (self.s[k + 1][0], self.s[k + 1][2])
                    d, al = self.nearest(p, a, b, self.dists[k], self.dists[k + 1])
                    if d < bd:
                        bd, ba = d, al
                dist[idx], along[idx] = bd, ba
        self.dist, self.along = dist, along

    def _regional(self):
        rcell = max(self.cell * 5.0, 10.0)
        self.rcell = rcell
        self.rcols = int(math.ceil(self.rect[2] / rcell)) + 3
        self.rrows = int(math.ceil(self.rect[3] / rcell)) + 3
        self.rox = self.rect[0] - self.cell
        self.roz = self.rect[1] - self.cell
        reg = [0.0] * (self.rcols * self.rrows)
        for rz in range(self.rrows):
            for rx in range(self.rcols):
                x = self.rox + rx * rcell
                z = self.roz + rz * rcell
                reg[rz * self.rcols + rx] = self.height_at_along(self.along_at(x, z))
        for _ in range(40):
            reg = self._blur(reg, self.rcols, self.rrows)
        self.regional = reg

    @staticmethod
    def _blur(values, width, height):
        out = list(values)
        tmp = list(values)
        for z in range(height):
            row = z * width
            for x in range(width):
                left = tmp[row + max(0, x - 1)]
                right = tmp[row + min(width - 1, x + 1)]
                out[row + x] = left * 0.25 + tmp[row + x] * 0.5 + right * 0.25
        tmp = list(out)
        for z in range(height):
            up = max(0, z - 1) * width
            mid = z * width
            down = min(height - 1, z + 1) * width
            for x in range(width):
                out[mid + x] = tmp[up + x] * 0.25 + tmp[mid + x] * 0.5 + tmp[down + x] * 0.25
        return out

    @staticmethod
    def _bilinear(field, x, z, origin, cell, cols, rows):
        fx = (x - origin[0]) / cell
        fz = (z - origin[1]) / cell
        gx = max(0, min(cols - 2, int(math.floor(fx))))
        gz = max(0, min(rows - 2, int(math.floor(fz))))
        tx = max(0.0, min(1.0, fx - gx))
        tz = max(0.0, min(1.0, fz - gz))
        i = gz * cols + gx
        top = field[i] * (1 - tx) + field[i + 1] * tx
        bottom = field[i + cols] * (1 - tx) + field[i + cols + 1] * tx
        return top * (1 - tz) + bottom * tz

    def distance_to_road(self, x, z):
        return self._bilinear(self.dist, x, z, self.rect[:2], self.cell, self.cols, self.rows)

    def along_at(self, x, z):
        # Если четыре угла ячейки «голосуют» за сильно разные километражи
        # (второй виток шпильки/лестницы рядом), билинейное усреднение
        # изобретает несуществующий километраж посередине — и высота дороги
        # в этой точке проваливается. Тогда берём километраж угла, ближайшего
        # к дороге. (Зеркало: road_network.gd -> along_road.)
        fx = (x - self.rect[0]) / self.cell
        fz = (z - self.rect[1]) / self.cell
        gx = max(0, min(self.cols - 2, int(math.floor(fx))))
        gz = max(0, min(self.rows - 2, int(math.floor(fz))))
        i = gz * self.cols + gx
        corners = [i, i + 1, i + self.cols, i + self.cols + 1]
        along = [self.along[c] for c in corners]
        if max(along) - min(along) > 30.0:
            best = min(corners, key=lambda c: self.dist[c])
            return self.along[best]
        return self._bilinear(self.along, x, z, self.rect[:2], self.cell,
                              self.cols, self.rows)

    def regional_height(self, x, z):
        return self._bilinear(self.regional, x, z, (self.rox, self.roz), self.rcell,
                              self.rcols, self.rrows)

    def height_at_along(self, d):
        f = max(0.0, min(self.length, d)) * len(self.s) / self.length
        i = max(0, min(len(self.s) - 2, int(math.floor(f))))
        return self.s[i][1] + (self.s[i + 1][1] - self.s[i][1]) * (f - i)

    def point_at(self, d):
        f = max(0.0, min(self.length, d)) * len(self.s) / self.length
        i = max(0, min(len(self.s) - 2, int(math.floor(f))))
        t = f - i
        return tuple(self.s[i][k] + (self.s[i + 1][k] - self.s[i][k]) * t for k in range(3))

    def direction_at(self, d):
        a = self.point_at(max(0.0, d - 0.5))
        b = self.point_at(min(self.length, d + 0.5))
        vx, vz = b[0] - a[0], b[2] - a[2]
        n = math.hypot(vx, vz) or 1.0
        return (vx / n, 0.0, vz / n)


# ---------------------------------------------------------------- высота
def smoothstep(a, b, x):
    if b <= a:
        return 0.0 if x < a else 1.0
    u = max(0.0, min(1.0, (x - a) / (b - a)))
    return u * u * (3 - 2 * u)


def hills(x, z):
    """Заглушка FastNoiseLite из редактора: те же крупные формы."""
    v = 16.0 * (0.55 * math.sin(x * 0.0042 + 0.7) * math.cos(z * 0.0039)
                + 0.45 * math.sin((x + z) * 0.0026 + 1.9))
    v += 12.0 * ((1.0 - abs(math.sin(x * 0.0019 + 0.4) * math.cos(z * 0.0017))) - 0.5) * 2.0
    v += 0.3 * math.sin(x * 0.21) * math.cos(z * 0.19)
    return v


def bumps(along, cfg):
    if cfg["bump_amp"] <= 0.0 and cfg["bump_rough"] <= 0.0:
        return 0.0
    wave = math.sin(along * math.tau / max(cfg["bump_wl"], 0.5))
    rough = 0.6 * math.sin(along * 5.0 * 0.9) + 0.4 * math.sin(along * 5.0 * 1.7)
    cross = 1.0 - cfg["bump_cross"] * 0.5 * (rough * 0.5 + 0.5)
    return (cfg["bump_amp"] * wave + cfg["bump_rough"] * rough) * cross


def height(net, cfg, x, z):
    d = net.distance_to_road(x, z)
    along = net.along_at(x, z)
    road_y = net.height_at_along(along)
    fade = smoothstep(cfg["fade_start"], cfg["fade_start"] + cfg["fade_len"], d)
    base = net.regional_height(x, z) + hills(x, z) * fade
    max_slope = math.tan(math.radians(max(6.0, cfg["emb_slope"])))
    blend = max(cfg["emb_min"], min(cfg["emb_max"], abs(road_y - base) / max(max_slope, 0.05)))
    t = smoothstep(cfg["corridor"], cfg["corridor"] + blend, d)
    h = base + (road_y - base) * (1.0 - t)
    near = 1.0 - t
    if near > 0.001:
        lateral = max(0.0, min(1.0, d / cfg["corridor"]))
        h -= cfg["camber"] * lateral * lateral * near
        h += bumps(along, cfg) * near
    return h


def ditch(d, cfg):
    if cfg["ditch"] <= 0.0:
        return 0.0
    return cfg["ditch"] * (1.0 - smoothstep(cfg["corridor"] + 0.5, cfg["corridor"] + 4.0, d))


class Stage:
    """Сетка земли + сэмплеры, как в rally_stage.gd."""

    def __init__(self, cfg=None, samples=None, curve_path=None):
        self.cfg = cfg or read_track()
        ctrl = load_curve(curve_path or CURVE)
        self.samples = samples or sample_curve(ctrl, 1.0)
        xs = [p[0] for p in self.samples]
        zs = [p[2] for p in self.samples]
        m = self.cfg["margin"]
        self.rect = (min(xs) - m, min(zs) - m,
                     max(xs) - min(xs) + 2.0 * m, max(zs) - min(zs) + 2.0 * m)
        self.net = Net(self.samples, self.rect, self.cfg["cell"])
        self._build_grid()

    def _build_grid(self):
        cfg, net = self.cfg, self.net
        cols, rows, cell = net.cols, net.rows, net.cell
        rect = self.rect
        grid = [0.0] * (cols * rows)
        dist = [0.0] * (cols * rows)
        for gz in range(rows):
            z = rect[1] + gz * cell
            for gx in range(cols):
                x = rect[0] + gx * cell
                i = gz * cols + gx
                dist[i] = net.distance_to_road(x, z)
                grid[i] = height(net, cfg, x, z) - ditch(dist[i], cfg)
        # лимит склонов — как _limit_terrain_slopes()
        max_delta = cell * math.tan(math.radians(cfg["max_slope"]))
        anchored = [False] * (cols * rows)
        dirty = []
        for gz in range(rows):
            for gx in range(cols):
                i = gz * cols + gx
                if dist[i] < cfg["corridor"] + 0.5 or gz in (0, rows - 1) or gx in (0, cols - 1):
                    anchored[i] = True
                    continue
                h = grid[i]
                if (abs(h - grid[i + 1]) > max_delta or abs(h - grid[i - 1]) > max_delta
                        or abs(h - grid[i + cols]) > max_delta or abs(h - grid[i - cols]) > max_delta):
                    dirty.append(i)
        marks = [0] * (cols * rows)
        for i in dirty:
            marks[i] = 1
        passes = 0
        while dirty and passes < 80:
            passes += 1
            nxt = []
            for i in dirty:
                marks[i] = 0
                gx, gz = i % cols, i // cols
                if anchored[i]:
                    continue
                for dz in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        if dx == 0 and dz == 0:
                            continue
                        nx, nz = gx + dx, gz + dz
                        if nx < 0 or nz < 0 or nx >= cols or nz >= rows:
                            continue
                        n = nz * cols + nx
                        delta = grid[i] - grid[n]
                        allowed = max_delta * (1.4142135 if (dx and dz) else 1.0)
                        if abs(delta) <= allowed:
                            continue
                        excess = (abs(delta) - allowed) * 0.5
                        sign = 1.0 if delta > 0.0 else -1.0
                        grid[i] -= excess * sign
                        if not anchored[n]:
                            grid[n] += excess * sign
                        if marks[n] == 0:
                            marks[n] = 1
                            nxt.append(n)
                        if marks[i] == 0:
                            marks[i] = 1
                            nxt.append(i)
            dirty = nxt
        self.grid = grid
        self.dist = dist

    def ground(self, x, z):
        """Высота нарисованного меша (по треугольнику), как ground_height()."""
        cols, rows, cell = self.net.cols, self.net.rows, self.net.cell
        rect = self.rect
        fx = (x - rect[0]) / cell
        fz = (z - rect[1]) / cell
        gx = max(0, min(cols - 2, int(math.floor(fx))))
        gz = max(0, min(rows - 2, int(math.floor(fz))))
        u = max(0.0, min(1.0, fx - gx))
        v = max(0.0, min(1.0, fz - gz))
        i = gz * cols + gx
        h00, h10 = self.grid[i], self.grid[i + 1]
        h01, h11 = self.grid[i + cols], self.grid[i + cols + 1]
        if u + v <= 1.0:
            return h00 + u * (h10 - h00) + v * (h01 - h00)
        return h11 * (u + v - 1.0) + h10 * (1.0 - v) + h01 * (1.0 - u)

    def normal(self, x, z, eps=1.4):
        left, right = self.ground(x - eps, z), self.ground(x + eps, z)
        back, front = self.ground(x, z - eps), self.ground(x, z + eps)
        vx, vy, vz = left - right, 2.0 * eps, back - front
        n = math.sqrt(vx * vx + vy * vy + vz * vz) or 1.0
        return (vx / n, vy / n, vz / n)
