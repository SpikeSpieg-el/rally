## Редактор: при открытии проекта и после импорта кузова из cars/ собирает
## новые машины. Вручную то же самое: Project → Tools → «Rally: собрать машины из cars/».
@tool
extends EditorPlugin

const VehicleSync := preload("res://addons/rally_vehicle_sync/vehicle_sync.gd")
const MENU_TEXT := "Rally: собрать машины из cars/"

var _pending := false
var _busy := false


func _enter_tree() -> void:
	add_tool_menu_item(MENU_TEXT, _sync_now)
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
	if _busy:
		return
	_busy = true
	VehicleSync.run()
	_busy = false


func _sync_now() -> void:
	_sync()
