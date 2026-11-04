"""Собирает сцены ассетов обстановки scenes/props/*.tscn.

Зачем: раньше лес, кусты и камни «собирались» прямо в коде rally_stage.gd —
открыть и поправить такой пропс в редакторе было нельзя. Теперь каждый пропс —
обычная сцена: открыли, подвигали меши, поменяли материал — и он таким же
уезжает в процедурную расстановку (сцена один раз «запекается» в MultiMesh).

Файлы перезаписываются целиком, поэтому правки надо вносить сюда (или прямо
в .tscn — тогда этот скрипт больше не запускать).

Запуск:  python3 tools/make_prop_scenes.py
"""

import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROPS_DIR = os.path.join(ROOT, "scenes", "props")
TEX = "res://textures/environment/%s.png"


# ------------------------------------------------------------------ геометрия

def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def rot_x(deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return [[1.0, 0.0, 0.0], [0.0, c, -s], [0.0, s, c]]


def rot_y(deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return [[c, 0.0, s], [0.0, 1.0, 0.0], [-s, 0.0, c]]


def rot_z(deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return [[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]]


def num(value):
    text = "%.7f" % value
    text = text.rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


def transform(origin=(0.0, 0.0, 0.0), rot=(0.0, 0.0, 0.0)):
    """Transform3D из смещения и углов Эйлера (порядок Rz·Ry·Rx), в тексте .tscn."""
    basis = mat_mul(mat_mul(rot_z(rot[2]), rot_y(rot[1])), rot_x(rot[0]))
    parts = [num(basis[0][0]), num(basis[1][0]), num(basis[2][0]),
             num(basis[0][1]), num(basis[1][1]), num(basis[2][1]),
             num(basis[0][2]), num(basis[1][2]), num(basis[2][2]),
             num(origin[0]), num(origin[1]), num(origin[2])]
    return "Transform3D(%s)" % ", ".join(parts)


class Material(object):
    def __init__(self, key, color, texture, roughness=0.95, specular=0.28):
        self.key = key
        self.color = color
        self.texture = texture
        self.roughness = roughness
        self.specular = specular

    def text(self):
        return (
            '[sub_resource type="StandardMaterial3D" id="%s"]\n'
            # ВАЖНО: в текстовом формате Color ждёт ЧЕТЫРЕ аргумента.
            # Color(r, g, b) движок не читает: «Expected 4 arguments».
            'albedo_color = Color(%s, 1)\n'
            'albedo_texture = ExtResource("%s")\n'
            'roughness = %s\n'
            'specular = %s\n'
            'specular_mode = 2\n' % (
                self.key,
                ", ".join(num(c) for c in self.color),
                self.texture,
                num(self.roughness),
                num(self.specular),
            )
        )


class Mesh(object):
    """Один меш (Geometry3D) со своим материалом и положением в пропсе."""

    def __init__(self, key, kind, params, material, origin=(0.0, 0.0, 0.0), rot=(0.0, 0.0, 0.0)):
        self.key = key
        self.kind = kind
        self.params = params
        self.material = material
        self.origin = origin
        self.rot = rot

    def text(self):
        lines = ['[sub_resource type="%s" id="%s"]' % (self.kind, self.key)]
        lines.append("material = SubResource(\"%s\")" % self.material.key)
        for name, value in self.params:
            lines.append("%s = %s" % (name, value))
        return "\n".join(lines) + "\n"


def cyl(top, bottom, height, radial, rings=1):
    return [("top_radius", num(top)), ("bottom_radius", num(bottom)),
            ("height", num(height)), ("radial_segments", str(radial)),
            ("rings", str(rings))]


def sphere(radius, height, radial, rings):
    return [("radius", num(radius)), ("height", num(height)),
            ("radial_segments", str(radial)), ("rings", str(rings))]


def box(size):
    return [("size", "Vector3(%s)" % ", ".join(num(v) for v in size))]


def prop(name, root_name, meshes, materials, textures, extra_nodes=""):
    """Собирает текст .tscn из списка мешей и материалов."""
    blocks = []
    for texture in textures:
        blocks.append('[ext_resource type="Texture2D" path="%s" id="%s"]\n' % (texture[1], texture[0]))
    for material in materials:
        blocks.append(material.text())
    for mesh in meshes:
        blocks.append(mesh.text())
    nodes = ['[node name="%s" type="Node3D"]\n' % root_name]
    for mesh in meshes:
        nodes.append(
            '[node name="%s" type="MeshInstance3D" parent="."]\n'
            'transform = %s\n'
            'mesh = SubResource("%s")\n' % (mesh.key, transform(mesh.origin, mesh.rot), mesh.key)
        )
    if extra_nodes:
        nodes.append(extra_nodes)
    header = "[gd_scene format=3]\n"
    return header + "\n" + "\n".join(blocks) + "\n" + "\n".join(nodes)


def write(name, text):
    path = os.path.join(PROPS_DIR, name + ".tscn")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)
    print("  %-20s %d байт" % (name + ".tscn", len(text)))


# --------------------------------------------------------------------- пропсы

def build():
    out = {}

    # --- ель: ствол + два яруса кроны ---------------------------------------
    # ВАЖНО: оттенки подобраны под ФОТОГРАФИЧЕСКИЕ текстуры из
    # textures/environment/. Процедурные (tools/make_prop_textures.py) были
    # плоскими и гасились цветом — например покрышку красили в 0.28. Фото уже
    # несёт свой цвет, поэтому множители подняты ближе к единице. Если
    # перегенерировать текстуры процедурно, оттенки надо вернуть старые
    # (подобрать заново: tools/refine_prop_textures.py <папка> --tints).
    bark = Material("Mat_bark", (0.78, 0.69, 0.58), "tex_bark", 1.0)
    needles = Material("Mat_needles", (0.90, 1.00, 0.90), "tex_needles", 0.95)
    out["fir_tree"] = prop(
        "fir_tree", "FirTree",
        [
            Mesh("Mesh_trunk", "CylinderMesh", cyl(0.22, 0.32, 2.3, 6), bark, (0, 1.15, 0)),
            Mesh("Mesh_lower", "CylinderMesh", cyl(0.0, 1.70, 4.2, 7), needles, (0, 3.2, 0)),
            Mesh("Mesh_upper", "CylinderMesh", cyl(0.0, 1.15, 3.4, 7), needles, (0, 5.9, 0)),
        ],
        [bark, needles],
        [("tex_bark", TEX % "bark"), ("tex_needles", TEX % "needles")],
    )

    # --- куст ----------------------------------------------------------------
    out["bush"] = prop(
        "bush", "Bush",
        [
            Mesh("Mesh_main", "SphereMesh", sphere(0.95, 1.5, 6, 3), needles, (0, 0.75, 0)),
            Mesh("Mesh_side", "SphereMesh", sphere(0.60, 1.0, 6, 2), needles, (0.55, 0.45, 0.25)),
        ],
        [needles],
        [("tex_needles", TEX % "needles")],
    )

    # --- валун ---------------------------------------------------------------
    rock = Material("Mat_rock", (0.85, 0.88, 0.90), "tex_rock", 0.98)
    out["boulder"] = prop(
        "boulder", "Boulder",
        [
            Mesh("Mesh_main", "SphereMesh", sphere(1.2, 2.4, 7, 3), rock, (0, 1.15, 0)),
            Mesh("Mesh_chip", "SphereMesh", sphere(0.55, 0.9, 6, 2), rock, (1.0, 0.35, 0.45)),
        ],
        [rock],
        [("tex_rock", TEX % "rock")],
    )

    # --- травяной пучок ------------------------------------------------------
    blade = Material("Mat_grass", (0.94, 1.00, 0.90), "tex_grass_blade", 1.0)
    out["grass"] = prop(
        "grass", "GrassTuft",
        [
            Mesh("Mesh_blade_a", "CylinderMesh", cyl(0.0, 0.50, 0.55, 5), blade, (0, 0.28, 0)),
            Mesh("Mesh_blade_b", "CylinderMesh", cyl(0.0, 0.40, 0.45, 5), blade,
                 (0.24, 0.22, 0.10), (0, 0, -12)),
            Mesh("Mesh_blade_c", "CylinderMesh", cyl(0.0, 0.42, 0.50, 5), blade,
                 (-0.22, 0.25, -0.12), (0, 0, 14)),
        ],
        [blade],
        [("tex_grass_blade", TEX % "grass_blade")],
    )

    # --- пень ----------------------------------------------------------------
    cut = Material("Mat_wood_cut", (0.86, 0.74, 0.55), "tex_wood_cut", 0.96)
    out["stump"] = prop(
        "stump", "Stump",
        [
            Mesh("Mesh_side", "CylinderMesh", cyl(0.34, 0.38, 0.72, 7), bark, (0, 0.36, 0)),
            Mesh("Mesh_top", "CylinderMesh", cyl(0.33, 0.33, 0.06, 7), cut, (0, 0.73, 0)),
        ],
        [bark, cut],
        [("tex_bark", TEX % "bark"), ("tex_wood_cut", TEX % "wood_cut")],
    )

    # --- бревно: цилиндр лежит вдоль Z --------------------------------------
    out["log"] = prop(
        "log", "Log",
        [
            Mesh("Mesh_body", "CylinderMesh", cyl(0.28, 0.32, 3.2, 7), bark, (0, 0.32, 0), (90, 0, 0)),
            Mesh("Mesh_cap_a", "CylinderMesh", cyl(0.31, 0.31, 0.10, 7), cut, (0, 0.32, 1.6), (90, 0, 0)),
            Mesh("Mesh_cap_b", "CylinderMesh", cyl(0.31, 0.31, 0.10, 7), cut, (0, 0.32, -1.6), (90, 0, 0)),
        ],
        [bark, cut],
        [("tex_bark", TEX % "bark"), ("tex_wood_cut", TEX % "wood_cut")],
    )

    # --- сухое дерево --------------------------------------------------------
    dry = Material("Mat_bark_dry", (1.00, 0.97, 0.92), "tex_bark_dry", 1.0)
    out["dead_tree"] = prop(
        "dead_tree", "DeadTree",
        [
            Mesh("Mesh_trunk", "CylinderMesh", cyl(0.16, 0.36, 4.4, 6), dry, (0, 2.2, 0)),
            Mesh("Mesh_branch_a", "CylinderMesh", cyl(0.04, 0.11, 1.7, 5), dry, (0.50, 3.10, 0.0), (0, 0, -55)),
            Mesh("Mesh_branch_b", "CylinderMesh", cyl(0.04, 0.10, 1.5, 5), dry, (-0.45, 3.70, 0.10), (0, 0, 48)),
            Mesh("Mesh_branch_c", "CylinderMesh", cyl(0.03, 0.08, 1.2, 5), dry, (0.15, 4.20, 0.35), (40, 0, -20)),
        ],
        [dry],
        [("tex_bark_dry", TEX % "bark_dry")],
    )

    # --- берёза --------------------------------------------------------------
    birch = Material("Mat_birch", (0.98, 0.98, 0.96), "tex_birch_bark", 0.92)
    leaf = Material("Mat_leaves", (0.94, 1.00, 0.90), "tex_leaves", 0.95)
    out["birch_tree"] = prop(
        "birch_tree", "BirchTree",
        [
            Mesh("Mesh_trunk", "CylinderMesh", cyl(0.14, 0.20, 5.0, 6), birch, (0, 2.5, 0)),
            Mesh("Mesh_crown_a", "SphereMesh", sphere(1.25, 2.0, 7, 3), leaf, (0.30, 5.30, 0.15)),
            Mesh("Mesh_crown_b", "SphereMesh", sphere(0.95, 1.6, 7, 3), leaf, (-0.45, 6.20, -0.20)),
        ],
        [birch, leaf],
        [("tex_birch_bark", TEX % "birch_bark"), ("tex_leaves", TEX % "leaves")],
    )

    # --- папоротник ----------------------------------------------------------
    fern = Material("Mat_fern", (0.93, 1.00, 0.90), "tex_fern", 1.0)
    out["fern"] = prop(
        "fern", "Fern",
        [
            Mesh("Mesh_frond_a", "CylinderMesh", cyl(0.0, 0.45, 0.70, 5), fern, (0, 0.35, 0), (0, 0, -10)),
            Mesh("Mesh_frond_b", "CylinderMesh", cyl(0.0, 0.38, 0.60, 5), fern, (0.28, 0.30, 0.16), (25, 0, -25)),
            Mesh("Mesh_frond_c", "CylinderMesh", cyl(0.0, 0.38, 0.60, 5), fern, (-0.24, 0.30, -0.18), (-25, 0, 25)),
            Mesh("Mesh_frond_d", "CylinderMesh", cyl(0.0, 0.34, 0.55, 5), fern, (0.05, 0.28, 0.32), (35, 0, 8)),
        ],
        [fern],
        [("tex_fern", TEX % "fern")],
    )

    # --- рулон сена: цилиндр лежит вдоль X ----------------------------------
    straw = Material("Mat_straw", (1.00, 0.96, 0.88), "tex_straw", 1.0)
    out["hay_bale"] = prop(
        "hay_bale", "HayBale",
        [
            Mesh("Mesh_bale", "CylinderMesh", cyl(0.85, 0.85, 1.5, 10), straw, (0, 0.85, 0), (0, 0, 90)),
            Mesh("Mesh_cap_a", "CylinderMesh", cyl(0.84, 0.84, 0.06, 10), straw, (0.75, 0.85, 0), (0, 0, 90)),
            Mesh("Mesh_cap_b", "CylinderMesh", cyl(0.84, 0.84, 0.06, 10), straw, (-0.75, 0.85, 0), (0, 0, 90)),
        ],
        [straw],
        [("tex_straw", TEX % "straw")],
    )

    # --- стопка покрышек -----------------------------------------------------
    tire = Material("Mat_tire", (0.97, 0.97, 1.00), "tex_tire", 0.88)
    out["tire_stack"] = prop(
        "tire_stack", "TireStack",
        [
            Mesh("Mesh_tire_a", "CylinderMesh", cyl(0.44, 0.44, 0.30, 10), tire, (0, 0.15, 0)),
            Mesh("Mesh_tire_b", "CylinderMesh", cyl(0.42, 0.42, 0.30, 10), tire, (0.03, 0.45, 0.02), (0, 15, 0)),
            Mesh("Mesh_tire_c", "CylinderMesh", cyl(0.40, 0.40, 0.30, 10), tire, (-0.02, 0.74, -0.02), (0, -12, 0)),
        ],
        [tire],
        [("tex_tire", TEX % "tire")],
    )

    # --- дощатый забор -------------------------------------------------------
    plank = Material("Mat_plank", (1.00, 0.96, 0.90), "tex_plank", 0.97)
    out["wooden_fence"] = prop(
        "wooden_fence", "WoodenFence",
        [
            Mesh("Mesh_rail_top", "BoxMesh", box((2.6, 0.14, 0.08)), plank, (0, 1.05, 0)),
            Mesh("Mesh_rail_low", "BoxMesh", box((2.6, 0.14, 0.08)), plank, (0, 0.62, 0)),
            Mesh("Mesh_post_a", "BoxMesh", box((0.13, 1.3, 0.13)), plank, (-1.2, 0.65, 0)),
            Mesh("Mesh_post_b", "BoxMesh", box((0.13, 1.3, 0.13)), plank, (0, 0.65, 0)),
            Mesh("Mesh_post_c", "BoxMesh", box((0.13, 1.3, 0.13)), plank, (1.2, 0.65, 0)),
        ],
        [plank],
        [("tex_plank", TEX % "plank")],
    )

    # --- группа камней -------------------------------------------------------
    mossy = Material("Mat_rock_mossy", (0.97, 1.00, 0.96), "tex_rock_mossy", 0.98)
    out["rock_cluster"] = prop(
        "rock_cluster", "RockCluster",
        [
            Mesh("Mesh_rock_a", "SphereMesh", sphere(0.90, 1.4, 6, 3), mossy, (0, 0.60, 0)),
            Mesh("Mesh_rock_b", "SphereMesh", sphere(0.55, 0.9, 6, 2), mossy, (0.85, 0.35, 0.35)),
            Mesh("Mesh_rock_c", "SphereMesh", sphere(0.38, 0.6, 6, 2), mossy, (-0.60, 0.25, -0.45)),
        ],
        [mossy],
        [("tex_rock_mossy", TEX % "rock_mossy")],
    )

    # --- насыпь грунта -------------------------------------------------------
    dirt = Material("Mat_dirt", (1.00, 0.95, 0.88), "tex_dirt", 1.0)
    out["dirt_mound"] = prop(
        "dirt_mound", "DirtMound",
        [
            Mesh("Mesh_mound", "SphereMesh", sphere(1.5, 0.8, 7, 2), dirt, (0, 0.25, 0)),
            Mesh("Mesh_pebble", "SphereMesh", sphere(0.30, 0.4, 5, 2), dirt, (1.10, 0.12, 0.50)),
        ],
        [dirt],
        [("tex_dirt", TEX % "dirt")],
    )

    # --- мешки с песком ------------------------------------------------------
    burlap = Material("Mat_burlap", (0.80, 0.72, 0.52), "tex_burlap", 1.0)
    out["sandbag_barrier"] = prop(
        "sandbag_barrier", "SandbagBarrier",
        [
            Mesh("Mesh_bag_a", "BoxMesh", box((1.3, 0.32, 0.45)), burlap, (-0.35, 0.16, 0.0)),
            Mesh("Mesh_bag_b", "BoxMesh", box((1.3, 0.32, 0.45)), burlap, (0.35, 0.16, 0.02)),
            Mesh("Mesh_bag_c", "BoxMesh", box((1.2, 0.30, 0.42)), burlap, (0.0, 0.47, -0.02)),
            Mesh("Mesh_bag_d", "BoxMesh", box((0.6, 0.28, 0.40)), burlap, (-0.30, 0.75, 0.05)),
        ],
        [burlap],
        [("tex_burlap", TEX % "burlap")],
    )

    # --- рекламный щит -------------------------------------------------------
    banner = Material("Mat_banner", (0.95, 0.96, 0.97), "tex_banner", 0.85)
    out["sponsor_banner"] = prop(
        "sponsor_banner", "SponsorBanner",
        [
            Mesh("Mesh_post_l", "BoxMesh", box((0.09, 1.9, 0.09)), plank, (-0.85, 0.95, 0)),
            Mesh("Mesh_post_r", "BoxMesh", box((0.09, 1.9, 0.09)), plank, (0.85, 0.95, 0)),
            Mesh("Mesh_board", "BoxMesh", box((1.9, 0.85, 0.06)), banner, (0, 1.65, 0)),
        ],
        [plank, banner],
        [("tex_plank", TEX % "plank"), ("tex_banner", TEX % "banner")],
    )

    return out


def main():
    os.makedirs(PROPS_DIR, exist_ok=True)
    print("Сцены ассетов → scenes/props/")
    for name, text in build().items():
        write(name, text)
    print("Готово.")


if __name__ == "__main__":
    main()
