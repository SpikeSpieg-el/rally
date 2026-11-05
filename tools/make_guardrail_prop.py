"""Rebuild the modular steel guardrail and its original texture (stdlib only).

python3 tools/make_guardrail_prop.py
Does not touch the wooden fence or any existing prop.
"""
import hashlib
import math
from pathlib import Path
import random
import struct
import zlib

from make_prop_scenes import Material, Mesh, box, prop, write

ROOT = Path(__file__).resolve().parents[1]


def png_chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)


def main():
    rng = random.Random(67134)
    raw = bytearray()
    for y in range(128):
        raw.append(0)
        for x in range(128):
            grain = rng.randint(-12, 12)
            brightness = 153 + grain + int(18 * math.cos(y * math.tau / 32))
            if (x % 64 - 32) ** 2 + (y % 32 - 16) ** 2 <= 9:
                brightness = 78 if x % 64 < 32 else 212
            raw.extend((max(0, min(255, brightness - 7)),
                        max(0, min(255, brightness)),
                        max(0, min(255, brightness + 5))))
    data = b"\x89PNG\r\n\x1a\n"
    data += png_chunk(b"IHDR", struct.pack(">IIBBBBB", 128, 128, 8, 2, 0, 0, 0))
    data += png_chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    data += png_chunk(b"IEND", b"")
    texture = ROOT / "textures/environment/galvanized_steel.png"
    texture.write_bytes(data)
    source = "res://textures/environment/galvanized_steel.png"
    imported = "res://.godot/imported/galvanized_steel.png-%s.ctex" % hashlib.md5(source.encode()).hexdigest()
    import_path = texture.with_suffix(".png.import")
    if not import_path.exists():
        import_path.write_text(f'''[remap]

importer="texture"
type="CompressedTexture2D"
path="{imported}"
metadata={{"vram_texture": false}}

[deps]

source_file="{source}"
dest_files=["{imported}"]

[params]

compress/mode=0
mipmaps/generate=true
mipmaps/limit=-1
detect_3d/compress_to=0
''', encoding="utf-8")
    steel = Material("Mat_steel", (1, 1, 1), "tex_steel", .65)
    reflector = Material("Mat_reflector", (.9, .12, .06), "tex_steel", .45)
    meshes = []
    # Folded strips form a corrugated crash barrier rather than a flat plank.
    for i, (height, depth, tilt) in enumerate([
        (.62, .01, 25), (.73, -.04, -25), (.84, -.04, 25), (.95, .01, -25)
    ]):
        meshes.append(Mesh("Rail_%d" % i, "BoxMesh", box((3.0, .13, .035)),
                           steel, (0, height, depth), (tilt, 0, 0)))
    meshes.append(Mesh("Post", "BoxMesh", box((.1, 1.2, .13)), steel, (0, .5, -.1)))
    for name, depth in [("FrontReflector", .09), ("BackReflector", -.12)]:
        meshes.append(Mesh(name, "BoxMesh", box((.12, .12, .02)), reflector, (1.15, .8, depth)))
    text = prop("metal_guardrail", "MetalGuardrail", meshes, [steel, reflector],
                [("tex_steel", source)], extra_nodes='''[node name="Collision" type="StaticBody3D" parent="."]

[node name="Shape" type="CollisionShape3D" parent="Collision"]
position = Vector3(0, 0.55, 0)
shape = SubResource("GuardrailShape")
''')
    text = text.replace('[node name="MetalGuardrail"', '''[sub_resource type="BoxShape3D" id="GuardrailShape"]
size = Vector3(3, 1.1, 0.28)

[node name="MetalGuardrail"''')
    text = text.replace('albedo_texture = ExtResource("tex_steel")\nroughness = 0.65',
                        'albedo_texture = ExtResource("tex_steel")\nmetallic = 0.65\nroughness = 0.65')
    text = text.replace("specular_mode = 2", "specular_mode = 0", 1)
    write("metal_guardrail", text)


if __name__ == "__main__":
    main()
