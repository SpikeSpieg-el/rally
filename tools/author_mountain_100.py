"""Reproducible 100 km mountain endurance stage; run from any directory.

Compact, non-crossing switchback terraces keep the existing rectangular
terrain builder bounded. Curves have monotone elevation handles.
"""
from pathlib import Path
import math
import random
import road_profile
import route_kit as kit

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'data/tracks/stage_mountain_100_route.tres'


def build():
    rng = random.Random(1002400)
    segments = []
    for terrace in range(64):
        # Balanced but unequal bends: no repeating four-turn template.
        # Mirrored radii keep each terrace inside its clearance envelope.
        for j in range(rng.randint(3, 5)):
            radius_in = rng.uniform(24, 65)
            radius_out = rng.uniform(26, 60)
            angle = rng.uniform(26, 55)
            segments += [('s', 65.0 if terrace == 0 and j == 0 else rng.uniform(80, 220), 0)]
            sign = 1 if terrace % 2 == 0 else -1
            if (terrace + j) % 3 == 0:
                # Broad approach followed by a tightening turn and recovery.
                radius_in, radius_out = max(radius_in, 55), min(radius_out, 32)
            segments += [('a', radius_in, angle, 0, sign),
                         ('a', radius_out, angle, 0, -sign),
                         ('a', radius_out, angle, 0, -sign),
                         ('a', radius_in, angle, 0, sign)]
        segments += [('s', 90, 0)]
        if terrace < 63:
            # Hairpin with safe approach/exit shelves, 160 m between terraces.
            segments += [('a', 80, 180, 0, 1 if terrace % 2 == 0 else -1),
                         ('s', 90, 0)]
    pts, _ = kit.compose(segments, step=1.0)
    acc = kit.xz_distances(pts)
    scale = 100000 / acc[-1]
    result = []
    for (x, z, _), d in zip(pts, acc):
        u = d / acc[-1]
        # Start at 320 m; sustained climb to a 2,400 m pass at km 58.
        # Short local crests add compression/release without impossible slopes.
        if u <= .58:
            base = 320 + 2080 * (.5 - .5 * math.cos(math.pi * u / .58))
        else:
            base = 780 + 1620 * (.5 + .5 * math.cos(math.pi * (u - .58) / .42))
        # Isolated geological shelves/crests instead of a pair of sine waves.
        feature = road_profile.sample(d * scale, 1002400, 7, 1800, 0, 0, 9)
        feature *= road_profile.ease(d * scale / 700) * road_profile.ease((100000 - d * scale) / 700)
        # Clearly visible uphill immediately after the launch zone, easing
        # back into the sustained mountain profile over several kilometres.
        distance = d * scale
        approach = 32 * (1 - math.exp(-distance / 500))
        approach *= 1 - road_profile.ease((distance - 1500) / 2000)
        result.append((x * scale, z * scale, base + feature + approach))
    controls = kit.select_controls(result, max_gap=28, min_gap=5, turn_trigger_deg=7)
    kit.write_curve(controls, str(OUT))
    # Normalize the written Bezier, including altitude, not just plan length.
    for _ in range(2):
        samples = kit._sample_written(str(OUT), step=0.5)
        length = sum(math.dist(a, b) for a, b in zip(samples, samples[1:]))
        ratio = 100000 / length
        controls = [(x * ratio, z * ratio, y * ratio) for x, z, y in controls]
        kit.write_curve(controls, str(OUT))
    print(f'{len(controls)} controls; length before final correction {length:.2f} m')


if __name__ == '__main__':
    build()
