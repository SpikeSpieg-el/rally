## Лёгкая автономная демонстрация: машина едет по замкнутой лесной дороге.
## Никакие настройки заезда и состояние игрока здесь не меняются.
extends Node3D

const CAR = preload("res://low_poly_lance_evo.tscn")
const TREE = preload("res://scenes/props/pine_tree.tscn")
const RADIUS_X := 85.0
const RADIUS_Z := 110.0
const ROAD_WIDTH := 10.0
const SEGMENTS := 240

var car: Node3D
var camera: Camera3D
var distance_angle := 0.0
var elapsed := 0.0
var wheels: Array[Node3D] = []


func _ready() -> void:
	_build_world()
	_update_drive(0.0)


func _process(delta: float) -> void:
	elapsed += delta
	# Движение по непрерывному кольцу, а не смена неподвижных кадров.
	distance_angle = fposmod(distance_angle + delta * 0.15, TAU)
	for wheel in wheels:
		wheel.rotate_x(delta * 15.0)
	_update_drive(delta)


func _point(angle: float) -> Vector3:
	return Vector3(cos(angle) * RADIUS_X, 0.0, sin(angle) * RADIUS_Z)


func _tangent(angle: float) -> Vector3:
	return Vector3(-sin(angle) * RADIUS_X, 0.0, cos(angle) * RADIUS_Z).normalized()


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.48, 0.57, 0.57)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.74, 0.79, 0.73)
	env.ambient_light_energy = 0.8
	env.fog_enabled = true
	env.fog_light_color = Color(0.56, 0.62, 0.59)
	env.fog_density = 0.004
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)

	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(800, 800)
	ground_mesh.material = _material(Color(0.24, 0.31, 0.21))
	ground.mesh = ground_mesh
	ground.position.y = -0.08
	add_child(ground)

	# Полотно повторяет траекторию машины; крайние полосы создают обочины.
	_add_road_strip(ROAD_WIDTH + 3.2, Color(0.35, 0.34, 0.25), 0.0)
	_add_road_strip(ROAD_WIDTH, Color(0.51, 0.43, 0.32), 0.015)
	_add_road_strip(ROAD_WIDTH - 2.0, Color(0.57, 0.49, 0.37), 0.025)

	var rng := RandomNumberGenerator.new()
	rng.seed = 47021
	# Лес с обеих сторон, с зазором до обочины; одинаковый результат при каждом запуске.
	for i in range(220):
		var angle := rng.randf_range(0.0, TAU)
		var side := -1.0 if i % 2 == 0 else 1.0
		var outward := Vector3(cos(angle), 0, sin(angle)).normalized()
		var tree := TREE.instantiate() as Node3D
		tree.position = _point(angle) + outward * side * rng.randf_range(10.0, 60.0)
		var tree_scale := rng.randf_range(0.55, 1.15)
		tree.scale = Vector3.ONE * tree_scale
		tree.rotation.y = rng.randf_range(0.0, TAU)
		add_child(tree)

	car = Node3D.new()
	car.name = "DemoCar"
	add_child(car)
	var model := CAR.instantiate() as Node3D
	# Такой же центр модели используется в существующем гараже.
	model.position = Vector3(0, -1.0842417, 0.82839704)
	# У исходной модели перед смотрит в +Z; Node3D.look_at использует -Z.
	model.rotation.y = PI
	car.add_child(model)
	for wheel_name in ["Mitsubishi_Wheel_Bk_L", "Mitsubishi_Wheel_Bk_R", "Mitsubishi_Wheel_Ft_L", "Mitsubishi_Wheel_Ft_R"]:
		var wheel := model.get_node_or_null(wheel_name) as Node3D
		if wheel != null:
			wheels.append(wheel)

	var dust := CPUParticles3D.new()
	dust.name = "Dust"
	dust.position = Vector3(0, 0.35, 2.0)
	dust.amount = 36
	dust.lifetime = 1.4
	dust.local_coords = false
	dust.direction = Vector3(0, 0.35, 1)
	dust.spread = 35.0
	dust.initial_velocity_min = 1.0
	dust.initial_velocity_max = 3.0
	dust.gravity = Vector3(0, 0.2, 0)
	dust.scale_amount_min = 0.3
	dust.scale_amount_max = 0.9
	dust.color = Color(0.61, 0.54, 0.43, 0.35)
	var dust_mesh := SphereMesh.new()
	dust_mesh.radius = 0.3
	dust_mesh.height = 0.6
	var dust_material := _material(Color(0.67, 0.59, 0.48, 0.35))
	dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mesh.material = dust_material
	dust.mesh = dust_mesh
	car.add_child(dust)

	camera = Camera3D.new()
	camera.fov = 48.0
	camera.far = 400.0
	camera.current = true
	add_child(camera)


func _add_road_strip(width: float, color: Color, height: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(SEGMENTS):
		var a := TAU * float(i) / float(SEGMENTS)
		var b := TAU * float(i + 1) / float(SEGMENTS)
		var side_a := Vector3(-_tangent(a).z, 0, _tangent(a).x) * width * 0.5
		var side_b := Vector3(-_tangent(b).z, 0, _tangent(b).x) * width * 0.5
		var p1 := _point(a) + side_a + Vector3.UP * height
		var p2 := _point(a) - side_a + Vector3.UP * height
		var p3 := _point(b) + side_b + Vector3.UP * height
		var p4 := _point(b) - side_b + Vector3.UP * height
		for point in [p1, p2, p3, p3, p2, p4]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(point)
	var road := MeshInstance3D.new()
	road.mesh = surface.commit()
	var material := _material(color)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	road.material_override = material
	add_child(road)


func _update_drive(_delta: float) -> void:
	var direction := _tangent(distance_angle)
	var right := Vector3(-direction.z, 0, direction.x)
	var p := _point(distance_angle)
	car.position = p + Vector3.UP * (0.05 + sin(elapsed * 8.0) * 0.025)
	car.look_at(car.position + direction, Vector3.UP)
	camera.position = p - direction * 12.0 + right * 5.5 + Vector3.UP * 5.0
	camera.look_at(p + direction * 7.0 - right * 4.5 + Vector3.UP * 0.8, Vector3.UP)
