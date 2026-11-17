"""Карта трассы «вид сверху»: дорога по высоте, река, мосты, старт/финиш.

Нужна, чтобы оценить план этапа без Godot: где дорога идёт вдоль воды, где
пересекает её, как разложены серпантины и не залезают ли ветки друг на друга.

Примеры:
    python3 tools/plot_stage_plan.py
    python3 tools/plot_stage_plan.py data/tracks/stage_england.tres
    python3 tools/plot_stage_plan.py data/tracks/stage_england.tres docs/previews/england_stage_plan.png

Читает ровно те ресурсы, что и игра (`road_curve`, блок реки, список мостов),
поэтому картинка всегда соответствует текущей трассе. При запуске без аргументов
строит планы в `docs/previews/` для всех трасс, у которых задана `road_curve`.

Бэкенды рендеринга (автовыбор, без обязательных внешних зависимостей):
  1. Pillow (`PIL`) — если установлен;
  2. ImageMagick (`convert` / `magick` + MVG и DejaVu Sans);
  3. встроенный чистый Python (zlib/struct + пиксельный шрифт 5×7).
"""
import argparse
import bisect
import math
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TRACKS_DIR = ROOT / 'data' / 'tracks'
PREVIEWS_DIR = ROOT / 'docs' / 'previews'

sys.path.insert(0, str(ROOT / 'tools'))
import stage_model

FONT_DIR = Path('/usr/share/fonts/truetype/dejavu')
SCALE_CANDIDATES_M = (50, 100, 200, 250, 500, 1000, 2000, 5000, 10000, 20000)

_EXT_RE = re.compile(r'^\[ext_resource\s+([^\]]+)\]', re.M)
_SUB_HEADER_RE = re.compile(r'^\[sub_resource\s+([^\]]+)\]\n', re.M)
_RES_HEADER_RE = re.compile(r'^\[resource\]\n', re.M)
_ATTR_PATH_RE = re.compile(r'\bpath="res://([^"]+)"')
_ATTR_ID_RE = re.compile(r'\bid="([^"]+)"')

# Компактный шрифт 5×7 для резервного чисто-питонового PNG-растеризатора.
_FONT_5X7 = {
    ' ': (0, 0, 0, 0, 0, 0, 0),
    '.': (0, 0, 0, 0, 0, 12, 12),
    ',': (0, 0, 0, 0, 12, 4, 8),
    '-': (0, 0, 0, 30, 0, 0, 0),
    '—': (0, 0, 0, 31, 0, 0, 0),
    '/': (1, 2, 2, 4, 8, 8, 16),
    ':': (0, 12, 12, 0, 12, 12, 0),
    '0': (14, 17, 19, 21, 25, 17, 14),
    '1': (4, 12, 4, 4, 4, 4, 14),
    '2': (14, 17, 1, 6, 8, 16, 31),
    '3': (30, 1, 1, 14, 1, 1, 30),
    '4': (2, 6, 10, 18, 31, 2, 2),
    '5': (31, 16, 30, 1, 1, 17, 14),
    '6': (6, 8, 16, 30, 17, 17, 14),
    '7': (31, 1, 2, 4, 8, 8, 8),
    '8': (14, 17, 17, 14, 17, 17, 14),
    '9': (14, 17, 17, 15, 1, 2, 12),
    'А': (14, 17, 17, 31, 17, 17, 17),
    'Б': (31, 16, 16, 30, 17, 17, 30),
    'В': (30, 17, 17, 30, 17, 17, 30),
    'Г': (31, 16, 16, 16, 16, 16, 16),
    'Д': (6, 10, 10, 10, 10, 31, 17),
    'Е': (31, 16, 16, 30, 16, 16, 31),
    'Ж': (21, 21, 14, 4, 14, 21, 21),
    'З': (14, 17, 1, 6, 1, 17, 14),
    'И': (17, 17, 19, 21, 25, 17, 17),
    'Й': (14, 0, 17, 19, 21, 25, 17),
    'К': (17, 18, 20, 24, 20, 18, 17),
    'Л': (7, 9, 9, 9, 9, 9, 17),
    'М': (17, 27, 21, 21, 17, 17, 17),
    'Н': (17, 17, 17, 31, 17, 17, 17),
    'О': (14, 17, 17, 17, 17, 17, 14),
    'П': (31, 17, 17, 17, 17, 17, 17),
    'Р': (30, 17, 17, 30, 16, 16, 16),
    'С': (14, 17, 16, 16, 16, 17, 14),
    'Т': (31, 4, 4, 4, 4, 4, 4),
    'У': (17, 17, 17, 15, 1, 17, 14),
    'Ф': (4, 14, 21, 21, 14, 4, 4),
    'Х': (17, 17, 10, 4, 10, 17, 17),
    'Ц': (17, 17, 17, 17, 17, 31, 1),
    'Ч': (17, 17, 17, 15, 1, 1, 1),
    'Ш': (21, 21, 21, 21, 21, 21, 31),
    'Щ': (21, 21, 21, 21, 21, 31, 1),
    'Ы': (17, 17, 29, 19, 19, 19, 29),
    'Ь': (16, 16, 30, 17, 17, 17, 30),
    'Э': (14, 17, 1, 15, 1, 17, 14),
    'Ю': (18, 21, 21, 29, 21, 21, 18),
    'Я': (15, 17, 17, 15, 5, 9, 17),
}


def _pil_available():
    try:
        from PIL import Image  # noqa: F401
        return True
    except ImportError:
        return False


def _magick_binary():
    for candidate in ('convert', 'magick'):
        found = shutil.which(candidate)
        if found:
            return found
    return None


def _font_path(bold=False):
    name = 'DejaVuSans-Bold.ttf' if bold else 'DejaVuSans.ttf'
    path = FONT_DIR / name
    return path if path.exists() else None


class _PilCanvas:
    def __init__(self, width, height, bg):
        from PIL import Image, ImageDraw, ImageFont
        self._img = Image.new('RGB', (width, height), bg)
        self._draw = ImageDraw.Draw(self._img)
        self._fonts = {}
        self._image_font = ImageFont

    def _font(self, size, bold):
        key = (size, bold)
        if key not in self._fonts:
            path = _font_path(bold=bold)
            try:
                self._fonts[key] = self._image_font.truetype(str(path), size) if path else self._image_font.load_default()
            except OSError:
                self._fonts[key] = self._image_font.load_default()
        return self._fonts[key]

    def rect(self, x0, y0, x1, y1, color):
        self._draw.rectangle([x0, y0, x1, y1], fill=color)

    def line(self, x0, y0, x1, y1, color, width=1):
        self._draw.line([(x0, y0), (x1, y1)], fill=color, width=max(1, int(round(width))))

    def polyline(self, points, color, width=1):
        if len(points) >= 2:
            self._draw.line(points, fill=color, width=max(1, int(round(width))), joint='curve')

    def circle(self, cx, cy, radius, fill_color, outline_color=None, outline_width=1):
        box = [cx - radius, cy - radius, cx + radius, cy + radius]
        self._draw.ellipse(box, fill=fill_color, outline=outline_color, width=outline_width)

    def text_width(self, text, size, bold=False):
        bbox = self._draw.textbbox((0, 0), text, font=self._font(size, bold))
        return bbox[2] - bbox[0]

    def text(self, x, y, text, color, size=13, bold=False):
        self._draw.text((x, y), text, font=self._font(size, bold), fill=color)

    def save(self, out_path):
        self._img.save(out_path)


class _MvgCanvas:
    """Рендер через ImageMagick MVG: сглаженные линии и реальный DejaVu Sans."""

    def __init__(self, width, height, bg, binary):
        self._w = width
        self._h = height
        self._bg = bg
        self._bin = binary
        self._cmds = [
            'push graphic-context',
            f'viewbox 0 0 {width} {height}',
            'stroke-linecap round',
            'stroke-linejoin round',
        ]
        self._cur_font = None

    @staticmethod
    def _rgb(color):
        return f'rgb({int(color[0])},{int(color[1])},{int(color[2])})'

    def rect(self, x0, y0, x1, y1, color):
        self._cmds.append(f'fill {self._rgb(color)} stroke none rectangle {x0:.1f},{y0:.1f} {x1:.1f},{y1:.1f}')

    def line(self, x0, y0, x1, y1, color, width=1):
        w = max(1.0, float(width))
        self._cmds.append(f'fill none stroke {self._rgb(color)} stroke-width {w:.2f} line {x0:.2f},{y0:.2f} {x1:.2f},{y1:.2f}')

    def polyline(self, points, color, width=1):
        if len(points) < 2:
            return
        w = max(1.0, float(width))
        coords = ' '.join(f'{x:.2f},{y:.2f}' for x, y in points)
        self._cmds.append(f'fill none stroke {self._rgb(color)} stroke-width {w:.2f} polyline {coords}')

    def circle(self, cx, cy, radius, fill_color, outline_color=None, outline_width=1):
        r = float(radius)
        if outline_color is not None and outline_width > 0:
            self._cmds.append(
                f'fill {self._rgb(fill_color)} stroke {self._rgb(outline_color)} '
                f'stroke-width {outline_width} circle {cx:.2f},{cy:.2f} {cx + r:.2f},{cy:.2f}'
            )
        else:
            self._cmds.append(
                f'fill {self._rgb(fill_color)} stroke none '
                f'circle {cx:.2f},{cy:.2f} {cx + r:.2f},{cy:.2f}'
            )

    def text_width(self, text, size, bold=False):
        factor = 0.76 if bold else 0.60
        return len(text) * size * factor

    def text(self, x, y, text, color, size=13, bold=False):
        fpath = _font_path(bold=bold)
        font_key = (str(fpath) if fpath else '', size)
        if font_key != self._cur_font:
            if fpath:
                self._cmds.append(f'font "{fpath}"')
            self._cmds.append(f'font-size {size}')
            self._cur_font = font_key
        safe = text.replace('\\', '\\\\').replace("'", "\\'")
        baseline_y = y + size * 0.92
        self._cmds.append(f"stroke none fill {self._rgb(color)} text {x:.1f},{baseline_y:.1f} '{safe}'")

    def save(self, out_path):
        self._cmds.append('pop graphic-context')
        mvg = '\n'.join(self._cmds)
        bg_color = self._rgb(self._bg)
        with tempfile.NamedTemporaryFile('w', suffix='.mvg', encoding='utf-8', delete=True) as handle:
            handle.write(mvg)
            handle.flush()
            cmd = [self._bin, '-size', f'{self._w}x{self._h}', f'xc:{bg_color}', '-draw', f'@{handle.name}', str(out_path)]
            res = subprocess.run(cmd, capture_output=True, text=True)
            if res.returncode != 0:
                raise RuntimeError(f'ImageMagick convert failed: {res.stderr.strip()}')


class _PurePyCanvas:
    """Резервный CPU-растеризатор без единой внешней библиотеки (чистый Python stdlib)."""

    def __init__(self, width, height, bg):
        self._w = width
        self._h = height
        r, g, b = bg
        self._buf = bytearray((r, g, b) * (width * height))

    def _blend_pixel(self, x, y, color, alpha=1.0):
        if x < 0 or y < 0 or x >= self._w or y >= self._h or alpha <= 0.0:
            return
        idx = (y * self._w + x) * 3
        if alpha >= 0.999:
            self._buf[idx] = color[0]
            self._buf[idx + 1] = color[1]
            self._buf[idx + 2] = color[2]
        else:
            inv = 1.0 - alpha
            self._buf[idx] = int(self._buf[idx] * inv + color[0] * alpha)
            self._buf[idx + 1] = int(self._buf[idx + 1] * inv + color[1] * alpha)
            self._buf[idx + 2] = int(self._buf[idx + 2] * inv + color[2] * alpha)

    def rect(self, x0, y0, x1, y1, color):
        x_lo = max(0, int(math.floor(min(x0, x1))))
        x_hi = min(self._w - 1, int(math.ceil(max(x0, x1))))
        y_lo = max(0, int(math.floor(min(y0, y1))))
        y_hi = min(self._h - 1, int(math.ceil(max(y0, y1))))
        for py in range(y_lo, y_hi + 1):
            for px in range(x_lo, x_hi + 1):
                self._blend_pixel(px, py, color, 1.0)

    def line(self, x0, y0, x1, y1, color, width=1):
        rad = max(0.5, width * 0.5)
        min_x = max(0, int(math.floor(min(x0, x1) - rad - 1)))
        max_x = min(self._w - 1, int(math.ceil(max(x0, x1) + rad + 1)))
        min_y = max(0, int(math.floor(min(y0, y1) - rad - 1)))
        max_y = min(self._h - 1, int(math.ceil(max(y0, y1) + rad + 1)))
        dx = x1 - x0
        dy = y1 - y0
        len_sq = dx * dx + dy * dy
        for py in range(min_y, max_y + 1):
            for px in range(min_x, max_x + 1):
                if len_sq > 1e-8:
                    t = ((px - x0) * dx + (py - y0) * dy) / len_sq
                    t = max(0.0, min(1.0, t))
                    dist = math.hypot(px - (x0 + dx * t), py - (y0 + dy * t))
                else:
                    dist = math.hypot(px - x0, py - y0)
                if dist <= rad - 0.5:
                    self._blend_pixel(px, py, color, 1.0)
                elif dist < rad + 0.5:
                    self._blend_pixel(px, py, color, rad + 0.5 - dist)

    def polyline(self, points, color, width=1):
        for a, b in zip(points, points[1:]):
            self.line(a[0], a[1], b[0], b[1], color, width=width)

    def circle(self, cx, cy, radius, fill_color, outline_color=None, outline_width=1):
        outer = radius + (outline_width * 0.5 if outline_color else 0.0)
        inner = radius - (outline_width * 0.5 if outline_color else 0.0)
        min_x = max(0, int(math.floor(cx - outer - 1)))
        max_x = min(self._w - 1, int(math.ceil(cx + outer + 1)))
        min_y = max(0, int(math.floor(cy - outer - 1)))
        max_y = min(self._h - 1, int(math.ceil(cy + outer + 1)))
        for py in range(min_y, max_y + 1):
            for px in range(min_x, max_x + 1):
                dist = math.hypot(px - cx, py - cy)
                if outline_color and dist >= inner - 0.5 and dist <= outer + 0.5:
                    if dist <= outer - 0.5 and dist >= inner + 0.5:
                        self._blend_pixel(px, py, outline_color, 1.0)
                    elif dist > outer - 0.5:
                        self._blend_pixel(px, py, outline_color, max(0.0, outer + 0.5 - dist))
                    else:
                        a = max(0.0, dist - (inner - 0.5))
                        self._blend_pixel(px, py, fill_color, 1.0)
                        self._blend_pixel(px, py, outline_color, a)
                elif dist <= radius - 0.5:
                    self._blend_pixel(px, py, fill_color, 1.0)
                elif dist < radius + 0.5 and not outline_color:
                    self._blend_pixel(px, py, fill_color, radius + 0.5 - dist)

    @staticmethod
    def _glyph_scale(size):
        return 2 if size >= 11 else 1

    def text_width(self, text, size, bold=False):
        s = self._glyph_scale(size)
        return max(0, len(text) * 6 * s - s)

    def text(self, x, y, text, color, size=13, bold=False):
        s = self._glyph_scale(size)
        cx = int(round(x))
        cy = int(round(y))
        for ch in text.upper():
            rows = _FONT_5X7.get(ch)
            if rows:
                for ry, bits in enumerate(rows):
                    for rx in range(5):
                        if (bits >> (4 - rx)) & 1:
                            for sy in range(s):
                                for sx in range(s):
                                    self._blend_pixel(cx + rx * s + sx, cy + ry * s + sy, color, 1.0)
                                    if bold and sx == 0:
                                        self._blend_pixel(cx + rx * s + sx + 1, cy + ry * s + sy, color, 1.0)
            cx += 6 * s

    def save(self, out_path):
        stride = self._w * 3
        raw = bytearray()
        for row in range(self._h):
            raw.append(0)
            start = row * stride
            raw.extend(self._buf[start:start + stride])
        compressed = zlib.compress(bytes(raw), level=6)

        def chunk(tag, payload):
            crc = zlib.crc32(tag + payload) & 0xFFFFFFFF
            return struct.pack('>I', len(payload)) + tag + payload + struct.pack('>I', crc)

        ihdr = struct.pack('>IIBBBBB', self._w, self._h, 8, 2, 0, 0, 0)
        png = (
            b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', ihdr)
            + chunk(b'IDAT', compressed)
            + chunk(b'IEND', b'')
        )
        Path(out_path).write_bytes(png)


def _create_canvas(width, height, bg):
    if _pil_available():
        return _PilCanvas(width, height, bg)
    magick = _magick_binary()
    if magick:
        return _MvgCanvas(width, height, bg, magick)
    return _PurePyCanvas(width, height, bg)


def default_output_path(track_path, out_dir=PREVIEWS_DIR):
    """Имя PNG для трассы: `stage_england.tres` -> `docs/previews/england_stage_plan.png`."""
    stem = Path(track_path).stem
    if stem.startswith('stage_'):
        stem = stem[len('stage_'):]
    if not stem.endswith('_stage'):
        stem = f'{stem}_stage'
    return Path(out_dir) / f'{stem}_plan.png'


def ensure_previews_dir(out_dir):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    if out_dir.resolve() == PREVIEWS_DIR.resolve():
        gdignore = out_dir / '.gdignore'
        if not gdignore.exists():
            gdignore.write_text('', encoding='utf-8')


def _parse_ext_resources(text):
    ext = {}
    for match in _EXT_RE.finditer(text):
        attrs = match.group(1)
        path_m = _ATTR_PATH_RE.search(attrs)
        id_m = _ATTR_ID_RE.search(attrs)
        if path_m and id_m:
            ext[id_m.group(1)] = ROOT / path_m.group(1)
    return ext


def _parse_sub_resources(text):
    subs = {}
    headers = list(_SUB_HEADER_RE.finditer(text))
    res_match = _RES_HEADER_RE.search(text)
    res_pos = res_match.start() if res_match else len(text)
    for idx, match in enumerate(headers):
        id_m = _ATTR_ID_RE.search(match.group(1))
        if not id_m:
            continue
        end = headers[idx + 1].start() if idx + 1 < len(headers) else res_pos
        subs[id_m.group(1)] = text[match.end():end]
    return subs, (text[res_match.end():] if res_match else '')


def _bool_prop(block, key, default):
    match = re.search(r'^%s\s*=\s*(true|false)\b' % re.escape(key), block, re.M)
    if not match:
        return default
    return match.group(1) == 'true'


def _float_prop(block, key, default):
    match = re.search(r'^%s\s*=\s*(-?[\d.]+)' % re.escape(key), block, re.M)
    return float(match.group(1)) if match else default


def _str_prop(block, key, default):
    match = re.search(r'^%s\s*=\s*"([^"]*)"' % re.escape(key), block, re.M)
    return match.group(1) if match else default


def read_track(path):
    text = Path(path).read_text(encoding='utf-8')
    ext = _parse_ext_resources(text)
    subs, resource = _parse_sub_resources(text)

    road = None
    road_match = re.search(r'^road_curve\s*=\s*ExtResource\("([^"]+)"\)', resource, re.M)
    if road_match:
        road = ext.get(road_match.group(1))

    river = None
    river_width = 14.0
    river_sub = re.search(r'^river\s*=\s*SubResource\("([^"]+)"\)', resource, re.M)
    if river_sub and river_sub.group(1) in subs:
        rblock = subs[river_sub.group(1)]
        if _bool_prop(rblock, 'enabled', False):
            wc_match = re.search(r'^water_curve\s*=\s*ExtResource\("([^"]+)"\)', rblock, re.M)
            if wc_match:
                river = ext.get(wc_match.group(1))
            river_width = _float_prop(rblock, 'width_meters', 14.0)

    bridges = []
    bridges_line = re.search(r'^bridges\s*=\s*Array\[[^\]]*\]\(\[([^\]]*)\]\)', resource, re.M)
    if bridges_line:
        bridge_ids = re.findall(r'SubResource\("([^"]+)"\)', bridges_line.group(1))
    else:
        bridge_ids = [
            sid for sid, block in subs.items()
            if 'open_radius' in block or 'water_clearance' in block
        ]

    for sid in bridge_ids:
        block = subs.get(sid)
        if not block or not _bool_prop(block, 'enabled', True):
            continue
        bridges.append({
            'distance': _float_prop(block, 'distance', 0.0),
            'radius': _float_prop(block, 'open_radius', 10.0),
            'name': _str_prop(block, 'display_name', sid),
        })

    return {
        'road': road,
        'river': river,
        'river_width': river_width,
        'bridges': sorted(bridges, key=lambda b: b['distance']),
    }


def height_color(t):
    """Синий → зелёный → жёлтый → красный: чем выше, тем горячее."""
    stops = [(0.0, (56, 96, 190)), (0.35, (60, 180, 120)), (0.7, (232, 200, 70)), (1.0, (222, 74, 62))]
    for (a, ca), (b, cb) in zip(stops, stops[1:]):
        if t <= b:
            k = (t - a) / max(b - a, 1e-6)
            return tuple(int(ca[i] + (cb[i] - ca[i]) * k) for i in range(3))
    return stops[-1][1]


def _accumulated_lengths(points):
    acc = [0.0]
    for a, b in zip(points, points[1:]):
        acc.append(acc[-1] + math.dist(a, b))
    return acc


def _point_at_distance(points, acc, dist):
    if dist <= 0.0:
        return points[0]
    if dist >= acc[-1]:
        return points[-1]
    idx = bisect.bisect_right(acc, dist) - 1
    idx = max(0, min(len(points) - 2, idx))
    seg_len = acc[idx + 1] - acc[idx]
    t = (dist - acc[idx]) / seg_len if seg_len > 1e-6 else 0.0
    a, b = points[idx], points[idx + 1]
    return (
        a[0] + (b[0] - a[0]) * t,
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
    )


def _pick_scale_bar_m(scale):
    target_px = 180.0
    in_range = [m for m in SCALE_CANDIDATES_M if 80.0 <= m * scale <= 300.0]
    pool = in_range if in_range else SCALE_CANDIDATES_M
    return min(pool, key=lambda m: abs(m * scale - target_px))


def _format_scale_label(meters):
    if meters >= 1000 and meters % 1000 == 0:
        return '%d км' % (meters // 1000)
    return '%d м' % meters


def _draw_marker_label(canvas, x, y, text, color, canvas_w, size=13, bold=False, dy=-7):
    tw = canvas.text_width(text, size=size, bold=bold)
    tx = x + 11
    if tx + tw > canvas_w - 12:
        tx = max(8, x - 11 - tw)
    canvas.text(tx, y + dy, text, color, size=size, bold=bold)


def _rect_route_clearance(rx, ry, rw, rh, screen_pts):
    """Минимальное расстояние от прямоугольника подписи до ближайших точек дороги."""
    cx0, cx1 = rx, rx + rw
    cy0, cy1 = ry, ry + rh
    best = 1e9
    for px_s, py_s in screen_pts:
        dx = max(cx0 - px_s, 0.0, px_s - cx1)
        dy = max(cy0 - py_s, 0.0, py_s - cy1)
        d = dx * dx + dy * dy
        if d < best:
            best = d
    return math.sqrt(best)


def _place_endpoint_label(canvas, mx, my, text, color, canvas_w, canvas_h, screen_pts, prefer_dy=None):
    size = 15
    bold = True
    tw = canvas.text_width(text, size=size, bold=bold)
    th = float(size)
    # Кандидаты вокруг маркера: выше, ниже, слева, справа, диагонали.
    if prefer_dy is not None:
        offsets = [(11, prefer_dy), (-11 - tw, prefer_dy), (-tw * 0.5, prefer_dy)]
    else:
        offsets = [
            (10, -th - 7),
            (10, 9),
            (-11 - tw, -th * 0.5),
            (11, -th * 0.5),
            (-tw * 0.5, -th - 10),
            (-tw * 0.5, 11),
            (-11 - tw, -th - 6),
            (-11 - tw, 8),
        ]
    best_pos = None
    best_score = -1e9
    for ox, oy in offsets:
        rx = mx + ox
        ry = my + oy
        if rx < 8 or rx + tw > canvas_w - 8:
            continue
        if ry < 62 or ry + th > canvas_h - 54:
            continue
        clearance = _rect_route_clearance(rx, ry, tw, th, screen_pts)
        marker_gap = max(mx - 10 - (rx + tw), rx - (mx + 10), my - 10 - (ry + th), ry - (my + 10), 0.0)
        dist_penalty = math.hypot(ox * 0.1, oy * 0.1) * 0.05
        score = min(clearance, 24.0) + min(marker_gap, 12.0) * 0.5 - dist_penalty
        if score > best_score:
            best_score = score
            best_pos = (rx, ry)
    if best_pos is None:
        _draw_marker_label(canvas, mx, my, text, color, canvas_w, size=size, bold=bold,
                           dy=(prefer_dy if prefer_dy is not None else -7))
    else:
        canvas.text(best_pos[0], best_pos[1], text, color, size=size, bold=bold)


def build_stage_plan(track_path, out_path=None, width_px=1100):
    track_path = Path(track_path)
    info = read_track(track_path)
    road_path = info['road']
    if road_path is None:
        return None
    if not Path(road_path).exists():
        raise FileNotFoundError(f'не найден файл кривой: {road_path}')

    if out_path is None:
        out_path = default_output_path(track_path)
    else:
        out_path = Path(out_path)
    ensure_previews_dir(out_path.parent)

    ctrl = stage_model.load_curve(str(road_path))
    approx_len = sum(math.dist(a[0], b[0]) for a, b in zip(ctrl, ctrl[1:]))
    step = max(2.0, approx_len / 2400.0) if (approx_len > 6000.0 or len(ctrl) > 1500) else 2.0
    route = stage_model.sample_curve(ctrl, step=step)
    if len(route) < 2:
        raise ValueError(f'слишком мало точек в {road_path}')
    acc = _accumulated_lengths(route)

    river_path = info['river']
    river = (
        stage_model.sample_curve(stage_model.load_curve(str(river_path)), step=2.0)
        if river_path is not None and Path(river_path).exists() else []
    )

    xs = [p[0] for p in route]
    zs = [p[2] for p in route]
    heights = [p[1] for p in route]
    min_x, max_x = min(xs), max(xs)
    min_z, max_z = min(zs), max(zs)
    span_x = max(1.0, max_x - min_x)
    span_z = max(1.0, max_z - min_z)

    pad_x = 60
    top_pad = 78
    bottom_pad = 76
    scale = (width_px - 160) / max(span_x, span_z)
    w = max(560, int(span_x * scale) + pad_x * 2)
    h = max(360, int(span_z * scale) + top_pad + bottom_pad)
    origin_x = pad_x + ((w - pad_x * 2) - span_x * scale) * 0.5
    origin_y = top_pad + ((h - top_pad - bottom_pad) - span_z * scale) * 0.5

    canvas = _create_canvas(w, h, (243, 241, 236))
    low_h = min(heights)
    elev_span = max(heights) - low_h

    def px(x, z):
        return (origin_x + (x - min_x) * scale, origin_y + (z - min_z) * scale)

    # Река: полоса по воде + тонкая линия оси.
    if river:
        band = max(2, int(round(info['river_width'] * scale)))
        river_pts = [px(p[0], p[2]) for p in river]
        canvas.polyline(river_pts, (186, 213, 226), width=band)
        canvas.polyline(river_pts, (96, 148, 176), width=max(1, band // 6))

    # Дорога: цвет по высоте.
    route_px = [px(p[0], p[2]) for p in route]
    for (ax, ay), (bx, by), pt in zip(route_px, route_px[1:], route):
        t = (pt[1] - low_h) / elev_span if elev_span > 0.5 else 0.35
        canvas.line(ax, ay, bx, by, height_color(max(0.0, min(1.0, t))), width=3)

    placed_bridge_labels = []
    for bridge in info['bridges']:
        bp = _point_at_distance(route, acc, bridge['distance'])
        x, y = px(bp[0], bp[2])
        canvas.circle(x, y, 9, (255, 255, 255), outline_color=(28, 28, 28), outline_width=2)
        dy = -8
        for prev_x, prev_y in placed_bridge_labels:
            if abs(x - prev_x) < 90 and abs((y + dy) - prev_y) < 18:
                dy += 18
        placed_bridge_labels.append((x, y + dy))
        _draw_marker_label(canvas, x, y, '%d м' % round(bridge['distance']), (28, 28, 28), w, size=13, dy=dy)

    sx, sy = route_px[0]
    fx, fy = route_px[-1]
    step_pts = max(1, len(route_px) // 800)
    near_pts = route_px[::step_pts]
    same_spot = math.hypot(fx - sx, fy - sy) < 28.0
    if same_spot:
        canvas.circle(sx, sy, 8, (32, 122, 52), outline_color=(243, 241, 236), outline_width=2)
        canvas.circle(fx, fy, 4, (150, 40, 34))
        _place_endpoint_label(canvas, sx, sy, 'СТАРТ', (32, 122, 52), w, h, near_pts, prefer_dy=-22)
        _place_endpoint_label(canvas, fx, fy, 'ФИНИШ', (150, 40, 34), w, h, near_pts, prefer_dy=7)
    else:
        for mx, my, text, color in (
            (sx, sy, 'СТАРТ', (32, 122, 52)),
            (fx, fy, 'ФИНИШ', (150, 40, 34)),
        ):
            canvas.circle(mx, my, 7, color, outline_color=(243, 241, 236), outline_width=1)
            _place_endpoint_label(canvas, mx, my, text, color, w, h, near_pts)

    # Легенда: высота и масштаб.
    canvas.text(pad_x, 18, 'ВЫСОТА, м', (60, 60, 60), size=13)
    bar_x = pad_x + 84
    for i in range(120):
        t = i / 119.0
        canvas.rect(bar_x + i * 2, 22, bar_x + i * 2 + 2, 34, height_color(t))
    if elev_span <= 0.5:
        flat_label = '%.0f м' % low_h
        tw = canvas.text_width(flat_label, size=13)
        canvas.text(bar_x + 120 - tw * 0.5, 38, flat_label, (60, 60, 60), size=13)
    else:
        canvas.text(bar_x, 38, '%.0f' % low_h, (60, 60, 60), size=13)
        high_label = '%.0f' % (low_h + elev_span)
        hw = canvas.text_width(high_label, size=13)
        canvas.text(bar_x + 240 - hw, 38, high_label, (60, 60, 60), size=13)

    bar_m = _pick_scale_bar_m(scale)
    bar_len = max(20, int(round(bar_m * scale)))
    bar_y = h - 26
    canvas.line(pad_x, bar_y, pad_x + bar_len, bar_y, (40, 40, 40), width=3)
    canvas.text(pad_x, bar_y - 20, _format_scale_label(bar_m), (40, 40, 40), size=13)
    if river:
        note = 'голубая полоса — река, кружки — мосты'
        if pad_x + bar_len + 36 + canvas.text_width(note, size=13) <= w - 16:
            canvas.text(pad_x + bar_len + 36, bar_y - 20, note, (90, 100, 110), size=13)

    canvas.save(out_path)
    print('%s: %d×%d px, %.0f м дороги, %.0f–%.0f м' %
          (out_path, w, h, acc[-1], low_h, low_h + elev_span))
    if river:
        print('река: %d точек осевой линии, мостов %d' % (len(river), len(info['bridges'])))
    return out_path


def iter_curve_tracks(tracks_dir=DEFAULT_TRACKS_DIR):
    for path in sorted(Path(tracks_dir).glob('*.tres')):
        text = path.read_text(encoding='utf-8')
        if 'script_class="RallyTrackConfig"' not in text:
            continue
        if read_track(path)['road'] is None:
            continue
        yield path


def build_all_previews(tracks_dir=DEFAULT_TRACKS_DIR, out_dir=PREVIEWS_DIR, width_px=1100):
    ensure_previews_dir(out_dir)
    built = []
    for track_path in iter_curve_tracks(tracks_dir):
        out_path = default_output_path(track_path, out_dir=out_dir)
        result = build_stage_plan(track_path, out_path=out_path, width_px=width_px)
        if result is not None:
            built.append((track_path, result))
    return built


def main(track_path=None, out_path=None, width_px=1100):
    if track_path is None:
        built = build_all_previews(width_px=width_px)
        if not built:
            raise SystemExit('не найдено ни одной трассы с road_curve')
        return built
    result = build_stage_plan(track_path, out_path=out_path, width_px=width_px)
    if result is None:
        raise SystemExit('в %s нет road_curve' % track_path)
    return result


def _parse_args(argv):
    parser = argparse.ArgumentParser(description='Генерация верхних PNG-планов трасс в docs/previews/.')
    parser.add_argument('track', nargs='?', help='Путь к .tres трассы (если не задан — пересобрать все).')
    parser.add_argument('out', nargs='?', help='Путь выходного PNG (по умолчанию docs/previews/<name>_stage_plan.png).')
    parser.add_argument('--all', action='store_true', help='Пересобрать все трассы с road_curve в docs/previews/.')
    parser.add_argument('--out-dir', default=None, help='Папка вывода (по умолчанию docs/previews).')
    parser.add_argument('--width', type=int, default=1100, help='Базовая ширина изображения в пикселях.')
    return parser.parse_args(argv)


if __name__ == '__main__':
    args = _parse_args(sys.argv[1:])
    if args.all or args.track is None:
        target_dir = Path(args.out_dir) if args.out_dir else PREVIEWS_DIR
        build_all_previews(out_dir=target_dir, width_px=args.width)
    else:
        target_out = args.out
        if target_out is None and args.out_dir:
            target_out = default_output_path(args.track, out_dir=args.out_dir)
        main(args.track, target_out, width_px=args.width)
