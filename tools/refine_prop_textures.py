"""Доводит «сырые» картинки пропсов до игровых текстур.

Генератор картинок выдаёт красивые, но НЕ бесшовные изображения, да ещё и
любого размера — прямо на меш такое не натянешь, шов будет виден. Этот
скрипт приводит их к виду, который ждёт движок:

  1. обрезает до квадрата и масштабирует до рабочего размера;
  2. делает текстуру БЕСШОВНОЙ: копия со сдвигом на полкартинки
     подмешивается к оригиналу плавной маской, поэтому разрыв уходит
     с края в середину, где его перекрывает непрерывная часть;
  3. кадрирует яркость под albedo_color материала из scenes/props/*.tscn —
     движок перемножает текстуру на этот цвет, и тёмная резина покрышки
     при множителе 0.28 уехала бы в чёрный квадрат. Яркость правится
     ГАММОЙ, а не умножением: света не «зажимаются» в белый;
  4. слегка приглушает насыщенность — игра пасмурная, а картинки сочные;
  5. уменьшает до 512² (после подмешивания — это заодно сглаживает шов).

Запуск:
    python3 tools/refine_prop_textures.py <папка-с-картинками>

В папке ожидаются файлы с именами будущих текстур: bark_dry.png,
birch_bark.png, leaves.png, fern.png, grass_blade.png, straw.png, tire.png,
plank.png, rock_mossy.png, dirt.png, burlap.png, banner.png, wood_cut.png.
Результат пишется в textures/environment/ поверх существующих файлов.

Если картинок нет, текстуры остаются процедурными — их по-прежнему собирает
tools/make_prop_textures.py.
"""

import math
import os
import re
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "textures", "environment")
PROPS_DIR = os.path.join(ROOT, "scenes", "props")

FINAL_SIZE = 512
WORK_SIZE = 768
SEAM_BAND = 0.30
# У досок длинная направленная структура: шов поперёк волокон очень заметен,
# поэтому его приходится размывать на существенно большей полосе.
SEAM_BAND_OVERRIDE = {"plank": 0.60}
DESATURATE = 0.14

# К какой средней яркости приводить ИТОГОВЫЙ цвет (текстура × albedo_color).
TARGET_LUMA = {
    "bark_dry": 0.42,
    "birch_bark": 0.66,
    "leaves": 0.42,
    "fern": 0.42,
    "grass_blade": 0.44,
    "straw": 0.48,
    "tire": 0.24,
    "plank": 0.45,
    "rock_mossy": 0.45,
    "dirt": 0.40,
    "burlap": 0.52,
    "banner": 0.62,
    "wood_cut": 0.55,
}
DEFAULT_LUMA = 0.44

# Некоторые текстуры тянутся на вытянутый меш — у них свой размер.
SPECIAL_SIZE = {"banner": (512, 256)}


def tint_for(texture_name):
    """albedo_color материалов, которыми красится эта текстура."""
    tints = []
    for fn in sorted(os.listdir(PROPS_DIR)):
        if not fn.endswith(".tscn"):
            continue
        text = open(os.path.join(PROPS_DIR, fn), encoding="utf-8").read()
        exts = {i: p for p, i in re.findall(
            r'\[ext_resource type="Texture2D" path="res://([^"]+)" id="([^"]+)"\]', text)}
        for block in re.split(r"^\[sub_resource ", text, flags=re.M)[1:]:
            if not re.match(r'type="StandardMaterial3D"', block):
                continue
            col = re.search(r"albedo_color = Color\(([^)]*)\)", block)
            tex = re.search(r'albedo_texture = ExtResource\("([^"]+)"\)', block)
            if not (col and tex) or tex.group(1) not in exts:
                continue
            if os.path.basename(exts[tex.group(1)]) != texture_name:
                continue
            tints.append([float(v) for v in col.group(1).split(",")[:3]])
    if not tints:
        return (1.0, 1.0, 1.0), 1.0
    means = [0.2126 * t[0] + 0.7152 * t[1] + 0.0722 * t[2] for t in tints]
    # Текстура красится несколькими материалами — берём усреднённый оттенок,
    # чтобы ни один пропс не уехал в крайность.
    return tuple(sum(t[i] for t in tints) / len(tints) for i in range(3)), sum(means) / len(means)


def to_square(img):
    w, h = img.size
    side = min(w, h)
    left, top = (w - side) // 2, (h - side) // 2
    return img.crop((left, top, left + side, top + side))


def make_seamless(a, band=SEAM_BAND):
    """band — доля картинки, на которой размывается шов."""
    """Сдвинутая на полкартинки копия закрывает разрыв на границе.

    Оригинал непрерывен в середине и рвётся на краю; копия — наоборот.
    Маска берёт середину из оригинала, а край — из копии, и шва нет нигде.
    """
    h, w = a.shape[:2]
    rolled = np.roll(a, (h // 2, w // 2), axis=(0, 1))
    y = np.abs(np.linspace(-1.0, 1.0, h, endpoint=False))[:, None]
    x = np.abs(np.linspace(-1.0, 1.0, w, endpoint=False))[None, :]
    d = np.maximum(y, x)
    m = np.clip(d / band, 0.0, 1.0)
    m = m * m * (3.0 - 2.0 * m)
    return a * (1.0 - m[..., None]) + rolled * m[..., None]


def suggest_tint(tint, tint_luma, raw_luma, target):
    """Подобрать albedo_color под фотографическую текстуру.

    Оттенки из scenes/props подбирались под гладкие процедурные текстуры:
    покрышку красили в 0.28, потому что procedural-текстура была светло-серой.
    Фототекстура уже чёрная, и множитель 0.28 увёл бы её в пятно — значит
    оттенок надо поднять. Тон сохраняем: масштабируем весь цвет целиком,
    ровно настолько, чтобы ни один канал не вышел за 1.0.
    """
    if raw_luma <= 0.001 or tint_luma <= 0.05:
        return tint
    scale = target / (raw_luma * tint_luma)
    headroom = 1.0 / max(max(tint), 0.001)
    scale = min(scale, headroom)
    return tuple(min(1.0, c * scale) for c in tint)


def solve_gamma(a, target, lo=0.12, hi=6.0):
    """Подобрать показатель степени: mean(a ** e) == target.

    Gamma, а не умножение: при любом показателе значения остаются в [0, 1],
    света не «зажимаются» в плашку.
    """
    for _ in range(48):
        mid = math.sqrt(lo * hi)
        if float(np.mean(a ** mid)) < target:
            hi = mid
        else:
            lo = mid
    return math.sqrt(lo * hi)


def refine(src_path, name):
    a = raw_texture(src_path, SEAM_BAND_OVERRIDE.get(name, SEAM_BAND))
    tint, tint_luma = tint_for(name + ".png")
    tint_luma = max(tint_luma, 0.05)
    luma = 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]
    target = TARGET_LUMA.get(name, DEFAULT_LUMA) / tint_luma
    target = min(max(target, 0.05), 0.97)
    gamma = solve_gamma(luma, target)
    a = np.power(np.clip(a, 0.0, 1.0), gamma)

    # Вычитать оттенок из текстуры НЕ надо: albedo_color у этих материалов
    # поднят почти до белого, поэтому PNG остаётся естественного цвета и его
    # можно повесить на любой другой меш без перекраса.

    size = SPECIAL_SIZE.get(name, (FINAL_SIZE, FINAL_SIZE))
    out_img = Image.fromarray(np.clip(a * 255.0, 0, 255).astype(np.uint8)).resize(
        size, Image.LANCZOS
    )
    out_path = os.path.join(OUT_DIR, name + ".png")
    out_img.save(out_path, optimize=True)
    final = np.asarray(out_img, dtype=np.float32) / 255.0
    final_luma = 0.2126 * final[..., 0] + 0.7152 * final[..., 1] + 0.0722 * final[..., 2]
    print("%-14s %-10s gamma %.2f  средняя яркость %.3f × оттенок %.2f = %.3f" % (
        name, "%dx%d" % size, gamma, float(final_luma.mean()), tint_luma,
        float(final_luma.mean()) * tint_luma))
    return out_path


def raw_texture(src_path, band=SEAM_BAND):
    """Текстура после обрезки, бесшовного подмешивания и приглушения цвета."""
    img = Image.open(src_path).convert("RGB")
    img = to_square(img).resize((WORK_SIZE, WORK_SIZE), Image.LANCZOS)
    a = np.asarray(img, dtype=np.float32) / 255.0
    a = make_seamless(a, band)
    grey = (0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2])[..., None]
    a = np.clip(a * (1.0 - DESATURATE) + grey * DESATURATE, 0.0, 1.0)
    return a


def main():
    if len(sys.argv) < 2:
        print(" usage: python3 tools/refine_prop_textures.py <папка-с-картинками>")
        print("        python3 tools/refine_prop_textures.py <папка> --tints")
        return 1
    src_dir = sys.argv[1]
    suggest = "--tints" in sys.argv
    names = sorted(TARGET_LUMA)
    done = 0
    for name in names:
        path = None
        for ext in (".png", ".jpg", ".jpeg"):
            candidate = os.path.join(src_dir, name + ext)
            if os.path.exists(candidate):
                path = candidate
                break
        if path is None:
            continue
        if suggest:
            a = raw_texture(path, SEAM_BAND_OVERRIDE.get(name, SEAM_BAND))
            luma = 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]
            raw_luma = float(luma.mean())
            tint, tint_luma = tint_for(name + ".png")
            target = TARGET_LUMA.get(name, DEFAULT_LUMA)
            new = suggest_tint(tint, tint_luma, raw_luma, target)
            new_luma = 0.2126 * new[0] + 0.7152 * new[1] + 0.0722 * new[2]
            gamma = solve_gamma(luma, target / max(new_luma, 0.05))
            print("%-14s Color(%s) -> Color(%s)   гамма %.2f" % (
                name,
                ", ".join("%.2f" % c for c in tint),
                ", ".join("%.3f" % c for c in new),
                gamma,
            ))
        else:
            refine(path, name)
        done += 1
    print("обработано: %d из %d" % (done, len(names)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
