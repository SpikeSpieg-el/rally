# godot --headless --path . --fixed-fps 120 --script res://tests/title_screen_flow.gd
extends SceneTree

const TitleScene = preload("res://scenes/title_screen.tscn")
const Recording = preload("res://scripts/menu/menu_recording.gd")
const Driver = preload("res://scripts/menu/menu_driver.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func _steps(count: int) -> void:
	for i in range(count):
		await physics_frame

func _run() -> void:
	var title = TitleScene.instantiate()
	root.add_child(title)
	current_scene = title
	await process_frame
	var stage = title.get_node("WorldViewport/MenuStage")
	var car = stage.get_node("RallyCar")
	var driver = stage.get_node("Driver")
	var track = stage.get_node("Track")
	var terrain = stage.get_node("Ground")
	driver.mode = Driver.Mode.AUTO
	car.reset_to_spawn()
	check(car is RigidBody3D and car.cinematic_mode, "меню использует настоящую физическую машину")
	check(track.get_node("RoadMesh").mesh != null, "видимая дорога построена")
	check(terrain.get_node("Mesh").mesh != null and terrain.get_node("CollisionShape3D").shape != null, "рельеф и коллизия построены")
	var low := INF
	var high := -INF
	for point in terrain._heights:
		low = minf(low, point)
		high = maxf(high, point)
	check(high - low > 10.0, "рельеф не плоский")
	var road_low := INF
	var road_high := -INF
	for i in range(track.curve.point_count):
		var height: float = track.curve.get_point_position(i).y
		road_low = minf(road_low, height)
		road_high = maxf(road_high, height)
	check(road_high - road_low > 8.0, "у дороги есть подъёмы и спуски")
	check(stage.get_node("Props").get_child_count() > 100, "расставлено лесное окружение")
	check(track.get_node("RoadSurface/CollisionShape3D").shape != null, "у дороги есть физическая коллизия")
	check(track.curve.get_point_position(0).distance_to(track.curve.get_point_position(track.curve.point_count - 1)) < 0.01, "трасса замкнута")
	check(stage.get_node("Cinematography/Camera3D").current, "активна кинематографическая камера")
	check(stage.get_node("Cinematography/Shots").get_child_count() >= 2, "есть несколько редактируемых пролётов")
	check(title.world_viewport.size.x <= title.preview_max_width and title.world_viewport.size.y <= title.preview_max_height, "рендер фона ограничен")
	check(title.start_button.has_focus(), "кнопка старта в фокусе")
	var start: Vector3 = car.global_position
	await _steps(300)
	check(car.global_position.distance_to(start) > 3.0, "машина едет под действием физики")
	check(car.get_wheel_contact_count() >= 2, "колёса соприкасаются с поверхностью")
	# Запись входа пользователя и чтение записи; никаких позиций в ней нет.
	driver.mode = Driver.Mode.RECORD
	driver.recording_path = "user://title_screen_flow_recording.tres"
	var f9 := InputEventKey.new()
	f9.keycode = KEY_F9
	f9.pressed = true
	driver._unhandled_key_input(f9)
	check(driver._is_recording, "F9 начинает запись")
	Input.action_press("throttle")
	await _steps(80)
	Input.action_release("throttle")
	driver._unhandled_key_input(f9)
	check(not driver._is_recording, "F9 останавливает запись")
	var saved := ResourceLoader.load(driver.recording_path) as Recording
	check(saved != null and saved.valid() and saved.frame_count() > 10, "запись физического ввода сохранена")
	if saved != null and saved.valid():
		check(saved.frames[0] > 0.0, "в запись попал газ")
		driver._source = saved
		driver.mode = Driver.Mode.PLAYBACK
		driver._time = 0.0
		driver._play(1.0 / float(saved.physics_fps))
		check(driver.throttle > 0.0, "при воспроизведении газ подаётся машине")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(driver.recording_path))
	title.settings_button.mouse_entered.emit()
	check(title.settings_button.has_focus(), "наведение переносит фокус")
	title._open_settings()
	check(title.input_settings != null and title.input_settings.visible, "настройки открываются")
	title.input_settings.close()
	await create_timer(0.5).timeout
	title.start_button.pressed.emit()
	await process_frame
	await process_frame
	check(current_scene != null and current_scene.scene_file_path == "res://scenes/main_menu.tscn", "старт открывает выбор трассы")
	if current_scene != null and current_scene.scene_file_path == "res://scenes/main_menu.tscn":
		var back := current_scene.get_node("Content/Body/Left/ButtonRow/BackButton") as Button
		back.pressed.emit()
		await process_frame
		await process_frame
		check(current_scene != null and current_scene.scene_file_path == "res://scenes/title_screen.tscn", "назад возвращает на первый экран")
	print("title_screen_flow: %d failures" % failures.size())
	quit(1 if not failures.is_empty() else 0)
