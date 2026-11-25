# godot --headless --path . --fixed-fps 120 --script res://tests/menu_track_focus.gd
# Выбор трассы на 3D-доске гаража: подсветка стрелками и мышью, выбор Enter/клик.
# Доска пересобирается при каждом открытии гаража, поэтому подсветка стартует
# с выбранной трассы, а выбор записывается в RallyGame только при подтверждении.
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
	await _frames(2)
	menu._on_start_pressed()
	await create_timer(0.5).timeout

	var garage = menu.garage
	var board = garage._track_board
	var panel = garage._track_panel
	check(board != null and panel != null, "в гараже есть доска трасс и панель условий")
	check(garage._track_phase, "гараж открывается с выбора трассы")
	check(board.visible and not garage._start.visible, "на доске видна трасса, кнопка старта скрыта")
	check(board.focus_index == 0, "подсветка начинается с выбранной трассы")

	board.step_focus(2)
	check(board.focus_index == 2 and panel.selected_track == 2, "стрелка двигает подсветку и карточку")
	check(int(game.track_index) == 0, "наведение не записывает выбор в RallyGame")

	# Клик: плита на экране находится через проекцию камеры витрины.
	var camera: Camera3D = garage._preview_camera
	var pad: Node3D = board.get_node("Pads/Pad_4")
	var screen: Vector2 = camera.unproject_position(pad.global_position + Vector3(0.0, board.label_height * 0.5, 0.0))
	check(board.pick(camera, screen) == 4, "клик попадает в плиту")
	check(board.pick(camera, screen + Vector2(900.0, 900.0)) == -1, "клик мимо плит ничего не выбирает")

	board.set_focus(4)
	board.choose_focused()
	check(not garage._track_phase, "выбор трассы переводит камеру к машине")
	check(int(game.track_index) == 4, "выбор записан в RallyGame")
	check(garage._back_button.text.contains("ТРАССЕ"), "кнопка назад из машины ведёт к трассе")

	garage._enter_track_phase()
	check(garage._track_phase and board.focus_index == 4, "возврат к трассе сохраняет выбор")

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
		print("menu_track_focus: OK")
		quit(0)
	else:
		quit(1)
