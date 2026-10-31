## Единая схема гаража: подписи, ограничения и сохранение одного пресета.
## Значения из старых/повреждённых конфигов никогда не попадают напрямую в физику.
extends RefCounted

const GROUPS := [
	{"id": "appearance", "title": "ВНЕШНОСТЬ", "note": "Ливрея, краска и колёса сразу видны на витрине. Цвет и яркость фар проявятся на трассе."},
	{"id": "engine", "title": "МОТОР", "note": "Характер момента и передаточные числа меняют разгон, а не только подписи в меню."},
	{"id": "drivetrain", "title": "ПРИВОД", "note": "Выберите коробку перед заездом. В режиме с педалью переключайте передачи с выжатым сцеплением."},
	{"id": "suspension", "title": "ПОДВЕСКА", "note": "Передняя и задняя оси настраиваются отдельно. Более жёсткий стабилизатор уменьшает крен."},
	{"id": "tires", "title": "ШИНЫ", "note": "Размер колёс влияет и на модель, и на физику. Настройки тормозов действуют на обе оси."},
]

# kind: color, choice, toggle, number. Границы используются и UI, и загрузкой.
const FIELDS := [
	{"group":"appearance", "key":"livery", "label":"Ливрея", "kind":"choice", "options":["Ралли · красная", "Itasha · неон", "Itasha · зелёная"], "tip":"Три штатные раскраски модели. Тон кузова накладывается поверх выбранной ливреи."},
	{"group":"appearance", "key":"body_color", "label":"Тон кузова и ливреи", "kind":"color", "tip":"Цвет умножается на общую текстуру кузова, включая детали ливреи."},
	{"group":"appearance", "key":"paint_finish", "label":"Покрытие", "kind":"choice", "options":["Заводское", "Глянец", "Матовый", "Металлик"], "tip":"Меняет свойства материала кузова; эффект зависит от освещения и рендерера."},
	{"group":"appearance", "key":"wheel_color", "label":"Тон колёс", "kind":"color", "tip":"Окрашивается вся общая текстура колеса, не только диск."},
	{"group":"appearance", "key":"headlight_color", "label":"Цвет света фар", "kind":"color", "tip":"Цвет пучка фар в заезде."},
	{"group":"appearance", "key":"headlight_energy", "label":"Яркость фар", "kind":"number", "min":0.0, "max":12.0, "step":0.25, "unit":"×", "tip":"Яркость освещения дороги фарами в заезде."},

	{"group":"engine", "key":"max_torque", "node":"Torque", "label":"Пиковый момент", "kind":"number", "min":100.0, "max":900.0, "step":5.0, "unit":"Н·м", "tip":"Максимальный крутящий момент двигателя."},
	{"group":"engine", "key":"max_rpm", "label":"Отсечка", "kind":"number", "min":3000.0, "max":10000.0, "step":100.0, "unit":"об/мин", "tip":"Максимальные обороты двигателя."},
	{"group":"engine", "key":"idle_rpm", "label":"Холостой ход", "kind":"number", "min":500.0, "max":2000.0, "step":50.0, "unit":"об/мин", "tip":"Обороты двигателя на холостом ходу."},
	{"group":"engine", "key":"torque_shape", "label":"Кривая момента", "kind":"choice", "options":["Базовая / пресета", "Турбо-полка", "Атмо-линейка", "Высокие обороты"], "tip":"Меняет распределение реального момента по оборотам. Базовая возвращает кривую исходного пресета."},
	{"group":"engine", "key":"engine_brake_scale", "label":"Торможение двигателем", "kind":"number", "min":0.2, "max":3.0, "step":0.05, "unit":"×", "tip":"Насколько сильно автомобиль замедляется при сбросе газа."},
	{"group":"engine", "key":"turbo", "label":"Звук турбины", "kind":"toggle", "tip":"Включает звуки сброса турбины и хлопков. Мощность настраивается отдельно."},
	{"group":"engine", "key":"final_drive", "node":"FinalDrive", "label":"Главная пара", "kind":"number", "min":1.0, "max":8.0, "step":0.05, "unit":"", "tip":"Большее число даёт более короткие передачи."},
	{"group":"engine", "key":"gear_1", "label":"1-я передача", "kind":"gear", "gear":0, "min":0.3, "max":5.0, "step":0.01, "unit":"", "tip":"Передачи должны идти по убыванию."},
	{"group":"engine", "key":"gear_2", "label":"2-я передача", "kind":"gear", "gear":1, "min":0.3, "max":5.0, "step":0.01, "unit":"", "tip":"Передачи должны идти по убыванию."},
	{"group":"engine", "key":"gear_3", "label":"3-я передача", "kind":"gear", "gear":2, "min":0.3, "max":5.0, "step":0.01, "unit":"", "tip":"Передачи должны идти по убыванию."},
	{"group":"engine", "key":"gear_4", "label":"4-я передача", "kind":"gear", "gear":3, "min":0.3, "max":5.0, "step":0.01, "unit":"", "tip":"Передачи должны идти по убыванию."},
	{"group":"engine", "key":"gear_5", "label":"5-я передача", "kind":"gear", "gear":4, "min":0.3, "max":5.0, "step":0.01, "unit":"", "tip":"Передачи должны идти по убыванию."},
	{"group":"engine", "key":"gear_6", "label":"6-я передача", "kind":"gear", "gear":5, "min":0.3, "max":5.0, "step":0.01, "unit":"", "tip":"Передачи должны идти по убыванию."},

	{"group":"drivetrain", "key":"transmission_mode", "label":"Коробка передач", "kind":"choice", "options":["Автомат", "Ручная", "Ручная + сцепление"], "tip":"Автомат: передачи вперёд переключаются сами. Ручная: Q/E. С педалью: выжмите сцепление перед переключением."},
	{"group":"drivetrain", "key":"drivetrain", "label":"Тип привода", "kind":"choice", "options":["AWD · полный", "RWD · задний", "FWD · передний"], "tip":"Выбирает ведущие оси машины."},
	{"group":"drivetrain", "key":"awd_front_torque", "label":"Момент на переднюю ось", "kind":"number", "min":0.0, "max":1.0, "step":0.01, "unit":"%", "display_scale":100.0, "tip":"Распределение тяги между осями в режиме AWD."},
	{"group":"drivetrain", "key":"traction_control_max_slip", "label":"Антипробуксовка", "kind":"number", "min":0.0, "max":4.0, "step":0.05, "unit":"", "tip":"Допустимое проскальзывание; 0 отключает систему."},
	{"group":"drivetrain", "key":"vehicle_mass", "label":"Масса", "kind":"number", "min":700.0, "max":2200.0, "step":1.0, "unit":"кг", "tip":"Масса автомобиля в физической модели."},
	{"group":"drivetrain", "key":"front_weight_distribution", "label":"Развесовка на переднюю ось", "kind":"number", "min":0.35, "max":0.70, "step":0.01, "unit":"%", "display_scale":100.0, "tip":"Доля массы на передней оси."},
	{"group":"drivetrain", "key":"center_of_gravity_height_offset", "label":"Высота центра масс", "kind":"number", "min":-0.30, "max":0.30, "step":0.01, "unit":"м", "tip":"Смещение центра тяжести относительно базового положения."},

	{"group":"suspension", "key":"front_spring_length", "label":"Ход спереди", "kind":"number", "min":0.10, "max":0.60, "step":0.005, "unit":"м", "tip":"Длина хода передней подвески."},
	{"group":"suspension", "key":"rear_spring_length", "label":"Ход сзади", "kind":"number", "min":0.10, "max":0.60, "step":0.005, "unit":"м", "tip":"Длина хода задней подвески."},
	{"group":"suspension", "key":"front_resting_ratio", "label":"Преднатяг спереди", "kind":"number", "min":0.30, "max":0.80, "step":0.01, "unit":"%", "display_scale":100.0, "tip":"Отношение статического сжатия передних пружин."},
	{"group":"suspension", "key":"rear_resting_ratio", "label":"Преднатяг сзади", "kind":"number", "min":0.30, "max":0.80, "step":0.01, "unit":"%", "display_scale":100.0, "tip":"Отношение статического сжатия задних пружин."},
	{"group":"suspension", "key":"front_damping_ratio", "label":"Амортизаторы спереди", "kind":"number", "min":0.10, "max":1.20, "step":0.01, "unit":"", "tip":"Демпфирование передней оси."},
	{"group":"suspension", "key":"rear_damping_ratio", "label":"Амортизаторы сзади", "kind":"number", "min":0.10, "max":1.20, "step":0.01, "unit":"", "tip":"Демпфирование задней оси."},
	{"group":"suspension", "key":"front_arb_ratio", "label":"Стабилизатор спереди", "kind":"number", "min":0.0, "max":0.80, "step":0.01, "unit":"", "tip":"Жёсткость переднего стабилизатора поперечной устойчивости."},
	{"group":"suspension", "key":"rear_arb_ratio", "label":"Стабилизатор сзади", "kind":"number", "min":0.0, "max":0.80, "step":0.01, "unit":"", "tip":"Жёсткость заднего стабилизатора поперечной устойчивости."},
	{"group":"suspension", "key":"bump_damp_multiplier", "label":"Демпфирование сжатия", "kind":"number", "min":0.2, "max":2.5, "step":0.01, "unit":"×", "tip":"Общий множитель сопротивления сжатию амортизаторов."},
	{"group":"suspension", "key":"rebound_damp_multiplier", "label":"Демпфирование отбоя", "kind":"number", "min":0.2, "max":2.5, "step":0.05, "unit":"×", "tip":"Общий множитель сопротивления отбою амортизаторов."},

	{"group":"tires", "key":"tire_radius", "node":"TireRadius", "label":"Радиус колеса", "kind":"number", "min":0.20, "max":0.65, "step":0.001, "unit":"м", "tip":"Физический радиус колеса и масштаб модели."},
	{"group":"tires", "key":"tire_width", "label":"Ширина шины", "kind":"number", "min":100.0, "max":400.0, "step":5.0, "unit":"мм", "tip":"Физическая ширина шины и ширина модели колеса."},
	{"group":"tires", "key":"grip_scale", "label":"Сцепление", "kind":"number", "min":0.3, "max":2.5, "step":0.01, "unit":"×", "tip":"Множитель сцепления на всех покрытиях."},
	{"group":"tires", "key":"tire_stiffness_scale", "label":"Жёсткость шин", "kind":"number", "min":0.3, "max":2.5, "step":0.01, "unit":"×", "tip":"Влияет на отклик шины при проскальзывании."},
	{"group":"tires", "key":"rolling_resistance_scale", "label":"Сопротивление качению", "kind":"number", "min":0.3, "max":3.0, "step":0.05, "unit":"×", "tip":"Множитель сопротивления качению на всех покрытиях."},
	{"group":"tires", "key":"max_steering_angle_deg", "label":"Угол поворота колёс", "kind":"number", "min":10.0, "max":50.0, "step":0.5, "unit":"°", "tip":"Максимальный угол передних колёс."},
	{"group":"tires", "key":"brake_force_multiplier", "label":"Сила тормозов", "kind":"number", "min":0.4, "max":1.6, "step":0.05, "unit":"×", "tip":"Общий множитель тормозного усилия."},
	{"group":"tires", "key":"front_brake_bias", "label":"Баланс тормозов спереди", "kind":"number", "min":0.30, "max":0.80, "step":0.01, "unit":"%", "display_scale":100.0, "tip":"Доля тормозного усилия на передней оси."},
]


static func sanitize_value(field: Dictionary, value: Variant, fallback: Variant) -> Variant:
	match field["kind"]:
		"number":
			if not (value is float or value is int) or not is_finite(float(value)):
				return fallback
			return clampf(float(value), float(field["min"]), float(field["max"]))
		"choice":
			if not value is int:
				return fallback
			return clampi(int(value), 0, field["options"].size() - 1)
		"toggle":
			return value if value is bool else fallback
		"color":
			if not value is Color:
				return fallback
			var color: Color = value
			if not (is_finite(color.r) and is_finite(color.g) and is_finite(color.b)):
				return fallback
			return Color(clampf(color.r, 0.0, 1.0), clampf(color.g, 0.0, 1.0), clampf(color.b, 0.0, 1.0), 1.0)
	return fallback


static func valid_gears(value: Variant, fallback: Array[float]) -> Array[float]:
	var result: Array[float] = []
	if not (value is Array or value is PackedFloat32Array or value is PackedFloat64Array):
		return fallback.duplicate()
	if value.size() != fallback.size() or value.is_empty():
		return fallback.duplicate()
	var previous := 5.01
	for raw in value:
		if not (raw is float or raw is int) or not is_finite(float(raw)):
			return fallback.duplicate()
		var ratio := float(raw)
		# Шаг ползунка — 0.01; меньший зазор сделал бы соседние
		# ограничения UI противоречивыми. Допуск учитывает float32.
		if ratio < 0.3 or ratio > 5.0 or previous - ratio < 0.00999:
			return fallback.duplicate()
		result.append(ratio)
		previous = ratio
	return result


static func read_setup(cfg: ConfigFile, section: String, setup: RallyCarSetup, base: RallyCarSetup) -> void:
	for field: Dictionary in FIELDS:
		if field["kind"] == "gear":
			continue
		var key: String = field["key"]
		var value: Variant = cfg.get_value(section, key, base.get(key))
		setup.set(key, sanitize_value(field, value, base.get(key)))
	setup.gear_ratios = valid_gears(cfg.get_value(section, "gear_ratios", base.gear_ratios), base.gear_ratios)
	setup.idle_rpm = minf(setup.idle_rpm, setup.max_rpm * 0.6)
	# Непустая Curve имеет приоритет в RallyCar. Явный выбор формы снимает её,
	# но нетронутая авторская кривая пресета переживает сохранение и загрузку.
	var keep_curve: Variant = cfg.get_value(section, "use_preset_torque_curve", true)
	if keep_curve is bool and not keep_curve:
		setup.torque_curve = null


static func normalized_setup(setup: RallyCarSetup, base: RallyCarSetup) -> RallyCarSetup:
	var result := setup.duplicate(true) as RallyCarSetup
	for field: Dictionary in FIELDS:
		if field["kind"] == "gear":
			continue
		var key: String = field["key"]
		result.set(key, sanitize_value(field, setup.get(key), base.get(key)))
	result.gear_ratios = valid_gears(setup.gear_ratios, base.gear_ratios)
	result.idle_rpm = minf(result.idle_rpm, result.max_rpm * 0.6)
	return result


static func write_setup(cfg: ConfigFile, section: String, setup: RallyCarSetup) -> void:
	for field: Dictionary in FIELDS:
		if field["kind"] != "gear":
			var key: String = field["key"]
			cfg.set_value(section, key, setup.get(key))
	cfg.set_value(section, "gear_ratios", setup.gear_ratios)
	cfg.set_value(section, "use_preset_torque_curve", setup.torque_curve != null)
