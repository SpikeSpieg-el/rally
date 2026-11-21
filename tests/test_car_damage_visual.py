"""Границы визуальных повреждений кузова; сама деформация проверяется в tests/car_damage_visual.gd.

Система работает на всех машинах (у каждой есть меш кузова в группе
rally_body_fx) и обязана оставаться косметической: здоровье, урон, счёт и физика
не меняются. Настройка живёт в ресурсах data/car/default_damage_visual.tres и
data/car/default_impact_fx.tres, чтобы её можно было править в инспекторе, —
здесь проверяется и это, и сами значения.
"""
import ast
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

VISUAL = "scripts/car_damage_visual.gd"
CAR = "scripts/rally_car.gd"
CONFIG = "scripts/data/rally_damage_visual_config.gd"
SETTINGS = "data/car/default_damage_visual.tres"
SUBDIVIDER = "scripts/car_mesh_subdivider.gd"
IMPACT = "scripts/effects/car_impact_fx.gd"
IMPACT_CONFIG = "scripts/data/rally_impact_fx_config.gd"
IMPACT_SETTINGS = "data/car/default_impact_fx.tres"
MARKS_INCLUDE = "shaders/car_damage_marks.gdshaderinc"
DIRT_SHADER = "shaders/car_dirt.gdshader"
ARCADE_SETTINGS = "scripts/data/rally_arcade_settings.gd"

## Константы, которые раньше держали настройку в коде: их больше не должно быть,
## иначе правки в инспекторе не будут иметь силы.
OBSOLETE_CONSTS = (
    "DAMAGE_VISUAL_IDS",
    "DAMAGE_VISUAL_MIN_DV_MPS",
    "DAMAGE_VISUAL_COOLDOWN_SEC",
    "DAMAGE_VISUAL_GROUND_NORMAL_Y",
    "DAMAGE_VISUAL_MAX_CONTACTS",
)

## Токены геймплея: косметический слой не должен их знать.
GAMEPLAY_TOKENS = (r"\bhp\b", r"\bhealth\b", r"_apply_damage", r"\brun_ended\b",
                   r"\barcade\b", r"\bscore\b", r"traffic_event", r"pedestrian")


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


def script_defaults(text):
    """Значения по умолчанию экспортируемых полей ресурса: {имя: строка значения}."""
    found = re.findall(
        r"^@export(?:_range\([^)]*\))? var (\w+): [\w\[\]]+ = (.+)$", text, re.M)
    return dict(found)


def export_count(text):
    """Сколько всего полей экспортирует скрипт (без групп)."""
    return len(re.findall(r"^@export(?:_range\([^)]*\))? var ", text, re.M))


def resource_values(text):
    """Поля секции [resource] в .tres: {имя: строка значения}."""
    match = re.search(r"^\[resource\]\n(.*?)(?=^\[|\Z)", text, re.S | re.M)
    assert match, "в .tres нет секции [resource]"
    return dict(re.findall(r"^(\w+) = (.*)$", match.group(1), re.M))


def value(text):
    """Строка значения GDScript/.tres в значение Python (числа, булевы, массивы)."""
    text = text.strip()
    if text in ("true", "false"):
        return text == "true"
    array = re.match(r'Array\[\w+\]\((\[.*\])\)$', text)
    if array:
        text = array.group(1)
    try:
        return ast.literal_eval(text)
    except (ValueError, SyntaxError):
        return text


class CarDamageVisualTest(unittest.TestCase):
    def test_settings_are_editable_in_inspector(self):
        """Настройка деформации обязана правиться в редакторе, а не в коде."""
        config = read(CONFIG)
        self.assertIn("@tool", config, "ресурс настройки должен открываться в редакторе")
        self.assertIn("class_name RallyDamageVisualConfig", config)
        self.assertIn("extends Resource", config)

        car = read(CAR)
        self.assertIn("@export var damage_visual_config: RallyDamageVisualConfig = null", car,
                      "у корня RallyCar должно быть поле настройки — его видно в инспекторе")
        self.assertIn('const DEFAULT_DAMAGE_VISUAL_PATH := "res://%s"' % SETTINGS, car)
        loader = function_body(car, "damage_config")
        self.assertIn("ResourceLoader.load(DEFAULT_DAMAGE_VISUAL_PATH)", loader,
                      "пустое поле берёт ресурс по умолчанию")

        settings = read(SETTINGS)
        self.assertIn('script_class="RallyDamageVisualConfig"', settings)
        self.assertIn("path=\"res://%s\"" % CONFIG, settings)
        for obsolete in OBSOLETE_CONSTS:
            self.assertNotIn(obsolete, car,
                             f"{obsolete}: настройка уехала в ресурс, константа больше не нужна")

    def test_resource_defaults_match_script(self):
        """Числа в .tres не должны разъезжаться с дефолтами скрипта настройки."""
        for config_path, settings_path in ((CONFIG, SETTINGS), (IMPACT_CONFIG, IMPACT_SETTINGS)):
            text = read(config_path)
            defaults = script_defaults(text)
            values = resource_values(read(settings_path))
            self.assertGreater(len(defaults), 10, f"{config_path}: в ресурсе настройки почти нет полей")
            self.assertEqual(len(defaults), export_count(text),
                             f"{config_path}: каждое поле — одной строкой «@export var имя: тип = значение»")
            self.assertEqual(set(values) - {"script"}, set(defaults),
                             f"{settings_path}: в .tres должны быть перечислены все поля настройки")
            for name, raw in defaults.items():
                self.assertEqual(value(raw), value(values[name]),
                                 f"{settings_path}:{name}: значение в .tres не совпадает с дефолтом скрипта")

    def test_enabled_for_every_car(self):
        values = resource_values(read(SETTINGS))
        self.assertEqual(value(values["vehicle_ids"]), [],
                         "пустой список — вмятины на всех машинах")
        self.assertEqual(value(script_defaults(read(CONFIG))["vehicle_ids"]), [])
        self.assertEqual(value(values["excluded_vehicle_ids"]), [])
        self.assertEqual(value(values["enabled"]), True)
        impact = resource_values(read(IMPACT_SETTINGS))
        self.assertEqual(value(impact["vehicle_ids"]), [], "эффекты удара — тоже на всех машинах")
        self.assertEqual(value(impact["enabled"]), True)
        self.assertIn("vehicle_ids.is_empty()", function_body(read(CONFIG), "applies_to"),
                      "пустой список машин означает «все машины»")

        install = function_body(read(CAR), "_install_damage_visual")
        self.assertIn("tuning.applies_to(vehicle_id)", install,
                      "компонент ставится машинам по списку настройки (пусто — всем)")
        self.assertIn("CarImpactFx.new()", install, "эффекты удара ставятся вместе с вмятинами")
        self.assertIn("tuning.enabled", install, "главный выключатель настройки действует")
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
        for path in (VISUAL, CONFIG, SUBDIVIDER, IMPACT, IMPACT_CONFIG):
            text = read(path).lower()
            for token in GAMEPLAY_TOKENS:
                self.assertIsNone(re.search(token, text),
                                  f"{path}: косметический слой не должен знать про {token}")
        car = read(CAR).lower()
        for name in ("_install_damage_visual", "_update_damage_visual"):
            body = function_body(car, name)
            for token in GAMEPLAY_TOKENS:
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
        self.assertNotIn("ARRAY_INDEX] =", visual, "удар не меняет индексы треугольников")
        self.assertIn("orig_vertices", visual, "исходные вершины хранятся для сброса и статистики")

    def test_mesh_is_refined_without_cracks(self):
        """Треугольники не «косит»: сетка сгущается, а вмятина — гладкое поле по положению."""
        visual = read(VISUAL)
        self.assertIn('preload("res://%s")' % SUBDIVIDER, visual)
        self.assertIn("Subdivider.prepared_surface(", visual)
        sub = read(SUBDIVIDER)
        # Середина ребра не зависит от порядка концов: швы делятся одинаково.
        self.assertIn("(verts[a] + verts[b]) * 0.5", sub)
        self.assertIn("mini(a, b)", sub)
        # Случайный сдвиг каждой вершины — источник перекошенных треугольников.
        self.assertNotIn("jitter", visual)
        self.assertNotIn("randf_range(-", visual)
        self.assertIn("func triangle_stats", visual, "качество сетки проверяется в движке")

    def test_shape_comes_from_settings(self):
        """Форма вмятины берётся из ресурса, а не захардкожена в компоненте."""
        visual = read(VISUAL)
        for field in ("depth_per_dv_m", "depth_min_m", "depth_max_m", "radius_base_m",
                      "radius_per_dv_m", "radius_max_m", "rim_bulge", "rim_width", "crumple_amount",
                      "crumple_scale_m", "buckle_amount", "buckle_wavelength_m", "crush_depth_scale",
                      "max_strain", "max_vertex_offset_m", "dent_budget_m", "dent_scale",
                      "subdivide_enabled", "subdivide_max_edge_m", "subdivide_max_passes",
                      "subdivide_vertex_limit", "surface_search_m", "follow_attached_parts",
                      "marks_enabled", "marks_max", "mark_strength_per_dv", "mark_strength_min",
                      "mark_radius_scale", "mark_soot", "scrape_growth_per_sec", "scrape_radius_m",
                      "primer_color", "metal_color", "soot_color", "metal_gloss",
                      "scratch_frequency", "marks_opacity"):
            self.assertIn("tuning." + field, visual, f"{field}: поле настройки не используется")
        car = function_body(read(CAR), "_update_damage_visual")
        for field in ("min_dv_mps", "cooldown_sec", "ground_normal_y", "roof_contact_height",
                      "use_contact_impulse", "scrape_min_speed_mps"):
            self.assertIn("tuning." + field, car, f"{field}: поле настройки не используется")

    def test_marks_are_drawn_in_body_overlay(self):
        """Следы удара рисует слой грязи кузова; кровь и грязь работают как раньше."""
        include = read(MARKS_INCLUDE)
        for uniform in ("damage_mark_pos[16]", "damage_mark_axis[16]", "damage_mark_normal[16]",
                        "damage_mark_data[16]", "damage_primer_color", "damage_metal_color",
                        "damage_soot_color"):
            self.assertIn(uniform, include)
        dirt = read(DIRT_SHADER)
        self.assertIn('#include "res://%s"' % MARKS_INCLUDE, dirt)
        self.assertIn("damage_marks(body_position", dirt)
        visual = read(VISUAL)
        self.assertIn("MARK_SLOTS := 16", visual, "число слотов совпадает с размером массивов шейдера")
        for name in ("damage_mark_pos", "damage_mark_axis", "damage_mark_normal", "damage_mark_data"):
            self.assertIn('"%s"' % name, visual)

    def test_impact_feel_is_editable_and_cosmetic(self):
        config = read(IMPACT_CONFIG)
        self.assertIn("@tool", config)
        self.assertIn("class_name RallyImpactFxConfig", config)
        car = read(CAR)
        self.assertIn("@export var impact_fx_config: RallyImpactFxConfig = null", car)
        self.assertIn('const DEFAULT_IMPACT_FX_PATH := "res://%s"' % IMPACT_SETTINGS, car)
        self.assertIn("ResourceLoader.load(DEFAULT_IMPACT_FX_PATH)", function_body(car, "impact_config"))
        self.assertIn("impact_fx.apply_camera(", function_body(car, "_apply_camera_shake"))
        self.assertIn("impact_fx.restore_camera(", function_body(car, "_update_cameras"))
        restart = function_body(car, "restart_at_spawn")
        self.assertIn("damage_visual.clear_damage()", restart, "новый заезд — целая машина")
        self.assertIn("impact_fx.clear()", restart)
        self.assertNotIn("clear_damage", function_body(car, "reset_to_spawn"),
                         "сброс на трассу (R) кузов не чинит")
        impact = read(IMPACT)
        self.assertIn('"Vehicle"', impact, "звук удара идёт через шину машины")
        for token in (r"\blinear_velocity\b", r"\bangular_velocity\b", r"apply_impulse", r"apply_central"):
            self.assertIsNone(re.search(token, impact), f"{IMPACT}: эффекты не трогают физику ({token})")
        # Стоп-кадр меняет Engine.time_scale — по умолчанию выключен.
        self.assertEqual(value(resource_values(read(IMPACT_SETTINGS))["hitstop_enabled"]), False)

    def test_dent_appears_before_arcade_damage(self):
        # Кузов мнётся раньше, чем аркада снимает HP: лёгкие касания видны,
        # а порог урона в настройках аркады остаётся прежним.
        dent = value(resource_values(read(SETTINGS))["min_dv_mps"])
        settings = read(ARCADE_SETTINGS)
        crash = float(re.search(r"var crash_min_dv_mps: float = ([\d.]+)", settings).group(1))
        self.assertLess(dent, crash, "вмятина должна появляться раньше, чем снимается HP")
        self.assertEqual(crash, 4.6, "порог урона аркады менять нельзя")

    def test_engine_check_is_wired_into_ci(self):
        workflow = read(".github/workflows/pages.yml")
        self.assertIn("tests/car_damage_visual.gd", workflow,
                      "движковая проверка вмятин обязана запускаться в CI")
        self.assertIn("tests.test_car_damage_visual", workflow,
                      "статическая проверка настройки обязана запускаться в CI")


if __name__ == "__main__":
    unittest.main()
