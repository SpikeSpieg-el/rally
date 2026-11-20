"""Regression checks for layered Bayer-ready dust/debris FX and model-configured brake lights."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def _extract_block(text: str, header_prefix: str) -> str:
    idx = text.find(header_prefix)
    if idx < 0:
        return ""
    next_hdr = text.find("\n[", idx + len(header_prefix))
    return text[idx:] if next_hdr < 0 else text[idx:next_hdr]


def _parse_float(block: str, key: str, default: float | None = None) -> float | None:
    m = re.search(rf"^{re.escape(key)}\s*=\s*([+-]?\d+(?:\.\d+)?(?:e[+-]?\d+)?)", block, re.M)
    return float(m.group(1)) if m else default


_IDENTITY_BASIS = (1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0)


def _car_scenes() -> list[str]:
    """Все игровые сцены машин: список не должен жить в тесте."""
    scenes = sorted(scene.relative_to(ROOT).as_posix()
                    for scene in (ROOT / "scenes").glob("rally_car*.tscn"))
    assert scenes, "в scenes/ нет сцен машин rally_car*.tscn"
    return scenes


def _nodes(scene: str, name: str, node_type: str) -> list[tuple[str, str, str]]:
    """Узлы сцены с этим именем и типом: [(заголовок, блок, родитель)]."""
    pattern = rf'\[node name="{re.escape(name)}" type="{re.escape(node_type)}" parent="([^"]*)"[^\n]*\]'
    return [(m.group(0), _extract_block(scene, m.group(0)), m.group(1))
            for m in re.finditer(pattern, scene)]


def _basis(block: str) -> list[float] | None:
    """Девять чисел базиса из Transform3D блока (или None, если трансформа нет)."""
    m = re.search(r"Transform3D\(([^)]+)\)", block)
    if not m:
        return None
    nums = [float(x.strip()) for x in m.group(1).split(",")]
    return nums[:9] if len(nums) >= 9 else None


def _compose(parent_basis, local_basis) -> list[float]:
    """Базис узла в системе координат сцены: parent * local."""
    return [
        sum(parent_basis[row * 3 + k] * local_basis[k * 3 + col] for k in range(3))
        for row in range(3)
        for col in range(3)
    ]


class DustAndDebrisTest(unittest.TestCase):
    def test_dust_fx_uses_soft_for_bayer_and_rich_ramps(self):
        src = _read("scripts/effects/rally_dust_fx.gd")
        self.assertIn("const STYLE := Style.SOFT_FOR_BAYER", src)
        self.assertIn("BaseMaterial3D.TRANSPARENCY_ALPHA", src)
        self.assertIn("BaseMaterial3D.DEPTH_DRAW_DISABLED", src)
        self.assertIn("BaseMaterial3D.DIFFUSE_LAMBERT_WRAP", src)
        self.assertIn("BaseMaterial3D.TEXTURE_FILTER_LINEAR", src)
        self.assertIn("static func debris_scale_curve()", src)
        self.assertIn("static func debris_color_variation()", src)
        self.assertIn("gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.0))", src)

    def test_default_fx_profile_lit_rear_directed_and_compact(self):
        tres = _read("data/stage/default_fx_profile.tres")
        res = _extract_block(tres, "[resource]")
        self.assertTrue(res, "[resource] block missing in default_fx_profile.tres")

        # Rearward direction, lit particles, zero yellow self-emission on night smoke
        self.assertRegex(res, r"foam_direction = Vector3\(0,\s*[\d.]+,\s*-[\d.]+\)")
        self.assertRegex(res, r"dust_direction = Vector3\(0,\s*[\d.]+,\s*-1\)")
        self.assertIn("foam_lit = true", res)
        self.assertIn("dust_lit = true", res)
        self.assertIn("foam_emission = 0.0", res)
        self.assertIn("dust_emission = 0.0", res)

        # Crisp tumbling low-poly grit debris over smoke
        self.assertIn("grit_lit = true", res)
        self.assertIn("grit_use_variation = true", res)
        grit_alpha = _parse_float(res, "grit_alpha")
        self.assertIsNotNone(grit_alpha)
        self.assertGreaterEqual(grit_alpha, 0.85)
        grit_spin = _parse_float(res, "grit_spin")
        self.assertIsNotNone(grit_spin)
        self.assertGreaterEqual(grit_spin, 180.0)
        segs = _parse_float(res, "spray_grain_segments")
        self.assertIsNotNone(segs)
        self.assertLessEqual(segs, 4.0)

        # Peak dust cloud fits behind bumper without intersecting chassis
        dust_radius = _parse_float(res, "dust_radius")
        dust_scale_max = _parse_float(res, "dust_scale_max")
        dust_growth = _parse_float(res, "dust_growth")
        self.assertIsNotNone(dust_radius)
        self.assertIsNotNone(dust_scale_max)
        self.assertIsNotNone(dust_growth)
        self.assertLessEqual(dust_radius * 2.0 * dust_scale_max * dust_growth, 3.23)

    def test_surface_effects_wires_debris_curves_and_keeps_spheremesh_contract(self):
        src = _read("scripts/surface_effects.gd")
        self.assertIn("DustFx.debris_scale_curve()", src)
        self.assertIn("DustFx.debris_color_variation()", src)
        self.assertIn("SphereMesh", src)
        self.assertIn('grit_alpha', src)


class EmissionAndTaillightsTest(unittest.TestCase):
    def test_mitsubishi_emission_texture_wired_with_multiply_op(self):
        self.assertTrue((ROOT / "textures/mitsubishi_emmision.png").is_file())
        self.assertTrue((ROOT / "textures/mitsubishi_emmision.png.import").is_file())

        tscn = _read("scenes/rally_car.tscn")
        self.assertIn('path="res://textures/mitsubishi_emmision.png"', tscn)
        mat = _extract_block(tscn, '[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_y2iot"]')
        self.assertTrue(mat, "StandardMaterial3D_y2iot block missing")
        self.assertIn("emission_enabled = true", mat)
        self.assertIn("emission = Color(1, 1, 1, 1)", mat)
        self.assertIn("emission_operator = 1", mat)
        self.assertIn("emission_texture = ExtResource(", mat)

        showroom = _read("low_poly_lance_evo.tscn")
        self.assertIn('path="res://textures/mitsubishi_emmision.png"', showroom)
        showroom_mat = _extract_block(showroom, '[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_psh58"]')
        self.assertIn("emission_enabled = true", showroom_mat)
        self.assertIn("emission_operator = 1", showroom_mat)
        self.assertIn("emission_texture = ExtResource(", showroom_mat)

    def test_brake_lights_are_configured_for_every_car_model(self):
        """Задние фонари есть у каждой машины, где бы модель их ни повесила.

        Сцены машин устроены по-разному: у Lancer фонари лежат внутри узла
        модели, у Golf и Subaru пятнашки TaillightL/R висят на корне сцены
        (parent="."), а линзы и центральный стоп-сигнал — внутри модели.
        Поэтому родитель ищется по сцене, а направление луча считается через
        фактическую цепочку: тот же порядок, каким rally_car.gd ищет узлы
        (сначала в модели, затем find_child по всему дереву).
        """
        scenes = _car_scenes()
        for scene_path in scenes:
            scene = _read(scene_path)
            model = re.search(r'body_model_path = NodePath\("([^"]+)"\)', scene)
            self.assertIsNotNone(model, f"{scene_path}: нет body_model_path")
            model_root = model.group(1)
            model_basis = _basis(_extract_block(scene, f'[node name="{model_root}"'))
            self.assertIsNotNone(model_basis,
                                 f"{scene_path}: у модели {model_root} нет явного трансформа")

            # Узлы, которые читает _setup_brake_lights(). TaillightGlow здесь
            # нет: ни одна сцена его не содержит, и рантайм живёт с null.
            # Линзы стоп-сигналов есть не у всех: у Lancer вместо них светится
            # материал кузова, поэтому они проверяются отдельно.
            required = (
                ("TaillightL", "SpotLight3D"),
                ("TaillightR", "SpotLight3D"),
                ("CenterBrakeLight", "MeshInstance3D"),
            )
            for node_name, node_type in required:
                found = _nodes(scene, node_name, node_type)
                self.assertEqual(len(found), 1,
                                 f"{scene_path}: узел {node_name} ({node_type}) должен быть ровно один")
                if len(found) != 1:
                    continue
                _, block, parent = found[0]
                self.assertIn(parent, (".", model_root),
                              f"{scene_path}: {node_name} должен висеть на корне сцены или на модели")
                local = _basis(block)
                self.assertIsNotNone(local, f"{scene_path}: у {node_name} нет Transform3D")
                if node_type != "SpotLight3D" or local is None:
                    continue
                # Тени у стоп-сигналов не нужны: они едят кадр и не видны ночью.
                self.assertNotIn("shadow_enabled = true", block, f"{scene_path}: {node_name}")
                # SpotLight3D светит вдоль своего -Z: луч должен смотреть назад.
                base = model_basis if parent == model_root else _IDENTITY_BASIS
                world = _compose(base, local)
                self.assertGreater(world[8], 0.9,
                                   f"{scene_path}: {node_name} должен светить назад")

            lenses = 0
            for lens_name in ("TaillightLensL", "TaillightLensR"):
                found = _nodes(scene, lens_name, "MeshInstance3D")
                if not found:
                    continue
                lenses += 1
                self.assertEqual(len(found), 1, f"{scene_path}: {lens_name} должен быть один")
                _, _, parent = found[0]
                self.assertIn(parent, (".", model_root),
                              f"{scene_path}: {lens_name} должен висеть на корне сцены или на модели")
            if lenses == 0:
                self.assertIn("emission_enabled = true", scene,
                              f"{scene_path}: нет ни линз стоп-сигналов, ни светящегося кузова — "
                              "торможение не будет видно")
            else:
                self.assertEqual(lenses, 2, f"{scene_path}: линзы стоп-сигналов должны быть парой")

            # Фары: у Lancer они внутри модели, у Golf и Subaru — на корне сцены.
            # SpotLight3D светит вдоль своего -Z, поэтому мировой базис отрицательный.
            for light_name in ("HeadlightL", "HeadlightR"):
                found = _nodes(scene, light_name, "SpotLight3D")
                self.assertEqual(len(found), 1,
                                 f"{scene_path}: узел {light_name} (SpotLight3D) должен быть ровно один")
                if len(found) != 1:
                    continue
                _, block, parent = found[0]
                self.assertIn(parent, (".", model_root),
                              f"{scene_path}: {light_name} должен висеть на корне сцены или на модели")
                local = _basis(block)
                self.assertIsNotNone(local, f"{scene_path}: у {light_name} нет Transform3D")
                if local is None:
                    continue
                base = model_basis if parent == model_root else _IDENTITY_BASIS
                world = _compose(base, local)
                self.assertLessEqual(world[8], -0.9,
                                     f"{scene_path}: {light_name} должен светить вперёд")
                # Тени дают только фары: у стоп-сигналов они съедают кадр впустую.
                self.assertIn("shadow_enabled = true", block,
                              f"{scene_path}: {light_name} должен отбрасывать тени")

            # Эмиттер гравия из-под задних колёс: позади кузова, на корне сцены.
            # У Lancer он у самого бампера (z = -2.42), у Golf и Subaru ближе к
            # середине (z = -1.50) — главное, что не внутри кузова.
            gravel_found = _nodes(scene, "GravelParticles", "GPUParticles3D")
            self.assertEqual(len(gravel_found), 1,
                             f"{scene_path}: узел GravelParticles должен быть ровно один")
            if len(gravel_found) == 1:
                _, gravel_block, gravel_parent = gravel_found[0]
                self.assertEqual(gravel_parent, ".",
                                 f"{scene_path}: GravelParticles belongs on the scene root")
                gravel_transform = re.search(r"Transform3D\(([^)]+)\)", gravel_block)
                self.assertIsNotNone(gravel_transform,
                                     f"{scene_path}: у GravelParticles нет Transform3D")
                if gravel_transform is not None:
                    nums = [float(x.strip()) for x in gravel_transform.group(1).split(",")]
                    self.assertLessEqual(nums[11], -1.0,
                                         f"{scene_path}: гравий должен лететь позади кузова")

        visuals = _read("scripts/car_visual_customization.gd")
        self.assertIn('car.find_child(node_name, true, false)', visuals)

    def test_brake_light_feel_config_and_rally_car_wiring(self):
        feel_gd = _read("scripts/data/rally_car_feel_config.gd")
        feel_tres = _read("data/car/default_car_feel.tres")
        car_gd = _read("scripts/rally_car.gd")

        for field in (
            "taillight_idle_energy",
            "taillight_brake_energy",
            "taillight_glow_idle_energy",
            "taillight_glow_brake_energy",
            "center_brake_idle_energy",
            "center_brake_brake_energy",
            "body_emission_idle",
            "body_emission_brake",
            "brake_light_response",
        ):
            self.assertIn(f"var {field}:", feel_gd)
            self.assertIn(f"{field} =", feel_tres)
            if field != "brake_light_response":
                self.assertIn(field, car_gd)

        self.assertIn("_setup_brake_lights()", car_gd)
        self.assertIn("_update_brake_lights(delta)", car_gd)
        self.assertIn("not _body_model.visible", car_gd)
        self.assertIn('"TaillightLensL", "TaillightLensR"', car_gd)
        self.assertIn("_prepare_taillight_lens(lens)", car_gd)
        self.assertIn("lens_mat.emission_energy_multiplier = glow_energy", car_gd)
        self.assertIn("CarVisuals.ensure_body_material", car_gd)


if __name__ == "__main__":
    unittest.main()
