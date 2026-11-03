## Лаборатория визуальных эффектов. Запустите сцену (F6), чтобы увидеть
## результат тех же узлов/материалов, которые используются в заезде.
## Переключатели на экране меняют только предпросмотр и НЕ сохраняют пресеты.
@tool
extends Node3D

const WeatherType = preload("res://scripts/data/rally_weather_config.gd")
const Rain = preload("res://data/weather/weather_rain.tres")
const Snow = preload("res://data/weather/weather_snow.tres")
const Clear = preload("res://data/weather/weather_clear.tres")
const Track = preload("res://data/tracks/stage_forest.tres")
const Effects = preload("res://scripts/effects/rally_visual_effects.gd")
const ScreenLook = preload("res://scripts/effects/rally_screen_look.gd")
const SpeedFeel = preload("res://scripts/effects/rally_speed_feel.gd")
const Precip = preload("res://scripts/effects/rally_precipitation_effect.gd")

@export_group("Условия предпросмотра")
@export var weather: WeatherType = Rain:
	set(value):
		weather = value
		_queue_refresh()
@export_range(0.0, 240.0, 1.0, "suffix:км/ч") var preview_speed_kmh: float = 120.0:
	set(value):
		preview_speed_kmh = value
		_queue_refresh()
## Временно показать картинку без экранного фильтра для сравнения.
@export var compare_original: bool = false:
	set(value):
		compare_original = value
		_queue_refresh()
@export_tool_button("Обновить предпросмотр") var refresh_button = refresh_preview

var effects: Effects = null
var _ready_done := false


func _ready() -> void:
	effects = get_node_or_null("VisualEffects") as Effects
	_ready_done = true
	_build_road_sample()
	_assign_surface_materials()
	_bind_controls()
	refresh_preview()


func _queue_refresh() -> void:
	if _ready_done:
		call_deferred("refresh_preview")


func _assign_surface_materials() -> void:
	if effects == null or effects.surfaces() == null:
		return
	var ground := get_node_or_null("Ground") as MeshInstance3D
	var road := get_node_or_null("Road") as MeshInstance3D
	if ground != null:
		ground.material_override = effects.surfaces().ground_material
	if road != null:
		road.material_override = effects.surfaces().road_material


func _build_road_sample() -> void:
	var road := get_node_or_null("Road") as MeshInstance3D
	if road == null:
		return
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var lateral := [-6.0, -5.0, 0.0, 5.0, 6.0]
	var rows := 41
	for row in range(rows):
		var z := -40.0 + float(row) * 2.0
		for lane in range(lateral.size()):
			vertices.append(Vector3(lateral[lane], 0.04, z))
			normals.append(Vector3.UP)
			uvs.append(Vector2(lateral[lane], float(row) * 2.0))
			colors.append(Color(0.42, 0.39, 0.33) if absf(lateral[lane]) <= 5.0 else Color(0.31, 0.25, 0.17))
	for row in range(rows - 1):
		for lane in range(lateral.size() - 1):
			var i := row * lateral.size() + lane
			indices.append_array([i, i + 1, i + lateral.size(), i + 1, i + lateral.size() + 1, i + lateral.size()])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	road.mesh = mesh


func _bind_controls() -> void:
	var weather_box := get_node_or_null("PreviewCanvas/Panel/Box/Weather") as OptionButton
	var speed_box := get_node_or_null("PreviewCanvas/Panel/Box/Speed") as OptionButton
	var screen_box := get_node_or_null("PreviewCanvas/Panel/Box/Screen") as OptionButton
	var feel_box := get_node_or_null("PreviewCanvas/Panel/Box/Feel") as OptionButton
	var rain_box := get_node_or_null("PreviewCanvas/Panel/Box/RainPreset") as OptionButton
	var compare := get_node_or_null("PreviewCanvas/Panel/Box/Compare") as CheckButton
	var slider := get_node_or_null("PreviewCanvas/Panel/Box/SpeedSlider") as HSlider
	_fill_options(weather_box, ["Ясно", "Дождь", "Снег"], 1)
	_fill_options(speed_box, ["60 км/ч", "120 км/ч", "200 км/ч"], 1)
	_fill_options(screen_box, ["Чистая картинка", "Мягкий PS1", "Классический PS1"], 2)
	_fill_options(feel_box, ["Выключено", "Комфорт", "Выразительно", "Аркада"], 2)
	_fill_options(rain_box, ["Слабые", "Обычные", "Сильные"], 1)
	if weather_box != null:
		weather_box.item_selected.connect(func(index: int) -> void:
			weather = [Clear, Rain, Snow][index]
		)
	if speed_box != null:
		speed_box.item_selected.connect(func(index: int) -> void:
			preview_speed_kmh = [60.0, 120.0, 200.0][index]
			if slider != null:
				slider.value = preview_speed_kmh
		)
	if screen_box != null and effects != null and effects.screen() != null:
		screen_box.item_selected.connect(func(index: int) -> void:
			effects.screen().look = [ScreenLook.Look.CLEAN, ScreenLook.Look.SOFT_PS1, ScreenLook.Look.CLASSIC_PS1][index]
		)
	if feel_box != null and effects != null and effects.speed() != null:
		feel_box.item_selected.connect(func(index: int) -> void:
			effects.speed().feel = [SpeedFeel.Feel.OFF, SpeedFeel.Feel.COMFORT, SpeedFeel.Feel.EXPRESSIVE, SpeedFeel.Feel.ARCADE][index]
		)
	if rain_box != null and effects != null:
		rain_box.item_selected.connect(func(index: int) -> void:
			var value: int = [Precip.Preset.LIGHT, Precip.Preset.STEADY, Precip.Preset.HEAVY][index]
			if effects.rain() != null:
				effects.rain().preset = value
			if effects.snow() != null:
				effects.snow().preset = value
		)
	if compare != null:
		compare.toggled.connect(func(value: bool) -> void: compare_original = value)
	if slider != null:
		slider.value_changed.connect(func(value: float) -> void: preview_speed_kmh = value)


func _fill_options(box: OptionButton, items: Array, selected: int) -> void:
	if box == null:
		return
	if box.item_count == 0:
		for item in items:
			box.add_item(item)
	box.select(selected)


func refresh_preview() -> void:
	if not _ready_done:
		return
	_assign_surface_materials()
	if effects == null:
		return
	effects.configure_screen(Track)
	effects.preview_weather(weather)
	var rect := effects.screen()
	if rect != null:
		rect.set_compare_original(compare_original)
		rect.set_preview_speed(preview_speed_kmh)
	var status := get_node_or_null("PreviewCanvas/Panel/Box/Status") as Label
	if status != null:
		status.text = "Предпросмотр: %.0f км/ч · %s\nПереключатели не сохраняются. Для постоянной настройки меняйте узлы сцены." % [
			preview_speed_kmh, weather.display_name if weather != null else "ясно",
		]
	var speed_label := get_node_or_null("PreviewCanvas/Panel/Box/SpeedValue") as Label
	if speed_label != null:
		speed_label.text = "Скорость для проверки: %.0f км/ч" % preview_speed_kmh
