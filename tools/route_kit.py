"""Общий механизм авторинга осевых линий спецучастков.

Используется tools/author_route.py (ночной лес) и tools/make_routes.py
(перевал, северная дуга). Почему этот модуль вообще нужен:

СТАРЫЙ генератор писал кривую так: брал контрольные точки каждые 65 м и
давал им катмулл-ромовские ручки, у которых наклон по высоте = средний
наклон хорды «сосед → сосед». На ровных полках и у гребней такая кривая
ОБЯЗАТЕЛЬНО отклоняется от задуманного профиля: за полкой, идущей после
подъёма, касательная всё ещё «вверх», полка вспухает бугром, а перед
следующим подъёмом проваливается — это и были «впадины» до 3.8 м (а в
запечённой старой версии — до +20 м на старте).

Рецепт исправления:
  1) контрольные точки ставятся не только «каждые 65 м», но и там, где
     меняется уклон или направление (полки, гребни, трамплины, шпильки);
  2) наклон ручек по высоте считается формулой Фрича—Карлсона
     (shape-preserving / monotone cubic): интерполяция не может создать
     бугров и впадин, которых нет в задуманном профиле;
  3) после записи кривая ПРОВЕРЯЕТСЯ: кривая сэмплируется обратно и
     сравнивается с задуманным профилем (высота, план, уклон, «ямы»).
"""
import math

STEP = 0.25                 # шаг компоновки (м)
HEIGHT_WINDOW = 16.0        # окно сглаживания высот (м)
MAX_GRADE_DEG = 8.0        # предельный уклон профиля


# ---------------------------------------------------------------- компоновка
def compose(segs, step=STEP):
    """SEGS -> плотный список точек (x, z, высота) и длина.

    kind: "s" straight (length, climb)
          "a" arc    (radius, angle_deg, climb, direction), dir +1 = right
    """
    x = z = h = y = dist = 0.0
    pts = [(x, z, y)]
    for seg in segs:
        if seg[0] == "s":
            _, length, climb = seg
            n = max(2, int(length / step))
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
            n = max(3, int(radius * ang / step))
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
    """треугольное скользящее среднее высот, план не трогаем.

    Радиус в ШАГАХ вычисляется из фактического расстояния между точками
    (авторские трассы идут шагом 0.25 м, генератор — 2.5 м): окно всегда
    означает заявленные метры, а не «сколько-то индексов».
    """
    n = len(pts)
    if n < 3:
        return list(pts)
    total = xz_distances(pts)[-1]
    spacing = max(1e-6, total / (n - 1))
    radius = max(1, int(round(window_m / spacing)))
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
    """уклон не круче max_deg в обе стороны"""
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


def xz_distances(pts):
    out = [0.0]
    for i in range(1, len(pts)):
        out.append(out[-1] + math.dist(pts[i - 1][:2], pts[i][:2]))
    return out


def slope_at(pts, acc, i, half_window=8.0):
    """уклон dh/dxz в точке i по окну ±half_window метров"""
    n = len(pts)
    lo = i
    while lo > 0 and acc[i] - acc[lo] > half_window:
        lo -= 1
    hi = i
    while hi < n - 1 and acc[hi] - acc[i] < half_window:
        hi += 1
    span = acc[hi] - acc[lo]
    if span < 1e-6:
        return 0.0
    return (pts[hi][2] - pts[lo][2]) / span


def select_controls(pts, max_gap=50.0, min_gap=14.0,
                    slope_trigger_deg=1.0, turn_trigger_deg=10.0):
    """Адаптивные контрольные точки.

    Точка ставится, если (а) с прошлой прошло max_gap метров, либо (б) прошло
    хотя бы min_gap метров и заметно изменился уклон (полка/гребень/трамплин)
    или НАКОПИЛСЯ поворот (вход и выход из дуги, шифты). Накопление важно:
    у S-образных шифтов суммарный поворот большой, а разность курсов
    «до и после» почти нулевая — по разности точка бы не ставилась, и сплайн
    срезал шифт целиком.
    """
    acc = xz_distances(pts)
    n = len(pts)
    heads = [0.0]
    for i in range(1, n):
        dx = pts[i][0] - pts[i - 1][0]
        dz = pts[i][1] - pts[i - 1][1]
        if dx * dx + dz * dz > 1e-12:
            heads.append(math.atan2(dz, dx))
        else:
            heads.append(heads[-1])
    # накопленный |поворот| от каждой точки вперёд не нужен — считаем на лету
    trig_slope = math.tan(math.radians(slope_trigger_deg))
    ctrl = [pts[0]]
    last_i = 0
    last_slope = slope_at(pts, acc, 0)
    turn_acc = 0.0
    for i in range(1, n):
        turn_acc += abs(math.atan2(math.sin(heads[i] - heads[i - 1]),
                                   math.cos(heads[i] - heads[i - 1])))
        gap = acc[i] - acc[last_i]
        if gap < min_gap:
            continue
        slope = slope_at(pts, acc, i)
        if gap >= max_gap or turn_acc >= math.radians(turn_trigger_deg) \
                or abs(slope - last_slope) >= trig_slope:
            ctrl.append(pts[i])
            last_i = i
            last_slope = slope
            turn_acc = 0.0
    if ctrl[-1] != pts[-1]:
        ctrl.append(pts[-1])
    return ctrl


# ------------------------------------------------- высотные касательные (Y)
def monotone_slopes(ctrl):
    """Наклоны dh/dxz в контрольных точках по Фричу—Карлсону.

    Гарантия: кубическая интерполяция Эрмита с такими наклонами НЕ создаёт
    между контрольными точками новых локальных экстремумов. Ровная полка
    остаётся ровной, гребень — на месте, впадин кривая не «придумывает».
    """
    n = len(ctrl)
    acc = xz_distances(ctrl)
    d = []
    for i in range(n - 1):
        span = max(1e-6, acc[i + 1] - acc[i])
        d.append((ctrl[i + 1][2] - ctrl[i][2]) / span)
    m = [0.0] * n
    for i in range(n):
        if i == 0:
            m[i] = d[0]
        elif i == n - 1:
            m[i] = d[-1]
        elif d[i - 1] * d[i] <= 0.0:
            m[i] = 0.0                     # смена знака уклона: экстремум
        else:
            h0 = acc[i] - acc[i - 1]
            h1 = acc[i + 1] - acc[i]
            w1 = 2.0 * h1 + h0
            w2 = h1 + 2.0 * h0
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
    # страховочный клэмп Фрича—Карлсона: на каждом отрезке наклоны концов
    # не дают кривой выйти за пределы монотонности.
    for i in range(n - 1):
        if d[i] > 0.0:
            m[i] = min(max(m[i], 0.0), 3.0 * d[i])
            m[i + 1] = min(max(m[i + 1], 0.0), 3.0 * d[i])
        elif d[i] < 0.0:
            m[i] = min(max(m[i], 3.0 * d[i]), 0.0)
            m[i + 1] = min(max(m[i + 1], 3.0 * d[i]), 0.0)
    return m


# ---------------------------------------------------------------- запись
def write_curve(ctrl, path, slopes=None, uid=None):
    """Контрольные точки -> Curve3D (.tres).

    План (XZ): ручки по направлению хорды «сосед → сосед», длина = треть
    расстояния до соседа — как раньше, план от этого не портился.
    Высота (Y): ручки по монотонным наклонам Фрича—Карлсона — раньше тут
    был средний наклон хорды, из-за чего полки вспухали и проваливались.

    ВАЖНО: Godot хранит point_in / point_out ОТНОСИТЕЛЬНО самой точки.
    """
    n = len(ctrl)
    if slopes is None:
        slopes = monotone_slopes(ctrl)
    values = []
    for i in range(n):
        px, pz, py = ctrl[i][0], ctrl[i][1], ctrl[i][2]
        prev = ctrl[max(0, i - 1)]
        nxt = ctrl[min(n - 1, i + 1)]
        tx, tz = nxt[0] - prev[0], nxt[1] - prev[1]
        tl = math.hypot(tx, tz) or 1.0
        hx, hz = tx / tl, tz / tl            # единичное направление в плане
        slope = slopes[i]
        seg_in = math.dist((prev[0], prev[1]), (px, pz)) if i > 0 else 0.0
        seg_out = math.dist((nxt[0], nxt[1]), (px, pz)) if i < n - 1 else 0.0
        hin = seg_in / 3.0
        hout = seg_out / 3.0
        pos = (px, py, pz)                   # Godot: x, y(высота), z
        hin_rel = (-hx * hin, -slope * hin, -hz * hin)
        hout_rel = (hx * hout, slope * hout, hz * hout)
        values.append("%.4f, %.4f, %.4f" % hin_rel)
        values.append("%.4f, %.4f, %.4f" % hout_rel)
        values.append("%.4f, %.4f, %.4f" % pos)
    header = '[gd_resource type="Curve3D" format=3]'
    if uid:
        header = '[gd_resource type="Curve3D" format=3 uid="%s"]' % uid
    text = (
        header + "\n\n"
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


# ---------------------------------------------------------------- проверка
def build_intent(segs, max_grade_deg=MAX_GRADE_DEG, step=1.0):
    """Задуманный профиль: компоновка -> сглаживание -> лимит уклона."""
    raw, length = compose(segs)
    pts = resample(limit_grade(smooth_heights(raw, HEIGHT_WINDOW), max_grade_deg), step)
    return pts, length


def _sample_written(path, step=1.0):
    """Читает записанный .tres и сэмплирует его как движок (stage_model)."""
    import stage_model as model
    ctrl = model.load_curve(path)
    return model.sample_curve(ctrl, step)


def verify(path, intent, max_dev=0.5, max_plan_dev=2.0, max_dip=0.35,
           min_clearance=28.0, verbose=True):
    """Сравнивает записанную кривую с задуманным профилем.

    Возвращает True, если всё в порядке. Проверяются:
      * отклонение высоты от замысла (бугры/впадины интерполяции);
      * отклонение в плане (срезанные углы);
      * «ямы»: локальные минимумы кривой, которых нет в замысле;
      * уклон;
      * самосближение трассы (мин. зазор между витками).
    """
    # сэмплы кривой — в порядке Godot (x, высота, z) -> авторский (x, z, высота)
    samples = [(p[0], p[2], p[1]) for p in _sample_written(path, 1.0)]
    ok = True
    sacc = xz_distances(samples)
    iacc = xz_distances(intent)
    total = min(sacc[-1], iacc[-1])

    def h_at(arr, acc, xz):
        j = 0
        while j < len(acc) - 2 and acc[j + 1] < xz:
            j += 1
        t = (xz - acc[j]) / max(1e-6, acc[j + 1] - acc[j])
        return arr[j][2] + (arr[j + 1][2] - arr[j][2]) * t

    def xy_at(arr, acc, xz):
        j = 0
        while j < len(acc) - 2 and acc[j + 1] < xz:
            j += 1
        t = (xz - acc[j]) / max(1e-6, acc[j + 1] - acc[j])
        return (arr[j][0] + (arr[j + 1][0] - arr[j][0]) * t,
                arr[j][1] + (arr[j + 1][1] - arr[j][1]) * t)

    worst_h = 0.0
    worst_plan = 0.0
    for xz in range(5, int(total) - 5, 5):
        dh = h_at(samples, sacc, float(xz)) - h_at(intent, iacc, float(xz))
        worst_h = max(worst_h, abs(dh))
        sx, sz = xy_at(samples, sacc, float(xz))
        ix, iz = xy_at(intent, iacc, float(xz))
        worst_plan = max(worst_plan, math.hypot(sx - ix, sz - iz))
    if worst_h > max_dev:
        ok = False
    # worst_plan копит вдоль-сдвиг и НЕ гейтится: решающая проверка ниже.

    # --- план, локальная срезка углов: расстояние от каждого пункта
    #     замысла до БЛИЖАЙШЕЙ точки кривой. Сравнение «по километражу»
    #     (выше) копит вдоль-сдвиг от крошечной разницы длин полилинии и
    #     дуг Безье — на длинных трассах он растёт линейно (~0.2 м/км),
    #     хотя углы никто не срезает. Решающая проверка — именно эта.
    cell = 8.0
    buckets = {}
    for i in range(0, len(samples), 2):
        key = (int(samples[i][0] // cell), int(samples[i][1] // cell))
        buckets.setdefault(key, []).append(i)
    worst_near = 0.0
    for i in range(0, len(intent), 4):
        ix, iz = intent[i][0], intent[i][1]
        bx, bz = int(ix // cell), int(iz // cell)
        best = 1e9
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for j in buckets.get((bx + dx, bz + dz), ()):
                    d = math.hypot(samples[j][0] - ix, samples[j][1] - iz)
                    if d < best:
                        best = d
        if best < 1e8:
            worst_near = max(worst_near, best)
    if worst_near > max_plan_dev:
        ok = False

    # --- ямы: локальные минимумы кривой глубже, чем в замысле
    def dip_depth(arr):
        n = len(arr)
        worst = 0.0
        for i in range(30, n - 30, 3):
            lo = arr[max(0, i - 30)][2]
            hi = arr[min(n - 1, i + 30)][2]
            if arr[i][2] < min(lo, hi):
                worst = max(worst, min(lo, hi) - arr[i][2])
        return worst

    dip_s = dip_depth(samples)
    dip_i = dip_depth(intent)
    if dip_s > dip_i + max_dip:
        ok = False

    # --- уклон
    worst_grade = 0.0
    for i in range(1, len(samples)):
        dxz = math.dist(samples[i - 1][:2], samples[i][:2])
        if dxz > 0.01:
            worst_grade = max(worst_grade,
                              abs(samples[i][2] - samples[i - 1][2]) / dxz)

    # --- самосближение
    best, where = 1e9, None
    step_check = 4
    thin = samples[::step_check]
    for a in range(0, len(thin), 2):
        for b in range(a + 30, len(thin)):
            d = math.dist(thin[a][:2], thin[b][:2])
            if d < best:
                best, where = d, (a * step_check, b * step_check)
    if best < min_clearance:
        ok = False

    if verbose:
        print("  длина            %.0f м" % sacc[-1])
        print("  контрольных      (см. выше)")
        print("  Δвысота макс     %.2f м (лимит %.2f)" % (worst_h, max_dev))
        print("  Δплан срезка     %.2f м (лимит %.2f)" % (worst_near, max_plan_dev))
        print("  Δплан накопл.    %.2f м (информационно: сдвиг по км)" % worst_plan)
        print("  ямы              кривая %.2f м / замысел %.2f м (+%.2f)" % (
            dip_s, dip_i, max_dip))
        print("  уклон макс       %.1f%%" % (worst_grade * 100.0))
        print("  самозазор        %.1f м (мин. %.1f)" % (best, min_clearance))
        print("  РЕЗУЛЬТАТ        %s" % ("OK" if ok else "ПРОВАЛ"))
    return ok


def ascii_map(pts, width=110, height=44):
    """Схема трассы в консоли — быстро видно форму и наложения витков."""
    xs = [p[0] for p in pts]
    zs = [p[1] for p in pts]
    ys = [p[2] for p in pts]
    minx, maxx = min(xs), max(xs)
    minz, maxz = min(zs), max(zs)
    span = max(maxx - minx, maxz - minz) * 1.05
    grid = [[" "] * width for _ in range(height)]
    lo, hi = min(ys), max(ys)
    marks = {0: "S", len(pts) - 1: "F"}
    for i, p in enumerate(pts):
        gx = int((p[0] - minx) / span * (width - 1))
        gz = int((maxz - p[1]) / span * (height - 1))   # z вверх = вверх экрана
        t = (p[2] - lo) / max(hi - lo, 1e-6)
        ch = " .:-=+*#%@"[min(9, int(t * 9.99))]
        if i in marks:
            ch = marks[i]
        if 0 <= gz < height and 0 <= gx < width:
            grid[gz][gx] = ch
    lines = ["    " + "".join(row) for row in grid]
    print("\n".join(lines))


def self_gap_report(samples, min_gap=26.0):
    """Где именно трасса подходит к себе ближе min_gap (км обеих веток)."""
    acc = xz_distances(samples)
    bad = []
    n = len(samples)
    for a in range(0, n, 4):
        for b in range(a + 100, n, 4):
            d = math.dist(samples[a][:2], samples[b][:2])
            if d < min_gap:
                bad.append((d, acc[a], acc[b]))
    bad.sort()
    return bad[:12]


def render(pts, path="/tmp/route_preview.png"):
    """Схема трассы сверху (если есть PIL; без неё просто пропускаем)."""
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print("  (PIL нет — схема пропущена)")
        return
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
    d.ellipse([screen[0][0] - 9, screen[0][1] - 9,
               screen[0][0] + 9, screen[0][1] + 9], fill=(60, 220, 255))
    d.ellipse([screen[-1][0] - 9, screen[-1][1] - 9,
               screen[-1][0] + 9, screen[-1][1] + 9], fill=(255, 90, 40))
    img.save(path)
    print("  схема            " + path)
