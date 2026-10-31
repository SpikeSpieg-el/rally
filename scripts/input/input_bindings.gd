## Персональные биндинги двух независимых устройств. Не меняет ui_accept/ui_cancel:
## меню остаётся управляемым, даже если пользователь очистил игровые действия.
extends RefCounted

signal changed

const DEFAULT_PATH := "user://rally_bindings.cfg"
const SLOTS := 2
const DEVICES := ["keyboard", "gamepad"]
const ACTIONS := [
	{"id":"throttle", "label":"Газ"},
	{"id":"brake", "label":"Тормоз"},
	{"id":"steer_left", "label":"Руль влево"},
	{"id":"steer_right", "label":"Руль вправо"},
	{"id":"handbrake", "label":"Ручник"},
	{"id":"clutch", "label":"Сцепление"},
	{"id":"shift_down", "label":"Передача вниз"},
	{"id":"shift_up", "label":"Передача вверх"},
	{"id":"camera_switch", "label":"Смена камеры"},
	{"id":"camera_recenter", "label":"Вернуть взгляд"},
	{"id":"camera_look_left", "label":"Взгляд влево"},
	{"id":"camera_look_right", "label":"Взгляд вправо"},
	{"id":"camera_look_up", "label":"Взгляд вверх"},
	{"id":"camera_look_down", "label":"Взгляд вниз"},
	{"id":"drivetrain_switch", "label":"Сменить привод"},
	{"id":"reset_car", "label":"Вернуть машину"},
	{"id":"pause", "label":"Пауза"},
]

var path: String = DEFAULT_PATH
var defaults: Dictionary = {}
var bindings: Dictionary = {}


func initialize() -> void:
	defaults.clear()
	for entry: Dictionary in ACTIONS:
		var action: String = entry.id
		defaults[action] = {"keyboard": [null, null], "gamepad": [null, null]}
		if not InputMap.has_action(action):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			var device := _device_for_event(event)
			if device.is_empty():
				continue
			var description: Variant = describe_event(event)
			if description == null:
				continue
			var slots: Array = defaults[action][device]
			var index := slots.find(null)
			if index >= 0:
				slots[index] = description
	bindings = defaults.duplicate(true)
	load_bindings()


## Храним только проверенные данные, не сериализованные объекты InputEvent.
static func describe_event(event: InputEvent) -> Variant:
	if event is InputEventKey:
		var key := event as InputEventKey
		var physical := int(key.physical_keycode)
		var code := physical if physical != 0 else int(key.keycode)
		if code <= 0 or code >= 0x02000000:
			return null
		return {"type": "key", "code": code, "physical": physical != 0}
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		if int(button.button_index) < 0 or int(button.button_index) >= JOY_BUTTON_MAX:
			return null
		return {"type": "button", "index": int(button.button_index)}
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if int(motion.axis) < 0 or int(motion.axis) >= JOY_AXIS_MAX or absf(motion.axis_value) < 0.01:
			return null
		return {"type": "axis", "index": int(motion.axis), "sign": 1 if motion.axis_value > 0.0 else -1}
	return null


static func _device_for_event(event: InputEvent) -> String:
	if event is InputEventKey:
		return "keyboard"
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return "gamepad"
	return ""


static func _validated(value: Variant, device: String) -> Variant:
	if not value is Dictionary:
		return null
	var data: Dictionary = value
	var type: Variant = data.get("type")
	if type == "key" and device == "keyboard":
		var code: Variant = data.get("code")
		var physical: Variant = data.get("physical")
		if code is int and physical is bool and code > 0 and code < 0x02000000:
			return {"type": "key", "code": code, "physical": physical}
	if type == "button" and device == "gamepad":
		var index: Variant = data.get("index")
		if index is int and index >= 0 and index < JOY_BUTTON_MAX:
			return {"type": "button", "index": index}
	if type == "axis" and device == "gamepad":
		var index: Variant = data.get("index")
		var axis_sign: Variant = data.get("sign")
		if index is int and index >= 0 and index < JOY_AXIS_MAX and axis_sign is int and axis_sign in [-1, 1]:
			return {"type": "axis", "index": index, "sign": axis_sign}
	return null


static func _to_event(data: Dictionary) -> InputEvent:
	match data.type:
		"key":
			var key := InputEventKey.new()
			if data.physical:
				key.physical_keycode = int(data.code) as Key
			else:
				key.keycode = int(data.code) as Key
			return key
		"button":
			var button := InputEventJoypadButton.new()
			button.device = -1
			button.button_index = int(data.index) as JoyButton
			return button
		"axis":
			var motion := InputEventJoypadMotion.new()
			motion.device = -1
			motion.axis = int(data.index) as JoyAxis
			motion.axis_value = float(data.sign)
			return motion
	return null


func _apply_action(action: String) -> void:
	if not InputMap.has_action(action) or not bindings.has(action):
		return
	# Любые незнакомые типы событий, например мышь из пользовательского проекта,
	# остаются нетронутыми. Настраиваются только клавиатура и геймпад.
	for event: InputEvent in InputMap.action_get_events(action):
		if not _device_for_event(event).is_empty():
			InputMap.action_erase_event(action, event)
	for device: String in DEVICES:
		for data in bindings[action][device]:
			if data is Dictionary:
				var event := _to_event(data)
				if event != null:
					InputMap.action_add_event(action, event)


func _apply_all() -> void:
	for entry: Dictionary in ACTIONS:
		_apply_action(String(entry.id))


func load_bindings() -> void:
	bindings = defaults.duplicate(true)
	var config := ConfigFile.new()
	if config.load(path) == OK:
		for device: String in DEVICES:
			for entry: Dictionary in ACTIONS:
				var action: String = entry.id
				if not config.has_section_key(device, action):
					continue
				var saved: Variant = config.get_value(device, action)
				if not saved is Array or saved.size() != SLOTS:
					continue
				var valid := true
				var decoded := []
				for raw in saved:
					var value: Variant = _validated(raw, device)
					if raw != null and value == null:
						valid = false
					decoded.append(value)
				if valid:
					bindings[action][device] = decoded
	# Повреждённая конфигурация с конфликтами не должна вызывать два действия
	# одновременно. Откатываем только проблемное устройство к заводской карте.
	for device: String in DEVICES:
		var used: Array = []
		var duplicate_found := false
		for entry: Dictionary in ACTIONS:
			for data in bindings[entry.id][device]:
				if data == null:
					continue
				if used.has(data):
					duplicate_found = true
				used.append(data)
		if duplicate_found:
			for entry: Dictionary in ACTIONS:
				bindings[entry.id][device] = defaults[entry.id][device].duplicate(true)
	_apply_all()
	changed.emit()


func _save() -> Error:
	var config := ConfigFile.new()
	for device: String in DEVICES:
		for entry: Dictionary in ACTIONS:
			config.set_value(device, String(entry.id), bindings[entry.id][device])
	return config.save(path)


func get_binding(action: String, device: String, slot: int) -> Variant:
	if not bindings.has(action) or device not in DEVICES or slot < 0 or slot >= SLOTS:
		return null
	var result: Variant = bindings[action][device][slot]
	return result.duplicate(true) if result is Dictionary else null


func bind(action: String, device: String, slot: int, event: InputEvent) -> Dictionary:
	if not bindings.has(action) or device not in DEVICES or slot < 0 or slot >= SLOTS:
		return {"ok": false, "message": "Неизвестное действие."}
	if event != null and _device_for_event(event) != device:
		return {"ok": false, "message": "Выберите устройство на этой вкладке."}
	var candidate: Variant = describe_event(event) if event != null else null
	if event != null and candidate == null:
		return {"ok": false, "message": "Эта кнопка или ось не поддерживается."}
	var before := bindings.duplicate(true)
	var old: Variant = bindings[action][device][slot]
	var swapped := ""
	# Одно действие на нажатие. При конфликте старые значения меняются местами,
	# поэтому пользователь не теряет управление неожиданно.
	if candidate != null:
		for entry: Dictionary in ACTIONS:
			var other: String = entry.id
			for other_slot in range(SLOTS):
				if other == action and other_slot == slot:
					continue
				if bindings[other][device][other_slot] == candidate:
					bindings[other][device][other_slot] = old
					swapped = String(entry.label)
	bindings[action][device][slot] = candidate
	var error := _save()
	if error != OK:
		bindings = before
		return {"ok": false, "message": "Не удалось сохранить: %s" % error_string(error)}
	_apply_all()
	changed.emit()
	return {"ok": true, "swapped": swapped}


func reset_device(device: String) -> bool:
	if device not in DEVICES:
		return false
	var before := bindings.duplicate(true)
	for entry: Dictionary in ACTIONS:
		bindings[entry.id][device] = defaults[entry.id][device].duplicate(true)
	var error := _save()
	if error != OK:
		bindings = before
		return false
	_apply_all()
	changed.emit()
	return true
