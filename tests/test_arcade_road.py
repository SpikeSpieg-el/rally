"""Аркадная бесконечная дорога: инварианты генерации (без Godot).

Проверяется то, что нельзя увидеть глазами в один заезд:
  * стыки участков не разъезжаются (чанк, собранный заново, встаёт на место);
  * участок ровно 260 м — иначе километраж в очках и HUD разойдётся с дорогой;
  * уклон профиля в пределах 7°, а высота на стыке совпадает с соседом;
  * ширина полотна непрерывна и остаётся в разумных пределах;
  * дорога НЕ сворачивается сама в себя и уходит от старта — иначе бесконечная
    трасса через полчаса езды начнёт петлять по собственному следу;
  * результат не зависит от порядка сборки (построил 40-й участок первым или
    сороковым — точки те же).

Запуск: python3 -m unittest tests.test_arcade_road
"""
import math
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import arcade_road_model as road

SEED = 2026
LEGS = 120
MIN_CLEARANCE = 25.0     # зазор между участками, далёкими по километражу
MIN_LINEARITY = 0.45     # пройденный путь к расстоянию по прямой


def _collect(legs, seed=SEED):
    points = []
    for leg in range(legs):
        leg_points, _ = road.build_leg(leg, seed)
        points.extend(leg_points)
    return points


class ArcadeRoadTest(unittest.TestCase):
    def test_chunk_seams_are_exact(self):
        for seed in (SEED, 77, 8123):
            for leg in range(0, 40):
                first, boundary = road.build_leg(leg, seed)
                second, _ = road.build_leg(leg + 1, seed)
                self.assertAlmostEqual(first[-1][0], second[0][0], places=6)
                self.assertAlmostEqual(first[-1][1], second[0][1], places=6)
                self.assertAlmostEqual(boundary[0], second[0][0], places=6)
                self.assertAlmostEqual(boundary[1], second[0][1], places=6)

    def test_every_leg_is_exactly_leg_length(self):
        for leg in range(0, 40):
            points, _ = road.build_leg(leg, SEED)
            travelled = points[-1][2] - leg * road.LEG_LENGTH
            self.assertAlmostEqual(travelled, road.LEG_LENGTH, places=2, msg=f'участок {leg}')
            end_x, end_z, end_heading, end_along = road.walk_leg_raw(leg, SEED)
            self.assertAlmostEqual(end_along, (leg + 1) * road.LEG_LENGTH, places=2)
            # Курс на выходе практически совпадает с осью: дорога привязана к
            # ней на каждом стыке доменов, поэтому не может накопить «закрутку».
            # Допуск 2° — это сжатые до MIN_PINNED_SWEEP дуги в самых крутых
            # серпантинах: там поворот ограничен, а не потерян.
            self.assertLess(abs(road.wrapf(end_heading - road.axis_heading(end_along, SEED),
                                           -math.pi, math.pi)), math.radians(2.0),
                            f'участок {leg}: курс ушёл от оси')

    def test_grade_is_bounded_and_joints_match(self):
        worst_grade = 0.0
        for i in range(0, 120000):
            worst_grade = max(worst_grade, abs(road.elevation_slope(i * 0.5, SEED)))
        self.assertLessEqual(math.degrees(math.atan(worst_grade)), road.MAX_GRADE_DEG + 0.001)
        for leg in range(0, 40):
            points, _ = road.build_leg(leg, SEED)
            joint = (leg + 1) * road.LEG_LENGTH
            self.assertAlmostEqual(road.elevation_at(joint, SEED),
                                   road.elevation_at(points[-1][2], SEED), places=6)

    def test_width_is_continuous_and_sane(self):
        for leg in range(0, 40):
            joint = leg * road.LEG_LENGTH
            self.assertAlmostEqual(road.half_width_at(joint - 0.001, SEED),
                                   road.half_width_at(joint + 0.001, SEED), places=4)
        widths = [road.half_width_at(d, SEED) for d in range(0, 40000, 5)]
        self.assertGreaterEqual(min(widths), 4.2)
        self.assertLessEqual(max(widths), 6.2)

    def test_road_never_folds_back_on_itself(self):
        points = _collect(LEGS)
        cell = 50.0
        grid = {}
        for index, (x, z, _) in enumerate(points):
            grid.setdefault((int(x // cell), int(z // cell)), []).append(index)
        best = float('inf')
        for x, z, along in points:
            cx, cz = int(x // cell), int(z // cell)
            for dx in (-2, -1, 0, 1, 2):
                for dz in (-2, -1, 0, 1, 2):
                    for other in grid.get((cx + dx, cz + dz), ()):
                        ox, oz, oalong = points[other]
                        if abs(oalong - along) < 200.0:
                            continue
                        best = min(best, math.hypot(ox - x, oz - z))
        self.assertGreater(best, MIN_CLEARANCE,
                           f'дорога подошла к собственному следу на {best:.1f} м')

    def test_road_makes_progress_away_from_start(self):
        points = _collect(LEGS)
        travelled = points[-1][2]
        straight = math.hypot(points[-1][0], points[-1][1])
        self.assertGreater(straight / travelled, MIN_LINEARITY,
                           f'{travelled / 1000:.0f} км пути дали {straight / 1000:.1f} км по прямой')

    def test_hairpins_are_real_hairpins(self):
        radii = []
        for leg in range(0, LEGS):
            for slot, (kind, share) in enumerate(road.shares(SEED, leg)):
                if kind != road.SERPENTINE:
                    continue
                for piece in road.pieces(kind, leg, SEED, slot, road.LEG_LENGTH * share):
                    if piece[0] == 'a':
                        radii.append((piece[1], math.degrees(abs(piece[2]))))
        self.assertTrue(radii, 'на 15 км не встретилось ни одного серпантина')
        for radius, sweep in radii:
            self.assertGreaterEqual(radius, 10.0)
            self.assertLessEqual(radius, 20.0)
            self.assertGreater(sweep, 90.0, 'поворот на серпантине должен быть крутым')

    def test_result_does_not_depend_on_build_order(self):
        isolated, _ = road.build_leg(47, SEED)
        road._CACHE.clear()
        sequential = None
        for leg in range(0, 48):
            points, _ = road.build_leg(leg, SEED)
            if leg == 47:
                sequential = points
        self.assertEqual(len(isolated), len(sequential))
        for a, b in zip(isolated, sequential):
            self.assertAlmostEqual(a[0], b[0], places=9)
            self.assertAlmostEqual(a[1], b[1], places=9)

    def test_seed_changes_the_route(self):
        first = _collect(6, SEED)
        second = _collect(6, SEED + 1)
        self.assertNotEqual(first[-1][:2], second[-1][:2])


if __name__ == '__main__':
    unittest.main()
