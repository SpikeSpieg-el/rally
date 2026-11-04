"""Генерирует бесшовные текстуры для ассетов обстановки (scenes/props/*.tscn).

Зачем: процедурная обстановка раньше красилась «плоскими» материалами без
текстур, а новые пропсы нужны именно с текстурами. Фотоматериалов в репозитории
нет, поэтому текстуры считаются procedurally: бесшовный value-noise + цветовая
раскладка. Картинки детерминированы (фиксированный seed), поэтому повторный
запуск даёт те же файлы и не замусоривает diff.

Запуск:  python3 tools/make_prop_textures.py

Зависимости: numpy, pillow (те же, что у tools/render_engine_audio.py).
"""

import hashlib
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "textures", "environment")

SIZE = 512
SEED = 20241104

# Алфавит и основание — точно как в ResourceUID::id_to_text() движка Godot.
UID_CHARS = "abcdefghijklmnopqrstuvwxyz0123456789"
UID_BASE = 36
UID_SALT = 0x5EED17


def godot_uid(text: str) -> str:
    """Детерминированный uid:// для ресурса (совпадает с форматом Godot 4)."""
    value = (int(hashlib.md5(text.encode("utf-8")).hexdigest()[:15], 16) ^ UID_SALT) % (2 ** 62)
    chars = ""
    while value:
        chars = UID_CHARS[value % UID_BASE] + chars
        value //= UID_BASE
    return "uid://" + chars


def _value_noise(rng: np.random.Generator, size: int, freq: int) -> np.ndarray:
    """Бесшовный value-noise: сетка замыкается по модулю — стыка не видно."""
    grid = rng.random((freq, freq), dtype=np.float32)
    axis = np.arange(size, dtype=np.float32) * float(freq) / float(size)
    y0 = np.floor(axis).astype(np.int32)
    frac = axis - np.floor(axis)
    frac = frac * frac * (3.0 - 2.0 * frac)
    y0 %= freq
    y1 = (y0 + 1) % freq
    a = grid[np.ix_(y0, y0)]
    b = grid[np.ix_(y0, y1)]
    c = grid[np.ix_(y1, y0)]
    d = grid[np.ix_(y1, y1)]
    tx = frac[None, :]
    ty = frac[:, None]
    top = a + (b - a) * tx
    bottom = c + (d - c) * tx
    return top + (bottom - top) * ty


def fbm(rng: np.random.Generator, freq: int, octaves: int = 4, gain: float = 0.5) -> np.ndarray:
    total = np.zeros((SIZE, SIZE), dtype=np.float32)
    amplitude = 1.0
    norm = 0.0
    for _ in range(octaves):
        total += _value_noise(rng, SIZE, freq) * amplitude
        norm += amplitude
        amplitude *= gain
        freq = max(2, freq * 2)
    return total / norm


def ramp(value: np.ndarray, low, high) -> np.ndarray:
    """Раскладка серого (0..1) в цвет: low — тень, high — свет."""
    low = np.asarray(low, dtype=np.float32)
    high = np.asarray(high, dtype=np.float32)
    t = np.clip(value, 0.0, 1.0)[:, :, None]
    return low[None, None, :] + (high[None, None, :] - low[None, None, :]) * t


def mix(a: np.ndarray, b: np.ndarray, t) -> np.ndarray:
    if not isinstance(t, np.ndarray):
        t = np.full((SIZE, SIZE), float(t), dtype=np.float32)
    t = np.clip(t, 0.0, 1.0)[:, :, None]
    return a + (b - a) * t


def stripes(rng: np.random.Generator, count: int, freq: int = 4, jitter: float = 0.35) -> np.ndarray:
    """Вертикальные полосы с шумовым сдвигом — кора, доски, мешковина."""
    column = np.arange(SIZE, dtype=np.float32) / SIZE
    noise = fbm(rng, freq, 3) * jitter
    wave = (column[None, :] * count + noise)
    return np.abs(np.sin(wave * np.pi))


def save(name: str, rgb: np.ndarray) -> None:
    # Внутри генераторов цвета живут в 0..1, в файле — байты 0..255.
    data = np.clip(rgb * 255.0, 0.0, 255.0).astype(np.uint8)
    path = os.path.join(OUT_DIR, name + ".png")
    Image.fromarray(data, mode="RGB").save(path, optimize=True)
    print("  %-16s %s" % (name + ".png", path.replace(ROOT + "/", "")))
    write_import(name)


def write_import(name: str) -> None:
    """Пишет .import рядом с картинкой, чтобы Godot не перепридумывал настройки."""
    res_path = "res://textures/environment/%s.png" % name
    digest = hashlib.md5(res_path.encode("utf-8")).hexdigest()
    path = os.path.join(OUT_DIR, name + ".png.import")
    body = IMPORT_TEMPLATE.format(uid=godot_uid(res_path), md5=digest, res_path=res_path, name=name)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(body)


IMPORT_TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"
uid="{uid}"
path.s3tc="res://.godot/imported/{name}.png-{md5}.s3tc.ctex"
metadata={{
"imported_formats": ["s3tc_bptc"],
"vram_texture": true
}}

[deps]

source_file="{res_path}"
dest_files=["res://.godot/imported/{name}.png-{md5}.s3tc.ctex"]

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


# ------------------------------------------------------------------ текстуры

def tex_bark_dry(rng):
    """Сухая древесина мёртвого дерева: серо-бурые продольные борозды."""
    grain = stripes(rng, 26, 6, 0.5)
    detail = fbm(rng, 48, 3)
    value = np.clip(grain * 0.7 + detail * 0.3, 0.0, 1.0)
    return mix(ramp(value, (0.16, 0.14, 0.12), (0.62, 0.55, 0.45)),
               ramp(value, (0.13, 0.12, 0.11), (0.52, 0.48, 0.42)), 0.35)


def tex_birch_bark(rng):
    """Берёза: белая кора с тёмными поперечными чёрточками."""
    base = ramp(fbm(rng, 24, 3), (0.78, 0.77, 0.72), (0.97, 0.96, 0.92))
    rows = np.arange(SIZE, dtype=np.float32) / SIZE
    chevrons = np.abs(np.sin((rows[:, None] * 40.0 + fbm(rng, 8, 2) * 6.0) * np.pi))
    dark = np.clip(1.0 - chevrons * 3.0, 0.0, 1.0)
    dark = np.clip(dark * (0.4 + fbm(rng, 16, 2) * 0.9), 0.0, 1.0)
    bark = mix(base, ramp(dark, (0.12, 0.11, 0.10), (0.30, 0.28, 0.26)), dark * 0.9)
    return mix(bark, ramp(fbm(rng, 64, 2), (0.10, 0.10, 0.09), (0.22, 0.21, 0.20)),
               np.clip(fbm(rng, 6, 2) * 0.35, 0.0, 0.35))


def tex_leaves(rng):
    """Листва лиственного дерева: зелёные пятна с просветами."""
    clump = fbm(rng, 10, 4)
    fine = fbm(rng, 40, 3)
    value = np.clip(clump * 0.7 + fine * 0.3, 0.0, 1.0)
    leaf = ramp(value, (0.10, 0.20, 0.07), (0.62, 0.76, 0.34))
    holes = np.clip((fine - 0.62) * 4.0, 0.0, 1.0)
    return mix(leaf, ramp(fine, (0.24, 0.16, 0.09), (0.45, 0.34, 0.16)), holes * 0.55)


def tex_fern(rng):
    """Папоротник: мелкие зелёные «перья» на тёмном фоне."""
    value = fbm(rng, 32, 4)
    frond = np.abs(np.sin((np.arange(SIZE, dtype=np.float32)[None, :] / SIZE * 30.0
                           + fbm(rng, 12, 2) * 5.0) * np.pi))
    leaf = np.clip(frond * 0.6 + value * 0.4, 0.0, 1.0)
    green = ramp(leaf, (0.06, 0.16, 0.05), (0.45, 0.70, 0.28))
    return mix(green, ramp(value, (0.13, 0.10, 0.06), (0.30, 0.24, 0.12)), 0.30)


def tex_grass_blade(rng):
    """Травяной пучок: узкие вертикальные лезвия."""
    blade = np.abs(np.sin((np.arange(SIZE, dtype=np.float32)[None, :] / SIZE * 46.0
                           + fbm(rng, 10, 2) * 8.0) * np.pi))
    value = np.clip(blade * 0.75 + fbm(rng, 40, 2) * 0.25, 0.0, 1.0)
    return ramp(value, (0.16, 0.26, 0.08), (0.74, 0.86, 0.42))


def tex_straw(rng):
    """Сено/солома: перепутанные светлые соломины."""
    along = np.abs(np.sin((np.arange(SIZE, dtype=np.float32)[:, None] / SIZE * 34.0
                           + fbm(rng, 14, 2) * 10.0) * np.pi))
    across = np.abs(np.sin((np.arange(SIZE, dtype=np.float32)[None, :] / SIZE * 22.0
                            + fbm(rng, 14, 2) * 8.0) * np.pi))
    value = np.clip(along * 0.45 + across * 0.35 + fbm(rng, 60, 2) * 0.2, 0.0, 1.0)
    return ramp(value, (0.32, 0.24, 0.09), (0.90, 0.79, 0.42))


def tex_tire(rng):
    """Резина покрышки: тёмные блоки протектора."""
    along = np.abs(np.sin(np.arange(SIZE, dtype=np.float32)[None, :] / SIZE * 18.0 * np.pi))
    across = np.abs(np.sin((np.arange(SIZE, dtype=np.float32)[:, None] / SIZE * 6.0
                            + fbm(rng, 8, 2)) * np.pi))
    blocks = np.clip(0.55 + along * 0.5 - across * 0.6, 0.0, 1.0)
    value = np.clip(blocks * 0.8 + fbm(rng, 80, 2) * 0.2, 0.0, 1.0)
    rubber = ramp(value, (0.05, 0.05, 0.06), (0.30, 0.30, 0.32))
    return mix(rubber, ramp(fbm(rng, 30, 2), (0.10, 0.10, 0.10), (0.20, 0.20, 0.21)), 0.25)


def tex_plank(rng):
    """Доски забора: продольные волокна и щели между досками."""
    rows = np.arange(SIZE, dtype=np.float32) / SIZE
    gaps = np.abs(np.sin(rows[:, None] * 4.0 * np.pi))
    gap_mask = np.clip((gaps - 0.86) * 7.0, 0.0, 1.0)
    grain = stripes(rng, 60, 8, 0.30)
    value = np.clip(grain * 0.65 + fbm(rng, 24, 3) * 0.35, 0.0, 1.0)
    wood = ramp(value, (0.24, 0.17, 0.10), (0.66, 0.50, 0.31))
    return mix(wood, np.full((SIZE, SIZE, 3), (0.07, 0.06, 0.05), dtype=np.float32), gap_mask)


def tex_rock_mossy(rng):
    """Камень с мхом: серые сколы и зелёные островки."""
    cracks = np.clip(1.0 - np.abs(fbm(rng, 12, 4) - 0.5) * 6.0, 0.0, 1.0)
    value = np.clip(fbm(rng, 20, 4) * 0.7 + cracks * 0.3, 0.0, 1.0)
    stone = ramp(value, (0.20, 0.21, 0.23), (0.74, 0.75, 0.76))
    moss = np.clip((fbm(rng, 8, 3) - 0.48) * 3.2, 0.0, 1.0)
    return mix(stone, ramp(fbm(rng, 36, 3), (0.14, 0.24, 0.10), (0.36, 0.50, 0.20)), moss * 0.85)


def tex_dirt(rng):
    """Голая земля насыпи: бурые комья и мелкие камешки."""
    value = fbm(rng, 16, 4)
    pebble = np.clip((fbm(rng, 64, 2) - 0.55) * 5.0, 0.0, 1.0)
    soil = ramp(np.clip(value * 0.8 + fbm(rng, 48, 2) * 0.2, 0.0, 1.0),
                (0.18, 0.12, 0.07), (0.58, 0.44, 0.30))
    return mix(soil, ramp(fbm(rng, 90, 2), (0.34, 0.31, 0.28), (0.62, 0.59, 0.54)), pebble * 0.6)


def tex_burlap(rng):
    """Мешковина: грубое плетение «в клетку»."""
    column = np.arange(SIZE, dtype=np.float32)[None, :] / SIZE
    row = np.arange(SIZE, dtype=np.float32)[:, None] / SIZE
    weave = np.abs(np.sin(column * 32.0 * np.pi)) * np.abs(np.sin(row * 32.0 * np.pi))
    value = np.clip(weave * 0.6 + fbm(rng, 40, 3) * 0.4, 0.0, 1.0)
    return ramp(value, (0.24, 0.19, 0.11), (0.74, 0.65, 0.46))


def tex_banner(rng):
    """Рекламный щит: цветная панель с полосой и блоками «текста»."""
    column = np.arange(SIZE, dtype=np.float32)[None, :] / SIZE
    row = np.arange(SIZE, dtype=np.float32)[:, None] / SIZE
    panel = np.full((SIZE, SIZE, 3), (0.86, 0.88, 0.90), dtype=np.float32)
    band = np.clip(1.0 - np.abs(row - 0.30) * 26.0, 0.0, 1.0)[:, :, None]
    panel = panel + (np.array([0.72, 0.11, 0.10], dtype=np.float32)[None, None, :] - panel) * band
    lower = np.clip(1.0 - np.abs(row - 0.72) * 22.0, 0.0, 1.0)[:, :, None]
    panel = panel + (np.array([0.08, 0.16, 0.42], dtype=np.float32)[None, None, :] - panel) * lower
    blocks = np.clip((np.abs(np.sin(column * 7.0 * np.pi)) - 0.55) * 4.0, 0.0, 1.0)
    block_rows = np.clip(((row > 0.42) & (row < 0.60)).astype(np.float32), 0.0, 1.0)
    ink = np.clip(blocks * block_rows, 0.0, 1.0)[:, :, None]
    panel = panel + (np.array([0.10, 0.11, 0.13], dtype=np.float32)[None, None, :] - panel) * ink * 0.8
    wear = fbm(rng, 24, 3) * 0.12
    return mix(panel, ramp(fbm(rng, 50, 2), (0.42, 0.40, 0.36), (0.58, 0.56, 0.52)), wear)


def tex_wood_cut(rng):
    """Срез древесины: годовые кольца и трещины от центра."""
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
    dx = (xx - SIZE * 0.5) / SIZE
    dy = (yy - SIZE * 0.5) / SIZE
    radius = np.sqrt(dx * dx + dy * dy)
    rings = np.abs(np.sin((radius * 46.0 + fbm(rng, 6, 2) * 3.0) * np.pi))
    value = np.clip(rings * 0.7 + fbm(rng, 70, 2) * 0.3, 0.0, 1.0)
    wood = ramp(value, (0.34, 0.24, 0.14), (0.78, 0.64, 0.44))
    cracks = np.clip((fbm(rng, 10, 4) - 0.62) * 6.0, 0.0, 1.0)
    return mix(wood, ramp(fbm(rng, 30, 2), (0.16, 0.12, 0.08), (0.30, 0.23, 0.15)), cracks * 0.7)


TEXTURES = [
    ("bark_dry", tex_bark_dry),
    ("birch_bark", tex_birch_bark),
    ("leaves", tex_leaves),
    ("fern", tex_fern),
    ("grass_blade", tex_grass_blade),
    ("straw", tex_straw),
    ("tire", tex_tire),
    ("plank", tex_plank),
    ("rock_mossy", tex_rock_mossy),
    ("dirt", tex_dirt),
    ("burlap", tex_burlap),
    ("banner", tex_banner),
    ("wood_cut", tex_wood_cut),
]


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    print("Текстуры ассетов → textures/environment/ (%dx%d)" % (SIZE, SIZE))
    for index, (name, builder) in enumerate(TEXTURES):
        rng = np.random.default_rng(SEED + index * 7919)
        save(name, builder(rng))
    print("Готово: %d текстур." % len(TEXTURES))


if __name__ == "__main__":
    main()
