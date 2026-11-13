"""Статические и геометрические проверки синхронизации кабины и скрытия дублирующего HUD в 1-м лице."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


class CockpitSyncAndHudVisibilityTest(unittest.TestCase):
    def test_cockpit_uses_external_script_in_both_scenes(self):
        self.assertTrue((ROOT / "scripts/ui/rally_cockpit.gd").is_file())
        self.assertTrue((ROOT / "scripts/ui/rally_cockpit.gd.uid").is_file())
        self.assertTrue((ROOT / "tests/cockpit_sync.gd").is_file())
        self.assertTrue((ROOT / "tests/cockpit_sync.gd.uid").is_file())

        for scene_rel in ("scenes/rally_car.tscn", "scenes/rally_cockpit.tscn.tscn"):
            tscn = read(scene_rel)
            self.assertNotIn('id="GDScript_cockpit"', tscn, f"{scene_rel} не должен содержать встроенный GDScript_cockpit")
            self.assertNotIn('"engine_rpm"', tscn, f"{scene_rel} не должен ссылаться на несуществующее поле engine_rpm")
            self.assertIn("res://scripts/ui/rally_cockpit.gd", tscn, f"{scene_rel} должен использовать внешний rally_cockpit.gd")

    def test_cockpit_reads_canonical_car_and_stage_telemetry(self):
        code = read("scripts/ui/rally_cockpit.gd")
        self.assertIn("@tool", code)
        self.assertIn("class_name RallyCockpit", code)
        for token in (
            "current_rpm",
            "max_rpm",
            "motor_is_redline",
            "speed_kmh",
            "get_gear_label",
            "get_transmission_label",
            "get_drivetrain_label",
            "steering_amount",
            "throttle_amount",
            "brake_amount",
            "clutch_amount",
            "handbrake_input",
            "PedalClutchPivot",
            "TripmasterLabel",
            "compute_telemetry_snapshot",
        ):
            self.assertIn(token, code)

    def test_hud_hiding_and_car_stage_wiring(self):
        hud_style = read("scripts/data/rally_hud_style.gd")
        for field in (
            "cockpit_hide_redundant_hud",
            "cockpit_hide_speed_panel",
            "cockpit_hide_radio_card",
            "cockpit_hide_telemetry_panel",
            "cockpit_hide_stage_panel",
            "cockpit_hide_timer_panel",
            "cockpit_hide_mini_map",
            "cockpit_hide_fps",
            "cockpit_hide_hint",
        ):
            self.assertIn(field, hud_style)

        style_tres = read("data/ui/default_hud_style.tres")
        self.assertIn("cockpit_hide_redundant_hud = true", style_tres)
        self.assertIn("cockpit_hide_speed_panel = true", style_tres)
        self.assertIn("cockpit_hide_radio_card = true", style_tres)

        hud_code = read("scripts/ui/rally_hud.gd")
        for token in (
            "signal cockpit_mode_changed(",
            "enum CockpitHideMode",
            "func bind_vehicle(",
            "func set_camera_mode(",
            "func is_cockpit_view(",
            "_apply_cockpit_visibility()",
        ):
            self.assertIn(token, hud_code)

        car_code = read("scripts/rally_car.gd")
        self.assertIn("signal camera_mode_changed(", car_code)
        self.assertIn('add_to_group("rally_car")', car_code)

        stage_code = read("scripts/rally_stage.gd")
        self.assertIn('add_to_group("rally_stage")', stage_code)
        self.assertIn("hud_controller.bind_vehicle(car)", stage_code)
        self.assertIn("hud_controller.set_camera_mode(car.camera_mode)", stage_code)

    @unittest.skipUnless(shutil.which("convert"), "ImageMagick convert не установлен")
    def test_sprite_speedometer_layout_prevents_right_edge_unit_clipping(self):
        # Проверяем реальные пропорции больших цифр (78x113) и подписей км/ч (153x51) / mph (232x51)
        # внутри SpeedPanel размером 340x224 из scenes/ui/rally_hud.tscn.
        code = read("scripts/ui/sprite_speedometer.gd")
        self.assertIn("quarter_angle_range", code)
        self.assertIn("digit_start_x_ratio: float = 0.285", code)

        panel_w, panel_h = 340.0, 224.0
        start_x = panel_w * 0.285
        d_h = panel_h * 0.255
        slot_w = d_h * 0.66
        col_w = d_h * (78.0 / 113.0)
        adv = max(slot_w, col_w) + 2.0
        speed_end_x = start_x + 2.0 * adv + max(slot_w, col_w)

        unit_h = panel_h * 0.125
        kmh_w = unit_h * (153.0 / 51.0)
        unit_x = speed_end_x + 6.0
        self.assertLessEqual(unit_x + kmh_w, panel_w - 10.0, "000 км/ч должен иметь минимум 10 px отступа от правого края")


if __name__ == "__main__":
    unittest.main()
