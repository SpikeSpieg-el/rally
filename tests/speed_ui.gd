# godot --headless --path . --script res://tests/speed_ui.gd
extends SceneTree

const Stage = preload("res://scripts/rally_stage.gd")
const Car = preload("res://scripts/rally_car.gd")

func _initialize() -> void:
	# Вне дерева: не запускаем генерацию трассы и физику автомобиля.
	var stage = Stage.new()
	var car = Car.new()
	var label := Label.new()
	stage.car = car
	stage.speed_label = label
	var cases := {0.0: "000", 5.0: "005", 50.0: "050", 99.4: "099", 99.6: "100", 120.0: "120", 1000.0: "1000"}
	var failures := 0
	for speed in cases:
		car.speed_kmh = speed
		stage._update_hud()
		if label.text != cases[speed]:
			printerr("FAIL: %.1f км/ч: %s вместо %s" % [speed, label.text, cases[speed]])
			failures += 1
	label.free()
	car.free()
	stage.free()
	if failures == 0:
		print("PASS: скорость в HUD, ведущие нули и округление")
	quit(0 if failures == 0 else 1)
