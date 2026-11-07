@tool
## Детерминированная лесная обстановка. Кнопка Bake делает каждый объект
## отдельным редактируемым узлом сцены; вручную добавленные не трогаются.
extends Node3D

const PINE = preload("res://scenes/props/pine_tree.tscn")
const FIR = preload("res://scenes/props/fir_tree.tscn")
const BIRCH = preload("res://scenes/props/birch_tree.tscn")
const BUSH = preload("res://scenes/props/bush.tscn")
const FERN = preload("res://scenes/props/fern.tscn")
const ROCK = preload("res://scenes/props/rock_cluster.tscn")
const STUMP = preload("res://scenes/props/stump.tscn")
const SIGN = preload("res://scenes/props/road_sign.tscn")

@export var auto_scatter := true
@export var seed_value := 4711
@export_range(0, 500, 1) var tree_count := 155
@export_range(0, 500, 1) var detail_count := 85
@export_range(0, 30, 1) var sign_count := 6
@export_range(8.0, 50.0, 1.0, "suffix:m") var road_clearance := 11.0
@export_tool_button("Пересоздать расстановку") var rebuild_button = rebuild
@export_tool_button("Сделать объекты редактируемыми") var bake_button = bake

func _ready() -> void:
	var terrain = get_node_or_null("../Ground")
	if Engine.is_editor_hint() and terrain != null and terrain.has_signal("terrain_rebuilt"):
		terrain.terrain_rebuilt.connect(_terrain_changed)
	if auto_scatter:
		rebuild()

func _terrain_changed() -> void:
	if auto_scatter:
		call_deferred("rebuild")

func rebuild() -> void:
	var terrain = get_node_or_null("../Ground")
	if terrain == null or terrain.network == null:
		return
	for child in get_children():
		if child.has_meta("menu_scattered"):
			remove_child(child)
			child.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var trees := [PINE, FIR, FIR, BIRCH]
	var details := [BUSH, FERN, ROCK, STUMP]
	var size: Vector2 = terrain.terrain_size
	var route := get_node_or_null("../Track") as Path3D
	if route == null or route.curve == null:
		return
	var length := route.curve.get_baked_length()
	for i in range(tree_count + detail_count):
		var position_xz := Vector2.ZERO
		var accepted := false
		for attempt in range(60):
			if i % 2 == 0:
				# Половина ассетов обрамляет дорогу, не только дальнюю границу карты.
				var along := rng.randf_range(0.0, length)
				var center := route.curve.sample_baked(along, true)
				var ahead := route.curve.sample_baked(fposmod(along + 1.0, length), true)
				var direction := (ahead - center).normalized()
				var side := Vector3(direction.z, 0.0, -direction.x).normalized()
				var lateral := rng.randf_range(road_clearance + 4.0, 50.0) * (1.0 if rng.randi() % 2 == 0 else -1.0)
				position_xz = Vector2(center.x + side.x * lateral, center.z + side.z * lateral)
			else:
				position_xz = Vector2(rng.randf_range(-size.x * 0.48, size.x * 0.48), rng.randf_range(-size.y * 0.48, size.y * 0.48))
			if absf(position_xz.x) > size.x * 0.48 or absf(position_xz.y) > size.y * 0.48:
				continue
			var distance: float = terrain.network.distance_to_road(position_xz.x, position_xz.y)
			# Деревья не перекрывают дорогу; мелкие кусты ближе к обочинам.
			var clearance := road_clearance + (3.0 if i < tree_count else 0.0)
			if distance >= clearance:
				accepted = true
				break
		if not accepted:
			continue
		var options: Array = trees if i < tree_count else details
		var scene: PackedScene = options[rng.randi_range(0, options.size() - 1)]
		var prop := scene.instantiate() as Node3D
		prop.name = "Tree_%03d" % i if i < tree_count else "Detail_%03d" % (i - tree_count)
		prop.set_meta("menu_scattered", true)
		add_child(prop)
		prop.position = Vector3(position_xz.x, terrain.ground_height(position_xz.x, position_xz.y) - 0.08, position_xz.y)
		prop.rotation.y = rng.randf_range(0.0, TAU)
		var factor := rng.randf_range(0.8, 1.2)
		prop.scale *= factor
	# Игровые дорожные знаки стоят у обочины, а не на проезжей части.
	for i in range(sign_count):
		var along := length * (float(i) + 0.5) / float(sign_count)
		var center := route.curve.sample_baked(along, true)
		var ahead := route.curve.sample_baked(fposmod(along + 1.0, length), true)
		var direction := (ahead - center).normalized()
		var side := Vector3(direction.z, 0.0, -direction.x).normalized()
		var sign := SIGN.instantiate() as Node3D
		sign.name = "RoadSign_%02d" % i
		sign.set_meta("menu_scattered", true)
		add_child(sign)
		sign.position = center + side * (road_clearance - 1.5)
		sign.position.y = terrain.ground_height(sign.position.x, sign.position.z) - 0.08
		sign.rotation.y = atan2(-direction.x, -direction.z)

## Привязать сохранённые или вручную расставленные объекты к мешу рельефа.
@export_tool_button("Посадить объекты на землю") var snap_button = snap_to_ground
func snap_to_ground() -> void:
	var terrain = get_node_or_null("../Ground")
	if terrain == null or terrain.network == null:
		return
	for prop in get_children():
		if prop is Node3D:
			prop.position.y = terrain.ground_height(prop.position.x, prop.position.z) - 0.08

func bake() -> void:
	if not Engine.is_editor_hint():
		return
	var scene_root := get_tree().edited_scene_root
	if scene_root == null:
		return
	if get_child_count() == 0:
		rebuild()
	auto_scatter = false
	for prop in get_children():
		if prop.has_meta("menu_scattered"):
			prop.remove_meta("menu_scattered")
			prop.owner = scene_root
