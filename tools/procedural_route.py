"""Прототип генератора процедурной трассы (тот же алгоритм, что в
scripts/track_generator.gd — здесь он проверяется численно).

Принцип «не халтурно и не на полный рандом»:
  * дорога собирается из раллийных ПРИЁМОВ (быстрая дуга, связка, шпилька
    с полками, шикан-шифт, гребень-трамплин, эссе), а не из случайных точек;
  * каждый приём перед добавлением проверяется на самозазор — не влез,
    значит параметры переразыгрываются (до 6 раз), потом переход в «побег»;
  * уклон профиля ограничен, высоты сглаживаются, у шпилек ровные полки,
    трамплины — с настоящим сбросом за гребнем;
  * трасса не убегает за горизонт (мягкая граница карты с доворотом к центру);
  * итог ПРОВЕРЯЕТСЯ (зазор/уклон/радиус) и при провале пересобирается
    с сидом+1 — максимум 10 попыток.

Запуск:  python3 tools/procedural_route.py [seed] [min_len] [max_len]
"""
import math
import random
import sys

sys.path.insert(0, "/home/user/rally/tools")
import route_kit as kit

STEP = 2.5              # шаг сэмплов приёмов (м)
HASH_STRIDE = 2         # каждый второй сэмпл кладём в хэш (шаг ~5 м)
CHECK_STRIDE = 2        # каждый второй сэмпл кандидата проверяем (шаг ~5 м)
HASH_CELL = 48.0        # ячейка пространственного хэша (м)
BRANCH_WINDOW = 90.0    # «своя» ветка: пары ближе этого километража не считаем
VAL_MIN_GAP = 24.0      # абсолютный предел «витки не слипаются» (м)


class Gen:
    def __init__(self, seed, length_min, length_max, min_radius=15.0, min_gap=32.0):
        self.rng = random.Random(seed)
        self.seed = seed
        self.length_min = length_min
        self.length_max = length_max
        self.min_radius = min_radius
        self.min_gap = min_gap
        self.target = self.rng.uniform(length_min, length_max)
        self.pts = [(0.0, 0.0, 0.0)]   # (x, z, h)
        self.acc = [0.0]               # XZ-путь
        self.heading = self.rng.uniform(0.0, math.tau)
        self.hash = {}                 # (ix, iz) -> [индексы сэмплов]
        self._bucket_log = []          # какие ячейки хэша тронул каждый приём
        self.total = 0.0
        self.soft_radius = 800.0 + self.target * 0.10
        self.blocked = 0

    # ------------------------------------------------------------ хэш
    def _hash_add(self, idx):
        if idx % HASH_STRIDE != 0:
            return
        x, z = self.pts[idx][0], self.pts[idx][1]
        key = (int(math.floor(x / HASH_CELL)), int(math.floor(z / HASH_CELL)))
        bucket = self.hash.get(key)
        if bucket is None:
            bucket = []
            self.hash[key] = bucket
        bucket.append(idx)
        self._bucket_log.append(key)

    def _nearest_blocker(self, cand, start_along):
        """Ближайшая существующая точка к кандидату (вне «своей» ветки).
        Проверяем каждый CHECK_STRIDE-й сэмпл: шаг ~5 м при зазорах ~30 м
        более чем достаточно, а счёт идёт на секунды."""
        best = (1e9, None, None)
        for k in range(0, len(cand), CHECK_STRIDE):
            x, z = cand[k]
            along_cand = start_along + float(k) * STEP
            ix = int(math.floor(x / HASH_CELL))
            iz = int(math.floor(z / HASH_CELL))
            for dx in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    for idx in self.hash.get((ix + dx, iz + dz), ()):
                        if abs(self.acc[idx] - along_cand) < BRANCH_WINDOW:
                            continue
                        d = math.hypot(self.pts[idx][0] - x, self.pts[idx][1] - z)
                        if d < best[0]:
                            best = (d, idx, (x, z))
        return best  # (дистанция, индекс или None, точка кандидата)

    def _clearance_ok(self, cand, start_along):
        return self._nearest_blocker(cand, start_along)[0] >= self.min_gap

    # ------------------------------------------------------------ приёмы
    def _free_radius(self, x, z):
        """Расстояние от точки до ближайшей «чужой» дороги (в радиусе 2 ячеек)."""
        best = 400.0
        ix = int(math.floor(x / HASH_CELL))
        iz = int(math.floor(z / HASH_CELL))
        for dx in (-2, -1, 0, 1, 2):
            for dz in (-2, -1, 0, 1, 2):
                for idx in self.hash.get((ix + dx, iz + dz), ()):
                    if abs(self.acc[idx] - self.total) < BRANCH_WINDOW:
                        continue
                    d = math.hypot(self.pts[idx][0] - x, self.pts[idx][1] - z)
                    if d < best:
                        best = d
        return best

    def _roomier_direction(self):
        """Куда впереди больше свободного места: +1 (влево) или -1 (вправо)."""
        x, z = self.pts[-1][0], self.pts[-1][1]
        best_sign = 1
        best_score = -1e9
        for sign in (-1, 1):
            h = self.heading + sign * math.radians(50.0)
            px = x + math.cos(h) * 130.0
            pz = z + math.sin(h) * 130.0
            free = min(self._free_radius(px, pz), 160.0)
            center = 2200.0 - min(math.hypot(px, pz), 2200.0)   # ближе к центру — лучше
            score = free + center * 0.03
            if score > best_score:
                best_score = score
                best_sign = sign
        return best_sign

    def _feature(self, kind, grade):
        """(segments, length): ("s", длина, climb) / ("a", R, угол, climb, dir)."""
        rng = self.rng
        near_edge = math.hypot(self.pts[-1][0], self.pts[-1][1]) > self.soft_radius

        def pick_direction():
            if near_edge:
                return self._roomier_direction()
            # тесно между своими же витками — тоже ищем простор
            x, z = self.pts[-1][0], self.pts[-1][1]
            if self._free_radius(x, z) < 70.0:
                return self._roomier_direction()
            return rng.choice((-1, 1))

        if kind == "straight":
            length = rng.uniform(90.0, 240.0)
            if near_edge:
                length *= 0.5
            return [("s", length, length * grade)]
        if kind == "arc_flow":
            radius = rng.uniform(55.0, 170.0)
            angle = rng.uniform(18.0, 75.0)
            direction = pick_direction()
            length = radius * math.radians(angle)
            return [("a", radius, angle, length * grade, direction)]
        if kind == "arc_tight":
            radius = rng.uniform(max(26.0, self.min_radius * 1.7), 55.0)
            angle = rng.uniform(40.0, 130.0)
            direction = pick_direction()
            length = radius * math.radians(angle)
            return [("a", radius, angle, length * grade, direction)]
        if kind == "hairpin":
            radius = rng.uniform(self.min_radius, self.min_radius + 4.0)
            angle = rng.uniform(150.0, 176.0)
            direction = pick_direction()
            shelf_in = rng.uniform(38.0, 55.0)
            shelf_out = rng.uniform(38.0, 55.0)
            arc_len = radius * math.radians(angle)
            return [
                ("s", shelf_in, shelf_in * grade * 0.3),
                ("a", radius, angle, arc_len * grade * 0.15, direction),
                ("s", shelf_out, shelf_out * grade * 0.3),
            ]
        if kind == "chicane":
            segs = []
            direction = pick_direction()
            for _i in range(3):
                radius = rng.uniform(22.0, 32.0)
                angle = rng.uniform(32.0, 46.0)
                segs.append(("s", rng.uniform(8.0, 16.0), 0.0))
                arc_len = radius * math.radians(angle)
                segs.append(("a", radius, angle, arc_len * grade * 0.6, direction))
                direction = -direction
            return segs
        if kind == "crest":
            run_in = rng.uniform(60.0, 110.0)
            face = rng.uniform(22.0, 32.0)
            run_out = rng.uniform(55.0, 85.0)
            return [
                ("s", run_in, run_in * max(grade, 0.025)),
                ("s", face, -rng.uniform(2.2, 3.4)),     # сброс за гребнем
                ("s", run_out, 0.0),
            ]
        if kind == "esses":
            segs = []
            direction = pick_direction()
            for _i in range(rng.randint(2, 3)):
                radius = rng.uniform(60.0, 120.0)
                angle = rng.uniform(25.0, 55.0)
                arc_len = radius * math.radians(angle)
                segs.append(("a", radius, angle, arc_len * grade, direction))
                direction = -direction
            return segs
        raise ValueError(kind)

    # ------------------------------------------------------------ геометрия
    def _save_state(self):
        return (len(self.pts), self.heading, len(self._bucket_log))

    def _restore_state(self, state):
        """Откат последнего приёма: точки, километраж, хэш, курс."""
        mark, heading, log_mark = state
        for key in self._bucket_log[log_mark:]:
            bucket = self.hash.get(key)
            if bucket:
                bucket[:] = [i for i in bucket if i < mark]
        del self._bucket_log[log_mark:]
        del self.pts[mark:]
        del self.acc[mark:]
        self.heading = heading
        self.total = self.acc[-1] if self.acc else 0.0

    def _walk(self, segs):
        """Прогонка сегментов от текущего конца: [(x, z)] сэмплы."""
        x, z = self.pts[-1][0], self.pts[-1][1]
        h = self.heading
        out = []
        for seg in segs:
            if seg[0] == "s":
                _, length, _climb = seg
                n = max(2, int(length / STEP))
                d = length / n
                for _i in range(n):
                    x += math.cos(h) * d
                    z += math.sin(h) * d
                    out.append((x, z))
            else:
                _, radius, angle, _climb, direction = seg
                ang = math.radians(angle)
                n = max(3, int(radius * ang / STEP))
                d_ang = ang / n
                d = radius * d_ang
                for _i in range(n):
                    h += direction * d_ang
                    x += math.cos(h) * d
                    z += math.sin(h) * d
                    out.append((x, z))
        return out

    def _emit(self, segs):
        """Добавляет сегменты к трассе вместе с высотами."""
        for seg in segs:
            if seg[0] == "s":
                _, length, climb = seg
                n = max(2, int(length / STEP))
                d = length / n
                for i in range(n):
                    self._advance(math.cos(self.heading) * d,
                                  math.sin(self.heading) * d, climb / n)
            else:
                _, radius, angle, climb, direction = seg
                ang = math.radians(angle)
                n = max(3, int(radius * ang / STEP))
                d_ang = ang / n
                d = radius * d_ang
                for i in range(n):
                    self.heading += direction * d_ang
                    self._advance(math.cos(self.heading) * d,
                                  math.sin(self.heading) * d, climb / n)

    def _advance(self, dx, dz, dh):
        x, z, h = self.pts[-1]
        self.pts.append((x + dx, z + dz, h + dh))
        self.acc.append(self.acc[-1] + math.hypot(dx, dz))
        self.total = self.acc[-1]
        self._hash_add(len(self.pts) - 1)

    def _escape(self, grade):
        """Приём не влез: ищем поворот в сторону, где свободнее.

        Последний шанс — чуть ослабленный зазор (28 м), дальше только откат.
        Непроверенной геометрии не добавляем никогда.
        """
        away = self._roomier_direction()
        for relax in (self.min_gap, 28.0):
            for attempt in range(10):
                angle = min(50.0 + attempt * 14.0, 168.0)
                radius = self.rng.uniform(22.0, 60.0)
                for direction in (away, -away):
                    seg = ("a", radius, angle, radius * math.radians(angle) * grade * 0.4, direction)
                    old_gap = self.min_gap
                    self.min_gap = relax
                    ok = self._clearance_ok(self._walk([seg]), self.total)
                    self.min_gap = old_gap
                    if ok:
                        self._emit([seg])
                        return True
        return False

    def _try_feature(self, kind, grade):
        for _attempt in range(6):
            segs = self._feature(kind, grade)
            if self._clearance_ok(self._walk(segs), self.total):
                self._emit(segs)
                return True
        # не влезло: разворачиваемся туда, где свободнее
        self.blocked += 1
        return self._escape(grade)

    # ------------------------------------------------------------ сборка
    def build(self):
        rng = self.rng
        self._emit([("s", 130.0, 0.0)])           # старт — ровная прямая
        grade = rng.uniform(-0.02, 0.03)
        kinds = ("straight", "arc_flow", "arc_flow", "arc_tight",
                 "hairpin", "chicane", "crest", "esses")
        guard = 0
        stuck = 0
        backs = 0
        history = []      # состояния до каждого принятого приёма
        while self.total < self.target - 300.0 and guard < 4000:
            guard += 1
            kind = rng.choice(kinds)
            state = self._save_state()
            if self._try_feature(kind, grade):
                history.append(state)
                stuck = 0
            else:
                stuck += 1
                if stuck >= 2 and history:
                    # замуровало: откатываем пару приёмов и пробуем иначе
                    for _ in range(2):
                        if history:
                            self._restore_state(history.pop())
                    stuck = 0
                    backs += 1
                    if backs > 40:
                        break
                    continue
                if stuck >= 3:
                    break
            grade = max(-0.065, min(0.065, grade + rng.uniform(-0.028, 0.028)))
            # возврат к нулю: не даём профилю уехать в стратосферу
            h = self.pts[-1][2]
            if h > 70.0:
                grade = min(grade, -0.012)
            elif h < -70.0:
                grade = max(grade, 0.012)
        # финиш: связка и ровные прямые (тоже с проверкой зазора)
        self._try_feature("arc_flow", grade * 0.5)
        for _attempt in range(6):
            tail = [("s", 120.0, 0.0), ("s", 150.0, 0.0)]
            if self._clearance_ok(self._walk(tail), self.total):
                self._emit(tail)
                break
            if not self._try_feature("arc_tight", 0.0):
                break
        return self.pts, self.total


def finalize(raw_pts):
    """Сглаживание + лимит уклона + прореживание (как авторским трассам)."""
    return kit.resample(kit.limit_grade(kit.smooth_heights(raw_pts, 16.0), 8.0), 1.0)


def validate(samples, min_radius):
    acc = kit.xz_distances(samples)
    # зазор — по пространственному хэшу (O(n), как при генерации)
    buckets = {}
    stride = 4          # финальная проверка: каждые 4 м
    for i in range(0, len(samples), stride):
        p = samples[i]
        key = (int(math.floor(p[0] / HASH_CELL)), int(math.floor(p[1] / HASH_CELL)))
        buckets.setdefault(key, []).append(i)
    worst = 1e9
    for i in range(0, len(samples), stride):
        p = samples[i]
        ix = int(math.floor(p[0] / HASH_CELL))
        iz = int(math.floor(p[1] / HASH_CELL))
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for j in buckets.get((ix + dx, iz + dz), ()):
                    if abs(acc[i] - acc[j]) < BRANCH_WINDOW:
                        continue
                    d = math.hypot(samples[i][0] - samples[j][0], samples[i][1] - samples[j][1])
                    if d < worst:
                        worst = d
    grade = 0.0
    for i in range(1, len(samples)):
        dxz = math.dist(samples[i - 1][:2], samples[i][:2])
        if dxz > 0.01:
            grade = max(grade, abs(samples[i][2] - samples[i - 1][2]) / dxz)
    min_r = 1e9
    for i in range(8, len(samples) - 8, 2):
        x0, z0 = samples[i - 8][0], samples[i - 8][1]
        x1, z1 = samples[i][0], samples[i][1]
        x2, z2 = samples[i + 8][0], samples[i + 8][1]
        a = math.hypot(x1 - x0, z1 - z0)
        b = math.hypot(x2 - x1, z2 - z1)
        c = math.hypot(x2 - x0, z2 - z0)
        if a < 1e-3 or b < 1e-3:
            continue
        area2 = abs((x1 - x0) * (z2 - z0) - (x2 - x0) * (z1 - z0))
        if area2 < 1e-6:
            continue
        min_r = min(min_r, a * b * c / (2.0 * area2))
    return {"gap": worst, "grade": grade, "radius": min_r}


def generate(seed, length_min=8000.0, length_max=12000.0, min_radius=15.0,
             min_gap=32.0, verbose=False):
    stats = None
    dense = None
    for attempt in range(10):
        gen = Gen(seed + attempt, length_min, length_max, min_radius, min_gap)
        raw, total = gen.build()
        dense = finalize(raw)
        stats = validate(dense, min_radius)
        length = kit.xz_distances(dense)[-1]
        if verbose:
            print("  попытка %d: длина %.0f, зазор %.1f, уклон %.1f%%, Rmin %.1f, блокировок %d" % (
                attempt, length, stats["gap"], stats["grade"] * 100.0, stats["radius"], gen.blocked))
        if length >= length_min * 0.85 and stats["gap"] >= VAL_MIN_GAP \
                and stats["grade"] <= 0.145 and stats["radius"] >= min_radius * 0.8:
            return dense, stats
    return dense, stats


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    length_min = float(sys.argv[2]) if len(sys.argv) > 2 else 8000.0
    length_max = float(sys.argv[3]) if len(sys.argv) > 3 else 12000.0
    print("=== генерация seed=%d [%.0f..%.0f] ===" % (seed, length_min, length_max))
    dense, stats = generate(seed, length_min, length_max, verbose=True)
    print("итог: длина %.0f м, зазор %.1f м, уклон %.1f%%, Rmin %.1f м" % (
        kit.xz_distances(dense)[-1], stats["gap"], stats["grade"] * 100.0, stats["radius"]))
    kit.ascii_map(dense, 100, 32)
    ys = [p[2] for p in dense]
    print("высоты: %.1f .. %.1f м" % (min(ys), max(ys)))


if __name__ == "__main__":
    main()
