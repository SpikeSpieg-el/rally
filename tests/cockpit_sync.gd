# godot --headless --path . --script res://tests/cockpit_sync.gd
extends SceneTree

const CarScene = preload("res://scenes/rally_car.tscn")
const HudScene = preload("res://scenes/ui/rally_hud.tscn")
const StageScript = preload("res://scripts/rally_stage.gd")
const CarScript = preload("res://scripts/rally_car.gd")
const CarSetupScript = preload("res://scripts/data/rally_car_setup.gd")
const TrackConfigScript = preload("res://scripts/data/rally_track_config.gd")
const HudStyle = preload("res://scripts/data/rally_hud_style.gd")
const SpeedometerScript = preload("res://scripts/ui/sprite_speedometer.gd")
const CockpitScript = preload("res://scripts/ui/rally_cockpit.gd")

var _failures: int = 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: %s" % msg)
		_failures += 1


func _initialize() -> void:
	_test_cockpit_sync_with_car_and_hud()
	_test_hud_hides_redundant_panels_in_cockpit()
	if _failures == 0:
		print("PASS: синхронизация кабины (RallyCockpit), сетапа машины и скрытие дублирующего HUD в 1-м лице")
	quit(0 if _failures == 0 else 1)


func _test_cockpit_sync_with_car_and_hud() -> void:
	var car := CarScene.instantiate()
	var setup := CarSetupScript.new()
	setup.display_name = "TEST SPEC"
	setup.max_rpm = 8200.0
	setup.transmission_mode = CarSetupScript.Transmission.MANUAL_CLUTCH
	setup.drivetrain = 1 # RWD
	car.active_setup = setup
	car.max_rpm = 8200.0
	car.transmission_mode = CarSetupScript.Transmission.MANUAL_CLUTCH
	car.drivetrain_mode = CarScript.DrivetrainMode.RWD
	car.speed_kmh = 100.0
	car.current_rpm = 6450.0
	car.motor_rpm = 6450.0
	car.current_gear = -1
	car.motor_is_redline = true
	car.steering_amount = 0.5
	car.throttle_amount = 0.8
	car.brake_amount = 0.25
	car.clutch_amount = 0.9
	car.handbrake_input = 0.6

	var stage := StageScript.new()
	var trk := TrackConfigScript.new()
	trk.display_name = "GR TEST STAGE"
	stage.track = trk
	stage.stage_time = 75.5

	var sp := SpeedometerScript.new()
	sp.speed_units = SpeedometerScript.SpeedUnits.KMH
	sp.speed_scale = 1.0
	sp.speed_smooth_speed = 0.0
	sp.rpm_smooth_speed = 0.0
	sp.set_telemetry(car.speed_kmh, car.current_rpm, car.max_rpm, car.get_gear_label(), car.motor_is_redline)

	var cockpit := car.get_node("RallyCockpit") as CockpitScript
	_check(cockpit != null, "RallyCockpit в сцене RallyCar должен использовать RallyCockpit")
	cockpit._cache_nodes()
	cockpit._ensure_motec_corner_labels()
	cockpit.bind_vehicle(car, stage, sp)
	cockpit.sync_dashboard(0.0)

	_check(cockpit.gear_label.text == "R", "передача в кабине должна быть R (а не -1), получено %s" % cockpit.gear_label.text)
	_check(cockpit.speed_label.text == "100 KM/H", "скорость в кабине должна быть 100 KM/H, получено %s" % cockpit.speed_label.text)
	_check(cockpit.rpm_label.text == "6450 RPM", "обороты в кабине должны совпадать с current_rpm (6450 RPM), получено %s" % cockpit.rpm_label.text)
	_check(cockpit.mode_label.text.contains("МКПП") and cockpit.mode_label.text.contains("RWD"), "ModeLabel должен отражать текущие КПП и привод: %s" % cockpit.mode_label.text)
	_check(cockpit.limit_label.text == "REDLINE!", "LimitLabel должен показывать REDLINE! при отсечке")
	_check(cockpit.pedal_clutch != null and absf(cockpit.pedal_clutch.rotation.x) > 0.05, "педаль сцепления должна анимироваться")
	_check(absf(cockpit.steering_pivot.rotation.z) > 0.1, "руль должен поворачиваться от steering_amount")
	_check(cockpit.tripmaster_label.text.contains("GR TEST STAGE") and cockpit.tripmaster_label.text.contains("01:15.50") and cockpit.tripmaster_label.text.contains("TEST SPEC"), "TripmasterLabel должен показывать этап, время и сетап: %s" % cockpit.tripmaster_label.text)

	# Переключаем единицы HUD в MPH — приборка кабины должна синхронизироваться.
	sp.speed_units = SpeedometerScript.SpeedUnits.MPH
	cockpit.sync_dashboard(0.0)
	_check(cockpit.speed_label.text == "062 MPH", "при MPH в HUD кабина должна показывать 062 MPH, получено %s" % cockpit.speed_label.text)

	sp.free()
	stage.free()
	car.free()


func _test_hud_hides_redundant_panels_in_cockpit() -> void:
	var hud_node := HudScene.instantiate()
	get_root().add_child(hud_node)

	var speed_p := hud_node.get_node("SpeedPanel") as Control
	var radio_p := hud_node.get_node("RadioCard") as Control
	var timer_p := hud_node.get_node("TimerPanel") as Control
	var tele_p := hud_node.get_node("TelemetryPanel") as Control

	hud_node.call("set_camera_mode", CarScript.CameraMode.CHASE_3RD)
	_check(speed_p.visible == true, "в 3-м лице SpeedPanel должен быть видим")
	_check(radio_p.visible == true, "в 3-м лице RadioCard должен быть видим")
	_check(timer_p.visible == true, "в 3-м лице TimerPanel должен быть видим")

	hud_node.call("set_camera_mode", CarScript.CameraMode.COCKPIT_1ST)
	_check(speed_p.visible == false, "в 1-м лице дублирующий SpeedPanel должен скрываться")
	_check(radio_p.visible == false, "в 1-м лице дублирующий RadioCard должен скрываться")
	_check(timer_p.visible == true, "в 1-м лице TimerPanel должен оставаться видимым по умолчанию")
	_check(tele_p.visible == true, "в 1-м лице TelemetryPanel должен оставаться видимым по умолчанию")

	# Смена стиля на KEEP_ALL_HUD должна возвращать панели.
	hud_node.set("cockpit_hide_mode", 2) # KEEP_ALL_HUD
	_check(speed_p.visible == true and radio_p.visible == true, "KEEP_ALL_HUD должен показывать весь HUD даже в кабине")

	# Возврат к AUTO_FROM_STYLE и смена камеры обратно на 3-е лицо.
	hud_node.set("cockpit_hide_mode", 0)
	_check(speed_p.visible == false and radio_p.visible == false, "AUTO_FROM_STYLE в кабине снова скрывает дубликаты")

	var style_res := hud_node.get("hud_style") as HudStyle
	style_res.cockpit_hide_telemetry_panel = true
	_check(tele_p.visible == false, "флаг hud_style.cockpit_hide_telemetry_panel должен скрывать TelemetryPanel в кабине")

	hud_node.call("set_camera_mode", CarScript.CameraMode.CHASE_3RD)
	_check(speed_p.visible == true and radio_p.visible == true and tele_p.visible == true, "при выходе из кабины все скрытые панели должны восстановиться")

	style_res.cockpit_hide_telemetry_panel = false
	hud_node.queue_free()
