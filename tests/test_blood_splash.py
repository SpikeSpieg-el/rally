"""Regression checks for directed, non-explosive spectator blood splashes."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def value(block: str, name: str) -> str:
    match = re.search(rf"^{re.escape(name)}\s*=\s*(.+)$", block, re.MULTILINE)
    if not match:
        raise AssertionError(f"Не найдено поле {name}")
    return match.group(1)


def scene_block(text: str, kind: str, name: str) -> str:
    if kind == "node":
        pattern = rf'^\[node name="{re.escape(name)}"[^\]]*\]\n(.*?)(?=^\[node|\Z)'
    else:
        pattern = rf'^\[sub_resource type="{re.escape(kind)}" id="{re.escape(name)}"\]\n(.*?)(?=^\[sub_resource|^\[node|\Z)'
    match = re.search(pattern, text, re.MULTILINE | re.DOTALL)
    if not match:
        raise AssertionError(f"Не найден блок {kind}/{name}")
    return match.group(1)


class BloodSplashTest(unittest.TestCase):
    def test_centered_forward_hit_also_splats_windshield(self):
        blood = read("scripts/effects/rally_blood_fx.gd")
        direct = blood.split("static func is_direct_front_impact(", 1)[1].split("\n\nfunc add_splat(", 1)[0]
        add_splat = blood.split("func add_splat(", 1)[1].split("\n\nfunc update(", 1)[0]

        z_min = float(re.search(r"FRONT_GLASS_SPLASH_Z\s*:=\s*([0-9.]+)", blood).group(1))
        half_width = float(re.search(r"FRONT_GLASS_SPLASH_HALF_WIDTH\s*:=\s*([0-9.]+)", blood).group(1))
        min_speed = float(re.search(r"FRONT_GLASS_SPLASH_MIN_SPEED\s*:=\s*([0-9.]+)", blood).group(1))
        forward_ratio = float(re.search(r"FRONT_GLASS_SPLASH_FORWARD_RATIO\s*:=\s*([0-9.]+)", blood).group(1))

        def is_direct_front(point, velocity):
            required = max(min_speed, abs(velocity[0]) * forward_ratio)
            return point[2] >= z_min and abs(point[0]) <= half_width and velocity[2] >= required

        self.assertTrue(is_direct_front((0.0, 0.7, 1.8), (0.0, 0.0, 8.0)))
        self.assertFalse(is_direct_front((0.0, 0.7, -1.8), (0.0, 0.0, 8.0)))
        self.assertFalse(is_direct_front((0.9, 0.7, 1.8), (0.0, 0.0, 8.0)))
        self.assertFalse(is_direct_front((0.0, 0.7, 1.8), (0.0, 0.0, -8.0)))
        self.assertIn("local_hit.z >= FRONT_GLASS_SPLASH_Z", direct)
        self.assertIn("local_velocity.z >= required_forward_speed", direct)
        self.assertIn("var glass_hit: bool = _is_glass_zone(raw_local_hit) or direct_front_hit", add_splat)

    def test_people_spray_from_the_real_impact_and_aim_front_splash_at_glass(self):
        person = read("scripts/track/spectator_person.gd")
        crush = person.split("func crush(", 1)[1].split("\n\nfunc _apply_car_blood", 1)[0]
        burst_origin = person.split("func _burst_origin(", 1)[1].split("\n\nfunc _splash_direction", 1)[0]
        splash_direction = person.split("func _splash_direction(", 1)[1].split("\n\nfunc _flatten", 1)[0]

        self.assertIn("BloodFx.is_direct_front_impact(car, hit_world, velocity)", crush)
        self.assertIn("_burst_origin(car, hit_world, direct_front_hit)", crush)
        self.assertIn("BloodFx.spray(spray_host, burst_world, velocity, blood_burst, splash_direction)", crush)
        self.assertIn("local_hit + outward * 0.38", burst_origin)
        self.assertIn("local_origin.z = maxf(local_origin.z, 2.45)", burst_origin)
        self.assertIn("Vector3(0.0, 0.9, -1.0)", splash_direction)

    def test_particles_are_a_small_splash_not_a_large_explosion(self):
        scene = read("scenes/effects/blood_burst.tscn")
        droplets = scene_block(scene, "node", "Droplets")
        mist = scene_block(scene, "node", "Mist")
        droplet_material = scene_block(scene, "ParticleProcessMaterial", "Process_drop")
        mist_material = scene_block(scene, "ParticleProcessMaterial", "Process_mist")

        self.assertEqual(int(value(droplets, "amount")), 48)
        self.assertLess(float(value(droplets, "explosiveness")), 1.0)
        self.assertLess(float(value(droplets, "lifetime")), 1.0)
        self.assertLess(float(value(droplet_material, "spread")), 35.0)
        self.assertLess(float(value(droplet_material, "initial_velocity_max")), 6.0)
        self.assertEqual(int(value(mist, "amount")), 14)
        self.assertLess(float(value(mist, "lifetime")), 0.5)
        # trail_lifetime у Mist не должен задаваться явно: сеттер
        # GPUParticles3D.set_trail_lifetime() отбрасывает значения < 0.01
        # (в т.ч. 0.0) с ошибкой C++. Дефолт свойства — 0.0, трейлы выключены.
        self.assertNotIn("trail_lifetime", mist)
        self.assertLess(float(value(mist_material, "initial_velocity_max")), 1.5)

    def test_reused_burst_does_not_accumulate_speed_each_hit(self):
        burst = read("scripts/effects/rally_blood_burst.gd")
        restart = burst.split("func _restart(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("BASE_VELOCITY_META", restart)
        self.assertIn("base_min + bonus * 0.45", restart)
        self.assertIn("base_max + bonus", restart)
        self.assertNotIn("process_mat.initial_velocity_min + bonus", restart)
        self.assertIn('const PREWARM_META := "blood_prewarm"', burst)
        self.assertIn("inherit_velocity_ratio", burst)
        self.assertIn("heading - world_velocity.normalized() * 0.28", burst)

        person = read("scripts/track/spectator_person.gd")
        self.assertIn("local_origin.z = maxf(local_origin.z, 2.45)", person)


if __name__ == "__main__":
    unittest.main()
