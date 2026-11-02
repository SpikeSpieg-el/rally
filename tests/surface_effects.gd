# godot --headless --path . --script res://tests/surface_effects.gd
extends SceneTree

const Effects = preload("res://scripts/surface_effects.gd")
var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
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
	var previous_dirt: float = effects.amounts.x
	var previous_damp: float = effects.damp.x
	effects.update_weather(1.0, 0.0, 10.0)
	check(effects.damp.x > previous_damp and effects.amounts.x < previous_dirt, "дождь увлажняет и постепенно смывает грязь даже без движения")
	previous_damp = effects.damp.x
	effects.update_weather(0.0, 0.0, 10.0)
	check(effects.damp.x < previous_damp, "без дождя налёт высыхает")
	var dry_amount: Vector4 = effects.amounts
	effects.update_weather(0.0, 1.0, 10.0)
	check(effects.snow_amounts.x > 0.0 and effects.amounts == dry_amount, "снег накапливается поверх грязи, не смывая её")
	var snow_before: float = effects.snow_amounts.z
	effects.accumulate(2, "snow", 0.0, 12.0, 1.0, 1.0)
	check(effects.snow_amounts.z > snow_before and effects.amounts == dry_amount, "снег из-под колёс оставляет снег, а не грязь")
	snow_before = effects.snow_amounts.x
	effects.update_weather(1.0, 0.0, 1.0)
	check(effects.snow_amounts.x < snow_before, "дождь постепенно убирает снежный налёт")
	effects.update_weather(0.0, 0.0, 1000.0)
	check(effects.damp == Vector4.ZERO and effects.snow_amounts == Vector4.ZERO, "в сухую погоду налёт высыхает и снег постепенно сходит")
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
	var soil_mesh := effects._sprays[0].draw_pass_1 as SphereMesh
	check((soil_mesh.material as StandardMaterial3D).vertex_color_use_as_albedo, "частицы используют цвет снега и грязи")
	root.add_child(car)
	effects.snow_amounts = Vector4.ONE * 0.3
	effects.update(car, [], "gravel", 1.0, 0.0, 1.0, 1.0, 0.0)
	check(effects.damp.x > 0.0, "осадки обновляют налёт даже без контакта с дорогой")
	check(effects.snow_amounts.x > 0.0 and effects._material.get_shader_parameter("snow_amount") == effects.snow_amounts, "снежный налёт передаётся в шейдер")
	effects.clear()
	check(effects.amounts == Vector4.ZERO and effects.damp == Vector4.ZERO and effects.snow_amounts == Vector4.ZERO, "сброс загрязнения и снега")
	car.free()
	effects.free()
	if failures == 0:
		print("PASS: независимые зоны грязи, насыщение, материалы и выброс грунта")
	quit(0 if failures == 0 else 1)
