"""Регрессионные проверки 4-режимного времени суток и переделанного «Ночного леса»."""
from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import check_road_collision  # noqa: E402
import stage_model as model  # noqa: E402


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def script_scalar(text: str, key: str) -> float:
    m = re.search(rf"var {key}:\s*(?:float|int)\s*=\s*(-?[0-9.]+)", text)
    if m is None:
        raise AssertionError(f"не найдено поле {key}")
    return float(m.group(1))


def script_color(text: str, key: str) -> list:
    m = re.search(rf"var {key}:\s*Color\s*=\s*Color\(([^)]+)\)", text)
    if m is None:
        raise AssertionError(f"не найден цвет {key}")
    return [float(x) for x in m.group(1).split(",")[:3]]


def tres_scalar(text: str, key: str) -> float:
    m = re.search(rf"^{key}\s*=\s*(-?[0-9.]+)", text, re.M)
    if m is None:
        raise AssertionError(f"не найдено свойство .tres {key}")
    return float(m.group(1))


class TimeOfDayPresetsTest(unittest.TestCase):
    def test_weather_enum_has_five_states_in_natural_order(self):
        weather = read("scripts/data/rally_weather_config.gd")
        self.assertIn("enum TimeOfDay { KEEP, MORNING, DAY, EVENING, NIGHT }", weather)
        self.assertIn('@export_enum("Как на трассе", "Утро", "День", "Вечер", "Ночь")', weather)
        for fn in ("is_night_time", "explicit_time_choice", "resolve_time_choice", "resolve_night_choice"):
            self.assertIn(f"static func {fn}(", weather)

    def test_menu_and_game_state_match_five_choices(self):
        game = read("scripts/game_state.gd")
        self.assertIn("const TIME_CHOICE_COUNT := 5", game)
        layout = read("scripts/data/rally_menu_layout.gd")
        self.assertIn('"КАК НА ТРАССЕ", "УТРО", "ДЕНЬ", "ВЕЧЕР", "НОЧЬ"', layout)
        self.assertIn('"УТРО", "ДЕНЬ", "ВЕЧЕР", "НОЧЬ"', layout)
        panel = read("scripts/garage_track_panel.gd")
        self.assertIn("WeatherType.resolve_time_choice(", panel)

    def test_stage_settings_define_distinct_morning_day_evening_night_presets(self):
        settings = read("scripts/data/rally_stage_settings.gd")
        # Утро: низкое тёплое солнце и тёплый рассветный горизонт.
        self.assertGreater(script_scalar(settings, "morning_sun_pitch"), -20.0)
        morning_horizon = script_color(settings, "morning_sky_horizon")
        self.assertGreater(morning_horizon[0], morning_horizon[2])
        # День: яркое высокое солнце и дальний горизонт.
        self.assertGreaterEqual(script_scalar(settings, "day_sun_energy"), 1.2)
        self.assertGreaterEqual(script_scalar(settings, "day_fog_far"), 280.0)
        # Вечер: бывшая светлая «ночь» (сумерки).
        self.assertGreaterEqual(script_scalar(settings, "evening_ambient_energy"), 0.7)
        self.assertAlmostEqual(script_scalar(settings, "evening_sun_energy"), 0.48, places=2)
        self.assertGreaterEqual(script_scalar(settings, "evening_fog_far"), 220.0)
        # Ночь: глубокая тёмная ночь как на трассе Англии.
        self.assertLessEqual(script_scalar(settings, "night_ambient_energy"), 0.15)
        self.assertLessEqual(script_scalar(settings, "night_sun_energy"), 0.22)
        self.assertLessEqual(script_scalar(settings, "night_fog_far"), 150.0)
        self.assertIn("var night_volumetric_fog: bool = true", settings)

    def test_stage_and_arcade_apply_all_four_presets(self):
        for rel in ("scripts/rally_stage.gd", "scripts/arcade/arcade_stage.gd"):
            text = read(rel)
            for mode in ("MORNING", "DAY", "EVENING", "NIGHT"):
                self.assertIn(f"WeatherType.TimeOfDay.{mode}", text, f"{rel}: нет ветки {mode}")
            self.assertIn("deg_to_rad(sun_pitch)", text, rel)
            self.assertIn("fog_near * _weather_visibility_scale()", text, rel)
            self.assertIn("fog_far * _weather_visibility_scale()", text, rel)


class ForestStageRedesignTest(unittest.TestCase):
    def test_scene_is_clean_and_has_no_baked_prop_clutter(self):
        scene = read("scenes/rally_stage.tscn")
        self.assertNotIn("Pine_001", scene)
        self.assertNotIn("feel = ", scene)
        self.assertIn('name="Props" type="Node3D"', scene)
        self.assertIn("shader_parameter/retro_strength = 1.0", scene)
        self.assertIn("shader_parameter/zone_contrast = 0.28", scene)
        self.assertIn("shader_parameter/puddle_mix = 0.35", scene)

    def test_forest_track_uses_dense_procedural_forest_and_england_dark_night(self):
        forest = read("data/tracks/stage_forest.tres")
        self.assertIn("use_baked_props = false", forest)
        self.assertIn("procedural_scenery = true", forest)
        self.assertGreaterEqual(tres_scalar(forest, "scenery_density"), 1.5)
        self.assertIn("dense_forest_scenery.tres", forest)
        # Родная ночь такая же глубокая, как в Англии.
        self.assertLessEqual(tres_scalar(forest, "ambient_energy"), 0.15)
        self.assertLessEqual(tres_scalar(forest, "sun_energy"), 0.22)
        self.assertLessEqual(tres_scalar(forest, "fog_far"), 150.0)
        self.assertIn("volumetric_fog = true", forest)
        # Плотный лесной конфиг не ломает default_scenery.tres.
        dense = read("data/stage/dense_forest_scenery.tres")
        self.assertIn("forest_in_all_zones = true", dense)
        self.assertGreater(tres_scalar(dense, "cluster_floor"), 0.4)
        self.assertLess(tres_scalar(dense, "tree_spacing_scale"), 0.8)
        self.assertGreater(tres_scalar(dense, "near_road_tree_bias"), 0.2)

    def test_forest_route_is_rich_elevation_and_collision_clean(self):
        samples = model.sample_curve(
            model.load_curve(str(ROOT / "data/tracks/stage_forest_route.tres")), 2.0
        )
        length = sum(
            ((samples[i][0] - samples[i - 1][0]) ** 2
             + (samples[i][2] - samples[i - 1][2]) ** 2) ** 0.5
            for i in range(1, len(samples))
        )
        ys = [p[1] for p in samples]
        self.assertGreater(length, 3600.0)
        self.assertLess(length, 4900.0)
        self.assertGreater(max(ys) - min(ys), 50.0)
        poke, _cell = check_road_collision.analyse(str(ROOT / "data/tracks/stage_forest.tres"), verbose=False)
        self.assertLessEqual(poke, check_road_collision.POKE_LIMIT)


if __name__ == "__main__":
    unittest.main()
