## Математика «ощущения скорости» для камеры без тряски.
##
## Здесь нет ни одного узла сцены и ни одного образа: только чистые функции,
## поэтому их можно проверить headless-тестом без машины и без физики.
##
## Почему так, а не тряской:
##  * высокочастотная тряска (10–20 Гц) читается как дрожь картинки и быстро
##    укачивает — ей не место в постоянной отдаче;
##  * скорость чувствуется заносом камеры в поворот, лёгким креном и
##    вертикальной инерцией: камера «плывёт» за машиной, а не дрожит;
##  * всё сглаживается экспонентой, поэтому кадр не дёргается даже при
##    просадках FPS и толчках физики.
##
## Как это устроено в других гонках (и почему здесь так): Forza/GT/DiRT дают
## скорость за счёт FOV-кривой, «догоняющей» камеры (лаг по дистанции),
## низкочастотного крена и мировых частиц. Тряску применяют точечно (удар,
## вылет), а не как постоянный фон — именно постоянная дрожь читается как баг.
## Поэтому здесь нет ни одного вызова randf()/шума: только физика и волны.
class_name RallySpeedSway
extends RefCounted

## Угловая скорость машины, которая считается «полной» для заноса камеры.
const YAW_REFERENCE_DEG := 90.0
## Боковая перегрузка, которая считается «полной» для заноса камеры, м/с².
const LATERAL_REFERENCE_MPS2 := 9.81


## Насколько текущая скорость «набегает»: 0 — эффект спит, 1 — максимум.
## Скорость ниже порога даёт ровно 0, чтобы на стоянке камера стояла.
static func speed_weight(speed_kmh: float, start_kmh: float, full_kmh: float) -> float:
	if not is_finite(speed_kmh) or not is_finite(start_kmh) or not is_finite(full_kmh):
		return 0.0
	if full_kmh <= start_kmh:
		return 1.0 if speed_kmh >= start_kmh else 0.0
	return clampf((speed_kmh - start_kmh) / (full_kmh - start_kmh), 0.0, 1.0)


## Занос камеры в поворот, радианы.
##
## `yaw_rate_deg` — угловая скорость машины вокруг вертикали, °/с
## (плюс — поворот влево). `lateral_mps2` — боковое ускорение в системе
## машины, м/с² (плюс — влево). `share` — какая доля приходится на угловую
## скорость, остальное берёт перегрузка. `invert` разворачивает направление:
## камера уходит наружу поворота, а не в его апекс.
static func corner_lean(yaw_rate_deg: float, lateral_mps2: float, share: float = 0.55,
		invert: bool = false) -> float:
	if not is_finite(yaw_rate_deg) or not is_finite(lateral_mps2):
		return 0.0
	var yaw_term: float = yaw_rate_deg / YAW_REFERENCE_DEG
	var lateral_term: float = lateral_mps2 / LATERAL_REFERENCE_MPS2
	var blend: float = clampf(share, 0.0, 1.0)
	var lean: float = clampf(yaw_term * blend + lateral_term * (1.0 - blend), -1.0, 1.0)
	return -lean if invert else lean


## Угол заноса, радианы: `lean` (-1..1) × предел × сила скорости.
static func lean_angle(lean: float, max_deg: float, amount: float) -> float:
	if not is_finite(lean) or not is_finite(amount):
		return 0.0
	return clampf(lean, -1.0, 1.0) * clampf(amount, 0.0, 1.0) * deg_to_rad(maxf(max_deg, 0.0))


## Кривая раскрытия FOV по скорости.
##
## `ease` смешивает линейный рост с плавным S-профилем: до ~60 км/ч кадр
## остаётся спокойным, а к максимуму FOV раскрывается быстрее. Так скорость
## чувствуется на трассе, но не «зумит» на каждой парковке.
static func speed_fov_factor(speed_kmh: float, reference_kmh: float, ease: float = 0.0) -> float:
	var linear: float = speed_weight(speed_kmh, 0.0, maxf(reference_kmh, 1.0))
	if ease <= 0.0:
		return linear
	var smooth: float = linear * linear * (3.0 - 2.0 * linear)
	return lerpf(linear, smooth, clampf(ease, 0.0, 1.0))


## Медленное «дыхание» камеры на скорости: один период, метры.
## Частота ограничена снизу, чтобы фаза не бежала рывками на больших delta.
static func float_bob(time_s: float, frequency_hz: float, amplitude: float) -> float:
	if not is_finite(time_s) or not is_finite(frequency_hz) or not is_finite(amplitude):
		return 0.0
	var hz: float = clampf(frequency_hz, 0.01, 20.0)
	return sin(time_s * hz * TAU) * maxf(amplitude, 0.0)


## Вертикальная реакция камеры на ускорение кузова (камера — мягкая масса).
## Возвращает смещение вверх, метры. Ограничена, чтобы удар не подбрасывал кадр.
static func vertical_inertia(vertical_accel: float, gain: float, limit: float) -> float:
	if not is_finite(vertical_accel) or not is_finite(gain):
		return 0.0
	var raw: float = vertical_accel * gain
	var cap: float = maxf(limit, 0.0)
	return clampf(raw, -cap, cap)


## Постоянная времени сглаживания, как в Godot: 1 - exp(-k·dt).
## Никогда не даёт 0 или 1, поэтому камера не «щёлкает» на смене кадра.
static func response_weight(response: float, delta: float) -> float:
	if not is_finite(response) or not is_finite(delta):
		return 0.0
	return 1.0 - exp(-maxf(response, 0.0) * maxf(delta, 0.0))
