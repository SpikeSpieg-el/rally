## Независимое оформление и логика частиц для одного типа покрытия.
## Каждый тип получает собственные цвета, поведение и три уровня интенсивности.
@tool
class_name RallySurfaceFxProfile
extends Resource

enum Kind { GRAVEL, MUD, GRASS, SNOW, ASPHALT }

@export_group("Покрытие")
@export_enum("Гравий", "Грязь", "Трава", "Снег", "Асфальт") var kind: int = Kind.GRAVEL
@export var enabled: bool = true

@export_group("Вид частиц")
@export var dry_color: Color = Color(0.43, 0.35, 0.25, 0.62)
@export var wet_color: Color = Color(0.20, 0.13, 0.07, 0.82)
## Множитель силы тяжести из общего RallyFxProfile.
@export var gravity_scale: Vector3 = Vector3(1.0, 0.45, 1.0)
## Куда летит выброс; продольное направление автоматически разворачивается при движении назад.
@export var direction: Vector3 = Vector3(0.0, 0.65, 1.0)
@export_range(0.1, 4.0, 0.05) var amount_scale: float = 1.0
@export_range(0.1, 4.0, 0.05) var lifetime_scale: float = 1.0
@export_range(0.1, 4.0, 0.05) var spread_scale: float = 1.0
@export_range(0.1, 4.0, 0.05) var velocity_scale: float = 1.0
@export_range(0.1, 4.0, 0.05) var particle_scale: float = 1.0
@export_range(0.1, 4.0, 0.05) var grain_scale: float = 1.0

@export_group("Загрязнение кузова")
## Цвет пыли/грязи, которую это покрытие оставляет на кузове. Гравий — светлая
## пыль, грязь — тёмный налипший слой, трава — зеленоватый налёт.
@export var body_dirt_color: Color = Color(0.32, 0.235, 0.14, 1.0)
## Скорость налипания на кузов, ед/с. Отрицательное значение — брать общее
## gravel/mud/grass_dirt_rate из RallyFxProfile (старые ресурсы).
@export_range(-1.0, 0.5, 0.001) var body_dirt_rate: float = -1.0
## Густота пятна на кузове: множитель к общей body_coverage.
@export_range(0.05, 3.0, 0.05) var body_dirt_coverage: float = 1.0
## Насколько далеко от колеса расходится пятно: множитель к body_spread.
@export_range(0.2, 3.0, 0.05) var body_dirt_spread: float = 1.0
## Предел непрозрачности слоя от этого покрытия: множитель к body_alpha.
@export_range(0.0, 1.0, 0.01) var body_dirt_alpha: float = 1.0

@export_group("Реакция на движение")
## Вклад обычного движения, пробуксовки и мокроты в силу выброса.
@export_range(0.0, 1.0, 0.01) var speed_weight: float = 0.60
@export_range(0.0, 1.0, 0.01) var slip_weight: float = 0.90
@export_range(0.0, 1.0, 0.01) var wet_weight: float = 0.20
@export_range(0.0, 150.0, 0.5) var speed_start_kmh: float = 4.0
@export_range(0.5, 250.0, 0.5) var speed_full_kmh: float = 70.0
@export_range(0.0, 3.0, 0.01) var slip_start: float = 0.10
@export_range(0.01, 4.0, 0.01) var slip_full: float = 0.80

@export_group("Уровни эффекта")
## Нулевая ступень скрыта. Первая — лёгкая пыль/брызги, третья — сильный занос.
@export_range(0.0, 1.0, 0.01) var level_1_threshold: float = 0.15
@export_range(0.0, 1.0, 0.01) var level_2_threshold: float = 0.43
@export_range(0.0, 1.0, 0.01) var level_3_threshold: float = 0.75
@export_range(0.0, 1.0, 0.01) var level_1_amount_ratio: float = 0.24
@export_range(0.0, 1.0, 0.01) var level_2_amount_ratio: float = 0.58
@export_range(0.0, 1.0, 0.01) var level_3_amount_ratio: float = 1.0
@export_range(0.1, 3.0, 0.05) var level_1_velocity_scale: float = 0.72
@export_range(0.1, 3.0, 0.05) var level_2_velocity_scale: float = 1.0
@export_range(0.1, 3.0, 0.05) var level_3_velocity_scale: float = 1.35

@export_group("Видимость и вклад")
## Во сколько раз дым гуще/прозрачнее, чем задано в профиле эффектов.
@export_range(0.2, 3.0, 0.05) var particle_tint: float = 1.0
## Сколько «работы» колесо превращает в дым/клубы (1 — как у гравия).
@export_range(0.0, 1.0, 0.01) var smoke_share: float = 0.55
## Сколько работы превращается в комья и капли (1 — как у гравия).
@export_range(0.0, 1.0, 0.01) var grit_share: float = 0.55
## Множитель скорости выброса (комочки летят быстрее/медленнее).
@export_range(0.05, 4.0, 0.05) var burst_scale: float = 1.0


func kind_name() -> String:
	match kind:
		Kind.MUD:
			return "mud"
		Kind.GRASS:
			return "grass"
		Kind.SNOW:
			return "snow"
		Kind.ASPHALT:
			return "asphalt"
		_:
			return "gravel"


func activity_for(speed_kmh: float, slip: float, wetness: float) -> float:
	var speed_end: float = maxf(speed_start_kmh + 0.1, speed_full_kmh)
	var slip_end: float = maxf(slip_start + 0.001, slip_full)
	var speed_activity: float = smoothstep(speed_start_kmh, speed_end, maxf(0.0, speed_kmh))
	var slip_activity: float = smoothstep(slip_start, slip_end, maxf(0.0, slip))
	var wet_activity: float = speed_activity * clampf(wetness, 0.0, 1.0) * wet_weight
	var activity: float = maxf(
		speed_activity * speed_weight, maxf(slip_activity * slip_weight, wet_activity)
	)
	return clampf(activity, 0.0, 1.0)


## 0 — эффекта нет, 1–3 — слабый, средний и сильный уровни.
func level_for(speed_kmh: float, slip: float, wetness: float) -> int:
	if not enabled:
		return 0
	var activity: float = activity_for(speed_kmh, slip, wetness)
	if activity < level_1_threshold:
		return 0
	if activity < maxf(level_1_threshold, level_2_threshold):
		return 1
	if activity < maxf(level_2_threshold, level_3_threshold):
		return 2
	return 3


## Плавная плотность по «силе» колеса: три полки из level_*_amount_ratio,
## между порогами — линейная интерполяция. Без ступенек: облако не «дёргается»,
## но три настроенных значения плотности реально работают.
func amount_ratio_for_activity(activity: float) -> float:
	var value := clampf(activity, 0.0, 1.0)
	if value <= level_1_threshold:
		return 0.0
	var points := [
		Vector2(level_1_threshold, level_1_amount_ratio),
		Vector2(maxf(level_1_threshold, level_2_threshold), level_2_amount_ratio),
		Vector2(maxf(level_2_threshold, level_3_threshold), level_3_amount_ratio),
		Vector2(1.0, level_3_amount_ratio),
	]
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		if value <= b.x or i == points.size() - 2:
			var span: float = maxf(b.x - a.x, 0.0001)
			return clampf(lerpf(a.y, b.y, clampf((value - a.x) / span, 0.0, 1.0)), 0.0, 1.0)
	return clampf(level_3_amount_ratio, 0.0, 1.0)


func amount_ratio_for_level(level: int) -> float:
	match clampi(level, 0, 3):
		1:
			return clampf(level_1_amount_ratio, 0.0, 1.0)
		2:
			return clampf(level_2_amount_ratio, 0.0, 1.0)
		3:
			return clampf(level_3_amount_ratio, 0.0, 1.0)
		_:
			return 0.0


func velocity_scale_for_level(level: int) -> float:
	match clampi(level, 0, 3):
		1:
			return level_1_velocity_scale
		2:
			return level_2_velocity_scale
		3:
			return level_3_velocity_scale
		_:
			return 0.0


func color_for_wetness(wetness: float) -> Color:
	return dry_color.lerp(wet_color, clampf(wetness, 0.0, 1.0))
