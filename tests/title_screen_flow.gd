# godot --headless --path . --script res://tests/title_screen_flow.gd
extends SceneTree

const TitleScene = preload("res://scenes/title_screen.tscn")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _run() -> void:
	var title = TitleScene.instantiate()
	root.add_child(title)
	current_scene = title
	await process_frame
	var drive = title.get_node("TitleDrive")
	var initial_position: Vector3 = drive.car.position
	drive._process(1.0)
	_check(drive.car.position.distance_to(initial_position) > 1.0, "машина движется по трассе")
	_check(drive.camera.current, "камера демонстрации активна")
	_check(title.start_button.has_focus(), "старт доступен с клавиатуры")
	_check(title.get_node_or_null("Menu") != null, "меню создано")
	title._open_settings()
	_check(title.input_settings != null and title.input_settings.visible, "настройки открываются")
	title.input_settings.close()
	await create_timer(0.5).timeout
	title.start_button.pressed.emit()
	await process_frame
	await process_frame
	_check(current_scene != null and current_scene.scene_file_path == "res://scenes/main_menu.tscn", "старт открывает выбор трассы")
	if current_scene != null and current_scene.scene_file_path == "res://scenes/main_menu.tscn":
		var back := current_scene.get_node("Content/Body/Left/ButtonRow/BackButton") as Button
		back.pressed.emit()
		await process_frame
		await process_frame
		_check(current_scene != null and current_scene.scene_file_path == "res://scenes/title_screen.tscn", "назад возвращает на первый экран")
	if failures.is_empty():
		print("title_screen_flow: OK")
	quit(1 if not failures.is_empty() else 0)
