## Ощущение машины: сглаживание скорости, камера, привязка колёс к модели,
## отклик отклика руля/камеры.
##
## Раньше эти числа были константами в rally_car.gd. Теперь это ресурс,
## res://data/car/default_car_feel.tres — правится в инспекторе.
## Машина читает его при старте заезда; сцену можно переопределить
## полем `feel` у корня RallyCar.
@tool
class_name RallyCarFeelConfig
extends Resource

@export_group("Модель и клиренс")
## Центр колеса в импортированной модели, м (Y).
@export var model_wheel_center_y: float = 1.4588
## Просвет кузова над землёй в модели, м.
@export var model_body_ground_clearance: float = 0.063
## Дополнительный сдвиг модели по высоте, м.
@export var model_height_offset: float = 0.0

@export_group("Сглаживание")
## Отклик спидометра (скорость «догоняет» реальную), 1/с.
@export_range(1.0, 60.0, 0.5) var speed_response: float = 10.0
## Отклик обзора мышью, 1/с.
@export_range(1.0, 60.0, 0.5) var look_response: float = 18.0
## Отклик FOV в кабине/на капоте, 1/с.
@export_range(1.0, 60.0, 0.5) var inside_fov_response: float = 6.0
## Отклик FOV погони, 1/с.
@export_range(1.0, 60.0, 0.5) var chase_fov_response: float = 5.0
## Отклик смещения от перегрузок в кабине, 1/с.
@export_range(1.0, 60.0, 0.5) var cockpit_motion_response: float = 8.0
## Отклик наклона камеры по уклону, 1/с.
@export_range(1.0, 60.0, 0.5) var slope_response: float = 6.0
## Скорость втягивания камеры при столкновении и возврата, ед/с.
@export_range(1.0, 200.0, 1.0) var camera_pull_in_speed: float = 25.0
@export_range(1.0, 100.0, 1.0) var camera_push_out_speed: float = 8.0
## Ограничения камеры погони: минимальная дистанция и нижняя граница высоты.
@export_range(0.1, 20.0, 0.1) var camera_min_distance: float = 1.2
@export_range(0.0, 10.0, 0.05) var camera_pivot_clearance: float = 0.35
## Пределы наклона орбиты камеры (градусы).
@export_range(-89.0, 0.0, 1.0) var camera_pitch_min_deg: float = -10.0
@export_range(1.0, 89.0, 1.0) var camera_pitch_max_deg: float = 75.0
## Насколько камера учитывает наклон машины на горках (0–2).
@export_range(0.0, 2.0, 0.05) var slope_follow: float = 0.65
## Прибавка дальности камеры на максимальной скорости (0.06 = +6%).
@export_range(0.0, 1.0, 0.01) var camera_speed_distance_gain: float = 0.06
## Скорость, на которой FOV/дистанция выходят на максимум, км/ч.
@export_range(20.0, 400.0, 1.0, "suffix:km/h") var speed_reference_kmh: float = 160.0
## Порог прироста FOV «в машине» по скорости, км/ч.
@export_range(20.0, 400.0, 1.0, "suffix:km/h") var inside_fov_speed_reference_kmh: float = 180.0

@export_group("Камера: отдача дороги и инерция")
## Общая громкость живой камеры: дорожная тряска, кивки, крены и удары.
## 0 выключает отдачу, но не трогает FOV по скорости и спокойный вид от капота.
@export_range(0.0, 2.0, 0.05) var camera_juice_strength: float = 1.0
## Масштаб отдачи для вида сзади поверх ползунка/поля силы движения камеры.
@export_range(0.0, 2.0, 0.05) var chase_juice_scale: float = 1.0
## Масштаб отдачи для кабины поверх `cockpit_motion_strength`.
@export_range(0.0, 2.0, 0.05) var cockpit_juice_scale: float = 1.0
## Опорное ускорение для перегрузок, м/с² (обычно земное g).
@export_range(1.0, 20.0, 0.01, "suffix:м/с²") var juice_g_accel: float = 9.81
## Предел локального ускорения, чтобы удары физики не ломали камеру, м/с².
@export_range(10.0, 160.0, 1.0, "suffix:м/с²") var juice_accel_limit: float = 80.0
## Отклик сглаживания перегрузок камеры, 1/с.
@export_range(1.0, 60.0, 0.5) var juice_accel_response: float = 12.0
## Предел перегрузки в расчёте кивков/кренов, g.
@export_range(0.5, 8.0, 0.1, "suffix:g") var juice_g_limit: float = 3.0
## Кивок камеры при разгоне, градусов на g.
@export_range(0.0, 8.0, 0.05, "suffix:°/g") var accel_pitch_deg_per_g: float = 1.2
## Кивок камеры при торможении, градусов на g.
@export_range(0.0, 8.0, 0.05, "suffix:°/g") var brake_pitch_deg_per_g: float = 2.0
## Крен камеры в повороте от боковой перегрузки, градусов на g.
@export_range(0.0, 8.0, 0.05, "suffix:°/g") var corner_roll_deg_per_g: float = 1.5
## Общий предел кивка/крена от перегрузок, градусы.
@export_range(0.0, 15.0, 0.1, "suffix:°") var juice_rotation_limit_deg: float = 4.0
## Смещение головы/кабины от перегрузок, м на м/с² (X, Y, Z кузова).
@export var cockpit_g_force_gain: Vector3 = Vector3(0.006, 0.002, 0.0045)
## Пределы смещения кабины от перегрузок, м.
@export var cockpit_g_force_limit: Vector3 = Vector3(0.12, 0.05, 0.16)
## Скорость начала дорожной тряски, км/ч.
@export_range(0.0, 200.0, 1.0, "suffix:км/ч") var road_shake_start_kmh: float = 25.0
## Скорость полной дорожной тряски, км/ч.
@export_range(20.0, 320.0, 1.0, "suffix:км/ч") var road_shake_full_kmh: float = 140.0
## Амплитуда дорожной тряски по позиции, м.
@export_range(0.0, 0.1, 0.001, "suffix:м") var road_shake_amplitude: float = 0.018
## Амплитуда дорожной тряски по повороту, градусы.
@export_range(0.0, 3.0, 0.05, "suffix:°") var road_shake_rotation_deg: float = 0.45
## Частота дорожной тряски, Гц.
@export_range(1.0, 40.0, 0.5, "suffix:Гц") var road_shake_frequency: float = 12.0
## Шероховатость асфальта для камеры и геймпада.
@export_range(0.0, 2.0, 0.05) var surface_roughness_asphalt: float = 0.15
## Шероховатость гравия/грунта для камеры и геймпада.
@export_range(0.0, 2.0, 0.05) var surface_roughness_dirt: float = 0.7
## Шероховатость травы для камеры и геймпада.
@export_range(0.0, 2.0, 0.05) var surface_roughness_grass: float = 1.0
## Затухание ударной тряски (trauma), единиц в секунду.
@export_range(0.1, 8.0, 0.1) var trauma_decay: float = 2.2
## Амплитуда ударной тряски по позиции при trauma=1, м.
@export_range(0.0, 0.2, 0.005, "suffix:м") var trauma_amplitude: float = 0.045
## Амплитуда ударной тряски по повороту при trauma=1, градусы.
@export_range(0.0, 5.0, 0.05, "suffix:°") var trauma_rotation_deg: float = 1.8
## Частота ударной тряски, Гц.
@export_range(1.0, 40.0, 0.5, "suffix:Гц") var trauma_frequency: float = 17.0
## Разнос частот осей тряски (X, Y, Z), чтобы шум не был синхронным.
@export var shake_frequency_spread: Vector3 = Vector3(1.0, 1.37, 2.11)
## Фазовый сдвиг осей тряски (X, Y, Z).
@export var shake_phase_offset: Vector3 = Vector3(0.0, 1.7, 3.9)
## Ударная добавка при переключении передачи.
@export_range(0.0, 1.0, 0.01) var shift_trauma: float = 0.28
## Кивок камеры при переключении передачи, градусы.
@export_range(0.0, 5.0, 0.05, "suffix:°") var shift_pitch_deg: float = 0.9
## Краткая прибавка FOV при переключении передачи, градусы.
@export_range(0.0, 8.0, 0.1, "suffix:°") var shift_fov_kick: float = 1.5
## Скорость затухания кивка/FOV после переключения, 1/с.
@export_range(0.5, 20.0, 0.5) var shift_kick_decay: float = 5.0
## Минимальная вертикальная скорость приземления для удара, м/с.
@export_range(0.0, 15.0, 0.5, "suffix:м/с") var landing_min_mps: float = 2.0
## Добавка trauma за каждый м/с сверх порога приземления.
@export_range(0.0, 0.5, 0.01) var landing_trauma_per_mps: float = 0.07
## Порог резкого сжатия подвески для удара (доля хода).
@export_range(0.0, 1.0, 0.01) var suspension_impact_threshold: float = 0.55
## Добавка trauma при резком сжатии подвески.
@export_range(0.0, 1.0, 0.01) var suspension_impact_trauma: float = 0.20
## Порог резкого замедления для удара, м/с².
@export_range(5.0, 80.0, 1.0, "suffix:м/с²") var impact_decel_threshold: float = 25.0
## Добавка trauma за каждый м/с² сверх порога замедления.
@export_range(0.0, 0.1, 0.001) var impact_trauma_per_mps2: float = 0.008

@export_group("Обзор мышью и геймпадом")
## Скорость возврата взгляда к центру, 1/с.
@export_range(0.0, 30.0, 0.1) var mouse_return_speed: float = 4.5
## Насколько «свободный взгляд» смешивается с обычной точкой (0–1).
@export_range(0.0, 1.0, 0.01) var freelook_influence: float = 1.5
## Сдвиг точки фокуса при свободном взгляде, м.
@export_range(-5.0, 5.0, 0.05) var freelook_focus_min: float = -0.6
@export_range(-5.0, 5.0, 0.05) var freelook_focus_max: float = 1.5

@export_group("Положение машины")
## Порог скорости для «следования за скоростью» камерой, км/ч.
@export_range(0.0, 100.0, 0.5) var camera_velocity_follow_start_kmh: float = 15.0
@export_range(0.0, 300.0, 1.0) var camera_velocity_follow_full_kmh: float = 75.0
## Запасной порог падения, если сцена не передала провайдер, м.
@export_range(-500.0, 100.0, 1.0) var fall_limit_y: float = -20.0
