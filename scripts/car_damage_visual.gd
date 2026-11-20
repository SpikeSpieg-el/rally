## Визуальные повреждения кузова: вмятины и заломы от ударов.
##
## Чисто косметический слой. При столкновении панель кузова получает локальную
## вмятину: вершины в радиусе удара вдавливаются внутрь, край слегка вспучивается,
## а сверху добавляется случайное «жевание» металла — аркаднее и читаемее, чем
## честная симуляция мягких тел в духе BeamNG. Удары накапливаются: каждая новая
## вмятина деформирует уже погнутый металл.
##
## Компонент НЕ трогает здоровье, урон, счёт и физику — только геометрию мешей.
## Он ничего не знает о конкретной машине: родитель решает, кому его ставить
## (сейчас — только Lancer, система сдаётся на пробу).
##
## Деформируются панели из группы rally_body_fx: это внешние кузовные меши.
## Интерьер, каркас безопасности, колёса и стёкла салона не помечены группой и
## остаются целыми, как и раньше.
class_name CarDamageVisual
extends Node

## Насколько близко к панели должен прийтись удар, чтобы её вообще рассматривать.
## Дешёвый отсев по расширенной AABB, чтобы не перебирать вершины всех панелей.
const SURFACE_PADDING := 0.7

## Смещения меньше этой величины (м) считаем отсутствующими: ни вмятины, ни
## пересчёта нормалей, ни попадания в статистику.
const EPSILON_M := 0.002

## Общий запас глубины вмятин на кузов, метры. Дальше металл «исчерпан» и новые
## удары его уже не меняют — защита от превращения машины в бесформенную кашу.
var dent_budget_m := 1.1

## Общая громкость деформации: 1.0 — подобрано под аркадный вид, 0.0 — выключено.
var dent_scale := 1.0

var enabled := true

var _space: Node3D = null
var _panels: Array[Dictionary] = []
var _total_dent_m := 0.0
var _impact_count := 0


## Собрать деформируемые панели кузова.
## model — корень визуальной модели (body_model_path машины),
## space — узел, в чьих локальных координатах приходят точки удара (машина).
## Повторный вызов пересобирает панели с нуля (например, после смены модели).
func setup(model: Node3D, space: Node3D = null) -> void:
	_clear_panels()
	_total_dent_m = 0.0
	_impact_count = 0
	_space = space if space != null else get_parent() as Node3D
	if model == null or _space == null:
		return
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := node as MeshInstance3D
		if mesh_inst == null or not mesh_inst.is_in_group("rally_body_fx"):
			continue
		var mesh := mesh_inst.mesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		_panels.append({
			"inst": mesh_inst,
			"aabb": mesh.get_aabb().grow(SURFACE_PADDING),
			"surfaces": _snapshot_surfaces(mesh),
		})


## Принять удар и помять кузов.
## point — точка контакта в локальных координатах машины (space),
## push_dir — куда вдавливается металл (от препятствия внутрь кузова),
## dv — потеря скорости в ударе, м/с: задаёт глубину и радиус вмятины.
func apply_impact(point: Vector3, push_dir: Vector3, dv: float) -> void:
	if not enabled or dent_scale <= 0.0 or _panels.is_empty() or dv <= 0.0:
		return
	if _total_dent_m >= dent_budget_m:
		return
	_impact_count += 1
	var budget_left := dent_budget_m - _total_dent_m
	# Глубина и радиус растут с силой удара, но упираются в остаток запаса кузова.
	var depth := minf(clampf(dv * 0.012, 0.02, 0.16) * dent_scale, budget_left)
	if depth <= EPSILON_M:
		return
	var radius := clampf(0.32 + dv * 0.024, 0.32, 0.62)
	var push := push_dir.normalized()
	if push == Vector3.ZERO:
		return
	var dented := _dent_at(point, push, radius, depth)
	if dented <= 0.0:
		# У низкополигональной панели вершины могут оказаться дальше радиуса
		# удара: пробуем один раз шире, иначе лёгкое касание не оставит следа.
		dented = _dent_at(point, push, radius * 2.0, depth)
	if dented > 0.0:
		_total_dent_m += dented


## Помять все панели в окрестности удара; вернёт наибольшую глубину, метры.
func _dent_at(point: Vector3, push: Vector3, radius: float, depth: float) -> float:
	var dented := 0.0
	for panel in _panels:
		dented = maxf(dented, _dent_panel(panel, point, push, radius, depth))
	return dented


## Вернуть кузов к исходной геометрии (используется в тестах и при «ремонте»).
func clear_damage() -> void:
	for panel in _panels:
		for surf in panel["surfaces"]:
			var arrays: Array = surf["arrays"]
			var orig: PackedVector3Array = surf["orig_vertices"]
			arrays[Mesh.ARRAY_VERTEX] = orig.duplicate()
			arrays[Mesh.ARRAY_NORMAL] = surf["orig_normals"].duplicate()
		_rebuild(panel)
	_total_dent_m = 0.0
	_impact_count = 0


## Сколько суммарно вдавлено кузова, метры. Для HUD, отладки и тестов.
func total_dent_depth() -> float:
	return _total_dent_m


## Сколько ударов принято (в том числе не оставивших вмятин).
func impact_count() -> int:
	return _impact_count


## Сколько кузовных панелей деформируется.
func panel_count() -> int:
	return _panels.size()


## Сводка по фактической деформации: сколько вершин сдвинуто, где центр вмятин
## (в координатах машины) и насколько глубоко. Нужно тестам и отладке.
func deformation_stats() -> Dictionary:
	var moved := 0
	var centroid := Vector3.ZERO
	var max_offset := 0.0
	for panel in _panels:
		var inst := panel["inst"] as MeshInstance3D
		if inst == null or not is_instance_valid(inst):
			continue
		var mesh_from_space := _space_from_mesh(inst)
		for surf in panel["surfaces"]:
			var arrays: Array = surf["arrays"]
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var orig: PackedVector3Array = surf["orig_vertices"]
			for i in range(mini(verts.size(), orig.size())):
				var delta_local: Vector3 = verts[i] - orig[i]
				if delta_local.length_squared() < EPSILON_M * EPSILON_M:
					continue
				var delta_space: Vector3 = mesh_from_space.basis * delta_local
				moved += 1
				centroid += mesh_from_space * verts[i]
				max_offset = maxf(max_offset, delta_space.length())
	if moved > 0:
		centroid /= float(moved)
	return {
		"moved_vertices": moved,
		"centroid_local": centroid,
		"max_offset_m": max_offset,
		"panels": _panels.size(),
	}


## Исходные наборы атрибутов каждой поверхности панели.
## Массивы берутся целиком (surface_get_arrays), чтобы не потерять цвета вершин,
## второй UV-канал и прочее, что импорт вложил в меш.
func _snapshot_surfaces(mesh: Mesh) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		out.append({
			"primitive": mesh.surface_get_primitive_type(s),
			"material": mesh.surface_get_material(s),
			"arrays": arrays,
			"orig_vertices": verts.duplicate(),
			"orig_normals": normals.duplicate(),
		})
	return out


## Переход из системы меша в систему машины.
## Считается по глобальным трансформам в момент удара, поэтому не портится, если
## модель двигали, масштабировали или подменяли после setup().
func _space_from_mesh(mesh_inst: MeshInstance3D) -> Transform3D:
	if _space == null or not is_instance_valid(_space):
		return Transform3D.IDENTITY
	if not mesh_inst.is_inside_tree() or not _space.is_inside_tree():
		return Transform3D.IDENTITY
	return _space.global_transform.affine_inverse() * mesh_inst.global_transform


## Вмять одну панель; вернёт фактическую глубину деформации (0.0 — не задета).
func _dent_panel(panel: Dictionary, point_space: Vector3, push_space: Vector3, radius: float, depth: float) -> float:
	var inst := panel["inst"] as MeshInstance3D
	if inst == null or not is_instance_valid(inst):
		return 0.0
	var mesh_from_space := _space_from_mesh(inst)
	var space_from_mesh := mesh_from_space.affine_inverse()
	var point_local: Vector3 = space_from_mesh * point_space
	var aabb: AABB = panel["aabb"]
	if not aabb.has_point(point_local):
		return 0.0
	# Масштаб модели: радиус и глубина заданы в метрах машины, а вершины живут
	# в единицах меша — приводим их друг к другу.
	var scale_local := _average_scale(space_from_mesh.basis)
	if scale_local <= 0.0001:
		return 0.0
	var radius_local := radius / scale_local
	var depth_local := depth / scale_local
	var push_local: Vector3 = (space_from_mesh.basis * push_space).normalized()
	if push_local == Vector3.ZERO:
		return 0.0
	var dented := 0.0
	for surf in panel["surfaces"]:
		var arrays: Array = surf["arrays"]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			continue
		var moved := PackedByteArray()
		moved.resize(verts.size())
		var r2 := radius_local * radius_local
		var deepest := 0.0
		for i in range(verts.size()):
			var v: Vector3 = verts[i]
			var offset: Vector3 = v - point_local
			var dist2 := offset.length_squared()
			if dist2 > r2:
				continue
			var t := sqrt(dist2) / radius_local
			# Профиль вмятины: глубокая воронка в центре и вспученный край, как
			# на настоящем погнутом листе. На самой кромке оба слагаемых нулевые —
			# переход к нетронутому металлу плавный, без ступеньки.
			var bowl := 1.0 - t
			bowl *= bowl
			var rim_t := clampf((t - 0.55) / 0.45, 0.0, 1.0)
			var rim := sin(PI * rim_t)
			var disp := depth_local * (bowl - 0.30 * rim)
			if absf(disp) * scale_local < EPSILON_M:
				continue
			# Случайное жевание: складки поперёк направления удара сильнее,
			# вдоль — слабее, плюс мелкий шум. Это и есть «аркадность».
			var crumple := _rand_unit() * (absf(disp) * 0.38)
			crumple -= push_local * crumple.dot(push_local)
			var jitter := _rand_unit() * (depth_local * 0.10)
			verts[i] = v + push_local * disp + crumple + jitter
			moved[i] = 1
			deepest = maxf(deepest, absf(disp))
		if deepest <= 0.0:
			continue
		arrays[Mesh.ARRAY_VERTEX] = verts
		_refresh_normals(arrays, moved)
		dented = maxf(dented, deepest * scale_local)
	if dented > 0.0:
		_rebuild(panel)
	return dented


## Пересчитать нормали только у тех треугольников, которые поехали: иначе
## плоская low-poly раскраска кузова превратилась бы в гладкую после первого удара.
func _refresh_normals(arrays: Array, moved: PackedByteArray) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if normals.size() != verts.size():
		return
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var accum := PackedVector3Array()
	accum.resize(verts.size())
	accum.fill(Vector3.ZERO)
	var touched := PackedByteArray()
	touched.resize(verts.size())
	if indices.size() >= 3:
		for t in range(0, indices.size() - 2, 3):
			var a := indices[t]
			var b := indices[t + 1]
			var c := indices[t + 2]
			if moved[a] == 0 and moved[b] == 0 and moved[c] == 0:
				continue
			var face := (verts[b] - verts[a]).cross(verts[c] - verts[a])
			accum[a] += face
			accum[b] += face
			accum[c] += face
			touched[a] = 1
			touched[b] = 1
			touched[c] = 1
	else:
		# Неиндексированная геометрия: у каждого треугольника свои вершины,
		# нормаль общая на все три.
		for t in range(0, verts.size() - 2, 3):
			if moved[t] == 0 and moved[t + 1] == 0 and moved[t + 2] == 0:
				continue
			var face := (verts[t + 1] - verts[t]).cross(verts[t + 2] - verts[t])
			accum[t] += face
			accum[t + 1] += face
			accum[t + 2] += face
			touched[t] = 1
			touched[t + 1] = 1
			touched[t + 2] = 1
	for i in range(verts.size()):
		if touched[i] == 0:
			continue
		var n: Vector3 = accum[i]
		if n == Vector3.ZERO:
			continue
		n = n.normalized()
		# Знак берём от исходной нормали: намотка треугольников в импорте может
		# быть любой, а вывернутые наизнанку нормали дали бы чёрные пятна.
		if n.dot(normals[i]) < 0.0:
			n = -n
		normals[i] = n
	arrays[Mesh.ARRAY_NORMAL] = normals


## Пересобрать меш панели из текущих (уже деформированных) массивов.
## Материалы поверхностей переносятся один в один, а перекраска кузова живёт в
## override-материалах самого MeshInstance3D и от замены меша не страдает.
func _rebuild(panel: Dictionary) -> void:
	var inst := panel["inst"] as MeshInstance3D
	if inst == null or not is_instance_valid(inst):
		return
	var new_mesh := ArrayMesh.new()
	for surf in panel["surfaces"]:
		new_mesh.add_surface_from_arrays(surf["primitive"], surf["arrays"])
		if surf["material"] != null:
			new_mesh.surface_set_material(new_mesh.get_surface_count() - 1, surf["material"])
	inst.mesh = new_mesh


func _average_scale(basis: Basis) -> float:
	var sx := basis.x.length()
	var sy := basis.y.length()
	var sz := basis.z.length()
	if sx <= 0.0 or sy <= 0.0 or sz <= 0.0:
		return 0.0
	return (sx + sy + sz) / 3.0


func _rand_unit() -> Vector3:
	var v := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	return v.normalized() if v != Vector3.ZERO else Vector3.UP


func _clear_panels() -> void:
	_panels.clear()
