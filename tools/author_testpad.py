"""Авторинг тест-полигона: лёгкое кольцо, чтобы попадать в заезд за секунды.

Зачем это нужно. Любая настоящая трасса — это километры полотна, рельефа,
леса и запечённой обстановки: чтобы проверить погоду, эффект скорости,
пресеты камеры или новый пропс, приходилось ждать загрузку и ехать до
интересного места. Полигон закрывает эту дыру:

  * замкнутое кольцо 1331 м (две прямые по 100 м и два поворота R=110):
    круг проходится за ~40 с, и «интересное место» всегда под колёсами;
  * полотно идеально плоское — ноль бугров, ноль гребней, ноль рельефа:
    любой эффект видно в чистом виде, без «а может, это яма»;
  * дорога широкая (12 м), обочина 2.5 м, сцепление трассы 1.0;
  * рельеф грубый (cell 3 м) и узкий (margin 60 м): меш земли в разы меньше,
    чем у любой боевой трассы, а загрузка — почти мгновенная;
  * вдоль обеих прямых стоят ВСЕ пропсы игры (54 вида) — витрина в игре,
    а не отдельная сцена-лаборатория;
  * трасса не потоковая (stream_world = false, use_baked_props = true).

Скрипт детерминирован: один запуск — один и тот же полигон. Он пишет
кривую, ресурс трассы и сцену участка, регистрирует трассу в
`data/rally_game_config.tres` и в конце ПРОВЕРЯЕТ результат: кольцо должно
быть замкнутым, без излома на стыке, плоским и коротким, а сцена — собрана
из существующих ресурсов и содержать все пропсы.

Запуск:  python3 tools/author_testpad.py
"""

import hashlib
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import route_kit as kit  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROUTE_PATH = os.path.join(ROOT, "data/tracks/stage_testpad_route.tres")
TRACK_PATH = os.path.join(ROOT, "data/tracks/stage_testpad.tres")
SCENE_PATH = os.path.join(ROOT, "scenes/rally_stage_testpad.tscn")
CONFIG_PATH = os.path.join(ROOT, "data/rally_game_config.tres")
PROPS_DIR = os.path.join(ROOT, "scenes/props")

TRACK_ID = "test_polygon"
TRACK_NAME = "ТЕСТ-ПОЛИГОН"
TRACK_DESCRIPTION = (
    "Лёгкое кольцо 1.3 км для проверки эффектов, погоды, камеры и пропсов.\n"
    "Полотно плоское и широкое, рельефа нет: любой эффект видно сразу.\n"
    "Вдоль обеих прямых выставлены все пропсы игры."
)

# ---------------------------------------------------------------- геометрия
RADIUS = 110.0          # радиус поворотов, м
FLAT = 100.0            # короткая «полка» кольца (низ и верх), м
SIDE = 2.0 * RADIUS     # длинная прямая (бока), м
LOOP_LENGTH = 2.0 * FLAT + 2.0 * SIDE + 2.0 * math.pi * RADIUS

# Витки трассы не должны подходить друг к другу: у кольца это ширина.
MIN_GAP = 2.0 * RADIUS

# ------------------------------------------------------------- оформление
ROAD_HALF_WIDTH = 6.0
ROAD_SHOULDER = 2.5
ROAD_STEP = 2.0
TERRAIN_MARGIN = 60.0
TERRAIN_CELL = 3.0
SCENERY_DENSITY = 0.35
CAP = 5                  # бит на канал — палитра PS1
TARGET_TIME = 45.0

# Витрина пропсов: две линии вдоль прямых, по 27 видов в каждой.
# Боковые прямые кольца стоят на x = FLAT + RADIUS (правая) и x = -RADIUS
# (левая), витрина — в 25 м от полотна, лицом к дороге.
SHOWCASE_INSET = 25.0
# Три линии по 18 видов: 11.8 м между соседями — даже дом и вертолёт не
# наезжают друг на друга. Крайние линии смотрят на полотно, средняя — внутрь.
SHOWCASE_ROWS = (
    # (x, z_начало, z_конец, поворот к дороге)
    (FLAT + RADIUS - SHOWCASE_INSET, 120.0, 320.0, -90.0),
    (FLAT / 2.0, 120.0, 320.0, -90.0),
    (-RADIUS + SHOWCASE_INSET, 320.0, 120.0, 90.0),
)
# Сцены, которые в витрину не годятся: это мостовые пролёты для рек.
SHOWCASE_SKIP = ("bridge_large", "bridge_small")


def color(r, g, b, a=1.0):
    return "Color(%s, %s, %s, %s)" % tuple(
        "%.4f" % v for v in (r, g, b, a)
    )


# Алфавит и основание — как в ResourceUID::id_to_text() движка Godot.
# Алгоритм тот же, что в tools/make_prop_textures.godot_uid(), но без numpy:
# авторинг полигона не должен тянуть обработку текстур.
UID_CHARS = "abcdefghijklmnopqrstuvwxyz0123456789"
UID_BASE = 36
UID_SALT = 0x5EED17


def godot_uid(text):
    """Детерминированный uid:// для нового ресурса (формат Godot 4)."""
    value = (int(hashlib.md5(text.encode("utf-8")).hexdigest()[:15], 16) ^ UID_SALT) % (2 ** 62)
    chars = ""
    while value:
        chars = UID_CHARS[value % UID_BASE] + chars
        value //= UID_BASE
    return "uid://" + chars


def read_uid(path):
    """uid ресурса: из шапки файла или из sidecar-файла `.uid` (скрипты)."""
    try:
        with open(path, encoding="utf-8") as handle:
            head = handle.readline()
    except OSError:
        head = ""
    found = re.search(r'uid="(uid://[^"]+)"', head)
    if found:
        return found.group(1)
    try:
        with open(path + ".uid", encoding="utf-8") as handle:
            sidecar = handle.read().strip()
    except OSError:
        return ""
    return sidecar if sidecar.startswith("uid://") else ""


def resource_uid(res_path):
    """uid ресурса: существующий файл главнее расчётного.

    Godot при пересохранении в редакторе выдаёт СВОЙ uid и прописывает его в
    ссылках. Если инструмент подставит пересчитанный хеш, ссылки повиснут,
    поэтому uid существующего файла — закон.
    """
    path = os.path.join(ROOT, res_path.replace("res://", ""))
    found = read_uid(path)
    if found:
        return found
    return godot_uid(res_path)


# ------------------------------------------------------------------ кривая
def build_route():
    """Задуманный контур: две прямые по FLAT и два бока по SIDE с дугами."""
    segs = [
        ("s", FLAT, 0.0),
        ("a", RADIUS, 90.0, 0.0, +1),
        ("s", SIDE, 0.0),
        ("a", RADIUS, 90.0, 0.0, +1),
        ("s", FLAT, 0.0),
        ("a", RADIUS, 90.0, 0.0, +1),
        ("s", SIDE, 0.0),
        ("a", RADIUS, 90.0, 0.0, +1),
    ]
    pts, length = kit.compose(segs, step=1.0)
    # Кольцо замыкается: последняя точка — ровно первая, без «щели» в полотне.
    pts[-1] = pts[0]
    ctrl = kit.select_controls(pts, max_gap=24.0, min_gap=12.0)
    if ctrl[-1] != ctrl[0]:
        ctrl.append(ctrl[0])
    ctrl[-1] = ctrl[0]
    return pts, ctrl, length


def write_route(ctrl):
    kit.write_curve(
        ctrl,
        ROUTE_PATH,
        uid=resource_uid("res://data/tracks/stage_testpad_route.tres"),
        closed=True,
    )


# ------------------------------------------------------------------ трасса
def track_text():
    route_uid = read_uid(ROUTE_PATH)
    lines = []
    lines.append(
        '[gd_resource type="Resource" script_class="RallyTrackConfig" '
        'format=3 uid="%s"]' % resource_uid("res://data/tracks/stage_testpad.tres")
    )
    lines.append("")
    lines.append('[ext_resource type="Script" path="res://scripts/data/rally_track_config.gd" id="track"]')
    lines.append('[ext_resource type="Curve3D" uid="%s" path="res://data/tracks/stage_testpad_route.tres" id="curve"]' % route_uid)
    lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("track")')
    lines.append('id = "%s"' % TRACK_ID)
    lines.append('display_name = "%s"' % TRACK_NAME)
    lines.append('description = "%s"' % TRACK_DESCRIPTION.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n"))
    lines.append('surface_name = "Асфальт"')
    lines.append("difficulty = 1")
    lines.append("target_time = %.1f" % TARGET_TIME)
    lines.append('stage_scene = "res://scenes/rally_stage_testpad.tscn"')
    lines.append("")
    lines.append('road_curve = ExtResource("curve")')
    lines.append("road_half_width = %.1f" % ROAD_HALF_WIDTH)
    lines.append("road_shoulder = %.1f" % ROAD_SHOULDER)
    lines.append("road_step = %.1f" % ROAD_STEP)
    lines.append("road_camber = 0.05")
    lines.append("offroad_grip = 0.75")
    lines.append("")
    lines.append("terrain_margin = %.1f" % TERRAIN_MARGIN)
    lines.append("terrain_cell = %.2f" % TERRAIN_CELL)
    lines.append("terrain_seed = 7701")
    # Рельефа нет вообще: эффекты и подвеску надо смотреть на чистом полотне.
    lines.append("hills_height = 0.0")
    lines.append("ridge_height = 0.0")
    lines.append("max_terrain_slope_deg = 25.0")
    lines.append("road_ditch_depth = 0.15")
    lines.append("detail_height = 0.15")
    lines.append("embankment_slope_deg = 22.0")
    lines.append("embankment_min_width = 4.0")
    lines.append("embankment_max_width = 18.0")
    lines.append("road_feature_height = 0.0")
    lines.append("road_feature_spacing = 320.0")
    lines.append("bumps_amplitude = 0.0")
    lines.append("bumps_roughness = 0.0")
    lines.append("bumps_cross = 0.0")
    lines.append("")
    lines.append("use_baked_props = true")
    lines.append("procedural_scenery = true")
    lines.append("scenery_density = %.2f" % SCENERY_DENSITY)
    lines.append("spawn_route_markers = true")
    lines.append("spawn_edge_posts = true")
    lines.append("spawn_checkpoints = true")
    lines.append("checkpoint_interval = 300.0")
    lines.append("stream_world = false")
    lines.append("procedural = false")
    lines.append("")
    lines.append("ground_color = %s" % color(0.30, 0.34, 0.27))
    lines.append("ground_color_2 = %s" % color(0.40, 0.44, 0.33))
    lines.append("rock_color = %s" % color(0.42, 0.43, 0.45))
    lines.append("road_color = %s" % color(0.20, 0.20, 0.22))
    lines.append("road_color_2 = %s" % color(0.30, 0.30, 0.32))
    lines.append("shoulder_color = %s" % color(0.32, 0.30, 0.24))
    lines.append("edge_post_color = %s" % color(0.90, 0.16, 0.10))
    lines.append("")
    lines.append("sky_top_color = %s" % color(0.28, 0.48, 0.80))
    lines.append("sky_horizon_color = %s" % color(0.78, 0.85, 0.92))
    lines.append("fog_color = %s" % color(0.76, 0.82, 0.88))
    lines.append("fog_near = 140.0")
    lines.append("fog_far = 420.0")
    lines.append("fog_density = 0.0")
    # night_mode не пишем: false — значение по умолчанию (так требует
    # tests/test_night_environment.py, иначе флаг ночи «размазывается»).
    lines.append("sun_color = %s" % color(1.0, 0.96, 0.88))
    lines.append("ambient_color = %s" % color(0.62, 0.68, 0.78))
    lines.append("ambient_energy = 0.85")
    lines.append("exposure = 1.05")
    lines.append("sun_energy = 1.45")
    lines.append("sun_pitch = -42.0")
    lines.append("sun_yaw = 35.0")
    lines.append("screen_space_ao = true")
    lines.append("volumetric_fog = false")
    lines.append("")
    lines.append("grip_scale = 1.0")
    lines.append("rolling_resistance_scale = 1.0")
    lines.append("")
    lines.append("ps1_style = true")
    lines.append("flat_shading = true")
    lines.append("dither_fog = true")
    lines.append("color_banding = %d" % CAP)
    lines.append("sky_flat = true")
    lines.append("enable_speed_fx = true")
    lines.append("")
    return "\n".join(lines)


# ------------------------------------------------------------------- сцена
def screen_material_lines():
    """Параметры ретро-экрана — ИЗ ШАБЛОНА, а не переписанные руками.

    Так числа в сцене полигона не расходятся с `scenes/effects/retro_screen.tscn`
    и с тестом, который сверяет все сцены с шаблоном эффекта скорости.
    """
    path = os.path.join(ROOT, "scenes/effects/retro_screen.tscn")
    params = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            stripped = line.strip()
            if stripped.startswith("shader_parameter/"):
                params.append(stripped)
    shader = ""
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if "shaders/speed_fx.gdshader" in line:
                found = re.search(r'uid="(uid://[^"]+)"', line)
                shader = found.group(1) if found else ""
                break
    return shader, "\n".join(params)


def showcase_props():
    """Все пропсы игры в стабильном порядке: имя, uid, путь."""
    props = []
    for name in sorted(os.listdir(PROPS_DIR)):
        if not name.endswith(".tscn"):
            continue
        stem = name[:-5]
        if stem in SHOWCASE_SKIP:
            continue
        props.append((stem, read_uid(os.path.join(PROPS_DIR, name)),
                      "res://scenes/props/" + name))
    return props


def compact(value):
    """Число без хвостовых нулей: .tscn читаем глазами, а не только движком."""
    text = ("%.6f" % value).rstrip("0").rstrip(".")
    return "0" if text in ("", "-0") else text


def yaw_transform(x, z, yaw_deg):
    """Transform3D поворота вокруг Y — формат Godot (9 чисел осей + origin)."""
    a = math.radians(yaw_deg)
    c, s = math.cos(a), math.sin(a)
    values = [c, 0.0, -s, 0.0, 1.0, 0.0, s, 0.0, c, x, 0.0, z]
    return "Transform3D(%s)" % ", ".join(compact(v) for v in values)


def scene_text():
    props = showcase_props()
    rows = len(SHOWCASE_ROWS)
    per_row = int(math.ceil(len(props) / float(rows)))
    lines = ['[gd_scene format=3 uid="%s"]' % resource_uid("res://scenes/rally_stage_testpad.tscn"), ""]
    lines.append('[ext_resource type="Script" uid="%s" path="res://scripts/rally_stage.gd" id="1_stage"]'
                 % read_uid(os.path.join(ROOT, "scripts/rally_stage.gd")))
    lines.append('[ext_resource type="Resource" uid="%s" path="res://data/rally_game_config.tres" id="2_config"]'
                 % resource_uid("res://data/rally_game_config.tres"))
    lines.append('[ext_resource type="Resource" uid="%s" path="res://data/tracks/stage_testpad.tres" id="3_track"]'
                 % resource_uid("res://data/tracks/stage_testpad.tres"))
    lines.append('[ext_resource type="Curve3D" uid="%s" path="res://data/tracks/stage_testpad_route.tres" id="4_route"]'
                 % read_uid(ROUTE_PATH))
    lines.append('[ext_resource type="PackedScene" uid="%s" path="res://scenes/rally_car.tscn" id="5_car"]'
                 % read_uid(os.path.join(ROOT, "scenes/rally_car.tscn")))
    lines.append('[ext_resource type="PackedScene" uid="%s" path="res://scenes/ui/rally_hud.tscn" id="6_hud"]'
                 % read_uid(os.path.join(ROOT, "scenes/ui/rally_hud.tscn")))
    screen_uid, screen_params = screen_material_lines()
    shader_uid = (' uid="%s"' % screen_uid) if screen_uid else ""
    lines.append('[ext_resource type="Shader"%s path="res://shaders/speed_fx.gdshader" id="0_screen_shader"]' % shader_uid)
    lines.append('[ext_resource type="PackedScene" path="res://scenes/effects/retro_screen.tscn" id="7_screen"]')
    lines.append('[ext_resource type="PackedScene" path="res://scenes/effects/visual_effects.tscn" id="8_effects"]')
    for index, (stem, uid, path) in enumerate(props):
        uid_part = (' uid="%s"' % uid) if uid else ""
        lines.append('[ext_resource type="PackedScene"%s path="%s" id="prop_%d"]' % (uid_part, path, index))
    lines.append("")
    lines.append('[sub_resource type="ShaderMaterial" id="ShaderMaterial_screen"]')
    lines.append("resource_local_to_scene = true")
    lines.append('shader = ExtResource("0_screen_shader")')
    lines.append(screen_params)
    lines.append("")

    lines.append('[node name="RallyStage" type="Node3D"]')
    lines.append('script = ExtResource("1_stage")')
    lines.append('track_override = ExtResource("3_track")')
    lines.append("")
    lines.append('''[node name="VisualEffects" parent="." instance=ExtResource("8_effects")]
editor_description = "Визуальные настройки: скорость, дождь, снег и материалы. Ретро-экран — под HUD."
''')
    lines.append('[node name="WorldEnvironment" type="WorldEnvironment" parent="."]')
    lines.append("")
    lines.append('[node name="SunLight" type="DirectionalLight3D" parent="."]')
    lines.append("transform = Transform3D(1, 0, 0, 0, 0.7071068, 0.7071068, 0, -0.7071068, 0.7071068, 0, 40, 0)")
    lines.append("light_energy = 1.45")
    lines.append("shadow_enabled = true")
    lines.append("directional_shadow_max_distance = 160.0")
    lines.append("")
    lines.append('[node name="Terrain" type="StaticBody3D" parent="."]')
    lines.append("")
    lines.append('[node name="Generated" type="Node3D" parent="."]')
    lines.append("")
    lines.append('[node name="Route" type="Path3D" parent="."]')
    lines.append('curve = ExtResource("4_route")')
    lines.append("")
    lines.append('''[node name="Props" type="Node3D" parent="."]
editor_description = "Витрина пропсов: по одному экземпляру каждого вида вдоль обеих прямых. Высоту выставляет этап при сборке."
''')

    slot = 0
    for row_index, (x, z_from, z_to, yaw) in enumerate(SHOWCASE_ROWS):
        count = per_row if row_index < rows - 1 else len(props) - slot
        for i in range(count):
            stem, _uid, _path = props[slot]
            slot += 1
            t = i / float(max(1, count - 1))
            z = z_from + (z_to - z_from) * t
            lines.append('[node name="%02d_%s" type="Node3D" parent="Props" instance=ExtResource("prop_%d")]'
                         % (slot, stem, slot - 1))
            lines.append("transform = %s" % yaw_transform(x, z, yaw))
            lines.append("")
    lines.append('[node name="RallyCar" parent="." instance=ExtResource("5_car")]')
    lines.append("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0)")
    lines.append("")
    lines.append('[node name="HUD" type="CanvasLayer" parent="."]')
    lines.append("")
    lines.append('''[node name="SpeedShaderRect" parent="HUD" instance=ExtResource("7_screen")]
editor_description = "Ретро-экран: готовый вид выбирается здесь, материал сохраняется в сцене."
material = SubResource("ShaderMaterial_screen")
''')
    lines.append('''[node name="RallyHUD" parent="HUD" instance=ExtResource("6_hud")]
''')
    return "\n".join(lines).rstrip() + "\n"


def write_scene():
    text = scene_text()
    with open(SCENE_PATH, "w", encoding="utf-8") as handle:
        handle.write(text)
    return len(showcase_props())


# -------------------------------------------------- регистрация в конфиге
def register_in_config():
    """Трасса в списке меню и как быстрый вход «ТЕСТ-ПОЛИГОН» с главной."""
    with open(CONFIG_PATH, encoding="utf-8") as handle:
        text = handle.read()
    uid = resource_uid("res://data/tracks/stage_testpad.tres")
    changed = False
    if "res://data/tracks/stage_testpad.tres" not in text:
        line = '[ext_resource type="Resource" uid="%s" path="res://data/tracks/stage_testpad.tres" id="testpad"]' % uid
        marker = "[resource]"
        text = text.replace(marker, line + "\n\n" + marker, 1)
        changed = True
    if 'ExtResource("testpad")' not in text.split("tracks = ", 1)[1].split("\n", 1)[0]:
        head, rest = text.split("tracks = Array[Resource]([", 1)
        body, tail = rest.split("])", 1)
        body = body.rstrip()
        body = body + (", " if body else "") + 'ExtResource("testpad")'
        text = head + "tracks = Array[Resource]([" + body + "])" + tail
        changed = True
    if "\ntest_track = " not in text:
        text = text.rstrip("\n") + '\ntest_track = ExtResource("testpad")\n'
        changed = True
    if changed:
        with open(CONFIG_PATH, "w", encoding="utf-8") as handle:
            handle.write(text)
    return changed


# ------------------------------------------------------------- проверки
def check(ok, message, failures):
    if not ok:
        failures.append(message)
    print("  %s %s" % ("OK  " if ok else "ПРОВАЛ", message))
    return ok


def verify(intent):
    failures = []
    print("Проверки тест-полигона:")
    baked = kit._sample_written(ROUTE_PATH, 1.0)
    points = [(p[0], p[2]) for p in baked]
    acc = kit.xz_distances([(p[0], p[1], 0.0) for p in points])
    length = acc[-1]
    check(abs(length - LOOP_LENGTH) < 25.0,
          "длина кольца %.0f м (замысел %.0f м)" % (length, LOOP_LENGTH), failures)
    check(length < 2000.0, "кольцо короткое: заезд начинается сразу", failures)

    first, last = points[0], points[-1]
    gap = math.hypot(first[0] - last[0], first[1] - last[1])
    check(gap < 0.05, "кольцо замкнуто (щель %.3f м)" % gap, failures)

    d0 = (points[1][0] - points[0][0], points[1][1] - points[0][1])
    dl = (points[-1][0] - points[-2][0], points[-1][1] - points[-2][1])
    kink = abs(math.degrees(math.atan2(dl[1], dl[0]) - math.atan2(d0[1], d0[0])))
    kink = min(kink, 360.0 - kink)
    check(kink < 1.5, "на стыке кольца нет излома курса (%.2f°)" % kink, failures)

    flat = max(abs(p[1]) for p in baked)
    check(flat < 0.05, "полотно плоское (перепад %.3f м)" % flat, failures)

    # Кривая не должна срезать повороты: расстояние от замысла до кривой.
    cell = 8.0
    buckets = {}
    for p in points[::2]:
        buckets.setdefault((int(p[0] // cell), int(p[1] // cell)), []).append(p)

    def nearest(p):
        bx, bz = int(p[0] // cell), int(p[1] // cell)
        best = 1e9
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for q in buckets.get((bx + dx, bz + dz), ()):
                    d = math.hypot(q[0] - p[0], q[1] - p[1])
                    if d < best:
                        best = d
        return best

    worst = max(nearest((p[0], p[1])) for p in intent[::2])
    check(worst < 1.5, "кривая держит замысел (срезка углов %.2f м)" % worst, failures)

    # Самозазор считаем по ДУГЕ кольца, а не по индексу: на замкнутом контуре
    # начало и конец — это одно и то же место, а соседние по кольцу точки
    # законно стоят рядом. Смотрим только на те, что разъехались на четверть
    # круга и больше — то есть на ПРОТИВОПОЛОЖНЫЕ стороны кольца.
    n = len(points)
    worst_gap = 1e9
    for i in range(0, n, 4):
        for j in range(i + 4, n, 4):
            along = min(abs(acc[i] - acc[j]), length - abs(acc[i] - acc[j]))
            if along < length * 0.25:
                continue
            d = math.hypot(points[i][0] - points[j][0], points[i][1] - points[j][1])
            worst_gap = min(worst_gap, d)
    check(worst_gap >= MIN_GAP - 20.0,
          "противоположные стороны кольца разъехались (%.0f м)" % worst_gap, failures)

    xs = [p[0] for p in points]
    zs = [p[1] for p in points]
    area = (max(xs) - min(xs) + 2 * TERRAIN_MARGIN) * (max(zs) - min(zs) + 2 * TERRAIN_MARGIN)
    cells = area / (TERRAIN_CELL * TERRAIN_CELL)
    check(cells < 60000, "земля грубая: ~%.0f клеток (у боевой трассы — сотни тысяч)" % cells, failures)

    track = open(TRACK_PATH, encoding="utf-8").read()
    check("bumps_amplitude = 0.0" in track and "hills_height = 0.0" in track,
          "полотно ровное: ни бугров, ни рельефа", failures)
    for forbidden in ("river = ", "bridges = ", "route_sections = ", "stream_world = true",
                      "night_mode = true", "procedural = true"):
        check(forbidden not in track, "в трассе нет «%s»" % forbidden.strip(), failures)

    scene = open(SCENE_PATH, encoding="utf-8").read()
    props = showcase_props()
    placed = len(re.findall(r'parent="Props" instance=ExtResource\("prop_', scene))
    check(placed == len(props), "витрина содержит все %d пропсов (нашлось %d)" % (len(props), placed), failures)
    check("res://scenes/rally_stage_testpad.tscn" in track, "трасса указывает на свою сцену", failures)
    check('ExtResource("4_route")' in scene, "в сцене есть кривая полигона", failures)
    for broken in ("bridge_large", "bridge_small"):
        check(broken not in scene, "мостовых пролётов в витрине нет (%s)" % broken, failures)

    config = open(CONFIG_PATH, encoding="utf-8").read()
    check("res://data/tracks/stage_testpad.tres" in config, "трасса зарегистрирована в rally_game_config", failures)
    check("\ntest_track = ExtResource(\"testpad\")" in config, "быстрый вход «ТЕСТ-ПОЛИГОН» включён", failures)

    print("  длина %.0f м, габарит %.0f × %.0f м, клеток земли ~%.0f"
          % (length, max(xs) - min(xs), max(zs) - min(zs), cells))
    return not failures


def main():
    if not os.path.isdir(os.path.dirname(TRACK_PATH)):
        raise SystemExit("нет каталога data/tracks — запускайте из корня проекта")
    intent, ctrl, planned = build_route()
    write_route(ctrl)
    with open(TRACK_PATH, "w", encoding="utf-8") as handle:
        handle.write(track_text())
    placed = write_scene()
    changed = register_in_config()
    print("тест-полигон")
    print("  замысел        %.0f м, контрольных точек %d" % (planned, len(ctrl)))
    print("  витрина        %d пропсов" % placed)
    print("  регистрация    %s" % ("обновлена" if changed else "уже была"))
    ok = verify(intent)
    print("  файлы          data/tracks/stage_testpad{,_route}.tres, scenes/rally_stage_testpad.tscn")
    if not ok:
        raise SystemExit("ПРОВЕРКА НЕ ПРОШЛА: правь параметры полигона")


if __name__ == "__main__":
    main()
