# godot --headless --path . --script res://tests/surface_effects.gd
extends SceneTree

const Effects = preload("res://scripts/surface_effects.gd")
var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var effects = Effects.new()
	check(effects.amounts == Vector4.ZERO, "новая машина чистая")
	effects.accumulate(0, "asphalt", 1.0, 20.0, 1.0, 10.0)
	check(effects.amounts == Vector4.ZERO, "чистый асфальт не создаёт грязь")
	effects.accumulate(0, "mud", 1.0, 0.0, 1.0, 10.0)
	check(effects.amounts == Vector4.ZERO, "стоящая машина не пачкается сама")
	effects.accumulate(0, "mud", 1.0, 12.0, 1.0, 1.0)
	check(effects.amounts.x > 0.0 and effects.damp.x > 0.0, "мокрый грунт даёт налёт")
	check(effects.amounts.y == 0.0 and effects.amounts.z == 0.0 and effects.amounts.w == 0.0, "загрязняется только зона активного колеса")
	effects.accumulate(1, "gravel", 0.0, 12.0, 0.0, 1.0)
	check(effects.amounts.y > 0.0 and effects.amounts.y < effects.amounts.x, "сухая пыль накапливается медленнее грязи")
	check(effects.damp.y == 0.0, "сухая пыль не становится мокрой")
	effects.accumulate(2, "mud", 1.0, 100.0, 100.0, 10000.0)
	check(effects.amounts.z == 1.0 and effects.damp.z == 1.0, "насыщение ограничено")
	var car := Node3D.new()
	var model := Node3D.new()
	model.name = "low poly lance evo"
	car.add_child(model)
	var body := MeshInstance3D.new()
	body.name = "Mitsubishi_Body"
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color.RED
	body.material_override = paint
	model.add_child(body)
	effects.install(car)
	check(body.material_overlay != null, "грязь — отдельный слой на кузове")
	check(body.material_override == paint and paint.albedo_color == Color.RED, "исходная краска не меняется")
	check(effects._sprays.size() == 4, "каждое колесо имеет собственный выброс грунта")
	effects.clear()
	check(effects.amounts == Vector4.ZERO and effects.damp == Vector4.ZERO, "сброс загрязнения")
	car.free()
	effects.free()
	if failures == 0:
		print("PASS: независимые зоны грязи, насыщение, материалы и выброс грунта")
	quit(0 if failures == 0 else 1)
