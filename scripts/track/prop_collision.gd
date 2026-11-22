## Коллизии пропсов: форма из библиотеки (RallyProp.collider_shape), общие
## ресурсы фигур и быстрая укладка прямо в физический сервер.
##
## Почему так, а не CollisionShape3D на каждое дерево:
##   * фигура одного размера — один ресурс на всю сцену (кэш по размеру:
##     2 см у мелких, 4 % у крупных), а не тысяча одинаковых CylinderShape3D;
##   * фигуры кладутся в тело ячейки через PhysicsServer3D.body_add_shape —
##     без узла на каждую фигуру: сборка чанка не создаёт тысячи узлов, дерево
##     сцены остаётся лёгким, а физика видит ровно те же фигуры;
##   * тело одно на ячейку/чанк и уходит вместе с ним — RID освобождает узел.
##
## Габариты сцен, фигуры из сцен и детали для обломков считаются один раз на
## сцену и кэшируются.
extends RefCounted

## Слой препятствий кузова: машина бьётся (маска 3), колёса не опираются.
const OBSTACLE_LAYER := 2
## Шаг округления малых размеров фигур в кэше, м.
const SIZE_STEP := 0.02
## Относительный шаг для размеров больше LINEAR_LIMIT (4 % — ошибка ±2 %).
const SIZE_REL_STEP := 0.04
## До этого размера сетка линейная: 0.5 м / 4 % = шаг 2 см — стыкуется.
const LINEAR_LIMIT := 0.5

enum Kind { BOX, CYLINDER, SPHERE, CAPSULE }

static var _shape_cache: Dictionary = {}
static var _bounds_cache: Dictionary = {}
static var _scene_shape_cache: Dictionary = {}
static var _parts_cache: Dictionary = {}
static var _entries_cache: Dictionary = {}


## Статическое тело-препятствие для пачки фигур (одно на ячейку или чанк).
static func make_body(body_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = OBSTACLE_LAYER
	body.collision_mask = 0
	return body


## Фигуры пропса в его собственной системе координат (масштаб 1):
## [{kind, size, xform}]. size: коробка — полный размер; цилиндр и капсула —
## (радиус, высота, радиус); сфера — (r, r, r). Пусто — коллизии нет.
static func entries_for(prop: RallyProp) -> Array:
	if prop == null or prop.collider_shape == RallyProp.ColliderShape.NONE:
		return []
	var key := "%d|%d|%.3f|%.3f|%.3f|%s" % [
		prop.get_instance_id(), prop.collider_shape, prop.collider_radius,
		prop.collider_height, prop.collider_y_offset, str(prop.collider_fit_scale),
	]
	if _entries_cache.has(key):
		return _entries_cache[key]
	var out: Array = []
	var fit := prop.collider_fit_scale
	match prop.collider_shape:
		RallyProp.ColliderShape.CYLINDER:
			out.append(_entry(Kind.CYLINDER, Vector3(prop.collider_radius, prop.collider_height, prop.collider_radius),
				Vector3(0.0, prop.collider_y_offset + prop.collider_height * 0.5, 0.0)))
		RallyProp.ColliderShape.SCENE:
			out = scene_shapes(prop.scene)
		RallyProp.ColliderShape.AUTO:
			out = scene_shapes(prop.scene)
			if out.is_empty():
				out = _fit_entries(prop.scene, Kind.BOX, fit, prop.collider_y_offset)
		RallyProp.ColliderShape.BOX_FIT:
			out = _fit_entries(prop.scene, Kind.BOX, fit, prop.collider_y_offset)
		RallyProp.ColliderShape.CYLINDER_FIT:
			out = _fit_entries(prop.scene, Kind.CYLINDER, fit, prop.collider_y_offset)
		RallyProp.ColliderShape.SPHERE_FIT:
			out = _fit_entries(prop.scene, Kind.SPHERE, fit, prop.collider_y_offset)
	_entries_cache[key] = out
	return out


## Сбросить кэш форм (после правки библиотеки в редакторе).
static func clear_cache() -> void:
	_entries_cache.clear()
	_bounds_cache.clear()
	_scene_shape_cache.clear()
	_parts_cache.clear()


## Положить фигуры одного экземпляра в тело. xform — экземпляр в системе тела
## (с масштабом). Вернёт число добавленных фигур.
static func add_instance(body: CollisionObject3D, entries: Array, xform: Transform3D) -> int:
	if body == null or entries.is_empty():
		return 0
	var rid := body.get_rid()
	var count := 0
	for pair in world_shapes(entries, xform):
		PhysicsServer3D.body_add_shape(rid, (pair[0] as Shape3D).get_rid(), pair[1])
		count += 1
	return count


## Фигуры экземпляра: [[Shape3D, Transform3D]] с учётом масштаба экземпляра.
## Масштаб «запекается» в размер фигуры (физика не любит масштаб в базисе).
static func world_shapes(entries: Array, xform: Transform3D, grow: float = 0.0) -> Array:
	var out: Array = []
	for entry in entries:
		var local: Transform3D = entry["xform"]
		var kind: int = entry["kind"]
		var size: Vector3 = entry["size"]
		var axis_x := (xform.basis * local.basis.x).length()
		var axis_y := (xform.basis * local.basis.y).length()
		var axis_z := (xform.basis * local.basis.z).length()
		var scaled := size
		match kind:
			Kind.BOX:
				scaled = Vector3(size.x * axis_x, size.y * axis_y, size.z * axis_z) + Vector3.ONE * (grow * 2.0)
			Kind.CYLINDER, Kind.CAPSULE:
				var r: float = size.x * maxf(axis_x, axis_z) + grow
				scaled = Vector3(r, size.y * axis_y + grow * 2.0, r)
			Kind.SPHERE:
				var rs: float = size.x * maxf(axis_x, maxf(axis_y, axis_z)) + grow
				scaled = Vector3(rs, rs, rs)
		var basis := (xform.basis * local.basis).orthonormalized()
		out.append([shape_for(kind, scaled), Transform3D(basis, xform * local.origin)])
	return out


## Общий ресурс фигуры нужного размера. Размеры округляются по
## логарифмической сетке (шаг SIZE_REL_STEP, но не мельче SIZE_STEP): у
## случайно отмасштабированных деревьев сотни размеров сводятся к десяткам
## ресурсов, а ошибка формы не больше ±2 % (для ствола — миллиметры).
static func shape_for(kind: int, size: Vector3) -> Shape3D:
	var qx := _quantize(size.x)
	var qy := _quantize(size.y)
	var qz := _quantize(size.z)
	var key := Vector4i(kind, qx, qy, qz)
	if _shape_cache.has(key):
		return _shape_cache[key]
	var sx := _dequantize(qx)
	var sy := _dequantize(qy)
	var sz := _dequantize(qz)
	var shape: Shape3D = null
	match kind:
		Kind.BOX:
			var box := BoxShape3D.new()
			box.size = Vector3(sx, sy, sz)
			shape = box
		Kind.CYLINDER:
			var cylinder := CylinderShape3D.new()
			cylinder.radius = sx
			cylinder.height = sy
			shape = cylinder
		Kind.CAPSULE:
			var capsule := CapsuleShape3D.new()
			capsule.radius = sx
			capsule.height = maxf(sy, capsule.radius * 2.0)
			shape = capsule
		_:
			var sphere := SphereShape3D.new()
			sphere.radius = sx
			shape = sphere
	_shape_cache[key] = shape
	return shape


## Номер ячейки размера: до LINEAR_LIMIT — линейно с шагом SIZE_STEP,
## дальше — логарифмически с шагом SIZE_REL_STEP.
static func _quantize(value: float) -> int:
	var v := maxf(value, SIZE_STEP)
	if v <= LINEAR_LIMIT:
		return roundi(v / SIZE_STEP)
	var linear_cells := roundi(LINEAR_LIMIT / SIZE_STEP)
	return linear_cells + roundi(log(v / LINEAR_LIMIT) / log(1.0 + SIZE_REL_STEP))


static func _dequantize(cell: int) -> float:
	var linear_cells := roundi(LINEAR_LIMIT / SIZE_STEP)
	if cell <= linear_cells:
		return maxf(cell, 1) * SIZE_STEP
	return LINEAR_LIMIT * pow(1.0 + SIZE_REL_STEP, cell - linear_cells)


## Сколько разных ресурсов фигур создано (для проверок и профилирования).
static func cached_shape_count() -> int:
	return _shape_cache.size()


## Габариты видимых мешей сцены (без коллизий и узлов-помощников).
static func bounds_of(scene: PackedScene) -> AABB:
	if scene == null:
		return AABB()
	var key := scene.get_instance_id()
	if _bounds_cache.has(key):
		return _bounds_cache[key]
	var root := scene.instantiate()
	var state := {"bounds": AABB(), "first": true}
	_collect_bounds(root, Transform3D.IDENTITY, state)
	if root != null:
		root.free()
	_bounds_cache[key] = state["bounds"]
	return state["bounds"]


## Фигуры CollisionShape3D, нарисованные в сцене пропса, в системе её корня.
static func scene_shapes(scene: PackedScene) -> Array:
	if scene == null:
		return []
	var key := scene.get_instance_id()
	if _scene_shape_cache.has(key):
		return _scene_shape_cache[key]
	var out: Array = []
	var root := scene.instantiate()
	_collect_shapes(root, Transform3D.IDENTITY, out)
	if root != null:
		root.free()
	_scene_shape_cache[key] = out
	return out


## Детали для обломков: каждый MeshInstance3D сцены — [{mesh, xform, aabb}],
## xform — в системе корня сцены, aabb — габариты меша в его системе.
static func parts_of(scene: PackedScene) -> Array:
	if scene == null:
		return []
	var key := scene.get_instance_id()
	if _parts_cache.has(key):
		return _parts_cache[key]
	var out: Array = []
	var root := scene.instantiate()
	_collect_parts(root, Transform3D.IDENTITY, out)
	if root != null:
		root.free()
	_parts_cache[key] = out
	return out


static func _entry(kind: int, size: Vector3, origin: Vector3, basis: Basis = Basis.IDENTITY) -> Dictionary:
	return {"kind": kind, "size": size, "xform": Transform3D(basis, origin)}


static func _fit_entries(scene: PackedScene, kind: int, fit: Vector3, y_offset: float) -> Array:
	var bounds := bounds_of(scene)
	if bounds.size.length_squared() < 1e-6:
		return []
	var size := bounds.size * fit
	var center := bounds.get_center()
	# Низ фигуры остаётся на земле, даже если её сжали по высоте.
	center.y = bounds.position.y + size.y * 0.5 + y_offset
	match kind:
		Kind.CYLINDER:
			return [_entry(Kind.CYLINDER, Vector3(maxf(size.x, size.z) * 0.5, size.y, 0.0), center)]
		Kind.SPHERE:
			var r: float = maxf(size.x, maxf(size.y, size.z)) * 0.5
			return [_entry(Kind.SPHERE, Vector3(r, r, r), center)]
		_:
			return [_entry(Kind.BOX, size, center)]


static func _collect_bounds(node: Node, parent: Transform3D, state: Dictionary) -> void:
	if node == null or node is CollisionObject3D:
		return
	var xform := parent
	if node is Node3D:
		xform = parent * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var box: AABB = xform * (node as MeshInstance3D).mesh.get_aabb()
		if state["first"]:
			state["bounds"] = box
			state["first"] = false
		else:
			state["bounds"] = (state["bounds"] as AABB).merge(box)
	for child in node.get_children():
		_collect_bounds(child, xform, state)


static func _collect_shapes(node: Node, parent: Transform3D, out: Array) -> void:
	if node == null:
		return
	var xform := parent
	if node is Node3D:
		xform = parent * (node as Node3D).transform
	if node is CollisionShape3D:
		var owner_shape := node as CollisionShape3D
		if owner_shape.shape != null and not owner_shape.disabled:
			var basis := xform.basis
			var scale := basis.get_scale()
			var ortho := basis.orthonormalized()
			var shape := owner_shape.shape
			if shape is BoxShape3D:
				out.append(_entry(Kind.BOX, (shape as BoxShape3D).size * scale, xform.origin, ortho))
			elif shape is CylinderShape3D:
				var cylinder := shape as CylinderShape3D
				out.append(_entry(Kind.CYLINDER, Vector3(cylinder.radius * maxf(scale.x, scale.z),
					cylinder.height * scale.y, 0.0), xform.origin, ortho))
			elif shape is CapsuleShape3D:
				var capsule := shape as CapsuleShape3D
				out.append(_entry(Kind.CAPSULE, Vector3(capsule.radius * maxf(scale.x, scale.z),
					capsule.height * scale.y, 0.0), xform.origin, ortho))
			elif shape is SphereShape3D:
				var r: float = (shape as SphereShape3D).radius * maxf(scale.x, maxf(scale.y, scale.z))
				out.append(_entry(Kind.SPHERE, Vector3(r, r, r), xform.origin, ortho))
			else:
				# Выпуклые и полигональные фигуры: коробка по их габаритам.
				var debug := shape.get_debug_mesh()
				if debug != null:
					var box: AABB = debug.get_aabb()
					out.append(_entry(Kind.BOX, box.size * scale, xform * box.get_center(), ortho))
	for child in node.get_children():
		_collect_shapes(child, xform, out)


static func _collect_parts(node: Node, parent: Transform3D, out: Array) -> void:
	if node == null or node is CollisionObject3D:
		return
	var xform := parent
	if node is Node3D:
		xform = parent * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null and (node as MeshInstance3D).visible:
		var mesh_inst := node as MeshInstance3D
		var mesh: Mesh = mesh_inst.mesh
		# Материалы экземпляра (override) переносим в копию меша: обломок
		# выглядит так же, как стоял.
		var has_override := false
		for s in range(mesh.get_surface_count()):
			if mesh_inst.get_surface_override_material(s) != null:
				has_override = true
		if (has_override or mesh_inst.material_override != null) and mesh is ArrayMesh:
			mesh = (mesh as ArrayMesh).duplicate()
			for s in range(mesh.get_surface_count()):
				var material: Material = mesh_inst.material_override
				if material == null:
					material = mesh_inst.get_surface_override_material(s)
				if material != null:
					mesh.surface_set_material(s, material)
		elif has_override or mesh_inst.material_override != null:
			# PrimitiveMesh хранит один материал.
			var material2: Material = mesh_inst.material_override
			if material2 == null:
				material2 = mesh_inst.get_surface_override_material(0)
			if mesh is PrimitiveMesh and material2 != null:
				mesh = (mesh as PrimitiveMesh).duplicate()
				(mesh as PrimitiveMesh).material = material2
		out.append({"mesh": mesh, "xform": xform, "aabb": mesh.get_aabb()})
	for child in node.get_children():
		_collect_parts(child, xform, out)
