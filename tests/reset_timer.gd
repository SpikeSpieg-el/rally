# godot --headless --path . --script res://tests/reset_timer.gd
extends SceneTree

class TestStage extends "res://scripts/rally_stage.gd":
	func _ready() -> void:
		set_process(false)
	func _update_route_weather(_delta: float) -> void:
		pass
	func _update_hud() -> void:
		pass

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var stage := TestStage.new()
	root.add_child(stage)
	stage._stage_live = true
	stage.stage_time = 42.0
	stage.timer_running = true
	stage.cp_triggered = [true, false]
	stage.cp_times = [20.0, 0.0]
	stage.last_cp_index = 0
	Input.action_press("reset_car")
	stage._process(0.5)
	Input.action_release("reset_car")
	var ok: bool = is_equal_approx(stage.stage_time, 42.5) and stage.timer_running and stage.last_cp_index == 0 and stage.cp_triggered[0] and is_equal_approx(stage.cp_times[0], 20.0)
	# Reset after finishing must not start a second run or resubmit results.
	stage.stage_finished = true
	stage.timer_running = false
	Input.action_press("reset_car")
	stage._process(0.5)
	Input.action_release("reset_car")
	ok = ok and stage.stage_finished and not stage.timer_running and is_equal_approx(stage.stage_time, 42.5)
	stage.free()
	print("Reset timer: ", "OK" if ok else "FAIL")
	quit(0 if ok else 1)
