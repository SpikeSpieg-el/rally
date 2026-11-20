"""Дворники лобового стекла: отдельная сцена, авто-стирание и независимость от камеры.

Godot не нужен: проверки фиксируют интеграцию, фильтр фактического попадания
по стеклу и точную 3D-геометрию WindshieldWipers / BloodGlassSmear.
"""
import math
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def _extract_node_transform(tscn: str, node_name: str, parent: str | None = None) -> tuple[list[float], tuple[float, float, float]]:
    if parent is None:
        pattern = rf'\[node name="{re.escape(node_name)}"[^\]]*\]\n(.*?)(?=\n\[|$)'
    else:
        pattern = rf'\[node name="{re.escape(node_name)}"[^\]]*parent="{re.escape(parent)}"[^\]]*\]\n(.*?)(?=\n\[|$)'
    m = re.search(pattern, tscn, re.S)
    if not m:
        raise AssertionError(f"Узел {node_name} (parent={parent}) не найден")
    tm = re.search(r"Transform3D\(([^)]+)\)", m.group(1))
    if not tm:
        return [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0], (0.0, 0.0, 0.0)
    nums = [float(v.strip()) for v in tm.group(1).split(",")]
    return nums[:9], (nums[9], nums[10], nums[11])


def _transform_point(basis: list[float], origin: tuple[float, float, float], point: tuple[float, float, float]) -> tuple[float, float, float]:
    return tuple(
        origin[row] + sum(basis[row * 3 + col] * point[col] for col in range(3))
        for row in range(3)
    )


def _inverse_transform_point(basis: list[float], origin: tuple[float, float, float], point: tuple[float, float, float]) -> tuple[float, float, float]:
    delta = tuple(point[i] - origin[i] for i in range(3))
    return tuple(sum(delta[row] * basis[row * 3 + col] for row in range(3)) for col in range(3))


def _compose_transform(
    parent_basis: list[float],
    parent_origin: tuple[float, float, float],
    local_basis: list[float],
    local_origin: tuple[float, float, float],
) -> tuple[list[float], tuple[float, float, float]]:
    basis = [
        sum(parent_basis[row * 3 + k] * local_basis[k * 3 + col] for k in range(3))
        for row in range(3)
        for col in range(3)
    ]
    origin = _transform_point(parent_basis, parent_origin, local_origin)
    return basis, origin


def _car_scenes() -> list[str]:
    """Все игровые сцены машин: их список не должен жить в тестах."""
    scenes = sorted((ROOT / "scenes").glob("rally_car*.tscn"))
    assert scenes, "в scenes/ нет сцен машин rally_car*.tscn"
    return [scene.relative_to(ROOT).as_posix() for scene in scenes]


def _model_root(tscn: str) -> str:
    """Имя узла модели кузова: сцена хранит его в body_model_path на корне.

    Так тест не привязан к именам моделей — у каждой машины своё
    («low poly lance evo», «Volkswagen Golf R32 Mk4», …).
    """
    m = re.search(r'body_model_path\s*=\s*NodePath\("([^"]+)"\)', tscn)
    if not m:
        raise AssertionError("В сцене нет body_model_path: имя узла кузова неизвестно")
    return m.group(1)


def _wipers_in_car(tscn: str) -> tuple[list[float], tuple[float, float, float]]:
    model_name = _model_root(tscn)
    model_basis, model_origin = _extract_node_transform(tscn, model_name, ".")
    wipers_basis, wipers_origin = _extract_node_transform(tscn, "WindshieldWipers", model_name)
    return _compose_transform(model_basis, model_origin, wipers_basis, wipers_origin)


class WiperSceneTest(unittest.TestCase):
    def test_wipers_are_a_separate_editable_scene(self):
        scene = ROOT / "scenes" / "effects" / "windshield_wipers.tscn"
        self.assertTrue(scene.is_file(), "нет сцены дворников")
        text = read("scenes/effects/windshield_wipers.tscn")
        for token in (
            "windshield_wipers.gd",
            "WiperLeft", "WiperRight",
            "Mesh_arm", "Mesh_blade",
            'name="Arm"', 'name="Blade"',
        ):
            self.assertIn(token, text, token)

    def test_wiper_script_drives_and_wipes(self):
        script = read("scripts/effects/windshield_wipers.gd")
        for token in (
            "class_name RallyWindshieldWipers",
            "func setup(",
            "wipe_glass",
            "glass_dirty",
            "park_degrees",
        ):
            self.assertIn(token, script, token)

    def test_wipers_are_not_tied_to_camera_view(self):
        script = read("scripts/effects/windshield_wipers.gd")
        process = script.split("func _process(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("if _blood_dirty():", process)
        self.assertNotIn("_viewing", script)
        self.assertNotIn("set_viewing", script)

        car = read("scripts/rally_car.gd")
        self.assertIn("wipers.setup(self)", car)
        self.assertNotIn("_sync_wiper_view", car)
        self.assertNotIn("set_viewing", car)

    def test_car_installs_wipers_independent_of_camera(self):
        for scene in _car_scenes():
            text = read(scene)
            self.assertIn("windshield_wipers.tscn", text, scene)
            self.assertIn(f'name="WindshieldWipers" parent="{_model_root(text)}"', text, scene)
            self.assertNotIn('name="Wipers"', text, f"{scene} не должен содержать старый дубликат Wipers")
        car = read("scripts/rally_car.gd")
        for token in (
            "_resolve_wipers",
            'get_node_or_null("WindshieldWipers")',
            'find_child("WindshieldWipers", true, false)',
            "wipers.setup(self)",
        ):
            self.assertIn(token, car, token)
        blood = read("scripts/effects/rally_blood_fx.gd")
        self.assertIn('car.find_child("WindshieldWipers", true, false)', blood)
        wipers = read("scripts/effects/windshield_wipers.gd")
        self.assertIn('p.is_in_group("rally_car")', wipers)
        self.assertNotIn('p.has_node("RallyCockpit")', wipers)

    def test_blood_fx_exposes_wipe_api_and_rig_aligned_shader(self):
        blood = read("scripts/effects/rally_blood_fx.gd")
        for token in (
            "func wipe_glass(",
            "func glass_dirty(",
            "_is_glass_zone",
            "_resolve_wiper_rig",
            "PuddleShader",
            "atan(-d.x, d.y)",
            "quad_center_local",
            "pivot_left",
            "pivot_right",
            "blade_range",
        ):
            self.assertIn(token, blood, token)
        self.assertNotIn("atan(d.x, d.y)", blood, "Знак угла должен совпадать с 3D rotation.z = angle")
        # Проверяем, что дефолтный fallback glass_point не опущен на уровень капота (< 1.35)
        m = re.search(r"var glass_point:\s*Vector3\s*=\s*Vector3\(([^)]+)\)", blood)
        self.assertIsNotNone(m)
        glass_y = float(m.group(1).split(",")[1])
        self.assertGreaterEqual(glass_y, 1.35, "glass_point.y должен находиться в зоне лобового стекла, а не капота")

    def test_real_glass_or_direct_front_impact_creates_glass_blood(self):
        blood = read("scripts/effects/rally_blood_fx.gd")
        add_splat = blood.split("func add_splat(", 1)[1].split("\n\nfunc update(", 1)[0]
        self.assertIn("var raw_local_hit: Vector3 = car.to_local(world_point)", add_splat)
        self.assertIn("var glass_hit: bool = _is_glass_zone(raw_local_hit) or direct_front_hit", add_splat)
        self.assertRegex(add_splat, r"if glass_hit:\s+_ensure_glass_smear\(car, raw_local_hit\)")
        # Один физический удар — одно пятно в точке контакта, без принудительных
        # следов на бампере, капоте или краях лобового.
        self.assertEqual(add_splat.count("_store_splat("), 1)
        self.assertEqual(add_splat.count("_add_decal("), 1)
        self.assertNotIn("bumper_point", add_splat)
        self.assertNotIn("hood_point", add_splat)

        glass_test = blood.split("func _is_glass_zone(", 1)[1].split("\n\nfunc ", 1)[0]
        self.assertIn("_glass_quad_transform.affine_inverse() * point", glass_test)
        self.assertIn("absf(glass_local.z) <= GLASS_CONTACT_DEPTH", glass_test)
        self.assertIn("var _glass_quad_transform: Transform3D", blood)

    def test_windshield_contact_region_excludes_side_and_rear_hits(self):
        blood = read("scripts/effects/rally_blood_fx.gd")
        depth_match = re.search(r"GLASS_CONTACT_DEPTH\s*:=\s*([0-9.]+)", blood)
        self.assertIsNotNone(depth_match)
        depth = float(depth_match.group(1))
        half_w, half_h = 1.46 / 2.0, 0.84 / 2.0

        for scene in _car_scenes():
            tscn = read(scene)
            basis, origin = _wipers_in_car(tscn)
            center_x = max(-0.45, min(0.45, -origin[0]))
            # Quad center is shifted from the rig's origin; its actual surface
            # is 1.5 cm in front of BloodGlassSmear's prewarmed plane.
            smear_origin = _transform_point(basis, origin, (center_x, 0.365, -0.015))

            def in_glass(point):
                x, y, z = _inverse_transform_point(basis, smear_origin, point)
                return abs(x) <= half_w and abs(y) <= half_h and abs(z) <= depth

            glass_hit = _transform_point(basis, origin, (center_x, 0.365, 0.0))
            self.assertTrue(in_glass(glass_hit), f"{scene}: реальная точка на стекле должна пройти фильтр")
            self.assertFalse(in_glass((0.0, 0.7, -1.4)), f"{scene}: удар сзади не должен попасть на стекло")
            self.assertFalse(in_glass((1.1, 1.1, 1.3)), f"{scene}: удар сбоку не должен попасть на стекло")
            self.assertFalse(in_glass((0.0, 0.7, 2.1)), f"{scene}: удар по капоту не должен попасть на стекло")

    def test_windshield_blood_projection_and_wiper_angle_match(self):
        """Проверяем, что BloodGlassSmear на WindshieldWipers попадает прямо в обзор CamCockpit,
        полностью вмещает дуги 3D-щёток и точно совпадает с ними по углу atan(-d.x, d.y)."""
        wipers_tscn = read("scenes/effects/windshield_wipers.tscn")
        _, piv_l = _extract_node_transform(wipers_tscn, "WiperLeft")
        _, piv_r = _extract_node_transform(wipers_tscn, "WiperRight")
        blade_m = re.search(r'size\s*=\s*Vector3\(([^)]+)\)', wipers_tscn.split('id="Mesh_blade"')[1].split("\n[")[0])
        blade_len = float(blade_m.group(1).split(",")[1])
        _, blade_pos = _extract_node_transform(wipers_tscn, "Blade", "WiperLeft")
        r_min = blade_pos[1] - blade_len * 0.5
        r_max = blade_pos[1] + blade_len * 0.5

        park_rad = math.radians(-82.0)
        top_rad = math.radians(10.0)
        quad_w, quad_h = 1.46, 0.84
        center_y = 0.365

        # Проверка математического тождества угла шейдера с 3D rotation.z
        for expected_rad in (park_rad, 0.5 * (park_rad + top_rad), top_rad):
            for piv in ((piv_l[0], piv_l[1]), (piv_r[0], piv_r[1])):
                px = piv[0] - r_max * math.sin(expected_rad)
                py = piv[1] + r_max * math.cos(expected_rad)
                dx, dy = px - piv[0], py - piv[1]
                shader_ang = math.atan2(-dx, dy)
                self.assertAlmostEqual(shader_ang, expected_rad, places=5)

        for scene in _car_scenes():
            tscn = read(scene)
            _, cam_pos = _extract_node_transform(tscn, "CamCockpit", "Cameras")
            w_basis, w_pos = _wipers_in_car(tscn)
            # Столбцы basis в Godot Transform3D:
            bx = (w_basis[0], w_basis[3], w_basis[6])
            by = (w_basis[1], w_basis[4], w_basis[7])
            bz = (w_basis[2], w_basis[5], w_basis[8])

            center_x = max(-0.45, min(0.45, -w_pos[0]))
            smear_pos = (
                w_pos[0] + bx[0] * center_x + by[0] * center_y - bz[0] * 0.015,
                w_pos[1] + bx[1] * center_x + by[1] * center_y - bz[1] * 0.015,
                w_pos[2] + bx[2] * center_x + by[2] * center_y - bz[2] * 0.015,
            )
            rel_y = smear_pos[1] - cam_pos[1]
            rel_z = smear_pos[2] - cam_pos[2]
            self.assertGreater(rel_z, 0.5, f"{scene}: стекло должно быть перед камерой")
            screen_y_center = (rel_y / rel_z) / math.tan(math.radians(76.0) / 2.0)
            self.assertLess(abs(screen_y_center), 0.20, f"{scene}: центр BloodGlassSmear должен быть на уровне глаз водителя, а не внизу (screen_y={screen_y_center:.3f})")

            # Вся дуга лезвия (r_min..r_max, park..top) должна лежать внутри границ QuadMesh
            x_min = center_x - quad_w * 0.5
            x_max = center_x + quad_w * 0.5
            y_min = center_y - quad_h * 0.5
            y_max = center_y + quad_h * 0.5
            for piv in ((piv_l[0], piv_l[1]), (piv_r[0], piv_r[1])):
                for rad in (r_min, r_max):
                    for step in range(11):
                        ang = park_rad + (top_rad - park_rad) * (step / 10.0)
                        px = piv[0] - rad * math.sin(ang)
                        py = piv[1] + rad * math.cos(ang)
                        self.assertGreaterEqual(px, x_min, f"{scene}: щётка вышла за левый край quad")
                        self.assertLessEqual(px, x_max, f"{scene}: щётка вышла за правый край quad")
                        self.assertGreaterEqual(py, y_min, f"{scene}: щётка вышла за нижний край quad")
                        self.assertLessEqual(py, y_max, f"{scene}: щётка вышла за верхний край quad")

    def test_first_hit_is_prewarmed_not_lazy(self):
        """Первый сбитый не должен фризить: всё тяжёлое готовится в install()."""
        blood = read("scripts/effects/rally_blood_fx.gd")
        for token in (
            "BURST_POOL_NAME",
            "_install_burst_pool",
            "_prewarm_burst",
            "_prime_glass_smear",
            "_prime_decals",
            "_stain_texture()",
        ):
            self.assertIn(token, blood, token)
        # Пул переиспользуется, а не собирается заново на каждый удар.
        self.assertIn("_burst_for(", blood)


if __name__ == "__main__":
    unittest.main()
