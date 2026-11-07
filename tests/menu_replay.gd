# godot --headless --path . --fixed-fps 120 --script res://tests/menu_replay.gd
extends SceneTree

const Stage = preload("res://scenes/menu/menu_stage.tscn")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var stage := Stage.instantiate()
	root.add_child(stage)
	var driver = stage.get_node("Driver")
	var car = stage.get_node("RallyCar")
	var route: Path3D = stage.get_node("Track")
	var director = stage.get_node("Cinematography")
	var seen_shots := {}
	check(driver._source != null and driver._source.valid(), "в сцене назначена запись")
	if driver._source == null or not driver._source.valid():
		quit(1)
		return
	var initial: Vector3 = car.global_position
	var max_deviation := 0.0
	var max_travel := 0.0
	var laps := 0
	var camera_below_ground := false
	var last_offset := 0.0
	var curve_length := route.curve.get_baked_length()
	var total: int = driver._source.frame_count() * 2 + 10
	for i in range(total):
		await physics_frame
		seen_shots[director._shot_index] = true
		var camera_pos: Vector3 = director.camera.global_position
		var terrain = stage.get_node("Ground")
		if camera_pos.y + 0.01 < terrain.ground_height(camera_pos.x, camera_pos.z):
			camera_below_ground = true
		var point := route.to_local(car.global_position)
		var offset := route.curve.get_closest_offset(point)
		if last_offset > curve_length * 0.75 and offset < curve_length * 0.1:
			laps += 1
		last_offset = offset
		max_deviation = maxf(max_deviation, point.distance_to(route.curve.get_closest_point(point)))
		max_travel = maxf(max_travel, car.global_position.distance_to(initial))
	check(seen_shots.size() >= 4, "кинокамера переключает пролёты")
	check(laps >= 2, "машина проехала два круга на записанном управлении")
	check(not camera_below_ground, "камера не уходит под рельеф")
	check(max_travel > 80.0, "машина действительно движется по кольцу")
	check(max_deviation < float(route.get("half_width")), "машина остаётся на дорожном полотне")
	check(driver._last_frame < 20, "запись началась заново")
	print("menu_replay: failures=%d, deviation=%.2f, travel=%.1f, laps=%d" % [failures, max_deviation, max_travel, laps])
	quit(1 if failures > 0 else 0)
