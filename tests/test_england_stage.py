"""Англия: маршрут, река и мосты — численная проверка без Godot.

Проверяет то, что руками глазами не увидишь: мосты стоят ровно там, где
маршрут пересекает русло, настил лежит на линии дороги, вода проходит под
ним с запасом, а между мостами дорога от реки не «прилипает».

Запуск: python3 -m unittest tests.test_england_stage
"""
import bisect
import math
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import stage_model

ROUTE = ROOT / 'data/tracks/stage_england_route.tres'
RIVER = ROOT / 'data/tracks/stage_england_river.tres'
TRACK = ROOT / 'data/tracks/stage_england.tres'
CONFIG = ROOT / 'data/rally_game_config.tres'
SCENE = ROOT / 'scenes/rally_stage_england.tscn'
PROPS = ROOT / 'data/stage/default_prop_library.tres'

MAX_LENGTH = 4800.0      # дальше включается автопоток мира (5 км)
MAX_GRADE = 0.095
WATER_MIN = 2.5          # просвет под настилом, м
ROAD_GAP_MIN = 24.0      # дорога не ближе этого к оси реки вне мостов
BRIDGE_ZONE = 90.0       # ±90 м вокруг моста — на подходе к нему дорога сближается законно


def _numbers(text, field):
    match = re.search(r'^%s = (-?[\d.]+)' % field, text, re.M)
    return float(match.group(1)) if match else None


class EnglandStageTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.route = stage_model.sample_curve(stage_model.load_curve(str(ROUTE)), step=1.0)
        cls.river = stage_model.sample_curve(stage_model.load_curve(str(RIVER)), step=1.0)
        # Река в плане монотонна по Z — по ней и строим таблицу «z → x, y».
        cls.river.sort(key=lambda p: p[2])
        cls.river_z = [p[2] for p in cls.river]
        cls.text = TRACK.read_text(encoding='utf-8')
        cls.bridges = []
        for match in re.finditer(r'id="(\w+)"\]\n((?:(?!\[sub_resource|\[resource)[\s\S])*)', cls.text):
            block = match.group(2)
            if 'prop_id' not in block or 'open_radius' not in block:
                continue
            cls.bridges.append({
                'id': match.group(1),
                'distance': _numbers(block, 'distance'),
                'prop_id': re.search(r'^prop_id = "([^"]+)"', block, re.M).group(1),
                'open_radius': _numbers(block, 'open_radius'),
                'deck_offset': _numbers(block, 'deck_offset') or 0.0,
                'water_clearance': _numbers(block, 'water_clearance'),
            })

    # ------------------------------------------------------------ река
    def river_at(self, z):
        """(x, y) оси реки в сечении z; None за пределами русла."""
        if not self.river_z or z < self.river_z[0] + 1.0 or z > self.river_z[-1] - 1.0:
            return None
        i = bisect.bisect_left(self.river_z, z)
        a, b = self.river[i - 1], self.river[i]
        span = b[2] - a[2]
        t = 0.0 if abs(span) < 1e-6 else (z - a[2]) / span
        return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)

    def point_at(self, distance):
        return self.route[max(0, min(len(self.route) - 1, int(round(distance))))]

    # ---------------------------------------------------------- маршрут
    def test_length_is_under_streaming_limit(self):
        length = sum(math.dist(a, b) for a, b in zip(self.route, self.route[1:]))
        self.assertLess(length, MAX_LENGTH)
        self.assertGreater(length, 3000)
        print(f'Длина маршрута {length:.0f} м')

    def test_grade_and_climb(self):
        heights = [p[1] for p in self.route]
        self.assertGreater(max(heights) - min(heights), 120)
        for a, b in zip(self.route, self.route[1:]):
            run = math.hypot(b[0] - a[0], b[2] - a[2])
            if run > 0.001:
                self.assertLess(abs(b[1] - a[1]) / run, MAX_GRADE)
        print(f'Высоты {min(heights):.1f} … {max(heights):.1f} м')

    # ----------------------------------------------------------- мосты
    def test_two_bridges_declared(self):
        self.assertEqual(len(self.bridges), 2, self.bridges)
        for bridge in self.bridges:
            self.assertGreater(bridge['open_radius'] or 0.0, 8.0)
            self.assertIn(bridge['prop_id'], PROPS.read_text(encoding='utf-8'))

    def test_bridges_are_on_crossings(self):
        self.assertEqual(len(self.bridges), 2)
        crossings = []
        previous = None
        for point in self.route:
            axis = self.river_at(point[2])
            if axis is None:
                continue
            side = point[0] - axis[0]
            if previous is not None and previous * side < 0.0:
                crossings.append(point)
            previous = side
        self.assertEqual(len(crossings), 2, f'пересечений {len(crossings)}')
        for bridge, crossing in zip(self.bridges, crossings):
            # Пересечение должно совпасть с центром пролёта.
            near = min(range(len(self.route)),
                       key=lambda i: math.dist(self.route[i], crossing))
            self.assertAlmostEqual(float(near), bridge['distance'], delta=12.0)

    def test_water_passes_under_deck(self):
        self.assertEqual(len(self.bridges), 2)
        for bridge in self.bridges:
            point = self.point_at(bridge['distance'])
            axis = self.river_at(point[2])
            self.assertIsNotNone(axis, bridge['id'])
            deck = point[1] + bridge['deck_offset']
            clearance = deck - axis[1]
            self.assertGreaterEqual(clearance, WATER_MIN - 0.1, bridge['id'])
            if bridge['water_clearance']:
                self.assertAlmostEqual(clearance, bridge['water_clearance'], delta=0.35, msg=bridge['id'])
            print(f"{bridge['id']}: вода на {clearance:.2f} м ниже настила")

    def test_road_stays_away_from_river(self):
        self.assertEqual(len(self.bridges), 2)
        zones = [(b['distance'] - BRIDGE_ZONE, b['distance'] + BRIDGE_ZONE) for b in self.bridges]
        for index, point in enumerate(self.route):
            if any(low <= index <= high for low, high in zones):
                continue
            axis = self.river_at(point[2])
            if axis is None:
                continue
            self.assertGreater(abs(point[0] - axis[0]), ROAD_GAP_MIN,
                               f'{index} м: дорога вплотную к руслу')

    def test_bridges_do_not_share_space(self):
        self.assertEqual(len(self.bridges), 2)
        first, second = self.bridges
        self.assertGreater(abs(second['distance'] - first['distance']),
                           first['open_radius'] + second['open_radius'] + 100.0)

    # -------------------------------------------------- регистрация/сцена
    def test_registered_and_scene_wired(self):
        self.assertIn('stage_england.tres', CONFIG.read_text(encoding='utf-8'))
        scene = SCENE.read_text(encoding='utf-8')
        self.assertIn('stage_england.tres', scene)
        self.assertIn('track_override', scene)
        self.assertIn('stage_england_river.tres', self.text)
        self.assertIn('bridge_small', self.text)
        self.assertIn('bridge_large', self.text)


if __name__ == '__main__':
    unittest.main()
