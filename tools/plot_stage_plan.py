"""Карта трассы «вид сверху»: дорога по высоте, река, мосты, старт/финиш.

Нужна, чтобы оценить план этапа без Godot: где дорога идёт вдоль воды, где
пересекает её, как разложены серпантины и не залезают ли ветки друг на друга.

    python3 tools/plot_stage_plan.py data/tracks/stage_england.tres docs/england_stage_plan.png

Читает ровно те ресурсы, что и игра (`road_curve`, блок реки, список мостов),
поэтому картинка всегда соответствует текущей трассе.
"""
import math
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import stage_model

FONT_DIR = Path('/usr/share/fonts/truetype/dejavu')


def font(size, bold=False):
    name = 'DejaVuSans-Bold.ttf' if bold else 'DejaVuSans.ttf'
    try:
        return ImageFont.truetype(str(FONT_DIR / name), size)
    except OSError:
        return ImageFont.load_default()


def _ext_path(text, ident):
    match = re.search(r'path="res://([^"]+)" id="%s"' % re.escape(ident), text)
    return ROOT / match.group(1) if match else None


def read_track(path):
    text = Path(path).read_text(encoding='utf-8')
    road = _ext_path(text, 'curve')
    river = _ext_path(text, 'river_curve')
    bridges = []
    for match in re.finditer(r'id="(\w+)"\]\n((?:(?!\[sub_resource|\[resource)[\s\S])*)', text):
        block = match.group(2)
        if 'prop_id' not in block or 'open_radius' not in block:
            continue
        distance = re.search(r'^distance = ([\d.]+)', block, re.M)
        name = re.search(r'^display_name = "([^"]*)"', block, re.M)
        radius = re.search(r'^open_radius = ([\d.]+)', block, re.M)
        bridges.append({
            'distance': float(distance.group(1)) if distance else 0.0,
            'radius': float(radius.group(1)) if radius else 10.0,
            'name': name.group(1) if name else match.group(1),
        })
    return road, river, sorted(bridges, key=lambda b: b['distance'])


def height_color(t):
    """Синий → зелёный → жёлтый → красный: чем выше, тем горячее."""
    stops = [(0.0, (56, 96, 190)), (0.35, (60, 180, 120)), (0.7, (232, 200, 70)), (1.0, (222, 74, 62))]
    for (a, ca), (b, cb) in zip(stops, stops[1:]):
        if t <= b:
            k = (t - a) / max(b - a, 1e-6)
            return tuple(int(ca[i] + (cb[i] - ca[i]) * k) for i in range(3))
    return stops[-1][1]


def main(track_path, out_path, width_px=1100):
    road_path, river_path, bridges = read_track(track_path)
    if road_path is None:
        raise SystemExit('в %s нет road_curve' % track_path)
    route = stage_model.sample_curve(stage_model.load_curve(str(road_path)), step=2.0)
    river = (stage_model.sample_curve(stage_model.load_curve(str(river_path)), step=2.0)
             if river_path is not None else [])

    xs = [p[0] for p in route]
    zs = [p[2] for p in route]
    heights = [p[1] for p in route]
    span_x = max(xs) - min(xs)
    span_z = max(zs) - min(zs)
    scale = (width_px - 160) / max(span_x, span_z)
    pad = 60
    w = int(span_x * scale) + pad * 2
    h = int(span_z * scale) + pad * 2 + 40

    img = Image.new('RGB', (w, h), (243, 241, 236))
    draw = ImageDraw.Draw(img)
    top = min(heights)
    bottom = max(heights) - top

    def px(x, z):
        return (pad + (x - min(xs)) * scale, pad + (z - min(zs)) * scale)

    # Река: полоса по воде + тонкая линия оси.
    if river:
        band = max(2, int(14.0 * scale))
        draw.line([px(p[0], p[2]) for p in river], fill=(186, 213, 226), width=band, joint='curve')
        draw.line([px(p[0], p[2]) for p in river], fill=(96, 148, 176), width=max(1, band // 6), joint='curve')

    # Дорога: цвет по высоте.
    for a, b in zip(route, route[1:]):
        t = (a[1] - top) / bottom if bottom > 1e-6 else 0.0
        draw.line([px(a[0], a[2]), px(b[0], b[2])], fill=height_color(max(0.0, min(1.0, t))), width=3)

    label_font = font(15, True)
    small = font(13)
    for bridge in bridges:
        index = min(len(route) - 1, int(round(bridge['distance'] / 2.0)))
        x, y = px(route[index][0], route[index][2])
        r = 9
        draw.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255), outline=(28, 28, 28), width=2)
        draw.text((x + 13, y - 8), '%d м' % round(bridge['distance']), font=small, fill=(28, 28, 28))

    for index, text, color in ((0, 'СТАРТ', (32, 122, 52)), (len(route) - 1, 'ФИНИШ', (150, 40, 34))):
        x, y = px(route[index][0], route[index][2])
        draw.ellipse([x - 7, y - 7, x + 7, y + 7], fill=color)
        draw.text((x + 11, y - 7), text, font=label_font, fill=color)

    # Легенда: высота и масштаб.
    draw.text((pad, 18), 'ВЫСОТА, м', font=small, fill=(60, 60, 60))
    bar_x = pad + 84
    for i in range(120):
        t = i / 119.0
        draw.line([(bar_x + i * 2, 22), (bar_x + i * 2, 34)], fill=height_color(t))
    draw.text((bar_x, 38), '%.0f' % top, font=small, fill=(60, 60, 60))
    draw.text((bar_x + 240 - 22, 38), '%.0f' % (top + bottom), font=small, fill=(60, 60, 60))

    bar_len = int(500 * scale)
    bar_y = h - 26
    draw.line([(pad, bar_y), (pad + bar_len, bar_y)], fill=(40, 40, 40), width=3)
    draw.text((pad, bar_y - 20), '500 м', font=small, fill=(40, 40, 40))
    if river:
        draw.text((pad + bar_len + 40, bar_y - 20), 'голубая полоса — река, кружки — мосты',
                  font=small, fill=(90, 100, 110))

    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    img.save(out_path)
    print('%s: %d×%d px, %.0f м дороги, %.0f–%.0f м' %
          (out_path, w, h, len(route) * 2.0, top, top + bottom))
    if river:
        print('река: %d точек осевой линии, мостов %d' % (len(river), len(bridges)))


if __name__ == '__main__':
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else 'stage_plan.png')
