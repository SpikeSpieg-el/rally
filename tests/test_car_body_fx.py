"""Scene bindings for body effects and model-independent selection."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def car_scenes():
    """Все игровые сцены машин: список не должен жить в тесте.

    Имена моделей и кузовных мешей у машин свои («low poly lance evo»,
    «Volkswagen Golf R32 Mk4», «Subaru Impreza Coupe WRX Type R STi2»), поэтому
    тест читает их из сцены, а не хардкодит.
    """
    return sorted(scene.relative_to(ROOT).as_posix()
                  for scene in (ROOT / "scenes").glob("rally_car*.tscn"))


def grouped_meshes(text, model):
    """Меши модели с группами: [(имя, список групп)] для узлов внутри `model`."""
    found = re.findall(
        r'\[node name="([^"]+)" type="MeshInstance3D" parent="([^"]+)"[^\n]*groups=\[([^\]]*)\]',
        text)
    return [(name, groups) for name, parent, groups in found
            if parent == model or parent.startswith(model + "/")]


class BodyFxTest(unittest.TestCase):
    def test_every_car_has_explicit_model_and_effect_meshes(self):
        scenes = car_scenes()
        self.assertTrue(scenes, "в scenes/ нет сцен машин rally_car*.tscn")
        for scene in scenes:
            text = read(scene)
            model = re.search(r'body_model_path = NodePath\("([^"]+)"\)', text)
            self.assertIsNotNone(model, f"{scene}: нет body_model_path")
            name = model.group(1)
            root = re.search(r'\[node name="' + re.escape(name) + r'" type="Node3D" parent="\."', text)
            self.assertIsNotNone(root, f"{scene}: узел модели {name} не найден")
            meshes = grouped_meshes(text, name)
            self.assertTrue(meshes, f"{scene}: у модели {name} нет мешей с группами")
            fx = [mesh for mesh, groups in meshes if '"rally_body_fx"' in groups]
            paint = [mesh for mesh, groups in meshes if '"rally_body_paint"' in groups]
            self.assertTrue(fx, f"{scene}: нет мешей группы rally_body_fx — грязь не ляжет на кузов")
            self.assertEqual(len(paint), 1, f"{scene}: меш покраски должен быть ровно один, найдено {paint}")
            self.assertIn(paint[0], fx,
                          f"{scene}: меш покраски {paint[0]} должен быть и в rally_body_fx")

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


if __name__ == "__main__":
    unittest.main()
