## Док «Мир трассы»: числа, которые видно только на собранной карте.
##
## Осевую, ширину, покрытие, лес и зоны удобнее тянуть мышью во вьюпорте, но
## есть параметры, которые мышью не нарисуешь: высота холмов, частота ridges,
## крутизна насыпи, глубина кювета, сцепление вне дороги, туман и экспозиция.
## Раньше за ними надо было лезть в инспектор ресурса, а потом ещё помнить про
## «Пересобрать». Здесь они рядом с кнопкой «Собрать» и с живой разметкой.
##
## Док — чистый Control: он не хранит данные, а читает и пишет поля того же
## RallyTrackConfig, который собирает RallyStage. Каждое перетаскивание
## ползунка завершается одной записью в Ctrl+Z.
@tool
extends VBoxContainer

const TITLE := "МИР ТРАССЫ"
const MIN_LABEL_WIDTH := 104.0
const MIN_VALUE_WIDTH := 62.0

## Таблица ползунков. Диапазоны повторяют подсказки @export_range в
## rally_track_config.gd — чтобы движение ползунка не выходило за допустимое.
const ROWS: Array = [
	{"group": "ДОРОГА", "property": "road_half_width", "title": "Полуширина", "min": 2.0, "max": 10.0, "step": 0.1, "fmt": "%.1f м"},
	{"group": "ДОРОГА", "property": "road_shoulder", "title": "Обочина", "min": 0.0, "max": 5.0, "step": 0.1, "fmt": "%.1f м"},
	{"group": "ДОРОГА", "property": "road_camber", "title": "Профиль", "min": 0.0, "max": 0.4, "step": 0.01, "fmt": "%.2f"},
	{"group": "ДОРОГА", "property": "offroad_grip", "title": "Сцепление вне", "min": 0.05, "max": 1.0, "step": 0.01, "fmt": "%.2f"},
	{"group": "РЕЛЬЕФ", "property": "hills_height", "title": "Холмы", "min": 0.0, "max": 80.0, "step": 0.5, "fmt": "%.1f м"},
	{"group": "РЕЛЬЕФ", "property": "hills_frequency", "title": "Частота", "min": 0.0005, "max": 0.02, "step": 0.0005, "fmt": "%.4f"},
	{"group": "РЕЛЬЕФ", "property": "ridge_height", "title": "Гряды", "min": 0.0, "max": 80.0, "step": 0.5, "fmt": "%.1f м"},
	{"group": "РЕЛЬЕФ", "property": "ridge_frequency", "title": "Частота гряд", "min": 0.0005, "max": 0.02, "step": 0.0005, "fmt": "%.4f"},
	{"group": "РЕЛЬЕФ", "property": "detail_height", "title": "Детали", "min": 0.0, "max": 3.0, "step": 0.01, "fmt": "%.2f м"},
	{"group": "НАСЫПЬ", "property": "embankment_min_width", "title": "Узкая насыпь", "min": 1.0, "max": 40.0, "step": 0.5, "fmt": "%.1f м"},
	{"group": "НАСЫПЬ", "property": "embankment_max_width", "title": "Широкая насыпь", "min": 4.0, "max": 120.0, "step": 1.0, "fmt": "%.0f м"},
	{"group": "НАСЫПЬ", "property": "embankment_slope_deg", "title": "Откос", "min": 10.0, "max": 55.0, "step": 1.0, "fmt": "%.0f°"},
	{"group": "НАСЫПЬ", "property": "road_ditch_depth", "title": "Кювет", "min": 0.0, "max": 2.0, "step": 0.05, "fmt": "%.2f м"},
	{"group": "СВЕТ И НЕБО", "property": "fog_near", "title": "Туман от", "min": 0.0, "max": 600.0, "step": 5.0, "fmt": "%.0f м"},
	{"group": "СВЕТ И НЕБО", "property": "fog_far", "title": "Туман до", "min": 10.0, "max": 900.0, "step": 5.0, "fmt": "%.0f м"},
	{"group": "СВЕТ И НЕБО", "property": "ambient_energy", "title": "Подсветка", "min": 0.0, "max": 2.0, "step": 0.05, "fmt": "%.2f"},
	{"group": "СВЕТ И НЕБО", "property": "exposure", "title": "Экспозиция", "min": 0.2, "max": 3.0, "step": 0.05, "fmt": "%.2f"},
]

var _studio = null
var _rows: Array = []
var _hint: Label = null
var _body: VBoxContainer = null
var _apply_button: Button = null
var _dragging_index: int = -1
var _hint_text := ""


func setup(studio) -> void:
	_studio = studio
	_build()
	refresh()


func _build() -> void:
	name = "Студия трассы"
	custom_minimum_size = Vector2(272.0, 120.0)
	add_theme_constant_override("separation", 4)
	var title := Label.new()
	title.text = TITLE
	title.add_theme_font_size_override("font_size", 12)
	add_child(title)
	_hint = Label.new()
	_hint.text = ""
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 11)
	add_child(_hint)
	_apply_button = Button.new()
	_apply_button.text = "Собрать мир по этим числам"
	_apply_button.tooltip_text = "То же, что Ctrl+R во вьюпорте"
	_apply_button.pressed.connect(_on_apply_pressed)
	add_child(_apply_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0.0, 220.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 2)
	scroll.add_child(_body)
	var group := ""
	for entry in ROWS:
		var row_group := String(entry["group"])
		if row_group != group:
			group = row_group
			_body.add_child(_make_group_label(group))
		_body.add_child(_make_row(entry))


func _make_group_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82))
	return label


func _make_row(entry: Dictionary) -> HBoxContainer:
	var index: int = _rows.size()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var caption := Label.new()
	caption.text = String(entry["title"])
	caption.tooltip_text = String(entry["property"])
	caption.custom_minimum_size.x = MIN_LABEL_WIDTH
	caption.add_theme_font_size_override("font_size", 11)
	row.add_child(caption)
	var slider := HSlider.new()
	slider.min_value = float(entry["min"])
	slider.max_value = float(entry["max"])
	slider.step = float(entry["step"])
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(60.0, 18.0)
	slider.tooltip_text = String(entry["property"])
	slider.value_changed.connect(_on_slider_value.bind(index))
	slider.drag_started.connect(_on_slider_drag_started.bind(index))
	slider.drag_ended.connect(_on_slider_drag_ended.bind(index))
	row.add_child(slider)
	var value_label := Label.new()
	value_label.text = "—"
	value_label.custom_minimum_size.x = MIN_VALUE_WIDTH
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 11)
	row.add_child(value_label)
	_rows.append({
		"property": String(entry["property"]),
		"title": String(entry["title"]),
		"fmt": String(entry["fmt"]),
		"slider": slider,
		"value": value_label,
		"before": null,
	})
	return row


func _resource() -> Resource:
	if _studio == null:
		return null
	return _studio.track


## Синхронизировать ползунки с ресурсом: числа могли поменять в инспекторе.
func refresh() -> void:
	if _studio == null:
		return
	var target = _resource()
	var ready_now: bool = target != null
	if _hint != null:
		var wanted := "Откройте сцену этапа RallyStage — правки пишутся в её ресурс трассы."
		if ready_now:
			wanted = "Ползунки пишут в %s. Сборка — по кнопке или Ctrl+R." % target.resource_path
		if wanted != _hint_text:
			_hint_text = wanted
			_hint.text = wanted
	if _apply_button != null:
		_apply_button.visible = ready_now and _studio.stage != null
	for i in range(_rows.size()):
		var entry: Dictionary = _rows[i]
		var slider: HSlider = entry["slider"]
		var value_label: Label = entry["value"]
		if not ready_now:
			slider.editable = false
			value_label.text = "—"
			continue
		var raw = target.get(StringName(entry["property"]))
		if raw is float or raw is int:
			slider.editable = true
			var value := float(raw)
			if i != _dragging_index:
				slider.set_value_no_signal(clampf(value, float(slider.min_value), float(slider.max_value)))
			value_label.text = String(entry["fmt"]) % value
		else:
			slider.editable = false
			value_label.text = "—"


func _on_slider_value(value: float, index: int) -> void:
	var target = _resource()
	if target == null or index < 0 or index >= _rows.size():
		return
	var entry: Dictionary = _rows[index]
	target.set(StringName(entry["property"]), value)
	var value_label: Label = entry["value"]
	value_label.text = String(entry["fmt"]) % value
	if _studio != null:
		_studio.world_param_changed()


func _on_slider_drag_started(index: int) -> void:
	_dragging_index = index
	var target = _resource()
	if target == null or index < 0 or index >= _rows.size():
		return
	var entry: Dictionary = _rows[index]
	entry["before"] = target.get(StringName(entry["property"]))


func _on_slider_drag_ended(_changed: bool, index: int) -> void:
	_dragging_index = -1
	var target = _resource()
	if target == null or _studio == null or index < 0 or index >= _rows.size():
		return
	var entry: Dictionary = _rows[index]
	var before = entry.get("before")
	var after = target.get(StringName(entry["property"]))
	entry["before"] = null
	if before == null or after == null or before == after:
		return
	var undo = _studio.host.get_undo_redo()
	if undo == null:
		return
	undo.create_action("Студия трассы: " + String(entry["title"]))
	undo.add_do_property(target, StringName(entry["property"]), after)
	undo.add_undo_property(target, StringName(entry["property"]), before)
	undo.add_do_method(_studio, "_after_edit")
	undo.add_undo_method(_studio, "_after_edit")
	undo.commit_action()


func _on_apply_pressed() -> void:
	if _studio != null:
		_studio.rebuild_stage()
