"""Торможение двигателем должно доходить до физики.

Параметр ``motor_brake`` (ползунок «Торможение двигателем» в гараже, поле
``engine_brake_scale`` сетапа) долго только записывался: модель мотора его не
читала, и ползунок ничего не менял. Динамику проверяет
``tests/engine_brake.gd``; здесь — связка «сетап → машина → мотор», чтобы
обрыв было видно и без Godot.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


def text(path):
    return (ROOT / path).read_text(encoding="utf-8")


def function_body(source, name):
    """Тело функции GDScript верхнего уровня: от ``func name`` до следующей."""
    match = re.search(r"^func %s\(.*?(?=^func |\Z)" % re.escape(name), source, re.S | re.M)
    return match.group(0) if match else ""


class EngineBrakeWiring(unittest.TestCase):
    def test_motor_reads_the_engine_brake(self):
        vehicle = text("scripts/gevp/vehicle.gd")
        brake = function_body(vehicle, "get_engine_brake_torque")
        self.assertTrue("motor_brake" in brake, "get_engine_brake_torque() не читает motor_brake")
        # И автомат, и ручная коробка с педалью сцепления считают мотор отдельно.
        for name in ("process_motor", "_process_manual_motor"):
            self.assertTrue(
                "get_engine_brake_torque(" in function_body(vehicle, name),
                name + "() не учитывает торможение двигателем",
            )

    def test_setup_scale_reaches_the_motor(self):
        car = text("scripts/rally_car.gd")
        self.assertTrue(
            "motor_brake = BASE_MOTOR_BRAKE * setup_resource.engine_brake_scale" in car,
            "apply_setup() не передаёт engine_brake_scale в motor_brake",
        )
        self.assertTrue(
            re.search(r"var engine_brake_scale: float = [0-9.]+", text("scripts/data/rally_car_setup.gd")),
            "в RallyCarSetup нет поля engine_brake_scale",
        )

    def test_garage_slider_edits_the_same_field(self):
        fields = text("scripts/car_customization.gd")
        self.assertTrue('"key":"engine_brake_scale"' in fields, "в гараже нет ползунка торможения двигателем")


if __name__ == "__main__":
    unittest.main()
