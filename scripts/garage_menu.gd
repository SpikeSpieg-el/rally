## Экран подготовки машины. Витрина и автомобиль заезда используют одну
## реализацию внешности; готовые пресеты доступны только для просмотра.
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
const CarModels = preload("res://scripts/car_models.gd")
const UiThemeType = preload("res://scripts/data/rally_ui_theme.gd")
const MenuLayoutType = preload("res://scripts/data/rally_menu_layout.gd")

@export_group("Инспектор: витрина")
## Скорость вращения витрины, радиан/сек. Берётся из layout, если не задана.
@export_range(0.0, 1.0, 0.01) var turntable_speed_override: float = -1.0
## Цвета и размеры шрифтов. Пусто — res://data/ui/default_ui_theme.tres.
@export var ui_theme: UiThemeType = null
## Тексты и подсказки гаража. Пусто — res://data/ui/default_menu_layout.tres.
@export var menu_layout: MenuLayoutType = null

var config: RallyGameConfig
var game: Node
var selected_index := 0
var setup: SetupType
var _creating := false
var _editing := false
var _readonly_values: Dictionary = {}
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
## Кузова машин, у которых есть своя модель: id → узел на витрине.
## Кузов сцены (%PreviewModel) показывается у машины без model_scene.
var _vehicle_models: Dictionary = {}
var _vehicle_id: String = "mitsubishi"


func theme_cfg() -> UiThemeType:
	if ui_theme == null:
		if ResourceLoader.exists("res://data/ui/default_ui_theme.tres"):
			ui_theme = ResourceLoader.load("res://data/ui/default_ui_theme.tres") as UiThemeType
		if ui_theme == null:
			ui_theme = UiThemeType.new()
	return ui_theme


func layout() -> MenuLayoutType:
	if menu_layout == null:
		if ResourceLoader.exists("res://data/ui/default_menu_layout.tres"):
			menu_layout = ResourceLoader.load("res://data/ui/default_menu_layout.tres") as MenuLayoutType
		if menu_layout == null:
			menu_layout = MenuLayoutType.new()
	return menu_layout


## Скорость витрины: явное значение сцены главнее ресурса.
func turntable_speed() -> float:
	if turntable_speed_override >= 0.0:
		return turntable_speed_override
	return layout().garage_turntable_speed

@onready var _name_input: LineEdit = %PresetName
@onready var _create: Button = %CreateButton
@onready var _reset: Button = %ResetButton
@onready var _save: Button = %SaveButton
@onready var _selector: OptionButton = %SetupSelector
@onready var _summary: Label = %Summary
@onready var _description: Label = %Description
@onready var _status: Label = %Status
@onready var _tabs: TabContainer = %SettingsTabs
@onready var _vehicle_selector: OptionButton = %VehicleSelector
@onready var _car_title: Label = $Margin/Layout/Body/ShowroomColumn/CarTitle
@onready var _model: Node3D = %PreviewModel
@onready var _turntable: Node3D = %Turntable
@onready var _start: Button = %StartButton
@onready var _preview_container: SubViewportContainer = $Margin/Layout/Body/ShowroomColumn/Preview
@onready var _preview_camera: Camera3D = $Margin/Layout/Body/ShowroomColumn/Preview/Viewport/Showroom/Camera
@onready var _retro_rect: ColorRect = $Margin/Layout/Body/ShowroomColumn/Preview/Viewport/PostFX/RetroShaderRect


func _ready() -> void:
	_build_settings()
	_fill_vehicle_selector()
	_vehicle_selector.item_selected.connect(_select_vehicle)
	_selector.item_selected.connect(_select_setup)
	_create.pressed.connect(_create_copy)
	_name_input.text_changed.connect(_on_name_changed)
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
		box.add_theme_constant_override("separation", theme_cfg().garage_group_separation)
		margin.add_child(box)
		var note := Label.new()
		note.text = String(group["note"])
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_font_size_override("font_size", theme_cfg().garage_note_size)
		note.add_theme_color_override("font_color", theme_cfg().text_muted)
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
	title.add_theme_font_size_override("font_size", theme_cfg().font_button_small)
	title.add_theme_color_override("font_color", theme_cfg().text_primary)
	header.add_child(title)

	if kind != "number" and kind != "gear":
		var readonly := Label.new()
		readonly.add_theme_font_size_override("font_size", theme_cfg().font_button_small)
		readonly.add_theme_color_override("font_color", theme_cfg().text_value)
		header.add_child(readonly)
		_readonly_values[key] = readonly

	if kind == "number" or kind == "gear":
		var value_label := Label.new()
		value_label.name = prefix + "Value"
		value_label.add_theme_font_size_override("font_size", theme_cfg().font_hud_value)
		value_label.add_theme_color_override("font_color", theme_cfg().text_value)
		header.add_child(value_label)
		_register_unique(value_label)
		_values[key] = value_label
		var slider := HSlider.new()
		slider.name = prefix + "Slider"
		slider.min_value = float(field["min"])
		slider.max_value = float(field["max"])
		slider.step = float(field["step"])
		slider.custom_minimum_size = Vector2(0, theme_cfg().garage_slider_height)
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
		picker.custom_minimum_size = Vector2(theme_cfg().garage_picker_width, theme_cfg().garage_picker_height)
		picker.edit_alpha = false
		picker.tooltip_text = String(field.get("tip", ""))
		header.add_child(picker)
		_register_unique(picker)
		picker.color_changed.connect(_on_custom_color_changed.bind(key))
		_controls[key] = picker
	elif kind == "choice":
		var choice := OptionButton.new()
		choice.name = prefix + "Choice"
		choice.custom_minimum_size = Vector2(theme_cfg().garage_choice_width, theme_cfg().garage_picker_height)
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
	# Список машин приходит из конфига, а он известен только здесь: в _ready()
	# конфига ещё нет, иначе в списке осталась бы одна машина по умолчанию.
	_fill_vehicle_selector()
	var fallback := config.default_vehicle_id() if config != null else "mitsubishi"
	var selected_vehicle: String = (
		String(game.get("vehicle_id")) if game != null and game.has_method("select_vehicle") else fallback
	)
	_show_vehicle(selected_vehicle)
	_configure_preview_style()
	_dirty.clear()
	_status.text = "Выберите пресет или создайте свой на его основе."
	_rebuild_selector()
	show()
	_select_setup(clampi(index, 0, maxi(0, _setup_count() - 1)))
	_start.grab_focus()


## Машины в порядке реестра: индекс пункта = индекс в data/vehicles.
func _vehicle_ids() -> Array[String]:
	var fallback: Array[String] = ["mitsubishi"]
	return config.vehicle_ids() if config != null else fallback


func _vehicle_index(id: String) -> int:
	return maxi(0, _vehicle_ids().find(id))


func _fill_vehicle_selector() -> void:
	_vehicle_selector.clear()
	for id in _vehicle_ids():
		var data: RallyVehicle = config.vehicle(id) if config != null else null
		_vehicle_selector.add_item(data.display_name if data != null else id.to_upper())


## Выбрать машину по id (из меню или теста). Индекс ищется в реестре.
func select_vehicle(id: String) -> void:
	_select_vehicle(_vehicle_index(id))


func _select_vehicle(index: int) -> void:
	var ids := _vehicle_ids()
	if index < 0 or index >= ids.size():
		return
	var id: String = ids[index]
	if not _show_vehicle(id):
		return
	if game != null and game.has_method("select_vehicle"):
		game.call("select_vehicle", id)
	# У каждой машины свой список пресетов: после смены машины список и выбор
	# пересобираются, иначе в гараже остались бы чужие настройки.
	_rebuild_selector()
	_select_setup(clampi(selected_index, 0, maxi(0, _setup_count() - 1)))
	_refresh()


## Показывает кузов выбранной машины. Модель грузится один раз и висит на
## витрине: при переключении машины включается нужный кузов.
func _show_vehicle(id: String) -> bool:
	var data: RallyVehicle = config.vehicle(id) if config != null else null
	if not _vehicle_models.has(id) and _vehicle_model(id) == null:
		# Модель не загрузилась — остаёмся на прежней машине, но не молчим.
		if data != null and not data.model_scene.is_empty():
			return false
	_vehicle_id = id
	_vehicle_selector.select(_vehicle_index(id))
	for key in _vehicle_models:
		(_vehicle_models[key] as Node3D).visible = key == id
	# Кузов сцены виден только у машины без своей модели.
	_model.visible = not _vehicle_models.has(id)
	_car_title.text = _vehicle_title(id)
	return true


## Кузов машины на витрине: своя модель из ресурса или кузов сцены (null).
func _vehicle_model(id: String) -> Node3D:
	if _vehicle_models.has(id):
		return _vehicle_models[id] as Node3D
	var data: RallyVehicle = config.vehicle(id) if config != null else null
	if data == null or data.model_scene.is_empty():
		return null
	var model := CarModels.make_model(id)
	if model == null:
		_status.text = "Не удалось загрузить модель: " + data.display_name
		return null
	_turntable.add_child(model)
	# Превью стоит на полу витрины, а не в координатах шасси.
	model.position = Vector3.ZERO
	model.visible = false
	_vehicle_models[id] = model
	return model


func _vehicle_title(id: String) -> String:
	var data: RallyVehicle = config.vehicle(id) if config != null else null
	return data.display_name if data != null else id.to_upper()


func _configure_preview_style() -> void:
	var selected_track: TrackType = null
	if game != null:
		selected_track = game.get("current_track") as TrackType
	if selected_track == null and config != null:
		selected_track = config.get_track(config.default_track_index) as TrackType
	var enabled: bool = selected_track != null and selected_track.ps1_style
	# Уменьшаем только 3D-превью; элементы меню остаются чёткими.
	_preview_container.stretch_shrink = layout().garage_retro_shrink if enabled else 1
	_preview_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if enabled else CanvasItem.TEXTURE_FILTER_PARENT_NODE
	_retro_rect.visible = enabled
	var material := _retro_rect.material as ShaderMaterial
	if material != null and selected_track != null:
		var cfg := layout()
		Ps1Materials.configure_post_effect(
			material, enabled, cfg.garage_retro_strength, float(cfg.garage_retro_resolution_y),
			selected_track.color_banding, selected_track.dither_fog
		)


func _process(delta: float) -> void:
	if visible and _turntable != null and not _dragging:
		_turntable.rotate_y(delta * turntable_speed())


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			_preview_container.accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_preview_camera.fov = maxf(layout().garage_preview_fov_min, _preview_camera.fov - layout().garage_preview_fov_step)
			_preview_container.accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_preview_camera.fov = minf(layout().garage_preview_fov_max, _preview_camera.fov + layout().garage_preview_fov_step)
			_preview_container.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_turntable.rotate_y(-event.relative.x * layout().garage_mouse_rotate_speed)
		_preview_container.accept_event()


## Число пунктов списка для текущей машины: у каждой машины свой набор.
func _setup_count() -> int:
	if game != null and game.has_method("setup_count"):
		return int(game.call("setup_count", _vehicle_id))
	return config.setup_count(_vehicle_id)


func _base_setup_count() -> int:
	return config.setup_count(_vehicle_id)


func _setup_at(index: int) -> SetupType:
	if game != null and game.has_method("get_custom_setup"):
		# Индекс идёт в той же нумерации, что и список выбранной машины.
		return game.call("get_custom_setup", index) as SetupType
	var original := config.get_setup(index, _vehicle_id) as SetupType
	return original.duplicate(true) as SetupType if original != null else null


func _rebuild_selector() -> void:
	_selector.clear()
	for i in range(_setup_count()):
		var preset := _setup_at(i)
		var prefix := "СВОЙ · " if i >= _base_setup_count() else "ГОТОВЫЙ · "
		_selector.add_item(prefix + (preset.display_name if preset != null else "—"), i)


func _select_setup(index: int) -> void:
	if config == null or index < 0 or index >= _setup_count():
		return
	var had_changes := not _dirty.is_empty()
	selected_index = index
	_creating = false
	_editing = index >= _base_setup_count()
	_dirty.clear()
	setup = _setup_at(index)
	if setup == null:
		return
	_name_input.text = setup.display_name
	_status.text = "Несохранённые изменения отменены." if had_changes else ("Свой пресет можно редактировать." if _editing else "Готовый пресет доступен только для просмотра.")
	_refresh()


func _create_copy() -> void:
	if setup == null:
		return
	setup = setup.duplicate(true) as SetupType
	_creating = true
	_editing = true
	_name_input.text = setup.display_name + " · МОЙ"
	_dirty.clear()
	_dirty[selected_index] = true
	_status.text = "Новая копия. Задайте название и сохраните её."
	_refresh()
	_name_input.grab_focus()


func _on_name_changed(_value: String) -> void:
	if not _updating and _editing:
		_mark_changed()


func _refresh() -> void:
	if setup == null:
		return
	_updating = true
	_selector.select(selected_index)
	_description.text = ("СВОЙ ПРЕСЕТ: " if _editing else "ГОТОВЫЙ ПРЕСЕТ: ") + setup.description
	var vehicle_data: RallyVehicle = config.vehicle(_vehicle_id) if config != null else null
	if vehicle_data != null and not vehicle_data.uses_livery_presets:
		_description.text += ("\nПресеты этой машины: свой мотор, свой ряд передач и своя"
			+ " подвеска. Окраска, ливреи и цвет дисков остаются у машины с"
			+ " поддержкой окраски.")
	_name_input.visible = _editing
	_save.visible = _editing
	_reset.visible = _editing
	_create.disabled = _creating
	_create.tooltip_text = "Сначала сохраните или отмените новую копию." if _creating else "Создать отдельную копию этого пресета."
	_summary.text = "%s\n%s  ·  %d кг  ·  %s" % [setup.get_engine_summary(), setup.get_drivetrain_name(), int(setup.vehicle_mass), setup.get_transmission_name()]
	for field: Dictionary in Customization.FIELDS:
		var key: String = field["key"]
		var kind: String = field["kind"]
		var control: Control = _controls[key]
		control.visible = _editing
		if _readonly_values.has(key):
			var readonly: Label = _readonly_values[key]
			readonly.visible = not _editing
			if kind == "choice":
				var options: Array = field["options"]
				readonly.text = String(options[clampi(int(setup.get(key)), 0, options.size() - 1)])
			elif kind == "toggle":
				readonly.text = "Вкл." if bool(setup.get(key)) else "Выкл."
			elif kind == "color":
				var color: Color = setup.get(key)
				readonly.text = "#" + color.to_html(false).to_upper()
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
	_model.position.y = _model_default_y + setup.tire_radius - layout().garage_reference_tire_radius
	CarVisuals.apply_body(_model, setup)
	var wheel_scale: Vector3 = CarVisuals.wheel_scale(setup.tire_radius, setup.tire_width)
	for i in range(_wheel_visuals.size()):
		_wheel_visuals[i].basis = _wheel_bases[i].scaled(wheel_scale)
		CarVisuals.apply_wheel(_wheel_visuals[i], setup)


func _mark_changed() -> void:
	_dirty[selected_index] = true
	_status.text = layout().garage_status_unsaved


func _on_slider_changed(value: float, key: String) -> void:
	if _updating or not _editing or setup == null or not _fields.has(key):
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
	if _updating or not _editing or setup == null:
		return
	setup.set(key, Customization.sanitize_value(_fields[key], value, setup.get(key)))
	if key == "torque_shape":
		# В RallyCar непустая пользовательская Curve важнее формы.
		# Вернуть исходную кривую можно первым пунктом списка.
		var base: SetupType = (
			game.call("get_setup_base", selected_index) as SetupType
			if game != null and game.has_method("get_setup_base")
			else config.get_setup(selected_index, _vehicle_id) as SetupType
		)
		setup.torque_curve = base.torque_curve.duplicate() as Curve if value == SetupType.TorqueShape.CUSTOM and base.torque_curve != null else null
	_mark_changed()
	_refresh()


func _on_toggle_changed(value: bool, key: String) -> void:
	if _updating or not _editing or setup == null:
		return
	setup.set(key, value)
	_mark_changed()
	_refresh()


func _on_custom_color_changed(color: Color, key: String) -> void:
	if _updating or not _editing or setup == null:
		return
	setup.set(key, Customization.sanitize_value(_fields[key], color, setup.get(key)))
	_mark_changed()
	_update_preview()


# Совместимость с прежним обработчиком настройки цвета.
func _on_color_changed(color: Color) -> void:
	_on_custom_color_changed(color, "body_color")


func _save_drafts() -> bool:
	if not _editing:
		return true
	if _name_input.text.strip_edges().is_empty():
		_status.text = "Введите название своего пресета."
		_name_input.grab_focus()
		return false
	if game == null or not game.has_method("save_user_setup"):
		_status.text = layout().garage_status_storage_missing
		return false
	var index := int(game.call("save_user_setup", selected_index, setup, _name_input.text, _creating))
	if index < 0:
		_status.text = layout().garage_status_save_failed
		return false
	_dirty.clear()
	_rebuild_selector()
	_select_setup(index)
	_status.text = "Свой пресет сохранён. Готовые пресеты не изменены."
	setup_saved.emit(selected_index)
	return true


func _save_button_pressed() -> void:
	_save_drafts()


func _start_race() -> void:
	if setup == null:
		return
	if _editing and (_creating or not _dirty.is_empty()) and not _save_drafts():
		return
	start_requested.emit(selected_index, setup)


func _reset_setup() -> void:
	if not _editing:
		return
	_select_setup(selected_index)
	_status.text = "Несохранённые изменения отменены."


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_request_back()
		get_viewport().set_input_as_handled()
