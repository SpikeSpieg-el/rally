"""Разрушаемые пропсы, коллизии обстановки и настройка ударов гонки.

Сам снос забора, обломки и общие фигуры проверяются в движке
(tests/breakable_props.gd). Здесь — контракт данных и кода: настройка живёт
в ресурсах и правится в инспекторе, значения .tres совпадают со скриптом,
этап и аркада умеют подменять эффекты удара для всей гонки, а коллизии
собираются без узла и без нового Shape3D на каждый пропс.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

CONFIG = "scripts/data/rally_breakable_config.gd"
SETTINGS = "data/stage/default_breakables.tres"
PROP = "scripts/data/rally_prop.gd"
LIBRARY = "data/stage/default_prop_library.tres"
COLLISION = "scripts/track/prop_collision.gd"
BREAKABLES = "scripts/track/breakable_props.gd"
DEBRIS = "scripts/track/breakable_debris.gd"
STAGE = "scripts/rally_stage.gd"
ARCADE_STAGE = "scripts/arcade/arcade_stage.gd"
ARCADE_SCENERY = "scripts/arcade/arcade_scenery.gd"
CAR = "scripts/rally_car.gd"
IMPACT = "scripts/effects/car_impact_fx.gd"


def text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def function(source: str, header: str) -> str:
    start = source.index(header)
    rest = source[start + len(header):]
    match = re.search(r"\n(?:static func |func |## )", rest)
    return source[start:start + len(header) + (match.start() if match else len(rest))]


def exports(source: str) -> dict:
    out = {}
    for name, value in re.findall(r"^@export(?:_range\([^)]*\))? var (\w+): [\w\[\]]+ = (.+)$", source, re.M):
        out[name] = value.strip()
    return out


def tres_values(source: str) -> dict:
    body = source.split("[resource]", 1)[1]
    return dict(re.findall(r"^(\w+) = (.+)$", body, re.M))


def library_props(source: str) -> dict:
    props = {}
    for block in re.split(r"\n(?=\[sub_resource)", source):
        match = re.search(r'\bid = "([^"]+)"', block)
        if match and block.startswith("[sub_resource"):
            props[match.group(1)] = dict(re.findall(r"^(\w+) = (.+)$", block, re.M))
    return props


def same(a: str, b: str) -> bool:
    try:
        return abs(float(a) - float(b)) < 1e-6
    except ValueError:
        return a.replace(" ", "") == b.replace(" ", "")


class BreakableConfigTest(unittest.TestCase):
    def test_settings_resource_matches_script_defaults(self):
        script = exports(text(CONFIG))
        values = tres_values(text(SETTINGS))
        self.assertIn('script_class="RallyBreakableConfig"', text(SETTINGS))
        self.assertGreater(len(script), 30, "настройка должна быть полностью в инспекторе")
        for name, value in values.items():
            if name == "script":
                continue
            self.assertIn(name, script, f"{name} нет в скрипте настройки")
            self.assertTrue(same(script[name], value), f"{name}: скрипт {script[name]} ≠ .tres {value}")

    def test_config_groups_cover_every_effect(self):
        source = text(CONFIG)
        for group in ("Включение", "Обломки", "Машина", "Камера и вибрация", "Щепки", "Звук"):
            self.assertIn(f'@export_group("{group}")', source)
        for name in ("enabled", "restore_on_restart", "max_pieces", "piece_lifetime_sec",
                     "momentum_transfer", "max_car_speed_loss_mps", "car_dent_per_mps",
                     "shake", "kick", "rumble", "splinter_amount", "break_sounds"):
            self.assertRegex(source, rf"var {name}\b")


class PropLibraryCollisionTest(unittest.TestCase):
    def test_collision_shapes_are_configurable_per_prop(self):
        source = text(PROP)
        self.assertIn("enum ColliderShape { CYLINDER, SCENE, AUTO, BOX_FIT, CYLINDER_FIT, SPHERE_FIT, NONE }", source)
        for name in ("collider_shape", "collider_fit_scale", "collider_y_offset", "breakable",
                     "break_mass_kg", "break_into_parts", "splinter_color"):
            self.assertRegex(source, rf"var {name}\b")
        # Шаг 45 м оставлял большинство деревьев призрачными.
        self.assertIn("var collider_spacing: float = 0.0", source)

    def test_library_gives_every_solid_prop_a_shape(self):
        props = library_props(text(LIBRARY))
        roadside = ("fir_tree", "pine_tree", "birch_tree", "dead_tree", "boulder", "rock_cluster",
                    "moss_rock", "stump", "log", "hay_bale", "tire_stack", "sandbag_barrier",
                    "wooden_fence", "sponsor_banner")
        for prop_id in roadside:
            self.assertIn(prop_id, props)
            self.assertGreater(float(props[prop_id].get("collider_max_offset", "0")), 0.0,
                               f"{prop_id}: у дороги без коллизии")
            self.assertEqual(float(props[prop_id].get("collider_spacing", "0")), 0.0,
                             f"{prop_id}: коллизия должна быть у каждого экземпляра")
        placed = ("traffic_cone", "stop_sign", "finish_warning_sign", "warning_triangle", "braking_marker",
                  "marshal_tent", "light_tower", "generator", "parked_car", "service_car", "broken_car",
                  "forester_house", "camper", "river_bank_rock", "dry_stone_wall")
        for prop_id in placed:
            self.assertIn("collider_shape", props[prop_id], f"{prop_id}: нет формы коллизии")
            self.assertNotEqual(props[prop_id]["collider_shape"], "6")
        # Кусты, трава и туман остаются проходимыми.
        for prop_id in ("bush", "fern", "grass", "fog_patch"):
            self.assertNotIn("collider_max_offset", props[prop_id])

    def test_wooden_fence_and_light_props_are_breakable(self):
        props = library_props(text(LIBRARY))
        for prop_id in ("wooden_fence", "sponsor_banner", "traffic_cone", "stop_sign",
                        "finish_warning_sign", "warning_triangle", "braking_marker"):
            self.assertEqual(props[prop_id].get("breakable"), "true", prop_id)
        self.assertEqual(props["wooden_fence"]["collider_shape"], "1", "запасная форма забора — из сцены")
        for prop_id in ("gate_sign", "metal_guardrail", "safety_net", "forester_house"):
            self.assertNotEqual(props[prop_id].get("breakable"), "true", prop_id)


class FastCollisionTest(unittest.TestCase):
    def test_shapes_are_shared_and_added_without_nodes(self):
        source = text(COLLISION)
        self.assertIn("PhysicsServer3D.body_add_shape(", source)
        self.assertIn("static var _shape_cache", source)
        self.assertIn("const OBSTACLE_LAYER := 2", source)
        add = function(source, "static func add_instance(")
        self.assertNotIn("CollisionShape3D.new()", add)

    def test_stage_colliders_use_library_shapes(self):
        stage = text(STAGE)
        colliders = function(stage, "func _add_prop_colliders(")
        self.assertIn("PropCollision.entries_for(", colliders)
        self.assertIn("PropCollision.add_instance(", colliders)
        self.assertNotIn("CylinderShape3D.new()", colliders)
        self.assertNotIn("CollisionShape3D.new()", colliders)
        self.assertIn("body.collision_layer = 2", colliders)
        dressing = function(stage, "func _dressing_multimesh(")
        self.assertIn("PropCollision.add_instance(", dressing)
        place = function(stage, "func _place_prop(")
        self.assertIn("wants_placed_collider()", place)
        self.assertIn("_dressing_breakables(container).add_node(", place)

    def test_arcade_scenery_shares_shapes(self):
        scenery = text(ARCADE_SCENERY)
        self.assertNotIn("CylinderShape3D.new()", scenery)
        self.assertNotIn("SphereShape3D.new()", scenery)
        self.assertIn('_emit_fences(root, "CountryFences"', scenery)
        self.assertIn('_emit_fences(root, "VillageFences"', scenery)
        for label in ("PowerPoles", "RoadSigns", "VillageHay", "VillageCars"):
            self.assertIn(f'_emit_colliders(root, "{label}"', scenery)


class BreakableRuntimeTest(unittest.TestCase):
    def test_corner_fence_breaks_when_enabled(self):
        stage = text(STAGE)
        fence = function(stage, "func _dressing_corner_fence(")
        self.assertIn("prop.breakable and s_breakables().enabled", fence)
        self.assertIn("BreakableProps.new()", fence)
        self.assertIn("if cfg.corner_fence_collisions and not breakable_fence:", fence)

    def test_sensor_is_not_solid_and_physics_is_untouched_in_callback(self):
        source = text(BREAKABLES)
        self.assertIn("PhysicsServer3D.area_set_monitor_callback(", source)
        self.assertIn("area_set_collision_layer(area, 0)", source)
        callback = function(source, "func _on_area_event(")
        self.assertIn("call_deferred(", callback)
        self.assertNotIn("add_child", callback)
        self.assertNotIn("area_set_shape_disabled", callback)
        self.assertIn('is_in_group("rally_car")', callback)

    def test_car_speed_loss_is_bounded(self):
        feedback = function(text(BREAKABLES), "func _car_feedback(")
        self.assertIn("max_car_speed_loss_mps", feedback)
        self.assertIn("apply_central_impulse(", feedback)
        self.assertIn('"nudge"', feedback)
        self.assertIn('"apply_impact"', feedback)

    def test_debris_does_not_block_wheels_or_car(self):
        source = text(DEBRIS)
        self.assertIn("const PIECE_LAYER := 4", source)
        self.assertIn("add_collision_exception_with(car)", source)
        self.assertIn("_enforce_limit()", source)

    def test_restart_restores_props(self):
        car = text(CAR)
        restart = function(car, "func restart_at_spawn(")
        self.assertIn('call_group("rally_breakable_props", "restore_all")', restart)
        self.assertIn('const GROUP := "rally_breakable_props"', text(BREAKABLES))


class RaceImpactSettingsTest(unittest.TestCase):
    def test_stage_exposes_race_impact_group(self):
        for path in (STAGE, ARCADE_STAGE):
            source = text(path)
            self.assertIn('@export_group("Удары и разрушения (гонка)")', source, path)
            self.assertIn("@export var impact_fx_override: RallyImpactFxConfig = null", source, path)
            self.assertIn("@export var damage_visual_override: RallyDamageVisualConfig = null", source, path)
            self.assertIn("@export var breakables: RallyBreakableConfig = null", source, path)
            self.assertIn("apply_impact_settings(impact_fx_override, damage_visual_override)", source, path)
        self.assertIn('DEFAULT_BREAKABLES_PATH := "res://data/stage/default_breakables.tres"', text(STAGE))

    def test_car_reinstalls_components_with_race_settings(self):
        car = text(CAR)
        apply = function(car, "func apply_impact_settings(")
        self.assertIn("impact_fx_config = fx_settings", apply)
        self.assertIn("damage_visual_config = damage_settings", apply)
        self.assertIn("_install_damage_visual()", apply)
        self.assertIn("if not is_inside_tree():", apply)

    def test_nudge_is_cosmetic(self):
        nudge = function(text(IMPACT), "func nudge(")
        for token in ("apply_central_impulse", "linear_velocity", "apply_impulse"):
            self.assertNotIn(token, nudge)


if __name__ == "__main__":
    unittest.main()
