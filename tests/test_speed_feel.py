"""Статические контракты усиленного ощущения скорости без запуска Godot.

Вид от капота должен остаться спокойным, а сзади/в кабине получают радиальные
штрихи, усиленное периферийное размытие и отдельную прибавку FOV кабины.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


class SpeedFeelShaderTest(unittest.TestCase):
    def test_shader_has_camera_aware_ps1_streaks(self):
        shader = read("shaders/speed_fx.gdshader")
        for uniform in (
            "uniform int camera_mode",
            "uniform float streak_strength",
            "uniform float blur_gain",
            "uniform float cockpit_scale",
            "uniform float speed_phase",
        ):
            self.assertIn(uniform, shader)
        self.assertIn("float view_streak = 0.0;", shader)
        self.assertIn("if (camera_mode != 1)", shader)
        self.assertIn("bayer4(pixel)", shader)
        self.assertIn("floor(effect_uv * grid)", shader)

    def test_hood_keeps_legacy_mask_and_vignette(self):
        shader = read("shaders/speed_fx.gdshader")
        self.assertIn("camera_mode == 1 ? 0.32 : 0.28", shader)
        self.assertIn("camera_mode == 1 ? 0.85 : 0.80", shader)
        self.assertIn("camera_mode == 1 ? 0.18 : 0.24", shader)


class SpeedFeelWiringTest(unittest.TestCase):
    def test_screen_receives_camera_and_phase(self):
        screen = read("scripts/effects/rally_screen_look.gd")
        self.assertIn("func set_preview_speed(speed_kmh: float, camera_mode: int = -1)", screen)
        self.assertIn("func advance_speed_phase(delta: float)", screen)
        for param in ("camera_mode", "streak_strength", "blur_gain", "cockpit_scale", "speed_phase"):
            self.assertIn(f'mat.set_shader_parameter("{param}"', screen)

    def test_stage_passes_active_camera_and_delta(self):
        stage = read("scripts/rally_stage.gd")
        self.assertIn("var camera_mode: int = car.camera_mode if car != null else 0", stage)
        self.assertIn("fx_nodes.update_speed(speed, track, camera_mode, delta)", stage)
        self.assertIn('speed_fx_material.set_shader_parameter("camera_mode", camera_mode)', stage)

    def test_cockpit_fov_bonus_is_separate_from_hood(self):
        car = read("scripts/rally_car.gd")
        self.assertIn("var cockpit_speed_fov_bonus: float = 10.0", car)
        self.assertIn("CameraMode.HOOD:", car)
        self.assertIn("hood_fov + inside_speed_fov_bonus", car)
        self.assertIn("cockpit_fov + cockpit_speed_fov_bonus", car)
        self.assertIn("var fov_bonus: float = cockpit_speed_fov_bonus if camera_mode == CameraMode.COCKPIT_1ST else inside_speed_fov_bonus", car)

    def test_settings_mirror_new_speed_fields(self):
        settings = read("scripts/data/rally_stage_settings.gd")
        feel = read("scripts/effects/rally_speed_feel.gd")
        for field in ("speed_streak_strength", "speed_blur_gain", "speed_cockpit_scale"):
            self.assertIn(f"var {field}:", settings)
            self.assertIn(f'cfg.set("{field}"', feel)
            self.assertIn(f'cfg.get("{field}")', feel)


if __name__ == "__main__":
    unittest.main()
