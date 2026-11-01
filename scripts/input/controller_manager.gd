## Автозагрузка ControllerManager: единая точка работы с геймпадами.
##
## Godot приводит кнопки и оси всех поддерживаемых SDL-контроллеров к одной
## раскладке, поэтому одна и та же карта ввода работает для DualSense
## (DualShock 5), DualShock 4/3, Xbox, Switch Pro, Steam Deck и большинства
## USB/Bluetooth-геймпадов. Этот узел добавляет к раскладке всё, чего нет в
## обычных действиях: горячее подключение, определение модели и подсказки с
## правильными символами кнопок, вибрацию, подсветку DualSense/DualShock 4,
## мёртвые зоны и кривую руля.
extends Node

signal device_list_changed
signal active_device_changed(gamepad_active: bool)
signal settings_changed
signal bindings_changed

const BindingsScript = preload("res://scripts/input/input_bindings.gd")
const DrivingFeedback = preload("res://scripts/input/driving_feedback.gd")
const TRIGGER_BRIDGE_PATH := "res://tools/dualsense/trigger_bridge.py"

const SETTINGS_PATH := "user://rally_controller.cfg"
const SONY_VENDOR := 0x054C
const XBOX_VENDOR := 0x045E
const NINTENDO_VENDOR := 0x057E
const VALVE_VENDOR := 0x28DE
const GOOGLE_VENDOR := 0x18D1

const DUALSENSE_PRODUCTS := [0x0CE6, 0x0DF2]
const DUALSENSE_EDGE_PRODUCTS := [0x0DF2]

## Настройки, которые меняются в паузе и сохраняются в user://.
var vibration_enabled: bool = true
var vibration_strength: float = 0.85
var driving_vibration_enabled: bool = true
var adaptive_triggers_enabled: bool = true
var adaptive_trigger_strength: float = 0.7
var steering_deadzone: float = 0.12
var trigger_deadzone: float = 0.08
var steering_curve: float = 1.25
var trigger_curve: float = 1.0
var lightbar_enabled: bool = true
var lightbar_color: Color = Color(0.98, 0.45, 0.06, 1.0)

var gamepad_active: bool = false
var bindings: RefCounted = null

var _devices: Array[Dictionary] = []
var _settings_path: String = SETTINGS_PATH
var _bridge_pipe: FileAccess = null
var _bridge_pid: int = -1
var _bridge_status_path: String = ""
var _bridge_status: String = "недоступны"
var _bridge_generation: int = 0
var _bridge_check_msec: int = 0
var _feedback_last_msec: int = 0
var _feedback_sent_msec: int = 0
var _rumble_until_msec: int = 0
var _feedback_running: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	refresh_devices()
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_ensure_ui_bindings()
	bindings = BindingsScript.new()
	bindings.changed.connect(_on_bindings_changed)
	bindings.initialize()
	apply_settings()
	apply_lightbar()
	_start_trigger_bridge()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		_set_gamepad_active(true)
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > 0.25:
			_set_gamepad_active(true)
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		_set_gamepad_active(false)


# ------------------------------------------------------------ подключение

func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	_stop_trigger_bridge()
	stop_rumble()
	refresh_devices()
	_start_trigger_bridge()
	settings_changed.emit()
	if connected:
		_set_gamepad_active(true)
		apply_lightbar()
	else:
		# Если остался хотя бы один геймпад — он становится основным.
		_set_gamepad_active(not _devices.is_empty())


func refresh_devices() -> void:
	_devices.clear()
	for device_id in Input.get_connected_joypads():
		var info := _read_device(int(device_id))
		if not info.is_empty():
			_devices.append(info)
	device_list_changed.emit()


func _read_device(device_id: int) -> Dictionary:
	var info_dict: Dictionary = {}
	if Input.has_method("get_joy_info"):
		info_dict = Input.get_joy_info(device_id)
	var device_name: String = String(info_dict.get("name", Input.get_joy_name(device_id)))
	var guid: String = String(info_dict.get("guid", Input.get_joy_guid(device_id)))
	var vendor: int = int(info_dict.get("vendor_id", info_dict.get("vendor", 0)))
	var product: int = int(info_dict.get("product_id", info_dict.get("product", 0)))
	var info := classify_device(device_name, guid, vendor, product)
	info["device_id"] = device_id
	info["name"] = device_name
	info["guid"] = guid
	info["vendor_id"] = vendor
	info["product_id"] = product
	if Input.has_method("has_joy_light"):
		info["lightbar"] = bool(info.lightbar) and bool(Input.call("has_joy_light", device_id))
	return info


## Определяет модель без обращения к железу — удобно тестировать.
## Возвращает словарь: family, glyph_family, label, lightbar, haptics, paddles.
static func classify_device(device_name: String, guid: String = "", vendor_id: int = 0, product_id: int = 0) -> Dictionary:
	var lower := device_name.to_lower()
	var guid_ids := _guid_vendor_product(guid)
	if vendor_id <= 0:
		vendor_id = int(guid_ids.x)
	if product_id <= 0:
		product_id = int(guid_ids.y)

	var family := "generic"
	var glyph_family := "generic"
	var label := device_name.strip_edges()
	var lightbar := false
	var haptics := false
	var paddles := false

	var sony := (
		vendor_id == SONY_VENDOR
		or lower.contains("sony")
		or lower.contains("playstation")
		or lower.contains("dualsense")
		or lower.contains("dualshock")
		or lower.contains("ps5 controller")
		or lower.contains("ps4 controller")
		or lower.contains("ps3 controller")
		or (lower.contains("wireless controller") and vendor_id == SONY_VENDOR)
	)

	if sony:
		glyph_family = "playstation"
		lightbar = true
		if product_id in DUALSENSE_PRODUCTS or lower.contains("dualsense") or lower.contains("ps5"):
			family = "dualsense"
			label = "DualSense (DualShock 5)"
			haptics = true
			paddles = product_id in DUALSENSE_EDGE_PRODUCTS or lower.contains("edge")
			if paddles:
				label = "DualSense Edge"
		elif (
			product_id in [0x05C4, 0x09CC, 0x0BA0]
			or lower.contains("dualshock 4")
			or lower.contains("ps4")
			or (lower.contains("wireless controller") and vendor_id == SONY_VENDOR)
		):
			family = "dualshock4"
			label = "DualShock 4"
		elif product_id == 0x0268 or lower.contains("dualshock 3") or lower.contains("ps3"):
			family = "dualshock3"
			label = "DualShock 3"
			lightbar = false
		else:
			family = "playstation"
			if label.is_empty() or lower.contains("wireless controller"):
				label = "PlayStation Controller"
	elif vendor_id == XBOX_VENDOR or lower.contains("xbox") or lower.contains("xinput"):
		family = "xbox"
		glyph_family = "xbox"
		if label.is_empty():
			label = "Xbox Controller"
	elif (
		vendor_id == NINTENDO_VENDOR
		or lower.contains("nintendo")
		or lower.contains("joy-con")
		or lower.contains("joycon")
		or lower.contains("switch pro")
		or (lower.contains("pro controller") and vendor_id == NINTENDO_VENDOR)
	):
		family = "switch"
		glyph_family = "switch"
		if lower.contains("joy-con") or lower.contains("joycon"):
			label = "Joy-Con"
		elif lower.contains("pro controller"):
			label = "Nintendo Switch Pro Controller"
		elif label.is_empty():
			label = "Nintendo Switch Controller"
	elif vendor_id == VALVE_VENDOR or lower.contains("steam"):
		family = "steam"
		glyph_family = "xbox"
		if lower.contains("deck"):
			label = "Steam Deck"
		else:
			label = "Steam Controller"
	elif vendor_id == GOOGLE_VENDOR or lower.contains("stadia"):
		family = "stadia"
		glyph_family = "xbox"
		label = "Google Stadia Controller"
	else:
		if label.is_empty():
			label = "Геймпад"

	return {
		"family": family,
		"glyph_family": glyph_family,
		"label": label,
		"lightbar": lightbar,
		"haptics": haptics,
		"paddles": paddles,
	}


## В SDL GUID вендор и продукт записаны little-endian. Если Godot вернул 0
## (бывает у Bluetooth-устройств), достаём их из строки GUID.
static func _guid_vendor_product(guid: String) -> Vector2i:
	if guid.length() < 20:
		return Vector2i.ZERO
	var vendor := _little_endian_hex(guid.substr(8, 4))
	var product := _little_endian_hex(guid.substr(16, 4))
	return Vector2i(vendor, product)


static func _little_endian_hex(text: String) -> int:
	if text.length() != 4:
		return 0
	var low := text.substr(0, 2).hex_to_int()
	var high := text.substr(2, 2).hex_to_int()
	return (high << 8) | low


func get_device_count() -> int:
	return _devices.size()


func has_gamepad() -> bool:
	return not _devices.is_empty()


func get_primary_device() -> Dictionary:
	if _devices.is_empty():
		return {}
	return (_devices[0] as Dictionary).duplicate(true)


func get_device_info(device_id: int) -> Dictionary:
	for info in _devices:
		if int(info.device_id) == device_id:
			return (info as Dictionary).duplicate(true)
	return {}


func get_device_summary() -> String:
	if _devices.is_empty():
		return "ГЕЙМПАД НЕ ПОДКЛЮЧЁН"
	var primary: Dictionary = _devices[0]
	var result := "%s • %s" % [String(primary.label), _layout_name(String(primary.glyph_family))]
	if _devices.size() > 1:
		result += " + ещё %d" % (_devices.size() - 1)
	return result


func is_dualsense() -> bool:
	for info in _devices:
		if String(info.family) == "dualsense":
			return true
	return false


func is_playstation() -> bool:
	for info in _devices:
		if String(info.glyph_family) == "playstation":
			return true
	return false


func supports_lightbar() -> bool:
	for info in _devices:
		if bool(info.lightbar):
			return true
	return false

func get_primary_device_id() -> int:
	if _devices.is_empty():
		return -1
	return int(_devices[0].device_id)


func get_glyph_family() -> String:
	if _devices.is_empty():
		return "generic"
	return String(_devices[0].glyph_family)


func _layout_name(glyph_family: String) -> String:
	match glyph_family:
		"playstation":
			return "раскладка PlayStation"
		"xbox":
			return "раскладка Xbox"
		"switch":
			return "раскладка Nintendo"
		_:
			return "универсальная раскладка"


# ---------------------------------------------------------------- глифы

static func glyphs_for(glyph_family: String) -> Dictionary:
	match glyph_family:
		"playstation":
			return {
				"accept": "✕", "cancel": "○", "west": "□", "north": "△",
				"l1": "L1", "r1": "R1", "l2": "L2", "r2": "R2",
				"l3": "L3", "r3": "R3", "select": "Create", "start": "Options",
				"guide": "PS", "dpad_up": "↑", "dpad_down": "↓",
				"dpad_left": "←", "dpad_right": "→", "stick": "LS",
				"right_stick": "RS", "touchpad": "Touchpad",
			}
		"switch":
			return {
				"accept": "B", "cancel": "A", "west": "Y", "north": "X",
				"l1": "L", "r1": "R", "l2": "ZL", "r2": "ZR",
				"l3": "LS", "r3": "RS", "select": "−", "start": "+",
				"guide": "Home", "dpad_up": "↑", "dpad_down": "↓",
				"dpad_left": "←", "dpad_right": "→", "stick": "LS",
				"right_stick": "RS", "touchpad": "Touch",
			}
		"xbox":
			return {
				"accept": "A", "cancel": "B", "west": "X", "north": "Y",
				"l1": "LB", "r1": "RB", "l2": "LT", "r2": "RT",
				"l3": "LS", "r3": "RS", "select": "View", "start": "Menu",
				"guide": "Xbox", "dpad_up": "↑", "dpad_down": "↓",
				"dpad_left": "←", "dpad_right": "→", "stick": "LS",
				"right_stick": "RS", "touchpad": "Share",
			}
		_:
			return {
				"accept": "1", "cancel": "2", "west": "3", "north": "4",
				"l1": "L1", "r1": "R1", "l2": "L2", "r2": "R2",
				"l3": "L3", "r3": "R3", "select": "Select", "start": "Start",
				"guide": "Guide", "dpad_up": "↑", "dpad_down": "↓",
				"dpad_left": "←", "dpad_right": "→", "stick": "LS",
				"right_stick": "RS", "touchpad": "Touch",
			}


func get_glyphs() -> Dictionary:
	return glyphs_for(get_glyph_family())


## Текущая подпись действия, включая переназначенные клавиши и оси.
func action_glyph(action: String) -> String:
	if action == "ui_accept":
		return String(get_glyphs().accept)
	if action == "ui_cancel":
		return String(get_glyphs().cancel)
	if action == "camera_look":
		return String(get_glyphs().right_stick)
	return binding_label(action, "gamepad")


func binding_label(action: String, device: String, slot: int = -1) -> String:
	if bindings == null:
		return "—"
	if slot >= 0:
		return _format_binding(bindings.call("get_binding", action, device, slot))
	for index in range(2):
		var data: Variant = bindings.call("get_binding", action, device, index)
		if data != null:
			return _format_binding(data)
	return "—"


func _format_binding(value: Variant) -> String:
	if not value is Dictionary:
		return "—"
	var data: Dictionary = value
	match data.get("type"):
		"key":
			return OS.get_keycode_string(int(data.code) as Key)
		"button":
			return button_glyph(int(data.index))
		"axis":
			var axis: int = data.index
			var positive: bool = int(data.sign) > 0
			var glyphs := get_glyphs()
			match axis:
				JOY_AXIS_LEFT_X:
					return "%s %s" % [glyphs.stick, "→" if positive else "←"]
				JOY_AXIS_LEFT_Y:
					return "%s %s" % [glyphs.stick, "↓" if positive else "↑"]
				JOY_AXIS_RIGHT_X:
					return "%s %s" % [glyphs.right_stick, "→" if positive else "←"]
				JOY_AXIS_RIGHT_Y:
					return "%s %s" % [glyphs.right_stick, "↓" if positive else "↑"]
				JOY_AXIS_TRIGGER_LEFT:
					return String(glyphs.l2) if positive else "%s −" % glyphs.l2
				JOY_AXIS_TRIGGER_RIGHT:
					return String(glyphs.r2) if positive else "%s −" % glyphs.r2
			return "Ось %d %s" % [axis, "+" if positive else "−"]
	return "—"


func _on_bindings_changed() -> void:
	bindings_changed.emit()


func button_glyph(button_index: int) -> String:
	var glyphs := get_glyphs()
	match button_index:
		JOY_BUTTON_A:
			return String(glyphs.accept)
		JOY_BUTTON_B:
			return String(glyphs.cancel)
		JOY_BUTTON_X:
			return String(glyphs.west)
		JOY_BUTTON_Y:
			return String(glyphs.north)
		JOY_BUTTON_BACK:
			return String(glyphs.select)
		JOY_BUTTON_GUIDE:
			return String(glyphs.guide)
		JOY_BUTTON_START:
			return String(glyphs.start)
		JOY_BUTTON_LEFT_STICK:
			return String(glyphs.l3)
		JOY_BUTTON_RIGHT_STICK:
			return String(glyphs.r3)
		JOY_BUTTON_LEFT_SHOULDER:
			return String(glyphs.l1)
		JOY_BUTTON_RIGHT_SHOULDER:
			return String(glyphs.r1)
		JOY_BUTTON_DPAD_UP:
			return String(glyphs.dpad_up)
		JOY_BUTTON_DPAD_DOWN:
			return String(glyphs.dpad_down)
		JOY_BUTTON_DPAD_LEFT:
			return String(glyphs.dpad_left)
		JOY_BUTTON_DPAD_RIGHT:
			return String(glyphs.dpad_right)
		_:
			return "Btn %d" % button_index


# --------------------------------------------------------------- действия

## Значения с мёртвой зоной из InputMap и настраиваемой кривой отклика.
func get_steering_input() -> float:
	return _shape_axis(Input.get_axis("steer_right", "steer_left"), steering_curve)


func get_throttle_input() -> float:
	return _shape_axis(Input.get_action_strength("throttle"), trigger_curve)


func get_brake_input() -> float:
	return _shape_axis(Input.get_action_strength("brake"), trigger_curve)


func get_handbrake_input() -> float:
	return Input.get_action_strength("handbrake")


func get_clutch_input() -> float:
	return _shape_axis(Input.get_action_strength("clutch"), trigger_curve)


func get_look_vector() -> Vector2:
	return Input.get_vector(
		"camera_look_left", "camera_look_right",
		"camera_look_up", "camera_look_down",
		0.15
	)


func _shape_axis(value: float, exponent: float) -> float:
	var clamped := clampf(value, -1.0, 1.0)
	if absf(clamped) <= 0.0001:
		return 0.0
	return signf(clamped) * pow(absf(clamped), maxf(exponent, 0.05))


func apply_settings() -> void:
	_set_action_deadzone("steer_left", steering_deadzone)
	_set_action_deadzone("steer_right", steering_deadzone)
	_set_action_deadzone("throttle", trigger_deadzone)
	_set_action_deadzone("brake", trigger_deadzone)
	_set_action_deadzone("clutch", trigger_deadzone)
	_set_action_deadzone("camera_look_left", 0.15)
	_set_action_deadzone("camera_look_right", 0.15)
	_set_action_deadzone("camera_look_up", 0.15)
	_set_action_deadzone("camera_look_down", 0.15)
	settings_changed.emit()


func _set_action_deadzone(action: String, deadzone: float) -> void:
	if InputMap.has_action(action):
		InputMap.action_set_deadzone(action, clampf(deadzone, 0.0, 0.95))


func _ensure_ui_bindings() -> void:
	_ensure_joy_button("ui_accept", JOY_BUTTON_A)
	_ensure_joy_button("ui_cancel", JOY_BUTTON_B)
	_ensure_joy_button("ui_focus_next", JOY_BUTTON_RIGHT_SHOULDER)
	_ensure_joy_button("ui_focus_prev", JOY_BUTTON_LEFT_SHOULDER)


func _ensure_joy_button(action: String, button_index: JoyButton) -> void:
	if not InputMap.has_action(action):
		return
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			if (event as InputEventJoypadButton).button_index == button_index:
				return
	var event := InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button_index
	InputMap.action_add_event(action, event)


func _set_gamepad_active(value: bool) -> void:
	if gamepad_active == value:
		return
	gamepad_active = value
	active_device_changed.emit(value)


# ------------------------------------------------------------- вибрация

## Короткий импульс вибрации: weak — высокочастотный, strong — низкочастотный мотор.
func rumble(weak: float, strong: float, duration: float = 0.15, device: int = -1) -> void:
	if not vibration_enabled or _devices.is_empty():
		return
	_rumble_until_msec = Time.get_ticks_msec() + int(maxf(duration, 0.01) * 1000.0)
	for info in _devices:
		var device_id := int(info.device_id)
		if device >= 0 and device_id != device:
			continue
		if Input.has_method("has_joy_vibration") and not bool(Input.call("has_joy_vibration", device_id)):
			continue
		Input.start_joy_vibration(
			device_id,
			clampf(weak * vibration_strength, 0.0, 1.0),
			clampf(strong * vibration_strength, 0.0, 1.0),
			maxf(duration, 0.01)
		)


func stop_rumble(device: int = -1) -> void:
	for info in _devices:
		var device_id := int(info.device_id)
		if device >= 0 and device_id != device:
			continue
		Input.stop_joy_vibration(device_id)


func test_rumble() -> void:
	rumble(0.55, 0.9, 0.35)


# -------------------------------------------------------------- подсветка

func apply_lightbar() -> void:
	if not lightbar_enabled:
		return
	var has_old_api := Input.has_method("set_joy_light_color")
	var has_new_api := Input.has_method("set_joy_light")
	if not has_old_api and not has_new_api:
		return
	for info in _devices:
		if not bool(info.lightbar):
			continue
		var device_id := int(info.device_id)
		if has_new_api:
			Input.call("set_joy_light", device_id, lightbar_color)
		else:
			Input.call("set_joy_light_color", device_id, lightbar_color)


func set_lightbar_color(color: Color) -> void:
	lightbar_color = color
	apply_lightbar()
	save_settings()


static func lightbar_palette() -> Array[Color]:
	return [
		Color(0.98, 0.45, 0.06, 1.0),
		Color(0.95, 0.15, 0.18, 1.0),
		Color(0.12, 0.55, 0.98, 1.0),
		Color(0.18, 0.92, 0.48, 1.0),
		Color(0.92, 0.20, 0.85, 1.0),
		Color(0.95, 0.95, 0.95, 1.0),
	]


# --------------------------------------------------------------- настройки

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(_settings_path) != OK:
		return
	vibration_enabled = bool(config.get_value("controller", "vibration_enabled", vibration_enabled))
	vibration_strength = clampf(float(config.get_value("controller", "vibration_strength", vibration_strength)), 0.0, 1.0)
	driving_vibration_enabled = bool(config.get_value("controller", "driving_vibration_enabled", driving_vibration_enabled))
	adaptive_triggers_enabled = bool(config.get_value("controller", "adaptive_triggers_enabled", adaptive_triggers_enabled))
	adaptive_trigger_strength = clampf(float(config.get_value("controller", "adaptive_trigger_strength", adaptive_trigger_strength)), 0.0, 1.0)
	steering_deadzone = clampf(float(config.get_value("controller", "steering_deadzone", steering_deadzone)), 0.0, 0.95)
	trigger_deadzone = clampf(float(config.get_value("controller", "trigger_deadzone", trigger_deadzone)), 0.0, 0.95)
	steering_curve = clampf(float(config.get_value("controller", "steering_curve", steering_curve)), 0.5, 3.0)
	trigger_curve = clampf(float(config.get_value("controller", "trigger_curve", trigger_curve)), 0.5, 3.0)
	lightbar_enabled = bool(config.get_value("controller", "lightbar_enabled", lightbar_enabled))
	var saved_color: Variant = config.get_value("controller", "lightbar_color", lightbar_color)
	if saved_color is Color:
		lightbar_color = saved_color as Color


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("controller", "vibration_enabled", vibration_enabled)
	config.set_value("controller", "vibration_strength", vibration_strength)
	config.set_value("controller", "driving_vibration_enabled", driving_vibration_enabled)
	config.set_value("controller", "adaptive_triggers_enabled", adaptive_triggers_enabled)
	config.set_value("controller", "adaptive_trigger_strength", adaptive_trigger_strength)
	config.set_value("controller", "steering_deadzone", steering_deadzone)
	config.set_value("controller", "trigger_deadzone", trigger_deadzone)
	config.set_value("controller", "steering_curve", steering_curve)
	config.set_value("controller", "trigger_curve", trigger_curve)
	config.set_value("controller", "lightbar_enabled", lightbar_enabled)
	config.set_value("controller", "lightbar_color", lightbar_color)
	var error: Error = config.save(_settings_path)
	if error != OK:
		push_warning("Не удалось сохранить настройки контроллера: %s" % error_string(error))


func reset_settings() -> void:
	vibration_enabled = true
	vibration_strength = 0.85
	driving_vibration_enabled = true
	adaptive_triggers_enabled = true
	adaptive_trigger_strength = 0.7
	steering_deadzone = 0.12
	trigger_deadzone = 0.08
	steering_curve = 1.25
	trigger_curve = 1.0
	lightbar_enabled = true
	lightbar_color = Color(0.98, 0.45, 0.06, 1.0)
	apply_settings()
	apply_lightbar()
	_restart_trigger_bridge()
	save_settings()


# ----------------------------------------------------- обратная связь DualSense
# Адаптивные триггеры доступны только через опциональный Linux USB bridge.
# Подключаем его лишь при одном геймпаде: Godot не предоставляет hidraw-путь,
# поэтому при нескольких контроллерах нельзя безопасно сопоставить устройства.
func _start_trigger_bridge() -> void:
	_bridge_status = "недоступны (нужен один DualSense по USB в Linux)"
	if not adaptive_triggers_enabled or OS.get_name() != "Linux" or _devices.size() != 1 or String(_devices[0].family) != "dualsense":
		return
	if not FileAccess.file_exists(TRIGGER_BRIDGE_PATH):
		_bridge_status = "мост триггеров отсутствует в экспорте"
		return
	var source := FileAccess.get_file_as_string(TRIGGER_BRIDGE_PATH)
	var script_path := "user://dualsense_bridge.py"
	_bridge_generation += 1
	_bridge_status_path = "user://dualsense_status_%d_%d.txt" % [OS.get_process_id(), _bridge_generation]
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_bridge_status_path))
	var script := FileAccess.open(script_path, FileAccess.WRITE)
	if script == null or source.is_empty():
		_bridge_status = "не удалось подготовить мост триггеров"
		return
	script.store_string(source)
	script.close()
	var result := OS.execute_with_pipe("python3", PackedStringArray([ProjectSettings.globalize_path(script_path), ProjectSettings.globalize_path(_bridge_status_path)]), false)
	if result.is_empty():
		_bridge_status = "не удалось запустить Python 3"
		return
	_bridge_pid = int(result.get("pid", -1))
	_bridge_pipe = result.get("stdio")
	_bridge_status = "подключение…"


func _stop_trigger_bridge() -> void:
	# Закрытие stdin вызывает очистку эффектов в мосте. Watchdog делает то же
	# при зависании игры; принудительно убивать процесс до очистки нельзя.
	if _bridge_pipe != null:
		_bridge_pipe.close()
		_bridge_pipe = null
	_bridge_pid = -1
	_bridge_status = "недоступны"


func _restart_trigger_bridge() -> void:
	_stop_trigger_bridge()
	_start_trigger_bridge()
	settings_changed.emit()


func get_trigger_status() -> String:
	if not adaptive_triggers_enabled:
		return "выключены"
	return _bridge_status


func _process(_delta: float) -> void:
	if _bridge_pid >= 0 and Time.get_ticks_msec() - _bridge_check_msec >= 250:
		_bridge_check_msec = Time.get_ticks_msec()
		var next_status := _bridge_status
		if FileAccess.file_exists(_bridge_status_path):
			var status := FileAccess.get_file_as_string(_bridge_status_path)
			if status == "ready":
				next_status = "доступны (USB)"
			elif status.begins_with("error:"):
				next_status = "недоступны: " + status.trim_prefix("error: ").strip_edges()
		if not OS.is_process_running(_bridge_pid):
			if next_status == "подключение…" or next_status == "доступны (USB)":
				next_status = "мост триггеров остановлен"
			_stop_trigger_bridge()
			DirAccess.remove_absolute(ProjectSettings.globalize_path(_bridge_status_path))
		if next_status != _bridge_status:
			_bridge_status = next_status
			settings_changed.emit()
	if _feedback_running and (get_tree().paused or Time.get_ticks_msec() - _feedback_last_msec > 400):
		stop_driving_feedback()


func _exit_tree() -> void:
	stop_driving_feedback()
	_stop_trigger_bridge()


func _trigger_binding_present(action: String, axis: int) -> bool:
	if bindings == null:
		return false
	for slot in range(2):
		var entry: Variant = bindings.call("get_binding", action, "gamepad", slot)
		if entry is Dictionary and entry.get("type") == "axis" and int(entry.get("index", -1)) == axis and int(entry.get("sign", 0)) == 1:
			return true
	return false


func update_driving_feedback(speed: float, rpm_ratio: float, slip: float, grounded: bool, roughness: float, throttle: float, brake: float, rumble_allowed: bool = true) -> void:
	if _devices.is_empty() or String(_devices[0].family) != "dualsense":
		return
	var now := Time.get_ticks_msec()
	_feedback_last_msec = now
	_feedback_running = true
	if now - _feedback_sent_msec < 100:
		return
	_feedback_sent_msec = now
	var feedback := DrivingFeedback.calculate(speed, rpm_ratio, slip, grounded, roughness, throttle, brake)
	if vibration_enabled and driving_vibration_enabled and rumble_allowed and now >= _rumble_until_msec:
		Input.start_joy_vibration(int(_devices[0].device_id), float(feedback.weak) * vibration_strength, float(feedback.strong) * vibration_strength, 0.2)
	if adaptive_triggers_enabled and _bridge_pipe != null and _bridge_status == "доступны (USB)":
		var left := roundi(float(feedback.left) * adaptive_trigger_strength * 8.0) if _trigger_binding_present("brake", JOY_AXIS_TRIGGER_LEFT) else 0
		var right := roundi(float(feedback.right) * adaptive_trigger_strength * 8.0) if _trigger_binding_present("throttle", JOY_AXIS_TRIGGER_RIGHT) else 0
		_bridge_pipe.store_line("%d %d" % [left, right])
		_bridge_pipe.flush()


func stop_driving_feedback() -> void:
	if not _feedback_running:
		return
	_feedback_running = false
	stop_rumble()
	if _bridge_pipe != null and _bridge_status == "доступны (USB)":
		_bridge_pipe.store_line("0 0")
		_bridge_pipe.flush()
