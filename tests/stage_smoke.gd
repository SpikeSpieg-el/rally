# Проверка настоящей сцены этапа вместе с дорогой, HUD и камерой.
# godot --headless --path . --fixed-fps 120 --script res://tests/stage_smoke.gd
extends SceneTree

const CarScript = preload("res://scripts/rally_car.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/rally_stage.tscn")
	if packed == null:
		printerr("FAIL: сцена этапа не загрузилась")
		quit(1)
		return
	var stage = packed.instantiate()
	root.add_child(stage)
	var deadline := Time.get_ticks_msec() + 240000
	while not stage._stage_live and Time.get_ticks_msec() < deadline:
		await process_frame
	if not stage._stage_live:
		printerr("FAIL: этап не завершил сборку")
		stage.queue_free()
		await process_frame
		quit(1)
		return

	var road := stage.get_node_or_null("Generated/RoadMesh") as MeshInstance3D
	var car = stage.get_node("RallyCar")
	var marker: Marker3D = car.get_node("Cameras/CamCockpit")
	var authored_marker := marker.transform
	var ok := road != null and road.material_override is ShaderMaterial
	if road != null:
		var arrays: Array = road.mesh.surface_get_arrays(0)
		ok = ok and arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array and not arrays[Mesh.ARRAY_TEX_UV].is_empty()
	ok = ok and stage.world_environment.environment.volumetric_fog_enabled
	ok = ok and stage.get_node_or_null("HUD/RallyHUD/PausePanel/Box/CameraOptions") != null
	var controller_options = stage.get_node_or_null("HUD/RallyHUD/PausePanel/Box/ControllerOptions")
	ok = ok and controller_options != null and controller_options.get_node_or_null("Status") != null
	print("Проверка окружения: дорога=%s, материал=%s, UV=%s, туман=%s, HUD=%s, контроллер=%s" % [road != null, road.material_override is ShaderMaterial if road else false, not road.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV].is_empty() if road else false, stage.world_environment.environment.volumetric_fog_enabled, stage.get_node_or_null("HUD/RallyHUD/PausePanel/Box/CameraOptions") != null, controller_options != null])
	for i in range(2):
		Input.action_press("camera_switch")
		await physics_frame
		await physics_frame
		Input.action_release("camera_switch")
		await physics_frame
		await physics_frame
	ok = ok and car.camera_mode == CarScript.CameraMode.COCKPIT_1ST
	ok = ok and marker.transform.is_equal_approx(authored_marker)
	print("Проверка камеры: режим=%s, маркер=%s" % [car.get_camera_label(), marker.transform.is_equal_approx(authored_marker)])
	# Escape работает и на паузе, настройки остаются доступными, а машина
	# не продолжает принимать команды и выполнять физику под меню.
	Input.action_press("pause")
	await process_frame
	await process_frame
	Input.action_release("pause")
	await process_frame
	var camera_options = stage.get_node("HUD/RallyHUD/PausePanel/Box/CameraOptions")
	var test_settings_path := "user://rally_camera_stage_smoke.cfg"
	camera_options.settings_path = test_settings_path
	var slider: HSlider = camera_options.get_node("CockpitFov/Slider")
	var target_fov := 80.0 if not is_equal_approx(slider.value, 80.0) else 85.0
	slider.value = target_fov
	ok = ok and paused and stage.pause_panel.visible and not car.can_process()
	ok = ok and camera_options.can_process() and is_equal_approx(car.cockpit_fov, target_fov)
	var resume_button: Button = stage.resume_button
	ok = ok and resume_button != null and resume_button.focus_mode == Control.FOCUS_ALL
	print("Фокус паузы: кнопка=%s, режим=%s, фокус=%s" % [resume_button != null, resume_button.focus_mode if resume_button != null else -1, resume_button.has_focus() if resume_button != null else false])
	var expected_fov: float = target_fov + car.inside_speed_fov_bonus * clampf(car.speed_kmh / 180.0, 0.0, 1.0)
	ok = ok and is_equal_approx(car.active_camera.fov, expected_fov)
	print("Проверка паузы: paused=%s, панель=%s, машина=%s, настройки=%s, fov=%.2f/%.2f (ожид. %.2f)" % [paused, stage.pause_panel.visible, car.can_process(), camera_options.can_process(), car.cockpit_fov, car.active_camera.fov, expected_fov])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_settings_path))
	Input.action_press("pause")
	await process_frame
	await process_frame
	Input.action_release("pause")
	await process_frame
	ok = ok and not paused and not stage.pause_panel.visible and car.can_process()
	print("Выход из паузы: paused=%s, панель=%s, машина=%s" % [paused, stage.pause_panel.visible, car.can_process()])
	for i in range(120):
		await physics_frame
	var start_position: Vector3 = car.global_position
	var start_forward: Vector3 = car.global_basis.z.normalized()
	Input.action_press("throttle")
	for i in range(240):
		await physics_frame
	Input.action_release("throttle")
	var travelled: float = (car.global_position - start_position).dot(start_forward)
	print("Движение по этапу: вперёд %.1f м, скорость %.1f км/ч, контактов %d" % [travelled, car.speed_kmh, car.get_wheel_contact_count()])
	ok = ok and travelled > 8.0 and car.linear_velocity.is_finite()
	print("Этап: готов=%s, длина=%.0f м, камера=%s, дорога/шейдер=%s" % [
		stage._stage_live, stage.network.total_length, car.get_camera_label(), road != null,
	])
	stage.queue_free()
	await process_frame
	if ok:
		print("PASS: реальный этап и переключение в кабину")
		quit(0)
	else:
		printerr("FAIL: окружение, дорога, HUD или камера этапа")
		quit(1)
