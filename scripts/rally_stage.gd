## Одна универсальная сцена гонки. Трасса, конфигурация машины и сид берутся
## из ресурсов (res://data/) или из автозагрузки RallyGame. Всё, что видно
## в этой сцене, можно редактировать в инспекторе Godot.
##
## Маршрут трассы создаётся scripts/data/rally_route.gd: шпильки, дуги,
## шифты, трамплины, гребни — в стиле Colin McRae Rally.
class_name RallyStage
extends Node3D

const CarType = preload("res://scripts/rally_car.gd")
const TrackConfigType = preload("res://scripts/data/rally_track_config.gd")
const CarSetupType = preload("res://scripts/data/rally_car_setup.gd")
const GameConfigType = preload("res://scripts/data/rally_game_config.gd")
const RouteType = preload("res://scripts/data/rally_route.gd")
const GroundShader = preload("res://shaders/forest_ground.gdshader")
const RangeShader = preload("res://shaders/mountain_track.gdshader")

@export_group("Данные (перетащите ресурсы в инспектор)")
@export var game_config: GameConfigType = null
@export var track_override: TrackConfigType = null
@export var car_setup_override: CarSetupType = null

@export_group("Генерация")
## Если включено, карта всегда создаётся с новым сидом, независимо от меню.
@export var force_random_seed: bool = false
@export var editor_seed: int = 1337
## 0 — использовать размер сетки из ресурса трассы.
@export_range(0, 241, 2) var terrain_grid_size_override: int = 0
@export var show_debug_info: bool = false

@onready var world_environment: WorldEnvironment = get_node_or_null("WorldEnvironment") as WorldEnvironment
@onready var sun_light: DirectionalLight3D = get_node_or_null("SunLight") as DirectionalLight3D
@onready var terrain: StaticBody3D = get_node_or_null("Terrain") as StaticBody3D
@onready var terrain_mesh: MeshInstance3D = get_node_or_null("Terrain/TerrainMesh") as MeshInstance3D
@onready var terrain_collider: CollisionShape3D = get_node_or_null("Terrain/TerrainCollider") as CollisionShape3D
@onready var generated: Node3D = get_node_or_null("Generated") as Node3D
@onready var hud: CanvasLayer = get_node_or_null("HUD") as CanvasLayer

var track: TrackConfigType = null
var setup: CarSetupType = null
var car: CarType = null
var seed_value: int = 1337
var random_stage: bool = false
var rng := RandomNumberGenerator.new()
var scenery_rng := RandomNumberGenerator.new()

# Маршрут (scripts/data/rally_route.gd).
var route_points: PackedVector2Array = PackedVector2Array()
var route_tangents: PackedVector2Array = PackedVector2Array()
var route_features: Array = []
var route_profile: PackedFloat32Array = PackedFloat32Array()
var route_grid: Dictionary = {}
var route_cell_size: float = 2.5
var route_bounds: Rect2 = Rect2(0.0, 0.0, 0.0, 0.0)
var start_pos: Vector2 = Vector2.ZERO
var finish_pos: Vector2 = Vector2.ZERO
var finish_tangent: Vector2 = Vector2(0.0, 1.0)
var checkpoints: Array = []
var cp_triggered: Array[bool] = []
var cp_times: Array[float] = []
var last_cp_index: int = -1
var hill_phase: Vector2 = Vector2.ZERO

var stage_time: float = 0.0
var timer_running: bool = false
var stage_finished: bool = false
var is_paused: bool = false
var speed_fx_material: ShaderMaterial = null
var best_time: float = 0.0
var is_new_record: bool = false

# HUD-узлы ищутся по имени, чтобы сцену можно было перестроить в редакторе.
var timer_label: Label = null
var split_label: Label = null
var stage_label: Label = null
var telemetry_label: Label = null
var rpm_bar: ProgressBar = null
var pause_panel: Control = null
var results_panel: Control = null
var results_label: Label = null
var speed_rect: ColorRect = null


func _enter_tree() -> void:
	# Родительский _enter_tree выполняется раньше _ready дочерней машины:
	# успеваем передать конфигурацию, назначенную в инспекторе сцены.
	var game: Node = get_node_or_null("/root/RallyGame")
	if game == null:
		return
	if car_setup_override != null:
		game.set("current_setup", car_setup_override)
	if track_override != null:
		game.set("current_track", track_override)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resolve_selection()
	_prepare_seed()
	_generate_road_parameters()
	_configure_world()
	_configure_terrain()
	_spawn_scenery()
	_spawn_route_markers()
	_spawn_checkpoints()
	_configure_car()
	_setup_hud()
	_update_hud()


func _exit_tree() -> void:
	if get_tree() != null:
		get_tree().paused = false


func _get_game() -> Node:
	return get_node_or_null("/root/RallyGame")


func _resolve_selection() -> void:
	var game: Node = _get_game()
	if game_config == null and game != null:
		var loaded: Variant = game.get("config")
		if loaded is GameConfigType:
			game_config = loaded
	if track_override != null:
		track = track_override
	elif game != null:
		var current: Variant = game.get("current_track")
		if current is TrackConfigType:
			track = current
	if track == null:
		if game != null:
			var first: Variant = game.call("get_track", 0)
			if first is TrackConfigType:
				track = first
	if track == null:
		track = TrackConfigType.new()
	if car_setup_override != null:
		setup = car_setup_override
	elif game != null:
		var current_setup: Variant = game.get("current_setup")
		if current_setup is CarSetupType:
			setup = current_setup
	if setup == null and game != null:
		var first_setup: Variant = game.call("get_setup", 0)
		if first_setup is CarSetupType:
			setup = first_setup
	random_stage = false
	if game != null:
		random_stage = bool(game.get("random_mode"))
	random_stage = random_stage or force_random_seed or track.random_seed


func _prepare_seed() -> void:
	var game: Node = _get_game()
	seed_value = int(track.map_seed)
	if game != null:
		seed_value = int(game.get("map_seed"))
	if editor_seed > 0 and game == null:
		seed_value = editor_seed
	if random_stage and force_random_seed:
		seed_value = int(Time.get_unix_time_from_system()) + randi() % 100000
	seed_value = maxi(1, absi(seed_value))
	stage_time = 0.0
	timer_running = false
	stage_finished = false
	last_cp_index = -1
	cp_triggered.clear()
	cp_times.clear()
	if game != null:
		best_time = float(game.call("get_best_time", track.get_record_key(seed_value)))


# ---------------------------------------------------------------- маршрут


func _generate_road_parameters() -> void:
	rng.seed = seed_value
	scenery_rng.seed = seed_value ^ 0x5F3A71
	var route: Dictionary = RouteType.generate(track, seed_value, random_stage)
	route_points = route["points"]
	route_tangents = route["tangents"]
	route_features = route["features"]
	checkpoints = route["checkpoints"]
	route_bounds = route["bounds"]
	hill_phase = RouteType.route_phases(track, seed_value)
	route_profile = RouteType.build_profile(track, route_points, route_features, hill_phase)
	_build_route_lookup()
	start_pos = route_points[0]
	finish_pos = route_points[route_points.size() - 1]
	finish_tangent = route_tangents[route_points.size() - 1]
	cp_triggered.resize(checkpoints.size())
	for i in range(checkpoints.size()):
		cp_triggered[i] = false
		cp_times.append(0.0)
	# Запоминаем сид итогового маршрута (best из нескольких попыток).
	if route.has("seed_used"):
		seed_value = int(route["seed_used"])


## Сетка ближайших точек маршрута: Vector2i(ячейка) -> индекс точки.
func _build_route_lookup() -> void:
	route_grid.clear()
	route_cell_size = 2.5
	var size: int = route_points.size()
	for i in range(size):
		var p: Vector2 = route_points[i]
		var cx: float = p.x / route_cell_size
		var cz: float = p.y / route_cell_size
		for gx in range(floori(cx) - 1, floori(cx) + 2):
			for gz in range(floori(cz) - 1, floori(cz) + 2):
				var key := Vector2i(gx, gz)
				var cell_center := Vector2(float(key.x) * route_cell_size, float(key.y) * route_cell_size)
				var dist2: float = p.distance_squared_to(cell_center)
				var best_i: Variant = route_grid.get(key, -1)
				if best_i == -1 or dist2 < route_points[int(best_i)].distance_squared_to(cell_center):
					route_grid[key] = i


## Возвращает [знаковое латеральное расстояние, расстояние по маршруту].
## Для плоской трассы (Range) — просто x и z.
func _route_lookup(x: float, z: float) -> Vector2:
	if track.is_flat():
		return Vector2(x, z + track.length * 0.5)
	var cx: int = int(floor(x / route_cell_size))
	var cz: int = int(floor(z / route_cell_size))
	var best_i := -1
	# Расширение по кругу — клетка точно есть (территория покрыта маршрутом).
	for ring in range(6):
		for gx in range(cx - ring, cx + ring + 1):
			for gz in range(cz - ring, cz + ring + 1):
				if absf(gx - cx) != ring and absf(gz - cz) != ring:
					continue
				var key := Vector2i(gx, gz)
				if route_grid.has(key):
					best_i = int(route_grid[key])
					break
			if best_i >= 0:
				break
		if best_i >= 0:
			break
	if best_i < 0:
		return Vector2(9999.0, 0.0)
	var p := Vector2(x, z)
	var best_lateral: float = 1.0e30
	var best_rd: float = 0.0
	# Уточнение: соседние точки маршрута (плотная разбивка 0.5 м).
	for i in range(maxi(0, best_i - 3), mini(route_points.size() - 1, best_i + 3)):
		var lateral: float = _lateral_signed(p, i)
		if absf(lateral) < absf(best_lateral):
			best_lateral = lateral
			best_rd = float(i) * RouteType.SAMPLE_STEP
	return Vector2(best_lateral, best_rd)


## Знаковое расстояние от точки до отрезка маршрута (i → i+1).
func _lateral_signed(p: Vector2, i: int) -> float:
	if route_points.size() < 2:
		return p.distance_to(route_points[i])
	var a: Vector2 = route_points[i]
	var b: Vector2 = route_points[i + 1]
	var ab: Vector2 = b - a
	var ab_len2: float = ab.length_squared()
	if ab_len2 < 1.0e-6:
		return p.distance_to(a)
	var t: float = clampf(p.dot(ab) / ab_len2, 0.0, 1.0)
	var proj: Vector2 = a + ab * t
	# Крестное произведение: знак «слева/справа» от направления движения.
	var cross: float = ab.x * (p.y - a.y) - ab.y * (p.x - a.x)
	return (p - proj).length() * (1.0 if cross >= 0.0 else -1.0)


func _terrain_height(x: float, z: float) -> float:
	if track.is_flat():
		return 0.0
	var lookup: Vector2 = _route_lookup(x, z)
	var lateral: float = lookup.x
	var route_dist: float = lookup.y
	var index: int = clampi(int(route_dist / RouteType.SAMPLE_STEP), 0, route_profile.size() - 1)
	var base: float = route_profile[index]
	# Кочки со смещением в сторону дороги.
	for feature in route_features:
		if feature.get("kind_tag", "") == "bump":
			var fdist: float = float(feature["route_dist"])
			var width: float = float(feature["width"])
			var side_blend: float = smoothstep(-1.5, 1.5, lateral * float(feature["side"]))
			base += float(feature["strength"]) * exp(-pow((route_dist - fdist) / width, 2.0)) * side_blend
	# Боковые склоны вне дороги.
	var offroad: float = base
	offroad += track.offroad_hills * sin(x * 0.045 + hill_phase.y) * sin(z * 0.026 + hill_phase.x)
	offroad += track.offroad_hills * 0.42 * sin(x * 0.105 + z * 0.04)
	var half: float = track.road_half_width
	var blend: float = smoothstep(half + 3.0, half + 18.0, absf(lateral))
	var height: float = lerpf(base, offroad, blend)
	if blend > 0.15:
		height += track.offroad_hills * 0.3 * TrackConfigType.hash_noise(x * 3.1 + 11.0, z * 2.7 + 3.0)
	return height


# ---------------------------------------------------------------- мир


func _configure_world() -> void:
	if world_environment != null:
		var env: Environment = null
		if world_environment.environment != null:
			env = world_environment.environment.duplicate() as Environment
		if env == null:
			env = Environment.new()
		var sky := Sky.new()
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = track.sky_top_color
		sky_material.sky_horizon_color = track.sky_horizon_color
		sky_material.ground_bottom_color = track.ground_color * 0.4
		sky_material.ground_horizon_color = track.sky_horizon_color
		# PS1: плоское небо-градиент вместо купола.
		sky_material.sky_curve = 0.55 if track.sky_flat else 0.18
		sky.sky_material = sky_material
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = 1.05
		env.glow_enabled = true
		# PS1-туман: жёсткие границы; объёмный туман только если не стиль PS1.
		env.volumetric_fog_enabled = not track.ps1_style
		env.volumetric_fog_density = 0.02
		env.volumetric_fog_albedo = track.fog_color
		# Расстояний туман для объектов (деревья, КПП, ворота).
		env.fog_enabled = true
		env.fog_light_color = track.fog_color
		env.fog_density = 0.0032
		world_environment.environment = env
	if sun_light != null:
		sun_light.rotation = Vector3(deg_to_rad(track.sun_pitch), deg_to_rad(track.sun_yaw), 0.0)
		sun_light.light_energy = track.sun_energy


func _clear_generated() -> void:
	if generated == null:
		return
	for child in generated.get_children():
		child.queue_free()


func _configure_terrain() -> void:
	_clear_generated()
	if terrain == null or terrain_mesh == null or terrain_collider == null:
		push_warning("RallyStage: узлы Terrain не найдены, генерация пропущена.")
		return
	terrain.remove_from_group("Road")
	terrain.remove_from_group("Grass")
	terrain.remove_from_group("Dirt")
	if track.is_flat():
		terrain.add_to_group("Road")
		var plane := PlaneMesh.new()
		var extent: float = maxf(track.length + 200.0, 600.0)
		plane.size = Vector2(extent, extent)
		terrain_mesh.mesh = plane
		var material := ShaderMaterial.new()
		material.shader = RangeShader
		material.set_shader_parameter("grass_color", track.ground_color)
		material.set_shader_parameter("dirt_color", track.road_color)
		material.set_shader_parameter("strip_half_width", track.road_half_width * 2.0)
		terrain_mesh.material_override = material
		var box := BoxShape3D.new()
		box.size = Vector3(extent, 1.0, extent)
		terrain_collider.shape = box
		terrain_collider.position = Vector3(0.0, -0.5, 0.0)
		return

	terrain.add_to_group("Grass")
	terrain_collider.position = Vector3.ZERO
	var mesh: ArrayMesh = _build_heightfield_mesh()
	terrain_mesh.mesh = mesh
	var ground_material := ShaderMaterial.new()
	ground_material.shader = GroundShader
	ground_material.set_shader_parameter("ground_color", track.ground_color)
	ground_material.set_shader_parameter("ground_color_2", track.ground_color_2)
	ground_material.set_shader_parameter("road_edge_color", track.road_color * 0.85)
	ground_material.set_shader_parameter("rock_color", track.rock_color)
	ground_material.set_shader_parameter("surface_roughness", 0.97)
	ground_material.set_shader_parameter("grain_scale", 2.4)
	ground_material.set_shader_parameter("flat_shading", 1.0 if track.flat_shading else 0.0)
	ground_material.set_shader_parameter("dither_fog", 1.0 if track.dither_fog else 0.0)
	ground_material.set_shader_parameter("banding_levels", float(track.color_banding))
	ground_material.set_shader_parameter("fog_color", track.fog_color)
	ground_material.set_shader_parameter("fog_near", track.fog_near)
	ground_material.set_shader_parameter("fog_far", track.fog_far)
	terrain_mesh.material_override = ground_material
	var collision: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	collision.backface_collision = true
	terrain_collider.shape = collision
	_build_road()


func _terrain_extent() -> Vector2:
	var margin: float = track.scenery_radius + 20.0
	var extent: float = maxf(route_bounds.size.x, route_bounds.size.y) + margin * 2.0
	return Vector2(extent, extent)


func _build_heightfield_mesh() -> ArrayMesh:
	var grid_size: int = track.terrain_grid_size
	if terrain_grid_size_override > 0:
		grid_size = terrain_grid_size_override
	grid_size = clampi(grid_size, 65, 241)
	var extent: Vector2 = _terrain_extent()
	var center: Vector2 = Vector2(
		route_bounds.position.x + route_bounds.size.x * 0.5,
		route_bounds.position.y + route_bounds.size.y * 0.5
	)
	var grid_step: float = extent.x / float(grid_size - 1)
	var half_extent: float = extent.x * 0.5
	var vertex_count: int = grid_size * grid_size
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.resize(vertex_count)
	normals.resize(vertex_count)
	colors.resize(vertex_count)
	indices.resize((grid_size - 1) * (grid_size - 1) * 6)
	var epsilon: float = maxf(grid_step * 0.4, 0.35)
	var half: float = track.road_half_width

	for z_index in range(grid_size):
		var z: float = center.y - half_extent + float(z_index) * grid_step
		for x_index in range(grid_size):
			var x: float = center.x - half_extent + float(x_index) * grid_step
			var index: int = z_index * grid_size + x_index
			vertices[index] = Vector3(x, _terrain_height(x, z), z)
			normals[index] = Vector3(
				_terrain_height(x - epsilon, z) - _terrain_height(x + epsilon, z),
				2.0 * epsilon,
				_terrain_height(x, z - epsilon) - _terrain_height(x, z + epsilon)
			).normalized()
			# Вершинный цвет: R — влияние дороги (0 = дорога), G — крутизна
			# склона (камни), B — шум для зёрнышка грунта.
			var lookup: Vector2 = _route_lookup(x, z)
			var road_influence: float = 1.0 - smoothstep(half + 0.8, half + 8.0, absf(lookup.x))
			var slope: float = 1.0 - clamp(normals[index].y, 0.0, 1.0)
			var grain: float = TrackConfigType.hash_noise(x * 7.3 + 11.0, z * 5.1 + 3.0)
			colors[index] = Color(road_influence, slope, grain, 1.0)

	var cursor: int = 0
	for z_index in range(grid_size - 1):
		for x_index in range(grid_size - 1):
			var i: int = z_index * grid_size + x_index
			indices[cursor] = i
			indices[cursor + 1] = i + 1
			indices[cursor + 2] = i + grid_size
			indices[cursor + 3] = i + 1
			indices[cursor + 4] = i + grid_size + 1
			indices[cursor + 5] = i + grid_size
			cursor += 6

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_road() -> void:
	# Одна и та же лента используется для визуала и для коллизии «Dirt».
	# Поэтому машина едет ровно по той дороге, которую видит игрок.
	var step: float = maxf(0.4, track.road_step)
	var count: int = maxi(2, ceili(track.length / step))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.resize(count * 2)
	normals.resize(count * 2)
	colors.resize(count * 2)
	indices.resize((count - 1) * 6)
	var half: float = track.road_half_width
	var color_rng := RandomNumberGenerator.new()
	color_rng.seed = seed_value ^ 0x1234

	for row in range(count):
		var i: int = clampi(int(float(row) * step / RouteType.SAMPLE_STEP), 0, route_points.size() - 1)
		var point: Vector2 = route_points[i]
		var tangent := Vector2(route_tangents[i].x, route_tangents[i].y)
		var dir3 := Vector3(tangent.x, 0.0, tangent.y)
		var side: Vector3 = Vector3(dir3.z, 0.0, -dir3.x)
		var shade: float = color_rng.randf_range(0.88, 1.12)
		var rumble_dash: bool = (i % 10) < 5
		for edge in range(2):
			var edge_sign: float = -1.0 if edge == 0 else 1.0
			var p3 := Vector3(point.x, 0.0, point.y) + side * (edge_sign * half)
			var height: float = _terrain_height(p3.x, p3.z)
			var offset: Vector3 = Vector3(p3.x, height + 0.022, p3.z)
			var index: int = row * 2 + edge
			vertices[index] = offset
			var eps: float = 0.4
			normals[index] = Vector3(
				_terrain_height(p3.x - eps, p3.z) - _terrain_height(p3.x + eps, p3.z),
				2.0 * eps,
				_terrain_height(p3.x, p3.z - eps) - _terrain_height(p3.x, p3.z + eps)
			).normalized()
			# PS1-ралли: красно-белые «барьходы» на обочинах + зёрнышко дороги.
			var base_color := track.road_color * shade
			base_color = base_color.lerp(track.road_color_2, color_rng.randf_range(0.0, 0.4))
			var curb: float = smoothstep(0.78, 1.0, absf(edge_sign))
			if curb > 0.3 and track.road_rumble:
				base_color = base_color.lerp(Color(0.75, 0.14, 0.10), curb * (0.55 if rumble_dash else 0.0))
			colors[index] = base_color

	var cursor: int = 0
	for row in range(count - 1):
		var i: int = row * 2
		indices[cursor] = i
		indices[cursor + 1] = i + 1
		indices[cursor + 2] = i + 2
		indices[cursor + 3] = i + 1
		indices[cursor + 4] = i + 3
		indices[cursor + 5] = i + 2
		cursor += 6

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var road_mesh := ArrayMesh.new()
	road_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var road_material := StandardMaterial3D.new()
	road_material.albedo_color = Color(1.0, 1.0, 1.0)
	road_material.vertex_color_use_as_albedo = true
	road_material.roughness = 1.0
	var road_visual := MeshInstance3D.new()
	road_visual.name = "RoadMesh"
	road_visual.mesh = road_mesh
	road_visual.material_override = road_material
	if generated != null:
		generated.add_child(road_visual)

	var faces := PackedVector3Array()
	for i in range(0, indices.size(), 3):
		faces.append(vertices[indices[i]])
		faces.append(vertices[indices[i + 1]])
		faces.append(vertices[indices[i + 2]])
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	_set_shape_faces(shape, faces)
	var road_body := StaticBody3D.new()
	road_body.name = "RoadSurface"
	road_body.add_to_group("Dirt")
	var collider := CollisionShape3D.new()
	collider.shape = shape
	road_body.add_child(collider)
	if generated != null:
		generated.add_child(road_body)


## Godot 4.7 переименовал свойство faces -> data; set_faces сохранён, но
## оставляем запасной путь на будущие патчи движка.
func _set_shape_faces(shape: ConcavePolygonShape3D, faces: PackedVector3Array) -> void:
	if shape.has_method("set_faces"):
		shape.call("set_faces", faces)
	else:
		shape.set("data", faces)


# ---------------------------------------------------------------- окружение


func _spawn_scenery() -> void:
	if generated == null:
		return
	var container := Node3D.new()
	container.name = "Scenery"
	generated.add_child(container)

	var trunk_material := StandardMaterial3D.new()
	trunk_material.albedo_color = Color(0.23, 0.125, 0.065)
	trunk_material.roughness = 1.0
	var foliage_material := StandardMaterial3D.new()
	foliage_material.albedo_color = track.tree_color
	foliage_material.roughness = 0.95
	var bush_material := StandardMaterial3D.new()
	bush_material.albedo_color = track.bush_color
	bush_material.roughness = 1.0
	var rock_material := StandardMaterial3D.new()
	rock_material.albedo_color = track.rock_color
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
	var bush_mesh := SphereMesh.new()
	bush_mesh.radius = 0.9
	bush_mesh.height = 1.4
	bush_mesh.radial_segments = 6
	bush_mesh.rings = 3
	bush_mesh.surface_set_material(0, bush_material)
	var trunk_shape := CylinderShape3D.new()
	trunk_shape.radius = 0.24
	trunk_shape.height = 1.8

	var radius: float = maxf(track.scenery_radius, track.length * 0.35)
	var total: int = track.tree_count + track.rock_count + track.bush_count
	var place_attempts := 12
	for i in range(total):
		var is_rock: bool = i >= track.tree_count + track.bush_count
		var is_bush: bool = i >= track.tree_count and not is_rock
		var item: Node3D = null
		for attempt in range(place_attempts):
			var x: float = scenery_rng.randf_range(-radius, radius)
			var z: float = scenery_rng.randf_range(route_bounds.position.y - radius, route_bounds.position.y + route_bounds.size.y + radius)
			var clearance: float = track.road_clearance
			if track.is_flat():
				clearance = maxf(clearance, track.road_half_width * 2.0 + 12.0)
			var lookup: Vector2 = _route_lookup(x, z)
			var distance_to_road: float = absf(lookup.x)
			if distance_to_road < clearance or absf(lookup.y) < 12.0:
				continue
			var y: float = _terrain_height(x, z)
			if is_rock:
				var rock := MeshInstance3D.new()
				rock.name = "Boulder"
				rock.mesh = rock_mesh
				rock.scale = Vector3(
					scenery_rng.randf_range(0.65, 1.5),
					scenery_rng.randf_range(0.45, 1.0),
					scenery_rng.randf_range(0.65, 1.4)
				)
				rock.position = Vector3(x, y + 0.22, z)
				container.add_child(rock)
				item = rock
			elif is_bush:
				var bush := MeshInstance3D.new()
				bush.name = "Bush"
				bush.mesh = bush_mesh
				bush.scale = Vector3.ONE * scenery_rng.randf_range(0.7, 1.4)
				bush.position = Vector3(x, y + 0.35, z)
				container.add_child(bush)
				item = bush
			else:
				var pine := _create_pine(trunk_mesh, foliage_mesh)
				pine.scale = Vector3.ONE * scenery_rng.randf_range(0.8, 1.5)
				pine.position = Vector3(x, y, z)
				if distance_to_road < clearance + 45.0:
					var body := StaticBody3D.new()
					body.position = Vector3(0.0, 0.9, 0.0)
					var collider := CollisionShape3D.new()
					collider.shape = trunk_shape
					body.add_child(collider)
					pine.add_child(body)
				container.add_child(pine)
				item = pine
			item.rotation = Vector3(0.0, scenery_rng.randf_range(0.0, TAU), 0.0)
			break
		if item == null:
			continue

	if track.sign_count > 0:
		_spawn_signs(container)
	if track.slalom_cones > 0:
		_spawn_slalom(container)


## Указательные щиты у ключевых участков (стиль раллийных спецучастков).
func _spawn_signs(container: Node3D) -> void:
	var board_material := StandardMaterial3D.new()
	board_material.albedo_color = Color(0.92, 0.92, 0.88)
	board_material.roughness = 0.9
	var post_material := StandardMaterial3D.new()
	post_material.albedo_color = Color(0.25, 0.18, 0.10)
	post_material.roughness = 1.0
	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(2.2, 0.16, 1.4)
	board_mesh.surface_set_material(0, board_material)
	var stripe_material := StandardMaterial3D.new()
	stripe_material.albedo_color = Color(0.9, 0.12, 0.1)
	stripe_material.roughness = 0.9
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(2.2, 0.06, 0.35)
	stripe_mesh.surface_set_material(0, stripe_material)
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.12, 2.0, 0.12)
	post_mesh.surface_set_material(0, post_material)

	# Щиты в随机ных точках маршрута на обочине.
	var indices := PackedInt32Array()
	var step_count: int = maxi(8, int(track.length / 90.0))
	for i in range(step_count):
		indices.append(int(scenery_rng.randi_range(10, route_points.size() - 10)))
	var placed: int = 0
	for i in range(indices.size()):
		if placed >= track.sign_count:
			break
		var idx: int = indices[i]
		var point: Vector2 = route_points[idx]
		var tangent := route_tangents[idx]
		var side_sign: float = 1.0 if scenery_rng.randf() > 0.5 else -1.0
		var normal := Vector2(-tangent.y, tangent.x) * side_sign
		var offset: float = track.road_half_width + 1.5 + scenery_rng.randf_range(0.0, 4.0)
		var x: float = point.x + normal.x * offset
		var z: float = point.y + normal.y * offset
		var y: float = _terrain_height(x, z)
		var sign := Node3D.new()
		sign.name = "Sign_%02d" % placed
		var post := MeshInstance3D.new()
		post.mesh = post_mesh
		post.position = Vector3(0.0, 1.0, 0.0)
		sign.add_child(post)
		var board := MeshInstance3D.new()
		board.mesh = board_mesh
		board.position = Vector3(0.0, 1.9, 0.0)
		sign.add_child(board)
		var stripe := MeshInstance3D.new()
		stripe.mesh = stripe_mesh
		stripe.position = Vector3(0.0, 1.9, 0.55)
		sign.add_child(stripe)
		sign.position = Vector3(x, y, z)
		sign.rotation.y = atan2(tangent.x, tangent.y) + side_sign * PI * 0.5
		container.add_child(sign)
		placed += 1


func _create_pine(trunk_mesh: CylinderMesh, foliage_mesh: CylinderMesh) -> Node3D:
	var pine := Node3D.new()
	pine.name = "Pine"
	var trunk := MeshInstance3D.new()
	trunk.mesh = trunk_mesh
	trunk.position = Vector3(0.0, 0.75, 0.0)
	pine.add_child(trunk)
	var foliage := MeshInstance3D.new()
	foliage.mesh = foliage_mesh
	foliage.position = Vector3(0.0, 2.6, 0.0)
	pine.add_child(foliage)
	var upper := MeshInstance3D.new()
	upper.mesh = foliage_mesh
	upper.position = Vector3(0.0, 3.75, 0.0)
	upper.scale = Vector3.ONE * 0.65
	pine.add_child(upper)
	return pine


func _spawn_slalom(container: Node3D) -> void:
	var cone_material := StandardMaterial3D.new()
	cone_material.albedo_color = Color(1.0, 0.32, 0.03)
	cone_material.emission_enabled = true
	cone_material.emission = Color(0.4, 0.06, 0.0)
	cone_material.emission_energy_multiplier = 0.6
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.035
	cone_mesh.bottom_radius = 0.25
	cone_mesh.height = 0.7
	cone_mesh.radial_segments = 12
	cone_mesh.surface_set_material(0, cone_material)
	var spacing: float = track.length / float(maxi(1, track.slalom_cones))
	for i in range(track.slalom_cones):
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var idx: int = clampi(int(float(i) * spacing / RouteType.SAMPLE_STEP), 0, route_points.size() - 1)
		var point: Vector2 = route_points[idx]
		var tangent := route_tangents[idx]
		var normal := Vector2(-tangent.y, tangent.x) * side
		var cone := MeshInstance3D.new()
		cone.name = "Cone_%02d" % i
		cone.mesh = cone_mesh
		var x: float = point.x + normal.x * 5.0
		var z: float = point.y + normal.y * 5.0
		cone.position = Vector3(x, _terrain_height(x, z) + 0.35, z)
		container.add_child(cone)


func _spawn_route_markers() -> void:
	if generated == null:
		return
	var container := Node3D.new()
	container.name = "RouteMarkers"
	generated.add_child(container)
	_create_gate(container, start_pos, route_tangents[0], Color(0.20, 0.80, 1.0))
	_create_gate(container, finish_pos, finish_tangent, Color(1.0, 0.48, 0.08))

	var left_material := StandardMaterial3D.new()
	left_material.albedo_color = Color(0.95, 0.95, 0.88)
	var right_material := StandardMaterial3D.new()
	right_material.albedo_color = Color(0.95, 0.16, 0.08)
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.12, 0.85, 0.12)
	var spacing: float = 28.0
	var dist: float = 12.0
	while dist < track.length - 8.0:
		var idx: int = clampi(int(dist / RouteType.SAMPLE_STEP), 0, route_points.size() - 1)
		var point: Vector2 = route_points[idx]
		var tangent := route_tangents[idx]
		var dir3 := Vector3(tangent.x, 0.0, tangent.y)
		var side: Vector3 = Vector3(dir3.z, 0.0, -dir3.x)
		for side_sign in [-1.0, 1.0]:
			var p3 := Vector3(point.x, 0.0, point.y) + side * (float(side_sign) * (track.road_half_width + 1.0))
			var post := MeshInstance3D.new()
			post.mesh = post_mesh
			post.material_override = left_material if side_sign < 0.0 else right_material
			post.position = Vector3(p3.x, _terrain_height(p3.x, p3.z) + 0.43, p3.z)
			container.add_child(post)
		dist += spacing


## КПП (control points): арки через track.checkpoint_interval метров.
func _spawn_checkpoints() -> void:
	if generated == null or checkpoints.is_empty():
		return
	var container := Node3D.new()
	container.name = "Checkpoints"
	generated.add_child(container)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.85, 0.20)
	material.emission_enabled = true
	material.emission = Color(0.35, 0.32, 0.07)
	material.emission_energy_multiplier = 0.5
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.16, 3.0, 0.16)
	post_mesh.surface_set_material(0, material)
	var banner_mesh := BoxMesh.new()
	banner_mesh.size = Vector3(track.road_half_width * 2.0 + 1.0, 0.22, 0.3)
	banner_mesh.surface_set_material(0, material)
	for i in range(checkpoints.size()):
		var cp: Dictionary = checkpoints[i]
		var point: Vector2 = cp["pos"]
		var tangent: Vector2 = cp["tangent"]
		var gate := Node3D.new()
		gate.name = "Checkpoint_%02d" % i
		gate.position = Vector3(point.x, _terrain_height(point.x, point.y), point.y)
		gate.rotation.y = atan2(tangent.x, tangent.y)
		for side_sign in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			post.mesh = post_mesh
			post.position = Vector3(float(side_sign) * (track.road_half_width + 0.35), 1.5, 0.0)
			gate.add_child(post)
		var banner := MeshInstance3D.new()
		banner.mesh = banner_mesh
		banner.position = Vector3(0.0, 3.0, 0.0)
		gate.add_child(banner)
		container.add_child(gate)


func _create_gate(container: Node3D, pos: Vector2, tangent: Vector2, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.35
	material.emission_energy_multiplier = 0.5
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.18, 3.0, 0.18)
	post_mesh.surface_set_material(0, material)
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(track.road_half_width * 2.0 + 1.0, 0.18, 0.18)
	bar_mesh.surface_set_material(0, material)

	var gate := Node3D.new()
	gate.position = Vector3(pos.x, _terrain_height(pos.x, pos.y), pos.y)
	gate.rotation.y = atan2(tangent.x, tangent.y)
	for side_sign in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		post.mesh = post_mesh
		post.position = Vector3(float(side_sign) * (track.road_half_width + 0.35), 1.5, 0.0)
		gate.add_child(post)
	var bar := MeshInstance3D.new()
	bar.mesh = bar_mesh
	bar.position = Vector3(0.0, 3.0, 0.0)
	gate.add_child(bar)
	container.add_child(gate)


# ---------------------------------------------------------------- машина


func _configure_car() -> void:
	car = get_node_or_null("RallyCar") as CarType
	if car == null:
		push_warning("RallyStage: узел RallyCar не найден.")
		return
	car.process_mode = Node.PROCESS_MODE_PAUSABLE
	car.apply_track_grip(track.grip_scale, track.rolling_resistance_scale)
	car.spawn_transform = _make_spawn_transform()
	car.reset_to_spawn()


func _make_spawn_transform() -> Transform3D:
	var idx: int = clampi(int(14.0 / RouteType.SAMPLE_STEP), 0, route_points.size() - 1)
	var point: Vector2 = route_points[idx]
	var tangent := route_tangents[idx]
	var height_offset: float = 0.15
	if car != null:
		height_offset = car.get_spawn_height_offset() + 0.12
	var y: float = _terrain_height(point.x, point.y) + height_offset
	# В проекте forward машины — basis.z (модель смотрит в +Z).
	var yaw: float = atan2(tangent.x, tangent.y)
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(point.x, y, point.y))


# ---------------------------------------------------------------- HUD


func _setup_hud() -> void:
	if hud == null:
		return
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	timer_label = hud.get_node_or_null("TopPanel/TimerLabel") as Label
	split_label = hud.get_node_or_null("TopPanel/SplitLabel") as Label
	stage_label = hud.get_node_or_null("TopPanel/StageLabel") as Label
	telemetry_label = hud.get_node_or_null("BottomPanel/TelemetryBox/TelemetryLabel") as Label
	rpm_bar = hud.get_node_or_null("BottomPanel/TelemetryBox/RPMBar") as ProgressBar
	speed_rect = hud.get_node_or_null("SpeedShaderRect") as ColorRect
	pause_panel = hud.get_node_or_null("PausePanel") as Control
	results_panel = hud.get_node_or_null("ResultsPanel") as Control
	if speed_rect != null:
		speed_fx_material = speed_rect.material as ShaderMaterial
		speed_rect.visible = track.enable_speed_fx
	if pause_panel != null:
		pause_panel.visible = false
	if results_panel != null:
		results_panel.visible = false
	_connect_button("PausePanel/Box/ResumeButton", "_on_resume_pressed")
	_connect_button("PausePanel/Box/RestartButton", "_on_restart_pressed")
	_connect_button("PausePanel/Box/MenuButton", "_on_menu_pressed")
	_connect_button("PausePanel/Box/QuitButton", "_on_quit_pressed")
	_connect_button("ResultsPanel/Box/AgainButton", "_on_restart_pressed")
	_connect_button("ResultsPanel/Box/MenuButton", "_on_menu_pressed")
	var hint := hud.get_node_or_null("ControlsHint") as Label
	if hint != null:
		hint.text = "[W/S] ГАЗ / ТОРМОЗ   [A/D] РУЛЬ   [SPACE] РУЧНИК\n[C] КАМЕРА  [V] ПРИВОД  [R] СБРОС  [Q/E] КПП\n[ESC] ПАУЗА   [F1–F7] ТРАССЫ"
	var title := hud.get_node_or_null("TopPanel/TitleLabel") as Label
	if title != null:
		title.text = track.display_name


func _connect_button(path: String, method: String) -> void:
	if hud == null:
		return
	var button := hud.get_node_or_null(path) as Button
	if button != null and not button.pressed.is_connected(Callable(self, method)):
		button.pressed.connect(Callable(self, method))


func _update_hud() -> void:
	if car == null:
		return
	if timer_label != null:
		timer_label.text = _format_time(stage_time)
	if rpm_bar != null:
		rpm_bar.max_value = car.max_rpm
		rpm_bar.value = car.current_rpm
	if stage_label != null:
		var mode_tag: String = "RANDOM" if random_stage else "SEED"
		stage_label.text = "%s  |  %s %d  |  %s" % [track.display_name, mode_tag, seed_value, track.surface_name]
	if telemetry_label != null:
		var gearbox_mode: String = "M" if car.manual_mode else "A"
		telemetry_label.text = "%03d КМ/Ч  |  %s\nКПП %s [%s]  |  %d RPM\nКАМЕРА: %s\nХОД ПОДВЕСКИ: %d%%  |  КОНТАКТ %d/4" % [
			int(car.speed_kmh),
			car.get_drivetrain_label(),
			car.get_gear_label(),
			gearbox_mode,
			int(car.current_rpm),
			car.get_camera_label(),
			roundi(car.get_max_suspension_compression() * 100.0),
			car.get_wheel_contact_count()
		]
	if split_label != null:
		if stage_finished:
			split_label.text = "ФИНИШ!  %s" % _format_time(stage_time)
		elif last_cp_index >= 0 and cp_times[last_cp_index] > 0.0:
			var best_split: float = 0.0
			var game: Node = _get_game()
			if game != null:
				best_split = float(game.call("get_best_split", _split_key(last_cp_index)))
			var line: String = "КПП%d %s" % [last_cp_index + 1, _format_time(cp_times[last_cp_index])]
			if best_split > 0.0:
				line += "  |  РЕКОРД %s" % _format_time(best_split)
			split_label.text = line
		else:
			split_label.text = "ЦЕЛЬ %s" % _format_time(track.target_time)
	if show_debug_info and split_label != null:
		split_label.text += "  | grid %d" % track.terrain_grid_size


func _split_key(cp_index: int) -> String:
	return "%s_%d_cp%d" % [track.id, seed_value, cp_index]


func _format_time(seconds: float) -> String:
	var minutes: int = floori(seconds / 60.0)
	var remaining: float = fmod(seconds, 60.0)
	return "%02d:%06.3f" % [minutes, remaining]


# ---------------------------------------------------------------- цикл


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("pause"):
		_set_paused(not is_paused)
	if is_paused:
		return
	if _handle_track_switch():
		return
	if Input.is_action_just_pressed("reset_car"):
		stage_time = 0.0
		timer_running = false
		stage_finished = false
		last_cp_index = -1
		cp_triggered.fill(false)
		cp_times.fill(0.0)
	if not stage_finished:
		if Input.get_action_strength("throttle") > 0.05:
			timer_running = true
		if timer_running:
			stage_time += delta
		_check_checkpoints()
		_check_finish()
	if speed_fx_material != null:
		var intensity: float = clampf(((car.speed_kmh if car != null else 0.0) - 70.0) / 130.0, 0.0, 1.0)
		speed_fx_material.set_shader_parameter("speed_intensity", intensity)
	_update_hud()


## Проверка контрольных точек: реакция на проезд арки КПП.
func _check_checkpoints() -> void:
	if car == null or not timer_running:
		return
	var forward := car.global_transform.basis.z
	for i in range(checkpoints.size()):
		if cp_triggered[i]:
			continue
		var cp: Dictionary = checkpoints[i]
		var dx: float = car.global_position.x - cp["pos"].x
		var dz: float = car.global_position.z - cp["pos"].y
		if dx * dx + dz * dz < 16.0:
			var tangent := Vector3(cp["tangent"].x, 0.0, cp["tangent"].y)
			if forward.dot(tangent) > 0.3:
				cp_triggered[i] = true
				cp_times[i] = stage_time
				last_cp_index = i
				var game: Node = _get_game()
				if game != null:
					game.submit_split(_split_key(i), stage_time)


func _check_finish() -> void:
	if car == null or not timer_running:
		return
	var dx: float = car.global_position.x - finish_pos.x
	var dz: float = car.global_position.z - finish_pos.y
	var tolerance: float = track.road_half_width + 4.0
	if dx * dx + dz * dz > tolerance * tolerance:
		return
	var forward := car.global_transform.basis.z
	var tangent := Vector3(finish_tangent.x, 0.0, finish_tangent.y)
	if forward.dot(tangent) > 0.35:
		_finish_stage()


func _finish_stage() -> void:
	stage_finished = true
	timer_running = false
	var game: Node = _get_game()
	is_new_record = false
	if game != null:
		is_new_record = bool(game.call("submit_time", track.get_record_key(seed_value), stage_time))
		best_time = float(game.call("get_best_time", track.get_record_key(seed_value)))
	if results_panel != null:
		results_panel.visible = true
		if results_label != null:
			var record_line: String = "НОВЫЙ РЕКОРД!" if is_new_record else "ЛУЧШЕЕ: %s" % _format_time(best_time)
			results_label.text = "%s\n\nВРЕМЯ  %s\n%s" % [track.display_name, _format_time(stage_time), record_line]
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _handle_track_switch() -> bool:
	var actions: Array[String] = ["track_1", "track_2", "track_3", "track_4", "track_5", "track_6", "track_7"]
	for i in range(actions.size()):
		if InputMap.has_action(actions[i]) and Input.is_action_just_pressed(actions[i]):
			_switch_track(i)
			return true
	return false


func _switch_track(index: int) -> void:
	var game: Node = _get_game()
	if game != null:
		game.call("select_track", index)
		game.call("prepare_race_seed")
	_set_paused(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	call_deferred("_reload_scene")


func _reload_scene() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _set_paused(value: bool) -> void:
	is_paused = value
	get_tree().paused = value
	if pause_panel != null:
		pause_panel.visible = value
	if value:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if car != null and car.mouse_look_enabled else Input.MOUSE_MODE_VISIBLE


func _on_resume_pressed() -> void:
	_set_paused(false)


func _on_restart_pressed() -> void:
	var game: Node = _get_game()
	if game != null:
		game.call("prepare_race_seed")
		game.call("restart_race")
	else:
		_reload_scene()


func _on_menu_pressed() -> void:
	var game: Node = _get_game()
	if game != null:
		game.call("goto_menu")
	else:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_quit_pressed() -> void:
	var game: Node = _get_game()
	if game != null:
		game.call("quit_game")
	else:
		get_tree().quit()
