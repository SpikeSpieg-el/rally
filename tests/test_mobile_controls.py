"""Mobile input and low-power Web configuration checks without Godot runtime."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


class MobileControlsTest(unittest.TestCase):
    def test_touch_controls_are_in_the_shared_hud(self):
        scene = read("scenes/ui/rally_hud.tscn")
        self.assertIn('path="res://scripts/ui/touch_controls.gd" id="13_touch_controls"', scene)
        self.assertIn('[node name="TouchControls" type="Control" parent="."]', scene)
        self.assertIn('script = ExtResource("13_touch_controls")', scene)

    def test_controls_support_multitouch_drag_and_existing_actions(self):
        controls = read("scripts/ui/touch_controls.gd")
        for token in (
            "signal pause_requested",
            "InputEventScreenTouch",
            "InputEventScreenDrag",
            "_touch_actions",
            "_action_holds",
            "Input.action_press(action, 1.0)",
            "Input.action_release(action)",
            '"steer_left"',
            '"steer_right"',
            '"throttle"',
            '"brake"',
            '"handbrake"',
            '"pause"',
            "NOTIFICATION_APPLICATION_FOCUS_OUT",
        ):
            self.assertIn(token, controls)

    def test_controls_hide_for_pause_results_and_input_settings(self):
        controls = read("scripts/ui/touch_controls.gd")
        for panel in ('"PausePanel"', '"ResultsPanel"', '"InputSettings"'):
            self.assertIn(panel, controls)
        self.assertIn("get_tree().paused", controls)
        self.assertIn("_release_all()", controls)

    def test_both_modes_connect_touch_pause(self):
        for rel in ("scripts/rally_stage.gd", "scripts/arcade/arcade_stage.gd"):
            stage = read(rel)
            self.assertIn("TouchControls", stage)
            self.assertIn('has_signal("pause_requested")', stage)
            self.assertIn('Callable(self, "_on_touch_pause_requested")', stage)
            self.assertIn("func _on_touch_pause_requested()", stage)

    def test_web_and_mobile_use_reduced_rendering_cost(self):
        settings = read("scripts/ui/game_settings.gd")
        self.assertIn('OS.has_feature("web") or OS.has_feature("mobile")', settings)
        self.assertIn("Engine.physics_ticks_per_second = 60", settings)
        self.assertIn("viewport.scaling_3d_scale = 0.72", settings)
        self.assertIn("viewport.msaa_3d = 0 if low_power else msaa_index()", settings)
        self.assertIn("disable_low_power_light_shadows", settings)

        for rel in ("scripts/rally_stage.gd", "scripts/arcade/arcade_stage.gd"):
            stage = read(rel)
            self.assertIn("env.glow_enabled = not low_power_render", stage)
            self.assertIn("and not low_power_render", stage)
            self.assertIn("volumetric and not low_power_render", stage)

        shader = read("shaders/speed_fx.gdshader")
        self.assertIn("uniform bool low_power_mode = false", shader)
        self.assertIn("if (!low_power_mode && mask > 0.001)", shader)

    def test_normal_rally_hud_updates_at_a_bounded_rate(self):
        stage = read("scripts/rally_stage.gd")
        self.assertIn("const HUD_REFRESH: float = 0.08", stage)
        self.assertIn("if _hud_clock >= HUD_REFRESH:", stage)
        self.assertIn("_update_hud()", stage)


if __name__ == "__main__":
    unittest.main()
