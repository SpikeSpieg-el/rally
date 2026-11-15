"""Scene bindings for body effects and model-independent selection."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class BodyFxTest(unittest.TestCase):
    def test_both_cars_have_explicit_model_and_effect_meshes(self):
        for scene, model, meshes in (
            ("scenes/rally_car.tscn", "low poly lance evo", ("Mitsubishi_Body", "Mitsubishi_Body_002", "Mitsubishi_Body_003")),
            ("scenes/rally_car2.tscn", "Subaru Impreza Coupe WRX Type R STi", ("Impreza_GC8_Body",)),
        ):
            text = read(scene)
            self.assertIn(f'body_model_path = NodePath("{model}")', text)
            for mesh in meshes:
                node = re.search(r'\[node name="' + mesh + r'" type="MeshInstance3D"[^\n]+', text)
                self.assertIsNotNone(node, mesh)
                self.assertIn('"rally_body_fx"', node.group())

    def test_effects_share_overlay_without_name_based_search(self):
        surface = read("scripts/surface_effects.gd")
        blood = read("scripts/effects/rally_blood_fx.gd")
        shader = read("shaders/car_dirt.gdshader")
        car = read("scripts/rally_car.gd")
        self.assertIn('is_in_group("rally_body_fx")', surface)
        self.assertNotIn('"Mitsubishi_Body"', surface + blood + car)
        self.assertNotIn('"low poly lance evo"', car)
        self.assertIn('set_blood_splats', blood)
        self.assertIn('blood_coverage(body_position)', shader)
        self.assertIn('blood + dirt_alpha * (1.0 - blood)', shader)
        self.assertIn('subaru_blood_stains.tscn', read("scenes/rally_car2.tscn"))


if __name__ == "__main__":
    unittest.main()
