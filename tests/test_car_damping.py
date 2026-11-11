"""Скрытое демпфирование движка не должно возвращаться на кузов машины.

У RigidBody3D в Godot по умолчанию действует ``physics/3d/default_linear_damp``
= 0.1: сила «0.1 · масса · скорость», которой нет в формулах игры. Из-за неё
стоковая машина упиралась в ~140 км/ч при любой главной паре. Динамику
проверяет ``tests/top_speed.gd``; здесь — конфигурация, чтобы ошибку было
видно и без Godot.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]

# Сцены, у которых корень — само тело RallyCar.
CAR_SCENES = ("scenes/rally_car.tscn", "scenes/rally_car2.tscn")
# RigidBody3D.DAMP_MODE_REPLACE: собственное значение тела заменяет проектное.
DAMP_MODE_REPLACE = "1"


def text(path):
    return (ROOT / path).read_text(encoding="utf-8")


def node_blocks(scene, name):
    """Свойства всех узлов с этим именем: {заголовок: {ключ: значение}}."""
    blocks = {}
    for match in re.finditer(r'^\[node name="%s"[^\n]*\]\n(.*?)(?=^\[|\Z)' % re.escape(name), scene, re.S | re.M):
        props = dict(re.findall(r"^(\w+) = (.*)$", match.group(1), re.M))
        blocks[match.group(0).splitlines()[0]] = props
    return blocks


class CarDampingConfig(unittest.TestCase):
    def test_car_body_replaces_engine_default_linear_damping(self):
        for path in CAR_SCENES:
            blocks = node_blocks(text(path), "RallyCar")
            self.assertEqual(len(blocks), 1, path)
            props = next(iter(blocks.values()))
            self.assertEqual(props.get("linear_damp_mode"), DAMP_MODE_REPLACE, path)
            self.assertEqual(float(props.get("linear_damp", "0")), 0.0, path)

    def test_no_scene_brings_the_damping_back(self):
        for scene_path in sorted((ROOT / "scenes").rglob("*.tscn")):
            relative = scene_path.relative_to(ROOT).as_posix()
            if relative in CAR_SCENES:
                continue
            scene = scene_path.read_text(encoding="utf-8")
            for header, props in node_blocks(scene, "RallyCar").items():
                self.assertNotIn("linear_damp_mode", props, relative + " " + header)
                self.assertNotIn("linear_damp", props, relative + " " + header)

    def test_aero_is_a_setup_field(self):
        # Сообщения короткие: assertIn напечатал бы весь файл целиком.
        setup = text("scripts/data/rally_car_setup.gd")
        self.assertTrue('@export_group("Аэродинамика")' in setup, "в RallyCarSetup нет группы «Аэродинамика»")
        for field in ("coefficient_of_drag", "frontal_area"):
            self.assertTrue(re.search(r"var %s: float = [0-9.]+" % field, setup), "в RallyCarSetup нет поля " + field)
            self.assertTrue("%s = setup_resource.%s" % (field, field) in text("scripts/rally_car.gd"), "apply_setup() не читает " + field)


if __name__ == "__main__":
    unittest.main()
