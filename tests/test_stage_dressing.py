"""Static guards for the special-stage dressing (spectators, bunting, ЛЭП).

Godot is not required: these checks pin the integration points so the
dressing cannot silently fall out of either world-building path
(streamed chunks and the single-build path) again.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


class StageDressingTest(unittest.TestCase):
    def test_planner_and_runtime_nodes_exist(self):
        for relative in (
            "scripts/track/stage_dressing.gd",
            "scripts/track/spectator_crowd.gd",
            "scripts/track/helicopter.gd",
            "tests/stage_dressing.gd",
        ):
            self.assertTrue((ROOT / relative).is_file(), relative)

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

    def test_dressing_features_present(self):
        stage = read("scripts/rally_stage.gd")
        for token in (
            "braking_marker_distances",
            "select_spectator_corners",
            "powerline_ranges",
            "fog_distances",
            "BuntingTape",
            "СТАРТ",
            "ФИНИШ",
            "СТОП",
        ):
            self.assertIn(token, stage, token)

    def test_crowd_has_flashes_fire_and_fleeing_photographers(self):
        Crowd = read("scripts/track/spectator_crowd.gd")
        for token in ("BILLBOARD_FIXED_Y", "_flash_timers", "_fleeing", "_fire_light", "GPUParticles3D"):
            self.assertIn(token, Crowd, token)

    def test_spawn_layout_exposes_dressing_switches(self):
        layout = read("scripts/data/rally_spawn_layout.gd")
        for name in ("stage_dressing", "spectator_spacing", "spectator_max_spots", "spectator_crowd_size", "helicopter"):
            self.assertIn(f"var {name}", layout, name)


if __name__ == "__main__":
    unittest.main()
