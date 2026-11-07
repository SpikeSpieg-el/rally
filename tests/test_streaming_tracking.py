"""Static guard for the real-time scheduler; Godot tests cover its behavior."""
from pathlib import Path
import unittest


class StreamingTrackingTest(unittest.TestCase):
    def test_live_planning_and_safety_use_the_car_in_stage_coordinates(self):
        root = Path(__file__).resolve().parents[1]
        source = (root / "scripts/world_streamer.gd").read_text(encoding="utf-8")
        process = source.split("\nfunc _process(delta: float) -> void:", 1)[1].split("\nfunc _run_job(", 1)[0]
        self.assertIn("stage.to_local(stage.car.global_position)", process)
        for expression in (
            "_plan_distance_squared(car_pos, _last_position)",
            "_request(car_pos)",
            "distance_to_road(car_pos.x, car_pos.z)",
            "along_road(car_pos.x, car_pos.z)",
            "_tile_key(car_pos)",
        ):
            self.assertIn(expression, process)
        self.assertNotIn("_request(position)", process)


if __name__ == "__main__":
    unittest.main()
