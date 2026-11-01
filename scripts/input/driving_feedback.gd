## Расчёт обратной связи отдельно от ввода/железа, чтобы его можно было тестировать.
extends RefCounted

static func calculate(speed_kmh: float, rpm_ratio: float, slip: float, grounded: bool, roughness: float, throttle: float, brake: float) -> Dictionary:
	var speed := clampf(speed_kmh / 130.0, 0.0, 1.0)
	var rpm := clampf(rpm_ratio, 0.0, 1.0)
	var slide := clampf(slip, 0.0, 1.0)
	var rough := clampf(roughness, 0.0, 1.0) if grounded else 0.0
	return {
		"weak": clampf(0.08 * rpm + speed * rough * 0.35 + slide * speed * 0.18, 0.0, 0.65),
		"strong": clampf(speed * rough * 0.14 + slide * speed * 0.24, 0.0, 0.55),
		"left": clampf(0.25 + speed * 0.35 + clampf(brake, 0.0, 1.0) * 0.2, 0.0, 1.0),
		"right": clampf(0.18 + rpm * 0.25 + clampf(throttle, 0.0, 1.0) * 0.15, 0.0, 1.0),
	}
