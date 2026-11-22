extends SceneTree

const BannerScene := preload("res://scenes/props/sponsor_banner.tscn")
const ShowroomScene := preload("res://scenes/garage_showroom.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _shot(index: int) -> void:
	RenderingServer.force_draw(false)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.resize(960, 540, Image.INTERPOLATE_BILINEAR)
	img.save_jpg("/tmp/shots/shot_%d.jpg" % index, 0.6)


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.35, 0.5, 0.65)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.5, 0)
	world.add_child(sun)
	var banner := BannerScene.instantiate() as Node3D
	banner.position = Vector3(-2.2, 0, 0)
	world.add_child(banner)
	# Как на трассе: экран через MultiMesh, три щита с разной фазой.
	var screen := banner.get_node("Mesh_screen_front") as MeshInstance3D
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = screen.mesh
	mm.instance_count = 3
	for i in range(3):
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.45), Vector3(2.6, 3.2 - i * 0.85, 0.5)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = screen.material_override
	world.add_child(mmi)
	var cam := Camera3D.new()
	cam.position = Vector3(0.2, 2.1, 6.2)
	world.add_child(cam)
	cam.look_at(Vector3(0.2, 2.0, 0))
	cam.current = true
	for i in range(4):
		await create_timer(0.8).timeout
		await _shot(i)
	# Обратная сторона щита.
	cam.position = Vector3(-2.2, 2.1, -5.0)
	cam.look_at(Vector3(-2.2, 2.1, 0))
	await create_timer(0.3).timeout
	await _shot(4)
	quit(0)
