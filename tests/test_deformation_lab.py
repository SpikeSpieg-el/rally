"""Тестовая сцена лаборатории деформации кузова.

Сцена scenes/editor/deformation_lab.tscn и скрипт scripts/editor/deformation_lab.gd
дают проверить и показать деформацию кузова выбранной машины. Все настройки —
импортные поля сцены и инспектора, деформацию задаёт существующий ресурс
RallyDamageVisualConfig. Тест статический: он читает сцену и скрипт,
поскольку в репозитории нет бинарника Godot для запуска.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

SCENE = "scenes/editor/deformation_lab.tscn"
SCRIPT = "scripts/editor/deformation_lab.gd"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class DeformationLabTest(unittest.TestCase):
    def setUp(self):
        self.scene = read(SCENE)
        self.script = read(SCRIPT)

    def test_scene_and_script_exist(self):
        self.assertIn("[gd_scene", self.scene)
        self.assertIn("extends Node3D", self.script)

    def test_root_is_tool_node_with_lab_script(self):
        self.assertIn("@tool", self.script)
        self.assertIn("class_name DeformationLab", self.script)
        root = re.search(r'\[node name="DeformationLab" type="Node3D"', self.scene)
        self.assertIsNotNone(root, "корень сцены должен быть Node3D DeformationLab")
        self.assertIn('script = ExtResource("1")', self.scene)
        self.assertIn(
            '[ext_resource type="Script" path="res://scripts/editor/deformation_lab.gd"',
            self.scene,
        )

    def test_scene_has_basic_nodes(self):
        for node in ("Environment", "CameraOrbit", "Ground", "Hint"):
            self.assertIn(f'[node name="{node}"', self.scene,
                          f"в сцене нет узла {node}")

    def test_camera_is_current(self):
        cam = re.search(r'\[node name="CameraOrbit" type="Camera3D"[^\n]*(?:\n[^\n]*){0,3}?current = true',
                        self.scene)
        self.assertIsNotNone(cam, "камера-обозреватель должна быть текущей (current = true)")

    def test_exported_fields_match_scene(self):
        """Каждое импортное поле сцены должно быть задано в самом .tscn."""
        exports = set(re.findall(r"@export var (\w+)", self.script))
        self.assertTrue(exports, "в скрипте нет @export полей")
        exports.discard("damage_config")  # ресурс задаётся через ExtResource
        for field in sorted(exports):
            self.assertIn(field + " =", self.scene,
                          f"поле {field} не задано в сцене (инспектор пустой)")
        self.assertIn("damage_config = ExtResource(", self.scene)

    def test_scene_uses_damage_visual_config_resource(self):
        self.assertIn(
            '[ext_resource type="Resource" path="res://data/car/default_damage_visual.tres"',
            self.scene,
        )
        self.assertIn("RallyDamageVisualConfig", self.script)

    def test_script_drives_car_damage_visual(self):
        for method in ("setup", "apply_impact", "clear_damage",
                       "impact_count", "panel_count"):
            self.assertIn(method, self.script,
                          f"скрипт не вызывает CarDamageVisual.{method}")
        self.assertIn("CarDamageVisual.new()", self.script)
        self.assertIn('is_in_group("rally_body_fx")', self.script)

    def test_script_uses_car_catalog_not_hardcoded_model(self):
        self.assertIn("CarModels", self.script)
        self.assertIn("make_model", self.script)
        # Модель и удары выбираются через каталог и инспектор, а не через
        # зажатые имена кузовных мешей.
        self.assertNotIn('"Mitsubishi_Body"', self.script)
        self.assertNotIn('"low poly lance evo"', self.script)

    def test_script_falls_back_to_default_config(self):
        self.assertIn("res://data/car/default_damage_visual.tres", self.script)

    def test_impact_fields_are_exported(self):
        for field in ("impact_point_local", "impact_push_dir", "impact_speed_mps"):
            self.assertIn(f"@export var {field}", self.script)


if __name__ == "__main__":
    unittest.main()
