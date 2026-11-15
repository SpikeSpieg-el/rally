"""Кто владеет быстрым состоянием машины, а кто — её настройкой.

Здесь собраны баги из ревью `rally_car.gd`, у которых один общий корень:
значение с двумя владельцами. `Wheel` пишет `current_cof` сам, а машина
пыталась плавно вести его к цели ручника — они перебивали друг друга.
`RallyCarFeelConfig.mouse_return_speed` дублировался экспортом на узле, и
правка в инспекторе сцены молча не работала. `reset_to_spawn()` приравнивал
настройку (`enable_stability`) к быстрому состоянию и гасил её навсегда.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def function(source: str, header: str) -> str:
    """Тело функции без следующего обработчика."""
    body = source.split(header, 1)[1]
    return body.split("\nfunc ", 1)[0]


class HandbrakeGripTest(unittest.TestCase):
    """Сглаживается множитель ручника, а не `current_cof` колеса."""

    def test_scale_is_smoothed_not_the_wheel_value(self):
        car = read("scripts/rally_car.gd")
        block = function(car, "func _update_handbrake_grip(delta: float) -> void:")
        # Сглаженный множитель — состояние машины, отдельное от колеса.
        self.assertIn("_handbrake_grip_scale = lerpf(", block)
        # Значение колеса собирается заново из таблицы каждый такт: смена
        # покрытия не выдаёт полный грип посреди возврата.
        self.assertIn(
            "wheel.current_cof = _get_surface_cof(str(wheel.surface_type)) * _handbrake_grip_scale",
            block,
        )
        # Старый баг: lerp по current_cof, который Wheel переписывает сам.
        self.assertNotIn("lerpf(wheel.current_cof", block)

    def test_wheel_owns_the_table_only_on_surface_change(self):
        # Поведение базового класса, на которое опирается машина: комментарий
        # должен объяснять именно это, иначе следующий правщик снова начнёт
        # сглаживать current_cof.
        car = read("scripts/rally_car.gd")
        before = car.split("func _update_handbrake_grip", 1)[0].rstrip().splitlines()
        comment: list[str] = []
        for line in reversed(before):
            if line.lstrip().startswith("##"):
                comment.append(line)
                continue
            break
        self.assertTrue(comment, "у _update_handbrake_grip нет док-комментария")
        text = "\n".join(comment)
        self.assertIn("current_cof", text, "комментарий не объясняет владельца current_cof")
        self.assertIn("surface_type", text, "комментарий не объясняет, когда Wheel пишет таблицу")

    def test_setup_change_keeps_the_handbrake_state(self):
        car = read("scripts/rally_car.gd")
        block = function(car, "func _refresh_grip_tuning() -> void:")
        self.assertIn("_handbrake_grip_scale", block)

    def test_reset_releases_the_handbrake_scale(self):
        car = read("scripts/rally_car.gd")
        block = function(car, "func reset_to_spawn() -> void:")
        self.assertIn("_handbrake_grip_scale = 1.0", block)


class RoughnessTimingTest(unittest.TestCase):
    """Вибрация геймпада получает покрытие текущего кадра, а не прошлого."""

    def test_roughness_is_computed_before_feedback(self):
        car = read("scripts/rally_car.gd")
        physics = function(car, "func _physics_process(delta: float) -> void:")
        roughness_at = physics.index("_surface_roughness_value = _surface_roughness()")
        feedback_at = physics.index("_update_driving_feedback(controller)")
        self.assertLess(roughness_at, feedback_at)
        # И ровно один раз за такт, а не два.
        self.assertEqual(physics.count("_surface_roughness_value = _surface_roughness()"), 1)


class ResetKeepsSetupTest(unittest.TestCase):
    """`reset_to_spawn()` не переписывает настройки машины."""

    def test_stability_survives_a_reset(self):
        car = read("scripts/rally_car.gd")
        reset = function(car, "func reset_to_spawn() -> void:")
        self.assertNotIn("enable_stability =", reset)
        # Стартовое значение по-прежнему задаётся в конфигурации GEVP.
        self.assertIn("enable_stability = false", function(car, "func _configure_gevp() -> void:"))

    def test_drivetrain_is_documented_as_a_race_control(self):
        # Переключение привода во время заезда — игровая функция (см. README,
        # таблица управления), а не отладочная кнопка. Поэтому респавн его не
        # сбрасывает, а объяснение живёт рядом с обработчиком клавиши.
        car = read("scripts/rally_car.gd")
        physics = function(car, "func _physics_process(delta: float) -> void:")
        self.assertIn('Input.is_action_just_pressed("drivetrain_switch")', physics)
        readme = read("README_RU.md")
        self.assertIn("привод AWD → RWD → FWD", readme)
        # И это не debug-ветка сборки: действие есть в обычных биндингах.
        self.assertIn('{"id":"drivetrain_switch"', read("scripts/input/input_bindings.gd"))


if __name__ == "__main__":
    unittest.main()
