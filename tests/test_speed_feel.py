"""Статические контракты ощущения скорости без запуска Godot.

Полоски/штрихи по краям кадра удалены: скорость дают камера, инерция, дорожная
отдача и лёгкое периферийное размытие. Вид от капота остаётся спокойным.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


class SpeedFeelShaderTest(unittest.TestCase):
    def test_no_procedural_speed_lines(self):
        shader = read("shaders/speed_fx.gdshader")
        for forbidden in (
            "streak_strength",
            "speed_phase",
            "view_streak",
            "sectors",
            "dash",
        ):
            self.assertNotIn(forbidden, shader)

    def test_keeps_camera_aware_peripheral_blur(self):
        shader = read("shaders/speed_fx.gdshader")
        for uniform in (
            "uniform int camera_mode",
            "uniform float blur_gain",
            "uniform float cockpit_scale",
        ):
            self.assertIn(uniform, shader)
        self.assertIn("if (camera_mode != 1)", shader)
        self.assertIn("camera_mode == 1 ? 0.32 : 0.28", shader)
        self.assertIn("camera_mode == 1 ? 0.85 : 0.80", shader)
        self.assertIn("camera_mode == 1 ? 0.18 : 0.24", shader)


class SpeedFeelWiringTest(unittest.TestCase):
    def test_screen_receives_camera_without_phase(self):
        screen = read("scripts/effects/rally_screen_look.gd")
        self.assertIn("func set_preview_speed(speed_kmh: float, camera_mode: int = -1)", screen)
        for param in ("camera_mode", "blur_gain", "cockpit_scale"):
            self.assertIn(f'mat.set_shader_parameter("{param}"', screen)
        for forbidden in ("advance_speed_phase", "streak_strength", "speed_phase"):
            self.assertNotIn(forbidden, screen)

    def test_stage_passes_active_camera(self):
        stage = read("scripts/rally_stage.gd")
        self.assertIn("var camera_mode: int = car.camera_mode if car != null else 0", stage)
        self.assertIn("fx_nodes.update_speed(speed, track, camera_mode)", stage)
        self.assertIn('speed_fx_material.set_shader_parameter("camera_mode", camera_mode)', stage)
        self.assertNotIn("speed_phase", stage)
        self.assertNotIn("streak_strength", stage)

    def test_cockpit_fov_bonus_is_separate_from_hood(self):
        car = read("scripts/rally_car.gd")
        self.assertIn("var cockpit_speed_fov_bonus: float = 10.0", car)
        self.assertIn("CameraMode.HOOD:", car)
        self.assertIn("hood_fov + inside_speed_fov_bonus", car)
        self.assertIn("cockpit_fov + cockpit_speed_fov_bonus", car)
        self.assertIn("var fov_bonus: float = cockpit_speed_fov_bonus if camera_mode == CameraMode.COCKPIT_1ST else inside_speed_fov_bonus", car)

    def test_settings_mirror_blur_fields_only(self):
        settings = read("scripts/data/rally_stage_settings.gd")
        feel = read("scripts/effects/rally_speed_feel.gd")
        for field in ("speed_blur_gain", "speed_cockpit_scale"):
            self.assertIn(f"var {field}:", settings)
            self.assertIn(f'cfg.set("{field}"', feel)
            self.assertIn(f'cfg.get("{field}")', feel)
        self.assertNotIn("speed_streak_strength", settings)
        self.assertNotIn("streak_percent", feel)


class SpeedFeelSceneTest(unittest.TestCase):
    def test_scenes_do_not_store_removed_streak_uniforms(self):
        for rel in (
            "scenes/effects/retro_screen.tscn",
            "scenes/rally_stage.tscn",
            "scenes/rally_stage2_forest.tscn",
            "scenes/editor/visual_effects_lab.tscn",
        ):
            scene = read(rel)
            self.assertNotIn("shader_parameter/streak_strength", scene)
            self.assertNotIn("shader_parameter/speed_phase", scene)

    def test_speed_effect_description_has_no_streaks(self):
        scene = read("scenes/effects/speed_effect.tscn")
        self.assertNotIn("штрихи", scene)
        self.assertIn("периферийное размытие", scene)


class CameraJuiceTest(unittest.TestCase):
    def test_juice_tuning_is_data_driven(self):
        feel = read("scripts/data/rally_car_feel_config.gd")
        for field in (
            "camera_juice_strength",
            "chase_juice_scale",
            "cockpit_juice_scale",
            "road_shake_start_kmh",
            "road_shake_full_kmh",
            "road_shake_amplitude",
            "road_shake_rotation_deg",
            "surface_roughness_asphalt",
            "surface_roughness_dirt",
            "surface_roughness_grass",
            "trauma_decay",
            "trauma_amplitude",
            "trauma_rotation_deg",
            "shift_trauma",
            "shift_pitch_deg",
            "shift_fov_kick",
            "landing_trauma_per_mps",
            "suspension_impact_threshold",
            "impact_decel_threshold",
            "cockpit_g_force_gain",
            "cockpit_g_force_limit",
        ):
            self.assertIn(f"var {field}:", feel)

    def test_chase_and_cockpit_use_juice(self):
        car = read("scripts/rally_car.gd")
        self.assertIn("var chase_motion_strength: float", car)
        self.assertIn("_update_camera_juice(delta)", car)
        self.assertIn("func _chase_juice_scale() -> float:", car)
        self.assertIn("func _cockpit_juice_scale() -> float:", car)
        self.assertIn("func _juice_shake_offset() -> Vector3:", car)
        self.assertIn("func _juice_shake_rotation() -> Vector3:", car)
        self.assertIn("func _juice_g_rotation() -> Vector3:", car)
        self.assertIn("func _reset_camera_juice() -> void:", car)
        self.assertIn("var chase_juice: float = _chase_juice_scale()", car)
        self.assertIn("var cockpit_juice: float = _cockpit_juice_scale()", car)
        self.assertIn("active_camera.rotate_object_local(Vector3.RIGHT, juice_rotation.x)", car)
        self.assertIn("active_camera.global_position += active_camera.global_transform.basis * (_juice_shake_offset() * chase_juice)", car)
        self.assertIn("active_camera.global_position += global_transform.basis * (_juice_shake_offset() * cockpit_juice)", car)

    def test_hood_camera_stays_calm(self):
        car = read("scripts/rally_car.gd")
        update_block = car.split("func _update_cameras(delta: float) -> void:", 1)[1].split("func _update_action_camera", 1)[0]
        hood_block = update_block.split("CameraMode.HOOD:", 1)[1].split("CameraMode.COCKPIT_1ST:", 1)[0]
        self.assertIn("active_camera.global_transform = cam_hood.global_transform", hood_block)
        for forbidden in ("_juice_", "camera_trauma", "g_force_offset"):
            self.assertNotIn(forbidden, hood_block)

    def test_reset_clears_juice(self):
        car = read("scripts/rally_car.gd")
        self.assertIn("_reset_camera_juice()", car)
        reset = car.split("func _reset_camera_juice() -> void:", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("camera_trauma = 0.0", reset)
        self.assertIn("_juice_shift_kick = 0.0", reset)
        self.assertIn("_juice_local_accel = Vector3.ZERO", reset)


if __name__ == "__main__":
    unittest.main()
