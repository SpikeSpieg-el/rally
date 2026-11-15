"""Guard scene-specific liveries, backward compatibility and persistence wiring."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class LiveryScenesTest(unittest.TestCase):
    def test_liveries_are_owned_by_each_car(self):
        evo = read("scenes/rally_car.tscn")
        subaru = read("scenes/rally_car2.tscn")
        self.assertIn('livery_textures = Array[Texture2D]([ExtResource("livery_0"), ExtResource("livery_1"), ExtResource("livery_2")])', evo)
        self.assertIn('livery_textures = Array[Texture2D]([ExtResource("9_helpe")])', subaru)
        body = re.search(r'\[node name="Impreza_GC8_Body"[^\n]+', subaru).group()
        self.assertIn('"rally_body_paint"', body)
        self.assertIn('"rally_body_fx"', body)
        self.assertNotIn('иташа', subaru)
        self.assertNotIn('const LIVERIES', read("scripts/car_visual_customization.gd"))

    def test_preview_race_and_persistence_use_per_car_list(self):
        car = read("scripts/rally_car.gd")
        garage = read("scripts/garage_menu.gd")
        models = read("scripts/car_models.gd")
        schema = read("scripts/car_customization.gd")
        self.assertIn('CarVisuals.apply_body(model, active_setup, livery_textures)', car)
        self.assertIn('setup, _livery_textures())', garage)
        self.assertIn('preview.set_meta("livery_textures", car.get("livery_textures"))', models)
        self.assertIn('livery_choice.clear()', garage)
        self.assertIn('clampi(int(value), 0, 4095)', schema)
        self.assertIn('set_blood_splats', read('scripts/surface_effects.gd'))


if __name__ == '__main__':
    unittest.main()
