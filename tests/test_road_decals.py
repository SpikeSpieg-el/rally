"""Пятна на полотне: декали с текстурами из шума для каждого вида дороги.

Раньше «интересность» полотна держалась на скользких полосах шейдера — одна
тёмная лужа и один светлый кусок рыхлого гравия на 240 м. Теперь по трассе
раскладываются настоящие Decal-узлы, у каждого вида покрытия свой набор:
гравий, грязь, асфальт и снег выглядят по-разному, а скользкие полосы
физики отмечаются лужами и рыхлой грязью в тех же местах.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPECS = ROOT / "scripts" / "data" / "rally_road_decal_spec.gd"
PROFILES = ROOT / "scripts" / "data" / "rally_road_decal_profile.gd"
GENERATOR = ROOT / "scripts" / "road_decals.gd"
STAGE = ROOT / "scripts" / "rally_stage.gd"
SETTINGS = ROOT / "scripts" / "data" / "rally_stage_settings.gd"
FX = ROOT / "scripts" / "data" / "rally_fx_profile.gd"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def default_float(text: str, key: str):
    match = re.search(rf"var {key}: float = (-?[0-9.]+)", text)
    return float(match.group(1)) if match else None


def default_int(text: str, key: str):
    match = re.search(rf"var {key}: int = (-?[0-9]+)", text)
    return int(match.group(1)) if match else None


def default_bool(text: str, key: str):
    match = re.search(rf"var {key}: bool = (true|false)", text)
    return match.group(1) == "true" if match else None


class DecalSpecTest(unittest.TestCase):
    """Спецификация одного пятна: форма из шума, цвет, нормали и ORM."""

    def setUp(self):
        self.text = read(SPECS)

    def test_kinds_cover_the_road_states(self):
        for name in ("WET", "LOOSE", "MUD", "PUDDLE", "ICE", "CRACK"):
            self.assertIn(name, self.text, f"нет вида пятна {name}")

    def test_shape_is_built_from_noise(self):
        for field in (
            "noise_type",
            "noise_frequency",
            "noise_octaves",
            "noise_lacunarity",
            "noise_gain",
            "noise_seed",
            "rim",
        ):
            self.assertIn(f"var {field}", self.text, f"нет поля шума {field}")

    def test_look_is_tuned_per_kind(self):
        for field in (
            "edge_color",
            "core_color",
            "albedo_mix",
            "opacity",
            "roughness",
            "metallic",
            "normal_strength",
            "normal_scale",
            "size_min",
            "size_max",
            "weight",
        ):
            self.assertIn(f"var {field}", self.text, f"нет поля вида {field}")

    def test_transparent_edge_and_soft_rim(self):
        # Край пятна обязан быть прозрачным, иначе декаль видна прямоугольником.
        self.assertRegex(self.text, r"var edge_color: Color = Color\([^)]*,\s*0\.0\)")
        rim = default_float(self.text, "rim")
        self.assertIsNotNone(rim)
        self.assertGreaterEqual(rim, 0.05)
        self.assertLessEqual(rim, 0.5)


class DecalProfileTest(unittest.TestCase):
    """Наборы пятен на каждый вид полотна."""

    def setUp(self):
        self.text = read(PROFILES)

    def test_every_road_kind_has_its_own_profile(self):
        for kind in ("GRAVEL", "MUD", "ASPHALT", "SNOW"):
            self.assertIn(f"_profile(RoadKind.{kind}", self.text, f"нет профиля {kind}")

    def test_defaults_return_all_profiles(self):
        self.assertRegex(self.text, r"static func defaults\(\)[\s\S]*?_gravel_profile\(\)")
        for name in ("_mud_profile", "_asphalt_profile", "_snow_profile"):
            self.assertIn(name, self.text)

    def test_each_profile_offers_several_variants(self):
        # «Мини лужа и кусочек грязи» — это по одному пятну на покрытие.
        for name in ("_gravel_profile", "_mud_profile", "_asphalt_profile", "_snow_profile"):
            body = self.text.split(f"static func {name}()", 1)[1].split("static func", 1)[0]
            self.assertGreaterEqual(
                body.count("_spec("), 3, f"{name}: меньше трёх видов пятен"
            )
            self.assertGreaterEqual(
                len(re.findall(r"^\t\t[0-9.]+,\s*$", body, re.M)),
                3,
                f"{name}: у пятен должны быть веса",
            )

    def test_weights_are_positive(self):
        weights = [float(value) for value in re.findall(r"^\t\t([0-9.]+),$", self.text, re.M)]
        self.assertTrue(weights, "не нашлось ни одного веса пятна")
        self.assertTrue(all(weight > 0.0 for weight in weights), "вес пятна должен быть > 0")

    def test_snow_profile_has_packed_snow_ice_and_slush(self):
        body = self.text.split("static func _snow_profile()", 1)[1].split("static func", 1)[0]
        self.assertIn("RallyRoadDecalSpec.Kind.LOOSE", body)
        self.assertIn("RallyRoadDecalSpec.Kind.ICE", body)
        self.assertIn("RallyRoadDecalSpec.Kind.WET", body)
        ice = body.split("var ice := _spec(", 1)[1].split("\n\t)", 1)[0]
        # Порядок аргументов: имя, вид, вес, край, ядро, шероховатость, размеры.
        roughness = re.search(r"\n\t\t([0-9.]+),\n\t\tVector2", ice).group(1)
        self.assertLess(float(roughness), 0.2, "лёд должен быть глянцевым")


class DecalGeneratorTest(unittest.TestCase):
    """Генератор: настоящие Decal-узлы, текстуры из шума, детерминированная раскладка."""

    def setUp(self):
        self.text = read(GENERATOR)

    def test_creates_real_decal_nodes(self):
        self.assertIn("Decal.new()", self.text)
        for prop in (
            "texture_albedo",
            "texture_normal",
            "texture_orm",
            "albedo_mix",
            "modulate",
            "upper_fade",
            "lower_fade",
            "cull_mask",
            "distance_fade_enabled",
        ):
            self.assertIn(prop, self.text, f"декаль не настраивает {prop}")

    def test_textures_are_noise_based(self):
        for token in ("NoiseTexture2D.new()", "FastNoiseLite.new()", "Gradient.new()", "color_ramp"):
            self.assertIn(token, self.text, f"текстура не собирается из шума: нет {token}")
        self.assertIn("generate_mipmaps = true", self.text)

    def test_road_kind_comes_from_the_physics_mapping(self):
        # Тот же surface_kind(), что и у физики: зимой пятна становятся снежными.
        self.assertIn('_surface_state.surface_kind(surface_name, false, _snow_cover)', self.text)

    def test_placement_is_deterministic(self):
        self.assertNotIn("randf(", self.text)
        self.assertNotIn("randi(", self.text)
        self.assertIn("hash_noise", self.text)

    def test_positions_stay_on_the_road(self):
        self.assertIn("half_width_at", self.text)
        self.assertIn("point_at", self.text)
        self.assertIn("direction_at", self.text)

    def test_decal_count_is_capped(self):
        self.assertIn("built_count >= max_decals", self.text)

    def test_textures_are_cached_per_spec(self):
        self.assertIn("_textures.has(key)", self.text)

    def test_slippery_zones_are_marked_by_decals(self):
        self.assertIn("mark_grip_zones", self.text)
        self.assertIn("_place_slippery_zones", self.text)
        self.assertIn("SpecType.Kind.PUDDLE", self.text)
        self.assertIn("SpecType.Kind.LOOSE", self.text)

    def test_snow_cover_rebuilds_the_set(self):
        self.assertIn("func set_snow_cover", self.text)
        self.assertIn("absf(clamped - _snow_cover) < 0.2", self.text)


class StageIntegrationTest(unittest.TestCase):
    """Этап собирает пятна, а настройки дают к ним доступ без кода."""

    def setUp(self):
        self.stage = read(STAGE)
        self.settings = read(SETTINGS)

    def test_stage_builds_decals_after_the_road(self):
        self.assertIn('const RoadDecalsType = preload("res://scripts/road_decals.gd")', self.stage)
        self.assertIn("func _build_road_decals()", self.stage)
        build = self.stage.split("func _build_world_async()", 1)[1]
        self.assertIn("_build_road_decals()", build)

    def test_rebuild_clears_the_previous_decals(self):
        clear = self.stage.split("func _clear_generated()", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("road_decals = null", clear)

    def test_route_weather_updates_the_decal_set(self):
        self.assertIn("road_decals.set_snow_cover(_weather_snow_cover())", self.stage)

    def test_grip_zone_geometry_has_one_source(self):
        spans = self.stage.split("func grip_zone_spans()", 1)[1].split("\nfunc ", 1)[0]
        for field in ("zone_start", "zone_period", "zone_length", "zone_half_width"):
            self.assertIn(field, spans, f"полосы не используют {field}")
        self.assertIn("_zone_lateral_offset()", spans)
        # Физика скользких полос остаётся на месте: пятна только показывают её.
        self.assertIn("func live_surface_grip", self.stage)

    def test_settings_expose_decal_controls(self):
        self.assertTrue(default_bool(self.settings, "road_decals_enabled"))
        self.assertEqual(default_int(self.settings, "road_decals_max"), 200)
        self.assertGreaterEqual(default_int(self.settings, "road_decals_texture_size"), 64)
        self.assertTrue(default_bool(self.settings, "road_decals_mark_grip_zones"))
        for field in (
            "road_decals_density_scale",
            "road_decals_size_scale",
            "road_decals_opacity",
            "road_decals_fade_begin",
        ):
            self.assertIsNotNone(default_float(self.settings, field), f"нет настройки {field}")
        opacity = default_float(self.settings, "road_decals_opacity")
        self.assertGreater(opacity, 0.4, "пятна должны быть видны")
        self.assertLessEqual(opacity, 1.0)

    def test_stage_passes_every_setting_to_the_generator(self):
        build = self.stage.split("func _build_road_decals()", 1)[1].split("\nfunc ", 1)[0]
        for field in (
            "road_decals_max",
            "road_decals_density_scale",
            "road_decals_size_scale",
            "road_decals_opacity",
            "road_decals_texture_size",
            "road_decals_fade_begin",
            "road_decals_fade_length",
            "road_decals_mark_grip_zones",
        ):
            self.assertIn(field, build, f"настройка {field} не доходит до пятен")

    def test_shader_strips_hand_the_look_over_to_decals(self):
        # Полосу теперь рисуют декали: в шейдере остаётся слабый след.
        fx = read(FX)
        self.assertLessEqual(default_float(fx, "zone_shader_contrast"), 0.4)
        self.assertLessEqual(default_float(fx, "zone_puddle_mix"), 0.5)


if __name__ == "__main__":
    unittest.main()
