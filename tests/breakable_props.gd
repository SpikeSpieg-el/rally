# godot --headless --path . --fixed-fps 120 --script res://tests/breakable_props.gd
# Разрушаемые пропсы и коллизии обстановки:
#   * дощатый забор не прикован — машина сносит секции, они разлетаются
#     физическими обломками, машина теряет немного скорости и едет дальше;
#   * рестарт заезда ставит забор на место и убирает обломки;
#   * с выключенным разрушением тот же забор — твёрдое препятствие;
#   * формы коллизий из библиотеки есть у всех крупных пропсов, ресурсы фигур
#     общие (одна фигура на размер), а не по CollisionShape3D на дерево.
extends SceneTree

const CarModels = preload("res://scripts/car_models.gd")
const SETUP := preload("res://data/setups/11_gravel.tres")
const Library = preload("res://data/stage/default_prop_library.tres")
const Collision = preload("res://scripts/track/prop_collision.gd")
const BreakableProps = preload("res://scripts/track/breakable_props.gd")
const Debris = preload("res://scripts/track/breakable_debris.gd")

const FENCE_Z := 10.0
const CRASH_SPEED := 20.0

var failures: Array[String] = []


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)
	else:
		print("PASS: " + message)


func _initialize() -> void:
	call_deferred("_run")


func make_ground() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.add_to_group("Dirt")
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	var collider := CollisionShape3D.new()
	collider.shape = box
	collider.position.y = -0.5
	body.add_child(collider)
	return body


## Запечь сцену пропса в один меш (как это делает этап для MultiMesh).
func bake(scene: PackedScene) -> ArrayMesh:
	var out := ArrayMesh.new()
	for part in Collision.parts_of(scene):
		var mesh: Mesh = part["mesh"]
		var xform: Transform3D = part["xform"]
		for s in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in range(verts.size()):
				verts[i] = xform * verts[i]
			arrays[Mesh.ARRAY_VERTEX] = verts
			var normals = arrays[Mesh.ARRAY_NORMAL]
			if normals is PackedVector3Array:
				var n: PackedVector3Array = normals
				for i in range(n.size()):
					n[i] = (xform.basis * n[i]).normalized()
				arrays[Mesh.ARRAY_NORMAL] = n
			arrays[Mesh.ARRAY_TANGENT] = null
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


func make_fence(settings: RallyBreakableConfig) -> BreakableProps:
	var prop: RallyProp = Library.by_id("wooden_fence")
	var fence := BreakableProps.new()
	fence.name = "Fence"
	fence.setup(settings)
	var kind := fence.add_kind(prop, bake(prop.scene), 0.0)
	for x in [-5.2, -2.6, 0.0, 2.6, 5.2]:
		fence.add_instance(kind, Transform3D(Basis.IDENTITY, Vector3(x, 0.0, FENCE_Z)))
	return fence


func make_car(world: Node3D) -> RigidBody3D:
	var scene: PackedScene = load(CarModels.car_scene_paths()[0])
	var car = scene.instantiate()
	car.setup_override = SETUP
	car.mouse_look_enabled = false
	car.spawn_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.3, -14))
	car.position = Vector3(0, 0.3, -14)
	world.add_child(car)
	return car


func debris_node() -> Node:
	var nodes := get_nodes_in_group(Debris.GROUP)
	return nodes[0] if not nodes.is_empty() else null


## Разогнать машину на забор: вернёт [макс. z, скорость после забора].
func ram(car: RigidBody3D, frames: int) -> Array:
	car.spawn_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.3, -14))
	car.reset_to_spawn()
	for i in range(120):
		await physics_frame
	car.sleeping = false
	car.linear_velocity = Vector3(0, 0, CRASH_SPEED)
	car.angular_velocity = Vector3.ZERO
	var max_z := -INF
	var speed_after := 0.0
	for i in range(frames):
		await physics_frame
		max_z = maxf(max_z, car.global_position.z)
		if car.global_position.z > FENCE_Z + 2.0 and speed_after == 0.0:
			speed_after = car.linear_velocity.length()
	return [max_z, speed_after]


func _run() -> void:
	check_library()
	check_shared_shapes()

	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)
	world.add_child(make_ground())

	# 1. Разрушение включено: забор сносится.
	var settings: RallyBreakableConfig = (load("res://data/stage/default_breakables.tres") as RallyBreakableConfig).duplicate()
	check(settings.enabled, "разрушение включено по умолчанию")
	var fence := make_fence(settings)
	world.add_child(fence)
	fence.finalize()
	check(fence.item_count() == 5 and fence.collidable_count() == 5, "датчики на всех секциях")
	check(fence.find_child("*", false, false) is MultiMeshInstance3D, "секции рисуются одним MultiMesh")
	var car := make_car(world)
	var result: Array = await ram(car, 300)
	var max_z: float = result[0]
	var speed_after: float = result[1]
	check(fence.broken_count() >= 1, "машина снесла секции забора: %d" % fence.broken_count())
	check(max_z > FENCE_Z + 3.0, "машина проехала сквозь снесённый забор: z=%.2f" % max_z)
	check(speed_after > CRASH_SPEED - settings.max_car_speed_loss_mps * 2.0 - 3.0,
		"машина теряет немного скорости, но не встаёт: %.1f м/с" % speed_after)
	check(speed_after < CRASH_SPEED - 0.1, "удар о забор отнимает скорость: %.1f м/с" % speed_after)
	var debris := debris_node()
	check(debris != null, "узел обломков создан")
	if debris != null:
		check(int(debris.call("piece_count")) >= 3, "забор рассыпался на доски: %d" % int(debris.call("piece_count")))
		var flown := 0
		var bodies := 0
		for child in debris.get_children():
			if not child is RigidBody3D:
				continue
			bodies += 1
			if (child as RigidBody3D).global_position.z > FENCE_Z + 1.0:
				flown += 1
			if bodies == 1:
				check(((child as RigidBody3D).collision_layer & 3) == 0, "обломки не на слое земли и препятствий")
				check(((child as RigidBody3D).collision_mask & 1) != 0, "обломки падают на землю")
		check(bodies >= 1 and flown >= 1, "обломки улетают вперёд по ходу машины")
	# 2. Рестарт заезда: забор на месте, обломков нет.
	car.call("restart_at_spawn")
	await process_frame
	check(fence.broken_count() == 0, "рестарт ставит забор на место")
	if debris != null:
		check(int(debris.call("piece_count")) == 0, "рестарт убирает обломки")
	# Снова сносится после рестарта.
	result = await ram(car, 300)
	check(fence.broken_count() >= 1, "после рестарта забор снова сносится")
	fence.queue_free()
	await physics_frame

	# 3. Разрушение выключено: твёрдый забор.
	var solid_settings := settings.duplicate() as RallyBreakableConfig
	solid_settings.enabled = false
	var solid := make_fence(solid_settings)
	world.add_child(solid)
	solid.finalize()
	await physics_frame
	result = await ram(car, 300)
	check(float(result[0]) < FENCE_Z, "выключенное разрушение — забор держит машину: z=%.2f" % float(result[0]))
	check(solid.broken_count() == 0, "твёрдый забор не ломается")

	car.queue_free()
	world.queue_free()
	await process_frame
	print("Breakable props: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)


## Формы коллизий есть у всех крупных пропсов библиотеки.
func check_library() -> void:
	for id in ["fir_tree", "pine_tree", "birch_tree", "dead_tree", "boulder", "rock_cluster", "stump",
			"log", "hay_bale", "tire_stack", "sandbag_barrier", "wooden_fence", "sponsor_banner",
			"traffic_cone", "stop_sign", "parked_car", "broken_car", "marshal_tent", "power_pole",
			"river_bank_rock", "dry_stone_wall"]:
		var prop: RallyProp = Library.by_id(id)
		check(prop != null, "пропс в библиотеке: " + id)
		if prop == null:
			continue
		var entries := Collision.entries_for(prop)
		check(not entries.is_empty(), "у пропса есть форма коллизии: " + id)
		for entry in entries:
			var size: Vector3 = entry["size"]
			check(size.x > 0.02 and size.y > 0.02, "форма не вырождена: %s %s" % [id, str(size)])
	var fence: RallyProp = Library.by_id("wooden_fence")
	check(fence != null and fence.breakable, "дощатый забор разрушаемый")
	var fence_shapes := Collision.entries_for(fence)
	check(fence_shapes.size() == 1 and (fence_shapes[0]["size"] as Vector3).is_equal_approx(Vector3(2.8, 1.75, 0.28)),
		"запасная форма забора — коробка из его сцены")
	for id in ["fir_tree", "birch_tree", "dead_tree"]:
		check(Library.by_id(id).collider_spacing == 0.0, "у каждого дерева у дороги своя коллизия: " + id)


## Сотни одинаковых деревьев — одна фигура и ни одного CollisionShape3D.
func check_shared_shapes() -> void:
	var prop: RallyProp = Library.by_id("fir_tree")
	var body := Collision.make_body("Trunks")
	var before := Collision.cached_shape_count()
	var added := 0
	for i in range(300):
		added += Collision.add_instance(body, Collision.entries_for(prop), Transform3D(Basis(Vector3.UP, float(i)), Vector3(i * 3.0, 0, 0)))
	check(added == 300, "по фигуре на дерево: %d" % added)
	check(Collision.cached_shape_count() - before <= 1, "одна общая фигура на размер: +%d" % (Collision.cached_shape_count() - before))
	check(PhysicsServer3D.body_get_shape_count(body.get_rid()) == 300, "фигуры лежат в теле на сервере")
	check(body.get_child_count() == 0, "без узла на дерево")
	check(body.collision_layer == 2, "слой препятствий кузова")
	body.free()
