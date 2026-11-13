"""Regression checks for layered Bayer-ready dust/debris FX and Lancer Evo lights."""
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

    def test_taillights_and_center_brake_live_under_lancer_evo_only(self):
        tscn = _read("scenes/rally_car.tscn")
        for node_name, node_type in [
            ("TaillightL", "SpotLight3D"),
            ("TaillightR", "SpotLight3D"),
            ("TaillightGlow", "OmniLight3D"),
            ("CenterBrakeLight", "MeshInstance3D"),
        ]:
            header = f'[node name="{node_name}" type="{node_type}" parent="low poly lance evo"'
            block = _extract_block(tscn, header)
            self.assertTrue(block, f"{header} missing in scenes/rally_car.tscn")
            self.assertNotIn("shadow_enabled = true", block)

        # Spotlights point rearward (-Z in Godot = +Z basis.z)
        for spot_name in ("TaillightL", "TaillightR"):
            block = _extract_block(
                tscn, f'[node name="{spot_name}" type="SpotLight3D" parent="low poly lance evo"'
            )
            m = re.search(r"Transform3D\(([^)]+)\)", block)
            self.assertIsNotNone(m, f"Missing Transform3D on {spot_name}")
            nums = [float(x.strip()) for x in m.group(1).split(",")]
            self.assertEqual(len(nums), 12)
            # Basis Z vector is cols (6, 7, 8); beam direction is -Z, so z_axis.z > 0.9 => beam.z < -0.9
            self.assertGreater(nums[8], 0.9, f"{spot_name} beam must point toward -Z")

        # Rear GravelParticles spawned behind rear bumper
        gravel_block = _extract_block(tscn, '[node name="GravelParticles" type="GPUParticles3D"')
        m = re.search(r"Transform3D\(([^)]+)\)", gravel_block)
        self.assertIsNotNone(m)
        nums = [float(x.strip()) for x in m.group(1).split(",")]
        self.assertLessEqual(nums[11], -2.0)

        # Headlights remain untouched and forward-pointing, subaru scene untouched
        self.assertIn('[node name="HeadlightL" type="SpotLight3D" parent="."', tscn)
        self.assertIn('[node name="HeadlightR" type="SpotLight3D" parent="."', tscn)
        subaru_tscn = _read("scenes/rally_car2.tscn")
        self.assertNotIn("TaillightL", subaru_tscn)
        self.assertNotIn("CenterBrakeLight", subaru_tscn)

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
        self.assertIn("not _evo_model.visible", car_gd)
        self.assertIn("CarVisuals.ensure_body_material", car_gd)


if __name__ == "__main__":
    unittest.main()
