"""Rebuild only the five biome props and their original seeded textures.

Run: python3 -m pip install Pillow; python3 tools/make_biome_props.py
Does not overwrite existing artist-authored grass or other prop scenes.
"""
import hashlib
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw
from make_prop_scenes import Material, Mesh, prop, sphere, cyl, write

ROOT = Path(__file__).resolve().parents[1]
TEXTURES = ROOT / "textures/environment"


def texture(name, base, seed, style):
    rng = random.Random(seed)
    image = Image.new("RGB", (128, 128))
    pixels = image.load()
    for y in range(128):
        for x in range(128):
            grain = rng.randint(-16, 16)
            if style == "bark":
                grain += int(18 * math.sin(x * 0.55 + math.sin(y * 0.09)))
            elif style == "moss":
                grain += int(14 * math.sin(x * 0.11) * math.cos(y * 0.13))
            pixels[x, y] = tuple(max(0, min(255, c + grain)) for c in base)
    draw = ImageDraw.Draw(image)
    if style == "needles":
        for _ in range(550):
            x, y = rng.randrange(128), rng.randrange(128)
            draw.line((x, y, x + rng.randint(-5, 5), y - 7), fill=(74, 100, 63))
    elif style == "cap":
        for _ in range(85):
            x, y = rng.randrange(128), rng.randrange(128)
            draw.ellipse((x, y, x + 3, y + 2), fill=(212, 181, 123))
    image.save(TEXTURES / (name + ".png"))


def flowers_texture():
    rng = random.Random(534)
    image = Image.new("RGBA", (128, 128))
    draw = ImageDraw.Draw(image)
    for i in range(9):
        x, y = 12 + i * 13, rng.randint(15, 70)
        draw.line((x, 127, x + 3, y), fill=(62, 91, 38, 255), width=2)
        draw.polygon([(x, 100), (x - 12, 82), (x, 89)], fill=(83, 111, 48, 255))
        for dx, dy in [(-3, 0), (3, 0), (0, -3), (0, 3)]:
            draw.ellipse((x + dx, y + dy, x + dx + 5, y + dy + 5), fill=(204, 187, 218, 255))
        draw.ellipse((x + 1, y + 1, x + 4, y + 4), fill=(234, 191, 67, 255))
    image.save(TEXTURES / "wildflowers.png")


def texture_import(name):
    """Explicit mipmaps also on a first headless import; keep artist overrides."""
    path = TEXTURES / (name + ".png.import")
    if path.exists():
        return
    source = "res://textures/environment/%s.png" % name
    digest = hashlib.md5(source.encode()).hexdigest()
    imported = "res://.godot/imported/%s.png-%s.ctex" % (name, digest)
    path.write_text(f'''[remap]

importer="texture"
type="CompressedTexture2D"
path="{imported}"
metadata={{
"vram_texture": false
}}

[deps]

source_file="{source}"
dest_files=["{imported}"]

[params]

compress/mode=0
mipmaps/generate=true
mipmaps/limit=-1
process/fix_alpha_border=true
process/premult_alpha=false
detect_3d/compress_to=0
''', encoding="utf-8")


def main():
    for name in ["juniper_needles", "dry_branches", "moss_stone", "mushroom_cap", "wildflowers"]:
        texture_import(name)
    texture("juniper_needles", (39, 65, 49), 101, "needles")
    texture("dry_branches", (113, 92, 64), 102, "bark")
    texture("moss_stone", (86, 104, 64), 103, "moss")
    texture("mushroom_cap", (135, 71, 39), 104, "cap")
    flowers_texture()
    for name, root, tex, meshes in [
        ("juniper", "Juniper", "juniper_needles", [
            ("SphereMesh", sphere(.6, 1.5, 7, 3), (0, .75, 0), (0, 0, 0)),
            ("SphereMesh", sphere(.4, .8, 7, 3), (.45, .4, .1), (0, 0, 0)),
            ("SphereMesh", sphere(.35, 1.0, 7, 3), (-.4, .5, -.1), (0, 0, 0)),
        ]),
        ("dry_shrub", "DryShrub", "dry_branches", [
            ("CylinderMesh", cyl(.018, .055, .85, 5), (0, .425, 0), (0, 0, 0)),
            ("CylinderMesh", cyl(.005, .025, .65, 4), (.17, .52, 0), (0, 0, -35)),
            ("CylinderMesh", cyl(.005, .025, .7, 4), (-.2, .48, .06), (15, 0, 40)),
            ("CylinderMesh", cyl(.005, .02, .55, 4), (.04, .48, .2), (40, 20, 0)),
            ("CylinderMesh", cyl(.004, .018, .4, 4), (.28, .65, -.09), (-30, 0, -55)),
        ]),
        ("moss_rock", "MossRock", "moss_stone", [
            ("SphereMesh", sphere(.65, .75, 7, 3), (0, .32, 0), (0, 0, 0)),
            ("SphereMesh", sphere(.32, .38, 6, 2), (.5, .17, .2), (0, 20, 0)),
        ]),
    ]:
        material = Material("Mat_surface", (1, 1, 1), "tex_surface", 1)
        nodes = [Mesh("Mesh_%d" % i, kind, params, material, origin, rot)
                 for i, (kind, params, origin, rot) in enumerate(meshes)]
        write(name, prop(name, root, nodes, [material],
                         [("tex_surface", "res://textures/environment/%s.png" % tex)]))

    cap = Material("Mat_cap", (1, 1, 1), "tex_cap", 1)
    stem = Material("Mat_stem", (.95, .86, .67), "tex_stem", 1)
    nodes = []
    for i, (x, z, h) in enumerate([(-.2, 0, .32), (.12, .13, .45), (.3, -.1, .22)]):
        nodes.append(Mesh("Stem_%d" % i, "CylinderMesh", cyl(.04, .06, h, 6), stem, (x, h / 2, z)))
        nodes.append(Mesh("Cap_%d" % i, "SphereMesh", sphere(h * .5, h * .4, 8, 3), cap, (x, h, z)))
    write("mushroom_cluster", prop("mushroom_cluster", "MushroomCluster", nodes, [cap, stem], [
        ("tex_cap", "res://textures/environment/mushroom_cap.png"),
        ("tex_stem", "res://textures/environment/dry_branches.png")]))
    material = Material("Mat_flowers", (1, 1, 1), "tex_flowers", 1)
    text = prop("wildflowers", "Wildflowers", [
        Mesh("Flowers_a", "QuadMesh", [("size", "Vector2(1, 0.8)"), ("center_offset", "Vector3(0, 0.4, 0)")], material),
        Mesh("Flowers_b", "QuadMesh", [("size", "Vector2(1, 0.8)"), ("center_offset", "Vector3(0, 0.4, 0)")], material, rot=(0, 90, 0)),
    ], [material], [("tex_flowers", "res://textures/environment/wildflowers.png")])
    text = text.replace('roughness = 1', 'transparency = 2\nalpha_scissor_threshold = 0.35\ncull_mode = 2\ntexture_repeat = false\nroughness = 1')
    write("wildflowers", text)


if __name__ == "__main__":
    main()
