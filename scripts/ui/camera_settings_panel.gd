## Камера в окне настроек: те же пять ползунков, что и в паузе, но без
## привязки к машине. Значения пишутся в user://rally_camera.cfg — их читает
## CameraSettings при старте заезда, поэтому настройка из меню работает
## в гонке без перезапуска.
extends VBoxContainer

const SETTINGS_PATH := "user://rally_camera.cfg"

## Значения по умолчанию — как у RallyCar (см. rally_car.gd).
const DEFAULTS := {
	"CockpitFov": 76.0,
	"ChaseFov": 72.0,
	"Motion": 0.35,
	"SpeedFeel": 1.0,
	"Sensitivity": 2.5,
}
const ROWS := [
	["CockpitFov", "FOV кабины", 45.0, 110.0, 1.0, "°"],
	["ChaseFov", "FOV сзади", 45.0, 110.0, 1.0, "°"],
	["Motion", "Движение камеры", 0.0, 1.0, 0.05, "%"],
	["SpeedFeel", "Ощущение скорости", 0.0, 1.0, 0.05, "%"],
	["Sensitivity", "Чувствительность мыши", 0.5, 10.0, 0.5, ""],
]

var _sliders: Dictionary = {}
var _values: Dictionary = {}
var _loading: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var note := Label.new()
	note.text = "Применяются в следующем заезде и сохраняются автоматически."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color(0.55, 0.68, 0.78, 1.0))
	add_child(note)
	for row_data in ROWS:
		_build_row(row_data)
	var reset := Button.new()
	reset.text = "СБРОСИТЬ КАМЕРУ"
	reset.custom_minimum_size = Vector2(0, 36)
	reset.pressed.connect(_reset)
	add_child(reset)
	_load()


func _build_row(row_data: Array) -> void:
	var key: String = row_data[0]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var title := Label.new()
	title.text = row_data[1]
	title.custom_minimum_size = Vector2(220, 0)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var slider := HSlider.new()
	slider.min_value = float(row_data[2])
	slider.max_value = float(row_data[3])
	slider.step = float(row_data[4])
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_ALL
	slider.value_changed.connect(_on_changed.bind(key))
	row.add_child(slider)
	var value := Label.new()
	value.custom_minimum_size = Vector2(64, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	_sliders[key] = slider
	_values[key] = value


func _load() -> void:
	_loading = true
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	for row_data in ROWS:
		var key: String = row_data[0]
		var slider := _sliders[key] as HSlider
		var saved: float = float(cfg.get_value("camera", key, float(DEFAULTS[key])))
		slider.set_value_no_signal(clampf(saved, slider.min_value, slider.max_value))
		_update_value(key, slider.value)
	_loading = false


func _update_value(key: String, value: float) -> void:
	var label := _values[key] as Label
	match key:
		"CockpitFov", "ChaseFov":
			label.text = "%d°" % roundi(value)
		"Motion", "SpeedFeel":
			label.text = "%d%%" % roundi(value * 100.0)
		_:
			label.text = "%.1f" % value


func _on_changed(value: float, key: String) -> void:
	_update_value(key, value)
	if _loading:
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	for row_data in ROWS:
		var row_key: String = row_data[0]
		cfg.set_value("camera", row_key, (_sliders[row_key] as HSlider).value)
	cfg.save(SETTINGS_PATH)


func _reset() -> void:
	_loading = true
	for row_data in ROWS:
		var key: String = row_data[0]
		var slider := _sliders[key] as HSlider
		slider.set_value_no_signal(float(DEFAULTS[key]))
		_update_value(key, slider.value)
	_loading = false
	var cfg := ConfigFile.new()
	for row_data in ROWS:
		var key: String = row_data[0]
		cfg.set_value("camera", key, float(DEFAULTS[key]))
	cfg.save(SETTINGS_PATH)
