"""Static guards for the runtime LOD integration; engine checks in prop_lod.gd."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class PropLodTest(unittest.TestCase):
    def test_lod_covers_generated_and_authored_props_without_per_frame_loop(self):
        stage = read("scripts/rally_stage.gd")
        self.assertIn('const PropLOD = preload("res://scripts/track/prop_lod.gd")', stage)
        self.assertIn("PropLOD.surface_with_lods(surface, mid_surface, far_surface, lod_scale)", stage)
        self.assertIn("instance.lod_bias = cfg.scenery_lod_bias", stage)
        self.assertIn('for root_name in ["StudioProps", "ManualProps", "Props"]:', stage)
        self.assertIn("_authored_lod_cache[source] = PropLOD.mesh_with_lods(source)", stage)
        self.assertIn("if Engine.is_editor_hint():", stage)
        lod = read("scripts/track/prop_lod.gd")
        self.assertIn("simplified.size() >= previous_count", lod)
        self.assertNotIn("func _process(", lod)
        self.assertNotIn("CollisionShape3D", lod)

    def test_headless_test_checks_real_triangle_buffers_and_colliders(self):
        script = read("tests/prop_lod.gd")
        self.assertIn("count0 > count1 and count1 > count2", script)
        self.assertIn("get_surface_lod_count", script)
        self.assertIn('pine.get_node("Body") == body', script)


if __name__ == "__main__":
    unittest.main()
