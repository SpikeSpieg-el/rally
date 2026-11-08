## Спавны и разметка заезда: старт/финиш, столбики обочины, арки КПП,
## знаки поворотов, точка появления и «спасение» машины.
##
## ЭТО ПУЛЬТ РАССТАНОВКИ. Значения читаются при сборке мира. Шаблон лежит в
## res://data/stage/default_spawn_layout.tres (правится в инспекторе), сцену
## можно переопределить полем `spawn_layout` у корня RallyStage.
##
## Здесь же расстояния контрольных точек: если нужно поставить арки руками,
## заполните `custom_checkpoint_distances` (метры от старта) — генератор по
## интервалу тогда не используется.
@tool
class_name RallySpawnLayout
extends Resource

@export_group("Старт и финиш")
## Ставить ворота старта (синие) и финиша (оранжевые).
@export var spawn_route_markers: bool = true
## Смещение машины и ворот старта от начала кривой, м.
@export_range(0.0, 200.0, 0.5) var start_distance: float = 14.0
## Насколько отступить от конца кривой для финиша, м (0 — самый конец).
@export_range(0.0, 200.0, 0.5) var finish_margin: float = 0.0
## Размер стойки ворот, м (x, y, z).
@export var gate_post_size: Vector3 = Vector3(0.18, 3.2, 0.18)
## Высота перекладины и её толщина, м.
@export_range(0.5, 10.0, 0.1) var gate_bar_height: float = 3.2
@export_range(0.05, 1.0, 0.01) var gate_bar_thickness: float = 0.18
## Насколько перекладина шире полотна (в каждую сторону), м.
@export_range(0.0, 5.0, 0.1) var gate_width_extra: float = 1.0
## Насколько стойки вынесены за кромку полотна, м.
@export_range(0.0, 3.0, 0.05) var gate_post_lateral: float = 0.35
@export var start_gate_color: Color = Color(0.20, 0.80, 1.00)
@export var finish_gate_color: Color = Color(1.00, 0.48, 0.08)
## Свечение ворот: цвет × множитель, и общая энергия emission.
@export_range(0.0, 2.0, 0.05) var gate_emission_energy: float = 0.5
@export_range(0.0, 4.0, 0.05) var gate_emission_multiplier: float = 0.35

@export_group("Столбики обочины")
## Красно-белые столбики по обочинам.
@export var edge_posts: bool = true
## Расстояние между столбиками, м.
@export_range(4.0, 120.0, 1.0) var edge_post_spacing: float = 26.0
## Отступ от начала и конца трассы, м.
@export_range(0.0, 100.0, 1.0) var edge_post_start: float = 14.0
@export_range(0.0, 100.0, 1.0) var edge_post_end: float = 8.0
## Насколько столбик вынесен за коридор «полотно + обочина», м.
@export_range(0.0, 10.0, 0.1) var edge_post_lateral: float = 1.8
## Размер самого столбика и белой «шапки», м.
@export var edge_post_size: Vector3 = Vector3(0.12, 1.0, 0.12)
@export var edge_post_cap_size: Vector3 = Vector3(0.13, 0.16, 0.13)
@export_range(0.0, 2.0, 0.01) var edge_post_cap_height: float = 0.85
@export_range(0.0, 1.0, 0.01) var edge_post_roughness: float = 0.85
@export var edge_post_cap_color: Color = Color(0.92, 0.92, 0.88)

@export_group("Контрольные арки")
@export var checkpoints: bool = true
## Свои расстояния КПП от старта, м. Пустой массив — брать интервал из трассы.
@export var custom_checkpoint_distances: PackedFloat32Array = PackedFloat32Array()
## Отступ от конца трассы, ближе которого арки не ставятся, м.
@export_range(0.0, 200.0, 1.0) var checkpoint_end_margin: float = 40.0
## Размер стойки арки, м.
@export var checkpoint_post_size: Vector3 = Vector3(0.16, 3.0, 0.16)
## Высота и толщина перекладины арки, м.
@export_range(0.5, 10.0, 0.1) var checkpoint_bar_height: float = 3.0
@export_range(0.05, 1.0, 0.01) var checkpoint_bar_thickness: float = 0.22
@export_range(0.05, 1.0, 0.01) var checkpoint_bar_depth: float = 0.30
## Ширина перекладины сверх полотна, м.
@export_range(0.0, 5.0, 0.1) var checkpoint_width_extra: float = 1.0
@export_range(0.0, 3.0, 0.05) var checkpoint_post_lateral: float = 0.35
@export var checkpoint_color: Color = Color(0.95, 0.85, 0.20)
@export_range(0.0, 2.0, 0.05) var checkpoint_emission_energy: float = 0.5
@export_range(0.0, 1.0, 0.01) var checkpoint_emission_strength: float = 0.35

@export_group("Знаки поворотов")
## Ставить щиты на входе в крутые повороты.
@export var corner_signs: bool = true
## Порог «крутизны» поворота, градусы.
@export_range(10.0, 150.0, 1.0) var corner_turn_threshold_deg: float = 58.0
## Через сколько метров смотреть направление (радиус поворота), м.
@export_range(5.0, 200.0, 1.0) var corner_lookahead: float = 55.0
## Минимальное расстояние между знаками, м.
@export_range(10.0, 600.0, 5.0) var corner_sign_spacing: float = 110.0
## Отступы от начала и конца трассы, м.
@export_range(0.0, 300.0, 1.0) var corner_sign_start: float = 50.0
@export_range(0.0, 300.0, 1.0) var corner_sign_end: float = 90.0
## Насколько знак вынесен за коридор, м.
@export_range(0.0, 10.0, 0.1) var corner_sign_lateral: float = 2.6
## Масштаб знака и доворот по вкусу, градусы.
@export_range(0.1, 5.0, 0.05) var corner_sign_scale: float = 1.0
@export_range(-180.0, 180.0, 1.0) var corner_sign_yaw_offset: float = 0.0

@export_group("Оформление спецучастка")
## Ленты, тормозные таблички, оранжевые сетки, зрители, лагеря, ЛЭП,
## стартово-финишный городок, следы шин и пятна тумана (RallyStageDressing).
@export var stage_dressing: bool = true
## Не чаще, чем через столько метров, ставить зрительские «островки».
@export_range(150.0, 1500.0, 10.0) var spectator_spacing: float = 420.0
## Потолок зрительских точек на трассу.
@export_range(1, 40, 1) var spectator_max_spots: int = 10
## Зрителей в одном лагере (плюс два фотографа у кромки).
@export_range(3, 16, 1) var spectator_crowd_size: int = 8
## Ставить вертолёт с прожектором над серединой трассы.
@export var helicopter: bool = true

@export_group("Болельщики на бровке")
## Расставлять одиночных фанатов по обочинам всей трассы.
@export var roadside_fans: bool = true
## Средний шаг вдоль оси, м. Меньше — чаще люди.
@export_range(8.0, 80.0, 1.0, "suffix:м") var roadside_fan_spacing: float = 26.0
## Потолок одиночных болельщиков на трассу.
@export_range(0, 200, 1) var roadside_fan_max: int = 90
## Отступ от старта и финиша, м.
@export_range(0.0, 300.0, 1.0, "suffix:м") var roadside_fan_start_margin: float = 70.0
@export_range(0.0, 300.0, 1.0, "suffix:м") var roadside_fan_end_margin: float = 110.0
## Шанс поставить человека в слоте (1 — в каждом шаге).
@export_range(0.0, 1.0, 0.01) var roadside_fan_keep_chance: float = 0.68
## Разброс шага: множитель min/max к roadside_fan_spacing.
@export var roadside_fan_spacing_scale: Vector2 = Vector2(0.72, 1.38)
## Шанс второго человека напротив, на другой стороне.
@export_range(0.0, 1.0, 0.01) var roadside_fan_both_sides_chance: float = 0.45
@export_range(0.0, 5.0, 0.05, "suffix:м") var roadside_fan_both_offset: float = 1.2
## Доля «храбрых», которые выходят навстречу машине.
@export_range(0.0, 1.0, 0.01) var roadside_fan_eager_chance: float = 0.42
## Доля тех, кто уже стоит на полотне у бровки.
@export_range(0.0, 1.0, 0.01) var roadside_fan_tarmac_chance: float = 0.14
## Смещение от кромки коридора, м: плюс — в поле, минус — на полотно.
@export var roadside_fan_inset: Vector2 = Vector2(0.45, 1.7)
@export var roadside_fan_eager_inset: Vector2 = Vector2(-0.55, 0.45)
@export var roadside_fan_tarmac_inset: Vector2 = Vector2(-1.35, -0.65)
@export var roadside_fan_other_inset: Vector2 = Vector2(0.55, 1.8)
@export var roadside_fan_other_eager_inset: Vector2 = Vector2(-0.45, 0.50)
@export_range(0.0, 1.0, 0.01) var roadside_fan_other_eager_chance: float = 0.38

@export_group("Металлический отбойник на крутых поворотах")
@export var guardrails: bool = true
## Модуль из библиотеки пропсов: длина вдоль локальной X — 3 м.
@export var guardrail_prop_id: String = "metal_guardrail"
## Отступ от кромки ПОЛОТНА (не от оси), м.
@export_range(1.0, 15.0, 0.1) var guardrail_offset: float = 3.0
## Шаг вдоль оси дороги. Секции растягиваются между соседними точками.
@export_range(0.5, 6.0, 0.25) var guardrail_step: float = 3.0
## Изменение направления в симметричном окне вокруг секции.
@export_range(20.0, 150.0, 1.0) var guardrail_turn_threshold_deg: float = 65.0
@export_range(10.0, 100.0, 1.0) var guardrail_lookahead: float = 40.0
@export_range(0.0, 100.0, 1.0) var guardrail_end_margin: float = 12.0
## Не ставить отбойник на обочину соседнего витка шпильки.
@export_range(0.0, 3.0, 0.1) var guardrail_road_clearance: float = 0.35
@export var guardrail_collisions: bool = true
@export_range(100.0, 1000.0, 10.0) var guardrail_visibility_range: float = 350.0

@export_group("Машина")
## Точка появления: расстояние от начала кривой, м (для F6/первого кадра).
@export_range(0.0, 200.0, 0.5) var car_spawn_distance: float = 14.0
## Дополнительная высота над полотном при появлении, м.
@export_range(0.0, 3.0, 0.01) var car_spawn_height_extra: float = 0.12
## Запас высоты при «спасении» машины клавишей R, м.
@export_range(0.0, 3.0, 0.01) var car_rescue_height_extra: float = 0.15
## Насколько близко к краям трассы разрешено «спасение», м.
@export_range(0.0, 100.0, 1.0) var car_rescue_margin: float = 8.0
## Насколько ниже земли должна оказаться машина, чтобы её вернули на дорогу, м.
@export_range(1.0, 300.0, 1.0) var car_fall_depth: float = 25.0


## Дистанции контрольных арок: свои из инспектора или автоматические по
## интервалу трассы. Возвращает метры от начала кривой.
func resolve_checkpoint_distances(length: float, track_interval: float, from_distance: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	if not checkpoints or length <= 0.0:
		return result
	var limit: float = maxf(from_distance, length - checkpoint_end_margin)
	if not custom_checkpoint_distances.is_empty():
		for value in custom_checkpoint_distances:
			if value > 0.0 and value < limit:
				result.append(value)
		result.sort()
		return result
	if track_interval <= 0.0:
		return result
	var distance: float = maxf(track_interval, from_distance + track_interval)
	while distance < limit:
		result.append(distance)
		distance += track_interval
	return result


## Дистанции столбиков обочины (шаг, отступы и концы — из инспектора).
func resolve_edge_post_distances(length: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	if not edge_posts or length <= 0.0:
		return result
	var limit: float = maxf(0.0, length - edge_post_end)
	var step: float = maxf(0.5, edge_post_spacing)
	var distance: float = maxf(0.0, edge_post_start)
	while distance < limit:
		result.append(distance)
		distance += step
	return result
