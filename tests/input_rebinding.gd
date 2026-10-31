# godot --headless --path . --script res://tests/input_rebinding.gd
# Редактирование, конфликты, сохранение и восстановление обеих раскладок.
extends SceneTree

const InputSettings = preload("res://scripts/ui/input_settings.gd")
const MainScene = preload("res://scenes/main_menu.tscn")
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("_run")

func key(code: Key, pressed: bool = true) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	return event

func button(index: JoyButton, pressed: bool = true) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = index
	event.pressed = pressed
	return event

func axis(index: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = index
	event.axis_value = value
	return event

func send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	# Input.parse_input_event обрабатывается в очереди следующего кадра.
	await process_frame
	await process_frame

func _run() -> void:
	var manager := root.get_node("ControllerManager")
	var service: RefCounted = manager.get("bindings")
	var original_path: String = service.get("path")
	service.set("path", "user://input_rebinding_test.cfg")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://input_rebinding_test.cfg"))
	service.call("load_bindings")
	check((service.call("get_binding", "clutch", "keyboard", 0) as Dictionary).code == KEY_SHIFT, "заводская клавиша сцепления — Shift")
	check((service.call("get_binding", "clutch", "gamepad", 0) as Dictionary).index == JOY_BUTTON_X, "заводская кнопка сцепления — X/□")
	var joystick_before: Dictionary = service.call("get_binding", "throttle", "gamepad", 0)
	var changed: Dictionary = service.call("bind", "throttle", "keyboard", 0, key(KEY_I))
	check(changed.ok and manager.call("binding_label", "throttle", "keyboard") == "I", "подпись и основной слот изменены")
	check((service.call("get_binding", "throttle", "keyboard", 1) as Dictionary).code == KEY_UP, "вторая клавиша осталась доступной")
	check(service.call("get_binding", "throttle", "gamepad", 0) == joystick_before, "изменение клавиатуры не трогает геймпад")
	await send(key(KEY_I))
	check(Input.is_action_pressed("throttle"), "новая физическая клавиша действительно даёт газ")
	await send(key(KEY_I, false))
	await send(key(KEY_W))
	check(not Input.is_action_pressed("throttle"), "старая основная клавиша больше не даёт газ")
	await send(key(KEY_W, false))

	changed = service.call("bind", "throttle", "keyboard", 0, key(KEY_S))
	check(changed.ok and not String(changed.swapped).is_empty(), "конфликт обнаружен")
	check((service.call("get_binding", "throttle", "keyboard", 0) as Dictionary).code == KEY_S, "газ переназначен на S")
	check((service.call("get_binding", "brake", "keyboard", 0) as Dictionary).code == KEY_I, "старая клавиша газа передана тормозу")
	await send(key(KEY_S))
	check(Input.is_action_pressed("throttle") and not Input.is_action_pressed("brake"), "конфликтующие действия не срабатывают одновременно")
	await send(key(KEY_S, false))

	changed = service.call("bind", "shift_up", "gamepad", 0, button(JOY_BUTTON_X))
	check(changed.ok and (service.call("get_binding", "clutch", "gamepad", 0) as Dictionary).index == JOY_BUTTON_RIGHT_SHOULDER, "кнопки геймпада тоже меняются местами")
	changed = service.call("bind", "clutch", "gamepad", 1, axis(JOY_AXIS_RIGHT_X, 1.0))
	check(changed.ok and (service.call("get_binding", "clutch", "gamepad", 1) as Dictionary).sign == 1, "половина оси может быть назначена на педаль")
	check(service.call("get_binding", "camera_look_right", "gamepad", 0) == null, "занятая ось больше не дублирует действие")
	check(String(manager.call("binding_label", "clutch", "gamepad", 1)).contains("→"), "подсказка отображает направление оси")
	# Синтетические события проходят через InputMap, как настоящий контроллер.
	await send(axis(JOY_AXIS_RIGHT_X, 0.6))
	var analog_clutch := float(manager.call("get_clutch_input"))
	check(analog_clutch > 0.3 and analog_clutch < 0.9, "аналоговая ось плавно управляет сцеплением")
	check(is_zero_approx(Input.get_action_strength("camera_look_right")), "освобождённая ось больше не управляет камерой")
	await send(axis(JOY_AXIS_RIGHT_X, -0.7))
	check(is_zero_approx(float(manager.call("get_clutch_input"))), "противоположное направление не выжимает сцепление")
	await send(axis(JOY_AXIS_RIGHT_X, 0.0))
	await send(button(JOY_BUTTON_X))
	check(Input.is_action_pressed("shift_up") and not Input.is_action_pressed("clutch"), "новая кнопка геймпада действительно переключает передачу")
	await send(button(JOY_BUTTON_X, false))

	# Изменения читаются заново из файла, не зависят от текущего InputMap.
	service.set("bindings", {})
	service.call("load_bindings")
	check((service.call("get_binding", "throttle", "keyboard", 0) as Dictionary).code == KEY_S, "клавиатура восстановлена с диска")
	check((service.call("get_binding", "shift_up", "gamepad", 0) as Dictionary).index == JOY_BUTTON_X, "геймпад восстановлен с диска")
	var before: Dictionary = service.call("get_binding", "throttle", "keyboard", 0)
	service.set("path", "user://folder_that_does_not_exist/bindings.cfg")
	changed = service.call("bind", "throttle", "keyboard", 0, key(KEY_F))
	check(not changed.ok and service.call("get_binding", "throttle", "keyboard", 0) == before, "ошибка записи откатывает привязку")
	service.set("path", "user://input_rebinding_test.cfg")
	check(bool(service.call("reset_device", "keyboard")), "сброс клавиатуры записан")
	check((service.call("get_binding", "throttle", "keyboard", 0) as Dictionary).code == KEY_W, "клавиатура вернулась к заводской")
	check((service.call("get_binding", "shift_up", "gamepad", 0) as Dictionary).index == JOY_BUTTON_X, "сброс клавиатуры не трогает геймпад")

	# Настоящее окно: вкладки, ввод, отмена и очистка, в том числе с геймпада.
	var menu := MainScene.instantiate()
	root.add_child(menu)
	menu._open_input_settings()
	var screen = menu.input_settings
	check(screen.visible and screen.tabs.get_tab_count() == 3, "настройки открыты из главного меню, есть отдельные вкладки")
	await process_frame
	# Геймпадом можно выбрать вкладку, но нельзя вывести фокус под модальное окно.
	screen.tabs.get_tab_bar().grab_focus()
	await send(button(JOY_BUTTON_LEFT_SHOULDER))
	await send(button(JOY_BUTTON_LEFT_SHOULDER, false))
	check(screen.is_ancestor_of(root.gui_get_focus_owner()), "фокус геймпада остаётся внутри настроек")
	screen.tabs.get_tab_bar().grab_focus()
	await send(button(JOY_BUTTON_DPAD_RIGHT))
	await send(button(JOY_BUTTON_DPAD_RIGHT, false))
	check(screen.tabs.current_tab == 1, "вкладка привязок геймпада выбирается с геймпада")
	await send(button(JOY_BUTTON_DPAD_RIGHT))
	await send(button(JOY_BUTTON_DPAD_RIGHT, false))
	check(screen.tabs.current_tab == 2, "вкладка клавиатуры выбирается с геймпада")
	screen.tabs.current_tab = 2
	screen._begin_capture("clutch", "keyboard", 1)
	screen._input(key(KEY_G))
	check((service.call("get_binding", "clutch", "keyboard", 1) as Dictionary).code == KEY_G, "окно сохраняет введённую клавишу")
	screen._begin_capture("clutch", "keyboard", 1)
	screen._input(key(KEY_ESCAPE))
	check(screen.visible and screen.capture_action.is_empty() and (service.call("get_binding", "clutch", "keyboard", 1) as Dictionary).code == KEY_G, "Esc отменяет захват, не закрывая окно")
	screen._begin_capture("clutch", "keyboard", 1)
	screen._input(key(KEY_BACKSPACE))
	check(service.call("get_binding", "clutch", "keyboard", 1) == null, "Backspace очищает выбранный слот")
	screen.tabs.current_tab = 1
	screen._begin_capture("clutch", "gamepad", 1)
	screen._input(axis(JOY_AXIS_LEFT_Y, -0.2))
	check(not screen.capture_action.is_empty(), "дрейф оси не назначается")
	screen._input(axis(JOY_AXIS_LEFT_Y, -0.9))
	check(screen.capture_action.is_empty() and (service.call("get_binding", "clutch", "gamepad", 1) as Dictionary).sign == -1, "направление аналоговой оси записано")
	screen.close()
	menu._on_start_pressed()
	menu.garage.controls_requested.emit()
	check(screen.visible, "экран управления открывается и из гаража")
	screen.close()
	menu.queue_free()
	await process_frame

	# Испорченные типы отклоняются, недостающие ключи берутся из дефолтов.
	var config := ConfigFile.new()
	config.set_value("keyboard", "throttle", [{"type": "key", "code": -1, "physical": true}, null])
	config.set_value("gamepad", "clutch", "not an array")
	config.save("user://input_rebinding_test.cfg")
	service.call("load_bindings")
	check((service.call("get_binding", "throttle", "keyboard", 0) as Dictionary).code == KEY_W, "повреждённая клавиатура заменена исходной")
	check((service.call("get_binding", "clutch", "gamepad", 0) as Dictionary).index == JOY_BUTTON_X, "повреждённый геймпад заменён исходным")
	service.set("path", original_path)
	service.call("load_bindings")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://input_rebinding_test.cfg"))
	if failures.is_empty():
		print("PASS: переназначение клавиатуры и геймпада, конфликты, UI и сохранение")
		quit(0)
	else:
		printerr("FAIL: переназначение управления: %d" % failures.size())
		quit(1)
