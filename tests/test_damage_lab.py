"""Лаборатория деформации кузова: тестовая сцена для показа вмятин без заезда.

Проверки статические (Godot не нужен) и держат главное обещание лаборатории:
  * сцена scenes/editor/damage_lab.tscn существует и собрана из настоящих узлов
    (свет, камера, земля, держатель модели), скрипт — scripts/editor/damage_lab.gd;
  * кузов выбирается в инспекторе: enum реестра (Lancer/Golf/Subaru) и поле
    custom_car_scene для произвольной сцены;
  * настройка деформации — поле damage_config (RallyDamageVisualConfig) с
    запасным путём на data/car/default_damage_visual.tres, ресурс дублируется,
    чтобы лаборатория не портила игровые числа;
  * деформация идёт через тот же компонент, что в игре (CarDamageVisual):
    setup/apply_impact/clear_damage/deformation_stats, клик — через луч
    intersect_ray по коллайдеру-подборщику, зоны — preset_impact/random_impact;
  * лаборатория остаётся косметической: здоровья, урона и счёта она не знает;
  * движковая проверка tests/damage_lab.gd и эта статическая запущены в CI,
    документация описывает лабораторию.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

SCENE = "scenes/editor/damage_lab.tscn"
SCRIPT = "scripts/editor/damage_lab.gd"
ENGINE_TEST = "tests/damage_lab.gd"
WORKFLOW = ".github/workflows/pages.yml"
DOC = "docs/CAR_DAMAGE_VISUAL_RU.md"

## Токены геймплея: лаборатория — косметический стенд, им не место в скрипте.
GAMEPLAY_TOKENS = (r"\bhp\b", r"\bhealth\b", r"_apply_damage", r"\brun_ended\b",
                   r"\barcade\b", r"\bscore\b", r"traffic_event", r"pedestrian")


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class DamageLabSceneTest(unittest.TestCase):
    def setUp(self):
        self.scene = read(SCENE)
        self.script = read(SCRIPT)

    def test_scene_exists_and_uses_lab_script(self):
        self.assertIn('path="res://%s"' % SCRIPT, self.scene,
                      "сцена обязана ссылаться на скрипт лаборатории")
        self.assertIn('name="DamageLab"', self.scene, "корень сцены — DamageLab")
        self.assertIn("editor_description", self.scene,
                      "у сцены должно быть описание для редактора")

    def test_scene_has_stage_nodes(self):
        for node in ("WorldEnvironment", "Sun", "Camera3D", "Ground", "ModelRoot", "Hint"):
            self.assertIn('name="%s"' % node, self.scene, f"нет узла {node}")
        self.assertIn("current = true", self.scene, "камера сцены обязана быть текущей")

    def test_body_is_chosen_in_inspector(self):
        self.assertIn('@export_enum("Lancer (mitsubishi)", "Golf (golf)", "Subaru (subaru)")',
                      self.script, "кузов реестра выбирается enum'ом в инспекторе")
        self.assertIn("@export var custom_car_scene: PackedScene = null", self.script,
                      "произвольный кузов назначается сценой в инспекторе")
        self.assertIn('"mitsubishi", "golf", "subaru"', self.script,
                      "все три машины реестра доступны в лаборатории")

    def test_deformation_settings_are_in_inspector(self):
        self.assertIn("@export var damage_config: RallyDamageVisualConfig = null", self.script,
                      "настройка деформации — поле инспектора")
        self.assertIn('const DEFAULT_DAMAGE_PATH := "res://data/car/default_damage_visual.tres"',
                      self.script, "пустое поле берёт игровой ресурс по умолчанию")
        self.assertIn("base.duplicate() as RallyDamageVisualConfig", self.script,
                      "ресурс дублируется: лаборатория не портит игровую настройку")
        for field in ("impact_dv_mps", "demo_on_start", "demo_interval_sec",
                      "auto_rotate", "camera_distance", "show_markers", "show_stats"):
            self.assertIn("var %s" % field, self.script,
                          f"поле {field} обязано настраиваться в инспекторе")

    def test_uses_the_game_deformation_component(self):
        self.assertIn("CarModels.make_model(", self.script,
                      "кузов берётся той же витриной, что в гараже")
        self.assertIn("_damage.setup(_model_root, _model_root, _active_config())", self.script,
                      "компонент ставится на модель лаборатории")
        self.assertIn("_damage.apply_impact(", self.script, "удар идёт через apply_impact")
        self.assertIn("_damage.clear_damage()", self.script, "ремонт — через clear_damage")
        self.assertIn("_damage.deformation_stats()", self.script,
                      "статистика — через deformation_stats")

    def test_click_and_preset_impacts(self):
        self.assertIn("intersect_ray(", self.script, "клик по кузову — лучом из камеры")
        self.assertIn("collision_mask = PICKER_LAYER", self.script,
                      "луч ловит только коллайдер-подборщик лаборатории")
        self.assertIn("func preset_impact(preset: int) -> float:", self.script,
                      "зоны ударов — отдельные методы для кнопок и тестов")
        self.assertIn("func random_impact() -> float:", self.script,
                      "случайный удар — для режима показа")
        self.assertIn("func dent_at(point_space: Vector3, push_dir: Vector3, dv: float) -> float:",
                      self.script, "удар в точку — публичный метод для клика и тестов")

    def test_lab_is_cosmetic_only(self):
        text = self.script.lower()
        for token in GAMEPLAY_TOKENS:
            self.assertIsNone(re.search(token, text),
                              f"{SCRIPT}: лаборатория не должна знать про {token}")


class DamageLabEngineTest(unittest.TestCase):
    def test_engine_test_covers_all_bodies(self):
        text = read(ENGINE_TEST)
        for token in ("set_vehicle_index", "custom_car_scene", "damage_config",
                      "preset_impact", "dent_at", "repair", "deformation_stats",
                      "rally_car2.tscn"):
            self.assertIn(token, text, f"движковая проверка не покрывает {token}")
        self.assertIn("for index in range(3):", text,
                      "все три кузова реестра проверяются по очереди")

    def test_checks_are_wired_into_ci(self):
        workflow = read(WORKFLOW)
        self.assertIn("tests/damage_lab.gd", workflow,
                      "движковая проверка лаборатории обязана запускаться в CI")
        self.assertIn("tests.test_damage_lab", workflow,
                      "статическая проверка лаборатории обязана запускаться в CI")

    def test_documented(self):
        doc = read(DOC)
        self.assertIn("damage_lab", doc, "документация вмятин описывает лабораторию")
        self.assertIn("custom_car_scene", doc,
                      "документация объясняет, как подставить свой кузов")


if __name__ == "__main__":
    unittest.main()
