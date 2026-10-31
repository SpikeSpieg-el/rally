## Экран подготовки машины. Витрина и автомобиль заезда используют одну
## реализацию внешности; схема UI и сохранения общая для всех пресетов.
extends Control

signal back_requested
signal controls_requested
signal setup_saved(index: int)
signal start_requested(index: int, setup: RallyCarSetup)

const SetupType = preload("res://scripts/data/rally_car_setup.gd")
const TrackType = preload("res://scripts/data/rally_track_config.gd")
const Ps1Materials = preload("res://scripts/ps1_materials.gd")
const Customization = preload("res://scripts/car_customization.gd")
const CarVisuals = preload("res://scripts/car_visual_customization.gd")

## Скорость вращения витрины, радиан/сек. 0 — остановить модель.
@export_range(0.0, 1.0, 0.01) var turntable_speed: float = 0.16

var config: RallyGameConfig
var game: Node
var selected_index := 0
var drafts: Dictionary = {}
var setup: SetupType
var _updating := false
var _dragging := false
var _dirty: Dictionary = {}
var _controls: Dictionary = {}
var _sliders: Dictionary = {}
var _values: Dictionary = {}
var _rows: Dictionary = {}
var _fields: Dictionary = {}
var _wheel_visuals: Array[MeshInstance3D] = []
var _wheel_bases: Array[Basis] = []
var _model_default_y: float = 0.0

@onready var _selector: OptionButton = %SetupSelector
@onready var _summary: Label = %Summary
@onready var _description: Label = %Description
@onready var _status: Label = %Status
@onready var _tabs: TabContainer = %SettingsTabs
@onready var _model: Node3D = %PreviewModel
@onready var _turntable: Node3D = %Turntable
@onready var _start: Button = %StartButton
@onready var _preview_container: SubViewportContainer = $Margin/Layout/Body/ShowroomColumn/Preview
@onready var _preview_camera: Camera3D = $Margin/Layout/Body/ShowroomColumn/Preview/Viewport/Showroom/Camera
@onready var _retro_rect: ColorRect = $Margin/Layout/Body/ShowroomColumn/Preview/Viewport/PostFX/RetroShaderRect


func _ready() -> void:
	_build_settings()
	_selector.item_selected.connect(_select_setup)
	%ResetButton.pressed.connect(_reset_setup)
	%SaveButton.pressed.connect(_save_button_pressed)
	%BackButton.pressed.connect(_request_back)
	%ControlsButton.pressed.connect(func() -> void: controls_requested.emit())
	_start.pressed.connect(_start_race)
	_preview_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview_container.gui_input.connect(_on_preview_input)
	_model_default_y = _model.position.y
	for wheel_name in ["Mitsubishi_Wheel_Ft_L", "Mitsubishi_Wheel_Ft_R", "Mitsubishi_Wheel_Bk_L", "Mitsubishi_Wheel_Bk_R"]:
		var wheel := _model.get_node(wheel_name) as MeshInstance3D
		_wheel_visuals.append(wheel)
		_wheel_bases.append(wheel.basis)


func _build_settings() -> void:
	for group: Dictionary in Customization.GROUPS:
		var scroll := ScrollContainer.new()
		scroll.name = String(group["id"]).capitalize().replace(" ", "")
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_tabs.add_child(scroll)
		_tabs.set_tab_title(_tabs.get_tab_count() - 1, String(group["title"]))
		var margin := MarginContainer.new()
		margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		margin.add_theme_constant_override("margin_left", 8)
		margin.add_theme_constant_override("margin_right", 18)
		margin.add_theme_constant_override("margin_top", 6)
		margin.add_theme_constant_override("margin_bottom", 8)
		scroll.add_child(margin)
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 11)
		margin.add_child(box)
		var note := Label.new()
		note.text = String(group["note"])
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_font_size_override("font_size", 13)
		note.add_theme_color_override("font_color", Color(0.55, 0.67, 0.73))
		box.add_child(note)
		for field: Dictionary in Customization.FIELDS:
			if field["group"] == group["id"]:
				_build_field(box, field)


func _build_field(parent: VBoxContainer, field: Dictionary) -> void:
	var key: String = field["key"]
	var kind: String = field["kind"]
	var prefix: String = String(field.get("node", key.to_pascal_case()))
	_fields[key] = field
	var row := VBoxContainer.new()
	row.name = prefix + "Row"
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)
	_rows[key] = row
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	row.add_child(header)
	var title := Label.new()
	title.text = String(field["label"])
	title.tooltip_text = String(field.get("tip", ""))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.79, 0.85, 0.89))
	header.add_child(title)

	if kind == "number" or kind == "gear":
		var value_label := Label.new()
		value_label.name = prefix + "Value"
		value_label.add_theme_font_size_override("font_size", 15)
		value_label.add_theme_color_override("font_color", Color(1.0, 0.68, 0.28))
		header.add_child(value_label)
		_register_unique(value_label)
		_values[key] = value_label
		var slider := HSlider.new()
		slider.name = prefix + "Slider"
		slider.min_value = float(field["min"])
		slider.max_value = float(field["max"])
		slider.step = float(field["step"])
		slider.custom_minimum_size = Vector2(0, 26)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.focus_mode = Control.FOCUS_ALL
		slider.tooltip_text = String(field.get("tip", ""))
		row.add_child(slider)
		_register_unique(slider)
		slider.value_changed.connect(_on_slider_changed.bind(key))
		_controls[key] = slider
		_sliders[key] = slider
	elif kind == "color":
		var picker := ColorPickerButton.new()
		picker.name = "BodyColor" if key == "body_color" else prefix + "Color"
		picker.custom_minimum_size = Vector2(140, 36)
		picker.edit_alpha = false
		picker.tooltip_text = String(field.get("tip", ""))
		header.add_child(picker)
		_register_unique(picker)
		picker.color_changed.connect(_on_custom_color_changed.bind(key))
		_controls[key] = picker
	elif kind == "choice":
		var choice := OptionButton.new()
		choice.name = prefix + "Choice"
		choice.custom_minimum_size = Vector2(215, 36)
		choice.tooltip_text = String(field.get("tip", ""))
		for option in field["options"]:
			choice.add_item(String(option))
		header.add_child(choice)
		_register_unique(choice)
		choice.item_selected.connect(_on_choice_changed.bind(key))
		_controls[key] = choice
	elif kind == "toggle":
		var toggle := CheckButton.new()
		toggle.name = prefix + "Toggle"
		toggle.tooltip_text = String(field.get("tip", ""))
		header.add_child(toggle)
		_register_unique(toggle)
		toggle.toggled.connect(_on_toggle_changed.bind(key))
		_controls[key] = toggle


func _register_unique(node: Node) -> void:
	# Сохраняем доступ по %TorqueSlider и другим именам для тестов и модов.
	node.owner = self
	node.unique_name_in_owner = true


func _request_back() -> void:
	back_requested.emit()


func open(game_config: RallyGameConfig, index: int, game_state: Node) -> void:
	config = game_config
	game = game_state
	_configure_preview_style()
	drafts.clear()
	_dirty.clear()
	_status.text = "Сохраните изменения или нажмите «На старт»."
	_selector.clear()
	for i in range(config.setup_count()):
		var preset := config.get_setup(i) as SetupType
		_selector.add_item(preset.display_name if preset != null else "—", i)
	show()
	_select_setup(clampi(index, 0, maxi(0, config.setup_count() - 1)))
	_start.grab_focus()


func _configure_preview_style() -> void:
	var selected_track: TrackType = null
	if game != null:
		selected_track = game.get("current_track") as TrackType
	if selected_track == null and config != null:
		selected_track = config.get_track(config.default_track_index) as TrackType
	var enabled: bool = selected_track != null and selected_track.ps1_style
	# Уменьшаем только 3D-превью; элементы меню остаются чёткими.
	_preview_container.stretch_shrink = 3 if enabled else 1
	_preview_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if enabled else CanvasItem.TEXTURE_FILTER_PARENT_NODE
	_retro_rect.visible = enabled
	var material := _retro_rect.material as ShaderMaterial
	if material != null and selected_track != null:
		Ps1Materials.configure_post_effect(material, enabled, 1.0, 270.0, selected_track.color_banding, selected_track.dither_fog)


func _process(delta: float) -> void:
	if visible and _turntable != null and not _dragging:
		_turntable.rotate_y(delta * turntable_speed)


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			_preview_container.accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_preview_camera.fov = maxf(24.0, _preview_camera.fov - 2.0)
			_preview_container.accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_preview_camera.fov = minf(60.0, _preview_camera.fov + 2.0)
			_preview_container.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_turntable.rotate_y(-event.relative.x * 0.008)
		_preview_container.accept_event()


func _select_setup(index: int) -> void:
	if config == null or index < 0 or index >= config.setup_count():
		return
	selected_index = index
	if not drafts.has(index):
		var original := config.get_setup(index) as SetupType
		if original == null:
			return
		var loaded: SetupType = null
		if game != null and game.has_method("get_custom_setup"):
			loaded = game.call("get_custom_setup", index) as SetupType
		drafts[index] = loaded if loaded != null else original.duplicate(true)
	setup = drafts[index] as SetupType
	_refresh()


func _refresh() -> void:
	if setup == null:
		return
	_updating = true
	_selector.select(selected_index)
	_description.text = "БАЗОВЫЙ ПРЕСЕТ: " + setup.description
	_summary.text = "%s\n%s  ·  %d кг  ·  %s" % [setup.get_engine_summary(), setup.get_drivetrain_name(), int(setup.vehicle_mass), setup.get_transmission_name()]
	for field: Dictionary in Customization.FIELDS:
		var key: String = field["key"]
		var kind: String = field["kind"]
		var control: Control = _controls[key]
		if kind == "gear":
			var gear: int = field["gear"]
			_rows[key].visible = gear < setup.gear_ratios.size()
			if gear >= setup.gear_ratios.size():
				continue
			var slider := control as HSlider
			slider.min_value = maxf(float(field["min"]), setup.gear_ratios[gear + 1] + 0.01) if gear + 1 < setup.gear_ratios.size() else float(field["min"])
			slider.max_value = minf(float(field["max"]), setup.gear_ratios[gear - 1] - 0.01) if gear > 0 else float(field["max"])
			slider.value = setup.gear_ratios[gear]
			_values[key].text = _format_number(setup.gear_ratios[gear], field)
		elif kind == "number":
			var value: float = float(setup.get(key))
			(control as HSlider).value = value
			(control as HSlider).editable = key != "awd_front_torque" or setup.drivetrain == SetupType.Drivetrain.AWD
			_values[key].text = _format_number(value, field)
		elif kind == "choice":
			(control as OptionButton).select(int(setup.get(key)))
		elif kind == "toggle":
			(control as CheckButton).button_pressed = bool(setup.get(key))
		elif kind == "color":
			(control as ColorPickerButton).color = setup.get(key)
	_update_preview()
	_updating = false


func _format_number(value: float, field: Dictionary) -> String:
	var scale: float = float(field.get("display_scale", 1.0))
	var step: float = float(field["step"]) * scale
	var decimals := 0
	if step < 0.01:
		decimals = 3
	elif step < 0.1:
		decimals = 2
	elif step < 1.0:
		decimals = 1
	var format := "%0." + str(decimals) + "f"
	var text: String = format % (value * scale)
	var unit: String = field.get("unit", "")
	return text if unit.is_empty() else text + " " + unit


func _update_preview() -> void:
	if _model == null or setup == null:
		return
	_model.position.y = _model_default_y + setup.tire_radius - 0.438
	CarVisuals.apply_body(_model, setup)
	var wheel_scale: Vector3 = CarVisuals.wheel_scale(setup.tire_radius, setup.tire_width)
	for i in range(_wheel_visuals.size()):
		_wheel_visuals[i].basis = _wheel_bases[i].scaled(wheel_scale)
		CarVisuals.apply_wheel(_wheel_visuals[i], setup)


func _mark_changed() -> void:
	_dirty[selected_index] = true
	_status.text = "Есть несохранённые изменения."


func _on_slider_changed(value: float, key: String) -> void:
	if _updating or setup == null or not _fields.has(key):
		return
	var field: Dictionary = _fields[key]
	if field["kind"] == "gear":
		var gear: int = field["gear"]
		if gear >= setup.gear_ratios.size():
			return
		var low: float = float(field["min"])
		var high: float = float(field["max"])
		if gear + 1 < setup.gear_ratios.size():
			low = maxf(low, setup.gear_ratios[gear + 1] + 0.01)
		if gear > 0:
			high = minf(high, setup.gear_ratios[gear - 1] - 0.01)
		setup.gear_ratios[gear] = clampf(value, low, high)
	else:
		setup.set(key, Customization.sanitize_value(field, value, setup.get(key)))
		setup.idle_rpm = minf(setup.idle_rpm, setup.max_rpm * 0.6)
	_mark_changed()
	_refresh()


func _on_choice_changed(value: int, key: String) -> void:
	if _updating or setup == null:
		return
	setup.set(key, Customization.sanitize_value(_fields[key], value, setup.get(key)))
	if key == "torque_shape":
		# В RallyCar непустая пользовательская Curve важнее формы.
		# Вернуть исходную кривую можно первым пунктом списка.
		var base := config.get_setup(selected_index) as SetupType
		setup.torque_curve = base.torque_curve.duplicate() as Curve if value == SetupType.TorqueShape.CUSTOM and base.torque_curve != null else null
	_mark_changed()
	_refresh()


func _on_toggle_changed(value: bool, key: String) -> void:
	if _updating or setup == null:
		return
	setup.set(key, value)
	_mark_changed()
	_refresh()


func _on_custom_color_changed(color: Color, key: String) -> void:
	if _updating or setup == null:
		return
	setup.set(key, Customization.sanitize_value(_fields[key], color, setup.get(key)))
	_mark_changed()
	_update_preview()


# Совместимость с прежним обработчиком настройки цвета.
func _on_color_changed(color: Color) -> void:
	_on_custom_color_changed(color, "body_color")


func _save_drafts() -> bool:
	if game == null or not game.has_method("save_custom_setups"):
		_status.text = "Не удалось сохранить: хранилище недоступно."
		return false
	if not bool(game.call("save_custom_setups", drafts)):
		_status.text = "Не удалось сохранить. Проверьте доступ к файлу настроек."
		return false
	_dirty.clear()
	_status.text = "Все открытые пресеты сохранены."
	setup_saved.emit(selected_index)
	return true


func _save_button_pressed() -> void:
	_save_drafts()


func _start_race() -> void:
	if setup == null:
		return
	if game != null and not _save_drafts():
		return
	start_requested.emit(selected_index, setup)


func _reset_setup() -> void:
	var base := config.get_setup(selected_index) as SetupType
	if base == null:
		return
	setup = base.duplicate(true) as SetupType
	drafts[selected_index] = setup
	_mark_changed()
	_status.text = "Пресет сброшен. Сохраните изменения или начните заезд."
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_request_back()
		get_viewport().set_input_as_handled()
