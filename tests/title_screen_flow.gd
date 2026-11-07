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
	var drive = title.get_node("WorldViewport/TitleDrive")
	# Проверяем обе ветки _build_surface до обращения к машине: при ошибке
	# сборки тест должен завершиться с FAIL, а не упасть на null.position.
	var terrain := drive.get_node_or_null("Terrain") as MeshInstance3D
	var road := drive.get_node_or_null("Road") as MeshInstance3D
	_check(terrain != null and terrain.mesh != null, "рельеф стартового экрана построен")
	_check(road != null and road.mesh != null, "дорога стартового экрана построена")
	_check(drive.car != null and drive.camera != null, "машина и камера созданы")
	if terrain == null or road == null or drive.car == null or drive.camera == null:
		quit(1)
		return
	var initial_position: Vector3 = drive.car.position
	drive._process(1.0)
	_check(drive.car.position.distance_to(initial_position) > 1.0, "машина движется по трассе")
	_check(drive.camera.current, "камера демонстрации активна")
	_check(drive.car.position.distance_to(drive._point(drive.distance)) < 0.2, "машина следует оси игровой трассы")
	_check(title.world_viewport.size.x <= 960 and title.world_viewport.size.y <= 540, "размер 3D-превью ограничен")
	_check(title.preview.get_parent() == title, "интерфейс не находится в 3D-превью")
	_check(road.material_override is ShaderMaterial, "дорога использует игровой шейдер")
	var batches := 0
	var colliders := 0
	for child in drive.get_children():
		if child is MultiMeshInstance3D:
			batches += 1
		if child is StaticBody3D:
			colliders += 1
	_check(batches > 0 and colliders == 0, "лес собран пакетами без физики")
	drive.distance = drive.DRIVE_END - 0.1
	drive._process(0.02)
	_check(drive.distance >= drive.DRIVE_START and drive.distance < drive.DRIVE_START + 1.0 and drive.fade < 0.1, "зацикливание скрыто затемнением")
	_check(title.start_button.has_focus(), "старт доступен с клавиатуры")
	var settings := title.get_node("Menu/VBoxContainer/SettingsButton") as Button
	settings.mouse_entered.emit()
	_check(settings.has_focus(), "наведение сразу переносит фокус на кнопку")
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
