# Проверка раскладки контроллеров и определения моделей.
# godot --headless --path . --script res://tests/controller_input.gd
extends SceneTree

const ManagerScript = preload("res://scripts/input/controller_manager.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _has_joy_button(action: String, button: int) -> bool:
	if not InputMap.has_action(action):
		return false
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == button:
			return true
	return false


func _has_joy_axis(action: String, axis: int, value: float) -> bool:
	if not InputMap.has_action(action):
		return false
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion:
			var motion := event as InputEventJoypadMotion
			if motion.axis == axis and is_equal_approx(motion.axis_value, value):
				return true
	return false


func _run() -> void:
	# Все игровые действия должны иметь кнопки/оси геймпада. Индексы — это
	# стандартная раскладка SDL, которую Godot использует для DualSense,
	# DualShock, Xbox, Switch Pro и большинства USB/Bluetooth-контроллеров.
	var buttons := {
		"handbrake": JOY_BUTTON_B,
		"shift_up": JOY_BUTTON_RIGHT_SHOULDER,
		"shift_down": JOY_BUTTON_LEFT_SHOULDER,
		"camera_switch": JOY_BUTTON_Y,
		"camera_recenter": JOY_BUTTON_RIGHT_STICK,
		"reset_car": JOY_BUTTON_BACK,
		"drivetrain_switch": JOY_BUTTON_LEFT_STICK,
		"pause": JOY_BUTTON_START,
		"ui_accept": JOY_BUTTON_A,
		"ui_cancel": JOY_BUTTON_B,
	}
	for action in buttons.keys():
		_check(_has_joy_button(String(action), int(buttons[action])), "нет кнопки геймпада у действия " + String(action))

	var axes := [
		["throttle", JOY_AXIS_TRIGGER_RIGHT, 1.0],
		["brake", JOY_AXIS_TRIGGER_LEFT, 1.0],
		["steer_left", JOY_AXIS_LEFT_X, -1.0],
		["steer_right", JOY_AXIS_LEFT_X, 1.0],
		["camera_look_left", JOY_AXIS_RIGHT_X, -1.0],
		["camera_look_right", JOY_AXIS_RIGHT_X, 1.0],
		["camera_look_up", JOY_AXIS_RIGHT_Y, -1.0],
		["camera_look_down", JOY_AXIS_RIGHT_Y, 1.0],
	]
	for entry in axes:
		_check(_has_joy_axis(String(entry[0]), int(entry[1]), float(entry[2])), "нет оси геймпада у действия " + String(entry[0]))

	# Определение моделей по vendor/product и по имени.
	var dualsense := ManagerScript.classify_device("DualSense Wireless Controller", "", 0x054C, 0x0CE6)
	_check(String(dualsense.family) == "dualsense", "DualSense не распознан по vendor/product")
	_check(String(dualsense.glyph_family) == "playstation", "у DualSense должна быть раскладка PlayStation")
	_check(bool(dualsense.lightbar) and bool(dualsense.haptics), "у DualSense должны быть подсветка и вибрация")
	_check(ManagerScript.glyphs_for("playstation").accept == "✕", "у PlayStation неверный глиф подтверждения")

	var dualsense_by_name := ManagerScript.classify_device("DualSense Wireless Controller")
	_check(String(dualsense_by_name.family) == "dualsense", "DualSense не распознан по имени")

	var dualshock4 := ManagerScript.classify_device("Wireless Controller", "030000004c050000cc09000000000000")
	_check(String(dualshock4.family) == "dualshock4", "DualShock 4 не распознан по GUID")

	var dualshock3 := ManagerScript.classify_device("PLAYSTATION(R)3 Controller", "", 0x054C, 0x0268)
	_check(String(dualshock3.family) == "dualshock3", "DualShock 3 не распознан")

	var xbox := ManagerScript.classify_device("Xbox Wireless Controller", "", 0x045E, 0x0B13)
	_check(String(xbox.glyph_family) == "xbox", "Xbox не распознан")
	_check(ManagerScript.glyphs_for("xbox").accept == "A", "у Xbox неверный глиф подтверждения")

	var switch_pro := ManagerScript.classify_device("Pro Controller", "", 0x057E, 0x2009)
	_check(String(switch_pro.family) == "switch", "Switch Pro не распознан")
	_check(ManagerScript.glyphs_for("switch").accept == "B", "у Switch южная кнопка подписана B")

	var steam_deck := ManagerScript.classify_device("Steam Deck Controller", "", 0x28DE, 0x1205)
	_check(String(steam_deck.family) == "steam", "Steam Deck не распознан")

	var generic := ManagerScript.classify_device("USB Gamepad", "", 0x1234, 0x5678)
	_check(String(generic.family) == "generic", "неизвестный геймпад должен оставаться универсальным")

	# Автозагрузка должна добавить UI-кнопки и применить мёртвые зоны.
	var manager: Node = root.get_node_or_null("ControllerManager")
	_check(manager != null, "автозагрузка ControllerManager не найдена")
	if manager != null:
		_check(_has_joy_button("ui_accept", JOY_BUTTON_A), "ControllerManager не добавил A в ui_accept")
		_check(_has_joy_button("ui_cancel", JOY_BUTTON_B), "ControllerManager не добавил B в ui_cancel")
		_check(is_equal_approx(InputMap.action_get_deadzone("steer_left"), float(manager.get("steering_deadzone"))), "мёртвая зона руля не применена")
		_check(int(manager.call("get_device_count")) == 0, "в headless-тесте не должно быть реальных геймпадов")

	if failures.is_empty():
		print("PASS: раскладка и определение контроллеров")
		quit(0)
	else:
		printerr("FAIL: контроллеры, ошибок %d" % failures.size())
		quit(1)
