"""Дворники лобового стекла: отдельная сцена, авто-стирание крови, вайринг.

Godot не нужен: проверки фиксируют интеграционные точки, чтобы фича
не распалась молча — сцена осталась отдельным ресурсом (не скриптовой
геометрией), машина сообщает кабинный режим, а пульт крови умеет
отдавать и тереть стекло.
"""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


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
            "func set_viewing(",
            "wipe_glass",
            "glass_dirty",
            "park_degrees",
        ):
            self.assertIn(token, script, token)

    def test_car_installs_wipers_and_tracks_cockpit_view(self):
        for scene in ("scenes/rally_car.tscn", "scenes/rally_car2.tscn"):
            text = read(scene)
            self.assertIn("windshield_wipers.tscn", text, scene)
            self.assertIn('name="Wipers"', text, scene)
        car = read("scripts/rally_car.gd")
        for token in (
            'get_node_or_null("Wipers")',
            'wipers.setup(self)',
            "_sync_wiper_view",
            "CameraMode.COCKPIT_1ST",
        ):
            self.assertIn(token, car, token)

    def test_blood_fx_exposes_wipe_api(self):
        blood = read("scripts/effects/rally_blood_fx.gd")
        for token in (
            "func wipe_glass(",
            "func glass_dirty(",
            "_is_glass_zone",
            "PuddleShader",
        ):
            self.assertIn(token, blood, token)

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
