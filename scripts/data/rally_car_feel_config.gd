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
