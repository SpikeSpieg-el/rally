# Запуск: godot --headless --path . --fixed-fps 120 --script res://tests/rally_regression.gd
# Проверка маркеров, параметров ночи и поведения автомобиля на плоском гравии.
extends SceneTree

const CarScene = preload("res://scenes/rally_car.tscn")
const CarScript = preload("res://scripts/rally_car.gd")
const StageScript = preload("res://scripts/rally_stage.gd")
const TrackResource = preload("res://data/tracks/stage_forest.tres")
const SetupResource = preload("res://data/setups/11_gravel.tres")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _wait_physics(frames: int) -> void:
	for i in range(frames):
		await physics_frame


func _shader_has_uniform(shader: Shader, uniform_name: String) -> bool:
	for uniform in shader.get_shader_uniform_list():
		if uniform.name == uniform_name:
			return true
	return false


func _run() -> void:
	# Ночная и дневная ветки настройки окружения работают независимо.
	var stage = StageScript.new()
	var environment_node := WorldEnvironment.new()
	var moon := DirectionalLight3D.new()
	stage.world_environment = environment_node
	stage.sun_light = moon
	stage.track = TrackResource
	stage._configure_world()
	var env: Environment = environment_node.environment
	_check(TrackResource.night_mode, "лесной этап должен быть ночным")
	_check(env.sky.sky_material is ShaderMaterial, "ночь должна использовать шейдер неба")
	var sky_material := env.sky.sky_material as ShaderMaterial
	var sky_shader: Shader = sky_material.shader
	var road_shader: Shader = load("res://shaders/gravel_road.gdshader")
	_check(_shader_has_uniform(sky_shader, "star_intensity"), "шейдер неба должен компилироваться")
	_check(_shader_has_uniform(road_shader, "track_strength"), "шейдер гравия должен компилироваться")
	_check(env.volumetric_fog_enabled and env.fog_enabled, "для ночи должны работать оба вида тумана")
	_check(is_equal_approx(moon.light_energy, TrackResource.sun_energy), "яркость луны должна браться из трассы")
	var day_track = TrackResource.duplicate()
	day_track.night_mode = false
	stage.track = day_track
	stage._configure_world()
	_check(environment_node.environment.sky.sky_material is ProceduralSkyMaterial, "дневные трассы должны сохранять обычное небо")
	stage.free()
	environment_node.free()
	moon.free()

	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	ground.add_to_group("UnrelatedGroup") # не должно мешать распознаванию Dirt
	ground.add_to_group("Dirt")
	var ground_collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(500.0, 1.0, 500.0)
	ground_collision.shape = box
	ground_collision.position.y = -0.5
	ground.add_child(ground_collision)
	world.add_child(ground)

	var car = CarScene.instantiate()
	car.setup_override = SetupResource
	car.mouse_look_enabled = false
	car.initial_camera_mode = CarScript.CameraMode.COCKPIT_1ST
	car.chase_min_fov = 45.0
	car.cockpit_motion_strength = 0.0
	var marker: Marker3D = car.get_node("Cameras/CamCockpit")
	marker.position = Vector3(0.22, 1.83, 0.44)
	marker.rotation = Vector3(-0.08, PI + 0.12, 0.03)
	var authored_marker: Transform3D = marker.transform
	car.position.y = 0.3
	world.add_child(car)
	car.spawn_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, 0.0))
	car.apply_track_grip(TrackResource.grip_scale, TrackResource.rolling_resistance_scale, TrackResource.offroad_grip)
	_check(car.camera_mode == CarScript.CameraMode.COCKPIT_1ST, "должен применяться начальный режим камеры")
	_check(is_equal_approx(car.chase_min_fov, 45.0), "FOV камеры сзади не должен перезаписываться узлом ActiveCamera")
	_check(marker.transform.is_equal_approx(authored_marker), "запуск не должен перезаписывать маркер кабины")
	car.true_steering_amount = 0.5
	car.g_force_offset = Vector3(0.1, 0.1, 0.1)
	car._update_cameras(1.0 / 120.0)
	_check(car.active_camera.global_transform.is_equal_approx(marker.global_transform), "при нулевом движении камера должна совпадать с маркером даже при рулении")
	car.true_steering_amount = 0.0
	car.camera_mode = CarScript.CameraMode.HOOD
	car._update_cameras(1.0 / 120.0)
	_check(marker.transform.is_equal_approx(authored_marker), "вид с капота не должен двигать маркер кабины")
	car.reset_to_spawn()
	_check(marker.transform.is_equal_approx(authored_marker), "сброс машины не должен двигать маркер кабины")
	marker.position.y += 0.4
	marker.rotate_y(0.15)
	var edited_marker: Transform3D = marker.transform
	car.camera_mode = CarScript.CameraMode.COCKPIT_1ST
	car._update_cameras(1.0 / 120.0)
	_check(marker.transform.is_equal_approx(edited_marker), "изменённый маркер должен сохраняться")
	_check(car.active_camera.global_transform.is_equal_approx(marker.global_transform), "камера должна следовать за изменением маркера")
	var left_light: SpotLight3D = car.get_node("HeadlightL")
	var right_light: SpotLight3D = car.get_node("HeadlightR")
	var beam_direction: Vector3 = -left_light.transform.basis.z.normalized()
	_check(beam_direction.z > 0.9 and beam_direction.y < 0.0, "фары должны светить вперёд и немного вниз")
	_check((-right_light.transform.basis.z.normalized()).is_equal_approx(beam_direction), "обе фары должны светить в одном направлении")
	_check(left_light.light_energy > 0.0 and right_light.light_energy > 0.0 and left_light.shadow_enabled and right_light.shadow_enabled, "обе фары должны светить и отбрасывать тени")

	# Настройки в паузе меняют камеру, сохраняются и умеют вернуться к сцене.
	var test_settings_path := "user://rally_camera_regression.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_settings_path))
	var hud = load("res://scenes/ui/rally_hud.tscn").instantiate()
	root.add_child(hud)
	var options = hud.get_node("PausePanel/Box/CameraOptions")
	options.settings_path = test_settings_path
	options.initialize(car)
	_check(is_equal_approx(car.chase_min_fov, 45.0), "настройки паузы должны сохранять разрешённый сценой минимальный FOV")
	var cockpit_slider: HSlider = options.get_node("CockpitFov/Slider")
	var default_fov: float = car.cockpit_fov
	cockpit_slider.value = 88.0
	_check(is_equal_approx(car.cockpit_fov, 88.0), "ползунок должен менять FOV кабины")
	var settings_file := ConfigFile.new()
	_check(settings_file.load(test_settings_path) == OK and is_equal_approx(float(settings_file.get_value("camera", "CockpitFov", 0.0)), 88.0), "настройки камеры должны сохраняться")
	var motion_slider: HSlider = options.get_node("Motion/Slider")
	motion_slider.value = 0.75
	_check(is_equal_approx(car.cockpit_motion_strength, 0.75), "ползунок движения должен менять силу инерции камеры")
	var hud_reload = load("res://scenes/ui/rally_hud.tscn").instantiate()
	root.add_child(hud_reload)
	var reloaded_options = hud_reload.get_node("PausePanel/Box/CameraOptions")
	reloaded_options.settings_path = test_settings_path
	car.cockpit_fov = 60.0
	reloaded_options.initialize(car)
	_check(is_equal_approx(car.cockpit_fov, 88.0) and is_equal_approx(car.cockpit_motion_strength, 0.75), "сохранённые настройки должны восстанавливаться в следующем заезде")
	hud_reload.queue_free()
	options._reset_to_scene_defaults()
	_check(is_equal_approx(car.cockpit_fov, default_fov), "сброс настроек должен возвращать FOV из сцены")
	_check(marker.transform.is_equal_approx(edited_marker), "настройки камеры не должны менять маркер")
	hud.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_settings_path))

	await _wait_physics(240)
	var contact_count: int = car.get_wheel_contact_count()
	_check(contact_count >= 3, "машина должна стоять на колёсах (%d)" % contact_count)
	for wheel in car.wheel_array:
		_check(wheel.surface_type == "Dirt", "колесо должно распознать гравий среди групп поверхности")

	var old_brake: float = car.max_brake_force
	car.apply_track_grip(TrackResource.grip_scale * 1.2, 1.0, 0.45)
	_check(is_equal_approx(float(car.coefficient_of_friction["Grass"]) / float(car.coefficient_of_friction["Dirt"]), 0.45), "offroad_grip должен менять сцепление травы относительно гравия")
	_check(car.max_brake_force > old_brake, "тормоза должны пересчитываться при изменении сцепления")
	ground.remove_from_group("Dirt")
	ground.add_to_group("Grass")
	await _wait_physics(10)
	for wheel in car.wheel_array:
		_check(wheel.surface_type == "Grass", "колесо должно переключаться на траву")
		_check(is_equal_approx(wheel.current_cof, float(car.coefficient_of_friction["Grass"])), "должно применяться сцепление травы")
	ground.remove_from_group("Grass")
	ground.add_to_group("Dirt")
	await _wait_physics(10)
	car.apply_track_grip(TrackResource.grip_scale, TrackResource.rolling_resistance_scale, TrackResource.offroad_grip)
	var rear_wheel = car.rear_axle.wheels[0]
	var normal_grip: float = float(car.coefficient_of_friction[rear_wheel.surface_type])
	car.handbrake_input = 1.0
	car._update_handbrake_grip(1.0)
	_check(rear_wheel.current_cof < normal_grip * 0.7, "ручник должен ослаблять сцепление задней оси")
	car.handbrake_input = 0.0
	car._update_handbrake_grip(1.0)
	_check(is_equal_approx(rear_wheel.current_cof, normal_grip), "после ручника сцепление должно возвращаться")

	# На пробуксовке TCS не должен обрывать тягу или вмешиваться в торможение.
	car.current_gear = 1
	car.throttle_input = 1.0
	car.is_braking = false
	car.clutch_amount = 0.0
	car.motor_rpm = 4000.0
	car.torque_output = 300.0
	for wheel in car.drive_wheels:
		wheel.slip_vector.y = -1.0
	car.process_clutch(1.0 / 120.0)
	_check(car.tcs_active and car.clutch_torque > 0.0, "TCS должен плавно ограничивать, но не обрывать тягу")
	car.is_braking = true
	car.motor_rpm = 4000.0
	car.process_clutch(1.0 / 120.0)
	_check(not car.tcs_active, "TCS не должен вмешиваться при торможении")

	# Полноценная физика/ввод, а не только проверка чисел конфигурации.
	car.reset_to_spawn()
	await _wait_physics(120)
	var start_position: Vector3 = car.global_position
	Input.action_press("throttle")
	await _wait_physics(480)
	Input.action_release("throttle")
	var forward_distance: float = car.global_position.z - start_position.z
	print("Разгон: %.1f м, %.1f км/ч, контактов %d" % [forward_distance, car.speed_kmh, car.get_wheel_contact_count()])
	_check(forward_distance > 10.0 and car.speed_kmh > 15.0, "машина должна уверенно разгоняться вперёд")
	_check(car.linear_velocity.is_finite(), "скорость должна оставаться конечной")

	var forward_before: Vector3 = car.global_basis.z
	Input.action_press("steer_left")
	await _wait_physics(120)
	Input.action_release("steer_left")
	var heading_change: float = forward_before.angle_to(car.global_basis.z)
	print("Поворот: изменение курса %.1f°" % rad_to_deg(heading_change))
	_check(heading_change > deg_to_rad(3.0), "руль должен менять направление машины")

	# Удержание тормоза на месте не должно само включать задний ход.
	car.reset_to_spawn()
	await _wait_physics(120)
	start_position = car.global_position
	Input.action_press("brake")
	await _wait_physics(240)
	Input.action_release("brake")
	var hold_distance: float = (car.global_position - start_position).length()
	print("Тормоз на месте: передача %d, смещение %.2f м" % [car.current_gear, hold_distance])
	_check(car.current_gear == 1 and hold_distance < 1.0, "удержание тормоза не должно включать задний ход")

	# Задний ход включается только shift_down (Q).
	Input.action_press("shift_down")
	await _wait_physics(2)
	Input.action_release("shift_down")
	await _wait_physics(60)
	_check(car.current_gear == -1, "shift_down на месте должен включать задний ход")
	start_position = car.global_position
	Input.action_press("throttle")
	await _wait_physics(180)
	Input.action_release("throttle")
	var reverse_distance: float = (car.global_position - start_position).dot(car.global_basis.z)
	print("Задний ход: %.1f м, передача %d" % [reverse_distance, car.current_gear])
	_check(reverse_distance < -2.0, "W на задней передаче должен ехать назад")

	# S тормозит задний ход и не переключает передачу.
	var reverse_speed_before: float = car.linear_velocity.dot(car.global_basis.z)
	Input.action_press("brake")
	await _wait_physics(120)
	Input.action_release("brake")
	var reverse_speed_after: float = car.linear_velocity.dot(car.global_basis.z)
	print("Тормоз в заднем ходе: %.1f -> %.1f м/с, передача %d" % [reverse_speed_before, reverse_speed_after, car.current_gear])
	_check(car.current_gear == -1 and absf(reverse_speed_after) < absf(reverse_speed_before), "S должен тормозить задний ход, не меняя передачу")

	# shift_up (E) возвращает первую передачу, и W снова едет вперёд.
	Input.action_press("shift_up")
	await _wait_physics(2)
	Input.action_release("shift_up")
	await _wait_physics(60)
	_check(car.current_gear == 1, "shift_up из R должен включать первую передачу")
	Input.action_press("throttle")
	await _wait_physics(900)
	Input.action_release("throttle")
	print("Выход из заднего хода: передача %d, продольная скорость %.1f м/с" % [car.current_gear, car.linear_velocity.dot(car.global_basis.z)])
	_check(car.current_gear > 0 and car.linear_velocity.dot(car.global_basis.z) > 0.0, "W после включения первой передачи должен вести машину вперёд")

	world.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: камера, ночное окружение, сцепление и управление")
		quit(0)
	else:
		printerr("Ошибок: %d" % failures.size())
		quit(1)
