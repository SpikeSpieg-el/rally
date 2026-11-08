"""Ночная трасса не должна выглядеть «молочной».

`night_mode = true` включает звёздное небо и лунный свет, но цвета берутся
из самого `.tres` трассы. Если там остаётся дневная палитра (белый туман,
тёплое сильное солнце), получается ровно тот конфликт, из-за которого
«ЖИВАЯ ЛЕНТА» стала белой и молочной ночью. Эти проверки держат данные
трасс в согласии с флагом ночи.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
TRACKS = ROOT / "data" / "tracks"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def color(text: str, key: str) -> list:
    match = re.search(rf"^{key} = Color\(([^)]*)\)", text, re.M)
    if match is None:
        return None
    return [float(part) for part in match.group(1).split(",")[:3]]


def scalar(text: str, key: str, default: float = None):
    match = re.search(rf"^{key} = (-?[0-9.]+)", text, re.M)
    return float(match.group(1)) if match else default


def script_color(text: str, key: str) -> list:
    """Цвет из GDScript-объявления: @export var key: Color = Color(r, g, b, a)."""
    match = re.search(rf"var {key}: Color = Color\(([^)]*)\)", text)
    if match is None:
        return None
    return [float(part) for part in match.group(1).split(",")[:3]]


def luminance(rgb: list) -> float:
    return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]


def track_texts() -> list:
    return [
        (path, read(path))
        for path in sorted(TRACKS.glob("*.tres"))
        if "RallyTrackConfig" in read(path)
    ]


def night_tracks() -> list:
    return [(path, text) for path, text in track_texts() if re.search(r"^night_mode = true$", text, re.M)]


class NightTrackEnvironmentTest(unittest.TestCase):
    def test_there_is_at_least_one_night_track(self):
        self.assertTrue(night_tracks(), "ночных трасс не осталось")

    def test_night_fog_is_not_white(self):
        # Белый туман на ночном небе даёт молочную дымку на весь кадр.
        for path, text in night_tracks():
            fog = color(text, "fog_color")
            self.assertIsNotNone(fog, f"{path.name}: нет fog_color")
            self.assertLess(
                luminance(fog), 0.35,
                f"{path.name}: туман слишком светлый для ночи ({fog})",
            )

    def test_night_sky_is_dark(self):
        for path, text in night_tracks():
            top = color(text, "sky_top_color")
            horizon = color(text, "sky_horizon_color")
            self.assertIsNotNone(top, f"{path.name}: нет sky_top_color")
            self.assertIsNotNone(horizon, f"{path.name}: нет sky_horizon_color")
            self.assertLess(luminance(top), 0.15, f"{path.name}: верх неба светлый")
            self.assertLess(luminance(horizon), 0.25, f"{path.name}: горизонт светлый")

    def test_night_sun_is_dim_and_cool(self):
        # Дневное тёплое солнце 1.4 на ночном небе — вторая половина конфликта.
        for path, text in night_tracks():
            sun = color(text, "sun_color")
            energy = scalar(text, "sun_energy", 1.4)
            self.assertIsNotNone(sun, f"{path.name}: нет sun_color")
            self.assertLessEqual(energy, 1.0, f"{path.name}: солнце ночью слишком яркое")
            self.assertGreaterEqual(
                sun[2], sun[0],
                f"{path.name}: ночное солнце должно быть холодным ({sun})",
            )

    def test_night_ambient_stays_dark(self):
        for path, text in night_tracks():
            ambient = color(text, "ambient_color")
            self.assertIsNotNone(ambient, f"{path.name}: нет ambient_color")
            self.assertLess(luminance(ambient), 0.7, f"{path.name}: подсветка слишком яркая")

    def test_live_strip_is_a_night_track(self):
        # «ЖИВАЯ ЛЕНТА»: раньше здесь лежала дневная палитра при ночном небе.
        dynamic = read(TRACKS / "stage_dynamic.tres")
        self.assertIn("night_mode = true", dynamic)
        self.assertLess(luminance(color(dynamic, "fog_color")), 0.35)
        self.assertLessEqual(scalar(dynamic, "sun_energy", 1.4), 1.0)
        self.assertGreaterEqual(scalar(dynamic, "exposure", 1.0), 1.0)
        # Объёмный туман делает видимыми лучи фар — как на ночном лесу.
        self.assertIn("volumetric_fog = true", dynamic)

    def test_day_tracks_are_not_forced_to_night(self):
        # Дневные трассы (например, северная дуга) не должны получить флаг ночи.
        for path, text in track_texts():
            if "night_mode = true" in text:
                continue
            self.assertIsNone(
                re.search(r"^night_mode = false$", text, re.M),
                f"{path.name}: false писать не нужно, это значение по умолчанию",
            )

    def test_day_night_switch_flips_the_fog_too(self):
        # Иначе дневная трасса, запущенная ночью, остаётся с белым туманом:
        # небо и солнце уже ночные, а кадр всё равно молочный.
        stage = (ROOT / "scripts" / "rally_stage.gd").read_text(encoding="utf-8")
        flip = stage.split("if night != track.night_mode:", 1)[1].split("if world_environment", 1)[0]
        self.assertIn("fog_color = _weather_fog_tint(cfg.night_fog_color)", flip)
        self.assertIn("fog_color = _weather_fog_tint(cfg.day_fog_color)", flip)
        settings = (ROOT / "scripts" / "data" / "rally_stage_settings.gd").read_text(encoding="utf-8")
        night_fog = script_color(settings, "night_fog_color")
        day_fog = script_color(settings, "day_fog_color")
        self.assertIsNotNone(night_fog)
        self.assertIsNotNone(day_fog)
        self.assertLess(luminance(night_fog), 0.35, "ночной туман по умолчанию светлый")
        self.assertGreater(luminance(day_fog), 0.6, "дневной туман по умолчанию тёмный")

    def test_weather_still_tints_the_fog(self):
        # Подкраска погодой осталась общей для цвета трассы и цвета суток.
        stage = (ROOT / "scripts" / "rally_stage.gd").read_text(encoding="utf-8")
        self.assertIn("func _weather_fog_tint(base: Color) -> Color:", stage)
        self.assertIn("weather.fog_color, weather.fog_color_strength", stage)
        self.assertIn("return _weather_fog_tint(track.fog_color)", stage)

    def test_day_night_switch_still_flips_the_palette(self):
        # Выбор «День»/«Ночь» в меню работает только когда время отличается от
        # природного: эта ветка и есть защита от молочной ночи на дневной трассе.
        stage = (ROOT / "scripts" / "rally_stage.gd").read_text(encoding="utf-8")
        self.assertIn("var night: bool = WeatherType.resolve_night_choice(", stage)
        self.assertIn("if night != track.night_mode:", stage)
        self.assertIn("cfg.night_sky_top", stage)
        self.assertIn("cfg.day_sky_top", stage)


if __name__ == "__main__":
    unittest.main()
