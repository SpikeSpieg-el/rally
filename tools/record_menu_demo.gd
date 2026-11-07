# Запись базового демо физическим автопилотом (не записанные позиции).
# godot --headless --path . --fixed-fps 120 --script res://tools/record_menu_demo.gd
extends SceneTree

const Stage = preload("res://scenes/menu/menu_stage.tscn")
const Driver = preload("res://scripts/menu/menu_driver.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/menu"))
	var stage := Stage.instantiate()
	root.add_child(stage)
	var driver = stage.get_node("Driver")
	var car = stage.get_node("RallyCar")
	var route: Path3D = stage.get_node("Track")
	driver.mode = Driver.Mode.AUTO
	driver.recording_path = "res://data/menu/demo_drive.tres"
	driver.max_record_seconds = 75.0
	driver.begin_recording()
	var worst_distance := 0.0
	var previous: Vector3 = car.global_position
	var jump := false
	var completed_lap := false
	var previous_offset := 0.0
	var length := route.curve.get_baked_length()
	while driver._is_recording:
		await physics_frame
		var local := route.to_local(car.global_position)
		var closest := route.curve.get_closest_point(local)
		var offset := route.curve.get_closest_offset(local)
		if previous_offset > length * 0.75 and offset < length * 0.1:
			completed_lap = true
			driver.finish_recording()
		previous_offset = offset
		worst_distance = maxf(worst_distance, local.distance_to(closest))
		if car.global_position.distance_to(previous) > 10.0:
			jump = true
		previous = car.global_position
	print("Menu recording: frames=%d, max deviation=%.1fm, reset=%s, lap=%s" % [driver._frames.size() / 4, worst_distance, jump, completed_lap])
	if driver._frames.is_empty() or worst_distance > 15.0 or jump or not completed_lap or not FileAccess.file_exists(driver.recording_path):
		printerr("Демо не удержалось на дороге; настройте Driver и повторите запись.")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(driver.recording_path))
		quit(1)
		return
	quit(0)
