# godot --headless --path . --script res://tests/driving_feedback.gd
extends SceneTree

const Feedback = preload("res://scripts/input/driving_feedback.gd")
const Manager = preload("res://scripts/input/controller_manager.gd")

func _initialize() -> void:
	var quiet: Dictionary = Feedback.calculate(0.0, 0.0, 0.0, true, 0.0, 0.0, 0.0)
	var gravel: Dictionary = Feedback.calculate(100.0, 0.8, 0.5, true, 0.7, 1.0, 1.0)
	var air: Dictionary = Feedback.calculate(100.0, 0.8, 0.5, false, 0.7, 1.0, 1.0)
	assert(gravel.weak > quiet.weak and gravel.strong > quiet.strong)
	assert(gravel.weak > air.weak)
	assert(gravel.left > quiet.left and gravel.right > quiet.right)
	var clamped: Dictionary = Feedback.calculate(10000.0, 100.0, 100.0, true, 100.0, 100.0, 100.0)
	assert(clamped.weak <= 1.0 and clamped.strong <= 1.0 and clamped.left <= 1.0 and clamped.right <= 1.0)
	var manager := Manager.new()
	manager._settings_path = "user://feedback_test.cfg"
	manager.driving_vibration_enabled = false
	manager.adaptive_triggers_enabled = false
	manager.adaptive_trigger_strength = 0.25
	manager.save_settings()
	manager.driving_vibration_enabled = true
	manager.adaptive_triggers_enabled = true
	manager.adaptive_trigger_strength = 1.0
	manager.load_settings()
	assert(not manager.driving_vibration_enabled and not manager.adaptive_triggers_enabled)
	assert(is_equal_approx(manager.adaptive_trigger_strength, 0.25))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(manager._settings_path))
	manager.free()
	print("Driving feedback tests passed")
	quit()
