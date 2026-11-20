# godot --headless --path . --script res://tests/car_body_fx.gd
extends SceneTree

const Effects = preload("res://scripts/surface_effects.gd")
const CarModels = preload("res://scripts/car_models.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# Все машины реестра: список сцен берём у самой игры, а не хардкодим,
	# иначе новая машина (rally_car3, rally_car4, …) осталась бы без проверки.
	for path in CarModels.car_scene_paths():
		var car = load(path).instantiate()
		car.mouse_look_enabled = false
		root.add_child(car)
		var fx = car.surface_effects
		var meshes: Array[MeshInstance3D] = fx._body_meshes(car)
		check(not meshes.is_empty(), path + ": указан кузов")
		for mesh in meshes:
			check(mesh.material_overlay == fx._material, path + ": слой на кузове")
		var wheel = car.get_node("Wheel_FL").find_children("*", "MeshInstance3D", true, false)[0]
		check(wheel.material_overlay != fx._material, path + ": колёса без налёта кузова")
		fx.amounts = Vector4.ONE * 0.5
		fx.update(car, [], "gravel", 0.0, 0.0, 0.0, 0.0, 0.0)
		check(fx._material.get_shader_parameter("dirt_amount") == fx.amounts, path + ": налёт обновлён")
		var blood = car.blood_fx
		blood.add_splat(car, car.to_global(blood.bumper_point), Vector3(0, 0, 20))
		var splats: PackedVector4Array = fx._material.get_shader_parameter("splat_data")
		check(splats.size() == 8 and splats[0].x > 0.0, path + ": кровь в том же шейдере")
		check(meshes[0].material_overlay == fx._material, path + ": кровь не заменила грязь")
		car.free()
	# Любое имя и вложенность: пачкаем только явно отмеченный меш.
	var generic := Node3D.new()
	var painted := MeshInstance3D.new()
	painted.name = "NewCarShell"
	painted.mesh = BoxMesh.new()
	painted.add_to_group("rally_body_fx")
	generic.add_child(painted)
	var other := MeshInstance3D.new()
	other.name = "Mitsubishi_Body"
	other.mesh = BoxMesh.new()
	generic.add_child(other)
	root.add_child(generic)
	var generic_fx = Effects.new()
	generic_fx.install(generic)
	check(painted.material_overlay == generic_fx._material and other.material_overlay == null, "имя не определяет кузов")
	generic_fx.clear()
	generic_fx.free()
	generic.free()
	print("Car body FX: %d failures" % failures)
	quit(0 if failures == 0 else 1)
