## Настройки геймпада в меню паузы.
##
## Сам узел создаёт строки программно, чтобы не раздувать сцену HUD: здесь
## только статус подключённого контроллера, вибрация, мёртвая зона и кривая
## руля. Все значения живут в автозагрузке ControllerManager и сохраняются в
## user://rally_controller.cfg.
extends VBoxContainer

const CONTROLLER_PATH := "/root/ControllerManager"
const TITLE_COLOR := Color(1.0, 0.55, 0.15, 1.0)
const LABEL_COLOR := Color(0.82, 0.88, 0.94, 1.0)
const VALUE_COLOR := Color(0.62, 0.76, 0.86, 1.0)

var controller: Node = null
var status_label: Label = null
var vibration_check: CheckBox = null
var strength_slider: HSlider = null
var deadzone_slider: HSlider = null
var curve_slider: HSlider = null
var test_button: Button = null
var lightbar_button: Button = null
var _loading: bool = false


func _ready() -> void:
	controller = get_node_or_null(CONTROLLER_PATH)
	_build()
	_connect_signals()
	_sync()


func _build() -> void:
	add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.name = "Title"
	title.text = "КОНТРОЛЛЕР"
	title.add_theme_color_override("font_color", TITLE_COLOR)
	title.add_theme_font_size_override("font_size", 13)
	add_child(title)

	status_label = Label.new()
	status_label.name = "Status"
	status_label.text = "ПОИСК ГЕЙМПАДА…"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", VALUE_COLOR)
	status_label.add_theme_font_size_override("font_size", 12)
	add_child(status_label)

	var vibration_row := HBoxContainer.new()
	vibration_row.name = "VibrationRow"
	vibration_row.add_theme_constant_override("separation", 8)
	add_child(vibration_row)

	vibration_check = CheckBox.new()
	vibration_check.name = "VibrationToggle"
	vibration_check.text = "ВИБРАЦИЯ"
	vibration_check.focus_mode = Control.FOCUS_ALL
	vibration_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vibration_check.add_theme_color_override("font_color", LABEL_COLOR)
	vibration_check.add_theme_font_size_override("font_size", 13)
	vibration_row.add_child(vibration_check)

	test_button = Button.new()
	test_button.name = "TestButton"
	test_button.text = "ТЕСТ"
	test_button.focus_mode = Control.FOCUS_ALL
	test_button.custom_minimum_size = Vector2(86.0, 28.0)
	test_button.add_theme_font_size_override("font_size", 12)
	vibration_row.add_child(test_button)

	strength_slider = _add_slider_row("Strength", "СИЛА ВИБРАЦИИ", 0.0, 100.0, 1.0, 85.0, "%")
	deadzone_slider = _add_slider_row("Deadzone", "МЁРТВАЯ ЗОНА", 3.0, 40.0, 1.0, 12.0, "%")
	curve_slider = _add_slider_row("Curve", "ОТКЛИК РУЛЯ", 100.0, 250.0, 5.0, 125.0, "x")

	var actions_row := HBoxContainer.new()
	actions_row.name = "ActionsRow"
	actions_row.add_theme_constant_override("separation", 8)
	add_child(actions_row)

	lightbar_button = Button.new()
	lightbar_button.name = "LightbarButton"
	lightbar_button.text = "ЦВЕТ ПОДСВЕТКИ"
	lightbar_button.focus_mode = Control.FOCUS_ALL
	lightbar_button.custom_minimum_size = Vector2(0.0, 30.0)
	lightbar_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lightbar_button.add_theme_font_size_override("font_size", 12)
	actions_row.add_child(lightbar_button)


func _add_slider_row(row_name: String, caption: String, minimum: float, maximum: float, step: float, value: float, suffix: String) -> HSlider:
	var row := HBoxContainer.new()
	row.name = row_name
	row.custom_minimum_size = Vector2(0.0, 24.0)
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	var label := Label.new()
	label.text = caption
	label.custom_minimum_size = Vector2(175.0, 0.0)
	label.add_theme_color_override("font_color", LABEL_COLOR)
	label.add_theme_font_size_override("font_size", 13)
	row.add_child(label)

	var slider := HSlider.new()
	slider.name = "Slider"
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_ALL
	row.add_child(slider)

	var value_label := Label.new()
	value_label.name = "Value"
	value_label.custom_minimum_size = Vector2(48.0, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_color_override("font_color", VALUE_COLOR)
	value_label.add_theme_font_size_override("font_size", 12)
	value_label.set_meta("suffix", suffix)
	row.add_child(value_label)
	return slider


func _connect_signals() -> void:
	vibration_check.toggled.connect(_on_vibration_toggled)
	strength_slider.value_changed.connect(_on_strength_changed)
	deadzone_slider.value_changed.connect(_on_deadzone_changed)
	curve_slider.value_changed.connect(_on_curve_changed)
	test_button.pressed.connect(_on_test_pressed)
	lightbar_button.pressed.connect(_on_lightbar_pressed)
	if controller != null:
		if controller.has_signal("device_list_changed") and not controller.is_connected("device_list_changed", _sync):
			controller.connect("device_list_changed", _sync)
		if controller.has_signal("active_device_changed") and not controller.is_connected("active_device_changed", _on_active_device_changed):
			controller.connect("active_device_changed", _on_active_device_changed)


func _sync() -> void:
	if controller == null:
		status_label.text = "МЕНЕДЖЕР КОНТРОЛЛЕРА НЕДОСТУПЕН"
		return
	_loading = true
	status_label.text = _status_text()
	vibration_check.set_pressed_no_signal(bool(controller.get("vibration_enabled")))
	strength_slider.set_value_no_signal(float(controller.get("vibration_strength")) * 100.0)
	deadzone_slider.set_value_no_signal(float(controller.get("steering_deadzone")) * 100.0)
	curve_slider.set_value_no_signal(float(controller.get("steering_curve")) * 100.0)
	_update_labels()
	_loading = false
	lightbar_button.visible = controller.has_method("supports_lightbar") and bool(controller.call("supports_lightbar"))


func _status_text() -> String:
	var has_gamepad: bool = controller.has_method("has_gamepad") and bool(controller.call("has_gamepad"))
	if not has_gamepad:
		return "ГЕЙМПАД НЕ ПОДКЛЮЧЁН • подключите USB/Bluetooth и он определится сам"
	var summary: String = String(controller.call("get_device_summary"))
	var note: String = "Горячее подключение поддерживается"
	if controller.has_method("is_dualsense") and bool(controller.call("is_dualsense")):
		note = "DualSense: вибрация, подсветка, стандартная раскладка"
	return "%s\n%s" % [summary, note]


func _on_active_device_changed(_gamepad_active: bool) -> void:
	if controller != null:
		status_label.text = _status_text()


func _on_vibration_toggled(pressed: bool) -> void:
	if _loading or controller == null:
		return
	controller.set("vibration_enabled", pressed)
	if not pressed and controller.has_method("stop_rumble"):
		controller.call("stop_rumble")
	controller.call("save_settings")


func _on_strength_changed(value: float) -> void:
	_update_label("Strength", value, "%")
	if _loading or controller == null:
		return
	controller.set("vibration_strength", value / 100.0)
	controller.call("save_settings")


func _on_deadzone_changed(value: float) -> void:
	_update_label("Deadzone", value, "%")
	if _loading or controller == null:
		return
	controller.set("steering_deadzone", value / 100.0)
	controller.call("apply_settings")
	controller.call("save_settings")


func _on_curve_changed(value: float) -> void:
	_update_label("Curve", value / 100.0, "x")
	if _loading or controller == null:
		return
	controller.set("steering_curve", value / 100.0)
	controller.call("save_settings")


func _on_test_pressed() -> void:
	if controller != null and controller.has_method("test_rumble"):
		controller.call("test_rumble")


func _on_lightbar_pressed() -> void:
	if controller == null or not controller.has_method("supports_lightbar"):
		return
	var palette: Array = controller.call("lightbar_palette")
	if palette.is_empty():
		return
	var current: Color = controller.get("lightbar_color")
	var index: int = 0
	var best_distance: float = INF
	for i in range(palette.size()):
		var candidate: Color = palette[i]
		var distance: float = absf(candidate.r - current.r) + absf(candidate.g - current.g) + absf(candidate.b - current.b)
		if distance < best_distance:
			best_distance = distance
			index = i
	controller.call("set_lightbar_color", palette[(index + 1) % palette.size()])


func _update_labels() -> void:
	_update_label("Strength", strength_slider.value, "%")
	_update_label("Deadzone", deadzone_slider.value, "%")
	_update_label("Curve", curve_slider.value / 100.0, "x")


func _update_label(row_name: String, value: float, suffix: String) -> void:
	var label := get_node_or_null("%s/Value" % row_name) as Label
	if label == null:
		return
	if suffix == "%":
		label.text = "%d%%" % roundi(value)
	else:
		label.text = "%.2f%s" % [value, suffix]
