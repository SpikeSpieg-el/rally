## Демо на фрагменте настоящей лесной трассы. Только визуал, без физики и
## изменения RallyGame: меню не создаёт заезд и не генерирует всю карту.
extends Node3D

const TRACK = preload("res://data/tracks/stage_forest.tres")
const ROUTE = preload("res://data/tracks/stage_forest_route.tres")
const CAR = preload("res://low_poly_lance_evo.tscn")
const PINE = preload("res://scenes/props/pine_tree.tscn")
const FIR = preload("res://scenes/props/fir_tree.tscn")
const BUSH = preload("res://scenes/props/bush.tscn")
const ROCK = preload("res://scenes/props/rock_cluster.tscn")
const GRASS = preload("res://scenes/props/grass2.tscn")
const DUST = preload("res://scripts/effects/rally_dust_fx.gd")
const GROUND_SHADER = preload("res://shaders/forest_ground.gdshader")
const ROAD_SHADER = preload("res://shaders/gravel_road.gdshader")
const GROUND_TEXTURE = preload("res://textures/environment/forest_floor.png")
const ROCK_TEXTURE = preload("res://textures/environment/rock.png")
const GRAVEL_TEXTURE = preload("res://textures/environment/gravel.png")

# Запас дороги за камерой и впереди: смена участка скрыта коротким затемнением.
const BUILD_START := 70.0
const BUILD_END := 540.0
const DRIVE_START := 115.0
const DRIVE_END := 455.0
const SPEED := 19.0
const ROAD_STEP := 3.0

var car: Node3D
var camera: Camera3D
var distance := 155.0
var elapsed := 0.0
var fade := 1.0
var wheels: Array[Node3D] = []


func _ready() -> void:
	_build_world()
	_update_drive()


func _process(delta: float) -> void:
	elapsed += delta
	distance += delta * SPEED
	if distance >= DRIVE_END:
		distance = DRIVE_START + fposmod(distance - DRIVE_END, DRIVE_END - DRIVE_START)
	fade = minf(smoothstep(DRIVE_START, DRIVE_START + 12.0, distance), (1.0 - smoothstep(DRIVE_END - 12.0, DRIVE_END, distance)))
	for wheel in wheels:
		wheel.rotate_x(-delta * SPEED / 0.35)
	_update_drive()


func _point(d: float) -> Vector3:
	return ROUTE.sample_baked(clampf(d, 0.0, ROUTE.get_baked_length()), true)


func _direction(d: float) -> Vector3:
	return (_point(d + 1.0) - _point(d - 1.0)).normalized()


func _side(d: float) -> Vector3:
	var dir := _direction(d)
	return Vector3(-dir.z, 0.0, dir.x).normalized()


# Рельеф идёт от кювета в холмы; край дороги остаётся на высоте её оси.
func _terrain_height(d: float, lateral: float) -> float:
	var away := maxf(0.0, absf(lateral) - 7.0)
	var hills := (0.5 + 0.5 * sin(d * 0.022 + lateral * 0.031)) * 5.0
	return _point(d).y - 0.08 + minf(away / 28.0, 1.0) * hills + sin(d * 0.08 + lateral * 0.12) * minf(away * 0.025, 0.7)


func _build_world() -> void:
	var env := Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.28, 0.4, 0.55)
	sky_material.sky_horizon_color = Color(0.82, 0.8, 0.74)
	sky_material.ground_horizon_color = Color(0.70, 0.72, 0.66)
	var sky := Sky.new()
	sky.sky_material = sky_material
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.70, 0.73, 0.70)
	env.ambient_light_energy = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.80, 0.76)
	env.fog_density = 0.006
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 110, 0)
	sun.light_color = Color(1.0, 0.90, 0.74)
	sun.light_energy = 1.2
	# В меню тени от сотен деревьев слишком дороги; текстуры и свет дают объём.
	sun.shadow_enabled = false
	add_child(sun)

	_build_surface(false)
	_build_surface(true)
	_build_scenery()
	_build_car()
	camera = Camera3D.new()
	camera.fov = 46.0
	camera.far = 240.0
	camera.current = true
	add_child(camera)


func _surface_material(road: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = ROAD_SHADER if road else GROUND_SHADER
	if road:
		material.set_shader_parameter("gravel_texture", GRAVEL_TEXTURE)
		material.set_shader_parameter("gravel_texture_smooth", GRAVEL_TEXTURE)
	else:
		material.set_shader_parameter("ground_texture", GROUND_TEXTURE)
		material.set_shader_parameter("ground_texture_smooth", GROUND_TEXTURE)
		material.set_shader_parameter("rock_texture", ROCK_TEXTURE)
		material.set_shader_parameter("rock_texture_smooth", ROCK_TEXTURE)
		material.set_shader_parameter("ground_color", TRACK.ground_color)
		material.set_shader_parameter("ground_color_2", TRACK.ground_color_2)
		material.set_shader_parameter("rock_color", TRACK.rock_color)
	return material


func _surface_vertex(surface: SurfaceTool, d: float, lateral: float, road: bool) -> void:
	var point := _point(d) + _side(d) * lateral
	if road:
		point.y -= TRACK.road_camber * pow(absf(lateral) / 7.0, 2.0)
		point.y += 0.04
		var shade := 0.94 + 0.06 * sin(d * 0.13 + lateral)
		var color: Color = TRACK.road_color.lerp(TRACK.road_color_2, 0.3) * shade
		if absf(lateral) > TRACK.road_half_width:
			color = color.lerp(TRACK.shoulder_color, 0.5)
		surface.set_color(color)
	else:
		point.y = _terrain_height(d, lateral)
		var shoulder := 1.0 - smoothstep(7.0, 16.0, absf(lateral))
		surface.set_color(Color(shoulder, 1.0, 0.5, 1.0))
	surface.set_uv(Vector2(lateral, d))
	surface.add_vertex(point)


func _build_surface(road: bool) -> void:
	var lanes: Array[float] = [-7.0, -5.0, -2.5, 0.0, 2.5, 5.0, 7.0] if road else [-75.0, -48.0, -28.0, -16.0, -7.0, 0.0, 7.0, 16.0, 28.0, 48.0, 75.0]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := ceili((BUILD_END - BUILD_START) / ROAD_STEP)
	for row in range(rows):
		var d0 := BUILD_START + (BUILD_END - BUILD_START) * float(row) / float(rows)
		var d1 := BUILD_START + (BUILD_END - BUILD_START) * float(row + 1) / float(rows)
		for lane in range(lanes.size() - 1):
			var a := lanes[lane]
			var b := lanes[lane + 1]
			_surface_vertex(surface, d0, b, road)
			_surface_vertex(surface, d0, a, road)
			_surface_vertex(surface, d1, a, road)
			_surface_vertex(surface, d1, b, road)
			_surface_vertex(surface, d0, b, road)
			_surface_vertex(surface, d1, a, road)
	surface.generate_normals()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Road" if road else "Terrain"
	mesh_instance.mesh = surface.commit()
	mesh_instance.material_override = _surface_material(road)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)


func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	# Секции дают MultiMesh нормальное отсечение: в кадр попадают только
	# ближайшие участки, а не 220 сцен с коллизиями и сотнями draw calls.
	for chunk in range(7):
		var start := BUILD_START + float(chunk) * 70.0
		var end := minf(start + 70.0, BUILD_END)
		if end <= start:
			continue
		for spec in [[PINE, 35, 10.0, 42.0], [FIR, 24, 12.0, 55.0], [BUSH, 24, 7.5, 25.0], [ROCK, 10, 8.0, 32.0], [GRASS, 75, 7.5, 28.0]]:
			var transforms: Array[Transform3D] = []
			for i in range(int(spec[1])):
				var d := rng.randf_range(start, end)
				var lateral := rng.randf_range(float(spec[2]), float(spec[3])) * (-1.0 if i % 2 == 0 else 1.0)
				var p := _point(d) + _side(d) * lateral
				p.y = _terrain_height(d, lateral)
				var scale_value := rng.randf_range(0.65, 1.05)
				transforms.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale_value), p))
			_add_multimesh(spec[0], transforms)


func _add_multimesh(scene: PackedScene, transforms: Array[Transform3D]) -> void:
	var template := scene.instantiate() as Node3D
	# Все используемые игровые пропсы состоят из мешей первого уровня.
	for child in template.get_children():
		if not child is MeshInstance3D:
			continue
		var part := child as MeshInstance3D
		if part.mesh == null:
			continue
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = part.mesh
		batch.instance_count = transforms.size()
		var local_transform := template.transform * part.transform
		for i in range(transforms.size()):
			batch.set_instance_transform(i, transforms[i] * local_transform)
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = batch
		instance.material_override = part.material_override
		# У grass2 материал назначен на поверхность, а не на mesh.
		if part.get_surface_override_material_count() > 0 and part.get_surface_override_material(0) != null:
			instance.material_override = part.get_surface_override_material(0)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
	template.free()


func _build_car() -> void:
	car = Node3D.new()
	car.name = "DemoCar"
	add_child(car)
	var model := CAR.instantiate() as Node3D
	model.position = Vector3(0, -1.0842417, 0.82839704)
	model.rotation.y = PI
	car.add_child(model)
	for wheel_name in ["Mitsubishi_Wheel_Bk_L", "Mitsubishi_Wheel_Bk_R", "Mitsubishi_Wheel_Ft_L", "Mitsubishi_Wheel_Ft_R"]:
		var wheel := model.get_node_or_null(wheel_name) as Node3D
		if wheel != null:
			wheels.append(wheel)
	var dust := CPUParticles3D.new()
	dust.name = "Dust"
	dust.position = Vector3(0, 0.3, 2.0)
	dust.amount = 24
	dust.lifetime = 1.4
	dust.local_coords = false
	dust.direction = Vector3(0, 0.3, 1)
	dust.spread = 30.0
	dust.initial_velocity_min = 1.0
	dust.initial_velocity_max = 3.0
	dust.gravity = Vector3(0, 0.25, 0)
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 1.3
	dust.color = Color(0.56, 0.49, 0.38, 0.45)
	dust.color_ramp = DUST.fade_ramp().gradient
	var puff := QuadMesh.new()
	puff.size = Vector2(2.0, 2.0)
	puff.material = DUST.puff_material(DUST.puff_texture())
	dust.mesh = puff
	car.add_child(dust)


func _update_drive() -> void:
	var p := _point(distance)
	var direction := _direction(distance)
	var right := _side(distance)
	car.position = p + Vector3.UP * (0.05 + sin(elapsed * 8.0) * 0.025)
	car.look_at(car.position + direction, Vector3.UP)
	camera.position = p - direction * 12.0 + right * 4.5 + Vector3.UP * 4.5
	camera.look_at(p + direction * 7.0 - right * 4.0 + Vector3.UP, Vector3.UP)
