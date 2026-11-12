"""Модульные сцены UK-участка: малый мост, большой мост, берег, стенка.

Это обычные сцены scenes/props/*.tscn — их открывают и правят в редакторе,
а расстановку задаёт RallyTrackConfig (river + bridges) и RallyPropLibrary.
Файлы перезаписываются целиком, поэтому правки вносятся сюда либо прямо в
.tscn (тогда скрипт больше не запускать).

Соглашение о координатах (важно для расстановки):
  * +X — ВДОЛЬ дороги (длина пролёта),
  * +Z — поперёк (ширина настила),
  * начало координат — ВЕРХ настила по центру пролёта,
  * всё, что ниже нуля, уходит в овраг реки.

Запуск:  python3 tools/make_uk_props.py
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from make_prop_scenes import PROPS_DIR, TEX, num, transform  # noqa: E402

ROOT = os.path.dirname(PROPS_DIR)
TEXTURES = {
    "wet_stone": TEX % "wet_stone",
    "mossy_masonry": TEX % "mossy_masonry",
    "bridge_timber": TEX % "bridge_timber",
    "wet_slate": TEX % "wet_slate",
}


class Scene(object):
    """Сборщик текста .tscn: текстуры, материалы, меши, формы и узлы."""

    def __init__(self, root_name):
        self.root_name = root_name
        self.ext = []
        self.subs = []
        self.nodes = []
        self._extra_nodes = []

    # ----------------------------------------------------------- ресурсы
    def texture(self, key):
        if all(entry[0] != key for entry in self.ext):
            self.ext.append((key, TEXTURES[key]))

    def material(self, key, color, texture, roughness=0.92, metallic=0.0, specular=0.3):
        self.texture(texture)
        self.subs.append(
            '[sub_resource type="StandardMaterial3D" id="%s"]\n'
            "albedo_color = Color(%s, 1)\n"
            'albedo_texture = ExtResource("%s")\n'
            "roughness = %s\n"
            "metallic = %s\n"
            "metallic_specular = %s\n"
            "specular_mode = 2\n"
            % (key, ", ".join(num(c) for c in color), texture,
               num(roughness), num(metallic), num(specular))
        )

    def box(self, key, size, material, origin=(0.0, 0.0, 0.0), rot=(0.0, 0.0, 0.0)):
        self._mesh(key, "BoxMesh", [("size", "Vector3(%s)" % ", ".join(num(v) for v in size))],
                   material, origin, rot)

    def cylinder(self, key, top, bottom, height, radial, material,
                 origin=(0.0, 0.0, 0.0), rot=(0.0, 0.0, 0.0)):
        self._mesh(key, "CylinderMesh",
                   [("top_radius", num(top)), ("bottom_radius", num(bottom)),
                    ("height", num(height)), ("radial_segments", str(radial)),
                    ("rings", "1")], material, origin, rot)

    def sphere(self, key, radius, height, radial, rings, material, origin=(0.0, 0.0, 0.0)):
        self._mesh(key, "SphereMesh",
                   [("radius", num(radius)), ("height", num(height)),
                    ("radial_segments", str(radial)), ("rings", str(rings))],
                   material, origin, (0.0, 0.0, 0.0))

    def _mesh(self, key, kind, params, material, origin, rot):
        self.subs.append(
            '[sub_resource type="%s" id="%s"]\nmaterial = SubResource("%s")\n%s\n'
            % (kind, key, material, "\n".join("%s = %s" % pair for pair in params))
        )
        self.nodes.append(
            '[node name="%s" type="MeshInstance3D" parent="."]\ntransform = %s\nmesh = SubResource("%s")\n'
            % (key, transform(origin, rot), key)
        )

    # ------------------------------------------------------------ коллизия
    def body(self, name, shapes, offset=(0.0, 0.0, 0.0), layer=2):
        """StaticBody3D с набором BoxShape3D. shapes: (ключ, размер, центр)."""
        self._extra_nodes.append('\n[node name="%s" type="StaticBody3D" parent="."]\n'
                                 "collision_layer = %d\n" % (name, layer))
        for key, size, centre in shapes:
            shape_key = "%s_%s" % (name, key)
            self.subs.append(
                '[sub_resource type="BoxShape3D" id="%s"]\nsize = Vector3(%s)\n'
                % (shape_key, ", ".join(num(v) for v in size))
            )
            self._extra_nodes.append(
                '\n[node name="%s" type="CollisionShape3D" parent="%s"]\n'
                "transform = %s\nshape = SubResource(\"%s\")\n"
                % (key, name,
                   transform((offset[0] + centre[0], offset[1] + centre[1], offset[2] + centre[2])),
                   shape_key)
            )

    # --------------------------------------------------------------- вывод
    def text(self):
        blocks = ['[ext_resource type="Texture2D" path="%s" id="%s"]\n' % (path, key)
                  for key, path in self.ext]
        return (
            "[gd_scene format=3]\n\n"
            + "\n".join(blocks)
            + "\n"
            + "\n".join(self.subs)
            + "\n"
            + '[node name="%s" type="Node3D"]\n' % self.root_name
            + "\n".join(self.nodes)
            + "".join(self._extra_nodes)
        )


def write(name, scene):
    path = os.path.join(PROPS_DIR, name + ".tscn")
    text = scene.text()
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)
    print("  %-22s %d байт" % (name + ".tscn", len(text)))


# --------------------------------------------------------------------- мосты
def bridge_small():
    """Малый мост: 22 м, дубовый настил на каменных береговых устоях."""
    scene = Scene("BridgeSmall")
    scene.material("Mat_masonry", (0.72, 0.78, 0.66), "mossy_masonry", 0.95)
    scene.material("Mat_coping", (0.66, 0.70, 0.70), "wet_stone", 0.72, 0.05)
    scene.material("Mat_timber", (0.68, 0.60, 0.52), "bridge_timber", 0.95)
    scene.material("Mat_beam", (0.45, 0.40, 0.35), "bridge_timber", 0.98)

    span = 22.0
    # Ширина настила = полотно + обочины + внешняя кромка ленты дороги
    # (2 * (3.9 + 1.2 + 1.5)) с запасом: парапет стоит СНАРУЖИ полотна,
    # иначе он прорастал бы сквозь гравий.
    width = 14.2
    scene.box("Deck", (span, 0.55, width), "Mat_timber", (0.0, -0.28, 0.0))
    for sign in (-1.0, 1.0):
        scene.box("SideBeam_%d" % (0 if sign < 0 else 1), (span, 0.58, 0.42), "Mat_beam",
                  (0.0, -0.62, sign * (width * 0.5 - 0.2)))
    for i in range(7):
        x = -9.0 + 3.0 * i
        scene.box("CrossBeam_%d" % i, (0.36, 0.52, width - 0.5), "Mat_beam",
                  (x, -0.78, 0.0), (0.0, 0.0, 0.0))
    for sign in (-1.0, 1.0):
        z = sign * (width * 0.5 - 0.12)
        side = "L" if sign < 0 else "R"
        scene.box("Parapet_%s" % side, (span, 0.92, 0.44), "Mat_masonry", (0.0, 0.46, z))
        scene.box("Coping_%s" % side, (span, 0.16, 0.60), "Mat_coping", (0.0, 1.00, z))
        for i in range(6):
            x = -8.75 + 3.5 * i
            scene.box("Post_%s_%d" % (side, i), (0.34, 1.32, 0.62), "Mat_masonry",
                      (x, 0.66, z))
            scene.box("PostCap_%s_%d" % (side, i), (0.44, 0.14, 0.72), "Mat_coping",
                      (x, 1.39, z))
    for sign in (-1.0, 1.0):
        x = sign * (span * 0.5 + 1.1)
        scene.box("Abutment_%d" % (0 if sign < 0 else 1), (2.4, 5.2, width + 1.6),
                  "Mat_masonry", (x, -2.7, 0.0))
        for z_sign in (-1.0, 1.0):
            scene.box("Wing_%d_%d" % (0 if sign < 0 else 1, 0 if z_sign < 0 else 1),
                      (3.4, 3.6, 0.8), "Mat_masonry",
                      (sign * (span * 0.5 + 2.3), -1.4, z_sign * (width * 0.5 + 0.2)),
                      (0.0, sign * z_sign * 28.0, 0.0))

    # Коллизия не должна вылезать на полотно:
    #   * парапет — за внешней кромкой ленты дороги (±6,6 м), иначе машина
    #     цепляет его краем колеи;
    #   * пятка опоры — ниже полотна, иначе на торце моста получается
    #     невидимая ступенька в 3 см;
    #   * настил — сплошной «пол» под лентой, чтобы пролёт оставался
    #     проезжим даже там, где лента над прорезанным руслом провисает.
    parapet_z = width * 0.5 + 0.15
    shapes = []
    for sign in (-1.0, 1.0):
        key = "ParapetL" if sign < 0 else "ParapetR"
        shapes.append((key, (span, 1.6, 0.7), (0.0, 0.8, sign * parapet_z)))
    shapes.append(("Deck", (span, 0.5, width - 0.8), (0.0, -0.27, 0.0)))
    for sign in (-1.0, 1.0):
        shapes.append(("Abutment" + ("L" if sign < 0 else "R"),
                       (2.6, 5.4, width + 1.8), (sign * (span * 0.5 + 1.1), -2.85, 0.0)))
    scene.body("Collision", shapes)
    write("bridge_small", scene)


def arch_ring(scene, span_centre, radius, deck_bottom, thickness, width, prefix):
    """Каменная арка из сегментов: полукруг под настилом."""
    segments = 10
    centre_y = deck_bottom - radius + thickness * 0.35
    for i in range(segments):
        angle = math.pi * (i + 0.5) / segments
        x = span_centre + radius * math.cos(angle)
        y = centre_y + radius * math.sin(angle)
        chord = 2.0 * radius * math.tan(math.pi / (2.0 * segments)) * 1.25
        scene.box("%s_%d" % (prefix, i), (max(chord, 0.6), thickness, width),
                  "Mat_masonry", (x, y, 0.0), (0.0, 0.0, math.degrees(angle) + 90.0))


def bridge_large():
    """Большой мост: 46 м, три каменные опоры и две полуциркульные арки."""
    scene = Scene("BridgeLarge")
    scene.material("Mat_masonry", (0.70, 0.76, 0.64), "mossy_masonry", 0.95)
    scene.material("Mat_coping", (0.62, 0.66, 0.66), "wet_stone", 0.68, 0.06)
    scene.material("Mat_timber", (0.60, 0.53, 0.46), "bridge_timber", 0.95)
    scene.material("Mat_slate", (0.55, 0.58, 0.60), "wet_slate", 0.72)

    span = 46.0
    width = 15.8
    deck_bottom = -0.5
    scene.box("Deck", (span, 0.52, width), "Mat_timber", (0.0, -0.26, 0.0))
    scene.box("DeckEdge_L", (span, 0.30, 0.55), "Mat_slate", (0.0, -0.05, -(width * 0.5 + 0.1)))
    scene.box("DeckEdge_R", (span, 0.30, 0.55), "Mat_slate", (0.0, -0.05, width * 0.5 + 0.1))

    pier_x = [-15.0, 0.0, 15.0]
    for i, x in enumerate(pier_x):
        scene.box("Pier_%d" % i, (3.4, 12.5, width + 1.6), "Mat_masonry", (x, -6.7, 0.0))
        scene.box("PierCap_%d" % i, (4.2, 0.5, width + 2.2), "Mat_coping", (x, -0.75, 0.0))
        scene.box("Cutwater_%d" % i, (1.4, 9.0, 2.4), "Mat_masonry",
                  (x - 2.2, -6.0, 0.0), (0.0, 0.0, 0.0))
    arch_ring(scene, -7.5, 6.9, deck_bottom, 1.1, width + 0.6, "ArchL")
    arch_ring(scene, 7.5, 6.9, deck_bottom, 1.1, width + 0.6, "ArchR")

    for sign in (-1.0, 1.0):
        z = sign * (width * 0.5 - 0.15)
        side = "L" if sign < 0 else "R"
        scene.box("Parapet_%s" % side, (span, 1.12, 0.52), "Mat_masonry", (0.0, 0.56, z))
        scene.box("Coping_%s" % side, (span, 0.18, 0.70), "Mat_coping", (0.0, 1.21, z))
        for i in range(9):
            x = -20.0 + 5.0 * i
            scene.box("Buttress_%s_%d" % (side, i), (0.9, 1.6, 0.78), "Mat_masonry",
                      (x, 0.80, z + sign * 0.35))
    for sign in (-1.0, 1.0):
        scene.box("Abutment_%d" % (0 if sign < 0 else 1), (4.2, 13.5, width + 2.4),
                  "Mat_masonry", (sign * (span * 0.5 + 1.8), -7.2, 0.0))
        for z_sign in (-1.0, 1.0):
            scene.box("Wing_%d_%d" % (0 if sign < 0 else 1, 0 if z_sign < 0 else 1),
                      (5.0, 4.6, 0.9), "Mat_masonry",
                      (sign * (span * 0.5 + 3.6), -2.0, z_sign * (width * 0.5 + 0.4)),
                      (0.0, sign * z_sign * 32.0, 0.0))

    shapes = []
    for sign in (-1.0, 1.0):
        z = sign * (width * 0.5 + 0.15)
        shapes.append(("Parapet" + ("L" if sign < 0 else "R"),
                       (span, 1.9, 0.9), (0.0, 0.95, z)))
    shapes.append(("Deck", (span, 0.5, width - 0.8), (0.0, -0.27, 0.0)))
    for i, x in enumerate(pier_x):
        shapes.append(("Pier%d" % i, (3.6, 2.0, width + 1.8), (x, -1.6, 0.0)))
    for sign in (-1.0, 1.0):
        shapes.append(("Abutment" + ("L" if sign < 0 else "R"),
                       (4.4, 13.6, width + 2.6), (sign * (span * 0.5 + 1.8), -7.2, 0.0)))
    scene.body("Collision", shapes)
    write("bridge_large", scene)


# --------------------------------------------------------------------- берег
def river_bank_rock():
    """Мокрый валун у воды: три сросшихся камня со мхом."""
    scene = Scene("RiverBankRock")
    scene.material("Mat_slate", (0.72, 0.76, 0.72), "wet_slate", 0.62, 0.04)
    scene.material("Mat_moss", (0.62, 0.72, 0.52), "mossy_masonry", 0.98)
    scene.sphere("Rock_A", 1.05, 1.5, 7, 3, "Mat_slate", (0.0, 0.52, 0.0))
    scene.sphere("Rock_B", 0.72, 1.1, 6, 3, "Mat_slate", (0.85, 0.34, 0.25))
    scene.sphere("Rock_C", 0.55, 0.85, 6, 2, "Mat_slate", (-0.72, 0.26, -0.30))
    scene.sphere("Moss_Cap", 0.62, 0.22, 6, 2, "Mat_moss", (0.1, 0.86, 0.05))
    write("river_bank_rock", scene)


def dry_stone_wall():
    """Модуль сухой кладки (3 м): UK-стенка по берегу и обочине."""
    scene = Scene("DryStoneWall")
    scene.material("Mat_masonry", (0.66, 0.72, 0.62), "mossy_masonry", 0.97)
    scene.material("Mat_coping", (0.58, 0.62, 0.60), "wet_stone", 0.8)
    length = 3.0
    rows = [(0.18, 0.36), (0.56, 0.34), (0.92, 0.30)]
    index = 0
    for row, (y, height) in enumerate(rows):
        count = 3 if row % 2 == 0 else 2
        block = length / count
        for i in range(count):
            x = -length * 0.5 + block * (i + 0.5)
            inset = 0.02 * ((i + row) % 3)
            scene.box("Stone_%d" % index, (block - 0.05, height, 0.56 - inset * 2),
                      "Mat_masonry", (x, y, 0.0))
            index += 1
    for i in range(5):
        x = -length * 0.5 + 0.3 + 0.6 * i
        scene.box("Coping_%d" % i, (0.58, 0.16, 0.66), "Mat_coping", (x, 1.14, 0.0))
    scene.body("Collision", [("Wall", (length, 1.2, 0.62), (0.0, 0.6, 0.0))], layer=2)
    write("dry_stone_wall", scene)


def main():
    os.makedirs(PROPS_DIR, exist_ok=True)
    print("UK-компоненты → scenes/props/")
    bridge_small()
    bridge_large()
    river_bank_rock()
    dry_stone_wall()
    print("Готово.")


if __name__ == "__main__":
    main()
