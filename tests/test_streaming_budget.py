"""Numerical geometry budgets for the real 100 km route, not FPS claims."""
from pathlib import Path
import math
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import stage_model


class StreamingBudgetTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.points = stage_model.sample_curve(stage_model.load_curve(
            str(ROOT / 'data/tracks/stage_mountain_100_route.tres')), 16)
        cls.index = {}
        # Conservative indexing (adjacent IDs too) avoids understating counts.
        for i, (x, _, z) in enumerate(cls.points):
            key = math.floor(x / 96), math.floor(z / 96)
            road_id = int(i * 16 / 128)
            cls.index.setdefault(key, set()).update((road_id, max(0, road_id - 1), road_id + 1))

    def test_local_geometry_not_whole_map(self):
        maximum_roads = maximum_tiles = 0
        for fraction in (0, .1, .25, .5, .58, .75, .99):
            x, _, z = self.points[int((len(self.points) - 1) * fraction)]
            centre = math.floor(x / 96), math.floor(z / 96)
            tiles, roads = set(), set()
            reach = math.ceil(384 / 96) + 1
            for dz in range(-reach, reach + 1):
                for dx in range(-reach, reach + 1):
                    key = centre[0] + dx, centre[1] + dz
                    cx, cz = (key[0] + .5) * 96, (key[1] + .5) * 96
                    if math.hypot(cx - x, cz - z) <= 384 + 96 * .71:
                        tiles.add(key)
                        roads.update(self.index.get(key, ()))
            self.assertLessEqual(len(tiles), 85)
            self.assertLessEqual(len(roads), 70)
            maximum_roads, maximum_tiles = max(maximum_roads, len(roads)), max(maximum_tiles, len(tiles))
        local_vertices = maximum_tiles * 17 * 17 + maximum_roads * 53 * 9
        full_road_vertices = (math.ceil(100000 / 2.5) + 1) * 9
        self.assertLess(local_vertices, full_road_vertices / 3)
        print(f'Conservative load-radius budget: <= {maximum_tiles} terrain tiles, <= {maximum_roads} road chunks; '
              f'<= {local_vertices} vertices vs {full_road_vertices} vertices in old road alone')


if __name__ == '__main__':
    unittest.main()
