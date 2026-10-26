class_name RallyStage
extends Node3D

const RallyCarType = preload("res://scripts/rally_car.gd")
const ForestGroundShader = preload("res://shaders/forest_ground.gdshader")
const SCENERY_COUNT: int = 72
const SLALOM_CONE_COUNT: int = 12
const PROFILE_RANGE: int = 0
const PROFILE_FOREST: int = 1
const PROFILE_SUSPENSION: int = 2
const FOREST_SCENE: String = "res://scenes/forest_rally.tscn"
const SUSPENSION_SCENE: String = "res://scenes/forest_suspension.tscn"
const RANGE_SCENE: String = "res://scenes/rally_stage.tscn"

@export_enum("Полигон", "Лесное ралли", "Лес: подвеска") var stage_profile: int = PROFILE_RANGE

@onready var terrain: StaticBody3D = $Terrain
@onready var terrain_mesh: MeshInstance3D = $Terrain/TerrainMesh
@onready var terrain_collider: CollisionShape3D = $Terrain/TerrainCollider
@onready var scenery: Node3D = $Scenery
@onready var slalom: Node3D = $Slalom
@onready var car: RallyCarType = $RallyCar
@onready var timer_label: Label = $HUD/TopPanel/TimerLabel
@onready var split_label: Label = $HUD/TopPanel/SplitLabel
@onready var telemetry_label: Label = $HUD/BottomPanel/TelemetryBox/TelemetryLabel
@onready var rpm_bar: ProgressBar = $HUD/BottomPanel/TelemetryBox/RPMBar
@onready var speed_fx_material: ShaderMaterial = null
@onready var world_environment: WorldEnvironment = $WorldEnvironment

var stage_time: float = 0.0
var timer_running: bool = false
var stage_finished: bool = false
var map_change_pending: bool = false
var scenery_rng := RandomNumberGenerator.new()


func _ready() -> void:
	scenery_rng.seed = 4707 + stage_profile * 101
	_configure_terrain()
	_spawn_scenery()
	if stage_profile == PROFILE_RANGE:
		_spawn_slalom()
	else:
		_spawn_forest_markers()
	car.spawn_transform = _make_spawn_transform()
	car.reset_to_spawn()
	_update_hud()


func _process(delta: float) -> void:
	if _handle_map_input():
		return
	if Input.is_action_just_pressed("reset_car"):
		stage_time = 0.0
		timer_running = false
		stage_finished = false

	if Input.get_action_strength("throttle") > 0.05 and not stage_finished:
		timer_running = true
	if timer_running:
		stage_time += delta
	if stage_profile != PROFILE_RANGE and timer_running and not stage_finished:
		var finish_z: float = _stage_finish_z()
		if car.global_position.z >= finish_z and absf(car.global_position.x - _route_center_x(finish_z)) < 10.0:
			stage_finished = true
			timer_running = false

	var speed_intensity: float = clampf((car.speed_kmh - 70.0) / 130.0, 0.0, 1.0)
	if speed_fx_material != null:
		speed_fx_material.set_shader_parameter("speed_intensity", speed_intensity)
	_update_hud()


func _handle_map_input() -> bool:
	if map_change_pending:
		return true
	var target_scene: String = ""
	if Input.is_action_just_pressed("map_forest") and stage_profile != PROFILE_FOREST:
		target_scene = FOREST_SCENE
	elif Input.is_action_just_pressed("map_suspension") and stage_profile != PROFILE_SUSPENSION:
		target_scene = SUSPENSION_SCENE
	elif Input.is_action_just_pressed("map_range") and stage_profile != PROFILE_RANGE:
		target_scene = RANGE_SCENE
	if target_scene.is_empty():
		return false
	map_change_pending = true
	call_deferred("_change_map", target_scene)
	return true


func _change_map(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)


func _configure_terrain() -> void:
	if stage_profile == PROFILE_RANGE:
		return
	terrain.remove_from_group("Road")
	terrain.add_to_group("Grass")
	terrain_collider.position = Vector3.ZERO
	var mesh: ArrayMesh = _build_heightfield_mesh()
	terrain_mesh.mesh = mesh
	var ground_material := ShaderMaterial.new()
	ground_material.shader = ForestGroundShader
	ground_material.set_shader_parameter("map_profile", float(stage_profile))
	terrain_mesh.material_override = ground_material
	var collision: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	collision.backface_collision = true
	terrain_collider.shape = collision
	_build_road_collision()
	if world_environment.environment != null:
		world_environment.environment.volumetric_fog_density = 0.0012
	var speed_shader_rect = $HUD/SpeedShaderRect
	if speed_shader_rect != null:
		speed_fx_material = speed_shader_rect.material as ShaderMaterial


func _build_road_collision() -> void:
	# The terrain is Grass. This thin ribbon is Dirt and follows exactly the
	# same height function, so tires get different grip on the road and verge.
	var faces := PackedVector3Array()
	var start_z: float = _stage_start_z() - 15.0
	var end_z: float = _stage_finish_z() + 15.0
	var step: float = 1.0 if stage_profile == PROFILE_FOREST else 0.75
	var row_count: int = ceili((end_z - start_z) / step) + 1
	var previous_left := Vector3.ZERO
	var previous_right := Vector3.ZERO

	for row in range(row_count):
		var z: float = minf(start_z + float(row) * step, end_z)
		var center: float = _route_center_x(z)
		var left_x: float = center - 4.1
		var right_x: float = center + 4.1
		var left := Vector3(left_x, _terrain_height(left_x, z) + 0.018, z)
		var right := Vector3(right_x, _terrain_height(right_x, z) + 0.018, z)
		if row > 0:
			faces.append(previous_left)
			faces.append(previous_right)
			faces.append(left)
			faces.append(previous_right)
			faces.append(right)
			faces.append(left)
		previous_left = left
		previous_right = right

	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var road_body := StaticBody3D.new()
	road_body.name = "RoadSurface"
	road_body.add_to_group("Dirt")
	var collider := CollisionShape3D.new()
	collider.shape = shape
	road_body.add_child(collider)
	add_child(road_body)


func _build_heightfield_mesh() -> ArrayMesh:
	var grid_size: int = 181 if stage_profile == PROFILE_FOREST else 201
	var grid_step: float = 2.0 if stage_profile == PROFILE_FOREST else 1.25
	var half_extent: float = float(grid_size - 1) * grid_step * 0.5
	var vertex_count: int = grid_size * grid_size
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	vertices.resize(vertex_count)
	normals.resize(vertex_count)
	indices.resize((grid_size - 1) * (grid_size - 1) * 6)

	for z_index in range(grid_size):
		var z: float = -half_extent + float(z_index) * grid_step
		for x_index in range(grid_size):
			var x: float = -half_extent + float(x_index) * grid_step
			var index: int = z_index * grid_size + x_index
			var epsilon: float = 0.35
			vertices[index] = Vector3(x, _terrain_height(x, z), z)
			normals[index] = Vector3(
				_terrain_height(x - epsilon, z) - _terrain_height(x + epsilon, z),
				2.0 * epsilon,
				_terrain_height(x, z - epsilon) - _terrain_height(x, z + epsilon)
			).normalized()

	var index_cursor: int = 0
	for z_index in range(grid_size - 1):
		for x_index in range(grid_size - 1):
			var i: int = z_index * grid_size + x_index
			indices[index_cursor] = i
			indices[index_cursor + 1] = i + 1
			indices[index_cursor + 2] = i + grid_size
			indices[index_cursor + 3] = i + 1
			indices[index_cursor + 4] = i + grid_size + 1
			indices[index_cursor + 5] = i + grid_size
			index_cursor += 6

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _terrain_height(x: float, z: float) -> float:
	if stage_profile == PROFILE_RANGE:
		return 0.0
	var center: float = _route_center_x(z)
	var road_distance: float = absf(x - center)
	var road_mask: float = 1.0 - smoothstep(4.5, 7.0, road_distance)
	var road_height: float = 0.0

	if stage_profile == PROFILE_FOREST:
		road_height = 1.4 * sin(z * 0.025) + 0.65 * sin(z * 0.07) + 0.8 * sin(z * 0.013)
		road_height += 0.65 * exp(-pow((z - 42.0) / 8.0, 2.0)) * road_mask
		road_height -= 0.35 * exp(-pow((z + 58.0) / 7.0, 2.0)) * road_mask
	else:
		road_height = 0.9 * sin(z * 0.025) + 0.35 * sin(z * 0.06)
		var side_blend: float = smoothstep(-1.5, 1.5, x - center)
		var left_bump: float = 0.27 * exp(-pow((z + 70.0) / 2.8, 2.0)) * side_blend
		var right_bump: float = 0.27 * exp(-pow((z + 55.0) / 2.8, 2.0)) * (1.0 - side_blend)
		var whoops_window: float = smoothstep(-40.0, -32.0, z) * (1.0 - smoothstep(25.0, 33.0, z))
		var whoops: float = 0.14 * sin((z + 35.0) * TAU / 7.5) * whoops_window
		var crest: float = 1.10 * exp(-pow((z - 55.0) / 5.0, 2.0))
		var dip: float = -0.45 * exp(-pow((z - 85.0) / 5.0, 2.0))
		road_height += (left_bump + right_bump + whoops + crest + dip) * road_mask

	var forest_height: float = road_height
	forest_height += 1.15 * sin(x * 0.045) * sin(z * 0.026)
	forest_height += 0.48 * sin(x * 0.11 + z * 0.04)
	var blend: float = smoothstep(5.0, 18.0, road_distance)
	return lerpf(road_height, forest_height, blend)


func _route_center_x(z: float) -> float:
	if stage_profile == PROFILE_FOREST:
		return 10.0 * sin(z * 0.025) + 5.0 * sin(z * 0.061)
	if stage_profile == PROFILE_SUSPENSION:
		return 8.0 * sin(z * 0.032) + 4.0 * sin(z * 0.075)
	return 0.0


func _route_center_derivative(z: float) -> float:
	if stage_profile == PROFILE_FOREST:
		return 0.25 * cos(z * 0.025) + 0.305 * cos(z * 0.061)
	if stage_profile == PROFILE_SUSPENSION:
		return 0.256 * cos(z * 0.032) + 0.30 * cos(z * 0.075)
	return 0.0


func _stage_start_z() -> float:
	if stage_profile == PROFILE_FOREST:
		return -135.0
	if stage_profile == PROFILE_SUSPENSION:
		return -105.0
	return -25.0


func _stage_finish_z() -> float:
	if stage_profile == PROFILE_FOREST:
		return 132.0
	if stage_profile == PROFILE_SUSPENSION:
		return 102.0
	return 100000.0


func _make_spawn_transform() -> Transform3D:
	var start_z: float = _stage_start_z()
	var start_x: float = _route_center_x(start_z)
	var start_y: float = _terrain_height(start_x, start_z) + 0.20
	var yaw: float = atan2(_route_center_derivative(start_z), 1.0)
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(start_x, start_y, start_z))


func _spawn_scenery() -> void:
	var trunk_material := StandardMaterial3D.new()
	trunk_material.albedo_color = Color(0.23, 0.125, 0.065)
	trunk_material.roughness = 1.0
	var foliage_material := StandardMaterial3D.new()
	foliage_material.albedo_color = Color(0.065, 0.24, 0.115)
	foliage_material.roughness = 0.95
	var rock_material := StandardMaterial3D.new()
	rock_material.albedo_color = Color(0.29, 0.31, 0.32)
	rock_material.roughness = 0.98

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.16
	trunk_mesh.bottom_radius = 0.23
	trunk_mesh.height = 1.5
	trunk_mesh.radial_segments = 7
	trunk_mesh.surface_set_material(0, trunk_material)
	var foliage_mesh := CylinderMesh.new()
	foliage_mesh.top_radius = 0.0
	foliage_mesh.bottom_radius = 1.45
	foliage_mesh.height = 3.8
	foliage_mesh.radial_segments = 8
	foliage_mesh.surface_set_material(0, foliage_material)
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 1.0
	rock_mesh.height = 2.0
	rock_mesh.radial_segments = 7
	rock_mesh.rings = 3
	rock_mesh.surface_set_material(0, rock_material)

	if stage_profile != PROFILE_RANGE:
		_spawn_forest(trunk_mesh, foliage_mesh, rock_mesh)
		return

	for i in range(SCENERY_COUNT):
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var item_position := Vector3(
			side * scenery_rng.randf_range(48.0, 265.0),
			0.0,
			scenery_rng.randf_range(-280.0, 270.0)
		)
		var is_tree: bool = scenery_rng.randf() < 0.76
		var item: Node3D
		if is_tree:
			item = _create_pine(trunk_mesh, foliage_mesh)
			item.scale = Vector3.ONE * scenery_rng.randf_range(0.78, 1.48)
		else:
			item = _create_rock(rock_mesh)
			item.scale = Vector3(
				scenery_rng.randf_range(0.75, 1.65),
				scenery_rng.randf_range(0.55, 1.10),
				scenery_rng.randf_range(0.75, 1.55)
			)
			item_position.y = 0.35
		scenery.add_child(item)
		item.position = item_position
		item.rotation = Vector3(0.0, scenery_rng.randf_range(0.0, TAU), 0.0)


func _spawn_forest(trunk_mesh: CylinderMesh, foliage_mesh: CylinderMesh, rock_mesh: SphereMesh) -> void:
	var tree_count: int = 125 if stage_profile == PROFILE_FOREST else 105
	var half_extent: float = 155.0 if stage_profile == PROFILE_FOREST else 120.0
	var trunk_shape := CylinderShape3D.new()
	trunk_shape.radius = 0.23
	trunk_shape.height = 1.8

	for i in range(tree_count):
		var x: float = 0.0
		var z: float = 0.0
		var road_distance: float = 0.0
		for attempt in range(16):
			x = scenery_rng.randf_range(-half_extent, half_extent)
			z = scenery_rng.randf_range(-half_extent, half_extent)
			road_distance = absf(x - _route_center_x(z))
			if road_distance > 11.0 and absf(z - _stage_start_z()) > 9.0:
				break
		if road_distance < 10.0:
			continue

		var item_position := Vector3(x, _terrain_height(x, z), z)
		var is_tree: bool = scenery_rng.randf() < 0.88
		var item: Node3D
		if is_tree:
			item = _create_pine(trunk_mesh, foliage_mesh)
			item.scale = Vector3.ONE * scenery_rng.randf_range(0.82, 1.55)
			if road_distance < 55.0:
				var trunk_body := StaticBody3D.new()
				trunk_body.position = Vector3(0.0, 0.9, 0.0)
				var trunk_collider := CollisionShape3D.new()
				trunk_collider.shape = trunk_shape
				trunk_body.add_child(trunk_collider)
				item.add_child(trunk_body)
		else:
			item = _create_rock(rock_mesh)
			item.scale = Vector3(
				scenery_rng.randf_range(0.65, 1.45),
				scenery_rng.randf_range(0.45, 0.95),
				scenery_rng.randf_range(0.65, 1.35)
			)
			item_position.y += 0.25
		scenery.add_child(item)
		item.position = item_position
		item.rotation = Vector3(0.0, scenery_rng.randf_range(0.0, TAU), 0.0)


func _create_pine(trunk_mesh: CylinderMesh, foliage_mesh: CylinderMesh) -> Node3D:
	var pine := Node3D.new()
	pine.name = "Pine"
	var trunk := MeshInstance3D.new()
	trunk.mesh = trunk_mesh
	trunk.position = Vector3(0.0, 0.75, 0.0)
	pine.add_child(trunk)
	var foliage := MeshInstance3D.new()
	foliage.mesh = foliage_mesh
	foliage.position = Vector3(0.0, 2.60, 0.0)
	pine.add_child(foliage)
	var upper_foliage := MeshInstance3D.new()
	upper_foliage.mesh = foliage_mesh
	upper_foliage.position = Vector3(0.0, 3.75, 0.0)
	upper_foliage.scale = Vector3.ONE * 0.65
	pine.add_child(upper_foliage)
	return pine


func _create_rock(rock_mesh: SphereMesh) -> MeshInstance3D:
	var rock := MeshInstance3D.new()
	rock.name = "Boulder"
	rock.mesh = rock_mesh
	return rock


func _spawn_slalom() -> void:
	var cone_material := StandardMaterial3D.new()
	cone_material.albedo_color = Color(1.0, 0.22, 0.025)
	cone_material.emission_enabled = true
	cone_material.emission = Color(0.35, 0.035, 0.005)
	cone_material.emission_energy_multiplier = 0.6
	cone_material.roughness = 0.72
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.035
	cone_mesh.bottom_radius = 0.25
	cone_mesh.height = 0.70
	cone_mesh.radial_segments = 12
	cone_mesh.surface_set_material(0, cone_material)

	for i in range(SLALOM_CONE_COUNT):
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var cone := MeshInstance3D.new()
		cone.name = "SlalomCone_%02d" % i
		cone.mesh = cone_mesh
		cone.position = Vector3(side * 6.0, 0.35, 5.0 + float(i) * 16.0)
		slalom.add_child(cone)

	for side in [-1.0, 1.0]:
		var start_cone := MeshInstance3D.new()
		start_cone.mesh = cone_mesh
		start_cone.position = Vector3(float(side) * 5.0, 0.35, -10.0)
		slalom.add_child(start_cone)


func _spawn_forest_markers() -> void:
	_create_gate(_stage_start_z() + 5.0, Color(0.20, 0.80, 1.0))
	_create_gate(_stage_finish_z(), Color(1.0, 0.48, 0.08))

	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.12, 0.80, 0.12)
	var left_material := StandardMaterial3D.new()
	left_material.albedo_color = Color(0.95, 0.95, 0.88)
	var right_material := StandardMaterial3D.new()
	right_material.albedo_color = Color(0.95, 0.16, 0.08)
	var z: float = _stage_start_z() + 20.0
	while z < _stage_finish_z() - 8.0:
		for side in [-1.0, 1.0]:
			var x: float = _route_center_x(z) + float(side) * 5.2
			var post := MeshInstance3D.new()
			post.mesh = post_mesh
			post.material_override = left_material if side < 0.0 else right_material
			post.position = Vector3(x, _terrain_height(x, z) + 0.40, z)
			slalom.add_child(post)
		z += 20.0


func _create_gate(z: float, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.35
	material.emission_energy_multiplier = 0.5
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.18, 3.0, 0.18)
	post_mesh.surface_set_material(0, material)
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(9.4, 0.18, 0.18)
	bar_mesh.surface_set_material(0, material)

	var gate := Node3D.new()
	var center_x: float = _route_center_x(z)
	gate.position = Vector3(center_x, _terrain_height(center_x, z), z)
	gate.rotation.y = atan2(_route_center_derivative(z), 1.0)
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		post.mesh = post_mesh
		post.position = Vector3(float(side) * 4.6, 1.5, 0.0)
		gate.add_child(post)
	var bar := MeshInstance3D.new()
	bar.mesh = bar_mesh
	bar.position = Vector3(0.0, 3.0, 0.0)
	gate.add_child(bar)
	slalom.add_child(gate)


func _update_hud() -> void:
	timer_label.text = _format_time(stage_time)
	rpm_bar.value = car.current_rpm
	var gearbox_mode: String = "M" if car.manual_mode else "A"
	telemetry_label.text = "%03d КМ/Ч | %s\nКПП %s [%s] | %d RPM\nКАМЕРА: %s\nХОД ПОДВЕСКИ: %d%%" % [
		int(car.speed_kmh),
		car.get_drivetrain_label(),
		car.get_gear_label(),
		gearbox_mode,
		int(car.current_rpm),
		car.get_camera_label(),
		roundi(car.get_max_suspension_compression() * 100.0)
	]

	var contact_count: int = car.get_wheel_contact_count()
	var tire_slip: float = car.get_average_tire_slip()
	if stage_finished:
		split_label.text = "ФИНИШ %s | R — ПРОЙТИ ЗАНОВО" % _format_time(stage_time)
		split_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
	else:
		split_label.text = "%s | КОНТАКТ %d/4 | SLIP %.2f" % [_current_section(), contact_count, tire_slip]
		var status_color := Color(0.2, 1.0, 0.4) if contact_count >= 3 and tire_slip < 0.65 else Color(1.0, 0.82, 0.22)
		split_label.add_theme_color_override("font_color", status_color)


func _current_section() -> String:
	if stage_profile == PROFILE_FOREST:
		return "ЛЕСНОЕ РАЛЛИ"
	if stage_profile == PROFILE_RANGE:
		return "ПОЛИГОН"
	var z: float = car.global_position.z
	if z < -72.0:
		return "ПОДВЕСКА: СТАРТ"
	if z < -62.0:
		return "ДИАГОНАЛЬНАЯ КОЧКА 1"
	if z < -45.0:
		return "ДИАГОНАЛЬНАЯ КОЧКА 2"
	if z < 33.0:
		return "ПОДВЕСКА: ВОЛНЫ"
	if z < 72.0:
		return "ПОДВЕСКА: CREST"
	return "ПОДВЕСКА: ПРОВАЛ / ФИНИШ"


func _format_time(seconds: float) -> String:
	var minutes: int = floori(seconds / 60.0)
	var remaining_seconds: float = fmod(seconds, 60.0)
	return "%02d:%06.3f" % [minutes, remaining_seconds]
