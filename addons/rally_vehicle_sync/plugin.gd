## Редактор: при открытии проекта и после импорта кузова из cars/ собирает
## новые машины. Панель «Машины Rally» (док справа) показывает состояние кузовов
## и даёт кнопки сборки. Тот же запуск есть в меню Project → Tools.
@tool
extends EditorPlugin

const VehicleSync := preload("res://addons/rally_vehicle_sync/vehicle_sync.gd")
const DockType := preload("res://addons/rally_vehicle_sync/vehicle_dock.gd")
const MENU_TEXT := "Rally: собрать машины из cars/"

var _dock: DockType = null
var _pending := false
var _busy := false


func _enter_tree() -> void:
	add_tool_menu_item(MENU_TEXT, _sync_now)
	_dock = DockType.new()
	_dock.name = "Машины Rally"
	add_control_to_dock(DOCK_SLOT_RIGHT_BR, _dock)
	_dock.build_requested.connect(_on_build_requested)
	_dock.rebuild_requested.connect(_on_rebuild_requested)
	var files := EditorInterface.get_resource_filesystem()
	files.filesystem_changed.connect(_schedule)
	files.resources_reimported.connect(_on_reimported)
	_schedule()


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_TEXT)
	var files := EditorInterface.get_resource_filesystem()
	if files.filesystem_changed.is_connected(_schedule):
		files.filesystem_changed.disconnect(_schedule)
	if files.resources_reimported.is_connected(_on_reimported):
		files.resources_reimported.disconnect(_on_reimported)
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


func _on_reimported(_resources: PackedStringArray) -> void:
	_schedule()


## Сборку откладываем на кадр: сигналы файловой системы приходят пачками.
func _schedule() -> void:
	if _pending:
		return
	_pending = true
	call_deferred("_sync")


func _sync() -> void:
	_pending = false
	_run(false)


func _sync_now() -> void:
	_run(true)


func _on_build_requested() -> void:
	_run(true)


func _on_rebuild_requested(id: String) -> void:
	if _busy:
		return
	_busy = true
	var report: Array[Dictionary] = VehicleSync.rebuild(id)
	_busy = false
	if _dock != null:
		_dock.show_report(report, true)


## manual — запуск по кнопке или из меню: тогда в журнале пишется и «ничего нового».
func _run(manual: bool) -> void:
	if _busy:
		return
	_busy = true
	var report: Array[Dictionary] = VehicleSync.run()
	_busy = false
	if _dock != null:
		_dock.show_report(report, manual)
