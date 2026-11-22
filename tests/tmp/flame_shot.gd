extends SceneTree

const CarModels = preload("res://scripts/car_models.gd")
const SETUP := preload("res://data/setups/11_gravel.tres")


class GameStub:
	extends Node
	var race_vehicle_id := "golf"

	func get_race_vehicle_id() -> String:
		return race_vehicle_id


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(800, 450)
	var game := GameStub.new()
	game.name = "RallyGame"
	root.add_child(game)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.06, 0.09)
	env.environment.ambient_light_color = Color(0.3, 0.3, 0.35)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 0.4
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	world.add_child(ground)
	var shots := 0
	for id in ["golf", "mitsubishi"]:
		game.race_vehicle_id = id
		var scene := load(CarModels.race_scene_path(id)) as PackedScene
		var setup := SETUP.duplicate(true) as RallyCarSetup
		setup.turbo = true
		var car := scene.instantiate() as RallyCar
		car.setup_override = setup
		car.mouse_look_enabled = false
		car.freeze = true
		world.add_child(car)
		for view in [Vector3(2.6, 1.0, -5.0), Vector3(4.5, 0.8, -1.2)]:
			for i in range(5):
				await process_frame
			var cam := Camera3D.new()
			world.add_child(cam)
			cam.position = view
			cam.look_at(Vector3(0, 0.4, -2.6))
			cam.make_current()
			for i in range(3):
				await process_frame
			car.exhaust_flames.fire(1.0, true)
			for i in range(3):
				await process_frame
			var img := root.get_texture().get_image()
			img.save_jpg("/tmp/shot_%d.jpg" % shots, 0.8)
			shots += 1
			cam.queue_free()
		car.queue_free()
		await process_frame
	quit(0)
