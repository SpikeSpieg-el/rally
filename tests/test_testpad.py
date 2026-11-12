"""Тест-полигон: лёгкое кольцо для проверки эффектов, погоды и пропсов.

Проверки статические (Godot не нужен) и держат главное обещание полигона:
  * кольцо ЗАМКНУТО и не имеет излома на стыке — иначе в полотне появится
    плоский клин на стартовой линии;
  * кольцо короткое и ПЛОСКОЕ, земля грубая — иначе «моментально попадать»
    не получится;
  * трасса не потоковая и без реки/мостов;
  * сцена участка собрана из существующих ресурсов и содержит витрину ВСЕХ
    пропсов игры (кроме мостовых пролётов);
  * трасса зарегистрирована в конфиге и доступна кнопкой «ТЕСТ-ПОЛИГОН»
    с главного экрана;
  * инструмент авторинга детерминирован: повторный запуск не меняет файлы.

Отдельно проверяется, что старой «лаборатории визуальных эффектов» больше нет:
её роль целиком занял полигон.
"""
from pathlib import Path
import hashlib
import re
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]

ROUTE = "data/tracks/stage_testpad_route.tres"
TRACK = "data/tracks/stage_testpad.tres"
SCENE = "scenes/rally_stage_testpad.tscn"
CONFIG = "data/rally_game_config.tres"

# Мостовые пролёты в витрину не входят: это не пропс, а часть переправы.
SKIP_PROPS = ("bridge_large.tscn", "bridge_small.tscn")


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def curve_points(rel: str):
    """Точки Curve3D из .tres: (in, out, позиция) на каждую точку."""
    text = read(rel)
    found = re.search(r'"points": PackedVector3Array\(([^)]*)\)', text)
    assert found, f"{rel}: нет массива points"
    values = [float(v) for v in found.group(1).split(",") if v.strip()]
    assert len(values) % 9 == 0, f"{rel}: массив points не кратен 9"
    points = []
    for i in range(0, len(values), 9):
        handle_in = values[i:i + 3]
        handle_out = values[i + 3:i + 6]
        position = values[i + 6:i + 9]
        points.append((handle_in, handle_out, position))
    return points


def curve_length(points) -> float:
    total = 0.0
    for i in range(1, len(points)):
        ax, _, az = points[i - 1][2]
        bx, _, bz = points[i][2]
        total += ((bx - ax) ** 2 + (bz - az) ** 2) ** 0.5
    return total


class TestPadShapeTest(unittest.TestCase):
    """Кольцо: замкнутое, плоское, короткое, гладкое на стыке."""

    def setUp(self):
        self.points = curve_points(ROUTE)

    def test_ring_is_closed(self):
        first = self.points[0][2]
        last = self.points[-1][2]
        gap = ((first[0] - last[0]) ** 2 + (first[2] - last[2]) ** 2) ** 0.5
        self.assertLess(gap, 0.05, f"кольцо не замкнуто: щель {gap:.3f} м")

    def test_seam_has_real_handles(self):
        # Замыкание ради замыкания даёт НУЛЕВЫЕ ручки у первой и последней
        # точки: кривая на мгновение останавливается, и на стартовой линии
        # появляется плоский клин. Инструмент обязан считать соседей через стык.
        out_first = self.points[0][1]
        in_last = self.points[-1][0]
        self.assertGreater(sum(abs(v) for v in out_first), 0.5, "у первой точки нет выхода через стык")
        self.assertGreater(sum(abs(v) for v in in_last), 0.5, "у последней точки нет входа через стык")

    def test_ring_is_flat(self):
        heights = [p[2][1] for p in self.points]
        self.assertLess(max(abs(h) for h in heights), 0.05, "полотно полигона должно быть плоским")

    def test_ring_is_short(self):
        length = curve_length(self.points)
        self.assertGreater(length, 1000.0, f"кольцо слишком короткое: {length:.0f} м")
        self.assertLess(length, 1600.0, f"кольцо слишком длинное для «моментально попадать»: {length:.0f} м")

    def test_ring_keeps_its_shape(self):
        # Повороты R=110 в плане: радиус кривизны не должен схлопнуться в шип.
        positions = [p[2] for p in self.points]
        xs = [p[0] for p in positions]
        zs = [p[2] for p in positions]
        self.assertAlmostEqual(max(xs) - min(xs), 320.0, delta=6.0)
        self.assertAlmostEqual(max(zs) - min(zs), 440.0, delta=6.0)


class TestPadTrackTest(unittest.TestCase):
    """Ресурс трассы: лёгкий, не потоковый, без реки и мостов."""

    def setUp(self):
        self.track = read(TRACK)

    def test_points_to_its_own_scene_and_route(self):
        self.assertIn('id = "test_polygon"', self.track)
        self.assertIn('display_name = "ТЕСТ-ПОЛИГОН"', self.track)
        self.assertIn(f'stage_scene = "res://{SCENE}"', self.track)
        self.assertIn(f'path="res://{ROUTE}"', self.track)

    def test_is_not_streamed(self):
        self.assertIn("stream_world = false", self.track)
        self.assertIn("use_baked_props = true", self.track)
        self.assertIn("procedural = false", self.track)

    def test_has_no_heavy_features(self):
        for forbidden in ("river = ", "bridges = ", "route_sections = ", "night_mode = true"):
            self.assertNotIn(forbidden, self.track, f"на полигоне не должно быть «{forbidden.strip()}»")

    def test_road_and_ground_are_cheap(self):
        margin = float(re.search(r"terrain_margin = ([\d.]+)", self.track).group(1))
        cell = float(re.search(r"terrain_cell = ([\d.]+)", self.track).group(1))
        self.assertLessEqual(margin, 80.0, "поле вокруг полигона должно быть узким")
        self.assertGreaterEqual(cell, 2.5, "сетка земли должна быть грубой")
        cells = (320.0 + 2 * margin) * (440.0 + 2 * margin) / (cell * cell)
        self.assertLess(cells, 60000, f"земля слишком подробная: ~{cells:.0f} клеток")

    def test_surface_is_clean(self):
        for field in ("bumps_amplitude", "bumps_roughness", "bumps_cross", "hills_height", "ridge_height"):
            match = re.search(r"%s = ([-\d.]+)" % field, self.track)
            self.assertIsNotNone(match, f"нет поля {field}")
            self.assertEqual(float(match.group(1)), 0.0, f"{field} должен быть нулевым")


class TestPadSceneTest(unittest.TestCase):
    """Сцена участка: настоящие узлы этапа и витрина всех пропсов."""

    def setUp(self):
        self.scene = read(SCENE)

    def test_scene_uses_the_stage_script(self):
        self.assertIn("res://scripts/rally_stage.gd", self.scene)
        for node in ("RallyStage", "WorldEnvironment", "SunLight", "Terrain", "Generated", "Route",
                     "RallyCar", "HUD", "VisualEffects", "Props"):
            self.assertIn(f'name="{node}"', self.scene, f"нет узла {node}")
        self.assertIn(f'path="res://{ROUTE}"', self.scene)
        self.assertIn(f'path="res://{TRACK}"', self.scene)

    def test_retro_screen_is_the_template_material(self):
        # Числа берутся из шаблона retro_screen.tscn, а не пишутся руками:
        # материал обязан совпадать с шаблоном эффекта скорости.
        self.assertIn('name="SpeedShaderRect"', self.scene)
        self.assertIn('material = SubResource("ShaderMaterial_screen")', self.scene)
        for uniform in ("shader_parameter/blur_strength", "shader_parameter/vignette_strength",
                        "shader_parameter/blur_gain", "shader_parameter/cockpit_scale",
                        "shader_parameter/speed_stretch"):
            self.assertIn(uniform, self.scene, f"в материале нет {uniform}")

    def test_showcase_has_every_prop(self):
        props = sorted(p for p in (ROOT / "scenes/props").glob("*.tscn") if p.name not in SKIP_PROPS)
        placed = re.findall(r'instance=ExtResource\("(prop_\d+)"\)', self.scene)
        self.assertEqual(len(placed), len(props), f"витрина неполная: {len(placed)} из {len(props)}")
        referenced = re.findall(r'path="res://scenes/props/([^"]+)"', self.scene)
        self.assertEqual(sorted(referenced), sorted(p.name for p in props))

    def test_no_bridge_spans_on_the_showcase(self):
        for name in SKIP_PROPS:
            self.assertNotIn(name, self.scene)

    def test_props_are_inside_the_ring(self):
        # Витрина стоит в поле кольца, а не на полотне: иначе первый же заезд
        # заканчивается в бревне.
        offsets = []
        for block in re.split(r"\n(?=\[node )", self.scene):
            if 'parent="Props"' not in block:
                continue
            found = re.search(r"transform = Transform3D\(([^)]*)\)", block)
            self.assertIsNotNone(found, "у пропса нет трансформа")
            numbers = [float(v) for v in found.group(1).split(",")]
            self.assertEqual(len(numbers), 12, "Transform3D должен содержать 12 чисел")
            offsets.append((numbers[9], numbers[11]))
        self.assertTrue(offsets, "у пропсов нет координат")
        for x, z in offsets:
            x, z = float(x), float(z)
            self.assertGreater(x, -105.0, "пропс попал на левое полотно")
            self.assertLess(x, 205.0, "пропс попал на правое полотно")
            self.assertGreater(z, 5.0, "пропс попал на нижнее полотно")
            self.assertLess(z, 435.0, "пропс попал на верхнее полотно")


class TestPadEntryTest(unittest.TestCase):
    """Вход: кнопка на главном экране, трасса в списке, выбор в меню не портится."""

    def test_registered_as_a_track(self):
        config = read(CONFIG)
        self.assertIn(f'path="res://{TRACK}"', config)
        tracks = re.search(r"tracks = Array\[Resource\]\(\[([^\]]*)\]\)", config)
        self.assertIsNotNone(tracks)
        self.assertIn('ExtResource("testpad")', tracks.group(1))

    def test_fast_entry_is_wired(self):
        self.assertIn("test_track", read("scripts/data/rally_game_config.gd"))
        self.assertIn('test_track = ExtResource("testpad")', read(CONFIG))
        state = read("scripts/game_state.gd")
        self.assertIn("func start_test_polygon() -> void:", state)
        self.assertIn("func has_test_polygon() -> bool:", state)
        # Заезд идёт по полигону, но выбранная в меню трасса не перезаписывается.
        body = state.split("func start_test_polygon", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("current_track = config.test_track", body)
        self.assertIn("start_race()", body)
        self.assertNotIn("_save_selection()", body)
        title = read("scripts/title_screen.gd")
        self.assertIn("TestPadButton", title)
        self.assertIn("start_test_polygon", title)
        self.assertIn('name="TestPadButton"', read("scenes/title_screen.tscn"))

    def test_old_lab_is_gone(self):
        removed = ("scenes/editor/visual_effects_lab.tscn", "scripts/editor/visual_effects_lab.gd")
        for rel in removed:
            self.assertFalse((ROOT / rel).exists(), f"{rel} должен быть удалён: его роль занял полигон")
        for rel in ("README_RU.md", "docs/SCENE_EFFECTS_RU.md", "scripts/title_screen.gd"):
            self.assertNotIn("visual_effects_lab", read(rel), f"{rel} всё ещё ссылается на лабораторию")


class TestPadAuthoringTest(unittest.TestCase):
    """Инструмент авторинга: детерминирован и сам себя проверяет."""

    def test_tool_is_deterministic(self):
        paths = [ROOT / ROUTE, ROOT / TRACK, ROOT / SCENE]
        before = [hashlib.md5(p.read_bytes()).hexdigest() for p in paths]
        result = subprocess.run(
            [sys.executable, str(ROOT / "tools/author_testpad.py")],
            cwd=str(ROOT), capture_output=True, text=True, timeout=180,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        after = [hashlib.md5(p.read_bytes()).hexdigest() for p in paths]
        self.assertEqual(before, after, "повторный запуск изменил файлы полигона")
        self.assertNotIn("ПРОВАЛ", result.stdout, "собственные проверки инструмента не прошли")

    def test_tool_verifies_itself(self):
        tool = read("tools/author_testpad.py")
        for check in ("кольцо замкнуто", "полотно плоское", "витрина содержит все",
                      "земля грубая", "трасса зарегистрирована"):
            self.assertIn(check, tool, f"инструмент не проверяет: {check}")


if __name__ == "__main__":
    unittest.main()
