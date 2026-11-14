## Панель «Машины Rally» в редакторе Godot.
##
## Что видно: список glb из cars/ и состояние каждого кузова (ждёт импорта,
## будет собрана, собрана, ждёт пересборки), кнопки сборки и журнал действий.
## Вся логика сборки — в vehicle_sync.gd. Панель только показывает и вызывает её.
@tool
extends VBoxContainer

signal build_requested
signal rebuild_requested(id: String)

const VehicleSync := preload("res://addons/rally_vehicle_sync/vehicle_sync.gd")
const COLOR_OK := Color(0.55, 0.85, 0.55)
const COLOR_ERROR := Color(1.0, 0.5, 0.5)
const COLOR_INFO := Color(0.75, 0.75, 0.75)
const EMPTY_TEXT := "В cars/ пока нет glb-файлов"

var _list: ItemList = null
var _log: RichTextLabel = null
var _rebuild_button: Button = null


func _init() -> void:
	custom_minimum_size = Vector2(260.0, 0.0)
	add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "Кузова из папки cars/"
	add_child(title)

	var hint := Label.new()
	hint.text = "Положите glb в cars/ и дождитесь импорта: машина соберётся сама."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", COLOR_INFO)
	add_child(hint)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0.0, 120.0)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_item_selected)
	add_child(_list)

	var build_button := Button.new()
	build_button.text = "Собрать новые"
	build_button.tooltip_text = "Собрать все кузова из cars/, которых ещё нет в проекте."
	build_button.pressed.connect(_on_build_pressed)
	add_child(build_button)

	_rebuild_button = Button.new()
	_rebuild_button.text = "Пересобрать выбранную"
	_rebuild_button.tooltip_text = "Пересобрать модель выбранной машины по текущему glb и подгонке."
	_rebuild_button.disabled = true
	_rebuild_button.pressed.connect(_on_rebuild_pressed)
	add_child(_rebuild_button)

	var refresh_button := Button.new()
	refresh_button.text = "Обновить список"
	refresh_button.pressed.connect(refresh)
	add_child(refresh_button)

	_log = RichTextLabel.new()
	_log.custom_minimum_size = Vector2(0.0, 140.0)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = true
	add_child(_log)


func _ready() -> void:
	refresh()


## Перечитывает cars/ и состояние кузовов. Выбор в списке сохраняется.
func refresh() -> void:
	if _list == null:
		return
	var keep := _selected_id()
	_list.clear()
	var cars: Array[Dictionary] = VehicleSync.scan()
	if cars.is_empty():
		_list.add_item(EMPTY_TEXT)
	for car: Dictionary in cars:
		var row := _list.add_item("%s — %s" % [String(car["id"]), String(car["state"])])
		_list.set_item_tooltip(row, String(car["file"]))
		_list.set_item_metadata(row, String(car["id"]))
	for item in _list.item_count:
		if not keep.is_empty() and String(_list.get_item_metadata(item)) == keep:
			_list.select(item)
	_update_buttons()


## Показывает результат сборки: строки журнала и обновлённый список.
## manual — запуск по кнопке: тогда пишем и то, что делать не пришлось.
func show_report(report: Array[Dictionary], manual: bool) -> void:
	if report.is_empty():
		if manual:
			_info("Новых кузовов нет: всё уже собрано.")
	for entry: Dictionary in report:
		var status := String(entry["status"])
		var line := "%s: %s" % [String(entry["id"]), String(entry["text"])]
		if status == VehicleSync.STATUS_ERROR:
			_line(line, COLOR_ERROR)
		else:
			_line(line, COLOR_OK)
	refresh()


func _on_build_pressed() -> void:
	build_requested.emit()


func _on_rebuild_pressed() -> void:
	var id := _selected_id()
	if id.is_empty():
		return
	rebuild_requested.emit(id)


func _on_item_selected(_index: int) -> void:
	_update_buttons()


func _update_buttons() -> void:
	if _rebuild_button != null:
		_rebuild_button.disabled = _selected_id().is_empty()


## Id выбранной машины или пусто, если ничего не выбрано.
func _selected_id() -> String:
	if _list == null:
		return ""
	var selected := _list.get_selected_items()
	if selected.is_empty():
		return ""
	return String(_list.get_item_metadata(selected[0]))


func _info(text: String) -> void:
	_line(text, COLOR_INFO)


func _line(text: String, color: Color) -> void:
	if _log == null:
		return
	_log.push_color(color)
	_log.add_text(text)
	_log.pop()
	_log.newline()
