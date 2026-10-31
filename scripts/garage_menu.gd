## Экран подготовки машины перед стартом. Превью использует те же меши,
## что и автомобиль на трассе, но без физики, звука и камер заезда.
extends Control

signal back_requested
signal start_requested(index: int, setup: RallyCarSetup)

const SetupType = preload("res://scripts/data/rally_car_setup.gd")
## Скорость вращения витрины, радиан/сек. 0 — остановить модель.
@export_range(0.0, 1.0, 0.01) var turntable_speed: float = 0.16

var config: RallyGameConfig
var game: Node
var selected_index := 0
var drafts: Dictionary = {}
var setup: SetupType
var _updating := false
@onready var _selector: OptionButton = %SetupSelector
@onready var _color_picker: ColorPickerButton = %BodyColor
@onready var _summary: Label = %Summary
@onready var _description: Label = %Description
@onready var _model: Node3D = %PreviewModel
@onready var _turntable: Node3D = %Turntable
@onready var _start: Button = %StartButton
var _values: Dictionary = {}
var _sliders: Dictionary = {}
var _wheels: Array[Node3D] = []
var _wheel_visuals: Array[Node3D] = []
var _wheel_bases: Array[Basis] = []
var _model_default_y: float = 0.0


func _ready() -> void:
	_sliders = {
		"max_torque": %TorqueSlider,
		"final_drive": %FinalDriveSlider,
		"spring": %SpringSlider,
		"tire_radius": %TireRadiusSlider,
	}
	_values = {
		"max_torque": %TorqueValue,
		"final_drive": %FinalDriveValue,
		"spring": %SpringValue,
		"tire_radius": %TireRadiusValue,
	}
	_selector.item_selected.connect(_select_setup)
	_color_picker.color_changed.connect(_on_color_changed)
	for key in _sliders:
		_sliders[key].value_changed.connect(_on_slider_changed.bind(key))
	%ResetButton.pressed.connect(_reset_setup)
	%BackButton.pressed.connect(_request_back)
	_start.pressed.connect(_start_race)
	_model_default_y = _model.position.y
	# Модель — редактируемый экземпляр low_poly_lance_evo.tscn, не создаётся кодом.
	for wheel_name in ["Mitsubishi_Wheel_Ft_L", "Mitsubishi_Wheel_Ft_R", "Mitsubishi_Wheel_Bk_L", "Mitsubishi_Wheel_Bk_R"]:
		var wheel := _model.get_node(wheel_name) as Node3D
		_wheels.append(wheel)
		_wheel_visuals.append(wheel)
		_wheel_bases.append(wheel.basis)


func _request_back() -> void:
	back_requested.emit()


func open(game_config: RallyGameConfig, index: int, game_state: Node) -> void:
	config = game_config
	game = game_state
	drafts.clear()
	_selector.clear()
	for i in range(config.setup_count()):
		var preset := config.get_setup(i) as SetupType
		_selector.add_item(preset.display_name if preset != null else "—", i)
	show()
	_select_setup(clampi(index, 0, maxi(0, config.setup_count() - 1)))
	_start.grab_focus()


func _process(delta: float) -> void:
	if visible and _turntable != null:
		_turntable.rotate_y(delta * turntable_speed)


func _select_setup(index: int) -> void:
	if config == null or index < 0 or index >= config.setup_count():
		return
	selected_index = index
	if not drafts.has(index):
		var original := config.get_setup(index) as SetupType
		if original == null:
			return
		drafts[index] = game.call("get_custom_setup", index) if game != null else original.duplicate(true)
	setup = drafts[index] as SetupType
	_refresh()


func _refresh() -> void:
	if setup == null:
		return
	_updating = true
	_selector.select(selected_index)
	_description.text = setup.description
	_summary.text = "%s\n%s  ·  %d кг  ·  %d об/мин" % [setup.get_engine_summary(), setup.get_drivetrain_name(), int(setup.vehicle_mass), int(setup.max_rpm)]
	_color_picker.color = setup.body_color
	_sliders["max_torque"].value = setup.max_torque
	_sliders["final_drive"].value = setup.final_drive
	_sliders["spring"].value = (setup.front_spring_length + setup.rear_spring_length) * 0.5
	_sliders["tire_radius"].value = setup.tire_radius
	_values["max_torque"].text = "%d Н·м" % roundi(setup.max_torque)
	_values["final_drive"].text = "%.2f" % setup.final_drive
	_values["spring"].text = "%.3f м" % ((setup.front_spring_length + setup.rear_spring_length) * 0.5)
	_values["tire_radius"].text = "%.3f м" % setup.tire_radius
	_update_preview()
	_updating = false


func _update_preview() -> void:
	if _model == null or setup == null:
		return
	# Та же геометрия и формулы, что в RallyCar._apply_visual_setup.
	_model.position.y = _model_default_y + setup.tire_radius - 0.438
	for child in _model.get_children():
		if child is MeshInstance3D and String(child.name).begins_with("Mitsubishi_Body"):
			var mesh := child as MeshInstance3D
			var original: Material = mesh.material_override
			if original == null and mesh.mesh != null:
				original = mesh.mesh.surface_get_material(0)
			var material := original.duplicate() as StandardMaterial3D if original is StandardMaterial3D else StandardMaterial3D.new()
			material.albedo_color = setup.body_color
			mesh.material_override = material
	for i in range(_wheel_visuals.size()):
		# Колёса исходной визуальной модели — самостоятельные редактируемые узлы.
		_wheel_visuals[i].basis = _wheel_bases[i].scaled(Vector3.ONE * (setup.tire_radius / 0.438))


func _on_slider_changed(value: float, key: String) -> void:
	if _updating or setup == null:
		return
	if key == "spring":
		# Сохраняем небольшой баланс передней и задней оси.
		var delta := value - (setup.front_spring_length + setup.rear_spring_length) * 0.5
		setup.front_spring_length = clampf(setup.front_spring_length + delta, 0.20, 0.45)
		setup.rear_spring_length = clampf(setup.rear_spring_length + delta, 0.20, 0.45)
	else:
		setup.set(key, value)
	_refresh()


func _on_color_changed(color: Color) -> void:
	if _updating or setup == null:
		return
	setup.body_color = Color(color.r, color.g, color.b, 1.0)
	_update_preview()


func _start_race() -> void:
	if setup != null:
		start_requested.emit(selected_index, setup)


func _reset_setup() -> void:
	var base := config.get_setup(selected_index) as SetupType
	if base == null:
		return
	setup = base.duplicate(true) as SetupType
	drafts[selected_index] = setup
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()
