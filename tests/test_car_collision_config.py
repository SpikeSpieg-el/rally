"""Configuration checks; the actual dynamics are covered by car_obstacle_collision.gd."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]

def text(path):
    return (ROOT / path).read_text(encoding='utf-8')

def rally_car_props(scene):
    """Свойства узла RallyCar: {ключ: значение}.

    Порядок строк в .tscn задаёт Godot при сохранении (mass и материал могут
    встать между collision_mask и continuous_cd), поэтому проверяем свойства
    по отдельности, а не соседством строк.
    """
    match = re.search(r'^\[node name="RallyCar"[^\n]*\]\n(.*?)(?=^\[|\Z)', scene, re.S | re.M)
    assert match, "в сцене нет узла RallyCar"
    return dict(re.findall(r'^(\w+) = (.*)$', match.group(1), re.M))


def car_scenes():
    """Все игровые сцены машин: список не должен жить в тесте."""
    return sorted(scene.relative_to(ROOT).as_posix()
                  for scene in (ROOT / 'scenes').glob('rally_car*.tscn'))


class CarCollisionConfig(unittest.TestCase):
    def test_every_car_keeps_obstacle_collision_and_ccd(self):
        scenes = car_scenes()
        self.assertTrue(scenes, 'в scenes/ нет сцен машин rally_car*.tscn')
        for name in scenes:
            scene = text(name)
            props = rally_car_props(scene)
            # Слой 2 — препятствия (отбойники, заборы, деревья): машина должна
            # их бить, а CCD не даёт колесу провалиться сквозь тонкий барьер.
            self.assertEqual(props.get('collision_mask'), '3', name)
            self.assertEqual(props.get('continuous_cd'), 'true', name)
            self.assertIn('friction = 0.15', scene, name)
            self.assertIn('type="ConvexPolygonShape3D"', scene, name)

    def test_barriers_and_trunks_do_not_become_suspension_ground(self):
        for name in ('metal_guardrail', 'wooden_fence', 'pine_tree'):
            scene = text('scenes/props/' + name + '.tscn')
            self.assertIn('type="StaticBody3D"', scene)
            self.assertIn('collision_layer = 2', scene)
        stage = text('scripts/rally_stage.gd')
        self.assertIn('shape.size = GuardrailPlacement.collision_size(a, b)', stage)
        self.assertGreaterEqual(stage.count('body.collision_layer = 2'), 2)
        self.assertIn('create(pivot, ideal_cam_pos, 3,', text('scripts/rally_car.gd'))

    def test_ground_check_is_used_consistently(self):
        wheel = text('scripts/gevp/wheel.gd')
        self.assertIn('get_collision_normal().dot(Vector3.UP) > 0.25', wheel)
        for path in ('scripts/gevp/vehicle.gd', 'scripts/rally_car.gd'):
            self.assertNotIn('wheel.is_colliding()', text(path))

if __name__ == '__main__':
    unittest.main()
