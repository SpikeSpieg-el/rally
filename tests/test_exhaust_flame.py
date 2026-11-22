"""Выстрелы пламени из выхлопа (textures/fire.png); работа в движке — tests/exhaust_flame.gd.

Пламя — косметика: настраивается ресурсом data/car/default_exhaust_flame.tres
(инспектор), не трогает физику, мощность и звук мотора, а звук только
сообщает о хлопке сигналом exhaust_pop.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

FX = "scripts/effects/exhaust_flame_fx.gd"
CONFIG = "scripts/data/rally_exhaust_flame_config.gd"
SETTINGS = "data/car/default_exhaust_flame.tres"
CAR = "scripts/rally_car.gd"
AUDIO = "scripts/engine_sound.gd"
FIRE = "textures/fire.png"
CAR_SCENES = ("scenes/rally_car.tscn", "scenes/rally_car2.tscn", "scenes/rally_car3.tscn")

## Физика и геймплей: пламени нельзя их касаться.
FORBIDDEN = (r"apply_(central_)?(impulse|force)", r"linear_velocity\s*=", r"angular_velocity\s*=",
             r"max_torque", r"\bmass\b", r"\bhp\b", r"\bhealth\b", r"\bscore\b",
             r"throttle_input\s*=", r"current_rpm\s*=", r"contact_monitor")


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class ExhaustFlameTest(unittest.TestCase):
    def test_files_exist(self):
        for path in (FX, CONFIG, SETTINGS, FIRE, FX + ".uid", CONFIG + ".uid"):
            self.assertTrue((ROOT / path).exists(), path)

    def test_settings_use_fire_texture(self):
        tres = read(SETTINGS)
        self.assertIn('script_class="RallyExhaustFlameConfig"', tres)
        self.assertIn('path="res://textures/fire.png"', tres)
        self.assertIn('path="res://scripts/data/rally_exhaust_flame_config.gd"', tres)
        self.assertIn("flame_texture = ExtResource(", tres)
        self.assertIn('preload("res://textures/fire.png")', read(CONFIG))
        fire_uid = re.search(r'uid="(uid://[a-z0-9]+)"', read(FIRE + ".import")).group(1)
        self.assertIn(fire_uid, tres)
        script_uid = read(CONFIG + ".uid").strip()
        self.assertIn(script_uid, tres)

    def test_config_exports_are_inspector_editable(self):
        config = read(CONFIG)
        self.assertIn("@tool", config)
        self.assertIn("class_name RallyExhaustFlameConfig", config)
        for group in ("Включение", "Когда стреляет", "Пламя", "Огненный шар", "Вспышка света", "Где выхлоп"):
            self.assertIn(f'@export_group("{group}")', config)
        for field in ("turbo_only", "sync_with_audio", "flame_length_m", "flame_life_sec",
                      "crackle_enabled", "upshift_enabled", "limiter_enabled",
                      "outlet_marker_prefix", "material_keywords", "manual_outlets", "fallback_outlet"):
            self.assertRegex(config, rf"@export(_range\([^)]*\))? var {field}\b")
        # Каждое поле ресурса существует в скрипте настройки.
        exported = set(re.findall(r"@export(?:_range\([^)]*\))? var (\w+)", config))
        for key in re.findall(r"^(\w+) = ", read(SETTINGS), flags=re.M):
            if key != "script":
                self.assertIn(key, exported, key)

    def test_resource_lists_every_field(self):
        exported = re.findall(r"@export(?:_range\([^)]*\))? var (\w+)", read(CONFIG))
        keys = re.findall(r"^(\w+) = ", read(SETTINGS), flags=re.M)
        for field in exported:
            self.assertIn(field, keys, f"{SETTINGS}: нет поля {field}")

    def test_car_installs_component(self):
        car = read(CAR)
        self.assertIn('DEFAULT_EXHAUST_FLAME_PATH := "res://data/car/default_exhaust_flame.tres"', car)
        self.assertIn("@export var exhaust_flame_config: RallyExhaustFlameConfig = null", car)
        self.assertIn("func _install_exhaust_flames()", car)
        self.assertIn("ExhaustFlameFx.new()", car)
        self.assertIn('get_node_or_null("EngineAudio")', car)
        self.assertIn("exhaust_flames.clear()", car)
        ready = car[car.index("func _ready()"):]
        ready = ready[:ready.index("\nfunc ", 1)]
        self.assertIn("_install_exhaust_flames()", ready)

    def test_audio_only_signals(self):
        audio = read(AUDIO)
        self.assertIn("signal exhaust_pop(strength: float)", audio)
        self.assertIn("exhaust_pop.emit(", audio)
        self.assertNotIn("ExhaustFlameFx.new", audio)
        self.assertNotIn("exhaust_flames", audio)

    def test_component_is_cosmetic(self):
        fx = read(FX)
        code = "\n".join(line for line in fx.splitlines() if not line.lstrip().startswith("#"))
        for token in FORBIDDEN:
            self.assertIsNone(re.search(token, code), token)
        self.assertIn("BLEND_MODE_ADD", fx)
        self.assertIn("SHADING_MODE_UNSHADED", fx)
        self.assertIn('connect("exhaust_pop"', fx)
        # Пул: во время езды узлы не создаются.
        process = fx[fx.index("func _process("):fx.index("# Сборка")]
        self.assertNotIn(".new()", process)
        self.assertNotIn("add_child", process)

    def test_car_scenes_have_exhaust_material(self):
        # Автоопределение труб ищет слово «exhaust» в материалах.
        for scene in CAR_SCENES:
            self.assertRegex(read(scene).lower(), r'resource_name = "[^"]*exhaust', scene)
            self.assertNotIn("contact_monitor", read(scene))


if __name__ == "__main__":
    unittest.main()
