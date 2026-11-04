"""Numerical checks of the committed Bezier route, without a Godot install."""
import math
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import stage_model


class MountainRouteTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.points = stage_model.sample_curve(stage_model.load_curve(
            str(ROOT / 'data/tracks/stage_mountain_100_route.tres')), step=1)

    def test_length_and_elevation(self):
        length = sum(math.dist(a, b) for a, b in zip(self.points, self.points[1:]))
        self.assertAlmostEqual(length, 100000, delta=3)
        heights = [p[1] for p in self.points]
        self.assertGreater(max(heights) - min(heights), 1800)
        self.assertGreater(max(heights), 2300)
        for a, b in zip(self.points, self.points[1:]):
            grade = abs(b[1] - a[1]) / math.hypot(b[0] - a[0], b[2] - a[2])
            self.assertLess(grade, .16)
        print(f'Length {length:.2f} m; altitude {min(heights):.1f}–{max(heights):.1f} m')

    def test_non_adjacent_branches_have_clearance(self):
        buckets = {}
        for i in range(0, len(self.points), 2):
            x, _, z = self.points[i]
            cell = (math.floor(x / 30), math.floor(z / 30))
            for dx in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    for j, px, pz in buckets.get((cell[0] + dx, cell[1] + dz), []):
                        if i - j > 120:  # more than 120 m along route
                            self.assertGreater(math.hypot(x - px, z - pz), 26)
            buckets.setdefault(cell, []).append((i, x, z))

    def test_start_is_not_a_flat_straight(self):
        a, b = self.points[10], self.points[30]
        launch_heading = math.atan2(b[2] - a[2], b[0] - a[0])
        turns = []
        for i in range(30, 160):
            a, b = self.points[i], self.points[i + 5]
            heading = math.atan2(b[2] - a[2], b[0] - a[0])
            turns.append(abs(math.atan2(math.sin(heading - launch_heading), math.cos(heading - launch_heading))))
        self.assertGreater(max(turns), math.radians(30))
        self.assertGreater(self.points[300][1] - self.points[0][1], 10)

    def test_sections_registered(self):
        text = (ROOT / 'data/tracks/stage_mountain_100.tres').read_text()
        self.assertEqual(text.count('[sub_resource'), 11)
        self.assertIn('stage_mountain_100.tres', (ROOT / 'data/rally_game_config.tres').read_text())


if __name__ == '__main__':
    unittest.main()
