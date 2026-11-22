## Разрушаемые пропсы одного куска мира: дощатый забор на повороте, щиты и
## заборчики из случайной обстановки, таблички и конусы оформления.
##
## Пока пропс цел, у него нет твёрдой коллизии: он рисуется MultiMesh'ем
## (сотни секций забора — один узел), а машину ловит лёгкий датчик — область
## физического сервера с коробкой на каждый пропс (без узлов на пропс).
## Машина въехала в датчик — пропс прячется и в тот же кадр рассыпается на
## физические обломки (BreakableDebris), машина отдаёт ему часть импульса,
## летят щепки, звучит треск, камера вздрагивает, на кузове остаётся след.
##
## Если разрушение выключено в настройке (RallyBreakableConfig.enabled), те же
## пропсы становятся обычными твёрдыми препятствиями с формой из библиотеки.
##
## Порядок работы: setup() → add_kind() → add_instance()/add_node() → finalize().
## finalize() можно звать повторно (пересобирает датчики и MultiMesh).
extends Node3D

const Collision = preload("res://scripts/track/prop_collision.gd")
const Debris = preload("res://scripts/track/breakable_debris.gd")

const GROUP := "rally_breakable_props"
## Слои тел, которые может снести машина: RallyCar лежит на первом слое.
const CAR_MASK := 1

## Пропс снесён: мировая точка удара, id пропса и скорость машины.
signal prop_broken(world_point: Vector3, prop_id: String, speed: float)

var config: RallyBreakableConfig = null

var _kinds: Array[Dictionary] = []
var _items: Array[Dictionary] = []
var _shape_item := PackedInt32Array()
var _area := RID()
var _solid: StaticBody3D = null
var _finalized := false
var _dirty := false
var _queued := false
var _broken := 0


## Настройка разрушения (общая для сцены этапа).
func setup(settings: RallyBreakableConfig) -> void:
	config = settings


func cfg() -> RallyBreakableConfig:
	if config == null:
		config = RallyBreakableConfig.new()
	return config


## Вид пропса. mesh — запечённый меш (как у остального леса).
## visibility_end — дальность видимости MultiMesh, 0 — без ограничения.
func add_kind(prop: RallyProp, mesh: Mesh, visibility_end: float = 0.0, cast_shadows: bool = true) -> int:
	var parts: Array = []
	if prop != null and prop.break_into_parts:
		parts = Collision.parts_of(prop.scene)
	if parts.is_empty() and mesh != null:
		parts = [{"mesh": mesh, "xform": Transform3D.IDENTITY, "aabb": mesh.get_aabb()}]
	var bounds: AABB = Collision.bounds_of(prop.scene if prop != null else null)
	if mesh != null:
		bounds = mesh.get_aabb()
	_kinds.append({
		"prop": prop,
		"mesh": mesh,
		"parts": parts,
		"bounds": bounds,
		"visibility": visibility_end,
		"shadows": cast_shadows,
		"multimesh": null,
		"slots": 0,
	})
	return _kinds.size() - 1


## Экземпляр вида: xform — в системе этого узла (с масштабом и растяжкой).
## collide = false — только картинка (пропс далеко от дороги).
func add_instance(kind: int, xform: Transform3D, collide: bool = true) -> int:
	if kind < 0 or kind >= _kinds.size():
		return -1
	var slot: int = _kinds[kind]["slots"]
	_kinds[kind]["slots"] = slot + 1
	_items.append({"kind": kind, "slot": slot, "node": null, "xform": xform, "collide": collide,
		"broken": false})
	_queue_finalize()
	return _items.size() - 1


## Готовый узел сцены пропса (табличка с номером, конус): снесённый, он
## улетает целиком — с надписями и всем, что в нём есть.
func add_node(prop: RallyProp, node: Node3D, collide: bool = true) -> int:
	if node == null:
		return -1
	var kind := -1
	for k in range(_kinds.size()):
		if _kinds[k]["prop"] == prop and _kinds[k]["mesh"] == null:
			kind = k
	if kind < 0:
		_kinds.append({
			"prop": prop,
			"mesh": null,
			"parts": [],
			"bounds": Collision.bounds_of(prop.scene if prop != null else null),
			"visibility": 0.0,
			"shadows": true,
			"multimesh": null,
			"slots": 0,
		})
		kind = _kinds.size() - 1
	_items.append({"kind": kind, "slot": -1, "node": node, "xform": Transform3D.IDENTITY,
		"collide": collide, "broken": false})
	_queue_finalize()
	return _items.size() - 1


## Собрать MultiMesh и датчики. Узел должен быть в дереве, чтобы датчики
## попали в физический мир (иначе соберутся при входе в дерево).
func finalize() -> void:
	_finalized = true
	_dirty = false
	for k in range(_kinds.size()):
		_build_multimesh(k)
	_refresh_node_xforms()
	if is_inside_tree():
		_build_physics()


## Без явного finalize() узел соберётся сам в конце кадра.
func _queue_finalize() -> void:
	_dirty = true
	if _queued:
		return
	_queued = true
	_auto_finalize.call_deferred()


func _auto_finalize() -> void:
	_queued = false
	if _dirty and is_inside_tree():
		finalize()


func _enter_tree() -> void:
	add_to_group(GROUP)
	if _finalized and not _area.is_valid() and _solid == null:
		_build_physics.call_deferred()


func _exit_tree() -> void:
	_free_area()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_free_area()


## Всего разрушаемых пропсов.
func item_count() -> int:
	return _items.size()


## Сколько из них ловит датчик (близко к дороге).
func collidable_count() -> int:
	var count := 0
	for item in _items:
		if item["collide"]:
			count += 1
	return count


## Сколько снесено с последнего восстановления.
func broken_count() -> int:
	return _broken


## Вернуть всё на место (рестарт заезда): снесённые пропсы встают, датчики
## снова ловят машину, обломки убираются. restore_on_restart = false — всё
## остаётся как было.
func restore_all() -> void:
	if not cfg().restore_on_restart:
		return
	if _broken > 0:
		for item in _items:
			if not item["broken"]:
				continue
			item["broken"] = false
			var node: Node3D = item["node"]
			if is_instance_valid(node):
				node.visible = true
			elif int(item["slot"]) >= 0:
				var multimesh: MultiMesh = _kinds[item["kind"]]["multimesh"]
				if multimesh != null:
					multimesh.set_instance_transform(item["slot"], item["xform"])
		_broken = 0
		if _area.is_valid():
			for shape in range(_shape_item.size()):
				PhysicsServer3D.area_set_shape_disabled(_area, shape, false)
	if is_inside_tree():
		for debris in get_tree().get_nodes_in_group(Debris.GROUP):
			debris.call("clear_pieces")


## Снести пропс номер index (так же, как от удара машины). Для проверок и
## внешних событий (взрыв, падение дерева).
func break_item(index: int, car: Node = null) -> bool:
	if index < 0 or index >= _items.size() or _items[index]["broken"]:
		return false
	_items[index]["broken"] = true
	var shape := _shape_item.find(index)
	if shape >= 0 and _area.is_valid():
		PhysicsServer3D.area_set_shape_disabled(_area, shape, true)
	_break(index, car)
	return true


## Мировой трансформ пропса номер index.
func item_transform(index: int) -> Transform3D:
	var item: Dictionary = _items[index]
	var node: Node3D = item["node"]
	if is_instance_valid(node) and node.is_inside_tree():
		return node.global_transform
	return global_transform * (item["xform"] as Transform3D)


func _build_multimesh(k: int) -> void:
	var kind: Dictionary = _kinds[k]
	var mesh: Mesh = kind["mesh"]
	if mesh == null:
		return
	var transforms: Array[Transform3D] = []
	transforms.resize(kind["slots"])
	for item in _items:
		if item["kind"] == k:
			transforms[item["slot"]] = Transform3D(Basis.from_scale(Vector3.ZERO), (item["xform"] as Transform3D).origin) \
				if item["broken"] else item["xform"]
	var multimesh: MultiMesh = kind["multimesh"]
	if multimesh == null:
		multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		kind["multimesh"] = multimesh
		var visual := MultiMeshInstance3D.new()
		var prop: RallyProp = kind["prop"]
		visual.name = (prop.group_name() if prop != null else "Breakable") + "_%d" % k
		visual.multimesh = multimesh
		if float(kind["visibility"]) > 0.0:
			visual.visibility_range_end = kind["visibility"]
			visual.visibility_range_end_margin = 30.0
			visual.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if not kind["shadows"]:
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(visual)
	multimesh.instance_count = transforms.size()
	for i in range(transforms.size()):
		multimesh.set_instance_transform(i, transforms[i])


func _refresh_node_xforms() -> void:
	if not is_inside_tree():
		return
	var to_local := global_transform.affine_inverse()
	for item in _items:
		var node: Node3D = item["node"]
		if is_instance_valid(node) and node.is_inside_tree():
			item["xform"] = to_local * node.global_transform


## Датчики (разрушение включено) или твёрдые фигуры (выключено).
func _build_physics() -> void:
	_free_area()
	if not is_inside_tree():
		return
	_refresh_node_xforms()
	var tuning := cfg()
	if not tuning.enabled:
		_build_solid()
		return
	_shape_item = PackedInt32Array()
	var area := PhysicsServer3D.area_create()
	PhysicsServer3D.area_set_space(area, get_world_3d().space)
	PhysicsServer3D.area_set_transform(area, global_transform)
	PhysicsServer3D.area_set_collision_layer(area, 0)
	PhysicsServer3D.area_set_collision_mask(area, CAR_MASK)
	PhysicsServer3D.area_set_monitorable(area, false)
	for i in range(_items.size()):
		var item: Dictionary = _items[i]
		if not item["collide"]:
			continue
		var bounds: AABB = _kinds[item["kind"]]["bounds"]
		if bounds.size.length_squared() < 1e-6:
			continue
		var entry := {"kind": Collision.Kind.BOX, "size": bounds.size, "xform": Transform3D(Basis.IDENTITY, bounds.get_center())}
		for pair in Collision.world_shapes([entry], item["xform"], tuning.detect_margin_m):
			PhysicsServer3D.area_add_shape(area, (pair[0] as Shape3D).get_rid(), pair[1], item["broken"])
			_shape_item.append(i)
	PhysicsServer3D.area_set_monitor_callback(area, _on_area_event)
	_area = area


func _build_solid() -> void:
	_solid = Collision.make_body("BreakableSolid")
	add_child(_solid)
	for item in _items:
		if not item["collide"] or item["broken"]:
			continue
		Collision.add_instance(_solid, Collision.entries_for(_kinds[item["kind"]]["prop"]), item["xform"])


func _free_area() -> void:
	if _area.is_valid():
		PhysicsServer3D.free_rid(_area)
	_area = RID()
	if _solid != null and is_instance_valid(_solid):
		_solid.queue_free()
	_solid = null


## Колбэк области физического сервера (идёт из шага физики).
func _on_area_event(status: int, _body: RID, instance_id: int, _body_shape: int, area_shape: int) -> void:
	if status != PhysicsServer3D.AREA_BODY_ADDED:
		return
	if area_shape < 0 or area_shape >= _shape_item.size():
		return
	var car := instance_from_id(instance_id) as Node
	if car == null or not car.is_in_group("rally_car"):
		return
	var index: int = _shape_item[area_shape]
	if _items[index]["broken"]:
		return
	_items[index]["broken"] = true
	# Ни узлы, ни фигуры области не трогаем внутри шага физики.
	_break_from_sensor.call_deferred(index, car)


func _break_from_sensor(index: int, car: Node) -> void:
	var shape := _shape_item.find(index)
	if shape >= 0 and _area.is_valid():
		PhysicsServer3D.area_set_shape_disabled(_area, shape, true)
	_break(index, car)


func _break(index: int, car: Node) -> void:
	var item: Dictionary = _items[index]
	var kind: Dictionary = _kinds[item["kind"]]
	var prop: RallyProp = kind["prop"]
	var tuning := cfg()
	var world := item_transform(index)
	var bounds: AABB = kind["bounds"]
	var car_body: RigidBody3D = null
	if is_instance_valid(car):
		car_body = car as RigidBody3D
	var velocity: Vector3 = Vector3.ZERO
	var car_position: Vector3 = world.origin
	if car_body != null:
		velocity = car_body.linear_velocity
		car_position = car_body.global_position
	var contact := _closest_point(world, bounds, car_position)
	var mass: float = prop.break_mass_kg if prop != null else 30.0
	var debris := _debris()
	debris.config = tuning
	# Прячем целый пропс.
	var node: Node3D = item["node"]
	if is_instance_valid(node):
		node.visible = false
		if prop == null or not prop.break_into_parts:
			var copy := node.duplicate() as Node3D
			if copy != null:
				copy.visible = true
				debris.spawn_node(copy, world, bounds, mass, velocity, contact, car_body)
		else:
			debris.spawn(Collision.parts_of(prop.scene), world, mass, velocity, contact, car_body)
	else:
		var multimesh: MultiMesh = kind["multimesh"]
		if multimesh != null:
			multimesh.set_instance_transform(item["slot"],
				Transform3D(Basis.from_scale(Vector3.ZERO), (item["xform"] as Transform3D).origin))
		debris.spawn(kind["parts"], world, mass, velocity, contact, car_body)
	var speed := velocity.length()
	var strength := tuning.strength(speed)
	var color := tuning.splinter_color
	if prop != null and prop.splinter_color.a > 0.0:
		color = prop.splinter_color
	debris.burst(contact, velocity, strength, color)
	_broken += 1
	if car_body != null:
		_car_feedback(car_body, contact, velocity, mass, strength)
	prop_broken.emit(contact, prop.id if prop != null else "", speed)


## Машина отдаёт пропсу импульс, камера вздрагивает, на кузове — след.
func _car_feedback(car: RigidBody3D, contact: Vector3, velocity: Vector3, mass: float, strength: float) -> void:
	var tuning := cfg()
	var speed := velocity.length()
	if speed > 0.05 and tuning.momentum_transfer > 0.0:
		var loss := minf(mass * speed * tuning.momentum_transfer / maxf(car.mass, 1.0), tuning.max_car_speed_loss_mps)
		loss = minf(loss, speed)
		car.apply_central_impulse(-velocity / speed * loss * car.mass)
	var into := car.global_position - contact
	into.y = 0.0
	if into.length_squared() > 1e-6:
		into = into.normalized()
	else:
		into = -velocity.normalized()
	var fx = car.get("impact_fx")
	if fx != null and is_instance_valid(fx) and fx.has_method("nudge"):
		fx.call("nudge", into, tuning.shake * strength, tuning.kick * strength, tuning.rumble * strength,
			tuning.rumble_duration)
	var visual = car.get("damage_visual")
	if visual != null and is_instance_valid(visual) and tuning.car_dent_per_mps > 0.0:
		var dv := minf(speed * tuning.car_dent_per_mps, tuning.car_dent_max_dv)
		if dv > 0.3:
			var to_car := car.global_transform.affine_inverse()
			var tangent := velocity - into * velocity.dot(into)
			visual.call("apply_impact", to_car * contact, to_car.basis * into, dv, to_car.basis * tangent)


func _closest_point(world: Transform3D, bounds: AABB, point: Vector3) -> Vector3:
	var local := world.affine_inverse() * point
	var clamped := local.clamp(bounds.position, bounds.end)
	return world * clamped


func _debris() -> Debris:
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group(Debris.GROUP):
			if is_instance_valid(node) and not node.is_queued_for_deletion():
				return node as Debris
	var manager := Debris.new()
	manager.name = "BreakableDebris"
	var host: Node = self
	var root := get_tree().root if is_inside_tree() else null
	while host.get_parent() != null and host.get_parent() != root:
		host = host.get_parent()
	host.add_child(manager)
	return manager
