"""Static guards for the special-stage dressing (spectators, bunting, ЛЭП).

Godot is not required: these checks pin the integration points so the
dressing cannot silently fall out of either world-building path
(streamed chunks and the single-build path) again, and so every dressing
prop stays an editable scene instead of script-built geometry.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

DRESSING_PROPS = [
    "braking_marker", "safety_net", "marshal_tent", "light_tower", "generator",
    "parked_car", "service_car", "broken_car", "traffic_cone",
    "finish_warning_sign", "stop_sign", "warning_triangle", "forester_house",
    "gate_sign", "bunting_post", "bunting_tape", "power_pole", "mud_patch",
    "fog_patch", "spectator_person", "camera_flash", "camper", "camper_tent",
    "campfire", "spectator_crowd", "helicopter",
]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


class StageDressingTest(unittest.TestCase):
    def test_planner_and_runtime_nodes_exist(self):
        for relative in (
            "scripts/track/stage_dressing.gd",
            "scripts/track/spectator_crowd.gd",
            "scripts/track/spectator_person.gd",
            "scripts/track/helicopter.gd",
            "scripts/effects/rally_blood_fx.gd",
            "shaders/car_blood.gdshader",
            "tests/stage_dressing.gd",
        ):
            self.assertTrue((ROOT / relative).is_file(), relative)

    def test_every_dressing_prop_is_an_editable_scene(self):
        library = read("data/stage/default_prop_library.tres")
        for prop_id in DRESSING_PROPS:
            scene = ROOT / "scenes" / "props" / f"{prop_id}.tscn"
            self.assertTrue(scene.is_file(), f"нет сцены пропса {prop_id}")
            self.assertIn(f'id = "{prop_id}"', library, prop_id)
            self.assertIn(f"res://scenes/props/{prop_id}.tscn", library, prop_id)

    def test_stage_places_scenes_not_script_boxes(self):
        stage = read("scripts/rally_stage.gd")
        self.assertIn("func _place_prop(", stage)
        self.assertIn("StageDressing.roadside_fans(", stage)
        for prop_id in (
            "braking_marker", "safety_net", "spectator_crowd", "spectator_person", "parked_car",
            "power_pole", "fog_patch", "forester_house", "broken_car",
            "warning_triangle", "marshal_tent", "light_tower", "generator",
            "service_car", "traffic_cone", "finish_warning_sign", "stop_sign",
            "gate_sign", "helicopter", "mud_patch",
        ):
            self.assertIn(f'"{prop_id}"', stage, prop_id)
        # Bunting/powerline mass props go through the baked-scene MultiMesh.
        self.assertIn('func _dressing_multimesh(', stage)
        self.assertIn('"bunting_post"', stage)
        self.assertIn('"bunting_tape"', stage)
        # The old script-built dressing helpers must not come back.
        for gone in ("func _dressing_box(", "func _dressing_label(", "func _dressing_car(", "func _dressing_house("):
            self.assertNotIn(gone, stage, gone)

    def test_stage_builds_dressing_on_both_paths(self):
        stage = read("scripts/rally_stage.gd")
        self.assertIn("_spawn_stage_dressing(0.0, -1.0, null)", stage)
        self.assertIn("_spawn_start_finish_dressing()", stage)
        streamer = read("scripts/world_streamer.gd")
        self.assertIn("stage._spawn_stage_dressing(", streamer)

    def test_scenery_uses_clustered_density(self):
        stage = read("scripts/rally_stage.gd")
        self.assertIn("StageDressing.cluster_factor(distance, track.terrain_seed)", stage)
        self.assertIn("attempt_chance * cluster", stage)

    def test_crowd_scene_composes_people_camp_and_flashes(self):
        Crowd_scene = read("scenes/props/spectator_crowd.tscn")
        for token in ("spectator_person.tscn", "camera_flash.tscn", "camper.tscn",
                      "camper_tent.tscn", "campfire.tscn", "spectator_crowd.gd"):
            self.assertIn(token, Crowd_scene, token)
        Crowd = read("scripts/track/spectator_crowd.gd")
        for token in ("_flash_timers", "_photographers", "Campfire/FireLight", "func setup(", "_arm_people"):
            self.assertIn(token, Crowd, token)
        person_scene = read("scenes/props/spectator_person.tscn")
        for token in ("spectator_person.gd", "Hitbox", "CapsuleShape3D"):
            self.assertIn(token, person_scene, token)
        person = read("scripts/track/spectator_person.gd")
        for token in ("func crush(", "splatter_blood", "BloodFx.spray"):
            self.assertIn(token, person, token)
        blood = read("scripts/effects/rally_blood_fx.gd")
        for token in ("func add_splat(", "func spray(", "car_blood.gdshader"):
            self.assertIn(token, blood, token)
        shader = read("shaders/car_blood.gdshader")
        self.assertIn("uniform vec3 splat_pos[8];", shader)
        self.assertNotIn("uniform vec3 splat_pos[8] =", shader)
        # Люди и вспышки — текстуры-файлы, которые можно перерисовать.
        for name in ("spectator_red", "spectator_yellow", "spectator_blue",
                     "spectator_green", "spectator_orange", "spectator_white", "camera_flash"):
            self.assertTrue((ROOT / "textures" / "sprites" / f"{name}.png").is_file(), name)

    def test_helicopter_is_a_scene_with_script_only_animating(self):
        heli_scene = read("scenes/props/helicopter.tscn")
        for token in ("helicopter.gd", "Rotor", "Beacon", "SearchCone", "Searchlight"):
            self.assertIn(token, heli_scene, token)
        heli = read("scripts/track/helicopter.gd")
        self.assertNotIn("BoxMesh.new()", heli)
        self.assertNotIn("_make_person", read("scripts/track/spectator_crowd.gd"))

    def test_spawn_layout_exposes_dressing_switches(self):
        layout = read("scripts/data/rally_spawn_layout.gd")
        for name in (
            "stage_dressing", "spectator_spacing", "spectator_max_spots",
            "spectator_crowd_size", "roadside_fans", "roadside_fan_spacing",
            "roadside_fan_max", "helicopter",
        ):
            self.assertIn(f"var {name}", layout, name)


if __name__ == "__main__":
    unittest.main()
