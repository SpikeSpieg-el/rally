# godot --headless --path . --fixed-fps 120 --script res://tests/menu_track_focus.gd
# Выбор трассы в меню: клик и фокус с клавиатуры не должны «терять» кнопку.
# Списки пересобираются на каждый выбор, и раньше фокус уходил в никуда
# вместе со старой кнопкой — следующее нажатие Enter ничего не делало.
extends SceneTree

const Config = preload("res://data/rally_game_config.tres")
const MainScene = preload("res://scenes/main_menu.tscn")

var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var previous := root.get_node_or_null("RallyGame")
	if previous != null:
		root.remove_child(previous)
		previous.queue_free()
	var game := GameState.new()
	game.name = "RallyGame"
	game.config = Config.duplicate(true)
	game.conditions_path = "user://menu_track_focus.cfg"
	game.records_path = "user://menu_track_focus_records.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.conditions_path))
	root.add_child(game)
	game.select_track(0)

	var menu = MainScene.instantiate()
	root.add_child(menu)
	await _frames(4)
	var buttons: Array = menu.track_buttons
	check(buttons.size() >= 3, "в меню есть список трасс")
	if buttons.size() < 3:
		await _finish(game, menu)
		return

	# Клавиатура/геймпад: фокус на «Живой ленте» выбирает её и остаётся на ней.
	buttons[2].grab_focus()
	await _frames(3)
	check(root.gui_get_focus_owner() == menu.track_buttons[2],
		"фокус остался на выбранной трассе")
	check(int(menu.selected_track) == 2, "фокус выбрал «Живую ленту»")
	check(game.track_index == 2 and String(game.current_track.get("id")) == "dynamic_stage",
		"RallyGame получил «Живую ленту»")

	# Следующее переключение с клавиатуры работает, а не упирается в пустоту.
	var down := InputEventAction.new()
	down.action = "ui_down"
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(3)
	check(root.gui_get_focus_owner() != null, "после переключения фокус не потерян")
	check(int(menu.selected_track) != 2, "стрелка вниз выбирает соседнюю трассу")

	# Клик мышью (кнопка получает фокус и нажатие): выбор применяется,
	# фокус переезжает на новую кнопку той же трассы.
	buttons = menu.track_buttons
	buttons[2].grab_focus()
	await _frames(3)
	buttons = menu.track_buttons
	buttons[2].pressed.emit()
	await _frames(3)
	check(int(menu.selected_track) == 2, "клик выбирает «Живую ленту»")
	check(root.gui_get_focus_owner() == menu.track_buttons[2],
		"после клика фокус на выбранной трассе")
	check(String(game.current_track.get("id")) == "dynamic_stage",
		"клик не подменяет трассу ночным лесом")
	check(int(game.starts) == 0, "выбор трассы не запускает заезд")

	await _finish(game, menu)


func _finish(game: Node, menu: Node) -> void:
	menu.queue_free()
	await process_frame
	root.remove_child(game)
	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://menu_track_focus.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://menu_track_focus_records.cfg"))
	if failures.is_empty():
		print("PASS: выбор трассы в меню не теряет фокус")
		quit(0)
	else:
		printerr("FAIL: меню трасс: %d проблем(ы)" % failures.size())
		quit(1)


## Настоящий RallyGame, но со счётчиком стартов: тест не должен менять сцену.
class GameState:
	extends "res://scripts/game_state.gd"
	var starts := 0

	func start_race() -> void:
		starts += 1
