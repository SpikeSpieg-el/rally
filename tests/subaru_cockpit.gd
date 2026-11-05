# godot --headless --path . --script res://tests/subaru_cockpit.gd
# Салон Subaru: своя сцена, свои приборы и ни одного узла приборки Lancer.
extends SceneTree

const CarScene = preload("res://scenes/rally_car.tscn")
const Models = preload("res://scripts/car_models.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _run() -> void:
	# 1. Сцена салона Subaru существует и собрана по тем же правилам, что и
	#    салон Lancer: магнитола на центральной консоли, брелок на зеркале,
	#    руль и приборы на своих местах.
	var cockpit_text := _read_text("res://scenes/subaru_cockpit.tscn")
	_check(cockpit_text.contains('node name="SubaruCockpit"'), "нет сцены салона Subaru")
	_check(
		cockpit_text.contains("res://scripts/ui/rally_cockpit_radio.gd"),
		"в салоне Subaru нет 3D-магнитолы"
	)
	_check(
		cockpit_text.contains('parent="Dashboard/CenterConsole"'),
		"магнитола Subaru должна стоять на центральной консоли"
	)
	_check(cockpit_text.contains('node name="CharmPivot"'), "в салоне Subaru нет подвески-брелока")
	_check(cockpit_text.contains('node name="SteeringWheelPivot"'), "в салоне Subaru нет руля")
	_check(
		cockpit_text.contains('node name="MotecDisplay"'), "в салоне Subaru нет приборного табло"
	)
	_check(
		cockpit_text.contains("shift_light_to_rpm: float = 6800.0"),
		"блинкеры Subaru должны работать по отсечке EJ25",
	)
	_check(cockpit_text.contains("SUVARU"), "трипмастер Subaru должен быть подписан по-своему")

	# 2. Модель Subaru больше не тащит за собой салон Lancer: его узлов в её
	#    сцене нет вовсе, поэтому приборка Mitsubishi не может «протечь».
	var subaru_scene_text := _read_text("res://scenes/rally_car2.tscn")
	_check(
		not subaru_scene_text.contains("RallyCockpit"),
		"в сцене машины Subaru не должно быть салона Lancer"
	)
	_check(
		not subaru_scene_text.contains("MotecDisplay"),
		"в сцене машины Subaru не должно быть табло Lancer"
	)

	# 3. Салон Mitsubishi остался нетронутым.
	var lancer_scene_text := _read_text("res://scenes/rally_car.tscn")
	_check(
		lancer_scene_text.contains('node name="RallyCockpit"'),
		"салон Lancer должен остаться в своей сцене"
	)
	_check(
		lancer_scene_text.contains('parent="RallyCockpit/Dashboard/CenterConsole"'),
		"магнитола Lancer должна остаться на его консоли"
	)

	# 4. Переключение салона на живой машине: Lancer прячется, Subaru
	#    появляется вместе с магнитолой и брелоком.
	var car = CarScene.instantiate()
	car.mouse_look_enabled = false
	root.add_child(car)
	_check(Models.install_cockpit(car), "салон Subaru должен подключаться")
	var cockpit := car.get_node_or_null("SubaruCockpit")
	_check(cockpit != null and cockpit.visible, "салон Subaru должен быть виден")
	var lancer_cockpit := car.get_node_or_null("RallyCockpit")
	_check(
		lancer_cockpit != null and not lancer_cockpit.visible,
		"салон Lancer должен быть скрыт в машине Subaru"
	)
	_check(
		car.get_node_or_null("SubaruCockpit/RadioHeadUnit") != null,
		"в салоне Subaru нет узла магнитолы"
	)
	_check(
		car.get_node_or_null("SubaruCockpit/InteriorShell/RearviewMirror/CharmPivot") != null,
		"в салоне Subaru нет узла брелока"
	)
	_check(
		car.get_node_or_null("SubaruCockpit/Dashboard/SteeringColumn/SteeringWheelPivot") != null,
		"в салоне Subaru нет узла руля"
	)
	car.free()

	if failures.is_empty():
		print("PASS: салон Subaru отдельный, приборка Lancer не появляется")
		quit(0)
	else:
		printerr("Ошибок: %d" % failures.size())
		quit(1)
