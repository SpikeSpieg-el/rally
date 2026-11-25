## Экран подготовки машины: 3D-гараж во весь экран, минимум меню и выноски-
## инфографика от частей машины (мотор — от капота, подвеска — от стойки
## переднего колеса, шины — от заднего колеса, привод — от заднего моста,
## внешность — от двери). Нажатие на выноску открывает панель настроек этой
## части, камера подъезжает к ней. Витрина и автомобиль заезда используют одну
## реализацию внешности; готовые пресеты доступны только для просмотра.
##
## Порядок: сначала трасса, потом машина и характеристики. На фазе трассы
## машина остаётся на витрине за доской, камера доски интерактивна
## (перетаскивание — панорама, колесо — масштаб, стрелки — листать) и сама
## вписывает доску в видимую часть кадра справа от левой панели, а внизу
## дублирует выбор 2D-лентой кнопок — первую трассу можно выбрать всегда.
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
const LayoutType = preload("res://scripts/ui/rally_screen_layout.gd")
const MenuLayoutType = preload("res://scripts/data/rally_menu_layout.gd")

@export_group("Инспектор: витрина")
## Скорость вращения витрины, радиан/сек. −1 — брать из layout, как и раньше;
## иначе значение перекрывает ресурс. Диапазон включает «не задано».
@export_range(-1.0, 1.0, 0.01) var turntable_speed_override: float = -1.0
## Цвета и размеры шрифтов. Пусто — res://data/ui/default_ui_theme.tres.
@export var ui_theme: UiThemeType = null
## Тексты и подсказки гаража. Пусто — res://data/ui/default_menu_layout.tres.
@export var menu_layout: MenuLayoutType = null
## Насколько машина покачивается на поворотном круге, градусы (0 — стоит).
@export_range(0.0, 90.0, 1.0, "suffix:°") var sway_amplitude_deg: float = 0.0
## Через сколько секунд после вращения мышью машина снова покачивается.
@export_range(0.0, 30.0, 0.5, "suffix:с") var sway_resume_sec: float = 3.0
## Насколько камера подъезжает к выбранной части (доля исходной дистанции).
## Карточки выносок настраиваются на узле %Callouts (GarageCallouts).
@export_range(0.2, 1.0, 0.01) var focus_distance: float = 0.8

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
## Метка витрины: список словарей {node, rest} — колёса одной модели и их
## исходный basis. Каждой модели кладутся свои колёса, чтобы крутить и красить
## только видимую машину, а не все кузова сразу.
const WHEELS_META := "vitrine_wheels"
## Колёса стандартной сцены витрины (кузов Lancer): запасной список, когда у
## машины нет своей модели и имена неоткуда взять (см. CarModels.WHEEL_META).
const SCENE_WHEEL_NAMES := ["Mitsubishi_Wheel_Ft_L", "Mitsubishi_Wheel_Ft_R", "Mitsubishi_Wheel_Bk_L", "Mitsubishi_Wheel_Bk_R"]
var _model_default_y: float = 0.0
## Кузова машин, у которых есть своя модель: id → узел на витрине.
## Кузов сцены (%PreviewModel) показывается, пока витрина машины не загружена.
var _vehicle_models: Dictionary = {}
var _vehicle_id: String = "mitsubishi"

## Открытая панель части машины (id группы), пусто — панель закрыта.
var _active_group := ""
var _base_yaw := 0.0
var _sway_phase := 0.0
var _idle_time := 0.0
var _cam_home_target := Vector3(0.0, 0.65, 0.0)
var _cam_dir := Vector3(0.6, 0.35, 0.7)
var _cam_home_dist := 9.5
var _cam_target := Vector3.ZERO
var _cam_dist := 9.5
var _cam_shift := 0.0
var _cam_home_dir := Vector3(0.6, 0.35, 0.7)
## Фаза гаража: true — выбор трассы у 3D-доски, false — машина (основной гараж).
var _track_phase := false
var _track_pose_target := Vector3.ZERO
var _track_pose_dir := Vector3(0.0, 0.3, 1.0)
var _track_pose_dist := 6.0
## Интерактивная камера доски: панорама по X (мир, сдвиг цели и камеры),
## зум (множитель дистанции) и их плавные цели. Камера сама вписывает доску
## в видимую часть кадра справа от левой панели и догоняет подсветку, если
## плита уехала за край — иначе первые трассы не выбрать.
var _track_pan := 0.0
var _track_pan_target := 0.0
var _track_zoom := 1.0
var _track_zoom_target := 1.0
## Клик против перетаскивания на доске: нажатие запоминается, выбор — только
## если мышь почти не сдвинулась; иначе это панорама камеры.
var _track_press_pos := Vector2.ZERO
var _track_pressing := false
var _track_panning := false
## 2D-лента трасс внизу (страховка, если 3D-плита недоступна): кнопки
## по числу трасс, наведение подсвечивает, клик выбирает.
var _track_strip: VBoxContainer = null
var _track_strip_box: HBoxContainer = null
var _track_strip_buttons: Array[Button] = []
var _track_strip_hint: Label = null


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
@onready var _car_title: Label = %CarTitle
# 3D-бокс — отдельная сцена scenes/garage_showroom.tscn: её удобно править во
# вкладке 3D редактора. Уникальные имена ищем внутри неё.
@onready var _showroom: Node3D = $Preview/Viewport/Showroom
@onready var _model: Node3D = _showroom.get_node("%PreviewModel")
@onready var _turntable: Node3D = _showroom.get_node("%Turntable")
@onready var _start: Button = %StartButton
@onready var _preview_container: SubViewportContainer = %Preview
@onready var _preview_viewport: SubViewport = $Preview/Viewport
@onready var _preview_camera: Camera3D = _showroom.get_node("%Camera")
@onready var _retro_rect: ColorRect = %RetroShaderRect
@onready var _callouts: GarageCallouts = %Callouts
@onready var _detail_panel: PanelContainer = %DetailPanel
@onready var _panel_title: Label = %PanelTitle
# Доска выбора трассы и панель условий — в той же витрине; узлы из сцен.
@onready var _track_board: GarageTrackBoard = _showroom.get_node_or_null("TrackBoard") as GarageTrackBoard
@onready var _track_panel: GarageTrackPanel = %TrackPanel
@onready var _back_button: Button = %BackButton
@onready var _hint: Label = %Hint


func _ready() -> void:
	# Телефон/браузер: крупнее шрифты и строки (см. RallyUiTheme.ui_scale).
	# Ставим ДО `_build_settings()`: строки настроек читают размеры из темы.
	theme_cfg().ui_scale = LayoutType.ui_scale()
	_build_settings()
	_fill_vehicle_selector()
	_vehicle_selector.item_selected.connect(_select_vehicle)
	_selector.item_selected.connect(_select_setup)
	_create.pressed.connect(_create_copy)
	_name_input.text_changed.connect(_on_name_changed)
	%ResetButton.pressed.connect(_reset_setup)
	%SaveButton.pressed.connect(_save_button_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	if _track_board != null:
		_track_board.focus_changed.connect(_on_track_focus_changed)
		_track_board.track_chosen.connect(_choose_track)
	%ControlsButton.pressed.connect(func() -> void: controls_requested.emit())
	_start.pressed.connect(_start_race)
	%PrevCar.pressed.connect(func() -> void: _step_vehicle(-1))
	%NextCar.pressed.connect(func() -> void: _step_vehicle(1))
	%ClosePanel.pressed.connect(close_group)
	_preview_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview_container.gui_input.connect(_on_preview_input)
	_build_track_strip()
	_model_default_y = _model.position.y
	_track_wheels(_model, SCENE_WHEEL_NAMES)
	_init_camera_rig()
	_callouts.camera = _preview_camera
	_callouts.viewport = _preview_viewport
	_callouts.part_pressed.connect(_on_part_pressed)


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
	close_group()
	_callouts.reset_layout()
	_dirty.clear()
	_status.text = "Выберите пресет или создайте свой на его основе."
	_rebuild_selector()
	show()
	_select_setup(clampi(index, 0, maxi(0, _setup_count() - 1)))
	_track_panel.open(config, game, theme_cfg(), layout())
	_enter_track_phase()


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
		if data != null and not data.race_scene.is_empty():
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
	if data == null or data.race_scene.is_empty():
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
	# Имена колёс берём из самой машины: список сцены витрины — только запасной
	# вариант для кузова без своей модели.
	var wheel_names: Array = model.get_meta(CarModels.WHEEL_META, [])
	_track_wheels(model, wheel_names if not wheel_names.is_empty() else SCENE_WHEEL_NAMES)
	return model


## Запоминает колёса модели по именам из ресурса машины; отсутствующие пропускает.
## Колёса кладутся в метку самой модели (WHEELS_META), поэтому витрина крутит и
## красит только видимую машину, а не все загруженные кузова сразу.
func _track_wheels(model: Node3D, names: Array) -> void:
	var wheels: Array[Dictionary] = []
	for wheel_name in names:
		var wheel := model.find_child(String(wheel_name), true, false) as Node3D
		if wheel != null:
			wheels.append({"node": wheel, "rest": wheel.basis})
	model.set_meta(WHEELS_META, wheels)


## Колёса одной модели витрины, запомненные в её метке WHEELS_META.
func _model_wheels(model: Node3D) -> Array[Dictionary]:
	if model == null or not model.has_meta(WHEELS_META):
		return []
	return model.get_meta(WHEELS_META) as Array[Dictionary]


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
	# Не material: это свойство Control, и локальная переменная с тем же
	# именем даёт предупреждение о затенении на каждом кадре.
	var retro := _retro_rect.material as ShaderMaterial
	if retro != null and selected_track != null:
		var cfg := layout()
		Ps1Materials.configure_post_effect(
			retro, enabled, cfg.garage_retro_strength, float(cfg.garage_retro_resolution_y),
			selected_track.color_banding, selected_track.dither_fog
		)


func _process(delta: float) -> void:
	if not visible or _turntable == null:
		return
	_update_turntable(delta)
	_update_camera_rig(delta)
	var model := _active_model()
	_callouts.model = model
	_callouts.wheels = _model_wheels(model)
	_callouts.active_part = _active_group
	var panel_rect := _detail_panel.get_global_rect()
	_callouts.focus_point = Vector2(panel_rect.position.x, panel_rect.position.y + 26.0)
	_callouts.tick(delta)


func _on_preview_input(event: InputEvent) -> void:
	if _track_phase:
		_on_track_board_input(event)
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			_idle_time = 0.0
			_preview_container.accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_preview_camera.fov = maxf(layout().garage_preview_fov_min, _preview_camera.fov - layout().garage_preview_fov_step)
			_preview_container.accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_preview_camera.fov = minf(layout().garage_preview_fov_max, _preview_camera.fov + layout().garage_preview_fov_step)
			_preview_container.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_base_yaw -= event.relative.x * layout().garage_mouse_rotate_speed
		_sway_phase = 0.0
		_idle_time = 0.0
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


## Ливреи берутся из игровой сцены выбранной машины, а не из общего списка.
func _livery_textures() -> Array:
	var model: Node3D = _vehicle_models.get(_vehicle_id) as Node3D
	return model.get_meta("livery_textures", []) if model != null else []


func _livery_labels() -> Array[String]:
	var labels: Array[String] = []
	var textures := _livery_textures()
	var model: Node3D = _vehicle_models.get(_vehicle_id) as Node3D
	var names: Array = model.get_meta("livery_names", []) if model != null else []
	for i in range(textures.size()):
		var label := String(names[i]).strip_edges() if i < names.size() else ""
		var texture := textures[i] as Texture2D
		if label.is_empty() and texture != null:
			label = texture.resource_path.get_file().get_basename()
		labels.append(label if not label.is_empty() else "Ливрея %d" % (i + 1))
	if labels.is_empty():
		labels.append("Заводская")
	return labels


func _refresh() -> void:
	if setup == null:
		return
	_updating = true
	_selector.select(selected_index)
	_description.text = ("СВОЙ ПРЕСЕТ: " if _editing else "ГОТОВЫЙ ПРЕСЕТ: ") + setup.description
	var livery_labels := _livery_labels()
	var livery_choice := _controls["livery"] as OptionButton
	livery_choice.clear()
	for label in livery_labels:
		livery_choice.add_item(label)
	livery_choice.disabled = _livery_textures().is_empty()
	# У машины без ливрей (Golf) пункт остаётся, но объясняет, почему он не нажимается.
	livery_choice.tooltip_text = (
		"У этой машины нет ливрей: кузов красится цветом из пресета."
		if livery_choice.disabled else "Ливрея кузова из списка выбранной машины."
	)
	_name_input.visible = _editing
	# Кнопки пресетов — только у машины: на фазе трассы их не показывает
	# ни _set_car_ui, ни обновление пресета.
	_save.visible = _editing and not _track_phase
	_reset.visible = _editing and not _track_phase
	_create.disabled = _creating
	_create.tooltip_text = "Сначала сохраните или отмените новую копию." if _creating else "Создать отдельную копию этого пресета."
	_summary.text = "%s\n%s  ·  %d кг" % [setup.get_engine_summary(), setup.get_drivetrain_name(), int(setup.vehicle_mass)]
	for field: Dictionary in Customization.FIELDS:
		var key: String = field["key"]
		var kind: String = field["kind"]
		var control: Control = _controls[key]
		control.visible = _editing
		if _readonly_values.has(key):
			var readonly: Label = _readonly_values[key]
			readonly.visible = not _editing
			if kind == "choice":
				var options: Array = livery_labels if key == "livery" else field["options"]
				var selected: int = int(setup.get(key))
				readonly.text = String(options[selected if selected >= 0 and selected < options.size() else 0])
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
			var choice := control as OptionButton
			var selected: int = int(setup.get(key))
			choice.select(selected if selected >= 0 and selected < choice.item_count else 0)
		elif kind == "toggle":
			(control as CheckButton).button_pressed = bool(setup.get(key))
		elif kind == "color":
			(control as ColorPickerButton).color = setup.get(key)
	_update_preview()
	_refresh_cards()
	_updating = false


func _format_number(value: float, field: Dictionary) -> String:
	var display_scale: float = float(field.get("display_scale", 1.0))
	var step: float = float(field["step"]) * display_scale
	var decimals := 0
	if step < 0.01:
		decimals = 3
	elif step < 0.1:
		decimals = 2
	elif step < 1.0:
		decimals = 1
	var format := "%0." + str(decimals) + "f"
	var text: String = format % (value * display_scale)
	var unit: String = field.get("unit", "")
	return text if unit.is_empty() else text + " " + unit


func _update_preview() -> void:
	if _model == null or setup == null:
		return
	_model.position.y = _model_default_y + setup.tire_radius - layout().garage_reference_tire_radius
	# Краска идёт на видимую модель: витрину выбранной машины или кузов сцены.
	var active_model := _vehicle_models.get(_vehicle_id, _model) as Node3D
	CarVisuals.apply_body(active_model, setup, _livery_textures())
	var wheel_scale: Vector3 = CarVisuals.wheel_scale(setup.tire_radius, setup.tire_width)
	# Колёса берём из самой видимой модели: их список она запомнила при загрузке.
	for entry: Dictionary in _model_wheels(active_model):
		var wheel := entry.get("node") as Node3D
		var rest := entry.get("rest") as Basis
		if wheel == null or not is_instance_valid(wheel):
			continue
		wheel.basis = rest.scaled(wheel_scale)
		if wheel is MeshInstance3D:
			CarVisuals.apply_wheel(wheel as MeshInstance3D, setup)
		for mesh in wheel.find_children("*", "MeshInstance3D", true, false):
			CarVisuals.apply_wheel(mesh as MeshInstance3D, setup)


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
	if key == "livery" and (value < 0 or value >= _livery_textures().size()):
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
	_refresh_cards()


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
	if not visible:
		return
	if _track_phase:
		# Клавиатура и геймпад: стрелки двигают подсветку доски, Enter — выбор.
		if event.is_action_pressed("ui_left") and _track_board != null:
			_track_board.step_focus(-1)
		elif event.is_action_pressed("ui_right") and _track_board != null:
			_track_board.step_focus(1)
		elif event.is_action_pressed("ui_accept") and _track_board != null:
			_track_board.choose_focused()
		elif event.is_action_pressed("ui_cancel"):
			_request_back()
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		# Esc сначала закрывает панель части, потом возвращает к выбору трассы.
		if not _active_group.is_empty():
			close_group()
		else:
			_enter_track_phase()
		get_viewport().set_input_as_handled()


## Фаза 1: камера у доски трасс, слева панель условий. Машина остаётся на
## витрине за доской — она не мешает плитам, а гараж без машины выглядит пустым.
func _enter_track_phase() -> void:
	if config == null or _track_board == null or _track_panel == null:
		return
	_track_phase = true
	close_group()
	var names := PackedStringArray()
	for i in range(config.track_count()):
		var track := config.get_track(i) as TrackType
		names.append(track.display_name if track != null else "—")
	_track_board.visible = true
	_track_board.build(names, _track_panel.selected_track)
	_track_panel.visible = true
	_set_car_ui(false)
	_turntable.visible = true
	_reset_track_camera()
	_back_button.text = "◀  НАЗАД"
	_update_track_pose()
	_refresh_track_strip()
	_ensure_focus_visible()


## Фаза 2: камера переезжает к машине, выбор трассы остаётся в панели условий.
func _enter_car_phase() -> void:
	_track_phase = false
	_track_pressing = false
	_track_panning = false
	if _track_board != null:
		_track_board.visible = false
	if _track_panel != null:
		_track_panel.visible = false
	if _track_strip != null:
		_track_strip.visible = false
	_turntable.visible = true
	_set_car_ui(true)
	_back_button.text = "◀  К ТРАССЕ"


## Выбор трассы (клик, Enter или геймпад): записать в RallyGame и ехать к машине.
func _choose_track(index: int) -> void:
	if not _track_phase or _track_board == null:
		return
	_track_board.set_focus(index)
	_track_panel.select_track(index)
	_enter_car_phase()


func _on_track_focus_changed(index: int) -> void:
	if _track_panel != null:
		_track_panel.preview_track(index)
	_refresh_track_strip()
	_ensure_focus_visible()


## Кнопка внизу: в фазе трассы — выход из гаража, у машины — назад к трассе.
func _on_back_pressed() -> void:
	if _track_phase:
		_request_back()
	else:
		_enter_track_phase()


## Элементы машины видны только во второй фазе; панель части закрывается отдельно.
## Кнопки пресетов (Сохранить/Отменить) — тоже только у машины: на доске
## внизу остаётся только Назад и Управление.
func _set_car_ui(on: bool) -> void:
	for path in ["TopLeft", "TopRight"]:
		var node := get_node_or_null(path) as CanvasItem
		if node != null:
			node.visible = on
	if _callouts != null:
		_callouts.visible = on
	if _hint != null:
		_hint.visible = on
	_start.visible = on
	_status.visible = on
	_reset.visible = on and _editing
	_save.visible = on and _editing


func _on_track_board_input(event: InputEvent) -> void:
	if _track_board == null:
		return
	if event is InputEventMouseMotion:
		if _track_pressing and not _track_panning:
			if event.position.distance_to(_track_press_pos) > 6.0:
				_track_panning = true
		if _track_panning:
			# Перетаскивание доски: камера едет за мышью (захват, как карта).
			var limit := _track_pan_limit()
			_track_pan_target = clampf(
				_track_pan_target - event.relative.x * _track_world_per_pixel(),
				-limit, limit
			)
			_preview_container.accept_event()
			return
		var hover := _track_board.pick(_preview_camera, _viewport_point(event.position))
		if hover >= 0:
			_track_board.set_focus(hover)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_track_pressing = true
				_track_panning = false
				_track_press_pos = event.position
			elif _track_pressing:
				# Отпустили без сдвига — это клик по плите, а не панорама.
				if not _track_panning:
					var hit := _track_board.pick(_preview_camera, _viewport_point(event.position))
					if hit >= 0:
						_choose_track(hit)
				_track_pressing = false
				_track_panning = false
			_preview_container.accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_track_zoom_target = clampf(_track_zoom_target * 0.9, 0.55, 2.2)
			_preview_container.accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_track_zoom_target = clampf(_track_zoom_target * 1.1, 0.55, 2.2)
			_preview_container.accept_event()


## Сколько метров доски приходится на пиксель контейнера превью.
func _track_world_per_pixel() -> float:
	var container_size := _preview_container.size
	if container_size.x <= 0.0:
		return 0.01
	return _track_visible_width() / container_size.x


## Ширина кадра в метрах на дистанции доски (по вертикальному FOV и аспекту).
func _track_visible_width() -> float:
	var half := tan(deg_to_rad(_preview_camera.fov) * 0.5) * _track_fit_dist() * _track_zoom
	return half * 2.0 * _view_aspect()


## Предел панорамы: камера не улетает дальше размаха плит от центра доски.
func _track_pan_limit() -> float:
	if _track_board == null:
		return 6.0
	var span := _track_board.board_span()
	return maxf((span.y - span.x) * 0.5 + 1.5, 1.5)


## Сброс панорамы и зума к вписанной доске.
func _reset_track_camera() -> void:
	_track_pan = 0.0
	_track_pan_target = 0.0
	_track_zoom = 1.0
	_track_zoom_target = 1.0
	_track_pressing = false
	_track_panning = false


## Доля ширины экрана, занятая левой панелью условий (0 — панели нет).
func _track_panel_fraction() -> float:
	if _track_panel == null or not _track_panel.visible:
		return 0.0
	var container_size := _preview_container.size
	if container_size.x <= 0.0:
		return 0.0
	var panel_rect := _track_panel.get_global_rect()
	var container_rect := _preview_container.get_global_rect()
	var right := panel_rect.position.x + panel_rect.size.x - container_rect.position.x
	return clampf(right / container_size.x, 0.0, 0.6)


## Дистанция, на которой вся доска влезает в видимую часть кадра
## (справа от левой панели). Минимум — поза из сцены.
func _track_fit_dist() -> float:
	if _track_board == null:
		return _track_pose_dist
	var span := _track_board.board_span()
	var board_width: float = span.y - span.x + 1.6
	var visible_fraction: float = 1.0 - _track_panel_fraction()
	if visible_fraction < 0.4:
		visible_fraction = 0.4
	var needed_width: float = board_width / visible_fraction
	var half := tan(deg_to_rad(_preview_camera.fov) * 0.5) * _view_aspect()
	if half <= 0.001:
		return _track_pose_dist
	return maxf(_track_pose_dist, needed_width / (half * 2.0))


## Если подсвеченная плита уехала за панель или за край экрана (стрелки,
## геймпад, лента), камера плавно догоняет её. Наведение под курсором
## камеру не трогает — плита и так под мышью. Проверка аналитическая
## (без проекции камеры), поэтому работает и пока камера ещё едет к доске.
func _ensure_focus_visible() -> void:
	if not _track_phase or _track_board == null:
		return
	var index: int = _track_board.focus_index
	if index < 0 or index >= _track_board.pad_count():
		return
	var visible_width := _track_visible_width()
	var fraction := _track_panel_fraction()
	var panel_shift: float = fraction * 0.5 * visible_width
	var half_visible: float = visible_width * (1.0 - fraction) * 0.5 - 0.8
	if half_visible < 0.5:
		half_visible = 0.5
	var offset: float = _track_board.pad_local_x(index) - _track_pan - panel_shift
	if absf(offset) > half_visible:
		var limit := _track_pan_limit()
		_track_pan_target = clampf(_track_board.pad_local_x(index) - panel_shift, -limit, limit)


## Точка в координатах контейнера -> в координатах вьюпорта витрины.
func _viewport_point(local: Vector2) -> Vector2:
	var container_size := _preview_container.size
	if container_size.x <= 0.0 or container_size.y <= 0.0:
		return local
	return local * (Vector2(_preview_viewport.size) / container_size)


## Поза камеры у доски берётся из узла TrackBoard (camera_target / camera_offset).
func _update_track_pose() -> void:
	if _track_board == null:
		return
	_track_pose_target = _track_board.camera_pose_target()
	var offset := _track_board.camera_pose_offset()
	_track_pose_dist = maxf(offset.length(), 0.5)
	_track_pose_dir = offset.normalized() if offset.length() > 0.01 else Vector3(0.0, 0.3, 1.0).normalized()


## 2D-лента трасс: кнопки по числу трасс справа от левой панели, над нижней
## полосой. 3D-доска может оказаться недоступна (плита за панелью, узкий
## экран, геймпад без мыши) — лента гарантирует, что первую трассу можно
## выбрать всегда. Наведение подсвечивает плиту, клик выбирает её.
func _build_track_strip() -> void:
	var strip := VBoxContainer.new()
	strip.name = "TrackStrip"
	strip.visible = false
	strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_left = 480.0
	strip.offset_top = -150.0
	strip.offset_right = -48.0
	strip.offset_bottom = -92.0
	strip.add_theme_constant_override("separation", 4)
	add_child(strip)
	_track_strip = strip
	_track_strip_hint = Label.new()
	_track_strip_hint.text = "ТЯНИТЕ — КАМЕРА  ·  КОЛЕСО — МАСШТАБ  ·  КЛИК ПО ПЛИТЕ ИЛИ КНОПКЕ — ВЫБРАТЬ  ·  ←/→ — ЛИСТАТЬ"
	_track_strip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_track_strip_hint.add_theme_color_override("font_color", Color(0.45, 0.53, 0.6, 1.0))
	_track_strip_hint.add_theme_font_size_override("font_size", 12)
	strip.add_child(_track_strip_hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_child(row)
	var prev := Button.new()
	prev.text = "◀"
	prev.custom_minimum_size = Vector2(44, 40)
	prev.tooltip_text = "Предыдущая трасса"
	# Фокус не забираем: стрелки всегда листают доску, а не кнопки ленты.
	prev.focus_mode = Control.FOCUS_NONE
	prev.pressed.connect(func() -> void: _step_track(-1))
	row.add_child(prev)
	var tracks_box := HBoxContainer.new()
	tracks_box.name = "TrackButtons"
	tracks_box.add_theme_constant_override("separation", 6)
	tracks_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tracks_box)
	_track_strip_box = tracks_box
	var next := Button.new()
	next.text = "▶"
	next.custom_minimum_size = Vector2(44, 40)
	next.tooltip_text = "Следующая трасса"
	next.focus_mode = Control.FOCUS_NONE
	next.pressed.connect(func() -> void: _step_track(1))
	row.add_child(next)
	# Кнопки трасс пересобираются при каждом открытии (число трасс из конфига).
	_track_strip_buttons.clear()


## Пересобрать кнопки ленты под текущий список трасс и подсветить фокус.
func _refresh_track_strip() -> void:
	if _track_strip == null or config == null:
		return
	_track_strip.visible = _track_phase
	if not _track_phase:
		return
	var tracks_box := _track_strip_box
	if tracks_box == null:
		return
	if _track_strip_buttons.size() != config.track_count():
		for button in _track_strip_buttons:
			tracks_box.remove_child(button)
			button.queue_free()
		_track_strip_buttons.clear()
		for i in range(config.track_count()):
			var track := config.get_track(i) as TrackType
			var button := Button.new()
			button.text = track.display_name if track != null else "—"
			button.custom_minimum_size = Vector2(150, 40)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.clip_text = true
			button.tooltip_text = button.text
			button.focus_mode = Control.FOCUS_NONE
			button.add_theme_font_size_override("font_size", 13)
			button.mouse_entered.connect(_on_track_strip_hover.bind(i))
			button.pressed.connect(_on_track_strip_pressed.bind(i))
			tracks_box.add_child(button)
			_track_strip_buttons.append(button)
	var focus: int = _track_board.focus_index if _track_board != null else -1
	for i in range(_track_strip_buttons.size()):
		_track_strip_buttons[i].modulate = (
			Color(1.0, 0.62, 0.15, 1.0) if i == focus else Color(1.0, 1.0, 1.0, 1.0)
		)


## Стрелки ленты: подсветка по кругу, как на доске.
func _step_track(step: int) -> void:
	if _track_board != null and _track_phase:
		_track_board.step_focus(step)


## Наведение на кнопку ленты: показать карточку трассы, не выбирая её.
func _on_track_strip_hover(index: int) -> void:
	if _track_phase and _track_board != null:
		_track_board.set_focus(index)


## Клик по кнопке ленты: выбрать трассу, как клик по 3D-плите.
func _on_track_strip_pressed(index: int) -> void:
	if _track_phase:
		_choose_track(index)


## Трасса для запуска: та, что выбрана в панели (меню берёт её после start_requested).
func current_track() -> TrackType:
	if _track_panel == null:
		return null
	return _track_panel.selected_track_resource()


## Перед стартом: трасса, условия и марафон уходят в RallyGame.
func prepare_race() -> void:
	if _track_panel != null:
		_track_panel.prepare_race()


# ---------------------------------------------------------------------------
# Поворотный круг и камера
# ---------------------------------------------------------------------------


## Камера смотрит на машину из точки, заданной в сцене (узел Camera); дальше её
## ведёт скрипт: подъезд к выбранной части и сдвиг вбок под панель настроек.
func _init_camera_rig() -> void:
	# Кадр берём таким, каким камера выставлена в garage_showroom.tscn: центр
	# облёта — точка на луче взгляда напротив оси поворотного круга.
	var forward := -_preview_camera.transform.basis.z.normalized()
	var axis_point := Vector3(_turntable.position.x, _cam_home_target.y, _turntable.position.z)
	var reach := maxf((axis_point - _preview_camera.position).dot(forward), 1.0)
	_cam_home_target = _preview_camera.position + forward * reach
	var offset := _preview_camera.position - _cam_home_target
	_cam_home_dist = maxf(offset.length(), 1.0)
	_cam_dir = offset / _cam_home_dist
	_cam_target = _cam_home_target
	_cam_dist = _cam_home_dist
	# Угол машины в покое — поворот Turntable в garage_showroom.tscn.
	_base_yaw = _turntable.rotation.y
	_cam_home_dir = _cam_dir
	_place_camera()


func _update_turntable(delta: float) -> void:
	if _dragging:
		_turntable.rotation.y = _base_yaw
		return
	_idle_time += delta
	# Пока открыта панель части, машина стоит: выноска не уезжает.
	if _active_group.is_empty() and _idle_time >= sway_resume_sec:
		_sway_phase += delta * turntable_speed() * 3.0
	var target := _base_yaw + sin(_sway_phase) * deg_to_rad(sway_amplitude_deg)
	_turntable.rotation.y = lerp_angle(_turntable.rotation.y, target, 1.0 - exp(-delta * 6.0))


func _update_camera_rig(delta: float) -> void:
	var target := _cam_home_target
	var dist := _cam_home_dist
	var dir := _cam_home_dir
	var shift := 0.0
	if _track_phase:
		# Доска вписывается в видимую часть кадра справа от левой панели:
		# дистанция — по размаху плит, центр — сдвинут вправо на долю панели,
		# плюс панорама и зум пользователя. Цель и камера сдвигаются вместе,
		# поэтому направление взгляда не меняется.
		var track_k := 1.0 - exp(-delta * 6.0)
		_track_pan = lerpf(_track_pan, _track_pan_target, track_k)
		_track_zoom = lerpf(_track_zoom, _track_zoom_target, track_k)
		dist = _track_fit_dist() * _track_zoom
		dir = _track_pose_dir
		var visible_width: float = tan(deg_to_rad(_preview_camera.fov) * 0.5) * 2.0 * dist * _view_aspect()
		var panel_shift: float = _track_panel_fraction() * 0.5 * visible_width
		target = _track_pose_target + Vector3(panel_shift + _track_pan, 0.0, 0.0)
	elif not _active_group.is_empty():
		var anchors := _callouts.part_anchors()
		if anchors.has(_active_group):
			var part: Vector3 = anchors[_active_group]
			target = _cam_home_target.lerp(part, 0.3)
		dist = _cam_home_dist * focus_distance
		# Панель настроек справа: машина уходит в левую половину кадра.
		var half_height := tan(deg_to_rad(_preview_camera.fov) * 0.5) * dist
		shift = half_height * _view_aspect() * 0.36
	var k := 1.0 - exp(-delta * 4.0)
	_cam_target = _cam_target.lerp(target, k)
	_cam_dist = lerpf(_cam_dist, dist, k)
	_cam_shift = lerpf(_cam_shift, shift, k)
	_cam_dir = _cam_dir.lerp(dir, k).normalized()
	_place_camera()


func _place_camera() -> void:
	_preview_camera.position = _cam_target + _cam_dir * _cam_dist
	_preview_camera.look_at(_cam_target, Vector3.UP)
	_preview_camera.h_offset = _cam_shift


func _view_aspect() -> float:
	var viewport_size := Vector2(_preview_viewport.size)
	return viewport_size.x / maxf(viewport_size.y, 1.0)


func _active_model() -> Node3D:
	return _vehicle_models.get(_vehicle_id, _model) as Node3D


## Соседняя машина по стрелкам ◀ ▶ у названия.
func _step_vehicle(step: int) -> void:
	var ids := _vehicle_ids()
	if ids.is_empty():
		return
	_select_vehicle(posmod(_vehicle_index(_vehicle_id) + step, ids.size()))
	_callouts.reset_layout()


# ---------------------------------------------------------------------------
# Панель настроек части машины
# ---------------------------------------------------------------------------


func _on_part_pressed(id: String) -> void:
	if _active_group == id:
		close_group()
	else:
		open_group(id)


## Открыть панель настроек части машины (id группы из car_customization.gd):
## камера подъезжает к детали, остальные выноски прячутся.
func open_group(id: String) -> void:
	var index := -1
	for i in range(Customization.GROUPS.size()):
		if String(Customization.GROUPS[i]["id"]) == id:
			index = i
	if index < 0:
		return
	_active_group = id
	_tabs.current_tab = index
	var caption: String = Customization.GROUPS[index]["title"]
	_panel_title.text = String(GarageCallouts.PART_CAPTIONS.get(id, caption))
	_detail_panel.show()
	_idle_time = 0.0


func close_group() -> void:
	_active_group = ""
	if _detail_panel != null:
		_detail_panel.hide()


## Цифры на карточках выносок — из текущего пресета.
func _refresh_cards() -> void:
	if setup == null or _callouts == null:
		return
	var finishes: Array = []
	for field: Dictionary in Customization.FIELDS:
		if field["key"] == "paint_finish":
			finishes = field["options"]
	_callouts.refresh(setup, _livery_labels(), finishes)
