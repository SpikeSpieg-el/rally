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
## Кривая FOV по скорости: 0 — линейно, 1 — плавный S-профиль (спокойно
## на малой скорости, раскрытие ближе к максимуму). Рекомендуется 0.6–1.0.
@export_range(0.0, 1.0, 0.05) var fov_speed_ease: float = 0.75
## Прибавка дальности камеры на максимальной скорости (0.06 = +6%).
@export_range(0.0, 1.0, 0.01) var camera_speed_distance_gain: float = 0.06
## Скорость, на которой FOV/дистанция выходят на максимум, км/ч.
@export_range(20.0, 400.0, 1.0, "suffix:km/h") var speed_reference_kmh: float = 160.0
## Порог прироста FOV «в машине» по скорости, км/ч.
@export_range(20.0, 400.0, 1.0, "suffix:km/h") var inside_fov_speed_reference_kmh: float = 180.0

@export_group("Камера: ощущение скорости")
## Главный выключатель живой камеры. 0 — камера строго на маркере, но FOV
## по скорости остаётся: он не укачивает и не мешает читать трассу.
@export_range(0.0, 2.0, 0.05) var speed_feel_strength: float = 1.0
## Масштаб ощущения скорости для вида сзади поверх ползунка паузы.
@export_range(0.0, 2.0, 0.05) var chase_feel_scale: float = 1.0
## Масштаб ощущения скорости для кабины поверх `cockpit_motion_strength`.
@export_range(0.0, 2.0, 0.05) var cockpit_feel_scale: float = 1.0
## Скорость, с которой начинает работать занос камеры в поворот, км/ч.
@export_range(0.0, 200.0, 1.0, "suffix:км/ч") var corner_lean_start_kmh: float = 25.0
## Скорость полного заноса камеры, км/ч.
@export_range(10.0, 320.0, 1.0, "suffix:км/ч") var corner_lean_full_kmh: float = 130.0
## Предел заноса камеры в поворот, градусы. Это не тряска, а плавный крен.
@export_range(0.0, 8.0, 0.05, "suffix:°") var corner_lean_max_deg: float = 2.4
## Доля угловой скорости машины в заносе камеры; остальное — боковая перегрузка.
@export_range(0.0, 1.0, 0.01) var corner_lean_rate_share: float = 0.55
## Отклик сглаживания заноса, 1/с. Меньше — камера «плывёт» мягче.
@export_range(0.5, 30.0, 0.5) var corner_lean_response: float = 5.0
## Крен кузова в кадре при повороте, градусы при полном заносе.
@export_range(0.0, 8.0, 0.05, "suffix:°") var corner_roll_max_deg: float = 1.2
## Отклик сглаживания крена, 1/с.
@export_range(0.5, 30.0, 0.5) var corner_roll_response: float = 6.0
## Разворот заноса: 1 — камера уходит наружу поворота (как крен кузова).
@export_range(0.0, 1.0, 1.0) var corner_lean_invert: float = 1.0
## Как камера «отстаёт» по дистанции при разгоне и «набегает» при торможении.
## Доля дистанции на один g продольной перегрузки.
@export_range(0.0, 0.5, 0.005) var speed_pull_gain: float = 0.07
## Предел смещения камеры по продольной перегрузке, м.
@export_range(0.0, 3.0, 0.01, "suffix:м") var speed_pull_limit: float = 0.9
## Отклик сглаживания продольной перегрузки, 1/с.
@export_range(0.5, 30.0, 0.5) var speed_pull_response: float = 4.0
## Предел ускорения, чтобы удары физики не дёргали камеру, м/с².
@export_range(10.0, 160.0, 1.0, "suffix:м/с²") var speed_accel_limit: float = 60.0
## Отклик сглаживания перегрузок, 1/с.
@export_range(0.5, 30.0, 0.5) var speed_accel_response: float = 10.0
## Медленное «дыхание» камеры на скорости, м.
@export_range(0.0, 0.1, 0.001, "suffix:м") var high_speed_bob_amplitude: float = 0.012
## Частота «дыхания» камеры, Гц. Это плавная волна, а не дрожь.
@export_range(0.1, 6.0, 0.05, "suffix:Гц") var high_speed_bob_hz: float = 0.7
## Смещение головы/кабины от перегрузок, м на м/с² (X, Y, Z кузова).
## В кабине это не тряска, а плавное «вдавливание» в кресло.
@export var cockpit_g_force_gain: Vector3 = Vector3(0.006, 0.002, 0.0045)
## Пределы смещения кабины от перегрузок, м.
@export var cockpit_g_force_limit: Vector3 = Vector3(0.12, 0.05, 0.16)
## Вертикальная реакция камеры на толчки кузова, м на м/с².
@export_range(0.0, 0.05, 0.001) var vertical_inertia_gain: float = 0.006
## Предел вертикальной реакции камеры, м.
@export_range(0.0, 0.3, 0.005, "suffix:м") var vertical_inertia_limit: float = 0.05
## Шероховатость покрытий для слабой вертикальной волны пути (геймпад).
@export_range(0.0, 2.0, 0.05) var surface_roughness_asphalt: float = 0.15
@export_range(0.0, 2.0, 0.05) var surface_roughness_dirt: float = 0.7
@export_range(0.0, 2.0, 0.05) var surface_roughness_grass: float = 1.0

@export_group("Камера: придорожный поток")
## Включать частицы скорости на обочине (мусор/пыльца/снег) у вида сзади.
@export var speed_motes_enabled: bool = true
## Сколько частиц в потоке.
@export_range(0, 600, 4) var speed_motes_amount: int = 160
## Как далеко от камеры рождать поток, м.
@export_range(2.0, 40.0, 0.5, "suffix:м") var speed_motes_length: float = 14.0
## Ширина потока по бокам от оси дороги, м.
@export_range(0.5, 20.0, 0.5, "suffix:м") var speed_motes_width: float = 9.0
## Высота потока над землёй, м.
@export_range(0.0, 7.0, 0.1, "suffix:м") var speed_motes_height: float = 2.6
## Размер частицы, м.
@export_range(0.01, 0.5, 0.005, "suffix:м") var speed_motes_size: float = 0.075
## Скорость, с которой поток начинает появляться, км/ч.
@export_range(0.0, 200.0, 1.0, "suffix:км/ч") var speed_motes_start_kmh: float = 30.0
## Скорость полной плотности потока, км/ч.
@export_range(20.0, 320.0, 1.0, "suffix:км/ч") var speed_motes_full_kmh: float = 120.0
## Цвет частиц потока.
@export var speed_motes_color: Color = Color(0.80, 0.84, 0.90, 0.55)
## Сколько секунд живёт частица, с.
@export_range(0.2, 4.0, 0.05, "suffix:с") var speed_motes_lifetime: float = 1.1
## Насколько поток тянется вдоль скорости машины (0 — висит на месте).
@export_range(0.0, 2.0, 0.05) var speed_motes_velocity_stretch: float = 0.85

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
