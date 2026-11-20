"""Границы визуальных повреждений кузова; сама деформация проверяется в tests/car_damage_visual.gd.

Система сдана на пробу только на Lancer и обязана оставаться косметической:
здоровье, урон, счёт и физика не меняются. Здесь проверяются те инварианты,
которые видны из текста кода, — движок доказывает остальное.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

VISUAL = "scripts/car_damage_visual.gd"
CAR = "scripts/rally_car.gd"


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def function_body(text, name):
    """Тело функции GDScript вместе с сигнатурой: до следующего объявления верхнего уровня.

    Всё, что принадлежит функции, в GDScript сдвинуто табуляцией, поэтому
    границей считаем любую строку от нулевой колонки.
    """
    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if re.match(r"^func %s\b" % re.escape(name), line):
            start = i
            break
    assert start is not None, f"в файле нет функции {name}"
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if re.match(r"^(func |static func |var |const |signal |class |enum |@export|#)", lines[j]):
            end = j
            break
    return "\n".join(lines[start:end])


class CarDamageVisualTest(unittest.TestCase):
    def test_enabled_for_lancer_only(self):
        car = read(CAR)
        ids = re.search(r"const DAMAGE_VISUAL_IDS := \[([^\]]*)\]", car)
        self.assertIsNotNone(ids, "нет списка машин с визуальными вмятинами")
        listed = [item.strip().strip('"') for item in ids.group(1).split(",") if item.strip()]
        self.assertEqual(listed, ["mitsubishi"], "систему сдаём на пробу только на Lancer")
        install = function_body(car, "_install_damage_visual")
        self.assertIn("DAMAGE_VISUAL_IDS.has(vehicle_id)", install,
                      "компонент ставится только машинам из списка")
        self.assertIn("cinematic_mode", install, "в кинематографической витрине кузов не бьётся")
        self.assertIn("contact_monitor = true", install,
                      "без записи контактов физика не отдаёт точку удара")

    def test_other_cars_keep_physics_as_is(self):
        # Запись контактов включается только вместе с компонентом и снимается,
        # если деформировать нечего: у остальных машин поведение прежнее.
        install = function_body(read(CAR), "_install_damage_visual")
        self.assertIn("contact_monitor = false", install)
        self.assertIn("max_contacts_reported = 0", install)
        for scene in sorted((ROOT / "scenes").glob("rally_car*.tscn")):
            text = scene.read_text(encoding="utf-8")
            self.assertNotIn("contact_monitor", text,
                             f"{scene.name}: запись контактов включается из кода, а не из сцены")

    def test_visual_layer_does_not_touch_health(self):
        gameplay = (r"\bhp\b", r"\bhealth\b", r"_apply_damage", r"\brun_ended\b",
                    r"\barcade\b", r"\bscore\b", r"traffic_event", r"pedestrian")
        visual = read(VISUAL).lower()
        for token in gameplay:
            self.assertIsNone(re.search(token, visual),
                              f"{VISUAL}: косметический слой не должен знать про {token}")
        car = read(CAR).lower()
        for name in ("_install_damage_visual", "_update_damage_visual"):
            body = function_body(car, name)
            for token in gameplay:
                self.assertIsNone(re.search(token, body),
                                  f"{CAR}:{name}: визуальные вмятины не трогают {token}")

    def test_deforms_only_marked_panels(self):
        visual = read(VISUAL)
        self.assertIn('is_in_group("rally_body_fx")', visual,
                      "деформируем только кузовные панели из группы rally_body_fx")
        # Покраска кузова живёт в override-материалах экземпляра меша: компонент
        # их не трогает, иначе ливрея и грязь на кузове поехали бы.
        self.assertNotIn("material_override", visual)
        self.assertNotIn("set_surface_override_material", visual)
        # Физика и столкновения — не его дело.
        for token in ("CollisionShape3D", "collision_layer", "collision_mask",
                      "linear_velocity", "angular_velocity", "\tmass"):
            self.assertNotIn(token, visual, f"{VISUAL}: компонент не должен трогать «{token}»")

    def test_vertex_data_is_carried_over_wholesale(self):
        visual = read(VISUAL)
        self.assertIn("surface_get_arrays", visual)
        self.assertIn("add_surface_from_arrays", visual)
        self.assertIn("surface_set_material", visual,
                      "материалы поверхностей переносятся на пересобранный меш")
        self.assertNotIn("surface_remove", visual)
        self.assertNotIn("ARRAY_INDEX] =", visual, "индексы треугольников не меняются")
        self.assertIn("orig_vertices", visual, "исходные вершины хранятся для сброса и статистики")

    def test_dent_appears_before_arcade_damage(self):
        # Кузов мнётся раньше, чем аркада снимает HP: лёгкие касания видны,
        # а порог урона в настройках аркады остаётся прежним.
        dent = float(re.search(r"const DAMAGE_VISUAL_MIN_DV_MPS := ([\d.]+)", read(CAR)).group(1))
        settings = read("scripts/data/rally_arcade_settings.gd")
        crash = float(re.search(r"var crash_min_dv_mps: float = ([\d.]+)", settings).group(1))
        self.assertLess(dent, crash, "вмятина должна появляться раньше, чем снимается HP")
        self.assertEqual(crash, 4.6, "порог урона аркады менять нельзя")

    def test_engine_check_is_wired_into_ci(self):
        workflow = read(".github/workflows/pages.yml")
        self.assertIn("tests/car_damage_visual.gd", workflow,
                      "движковая проверка вмятин обязана запускаться в CI")


if __name__ == "__main__":
    unittest.main()
