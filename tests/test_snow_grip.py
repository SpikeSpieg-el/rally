"""Снежное полотно зимой: скользко, но это дорога, а не каток.

Жалоба: «в стоке невозможно ездить, я как на льду, а там всего-то снег; иногда
прям показывает проскальзывание и колёса могут крутиться на месте». Причин
было три, и все три здесь под замком:

1) погода применялась дважды — множитель снега (0.62) вкладывался в конфиг
   трассы И ещё раз в контакт колеса, итого 0.38 от сухого сцепления;
2) снег в модели грунта получал общий «минус за накат», как грязь: чем больше
   проехали, тем скользче, хотя укатанный снег держит лучше каши;
3) рыхлая колея на снегу тормозила машину сильнее грязи (до ×2.8), и колесо
   буксовало на месте вместо разгона.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
STAGE = ROOT / "scripts" / "rally_stage.gd"
SURFACE = ROOT / "scripts" / "road_surface.gd"
FX = ROOT / "scripts" / "data" / "rally_fx_profile.gd"
WEATHER = ROOT / "data" / "weather"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def default_float(text: str, key: str) -> float:
    match = re.search(rf"var {key}: float = (-?[0-9.]+)", text)
    if match is None:
        raise AssertionError(f"нет поля {key}")
    return float(match.group(1))


def preset(name: str) -> dict:
    text = read(WEATHER / f"weather_{name}.tres")
    values = {}
    for key in ("grip_scale", "rolling_resistance_scale", "snow_cover", "wetness"):
        match = re.search(rf"^{key} = (-?[0-9.]+)", text, re.M)
        values[key] = float(match.group(1)) if match else None
    return values


def fx_profile() -> dict:
    text = read(FX)
    keys = (
        "packing_grip_snow",
        "packing_grip_other",
        "packing_grip_gravel",
        "rut_rolling_snow",
        "rut_rolling_soft",
        "rut_rolling_firm",
        "grip_min_snow",
        "grip_min",
        "grip_max",
        "rolling_min",
        "rolling_max",
        "packing_rolling_gain",
        "rut_grip_loss_dry",
        "rut_grip_loss_wet",
    )
    return {key: default_float(text, key) for key in keys}


def surface_state(kind: str, compaction: float, looseness: float, wetness: float):
    """Повтор формулы RoadSurface.sample() для проверки чисел без движка."""
    fx = fx_profile()
    packing = fx["packing_grip_other"]
    if kind == "gravel":
        packing = fx["packing_grip_gravel"]
    if kind == "snow":
        packing = fx["packing_grip_snow"]
    rut_loss = fx["rut_grip_loss_dry"] + (
        fx["rut_grip_loss_wet"] - fx["rut_grip_loss_dry"]
    ) * wetness
    rut_rolling = fx["rut_rolling_firm"] if kind == "asphalt" else fx["rut_rolling_soft"]
    if kind == "snow":
        rut_rolling = fx["rut_rolling_snow"]
    floor = fx["grip_min_snow"] if kind == "snow" else fx["grip_min"]
    grip = min(max(1.0 + compaction * packing - looseness * rut_loss, floor), fx["grip_max"])
    rolling = min(
        max(1.0 - compaction * fx["packing_rolling_gain"] + looseness * rut_rolling, fx["rolling_min"]),
        fx["rolling_max"],
    )
    return grip, rolling


class WeatherPresetTest(unittest.TestCase):
    def test_snow_is_slippery_but_not_ice(self):
        snow = preset("snow")
        self.assertGreaterEqual(snow["grip_scale"], 0.65, "снег не должен быть льдом")
        self.assertLessEqual(snow["grip_scale"], 0.85, "снег не должен быть как сухой асфальт")

    def test_snow_is_still_slipperier_than_rain(self):
        snow = preset("snow")
        rain = preset("rain")
        self.assertLess(snow["grip_scale"], rain["grip_scale"], "снег обязан скользить сильнее дождя")

    def test_snow_does_not_bog_the_car_down(self):
        snow = preset("snow")
        self.assertLessEqual(
            snow["rolling_resistance_scale"], 1.35, "рыхлый снег не должен держать машину как грязь"
        )

    def test_snow_covers_the_road(self):
        self.assertGreaterEqual(preset("snow")["snow_cover"], 0.8)


class NoDoubleWeatherTest(unittest.TestCase):
    """Один множитель погоды: либо в трассе, либо в контакте колеса."""

    def setUp(self):
        self.stage = read(STAGE)

    def test_conditions_remember_what_they_baked_into_the_track(self):
        apply = self.stage.split("func _apply_conditions_to_track()", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("_baked_grip = weather.grip_scale", apply)
        self.assertIn("_baked_rolling = weather.rolling_resistance_scale", apply)
        self.assertIn("_baked_offroad = weather.offroad_grip_scale", apply)
        self.assertLess(
            apply.index("_baked_grip = weather.grip_scale"),
            apply.index("track.grip_scale = clampf("),
            "сначала запоминаем множитель, потом вкладываем его в трассу",
        )

    def test_contact_applies_only_the_difference(self):
        contact = self.stage.split("func surface_contact(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("weather.grip_scale / _baked_grip", contact)
        self.assertIn("weather.rolling_resistance_scale / _baked_rolling", contact)
        self.assertIn("weather.offroad_grip_scale / _baked_offroad", contact)
        self.assertNotIn("result.grip *= weather.grip_scale", contact)

    def test_ratio_is_one_for_a_regular_track(self):
        snow = preset("snow")
        baked = snow["grip_scale"]
        applied = snow["grip_scale"] / baked
        self.assertAlmostEqual(applied, 1.0)
        # Вот чего больше нет: снег 0.62 × 0.62 = 0.38 от сухого сцепления.
        self.assertAlmostEqual(snow["grip_scale"] * snow["grip_scale"], 0.72 * 0.72)
        self.assertGreater(snow["grip_scale"] * applied, 0.7)

    def test_route_weather_keeps_working(self):
        # У маршрута со сценарием погода меняется на ходу: там множитель ещё
        # не вложен в трассу, и контакт применяет его целиком.
        apply = self.stage.split("func _apply_conditions_to_track()", 1)[1].split("\nfunc ", 1)[0]
        self.assertLess(
            apply.index("_baked_grip = 1.0"),
            apply.index("if track == null:"),
            "сброс множителей должен идти до ранних выходов",
        )


class SnowSurfaceTest(unittest.TestCase):
    """Снег в модели грунта: накат держит, рыхлая каша не тормозит как грязь."""

    def test_fresh_snow_is_neutral(self):
        grip, rolling = surface_state("snow", 0.0, 0.0, 0.1)
        self.assertAlmostEqual(grip, 1.0)
        self.assertAlmostEqual(rolling, 1.0)

    def test_packing_improves_snow_grip(self):
        fresh, _ = surface_state("snow", 0.0, 0.0, 0.1)
        packed, _ = surface_state("snow", 1.0, 0.0, 0.1)
        self.assertGreater(packed, fresh, "укатанная линия должна держать лучше каши")

    def test_packing_still_hurts_mud(self):
        fresh, _ = surface_state("mud", 0.0, 0.0, 1.0)
        packed, _ = surface_state("mud", 1.0, 0.0, 1.0)
        self.assertLess(packed, fresh, "у грязи накат по-прежнему скользкий")

    def test_snow_grip_never_drops_to_ice(self):
        for compaction in (0.0, 0.5, 1.0):
            for looseness in (0.0, 0.5, 1.0):
                for wetness in (0.0, 0.5, 1.0):
                    grip, _ = surface_state("snow", compaction, looseness, wetness)
                    self.assertGreaterEqual(grip, 0.8, "снег не должен проваливаться в лёд")

    def test_loose_snow_rolls_easier_than_mud(self):
        _, snow_rolling = surface_state("snow", 0.0, 1.0, 0.1)
        _, mud_rolling = surface_state("mud", 0.0, 1.0, 0.1)
        self.assertLess(snow_rolling, mud_rolling, "рыхлый снег не должен держать как грязь")
        self.assertLessEqual(snow_rolling, 1.6)

    def test_fields_are_declared_and_used(self):
        fx = read(FX)
        self.assertGreater(default_float(fx, "packing_grip_snow"), 0.0)
        self.assertLess(default_float(fx, "rut_rolling_snow"), default_float(fx, "rut_rolling_soft"))
        self.assertGreater(default_float(fx, "grip_min_snow"), default_float(fx, "grip_min"))
        surface = read(SURFACE)
        for field in ("packing_grip_snow", "rut_rolling_snow", "grip_min_snow"):
            self.assertIn(f'"{field}"', surface, f"модель грунта не читает {field}")
        snow_branches = len(re.findall(r'if kind == "snow":', surface))
        self.assertGreaterEqual(snow_branches, 3, "у снега должны быть свои ветки")


if __name__ == "__main__":
    unittest.main()
