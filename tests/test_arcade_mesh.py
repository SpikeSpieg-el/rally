"""Меш аркадного чанка: намотка треугольников и дорожная разметка.

Без Godot геометрию не запустить, но обе беды этого файла видны статически.

1. Намотка. Godot отбрасывает обратные грани. Полотно и земляная лента
   строятся одной сеткой, но полосы земли идут ПОПЕРЁК обхода полотна
   (-30 … -6.3, затем +6.3 … +30). С теми же индексами лента получила
   зеркальную намотку и стала невидимой: в игре вокруг дороги была пустота
   до самого неба. Здесь порядок треугольников восстанавливается из текста
   шейпера и проверяется численно.

2. Разметка. При одной широкой полосе на центр цвет размазывался по всей её
   ширине, и пунктир не читался. Теперь краска — отдельные узкие ряды, и
   проверяется, что полосы идут строго слева направо и что краска на них
   действительно попадает.

Запуск: python3 -m unittest tests.test_arcade_mesh
"""
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHUNK = ROOT / 'scripts/arcade/arcade_chunk.gd'


def _text(path):
    return path.read_text(encoding='utf-8')


def _number(text, pattern):
    found = re.search(pattern, text)
    return float(found.group(1)) if found else None


class WindingTest(unittest.TestCase):
    """Треугольники обеих лент должны быть видны сверху."""

    @classmethod
    def setUpClass(cls):
        text = _text(CHUNK)
        cls.line_half = _number(text, r'const LINE_HALF: float = ([\d.]+)')
        cls.shoulder = _number(text, r'const SHOULDER: float = ([\d.]+)')
        cls.edge = _number(text, r'const EDGE_BAND: float = ([\d.]+)')
        cls.verge_width = _number(text, r'const VERGE_WIDTH: float = ([\d.]+)')
        spreads = re.search(r'const VERGE_SPREAD := \[([^\]]+)\]', text).group(1)
        cls.spread = [float(v) for v in spreads.split(',')]
        cls.road_lanes = int(re.search(r'const ROAD_LANES := (\d+)', text).group(1))
        cls.verge_lanes = int(re.search(r'const VERGE_LANES := (\d+)', text).group(1))
        cls.flips = 'for i in range(0, indices.size(), 3)' in text

    def _laterals(self, half):
        return [
            -(half + self.shoulder + self.edge), -(half + self.shoulder), -half,
            -self.line_half, self.line_half,
            max(half * 0.5, self.line_half * 4.0) - self.line_half,
            max(half * 0.5, self.line_half * 4.0) + self.line_half,
            half + self.shoulder, half + self.shoulder + self.edge,
        ]

    def _verge_laterals(self, half):
        inner = half + self.shoulder + self.edge
        out = []
        for lane in range(self.verge_lanes):
            sign = -1.0 if lane < 3 else 1.0
            out.append(sign * (inner + self.verge_width * self.spread[lane]))
        return out

    @staticmethod
    def _normal(p0, p1, p2):
        u = [p1[i] - p0[i] for i in range(3)]
        v = [p2[i] - p0[i] for i in range(3)]
        return (u[1] * v[2] - u[2] * v[1],
                u[2] * v[0] - u[0] * v[2],
                u[0] * v[1] - u[1] * v[0])

    def _facing(self, laterals, flipped):
        """Знак y нормали первого треугольника (обход как в _grid_indices)."""
        side = (1.0, 0.0, 0.0)   # side_at(direction=+Z)
        def point(lane, along):
            return (side[0] * laterals[lane], 0.0, along)
        i0, i1, i2 = point(0, 0.0), point(1, 0.0), point(0, 2.5)
        if flipped:
            i1, i2 = i2, i1
        return self._normal(i0, i1, i2)[1]

    def test_road_faces_up(self):
        # Полотно видно в игре — его обход и есть эталон.
        for half in (2.9, 3.6, 4.8):
            self.assertLess(self._facing(self._laterals(half), False), 0.0,
                            f'полотно при half={half} смотрит вниз')

    def test_verge_faces_the_same_way_as_the_road(self):
        # Godot считает лицевой гранью обход по часовой стрелке, если смотреть
        # на неё. Смотрим сверху — значит нормаль по правилу правой руки
        # смотрит ВНИЗ. Эталон — полотно: оно в игре видно.
        road = self._facing(self._laterals(3.6), False)
        verge = self._facing(self._verge_laterals(3.6), self.flips)
        self.assertGreater(
            road * verge, 0.0,
            'земляная лента обходится зеркально полотну — Godot её не нарисует, '
            'и вокруг дороги будет пустота до самого неба')
        self.assertLess(verge, 0.0, 'лента земли смотрит вниз, как и полотно')

    def test_the_flip_is_what_makes_the_verge_visible(self):
        # Разворот треугольников в коде — не «на всякий случай»: без него
        # намотка ленты уходит вверх, и земля пропадает. Проверяем, что это
        # тот самый разворот, который чинит баг.
        without = self._facing(self._verge_laterals(3.6), False)
        with_flip = self._facing(self._verge_laterals(3.6), True)
        self.assertLess(without * with_flip, 0.0, 'разворот не меняет ориентацию')
        self.assertGreater(without, 0.0, 'без разворота земля должна быть отвёрнута')
        self.assertLess(with_flip, 0.0, 'с разворотом земля должна смотреть вниз')
        self.assertTrue(self.flips, 'в _verge_strip нет разворота треугольников')

    def test_lane_count_matches_the_lateral_list(self):
        self.assertEqual(len(self._laterals(3.6)), self.road_lanes,
                         'ROAD_LANES не совпадает с числом координат полос — '
                         'сетка соберётся мусором')
        self.assertEqual(len(self._verge_laterals(3.6)), self.verge_lanes)


class MarkingTest(unittest.TestCase):
    """Двухсторонка читается по разметке: осевая и линия полосы."""

    @classmethod
    def setUpClass(cls):
        text = _text(CHUNK)
        cls.text = text
        cls.line_half = _number(text, r'const LINE_HALF: float = ([\d.]+)')
        cls.dash_on = _number(text, r'const DASH_ON: float = ([\d.]+)')
        cls.dash_period = _number(text, r'const DASH_PERIOD: float = ([\d.]+)')
        cls.lane_on = _number(text, r'const LANE_DASH_ON: float = ([\d.]+)')
        cls.lane_period = _number(text, r'const LANE_DASH_PERIOD: float = ([\d.]+)')
        cls.lift = _number(text, r'const PAINT_LIFT: float = ([\d.]+)')

    def test_laterals_are_strictly_ordered(self):
        # Разметка — отдельные пары рядов; если порядок сбит, треугольники
        # вывернутся и краска исчезнет.
        text = self.text
        half = 3.6
        shoulder = half + 1.2
        outer = shoulder + 1.1
        lane_line = max(half * 0.5, self.line_half * 4.0)
        laterals = [-outer, -shoulder, -half, -self.line_half, self.line_half,
                    lane_line - self.line_half, lane_line + self.line_half,
                    shoulder, outer]
        for a, b in zip(laterals, laterals[1:]):
            self.assertLess(a, b, 'координаты полос полотна не по порядку')

    def test_paint_is_narrower_than_the_road(self):
        half = 3.6
        self.assertLess(self.line_half * 2.0, half * 0.25,
                        'осевая линия шире четверти полуширины — это не разметка')
        self.assertGreaterEqual(self.line_half, 0.05,
                                'линия тоньше 10 см на скорости не читается')

    def test_dashes_leave_gaps(self):
        self.assertLess(self.dash_on, self.dash_period, 'осевая сплошная')
        self.assertLess(self.lane_on, self.lane_period, 'линия полосы сплошная')
        self.assertGreater(self.dash_period - self.dash_on, 1.0,
                           'промежуток меньше метра — пунктир сольётся')
        self.assertNotAlmostEqual(self.dash_period, self.lane_period, places=3,
                                  msg='периоды совпадают — полосы пульсируют синхронно')

    def test_paint_is_lifted_above_the_asphalt(self):
        self.assertGreater(self.lift, 0.0,
                           'краска на той же глубине, что асфальт — будет мерцать')
        self.assertLess(self.lift, 0.05, 'краска висит над дорогой заметным слоем')

    def test_paint_colour_is_far_from_asphalt(self):
        # Достаём литералы цвета из _surface_color.
        colour = re.search(r'if _is_paint\([^)]*\):\s*\n\s*#[^\n]*\n\s*return Color\(([^)]+)\)',
                           self.text)
        self.assertIsNotNone(colour, 'в _surface_color нет отдельного цвета краски')
        paint = [float(v) for v in colour.group(1).split(',')]
        asphalt = [0.30, 0.28, 0.26]
        difference = sum(abs(paint[i] - asphalt[i]) for i in range(3))
        self.assertGreater(difference, 1.0,
                           'краска почти не отличается от асфальта — не видно')

    def test_both_marking_lines_exist(self):
        # Осевая и линия полосы: без второй дорога выглядит однополосной.
        self.assertIn('lane_line', self.text)
        self.assertIn('_road_laterals', self.text)


class LaneTest(unittest.TestCase):
    """Двухсторонка: машина едет по правой полосе, а не по осевой."""

    @classmethod
    def setUpClass(cls):
        cls.stage = (ROOT / 'scripts/arcade/arcade_stage.gd').read_text(encoding='utf-8')

    def test_car_drives_in_the_right_lane(self):
        # На двухсторонке середина дороги — разделительная линия. Машина,
        # поставленная на неё, едет по встречке с точки зрения разметки.
        self.assertIn('func _driving_lateral(', self.stage,
                      'в этапе нет расчёта полосы движения')
        self.assertIn('_frame_at', self.stage)
        code = '\n'.join(line.split('#', 1)[0] for line in self.stage.splitlines())
        self.assertIn('side * lateral', code,
                      'при расстановке машины не учитывается поперечный сдвиг полосы')

    def test_lane_is_between_the_centre_and_the_lane_line(self):
        # Полоса — между осевой (0) и линией полосы (half/2), ровно посередине.
        half = 3.6
        lane_line = max(half * 0.5, 0.09 * 4.0)
        centre = lane_line * 0.5
        self.assertGreater(centre, 0.4, 'машина почти на осевой')
        self.assertLess(centre, lane_line, 'машина за линией полосы')
        self.assertLess(centre + 1.0, half, 'машина свисает с полотна')


if __name__ == '__main__':
    unittest.main()
