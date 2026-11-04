## Общее окно управления: открывается из главного меню, гаража и паузы.
## Для каждого игрового действия есть два независимых слота на устройство.
extends Control

signal closed

const Bindings = preload("res://scripts/input/input_bindings.gd")
const ControllerSettings = preload("res://scripts/ui/controller_settings.gd")
const GameSettings = preload("res://scripts/ui/game_settings.gd")
const UiThemeType = preload("res://scripts/data/rally_ui_theme.gd")

## Палитра/размеры окна. Пусто — res://data/ui/default_ui_theme.tres.
@export var ui_theme: UiThemeType = null

var manager: Node
var tabs: TabContainer
var status: Label
var reset_button: Button
var cancel_button: Button
var close_button: Button
var controller_options: VBoxContainer
var buttons: Dictionary = {}
var capture_action: String = ""
var capture_device: String = ""
var capture_slot := -1
var blocked_axes: Dictionary = {}
var _previous_focus: Control
var _overlay_focus: Control
var _closed_frame := -100
var _closing := false
var _fade_tween: Tween = null


## Палитра окна (никогда null).
func theme_cfg() -> UiThemeType:
	if ui_theme == null:
		if ResourceLoader.exists("res://data/ui/default_ui_theme.tres"):
			ui_theme = ResourceLoader.load("res://data/ui/default_ui_theme.tres") as UiThemeType
		if ui_theme == null:
			ui_theme = UiThemeType.new()
	return ui_theme


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	manager = get_node_or_null("/root/ControllerManager")
	_build()
	if manager != null and manager.has_signal("bindings_changed"):
		manager.connect("bindings_changed", _refresh_buttons)
	get_viewport().gui_focus_changed.connect(_on_gui_focus_changed)
	hide()


func _build() -> void:
	var t := theme_cfg()
	var background := ColorRect.new()
	background.color = t.overlay_backdrop
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(t.overlay_min_width, t.overlay_min_height)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = t.panel_background
	panel_style.border_color = t.border_accent
	panel_style.set_border_width_all(t.border_width)
	panel_style.border_width_top = 4
	panel_style.set_corner_radius_all(6)
	panel_style.content_margin_left = 28.0
	panel_style.content_margin_right = 28.0
	panel_style.content_margin_top = 22.0
	panel_style.content_margin_bottom = 22.0
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", t.overlay_separation)
	panel.add_child(layout)
	var eyebrow := Label.new()
	eyebrow.text = "НАСТРОЙКИ  /  УПРАВЛЕНИЕ"
	eyebrow.add_theme_color_override("font_color", t.accent)
	eyebrow.add_theme_font_size_override("font_size", t.font_overlay_note)
	layout.add_child(eyebrow)
	var title := Label.new()
	title.text = "НАСТРОЙКИ ИГРЫ"
	title.add_theme_font_size_override("font_size", t.font_overlay_title)
	layout.add_child(title)

	tabs = TabContainer.new()
	tabs.name = "Tabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.clip_tabs = true
	layout.add_child(tabs)
	_build_game_tab()
	_build_controller_tab()
	_build_bindings_tab("gamepad", "ГЕЙМПАД · КНОПКИ")
	_build_bindings_tab("keyboard", "КЛАВИАТУРА")
	tabs.tab_changed.connect(_on_tab_changed)

	status = Label.new()
	status.name = "Status"
	status.text = "Настройки сохраняются автоматически."
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", t.text_secondary)
	status.add_theme_font_size_override("font_size", t.font_overlay_note)
	layout.add_child(status)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", t.overlay_separation)
	layout.add_child(footer)
	reset_button = Button.new()
	reset_button.name = "ResetBindings"
	reset_button.text = "СБРОСИТЬ ПРИВЯЗКИ"
	reset_button.custom_minimum_size = Vector2(t.overlay_reset_button_width, t.overlay_button_height)
	reset_button.pressed.connect(_reset_current_device)
	footer.add_child(reset_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	cancel_button = Button.new()
	cancel_button.name = "CancelCapture"
	cancel_button.text = "ОТМЕНИТЬ ВВОД"
	cancel_button.custom_minimum_size = Vector2(t.overlay_button_width, t.overlay_button_height)
	cancel_button.pressed.connect(_cancel_capture)
	footer.add_child(cancel_button)
	close_button = Button.new()
	close_button.name = "Close"
	close_button.text = "ГОТОВО"
	close_button.custom_minimum_size = Vector2(t.overlay_close_button_width, t.overlay_button_height)
	close_button.pressed.connect(close)
	footer.add_child(close_button)
	cancel_button.hide()
	reset_button.hide()
	_refresh_buttons()


func _new_scroll(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "Tab%d" % tabs.get_tab_count()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroll)
	tabs.set_tab_title(tabs.get_tab_count() - 1, title)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := theme_cfg()
	margin.add_theme_constant_override("margin_left", t.overlay_margin_left)
	margin.add_theme_constant_override("margin_right", t.overlay_margin_right)
	margin.add_theme_constant_override("margin_top", t.overlay_margin_vertical)
	margin.add_theme_constant_override("margin_bottom", t.overlay_margin_vertical)
	scroll.add_child(margin)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", maxi(1, t.overlay_margin_vertical / 2))
	margin.add_child(content)
	return content


func _build_game_tab() -> void:
	var content := _new_scroll("ИГРА")
	var settings := GameSettings.new()
	settings.name = "GameSettings"
	content.add_child(settings)


func _build_controller_tab() -> void:
	var content := _new_scroll("ГЕЙМПАД")
	var note := Label.new()
	note.text = "Подключите геймпад по USB или Bluetooth. Настройки применяются сразу."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", theme_cfg().text_muted)
	content.add_child(note)
	controller_options = ControllerSettings.new()
	controller_options.ui_theme = theme_cfg()
	content.add_child(controller_options)


func _build_bindings_tab(device: String, title: String) -> void:
	var content := _new_scroll(title)
	var note := Label.new()
	note.text = "Два слота на действие. Выберите слот и нажмите клавишу, кнопку или отклоните ось.\nEsc — отменить ввод, Backspace — очистить слот. Конфликтующие назначения меняются местами."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", theme_cfg().text_muted)
	note.add_theme_font_size_override("font_size", theme_cfg().font_overlay_note)
	content.add_child(note)
	for entry: Dictionary in Bindings.ACTIONS:
		var action: String = entry.id
		var row := HBoxContainer.new()
		row.name = action.to_pascal_case()
		row.add_theme_constant_override("separation", theme_cfg().row_separation)
		content.add_child(row)
		var label := Label.new()
		label.text = String(entry.label)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", theme_cfg().font_overlay_label)
		row.add_child(label)
		for slot in range(Bindings.SLOTS):
			var button := Button.new()
			button.name = "Slot%d" % (slot + 1)
			button.custom_minimum_size = Vector2(theme_cfg().binding_button_width, theme_cfg().binding_button_height)
			button.focus_mode = Control.FOCUS_ALL
			button.pressed.connect(_begin_capture.bind(action, device, slot))
			row.add_child(button)
			buttons[_button_key(action, device, slot)] = button


func _button_key(action: String, device: String, slot: int) -> String:
	return "%s:%s:%d" % [device, action, slot]


func _kill_fade() -> void:
	if _fade_tween != null and _fade_tween.is_running():
		_fade_tween.kill()
	_fade_tween = null


func open() -> void:
	if visible and not _closing:
		return
	_kill_fade()
	_closing = false
	_previous_focus = get_viewport().gui_get_focus_owner()
	show()
	mouse_filter = Control.MOUSE_FILTER_STOP
	modulate.a = 0.0
	_on_tab_changed(tabs.current_tab)
	_refresh_buttons()
	if tabs.current_tab == 1 and controller_options != null:
		var first := controller_options.get_node_or_null("VibrationRow/VibrationToggle") as Control
		if first != null:
			first.grab_focus()
	else:
		close_button.grab_focus()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 1.0, 0.20)


# При навигации клавиатурой/геймпадом фокус не должен уходить под модальное
# окно, иначе можно случайно запустить заезд или нажать кнопку паузы.
func _on_gui_focus_changed(focus: Control) -> void:
	if not visible:
		return
	if focus != null and is_ancestor_of(focus):
		_overlay_focus = focus
		return
	if is_instance_valid(_overlay_focus) and _overlay_focus.is_visible_in_tree():
		_overlay_focus.grab_focus()
	elif tabs != null:
		tabs.get_tab_bar().grab_focus()


func close() -> void:
	if not visible or _closing:
		return
	_closing = true
	_cancel_capture()
	_kill_fade()
	# Окно уходит плавно, но сразу перестаёт перехватывать мышь. Флаг
	# _closing сохраняет блокировку действий до конца анимации.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 0.0, 0.16)
	await get_tree().create_timer(0.16, true).timeout
	# За время fade-out окно могли открыть заново: тогда старый close()
	# больше не должен его прятать.
	if not _closing:
		return
	hide()
	modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_closing = false
	_closed_frame = Engine.get_process_frames() + 1
	if is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()
	closed.emit()


func blocks_actions() -> bool:
	return visible or _closing or Engine.get_process_frames() <= _closed_frame


func _on_tab_changed(index: int) -> void:
	if not capture_action.is_empty():
		_cancel_capture()
	if reset_button != null:
		reset_button.visible = index > 1
	if status != null:
		status.text = "Настройки сохраняются автоматически."


func _begin_capture(action: String, device: String, slot: int) -> void:
	if manager == null or manager.get("bindings") == null:
		status.text = "Менеджер управления недоступен."
		return
	capture_action = action
	capture_device = device
	capture_slot = slot
	blocked_axes.clear()
	# Не принимаем стик, которым открыли меню, пока он не вернулся к центру.
	if device == "gamepad":
		for joy_id in Input.get_connected_joypads():
			for axis in range(JOY_AXIS_MAX):
				if absf(Input.get_joy_axis(joy_id, axis as JoyAxis)) > 0.45:
					blocked_axes["%d:%d" % [joy_id, axis]] = true
	status.text = "Нажмите новую клавишу" if device == "keyboard" else "Нажмите кнопку или отклоните нужную ось геймпада"
	status.text += "  •  Esc — отменить, Backspace — очистить"
	cancel_button.show()
	_refresh_buttons()


func _cancel_capture() -> void:
	capture_action = ""
	capture_device = ""
	capture_slot = -1
	blocked_axes.clear()
	if cancel_button != null:
		cancel_button.hide()
	if status != null:
		status.text = "Настройки сохраняются автоматически."
	_refresh_buttons()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not capture_action.is_empty():
		if event is InputEventKey:
			var key := event as InputEventKey
			if not key.pressed or key.echo:
				return
			if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
				_cancel_capture()
				get_viewport().set_input_as_handled()
				return
			if key.keycode == KEY_BACKSPACE or key.physical_keycode == KEY_BACKSPACE:
				_finish_capture(null)
				get_viewport().set_input_as_handled()
				return
			if capture_device == "keyboard":
				_finish_capture(key)
				get_viewport().set_input_as_handled()
			return
		if capture_device == "gamepad" and event is InputEventJoypadButton:
			if (event as InputEventJoypadButton).pressed:
				_finish_capture(event)
				get_viewport().set_input_as_handled()
			return
		if capture_device == "gamepad" and event is InputEventJoypadMotion:
			var motion := event as InputEventJoypadMotion
			var axis_key := "%d:%d" % [motion.device, motion.axis]
			if absf(motion.axis_value) < 0.3:
				blocked_axes.erase(axis_key)
			elif absf(motion.axis_value) >= 0.65 and not blocked_axes.has(axis_key):
				_finish_capture(motion)
				get_viewport().set_input_as_handled()
			return
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _finish_capture(event: InputEvent) -> void:
	var action := capture_action
	var device := capture_device
	var slot := capture_slot
	var service: RefCounted = manager.get("bindings")
	var result: Dictionary = service.call("bind", action, device, slot, event)
	_cancel_capture()
	if not bool(result.get("ok", false)):
		status.text = String(result.get("message", "Не удалось изменить привязку."))
	else:
		var swapped: String = result.get("swapped", "")
		status.text = "Сохранено." if swapped.is_empty() else "Сохранено. Привязка «%s» поменяна местами." % swapped


func _refresh_buttons() -> void:
	if manager == null or buttons.is_empty():
		return
	for entry: Dictionary in Bindings.ACTIONS:
		for device: String in Bindings.DEVICES:
			for slot in range(Bindings.SLOTS):
				var key := _button_key(String(entry.id), device, slot)
				var button := buttons.get(key) as Button
				if button == null:
					continue
				button.text = "НАЖМИТЕ…" if capture_action == entry.id and capture_device == device and capture_slot == slot else String(manager.call("binding_label", String(entry.id), device, slot))
				button.tooltip_text = "Нажмите для переназначения"


func _reset_current_device() -> void:
	if manager == null or tabs.current_tab == 0:
		return
	_cancel_capture()
	var device := "gamepad" if tabs.current_tab == 2 else "keyboard"
	var service: RefCounted = manager.get("bindings")
	status.text = "Заводские привязки восстановлены." if service != null and bool(service.call("reset_device", device)) else "Не удалось сохранить привязки."
