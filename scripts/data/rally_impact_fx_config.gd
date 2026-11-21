## Эффекты столкновения: тряска камеры, искры, обломки, пыль, звук и вибрация.
##
## Ресурс res://data/car/default_impact_fx.tres — правится в инспекторе:
## либо у корня RallyCar в сцене машины (поле `impact_fx_config`), либо прямо в
## файле ресурса (FileSystem → data/car/). Поля сгруппированы по эффектам,
## у каждого эффекта свой выключатель.
##
## Слой косметический: на здоровье, урон, очки и физику машины не влияет.
@tool
class_name RallyImpactFxConfig
extends Resource

@export_group("Включение")
## Главный выключатель всех эффектов удара.
@export var enabled: bool = true
## Машины, на которых эффекты работают (vehicle_id). Пусто — на всех.
@export var vehicle_ids: Array[String] = []
## С какой потери скорости за кадр удар вообще даёт эффекты, м/с.
@export_range(0.3, 10.0, 0.1, "suffix:м/с") var min_dv_mps: float = 1.6
## Потеря скорости, при которой эффекты выходят на полную силу, м/с.
@export_range(2.0, 40.0, 0.5, "suffix:м/с") var full_dv_mps: float = 16.0
## Пауза между вспышками эффектов удара, с.
@export_range(0.02, 1.0, 0.01, "suffix:с") var cooldown_sec: float = 0.12
## Скольжение вдоль препятствия: с какой скорости появляются искры и скрежет, м/с.
@export_range(0.5, 20.0, 0.5, "suffix:м/с") var scrape_min_speed_mps: float = 3.0
## Скорость скольжения, при которой искры и скрежет на максимуме, м/с.
@export_range(2.0, 60.0, 0.5, "suffix:м/с") var scrape_full_speed_mps: float = 22.0

@export_group("Камера")
## Тряска камеры от удара.
@export var shake_enabled: bool = true
## Сколько «встряски» (0..1) добавляет каждый м/с удара.
@export_range(0.0, 0.3, 0.005) var shake_trauma_per_dv: float = 0.075
## Как быстро встряска гаснет, в секунду.
@export_range(0.2, 8.0, 0.05) var shake_decay: float = 1.6
## Наибольшее смещение камеры, м.
@export_range(0.0, 1.0, 0.01, "suffix:м") var shake_offset_m: float = 0.22
## Наибольший поворот камеры, градусы.
@export_range(0.0, 15.0, 0.1, "suffix:°") var shake_angle_deg: float = 3.2
## Частота дрожи, Гц.
@export_range(1.0, 60.0, 0.5, "suffix:Гц") var shake_frequency_hz: float = 22.0
## Сила тряски в виде из кабины и с капота (камера и так сидит в кузове).
@export_range(0.0, 2.0, 0.05) var inside_shake_scale: float = 0.7
## Рывок камеры в сторону удара, м на полную силу удара.
@export_range(0.0, 2.0, 0.01, "suffix:м") var kick_m: float = 0.45
## Как быстро камера возвращается после рывка, в секунду.
@export_range(0.5, 30.0, 0.5) var kick_return: float = 7.0
## Короткий «удар» угла обзора на полную силу удара, градусы.
@export_range(0.0, 20.0, 0.5, "suffix:°") var fov_punch_deg: float = 6.0
## Лёгкая дрожь камеры при скольжении вдоль забора (доля полной тряски).
@export_range(0.0, 1.0, 0.01) var scrape_shake: float = 0.18

@export_group("Вибрация геймпада")
@export var rumble_enabled: bool = true
## Слабый и сильный мотор на полную силу удара (0..1).
@export_range(0.0, 1.0, 0.05) var rumble_weak: float = 0.55
@export_range(0.0, 1.0, 0.05) var rumble_strong: float = 1.0
## Длительность вибрации от удара, с.
@export_range(0.02, 1.5, 0.01, "suffix:с") var rumble_duration: float = 0.28
## Вибрация при скольжении вдоль забора (0..1).
@export_range(0.0, 1.0, 0.05) var rumble_scrape: float = 0.35

@export_group("Искры")
@export var sparks_enabled: bool = true
## Сколько искр в одной вспышке на полную силу удара.
@export_range(4, 512, 1) var sparks_amount: int = 90
## Сколько искр при самом слабом ударе (доля полной вспышки).
@export_range(0.0, 1.0, 0.05) var sparks_min_ratio: float = 0.2
## Время жизни искры, с.
@export_range(0.05, 3.0, 0.01, "suffix:с") var sparks_lifetime: float = 0.55
## Скорость вылета искр, м/с.
@export_range(0.0, 40.0, 0.5, "suffix:м/с") var sparks_speed_min: float = 3.5
@export_range(0.0, 60.0, 0.5, "suffix:м/с") var sparks_speed_max: float = 11.0
## Разлёт вокруг направления отскока, градусы.
@export_range(0.0, 180.0, 1.0, "suffix:°") var sparks_spread_deg: float = 60.0
## Доля земной тяжести для искр.
@export_range(0.0, 3.0, 0.05) var sparks_gravity: float = 1.0
## Размер искры: толщина и длина штриха, м.
@export var sparks_size: Vector2 = Vector2(0.018, 0.16)
## Цвет искры (раскалённый металл) и яркость свечения.
@export var sparks_color: Color = Color(1.0, 0.72, 0.32, 1)
@export_range(0.5, 16.0, 0.1) var sparks_energy: float = 4.0
## Искры при скольжении вдоль забора, штук в секунду на полной скорости.
@export_range(0.0, 600.0, 5.0) var scrape_sparks_per_sec: float = 220.0

@export_group("Обломки")
@export var debris_enabled: bool = true
## С какой силы удара отлетают куски пластика и краски, м/с.
@export_range(0.5, 30.0, 0.5, "suffix:м/с") var debris_min_dv_mps: float = 4.5
## Сколько кусков на полную силу удара.
@export_range(1, 128, 1) var debris_amount: int = 22
## Время жизни куска, с.
@export_range(0.1, 5.0, 0.05, "suffix:с") var debris_lifetime: float = 1.3
## Размер куска, м.
@export_range(0.005, 0.4, 0.005, "suffix:м") var debris_size_m: float = 0.06
## Скорость вылета кусков, м/с.
@export_range(0.0, 30.0, 0.5, "suffix:м/с") var debris_speed_min: float = 2.0
@export_range(0.0, 40.0, 0.5, "suffix:м/с") var debris_speed_max: float = 6.5
## Брать цвет кусков с краски кузова (иначе — цвет ниже).
@export var debris_use_paint_color: bool = true
@export var debris_color: Color = Color(0.55, 0.56, 0.6, 1)
## Осколки стекла и фар на сильном ударе.
@export var glass_enabled: bool = true
@export_range(1.0, 40.0, 0.5, "suffix:м/с") var glass_min_dv_mps: float = 9.0
@export_range(1, 128, 1) var glass_amount: int = 26
@export var glass_color: Color = Color(0.82, 0.92, 1.0, 0.85)

@export_group("Пыль удара")
@export var dust_enabled: bool = true
## Сколько клубов пыли и краски на полную силу удара.
@export_range(1, 64, 1) var dust_amount: int = 10
## Размер клуба, м, и время жизни, с.
@export_range(0.05, 3.0, 0.05, "suffix:м") var dust_size_m: float = 0.55
@export_range(0.1, 5.0, 0.05, "suffix:с") var dust_lifetime: float = 1.1
@export var dust_color: Color = Color(0.62, 0.58, 0.52, 0.55)

@export_group("Звук")
@export var sound_enabled: bool = true
## Свои звуки удара (выбирается случайный). Пусто — синтезированный хруст.
@export var impact_sounds: Array[AudioStream] = []
## Свои звуки сильного удара. Пусто — синтезированный тяжёлый удар.
@export var heavy_impact_sounds: Array[AudioStream] = []
## С какой силы удар звучит как тяжёлый, м/с.
@export_range(2.0, 40.0, 0.5, "suffix:м/с") var heavy_dv_mps: float = 9.0
## Громкость самого слабого и самого сильного удара, дБ.
@export_range(-40.0, 12.0, 0.5, "suffix:дБ") var impact_volume_min_db: float = -12.0
@export_range(-40.0, 12.0, 0.5, "suffix:дБ") var impact_volume_max_db: float = 3.0
## Случайный разброс высоты тона, доля.
@export_range(0.0, 0.5, 0.01) var pitch_jitter: float = 0.12
## Свой зацикленный звук скрежета. Пусто — синтезированный.
@export var scrape_sound: AudioStream = null
## Громкость скрежета на полной скорости, дБ.
@export_range(-40.0, 12.0, 0.5, "suffix:дБ") var scrape_volume_db: float = -5.0
## Дальность слышимости (unit_size AudioStreamPlayer3D).
@export_range(1.0, 50.0, 0.5) var sound_unit_size: float = 8.0

@export_group("Стоп-кадр")
## Короткое замедление времени на сильном ударе. Выключено по умолчанию:
## замедляет и физику, и таймер заезда.
@export var hitstop_enabled: bool = false
@export_range(1.0, 60.0, 0.5, "suffix:м/с") var hitstop_min_dv_mps: float = 14.0
@export_range(0.05, 1.0, 0.01) var hitstop_time_scale: float = 0.3
@export_range(0.01, 0.5, 0.01, "suffix:с") var hitstop_duration_sec: float = 0.07


## Работают ли эффекты на машине с этим id.
func applies_to(vehicle_id: String) -> bool:
	return enabled and (vehicle_ids.is_empty() or vehicle_ids.has(vehicle_id))


## Сила удара 0..1 по потере скорости.
func strength(dv: float) -> float:
	return clampf((dv - min_dv_mps) / maxf(full_dv_mps - min_dv_mps, 0.01), 0.0, 1.0)
