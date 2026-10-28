## Настройки камеры в меню паузы. Позиции/повороты маркеров не затрагиваются.
extends VBoxContainer

const CarType = preload("res://scripts/rally_car.gd")
const SETTINGS_PATH := "user://rally_camera.cfg"
const ROWS := ["CockpitFov", "ChaseFov", "Motion", "Sensitivity"]

var car: CarType = null
var settings_path: String = SETTINGS_PATH
var defaults: Dictionary = {}
var chase_fov_bonus: float = 0.0
var loading_values: bool = false


func initialize(target: CarType) -> void:
	if target == null:
		return
	car = target
	chase_fov_bonus = car.chase_max_fov - car.chase_min_fov
	defaults = {
		"CockpitFov": car.cockpit_fov,
		"ChaseFov": car.chase_min_fov,
		"Motion": car.cockpit_motion_strength,
		"Sensitivity": car.mouse_sensitivity * 1000.0,
	}
	var config := ConfigFile.new()
	config.load(settings_path)
	loading_values = true
	for row_name in ROWS:
		var slider := get_node("%s/Slider" % row_name) as HSlider
		var saved_value: float = float(config.get_value("camera", row_name, defaults[row_name]))
		slider.set_value_no_signal(clampf(saved_value, slider.min_value, slider.max_value))
		_on_value_changed(slider.value, row_name)
		slider.value_changed.connect(_on_value_changed.bind(row_name))
	loading_values = false
	$ResetButton.pressed.connect(_reset_to_scene_defaults)


func _on_value_changed(value: float, row_name: String) -> void:
	var value_label := get_node("%s/Value" % row_name) as Label
	match row_name:
		"CockpitFov":
			car.cockpit_fov = value
			if car.camera_mode == CarType.CameraMode.COCKPIT_1ST:
				car.active_camera.fov = value + car.inside_speed_fov_bonus * clampf(car.speed_kmh / 180.0, 0.0, 1.0)
			value_label.text = "%d°" % roundi(value)
		"ChaseFov":
			car.chase_min_fov = value
			car.chase_max_fov = clampf(value + chase_fov_bonus, 45.0, 120.0)
			if car.camera_mode == CarType.CameraMode.CHASE_3RD:
				car.active_camera.fov = lerpf(value, car.chase_max_fov, clampf(car.speed_kmh / 160.0, 0.0, 1.0))
			value_label.text = "%d°" % roundi(value)
		"Motion":
			car.cockpit_motion_strength = value
			value_label.text = "%d%%" % roundi(value * 100.0)
		"Sensitivity":
			car.mouse_sensitivity = value / 1000.0
			value_label.text = "%.1f" % value
	if not loading_values:
		_save_values()


func _save_values() -> void:
	var config := ConfigFile.new()
	for row_name in ROWS:
		var slider := get_node("%s/Slider" % row_name) as HSlider
		config.set_value("camera", row_name, slider.value)
	var err: Error = config.save(settings_path)
	if err != OK:
		push_warning("Не удалось сохранить настройки камеры: %s" % error_string(err))


func _reset_to_scene_defaults() -> void:
	loading_values = true
	for row_name in ROWS:
		var slider := get_node("%s/Slider" % row_name) as HSlider
		slider.set_value_no_signal(float(defaults[row_name]))
		_on_value_changed(slider.value, row_name)
	loading_values = false
	_save_values()
