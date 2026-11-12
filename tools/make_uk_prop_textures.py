"""Текстуры для UK-участка: мокрый камень, замшелая кладка, мостовой брус.

Зачем отдельный файл: textures/environment/ уже занят лесными текстурами
(tools/make_prop_textures.py), а мосты и берега Англии — другая палитра:
серый мокрый сланец, зелёный мох, потемневшее дерево настила.

Запуск:  python3 tools/make_uk_prop_textures.py
Зависимости: numpy, pillow — как у tools/make_prop_textures.py.
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import make_prop_textures as base  # noqa: E402  (общие шум/раскладка/импорт)

SIZE = base.SIZE


def tex_wet_stone(rng):
    """Мокрый британский камень: серый, холодный, с блестящими лужицами."""
    coarse = base.fbm(rng, 4, 5)
    grain = base.fbm(rng, 32, 3)
    blotch = base.fbm(rng, 8, 3)
    value = 0.55 * coarse + 0.28 * grain + 0.17 * blotch
    stone = base.ramp(value, (0.075, 0.085, 0.085), (0.44, 0.46, 0.44))
    # Плиты: редкие швы тёмного раствора.
    seam = np.abs(np.sin((np.arange(SIZE, dtype=np.float32)[None, :] + coarse * 6.0) * 0.9))
    stone *= (0.82 + 0.18 * seam)[:, :, None]
    wet = base.mix(stone, stone * 0.55, np.clip(blotch * 0.9, 0.0, 1.0))
    return wet


def tex_mossy_masonry(rng):
    """Замшелая кладка моста: тёплый камень + зелёные лишайники по швам."""
    blocks = base.fbm(rng, 3, 4)
    grit = base.fbm(rng, 24, 3)
    moss = base.fbm(rng, 6, 4)
    masonry = base.ramp(0.7 * blocks + 0.3 * grit, (0.10, 0.105, 0.095), (0.40, 0.39, 0.34))
    green = base.ramp(moss, (0.03, 0.055, 0.020), (0.18, 0.26, 0.10))
    cover = np.clip((moss - 0.52) * 2.6, 0.0, 1.0) * 0.75
    # Лишайник держится в «швах» — там, где блоки темнее среднего.
    cover *= np.clip(1.2 - blocks * 1.1, 0.0, 1.0)
    return base.mix(masonry, green, cover)


def tex_bridge_timber(rng):
    """Брус настила: тёмное мокрое дерево с продольными волокнами."""
    grain = base.stripes(rng, 26, 5, 0.5)
    knots = base.fbm(rng, 16, 4)
    value = 0.55 * grain + 0.45 * knots
    wood = base.ramp(value, (0.045, 0.032, 0.024), (0.24, 0.16, 0.10))
    cracks = np.clip((grain - 0.82) * 5.0, 0.0, 1.0)
    return base.mix(wood, wood * 0.35, cracks)


def tex_wet_slate(rng):
    """Сланец/булыжник для берега: почти чёрный камень с холодным блеском."""
    coarse = base.fbm(rng, 5, 4)
    grain = base.fbm(rng, 40, 3)
    value = 0.65 * coarse + 0.35 * grain
    slate = base.ramp(value, (0.035, 0.042, 0.048), (0.24, 0.26, 0.27))
    sheen = np.clip((grain - 0.6) * 3.0, 0.0, 1.0)
    return base.mix(slate, slate * 1.35 + 0.02, sheen)


TEXTURES = [
    ("wet_stone", tex_wet_stone),
    ("mossy_masonry", tex_mossy_masonry),
    ("bridge_timber", tex_bridge_timber),
    ("wet_slate", tex_wet_slate),
]


def main() -> None:
    os.makedirs(base.OUT_DIR, exist_ok=True)
    print("Текстуры UK-участка → textures/environment/")
    for index, (name, maker) in enumerate(TEXTURES):
        rng = np.random.default_rng(base.SEED + 977 * (index + 1))
        base.save(name, maker(rng))
    print("Готово: %d текстур" % len(TEXTURES))


if __name__ == "__main__":
    main()
