"""Guard scene-specific liveries, backward compatibility and persistence wiring."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def car_scenes():
    """Все игровые сцены машин: список не должен жить в тесте."""
    return sorted(scene.relative_to(ROOT).as_posix()
                  for scene in (ROOT / "scenes").glob("rally_car*.tscn"))


def texture_array(text):
    """Id внешних ресурсов из livery_textures (пусто, если поля нет)."""
    m = re.search(r'^livery_textures = Array\[Texture2D\]\(\[(.*?)\]\)', text, re.M)
    return re.findall(r'ExtResource\("([^"]+)"\)', m.group(1)) if m else []


def name_array(text):
    """Подписи ливрей из livery_names."""
    m = re.search(r'^livery_names = Array\[String\]\(\[(.*?)\]\)', text, re.M)
    return re.findall(r'"([^"]*)"', m.group(1)) if m else []


def resource_path(text, ext_id):
    """Путь внешнего ресурса по его id."""
    m = re.search(rf'\[ext_resource [^\n]*path="([^"]+)" id="{re.escape(ext_id)}"\]', text)
    return m.group(1) if m else ext_id


class LiveryScenesTest(unittest.TestCase):
    def test_liveries_are_owned_by_each_car(self):
        """Ливреи принадлежат сцене машины, а не общему списку в коде.

        Число ливрей у машин своё: три у Lancer, четыре у Subaru и ни одной у
        Golf R32 — он ездит в заводской краске модели, поэтому селектор ливрей
        в гараже для него выключен, а тон кузова красит поверхность кузова.
        """
        scenes = car_scenes()
        self.assertTrue(scenes, "в scenes/ нет сцен машин rally_car*.tscn")
        owners = {}
        for scene in scenes:
            text = read(scene)
            textures = texture_array(text)
            names = name_array(text)
            if textures:
                self.assertEqual(len(textures), len(names),
                                 f"{scene}: на каждую ливрею нужна подпись")
                self.assertTrue(all(name.strip() for name in names),
                                f"{scene}: пустая подпись ливреи")
            else:
                self.assertEqual(names, [], f"{scene}: подписи ливрей без самих текстур")
            for ext_id in textures:
                path = resource_path(text, ext_id)
                self.assertNotIn(path, owners,
                                 f"{scene}: ливрея {path} уже принадлежит {owners.get(path)}")
                owners[path] = scene

            # Краска и грязь: ровно один меш покраски, и он же помечен для эффектов.
            paint = re.findall(
                r'\[node name="([^"]+)" type="MeshInstance3D"[^\n]*groups=\[([^\]]*)\]', text)
            painted = [name for name, groups in paint if '"rally_body_paint"' in groups]
            self.assertEqual(len(painted), 1,
                             f"{scene}: меш покраски должен быть ровно один, найдено {painted}")
            if painted:
                groups = next(g for name, g in paint if name == painted[0])
                self.assertIn('"rally_body_fx"', groups,
                              f"{scene}: меш покраски {painted[0]} должен получать грязь")
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
