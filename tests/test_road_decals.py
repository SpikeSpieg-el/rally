"""Пятна на полотне: декали с текстурами из шума для каждого вида дороги.

Раньше «интересность» полотна держалась на скользких полосах шейдера — одна
тёмная лужа и один светлый кусок рыхлого гравия на 240 м. Теперь по трассе
раскладываются настоящие Decal-узлы, у каждого вида покрытия свой набор:
гравий, грязь, асфальт и снег выглядят по-разному, а скользкие полосы
физики отмечаются лужами и рыхлой грязью в тех же местах.

Второй заход: пятна выглядели прямоугольниками и настраивались только кодом.
Теперь маска пятна печётся по пикселям (радиальное затухание + шум, альфа
строго ноль у края текстуры), а сами пятна — ресурсы
data/stage/road_decals/*.tres, которые правятся в инспекторе.
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
TRES_DIR = ROOT / "data" / "stage" / "road_decals"
DEFAULT_SETTINGS = ROOT / "data" / "stage" / "default_stage_settings.tres"

PROFILE_FILES = {
    "gravel": 0,
    "mud": 1,
    "asphalt": 2,
    "snow": 3,
    "grass": 4,
}

# Виды пятен из RallyRoadDecalSpec.Kind.
WET, LOOSE, MUD, PUDDLE, ICE, CRACK = range(6)

LOOK_KEYS = (
    "display_name",
    "kind",
    "weight",
    "edge_color",
    "core_color",
    "noise_type",
    "noise_frequency",
    "noise_octaves",
    "noise_lacunarity",
    "noise_gain",
    "noise_seed",
    "blob_count",
    "edge_feather",
    "mask_threshold",
    "mask_gain",
    "size_min",
    "size_max",
    "albedo_mix",
    "opacity",
    "roughness",
    "metallic",
    "normal_strength",
    "normal_scale",
    "blob_stretch",
)


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


def as_float(block: dict, key: str) -> float:
    return float(block[key])


def as_int(block: dict, key: str) -> int:
    return int(block[key])


def color_channels(value: str):
    match = re.search(r"Color\(([^)]*)\)", value)
    if not match:
        raise AssertionError(f"не цвет: {value}")
    return [float(part) for part in match.group(1).split(",")]


def parse_tres(path: Path):
    """Разобрать .tres: ext_resource (id -> путь), sub_resource блоки, [resource]."""
    header = ""
    ext: dict = {}
    subs: list = []
    resource: dict = {}
    current = None
    for index, line in enumerate(read(path).splitlines()):
        stripped = line.strip()
        if index == 0:
            header = stripped
            continue
        if stripped.startswith("[ext_resource"):
            attrs = dict(re.findall(r'(\w+)="([^"]*)"', stripped))
            ext[attrs.get("id", "")] = attrs.get("path", "")
            current = None
        elif stripped.startswith("[sub_resource"):
            attrs = dict(re.findall(r'(\w+)="([^"]*)"', stripped))
            current = {"__type": attrs.get("type", ""), "__id": attrs.get("id", "")}
            subs.append(current)
        elif stripped.startswith("[resource"):
            current = resource
        elif current is not None and "=" in stripped and not stripped.startswith("["):
            key, _, value = stripped.partition("=")
            current[key.strip()] = value.strip()
    return header, ext, subs, resource


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
        ):
            self.assertIn(f"var {field}", self.text, f"нет поля шума {field}")

    def test_soft_mask_instead_of_hard_rim(self):
        # Форму пятна задаёт мягкая маска: сколько капель, насколько мягкий
        # край, сколько съедает шум и какой контраст. Старый жёсткий rim убран.
        for field in ("blob_count", "edge_feather", "mask_threshold", "mask_gain"):
            self.assertIn(f"var {field}", self.text, f"нет поля маски {field}")
        self.assertNotIn("var rim:", self.text, "жёсткий rim больше не нужен")

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

    def test_transparent_edge(self):
        # Край пятна обязан быть прозрачным, иначе декаль видна прямоугольником.
        self.assertRegex(self.text, r"var edge_color: Color = Color\([^)]*,\s*0\.0\)")


class DecalProfileDataTest(unittest.TestCase):
    """Наборы пятен на каждый вид полотна — это ресурсы, а не код."""

    def setUp(self):
        self.files = {name: TRES_DIR / f"{name}.tres" for name in PROFILE_FILES}

    def test_every_road_kind_has_its_own_resource(self):
        for name, path in self.files.items():
            self.assertTrue(path.exists(), f"нет файла профиля {path.name}")
            header, ext, subs, resource = parse_tres(path)
            self.assertIn('script_class="RallyRoadDecalProfile"', header)
            self.assertEqual(
                as_int(resource, "road_kind"),
                PROFILE_FILES[name],
                f"{path.name}: не тот вид покрытия",
            )
            self.assertIn(
                "res://scripts/data/rally_road_decal_spec.gd", ext.values(),
                f"{path.name}: пятна не объявлены как RallyRoadDecalSpec",
            )

    def test_each_profile_offers_several_variants(self):
        # «Мини лужа и кусочек грязи» — это по одному пятну на покрытие.
        for name in ("gravel", "mud", "asphalt", "snow"):
            _, _, subs, _ = parse_tres(self.files[name])
            self.assertGreaterEqual(len(subs), 3, f"{name}: меньше трёх видов пятен")

    def test_decal_array_matches_the_specs(self):
        for name, path in self.files.items():
            _, _, subs, resource = parse_tres(path)
            decals = resource.get("decals", "")
            self.assertIn("SubResource(", decals, f"{name}: пятна не перечислены")
            listed = re.findall(r'SubResource\("([^"]+)"\)', decals)
            self.assertEqual(len(listed), len(subs), f"{name}: список пятен разошёлся")
            self.assertEqual(listed, [block["__id"] for block in subs])

    def test_every_spec_carries_its_full_look(self):
        for name, path in self.files.items():
            _, _, subs, _ = parse_tres(path)
            self.assertTrue(subs, f"{name}: нет ни одного пятна")
            for block in subs:
                for key in LOOK_KEYS:
                    self.assertIn(key, block, f"{name}/{block['__id']}: нет поля {key}")

    def test_edges_are_transparent_in_data(self):
        for name, path in self.files.items():
            _, _, subs, _ = parse_tres(path)
            for block in subs:
                alpha = color_channels(block["edge_color"])[3]
                self.assertEqual(
                    alpha, 0.0, f"{name}/{block['display_name']}: край не прозрачный"
                )

    def test_mask_is_soft_and_stays_inside_the_texture(self):
        for name, path in self.files.items():
            _, _, subs, _ = parse_tres(path)
            for block in subs:
                label = f"{name}/{block['display_name']}"
                self.assertGreaterEqual(as_int(block, "blob_count"), 1, f"{label}: нет капель")
                feather = as_float(block, "edge_feather")
                self.assertGreaterEqual(feather, 0.3, f"{label}: край почти обрез")
                self.assertLessEqual(feather, 0.95)
                gain = as_float(block, "mask_gain")
                self.assertGreaterEqual(gain, 0.5, f"{label}: маска слишком резкая")
                threshold = as_float(block, "mask_threshold")
                self.assertLessEqual(threshold, 0.5, f"{label}: шум съедает всё пятно")

    def test_blob_shape_is_editable(self):
        # Форма капли — тоже данные: (1, 1) круг, вытянутая ось — полоса/трещина.
        stretched = 0
        for name, path in self.files.items():
            _, _, subs, _ = parse_tres(path)
            for block in subs:
                match = re.match(r"Vector2\(([0-9.]+), ([0-9.]+)\)", block["blob_stretch"])
                self.assertIsNotNone(match, f"{name}: форма капли не задана")
                width, height = float(match.group(1)), float(match.group(2))
                self.assertGreater(width, 0.0)
                self.assertGreater(height, 0.0)
                if max(width, height) / min(width, height) > 2.0:
                    stretched += 1
        self.assertGreater(stretched, 0, "нет ни одного вытянутого пятна (трещин)")

    def test_kinds_cover_all_road_states(self):
        kinds = set()
        for path in self.files.values():
            _, _, subs, _ = parse_tres(path)
            kinds.update(as_int(block, "kind") for block in subs)
        for kind in (WET, LOOSE, MUD, PUDDLE, ICE, CRACK):
            self.assertIn(kind, kinds, f"вид пятна {kind} не встречается нигде")

    def test_puddles_and_ice_are_glossy(self):
        found = 0
        for name, path in self.files.items():
            _, _, subs, _ = parse_tres(path)
            for block in subs:
                if as_int(block, "kind") in (PUDDLE, ICE):
                    found += 1
                    self.assertLess(
                        as_float(block, "roughness"), 0.2,
                        f"{name}/{block['display_name']}: лужа/лёд должны блестеть",
                    )
        self.assertGreater(found, 0, "луж и льда нет вовсе")

    def test_each_kind_has_its_own_noise_seed(self):
        seeds = []
        for path in self.files.values():
            _, _, subs, _ = parse_tres(path)
            seeds.extend(as_int(block, "noise_seed") for block in subs)
        self.assertEqual(len(seeds), len(set(seeds)), "два пятна рисуются одним шумом")

    def test_profiles_have_density_and_weights(self):
        for name, path in self.files.items():
            _, _, subs, resource = parse_tres(path)
            self.assertGreater(as_float(resource, "density"), 0.0, f"{name}: нулевая плотность")
            spread = as_float(resource, "spread")
            self.assertGreater(spread, 0.0)
            self.assertLessEqual(spread, 1.0)
            for block in subs:
                self.assertGreater(as_float(block, "weight"), 0.0, f"{name}: вес пятна <= 0")
                self.assertRegex(block["size_min"], r"Vector2\([0-9.]+, [0-9.]+\)")
                self.assertRegex(block["size_max"], r"Vector2\([0-9.]+, [0-9.]+\)")

    def test_snow_profile_has_packed_snow_ice_and_slush(self):
        _, _, subs, _ = parse_tres(self.files["snow"])
        kinds = {as_int(block, "kind") for block in subs}
        for kind in (LOOSE, ICE, WET):
            self.assertIn(kind, kinds, "зимой нужны накат, лёд и слякоть")

    def test_asphalt_has_cracks(self):
        _, _, subs, _ = parse_tres(self.files["asphalt"])
        self.assertIn(CRACK, {as_int(block, "kind") for block in subs})


class DecalProfileScriptTest(unittest.TestCase):
    """Скрипт профиля только читает ресурсы; генерация вида — в данных."""

    def setUp(self):
        self.text = read(PROFILES)

    def test_profiles_come_from_disk(self):
        self.assertIn("static func load_files()", self.text)
        self.assertIn("res://data/stage/road_decals", self.text)
        self.assertRegex(self.text, r"static func defaults\(\)[\s\S]*?load_files\(\)")

    def test_look_is_no_longer_hardcoded(self):
        for name in ("_gravel_profile", "_mud_profile", "_asphalt_profile", "_snow_profile"):
            self.assertNotIn(name, self.text, f"{name}: вид пятен снова зашит в код")

    def test_fallback_is_simple(self):
        self.assertIn("static func _fallback(", self.text)


class DecalGeneratorTest(unittest.TestCase):
    """Генератор: маска пятна, а не квадрат шума."""

    def setUp(self):
        self.text = read(GENERATOR)

    def test_albedo_is_baked_with_a_soft_mask(self):
        self.assertIn("func _bake_albedo(", self.text)
        self.assertIn("Image.create_from_data(", self.text)
        self.assertIn("smoothstep(", self.text)
        self.assertIn("func _blob_centers(", self.text)
        self.assertIn('"albedo": albedo', self.text)
        self.assertIn("image.generate_mipmaps()", self.text)

    def test_blob_never_touches_the_texture_border(self):
        # Центр капли выбирается так, чтобы радиус гарантированно влез в текстуру.
        self.assertIn("0.5 - radius * 1.02", self.text)
        self.assertIn("clampf(base_radius", self.text)

    def test_noise_drives_the_mask_and_the_relief(self):
        for token in (
            "FastNoiseLite.new()",
            "get_noise_2d(",
            "warp_x",
            "WARP_STRENGTH",
            "erosion",
            "threshold",
        ):
            self.assertIn(token, self.text, f"маска не использует {token}")
        self.assertIn("absf(clamped - _snow_cover) < 0.2", self.text)

    def test_normal_and_orm_are_optional_textures(self):
        for token in (
            "NoiseTexture2D.new()",
            "Gradient.new()",
            "color_ramp",
            "as_normal_map",
            "generate_mipmaps = true",
        ):
            self.assertIn(token, self.text, f"нет текстуры рельефа/ORM: {token}")
        self.assertIn("if use_normal_maps", self.text)
        self.assertIn("if use_orm", self.text)

    def test_profiles_are_resources(self):
        self.assertIn("ProfileType.load_files()", self.text)
        self.assertIn("func _register_profile(", self.text)
        self.assertIn("profile is RallyRoadDecalProfile", self.text)
        self.assertIn("@export var profiles: Array[Resource] = []", self.text)

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

    def test_zone_strips_overlap_instead_of_stretching(self):
        # Куски полосы перекрываются: мокрая лента, а не набор отдельных пятен.
        self.assertIn("half_width * 2.2", self.text)
        self.assertIn("piece_length * 1.7", self.text)

    def test_snow_cover_rebuilds_the_set(self):
        self.assertIn("func set_snow_cover", self.text)


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
        self.assertTrue(default_bool(self.settings, "road_decals_use_normal_maps"))
        self.assertTrue(default_bool(self.settings, "road_decals_use_orm"))
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

    def test_settings_hold_the_decal_resources(self):
        self.assertIn("var road_decal_profiles: Array[Resource] = []", self.settings)

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
            "road_decals_use_normal_maps",
            "road_decals_use_orm",
            "road_decal_profiles",
        ):
            self.assertIn(field, build, f"настройка {field} не доходит до пятен")

    def test_default_settings_point_at_every_profile(self):
        header, ext, _, resource = parse_tres(DEFAULT_SETTINGS)
        self.assertIn('script_class="RallyStageSettings"', header)
        paths = set(ext.values())
        for name in PROFILE_FILES:
            expected = f"res://data/stage/road_decals/{name}.tres"
            self.assertIn(expected, paths, f"настройки не знают про {name}")
        listed = resource.get("road_decal_profiles", "")
        self.assertIn("Array[Resource](", listed)
        for name in PROFILE_FILES:
            self.assertRegex(
                listed,
                rf'ExtResource\("[^"]+"\)',
                "пятна должны быть ссылками на ресурсы",
            )
        self.assertEqual(
            len(re.findall(r"ExtResource\(", listed)), len(PROFILE_FILES),
            "в настройках не все виды покрытия",
        )

    def test_shader_strips_hand_the_look_over_to_decals(self):
        # Полосу теперь рисуют декали: в шейдере остаётся слабый след.
        fx = read(FX)
        self.assertLessEqual(default_float(fx, "zone_shader_contrast"), 0.4)
        self.assertLessEqual(default_float(fx, "zone_puddle_mix"), 0.5)


if __name__ == "__main__":
    unittest.main()
