"""Continuous, sparse road events on every registered track (no engine)."""
from pathlib import Path
import math
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import road_profile as profile
import stage_model
from procedural_route import Gen


class RoadProfileTest(unittest.TestCase):
    def test_all_tracks_have_flat_intervals_and_bounded_grade(self):
        # stage_pereval больше не существует (трасса удалена из репозитория),
        # список — только играбельные трассы с файлом конфига.
        for name in ('forest', 'north_arc', 'dynamic', 'mountain_100'):
            cfg = stage_model.read_track(str(ROOT / f'data/tracks/stage_{name}.tres'))
            cfg['route_length'] = 10000
            values = [stage_model.bumps(i * .25, cfg) for i in range(40001)]
            flat = sum(abs(v) < .0001 for v in values) / len(values)
            grade = max(abs(a - b) / .25 for a, b in zip(values, values[1:]))
            self.assertGreater(flat, .45, name)
            self.assertLess(grade, .09, name)
            self.assertEqual(values[0], 0)
            self.assertEqual(values[-1], 0)
            print(f'{name}: {flat:.0%} flat, maximum added grade {grade:.1%}')

    def test_no_steps_at_event_or_patch_boundaries(self):
        for seed in (2024, 8123, 777, 1002400):
            for step in (96, 320):
                for i in range(1, 50):
                    d = float(i * step)
                    self.assertLess(abs(profile.sample(d - .001, seed) - profile.sample(d + .001, seed)), .0002)
        for kind in range(5):
            self.assertAlmostEqual(profile.shape(0, kind), 0)
            self.assertAlmostEqual(profile.shape(1, kind), 0)

    def test_seed_and_patterns(self):
        first = [profile.sample(d, 8123) for d in range(10000)]
        self.assertEqual(first, [profile.sample(d, 8123) for d in range(10000)])
        self.assertNotEqual(first, [profile.sample(d, 8124) for d in range(10000)])
        kinds = {int(profile.roll(i, 8123, 4) * 5) for i in range(100)}
        self.assertEqual(kinds, set(range(5)))
        self.assertTrue(any(v > .3 for v in first))
        self.assertTrue(any(v < -.3 for v in first))

    def test_new_generator_patterns_are_real_and_bounded(self):
        for kind in ('tightening', 'opening', 'double_apex', 'crest_turn', 'compression', 'shelf'):
            builder = Gen(4711, 2000, 2500)
            segments = builder._feature(kind, .03)
            self.assertGreaterEqual(len(segments), 3, kind)
            for seg in segments:
                length = seg[1] if seg[0] == 's' else seg[1] * math.radians(seg[2])
                climb = seg[2] if seg[0] == 's' else seg[3]
                self.assertLess(abs(climb / length), .09, kind)


if __name__ == '__main__':
    unittest.main()
