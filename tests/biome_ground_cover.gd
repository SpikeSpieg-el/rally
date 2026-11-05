# godot --headless --path . --script res://tests/biome_ground_cover.gd
extends SceneTree

const Stage = preload("res://scripts/rally_stage.gd")
const Track = preload("res://scripts/data/rally_track_config.gd")
const Library = preload("res://scripts/data/rally_prop_library.gd")
const Scenery = preload("res://scripts/data/rally_scenery_config.gd")
const Biome = preload("res://scripts/data/rally_scenery_biome.gd")
const Prop = preload("res://scripts/data/rally_prop.gd")
const Network = preload("res://scripts/road_network.gd")

var failures: Array[String] = []


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)


func _initialize() -> void:
	call_deferred("_run")


func positions(stage) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var scenery: Node = stage.generated.get_node_or_null("Scenery")
	if scenery == null:
		return result
	for group in scenery.get_children():
		for cell in group.get_children():
			if not cell is MultiMeshInstance3D:
				continue
			check(
				cell.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "трава без теней"
			)
			for i in range(cell.multimesh.instance_count):
				var point: Vector3 = (
					(cell.transform * cell.multimesh.get_instance_transform(i)).origin
				)
				check(
					stage.terrain_rect.has_point(Vector2(point.x, point.z)),
					"трава внутри terrain_rect"
				)
				check(
					(
						stage.network.distance_to_road(point.x, point.z)
						>= stage.corridor_half() + stage.scenery.road_clearance - 0.01
					),
					"трава не попадает на дорогу"
				)
				result.append(point)
	return result


func clear_scenery(stage) -> void:
	var node: Node = stage.generated.get_node_or_null("Scenery")
	if node != null:
		node.free()


func _run() -> void:
	var defaults = load("res://data/stage/default_prop_library.tres")
	var cfg = load("res://data/stage/default_scenery.tres")
	var covers: Array[RallyProp] = defaults.ground_cover_props(cfg.ground_cover_prop_ids)
	check(covers.size() == 4, "grass2, grass3, грибы и цветы зарегистрированы как заполнение")
	check(defaults.by_id("grass2").supports_biome("forest"), "grass2 растёт в лесу")
	check(
		not defaults.by_id("grass3").supports_biome("forest"),
		"grass3 не смешивается с лесной травой"
	)
	for zone in range(4):
		check(cfg.biome_for_zone(zone) != null, "каждая зона имеет редактируемый биом")
	var forest: RallySceneryBiome = cfg.biome_for_zone(0)
	var patch: float = forest.density_at(-12.4, 15.0, 47)
	check(patch == forest.density_at(-12.4, 15.0, 47), "пятна детерминированы")
	check(patch >= forest.patch_floor and patch <= 1.0, "плотность пятен ограничена")
	check(
		(
			absf(
				forest.density_at(18.0 - 0.001, 5.0, 47) - forest.density_at(18.0 + 0.001, 5.0, 47)
			)
			< 0.001
		),
		"пятна непрерывны на границе ячеек"
	)
	for id in ["juniper", "dry_shrub", "moss_rock", "mushroom_cluster", "wildflowers"]:
		check(defaults.by_id(id) != null and defaults.by_id(id).scene != null, "новый пропс: " + id)

	# Новый вид без добавления id в конфиг; библиотека БЕЗ крупных объектов.
	var grass := Prop.new()
	grass.id = "custom_cover"
	grass.scene = load("res://scenes/props/grass2.tscn")
	grass.weight = 0.0
	grass.ground_cover = true
	grass.small = false  # ground_cover сам включает короткий LOD и отключает тени.
	grass.cover_max_slope = 89.0
	var library := Library.new()
	library.props = [grass]
	var empty_ids: Array[String] = []
	check(library.ground_cover_props(empty_ids).size() == 1, "авторегистрация нового вида")
	check(library.active_props().is_empty(), "заполнение не попадает в обычную урну")
	check(library.pick_cover([grass], 0.5) == grass, "вес заполнения независим от weight")
	grass.cover_weight = 0.0
	check(library.ground_cover_props(empty_ids).is_empty(), "нулевой вес выключает вид")
	grass.cover_weight = 1.0

	var stage = Stage.new()
	stage.prop_library = library
	stage.scenery = Scenery.new()
	stage.scenery.ground_cover_prop_ids.clear()
	stage.scenery.ground_cover_density = 1.0
	stage.scenery.max_instances = 80
	stage.track = Track.new()
	stage.track.use_baked_props = false
	stage.track.scenery_density = 1.0
	stage.track.terrain_seed = 4711
	var curve := Curve3D.new()
	curve.add_point(Vector3.ZERO)
	curve.add_point(Vector3(0, 0, 180))
	stage.terrain_rect = Rect2(-100, -100, 200, 400)
	stage.network = Network.build(curve, stage.terrain_rect, 3.0)
	stage._setup_noise()
	stage.generated = Node3D.new()
	stage.add_child(stage.generated)
	var baked: Mesh = stage._bake_prop_mesh(grass)
	check(baked.get_surface_count() > 0, "cross-card трава запекается в MultiMesh")
	var material = baked.surface_get_material(0)
	check(
		material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR,
		"alpha scissor сохраняется после запекания"
	)
	await stage._spawn_procedural_scenery(false)
	var first := positions(stage)
	check(
		first.size() > 0 and first.size() <= 80, "работает отдельно от деревьев и соблюдает бюджет"
	)
	clear_scenery(stage)
	await stage._spawn_procedural_scenery(false)
	check(first == positions(stage), "повторная сборка с тем же сидом совпадает")
	clear_scenery(stage)
	stage.track.scenery_density = 0.0
	await stage._spawn_procedural_scenery(false)
	check(positions(stage).is_empty(), "нулевая плотность трассы отключает заполнение")
	clear_scenery(stage)
	stage.track.scenery_density = 1.0
	stage.scenery.extra_grass_prop_ids = ["custom_cover"]
	stage.scenery.extra_grass_density = 2.5
	stage.scenery.ground_cover_density = 0.0
	await stage._spawn_procedural_scenery(false)
	check(positions(stage).is_empty(), "нулевая плотность заполнения работает")
	clear_scenery(stage)
	stage.scenery.ground_cover_density = 1.0
	stage.scenery.extra_grass_density = 0.0
	grass.cover_altitude = Vector2(99999, 100000)
	await stage._spawn_procedural_scenery(false)
	check(positions(stage).is_empty(), "ограничение по высоте работает")
	clear_scenery(stage)
	grass.cover_altitude = Vector2(-10000, 10000)
	grass.biome_ids = ["not_this_biome"]
	stage.scenery.biomes.assign(cfg.biomes)
	await stage._spawn_procedural_scenery(false)
	check(positions(stage).is_empty(), "несовместимый биом не заполняется")
	stage.free()
	print("Biome ground cover: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
