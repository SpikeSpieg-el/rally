"""Configuration checks; the actual dynamics are covered by car_obstacle_collision.gd."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

def text(path):
    return (ROOT / path).read_text(encoding='utf-8')

class CarCollisionConfig(unittest.TestCase):
    def test_both_cars_keep_obstacle_collision_and_ccd(self):
        for name in ('rally_car.tscn', 'rally_car2.tscn'):
            scene = text('scenes/' + name)
            self.assertIn('collision_mask = 3\ncontinuous_cd = true', scene)
            self.assertIn('friction = 0.15', scene)
            self.assertIn('type="ConvexPolygonShape3D"', scene)

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
