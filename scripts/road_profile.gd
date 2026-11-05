## Непериодический профиль полотна. Один источник для дороги и рельефа.
## Крупные события отделены длинными ровными интервалами; мелочь локальна.
@tool
class_name RallyRoadProfile
extends RefCounted

static func roll(index: int, seed_value: int, salt: int) -> float:
	var n: int = posmod(index, 1000003) * 92821 + posmod(seed_value, 1000003) * 68917 + salt * 2833
	n = posmod((n ^ (n >> 13)) * 127, 1000003)
	return float(n) / 1000003.0

## Quintic: нулевые первая и вторая производные на краях, без изломов.
static func quintic_ease(value: float) -> float:
	var t: float = clampf(value, 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)

static func lobe(t: float, peak: float = 0.5) -> float:
	if t <= 0.0 or t >= 1.0:
		return 0.0
	return quintic_ease(t / peak) if t < peak else 1.0 - quintic_ease((t - peak) / (1.0 - peak))

static func shape(t: float, kind: int) -> float:
	match kind:
		0: # асимметричный гребень, длинный подход / короткий сброс
			return lobe(t, 0.63)
		1: # широкая просадка
			return -lobe(t, 0.42)
		2: # приподнятая полка с ровной вершиной
			return quintic_ease(t / 0.3) * (1.0 - quintic_ease((t - 0.72) / 0.28))
		3: # компрессия перед выходом на гребень
			return -0.65 * lobe(t / 0.6, 0.55) + 0.75 * lobe((t - 0.4) / 0.6, 0.6)
		_: # два разных широких бугра с седловиной, не синусоида
			return 0.8 * lobe(t / 0.7, 0.42) + 0.45 * lobe((t - 0.48) / 0.52, 0.6)

static func sample(along: float, seed_value: int, feature_height: float, feature_spacing: float,
	amplitude: float, roughness: float, wavelength: float, length: float = INF) -> float:
	var spacing: float = maxf(240.0, feature_spacing)
	var block: int = floori(along / spacing)
	var local: float = fposmod(along, spacing)
	var value: float = 0.0
	if roll(block, seed_value, 1) < 0.68:
		var start: float = spacing * lerpf(0.1, 0.22, roll(block, seed_value, 2))
		var span: float = spacing * lerpf(0.28, 0.61, roll(block, seed_value, 3))
		var t: float = (local - start) / span
		if t > 0.0 and t < 1.0:
			var kind: int = mini(4, int(roll(block, seed_value, 4) * 5.0))
			value = feature_height * lerpf(0.45, 1.0, roll(block, seed_value, 5)) * shape(t, kind)
	# Только редкие короткие пятна, а не стиральная доска по всей трассе.
	var patch: int = floori(along / 96.0)
	if roll(patch, seed_value, 11) < 0.32:
		var start: float = lerpf(18.0, 40.0, roll(patch, seed_value, 12))
		var span: float = clampf(wavelength * lerpf(2.2, 3.4, roll(patch, seed_value, 13)), 18.0, 38.0)
		var t: float = (fposmod(along, 96.0) - start) / span
		if t > 0.0 and t < 1.0:
			var sign_value: float = -1.0 if roll(patch, seed_value, 14) < 0.5 else 1.0
			value += sign_value * amplitude * lobe(t, 0.38 + roll(patch, seed_value, 15) * 0.24)
			value += roughness * shape(t, 3) * 0.5
	# Старт и финиш ровные даже при смене сида.
	return value * quintic_ease((along - 65.0) / 55.0) * quintic_ease((length - along - 65.0) / 55.0)
