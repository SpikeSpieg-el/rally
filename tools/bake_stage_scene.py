"""Запекает ассеты трассы в сцену scenes/rally_stage.tscn.

Что делает:
  1) создаёт сцены ассетов scenes/props/{fir_tree,boulder,bush}.tscn
     (если их ещё нет) — из тех же мешей, что были в data/props/*.tres;
  2) расставляет ассеты вдоль дороги как ОБЫЧНЫЕ УЗЛЫ сцены (узел Props),
     чтобы их можно было двигать/удалять/добавлять руками в 3D-вьюпорте;
  3) кладёт кривую трассы прямо в узел Route (Path3D) — тянуть точки можно
     в 3D, без ползунков в .tres.

Позиции детерминированные (фиксированный seed), высота Y пересчитывается
движком при сборке трассы («Посадить ассеты на землю» вызывается автоматически).

Запуск:  python3 tools/bake_stage_scene.py
"""
import math
import os
import random
import re

import stage_model as model

ROOT = "/home/user/rally"
SCENE = ROOT + "/scenes/rally_stage.tscn"
PROPS_DIR = ROOT + "/scenes/props"

# ---------------------------------------------------------------- сцены ассетов
PROP_SCENES = {
    "fir_tree": '''[gd_scene load_steps=3 format=3]

[sub_resource type="StandardMaterial3D" id="Material_fir"]
albedo_color = Color(0.075, 0.215, 0.115, 1)
roughness = 0.95
specular_mode = 2

[sub_resource type="CylinderMesh" id="Mesh_fir"]
material = SubResource("Material_fir")
top_radius = 0.0
bottom_radius = 1.7
height = 6.5
radial_segments = 7
rings = 1

[node name="FirTree" type="Node3D"]

[node name="Mesh" type="MeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 3.25, 0)
mesh = SubResource("Mesh_fir")
''',
    "boulder": '''[gd_scene load_steps=3 format=3]

[sub_resource type="StandardMaterial3D" id="Material_rock"]
albedo_color = Color(0.31, 0.32, 0.33, 1)
roughness = 0.98
specular_mode = 2

[sub_resource type="SphereMesh" id="Mesh_rock"]
material = SubResource("Material_rock")
radius = 1.2
height = 2.4
radial_segments = 7
rings = 3

[node name="Boulder" type="Node3D"]

[node name="Mesh" type="MeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.2, 0)
mesh = SubResource("Mesh_rock")
''',
    "bush": '''[gd_scene load_steps=3 format=3]

[sub_resource type="StandardMaterial3D" id="Material_bush"]
albedo_color = Color(0.13, 0.32, 0.14, 1)
roughness = 1.0
specular_mode = 2

[sub_resource type="SphereMesh" id="Mesh_bush"]
material = SubResource("Material_bush")
radius = 0.9
height = 1.4
radial_segments = 6
rings = 3

[node name="Bush" type="Node3D"]

[node name="Mesh" type="MeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.7, 0)
mesh = SubResource("Mesh_bush")
''',
}


def ensure_prop_scenes():
    os.makedirs(PROPS_DIR, exist_ok=True)
    for name, text in PROP_SCENES.items():
        path = "%s/%s.tscn" % (PROPS_DIR, name)
        if not os.path.exists(path):
            with open(path, "w") as f:
                f.write(text)
            print("создана сцена ассета:", path)


# ---------------------------------------------------------------- расстановка
def curvature(net, d):
    a = net.direction_at(max(0.0, d - 6.0))
    b = net.direction_at(min(net.length, d + 6.0))
    dot = max(-1.0, min(1.0, a[0] * b[0] + a[2] * b[2]))
    return math.degrees(math.acos(dot))


def basis_text(yaw, scale, squash_y=1.0):
    """Transform3D из yaw-поворота и масштаба (в тексте сцены)."""
    c, s = math.cos(yaw), math.sin(yaw)
    # basis.x = (cos, 0, -sin), basis.z = (sin, 0, cos)
    xx, xy, xz = c * scale, 0.0, -s * scale
    yx, yy, yz = 0.0, scale * squash_y, 0.0
    zx, zy, zz = s * scale, 0.0, c * scale
    return (xx, xy, xz, yx, yy, yz, zx, zy, zz)


def fmt(values):
    return ", ".join("%.5f" % v for v in values)


class Placer:
    def __init__(self, stage, rng):
        self.stage = stage
        self.net = stage.net
        self.rng = rng
        self.nodes = []
        self.counter = {}

    def add(self, kind, scene_id, x, z, yaw, scale, squash_y=1.0, group="Props"):
        self.counter[kind] = self.counter.get(kind, 0) + 1
        name = "%s_%03d" % (kind, self.counter[kind])
        y = self.stage.ground(x, z)
        basis = basis_text(yaw, scale, squash_y)
        line = (
            '\n[node name="%s" parent="Props" instance=ExtResource("%s") groups=["%s"]]\n'
            "transform = Transform3D(%s, %.4f, %.4f, %.4f)\n"
            % (name, scene_id, group, fmt(basis), x, y, z)
        )
        self.nodes.append(line)

    def along_road(self, kind, scene_id, spacing, lateral_min, lateral_max,
                   scale_min, scale_max, squash_y=1.0, jitter=6.0, both_sides=True,
                   min_distance=12.0, skip_near_hairpin=None):
        d = min_distance
        while d < self.net.length - min_distance:
            if skip_near_hairpin is not None and skip_near_hairpin(d):
                d += spacing
                continue
            dist = d + self.rng.uniform(-jitter, jitter)
            dist = max(min_distance, min(self.net.length - min_distance, dist))
            center = self.net.point_at(dist)
            direction = self.net.direction_at(dist)
            side = (direction[2], 0.0, -direction[0])
            sides = (-1.0, 1.0) if both_sides else (1.0,)
            for sign in sides:
                lateral = self.rng.uniform(lateral_min, lateral_max) * sign
                x = center[0] + side[0] * lateral
                z = center[2] + side[2] * lateral
                if self.net.distance_to_road(x, z) < self.stage.cfg["corridor"] + 1.2:
                    continue
                self.add(kind, scene_id, x, z, self.rng.uniform(0.0, math.tau),
                         self.rng.uniform(scale_min, scale_max), squash_y)
            d += spacing

    def scattered(self, kind, scene_id, count, lateral_min, lateral_max,
                  scale_min, scale_max, squash_y=1.0):
        placed = 0
        guard = 0
        while placed < count and guard < count * 30:
            guard += 1
            dist = self.rng.uniform(10.0, self.net.length - 10.0)
            center = self.net.point_at(dist)
            direction = self.net.direction_at(dist)
            side = (direction[2], 0.0, -direction[0])
            lateral = self.rng.uniform(lateral_min, lateral_max)
            if self.rng.random() < 0.5:
                lateral = -lateral
            x = center[0] + side[0] * lateral
            z = center[2] + side[2] * lateral
            if self.net.distance_to_road(x, z) < lateral_min * 0.8:
                continue
            self.add(kind, scene_id, x, z, self.rng.uniform(0.0, math.tau),
                     self.rng.uniform(scale_min, scale_max), squash_y)
            placed += 1

    def signs_at_hairpins(self, scene_id):
        """Щиты перед медленными поворотами (внешняя сторона)."""
        d = 40.0
        placed = 0
        while d < self.net.length - 40.0 and placed < 16:
            if curvature(self.net, d) > 35.0:
                center = self.net.point_at(d)
                direction = self.net.direction_at(d)
                side = (direction[2], 0.0, -direction[0])
                for sign in (-1.0, 1.0):
                    lateral = (self.stage.cfg["corridor"] + 1.6) * sign
                    x = center[0] + side[0] * lateral
                    z = center[2] + side[2] * lateral
                    yaw = math.atan2(direction[0], direction[2]) + sign * math.pi * 0.5
                    self.add("Sign", scene_id, x, z, yaw, 1.0)
                    placed += 1
                d += 60.0
            else:
                d += 5.0


def build_props():
    stage = model.Stage()
    rng = random.Random(20251027)
    placer = Placer(stage, rng)
    # ели у дороги (вторая линия леса)
    placer.along_road("Pine", "pine_tree", 26.0, 8.0, 15.0, 0.85, 1.35, 1.1, jitter=7.0)
    # дальний лес
    placer.along_road("Fir", "fir_tree", 17.0, 18.0, 58.0, 0.8, 1.6, 1.2, jitter=8.0)
    # кусты по обочине
    placer.along_road("Bush", "bush", 30.0, 4.5, 10.0, 0.7, 1.5, 0.75, jitter=9.0)
    # валуны
    placer.scattered("Boulder", "boulder", 110, 9.0, 34.0, 0.5, 1.6, 0.7)
    # предупреждающие щиты
    placer.signs_at_hairpins("road_sign")
    return stage, "".join(placer.nodes)


# ---------------------------------------------------------------- сцена
def split_blocks(text):
    """Файл .tscn -> (префикс-шапка, [(заголовок, тело)]), заголовки начинаются с '['."""
    lines = text.split("\n")
    blocks = []
    header = []
    for line in lines:
        if line.startswith("["):
            blocks.append([line, []])
        elif blocks:
            blocks[-1][1].append(line)
        else:
            header.append(line)
    blocks = [(b[0], "\n".join(b[1])) for b in blocks]
    if blocks and blocks[0][0].startswith("[gd_scene"):
        header = [blocks[0][0]] + header
        blocks = blocks[1:]
    return header, blocks


def join_blocks(header, blocks):
    out = "\n".join(header).rstrip("\n")
    for head, body in blocks:
        out += "\n" + head + "\n"
        if body.strip("\n"):
            out += body.strip("\n") + "\n"
    while "\n\n\n" in out:
        out = out.replace("\n\n\n", "\n\n")
    # Godot не ставит пустую строку между строками ext_resource
    out = re.sub(r'(\[ext_resource [^\n]*\])\n\n(?=\[ext_resource )', r'\1\n', out)
    return out.rstrip("\n") + "\n"


def patch_scene(stage, props_text):
    text = open(SCENE).read()
    header, blocks = split_blocks(text)

    kept = []
    for head, body in blocks:
        name_match = re.match(r'\[node name="([^"]+)"(?: type="([^"]*)")?(?: parent="([^"]*)")?', head)
        if name_match:
            name = name_match.group(1)
            parent = name_match.group(3) or "."
            if name == "Props" or parent == "Props":
                continue                      # старые запечённые ассеты
        if head.startswith('[sub_resource type="Curve3D" id="Curve3D_route"]'):
            continue                          # прежняя вложенная кривая
        if head.startswith('[node name="Route"'):
            body = re.sub(r'^curve = .*\n?', "", body, flags=re.M)
            body = re.sub(r'^curve = .*\n?', "", body, flags=re.M)
            body = 'curve = ExtResource("4_route")\n' + body
            head = '[node name="Route" type="Path3D" parent="."]'
        kept.append([head, body])

    if 'path="res://data/tracks/stage_forest_route.tres"' not in text:
        raise SystemExit("в сцене нет ext_resource на кривую трассы")

    # ext_resource на сцены ассетов
    ext_lines = []
    for scene in ["pine_tree", "fir_tree", "boulder", "bush", "road_sign"]:
        line = '[ext_resource type="PackedScene" path="res://scenes/props/%s.tscn" id="%s"]' % (
            scene, scene)
        if ('ExtResource("%s")' % scene) in props_text and line not in text:
            ext_lines.append(line)
    if ext_lines:
        insert_at = next((i for i, b in enumerate(kept) if b[0].startswith("[ext_resource"))
                         if any(b[0].startswith("[ext_resource") for b in kept) else 0)
        # вставляем после последнего ext_resource
        last_ext = max((i for i, b in enumerate(kept) if b[0].startswith("[ext_resource")),
                       default=None)
        index = (last_ext + 1) if last_ext is not None else 0
        for offset, line in enumerate(ext_lines):
            kept.insert(index + offset, [line, ""])

    # ассеты: узел Props + запечённые узлы
    kept.append(['[node name="Props" type="Node3D" parent="."]', ""])
    header_props, prop_blocks = split_blocks(props_text)
    kept.extend([[b[0], b[1]] for b in prop_blocks])

    ext_count = len(re.findall(r"^\[ext_resource ", join_blocks(header, kept), re.M))
    sub_count = len(re.findall(r"^\[sub_resource ", join_blocks(header, kept), re.M))
    header = [re.sub(r"^\[gd_scene load_steps=\d+",
                     "[gd_scene load_steps=%d" % (ext_count + sub_count + 1),
                     header[0], count=1)]
    open(SCENE, "w").write(join_blocks(header, kept))
    return ext_count, sub_count


def curve_resource_body(ctrl):
    values = []
    for p_in, p_out, pos in ctrl:
        for point in (p_in, p_out, pos):
            values.append("%.4f, %.4f, %.4f" % point)
    return (
        "bake_interval = 0.5\n"
        "_data = {\n"
        '"points": PackedVector3Array(%s),\n'
        '"tilts": PackedFloat32Array(%s)\n'
        "}\n" % (", ".join(values), ", ".join(["0"] * len(ctrl)))
    )


def main():
    ensure_prop_scenes()
    stage, props = build_props()
    ext_count, sub_count = patch_scene(stage, props)
    nodes = props.count("[node name=")
    print("ассетов в сцене: %d" % nodes)
    print("ext/base resources: %d / %d" % (ext_count, sub_count))
    print("готово:", SCENE)


if __name__ == "__main__":
    main()
