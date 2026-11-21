## Повреждения кузова: вмятины, смятие «гармошкой» и следы на краске.
##
## Чисто косметический слой, одинаковый для любой машины: он берёт меши
## модели из группы rally_body_fx и ничего не знает о конкретной марке.
##
## Как мнётся металл (и почему треугольники больше не «косит»):
##
## 1. Перед первым ударом длинные рёбра кузова делятся пополам
##    (scripts/car_mesh_subdivider.gd). Низкополигональная дверь из двух
##    треугольников превращается в сетку, которую можно плавно прогнуть, а
##    внешне машина не меняется — новые вершины лежат на старых гранях.
## 2. Вмятина — это гладкое поле смещений в системе машины: смещение точки
##    зависит только от её положения, а не от индекса вершины или панели.
##    Поэтому совпадающие вершины соседних треугольников, швов UV и даже
##    разных панелей едут одинаково — щелей и рваных краёв нет.
## 3. Поле плавное (без случайного дрожания каждой вершины), с ограничением
##    глубины относительно радиуса — треугольники не выворачиваются.
## 4. Нормали не пересчитываются заново, а поворачиваются вслед за гранями:
##    гладкие места остаются гладкими, жёсткие рёбра — жёсткими.
##
## Удары накапливаются, суммарная глубина ограничена запасом на кузов, а
## смещение каждой вершины — пределом, чтобы силуэт не проваливался в салон.
##
## Следы (царапины, сколы, копоть) рисует overlay-слой кузова: тот же проход,
## что и грязь (shaders/car_dirt.gdshader), либо собственный слой
## shaders/car_damage_marks.gdshader, если грязи на машине нет.
##
## Компонент НЕ трогает здоровье, урон, счёт и физику — только геометрию мешей
## и параметры overlay-слоя. Все числа — в RallyDamageVisualConfig
## (data/car/default_damage_visual.tres).
class_name CarDamageVisual
extends Node

const Subdivider = preload("res://scripts/car_mesh_subdivider.gd")
const MarksShader = preload("res://shaders/car_damage_marks.gdshader")

## Смещения меньше этой величины (м) считаем отсутствующими.
const EPSILON_M := 0.002
## Столько следов умеет показать шейдер (размер массивов в car_damage_marks).
const MARK_SLOTS := 16
## Пауза, после которой царапина вдоль забора считается законченной, с.
const SCRAPE_CONTINUE_SEC := 0.35
## Самая длинная царапина одним следом, м: дальше начинается новая.
const SCRAPE_MAX_LENGTH_M := 3.5
## Повторный удар ближе этой доли радиуса к старому следу усиливает его,
## а не занимает новый слот.
const MARK_MERGE_RATIO := 0.45

## Удар принят и помял кузов: точка (система машины) и глубина, м.
signal dented(point: Vector3, depth_m: float)

## Настройка: пороги, форма, сетка, следы. Подставляется родителем; без неё
## берутся значения по умолчанию того же класса.
var config: RallyDamageVisualConfig = null

var _space: Node3D = null
var _panels: Array[Dictionary] = []
var _followers: Array[Dictionary] = []
var _total_dent_m := 0.0
var _impact_count := 0
var _bounds := AABB()
var _body_center := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _last_impact: Dictionary = {}

var _mark_pos := PackedVector3Array()
var _mark_axis := PackedVector4Array()
var _mark_normal := PackedVector4Array()
var _mark_data := PackedVector4Array()
var _next_mark := 0
var _marks_dirty := false
var _scrape_slot := -1
var _scrape_start := Vector3.ZERO
var _scrape_snap := Vector3.ZERO
var _scrape_axis := Vector3.ZERO
var _scrape_idle := 1000.0
var _own_marks_material: ShaderMaterial = null
var _synced_materials: Dictionary = {}
var _shader_support: Dictionary = {}


func _init() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 2
	_reset_marks()


## Собрать деформируемые панели кузова.
## model — корень визуальной модели (body_model_path машины),
## space — узел, в чьих координатах приходят точки удара (машина),
## settings — настройка (null — значения по умолчанию).
## Повторный вызов пересобирает панели с нуля (например, после смены модели).
func setup(model: Node3D, space: Node3D = null, settings: RallyDamageVisualConfig = null) -> void:
	_restore_followers()
	_panels.clear()
	_followers.clear()
	_synced_materials.clear()
	_total_dent_m = 0.0
	_impact_count = 0
	_last_impact = {}
	config = settings
	_space = space if space != null else get_parent() as Node3D
	_rng.randomize()
	_reset_marks()
	if model == null or _space == null:
		return
	var tuning := cfg()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := node as MeshInstance3D
		if mesh_inst == null or not mesh_inst.is_in_group("rally_body_fx"):
			continue
		if mesh_inst.mesh == null or mesh_inst.mesh.get_surface_count() == 0:
			continue
		var panel := _make_panel(mesh_inst, tuning)
		if not panel.is_empty():
			_panels.append(panel)
	_compute_bounds()
	if tuning.follow_attached_parts:
		_collect_followers(model)


## Настройка — никогда не null.
func cfg() -> RallyDamageVisualConfig:
	if config == null:
		config = RallyDamageVisualConfig.new()
	return config


## Принять удар и помять кузов. Вернёт глубину вмятины, м (0 — геометрия не
## изменилась; след на краске при этом всё равно может появиться).
## point — точка контакта в координатах машины (space),
## push_dir — куда вдавливается металл (от препятствия внутрь кузова),
## dv — потеря скорости в ударе, м/с: задаёт глубину, радиус и силу следа,
## slide_dir — куда машина скользила вдоль препятствия (для штрихов царапин).
func apply_impact(point: Vector3, push_dir: Vector3, dv: float, slide_dir: Vector3 = Vector3.ZERO) -> float:
	var tuning := cfg()
	if not tuning.enabled or _panels.is_empty() or dv <= 0.0:
		return 0.0
	var push := push_dir.normalized()
	if push == Vector3.ZERO:
		return 0.0
	_impact_count += 1
	var radius := clampf(tuning.radius_base_m + dv * tuning.radius_per_dv_m,
		tuning.radius_base_m, maxf(tuning.radius_max_m, tuning.radius_base_m))
	var surface := _find_surface(point, push, radius, tuning.surface_search_m)
	if not bool(surface["found"]):
		return 0.0
	var center: Vector3 = surface["point"]
	var dented_m := 0.0
	if tuning.dent_scale > 0.0 and _total_dent_m < tuning.dent_budget_m:
		var depth := clampf(dv * tuning.depth_per_dv_m, tuning.depth_min_m,
			maxf(tuning.depth_max_m, tuning.depth_min_m)) * tuning.dent_scale
		depth = minf(depth, radius * tuning.max_strain)
		depth = minf(depth, tuning.dent_budget_m - _total_dent_m)
		if depth > EPSILON_M:
			dented_m = _deform(center, push, radius, depth, tuning)
			_total_dent_m += dented_m
	if tuning.marks_enabled:
		var strength := clampf(dv * tuning.mark_strength_per_dv, tuning.mark_strength_min, 1.0)
		var soot := tuning.mark_soot * clampf((dv - tuning.min_dv_mps) / 14.0, 0.0, 1.0)
		var slide := slide_dir - push * slide_dir.dot(push)
		var stretch := 1.0 + clampf(slide.length() / 12.0, 0.0, 1.5)
		_add_impact_mark(center + push * dented_m * 0.6, push, slide,
			strength, radius * tuning.mark_radius_scale, soot, stretch)
	_last_impact = {"point": center, "push": push, "radius": radius, "depth": dented_m, "dv": dv}
	if dented_m > 0.0:
		dented.emit(center, dented_m)
	return dented_m


## Царапина при скольжении вдоль забора: зовётся каждый кадр контакта.
## point, push_dir и slide_dir — в координатах машины, intensity — 0..1.
## Пока скольжение продолжается, след тянется за точкой контакта.
func add_scrape(point: Vector3, push_dir: Vector3, slide_dir: Vector3, intensity: float, delta: float) -> void:
	var tuning := cfg()
	if not tuning.enabled or not tuning.marks_enabled or _panels.is_empty():
		return
	var push := push_dir.normalized()
	if push == Vector3.ZERO:
		return
	var axis := slide_dir - push * slide_dir.dot(push)
	if axis.length_squared() < 1e-6:
		return
	axis = axis.normalized()
	var growth := tuning.scrape_growth_per_sec * clampf(intensity, 0.0, 1.0) * maxf(delta, 0.0)
	var radius := tuning.scrape_radius_m
	if _scrape_slot >= 0 and _scrape_idle < SCRAPE_CONTINUE_SEC and axis.dot(_scrape_axis) > 0.3:
		var here := point + _scrape_snap
		var span := here - _scrape_start
		span -= push * span.dot(push)
		var length := span.length()
		if length <= SCRAPE_MAX_LENGTH_M:
			var dir := span / length if length > 0.05 else axis
			var stretch := maxf(1.0, (length * 0.5 + radius) / radius)
			_mark_pos[_scrape_slot] = (_scrape_start + here) * 0.5
			_mark_axis[_scrape_slot] = Vector4(dir.x, dir.y, dir.z, stretch)
			var data := _mark_data[_scrape_slot]
			data.x = minf(1.0, data.x + growth)
			_mark_data[_scrape_slot] = data
			_scrape_idle = 0.0
			_marks_dirty = true
			return
	# Новая царапина: один раз ищем настоящую поверхность кузова под точкой
	# контакта (коллизия — выпуклая оболочка) и дальше переносим ту же поправку.
	var surface := _find_surface(point, push, radius * 2.0, tuning.surface_search_m)
	_scrape_snap = (Vector3(surface["point"]) - point) if bool(surface["found"]) else Vector3.ZERO
	_scrape_start = point + _scrape_snap
	_scrape_axis = axis
	_scrape_slot = _add_mark(_scrape_start, push, axis, maxf(growth, 0.18), radius, 1.0, 0.0, 1.0)
	_scrape_idle = 0.0


## Вернуть кузов к исходной геометрии и стереть следы («ремонт», тесты).
func clear_damage() -> void:
	for panel in _panels:
		for surf in panel["surfaces"]:
			var arrays: Array = surf["arrays"]
			var orig_vertices: PackedVector3Array = surf["orig_vertices"]
			var orig_normals: PackedVector3Array = surf["orig_normals"]
			var orig_tangents: PackedFloat32Array = surf["orig_tangents"]
			var rest: PackedVector3Array = surf["rest"]
			arrays[Mesh.ARRAY_VERTEX] = orig_vertices.duplicate()
			if surf["has_normals"]:
				arrays[Mesh.ARRAY_NORMAL] = orig_normals.duplicate()
			if surf["has_tangents"]:
				arrays[Mesh.ARRAY_TANGENT] = orig_tangents.duplicate()
			var offsets := PackedVector3Array()
			offsets.resize(rest.size())
			offsets.fill(Vector3.ZERO)
			surf["offsets"] = offsets
		_rebuild(panel)
	_restore_followers()
	_total_dent_m = 0.0
	_impact_count = 0
	_last_impact = {}
	clear_marks()


## Стереть только следы на краске.
func clear_marks() -> void:
	_reset_marks()
	_marks_dirty = true
	_sync_mark_materials(true)


## Сколько суммарно вдавлено кузова, метры. Для HUD, отладки и тестов.
func total_dent_depth() -> float:
	return _total_dent_m


## Сколько ударов принято (в том числе не оставивших вмятин).
func impact_count() -> int:
	return _impact_count


## Сколько кузовных панелей деформируется.
func panel_count() -> int:
	return _panels.size()


## Сколько вершин во всех панелях (после сгущения сетки).
func vertex_count() -> int:
	var total := 0
	for panel in _panels:
		for surf in panel["surfaces"]:
			var rest: PackedVector3Array = surf["rest"]
			total += rest.size()
	return total


## Сколько следов сейчас видно на кузове.
func mark_count() -> int:
	var count := 0
	for data in _mark_data:
		if data.x >= 0.01:
			count += 1
	return count


## Габариты кузова в координатах машины (до ударов).
func body_bounds() -> AABB:
	return _bounds


## Последний принятый удар: point, push, radius, depth, dv (пусто — ударов не было).
func last_impact() -> Dictionary:
	return _last_impact


## Сводка по фактической деформации: сколько вершин сдвинуто, где центр вмятин
## (в координатах машины) и насколько глубоко. Нужно тестам и отладке.
func deformation_stats() -> Dictionary:
	var moved := 0
	var centroid := Vector3.ZERO
	var max_offset := 0.0
	for panel in _panels:
		for surf in panel["surfaces"]:
			var rest: PackedVector3Array = surf["rest"]
			var offsets: PackedVector3Array = surf["offsets"]
			for i in range(mini(rest.size(), offsets.size())):
				var length := offsets[i].length()
				if length < EPSILON_M:
					continue
				moved += 1
				centroid += rest[i] + offsets[i]
				max_offset = maxf(max_offset, length)
	if moved > 0:
		centroid /= float(moved)
	return {
		"moved_vertices": moved,
		"centroid_local": centroid,
		"max_offset_m": max_offset,
		"panels": _panels.size(),
		"vertices": vertex_count(),
		"marks": mark_count(),
	}


## Качество сетки после вмятин — доказательство, что треугольники не «косит»:
## triangles — всего треугольников, flipped — сколько вывернуто наизнанку
## (нормаль грани повернулась больше чем на 90°), max_stretch — во сколько раз
## удлинилось самое растянутое ребро, seam_gap_m — наибольший разрыв между
## вершинами, которые до ударов совпадали (швы UV, жёсткие рёбра, стыки панелей).
func triangle_stats() -> Dictionary:
	var triangles := 0
	var flipped := 0
	var max_stretch := 1.0
	var seams: Dictionary = {}
	var seam_gap := 0.0
	for panel in _panels:
		for surf in panel["surfaces"]:
			var rest: PackedVector3Array = surf["rest"]
			var offsets: PackedVector3Array = surf["offsets"]
			for i in range(rest.size()):
				var key := Vector3i((rest[i] * 2000.0).round())
				var now := rest[i] + offsets[i]
				if seams.has(key):
					var first: Vector3 = seams[key]
					seam_gap = maxf(seam_gap, first.distance_to(now))
				else:
					seams[key] = now
			if not surf["triangles"]:
				continue
			var indices: PackedInt32Array = surf["indices"]
			for t in range(indices.size() / 3):
				var a := indices[t * 3]
				var b := indices[t * 3 + 1]
				var c := indices[t * 3 + 2]
				var before := (rest[b] - rest[a]).cross(rest[c] - rest[a])
				if before.length_squared() < 1e-12:
					continue
				triangles += 1
				var pa := rest[a] + offsets[a]
				var pb := rest[b] + offsets[b]
				var pc := rest[c] + offsets[c]
				if offsets[a] == Vector3.ZERO and offsets[b] == Vector3.ZERO and offsets[c] == Vector3.ZERO:
					continue
				var after := (pb - pa).cross(pc - pa)
				if after.dot(before) <= 0.0:
					flipped += 1
				max_stretch = maxf(max_stretch, _stretch(rest[a], rest[b], pa, pb))
				max_stretch = maxf(max_stretch, _stretch(rest[b], rest[c], pb, pc))
				max_stretch = maxf(max_stretch, _stretch(rest[c], rest[a], pc, pa))
	return {
		"triangles": triangles,
		"flipped": flipped,
		"max_stretch": max_stretch,
		"seam_gap_m": seam_gap,
	}


func _stretch(rest_a: Vector3, rest_b: Vector3, now_a: Vector3, now_b: Vector3) -> float:
	var rest_len := rest_a.distance_to(rest_b)
	return now_a.distance_to(now_b) / rest_len if rest_len > 1e-4 else 1.0


func _process(delta: float) -> void:
	_scrape_idle += delta
	if _own_marks_material != null and _space != null and is_instance_valid(_space) and _space.is_inside_tree():
		_own_marks_material.set_shader_parameter("world_to_car", _space.global_transform.affine_inverse())
	_sync_mark_materials(false)


# ── Панели ──────────────────────────────────────────────────────────────────

func _make_panel(mesh_inst: MeshInstance3D, tuning: RallyDamageVisualConfig) -> Dictionary:
	var mesh := mesh_inst.mesh
	var to_space := _to_space(mesh_inst)
	var scale_local := _average_scale(to_space.basis)
	if scale_local <= 0.0001:
		return {}
	var edge_local := tuning.subdivide_max_edge_m / scale_local if tuning.subdivide_enabled else 0.0
	var passes := tuning.subdivide_max_passes if tuning.subdivide_enabled else 0
	var surfaces: Array[Dictionary] = []
	var subdivided := false
	for s in range(mesh.get_surface_count()):
		var prepared: Dictionary
		if mesh.surface_get_primitive_type(s) == Mesh.PRIMITIVE_TRIANGLES:
			prepared = Subdivider.prepared_surface(mesh, s, edge_local, passes, tuning.subdivide_vertex_limit)
		else:
			# Линии и точки не делятся и не мнутся гранями — только сдвигаются.
			prepared = {
				"arrays": mesh.surface_get_arrays(s),
				"adj_offsets": PackedInt32Array(),
				"adj_tris": PackedInt32Array(),
				"subdivided": false,
			}
		var arrays: Array = prepared["arrays"]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals := PackedVector3Array()
		if arrays[Mesh.ARRAY_NORMAL] != null:
			normals = arrays[Mesh.ARRAY_NORMAL]
		var tangents := PackedFloat32Array()
		if arrays[Mesh.ARRAY_TANGENT] != null:
			tangents = arrays[Mesh.ARRAY_TANGENT]
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		var rest := PackedVector3Array()
		rest.resize(verts.size())
		for i in range(verts.size()):
			rest[i] = to_space * verts[i]
		var offsets := PackedVector3Array()
		offsets.resize(verts.size())
		offsets.fill(Vector3.ZERO)
		var triangles: bool = mesh.surface_get_primitive_type(s) == Mesh.PRIMITIVE_TRIANGLES \
			and indices.size() >= 3
		surfaces.append({
			"primitive": mesh.surface_get_primitive_type(s),
			"material": mesh.surface_get_material(s),
			"arrays": arrays,
			"orig_vertices": verts.duplicate(),
			"orig_normals": normals.duplicate(),
			"orig_tangents": tangents.duplicate(),
			"has_normals": normals.size() == verts.size() and not verts.is_empty(),
			"has_tangents": tangents.size() == verts.size() * 4 and not verts.is_empty(),
			"indices": indices,
			"triangles": triangles,
			"adj_offsets": prepared["adj_offsets"],
			"adj_tris": prepared["adj_tris"],
			"rest": rest,
			"offsets": offsets,
		})
		if bool(prepared["subdivided"]):
			subdivided = true
	var panel := {
		"inst": mesh_inst,
		"surfaces": surfaces,
		"to_space": to_space,
	}
	# Сгущённую сетку ставим сразу: первый удар не тратит время на деление,
	# а внешне кузов тот же — новые вершины лежат на старых гранях.
	if subdivided:
		_rebuild(panel)
	return panel


## Переход из системы меша в систему машины. Считается по цепочке родителей,
## поэтому работает и вне дерева сцены; если space не предок — по глобальным
## трансформам.
func _to_space(node: Node3D) -> Transform3D:
	if _space == null or not is_instance_valid(_space):
		return Transform3D.IDENTITY
	var result := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != null and cursor != _space:
		if cursor is Node3D:
			result = (cursor as Node3D).transform * result
		cursor = cursor.get_parent()
	if cursor == _space:
		return result
	if node.is_inside_tree() and _space.is_inside_tree():
		return _space.global_transform.affine_inverse() * node.global_transform
	return Transform3D.IDENTITY


## Модель могли сдвинуть или масштабировать после setup(): пересчитываем
## исходные положения в системе машины, смещения при этом сохраняются.
func _refresh_rest(panel: Dictionary) -> void:
	var inst := panel["inst"] as MeshInstance3D
	if inst == null or not is_instance_valid(inst):
		return
	var to_space := _to_space(inst)
	var old: Transform3D = panel["to_space"]
	if old.is_equal_approx(to_space):
		return
	panel["to_space"] = to_space
	for surf in panel["surfaces"]:
		var orig: PackedVector3Array = surf["orig_vertices"]
		var rest := PackedVector3Array()
		rest.resize(orig.size())
		for i in range(orig.size()):
			rest[i] = to_space * orig[i]
		surf["rest"] = rest


func _compute_bounds() -> void:
	var first := true
	_bounds = AABB()
	for panel in _panels:
		for surf in panel["surfaces"]:
			for p in surf["rest"]:
				if first:
					_bounds = AABB(p, Vector3.ZERO)
					first = false
				else:
					_bounds = _bounds.expand(p)
	_body_center = _bounds.get_center()


## Найти поверхность кузова под ударом: среди вершин рядом с линией удара —
## самую наружную. Коллизия машины — выпуклая оболочка, и точка контакта
## лежит не на краске; без этого вмятина приходилась бы в воздух.
func _find_surface(point: Vector3, push: Vector3, radius: float, search: float) -> Dictionary:
	var lateral_limit := maxf(radius * 0.6, 0.12)
	var lateral2 := lateral_limit * lateral_limit
	var reach2 := (search + radius) * (search + radius)
	var best_a := INF
	var best := Vector3.ZERO
	var found := false
	var nearest := Vector3.ZERO
	var nearest_d2 := INF
	for panel in _panels:
		_refresh_rest(panel)
		for surf in panel["surfaces"]:
			var rest: PackedVector3Array = surf["rest"]
			var offsets: PackedVector3Array = surf["offsets"]
			for i in range(rest.size()):
				var p := rest[i] + offsets[i]
				var d := p - point
				var d2 := d.length_squared()
				if d2 > reach2:
					continue
				if d2 < nearest_d2:
					nearest_d2 = d2
					nearest = p
				var a := d.dot(push)
				if a < -search or a > search:
					continue
				if (d - push * a).length_squared() > lateral2:
					continue
				if a < best_a:
					best_a = a
					best = p
					found = true
	if not found and nearest_d2 <= search * search:
		return {"found": true, "point": nearest}
	return {"found": found, "point": best}


## Помять все панели полем вмятины; вернёт наибольшую глубину, метры.
func _deform(center: Vector3, push: Vector3, radius: float, depth: float, tuning: RallyDamageVisualConfig) -> float:
	var shape := DentShape.new()
	shape.center = center
	shape.push = push
	shape.radius = radius
	shape.depth = depth
	shape.crush = maxf(radius * tuning.crush_depth_scale, 0.01)
	shape.rim_bulge = tuning.rim_bulge
	shape.rim_width = clampf(tuning.rim_width, 0.05, 0.8)
	shape.buckle = tuning.buckle_amount
	shape.wavelength = maxf(tuning.buckle_wavelength_m, 0.05)
	shape.phase = _rng.randf() * TAU
	shape.crumple = tuning.crumple_amount
	shape.body_center = _body_center
	_noise.seed = _rng.randi()
	_noise.frequency = 1.0 / maxf(tuning.crumple_scale_m, 0.02)
	shape.noise = _noise
	shape.prepare()
	var max_offset := tuning.max_vertex_offset_m
	var deepest := 0.0
	for panel in _panels:
		var inst := panel["inst"] as MeshInstance3D
		if inst == null or not is_instance_valid(inst):
			continue
		_refresh_rest(panel)
		var changed := false
		for surf in panel["surfaces"]:
			var rest: PackedVector3Array = surf["rest"]
			var offsets: PackedVector3Array = surf["offsets"]
			var moved := PackedInt32Array()
			for i in range(rest.size()):
				var current := rest[i] + offsets[i]
				if current.distance_squared_to(center) > shape.bound2:
					continue
				var off := shape.offset_at(current)
				if off.length_squared() < 1e-10:
					continue
				var total := offsets[i] + off
				var length := total.length()
				if length > max_offset:
					total *= max_offset / length
				offsets[i] = total
				moved.append(i)
				deepest = maxf(deepest, shape.last_push)
			if moved.is_empty():
				continue
			surf["offsets"] = offsets
			_apply_offsets(panel, surf, moved)
			changed = true
		if changed:
			_rebuild(panel)
	_move_followers(shape, max_offset)
	return deepest


## Перенести смещения (система машины) в вершины меша и повернуть нормали.
func _apply_offsets(panel: Dictionary, surf: Dictionary, moved: PackedInt32Array) -> void:
	var to_space: Transform3D = panel["to_space"]
	var from_space := to_space.basis.inverse()
	var arrays: Array = surf["arrays"]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var orig: PackedVector3Array = surf["orig_vertices"]
	var offsets: PackedVector3Array = surf["offsets"]
	for i in moved:
		verts[i] = orig[i] + from_space * offsets[i]
	arrays[Mesh.ARRAY_VERTEX] = verts
	if surf["triangles"] and surf["has_normals"]:
		_refresh_normals(surf, moved)


## Нормали поворачиваются вслед за гранями. Для каждой вершины берутся все
## касающиеся её треугольники, у каждого — поворот от исходной нормали грани к
## текущей; исходная нормаль вершины поворачивается их средним. Так сохраняется
## авторская раскраска: сглаженные места гладкие, жёсткие рёбра жёсткие, и
## никакая грань не меняет знак освещения на шве.
func _refresh_normals(surf: Dictionary, moved: PackedInt32Array) -> void:
	var arrays: Array = surf["arrays"]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var orig_normals: PackedVector3Array = surf["orig_normals"]
	var orig: PackedVector3Array = surf["orig_vertices"]
	var indices: PackedInt32Array = surf["indices"]
	var adj_offsets: PackedInt32Array = surf["adj_offsets"]
	var adj_tris: PackedInt32Array = surf["adj_tris"]
	if normals.size() != verts.size() or adj_offsets.size() != verts.size() + 1:
		return
	var rotations: Dictionary = {}
	var affected: Dictionary = {}
	for v in moved:
		for k in range(adj_offsets[v], adj_offsets[v + 1]):
			var t := adj_tris[k]
			if rotations.has(t):
				continue
			rotations[t] = _tri_rotation(t, indices, orig, verts)
			affected[indices[t * 3]] = true
			affected[indices[t * 3 + 1]] = true
			affected[indices[t * 3 + 2]] = true
	var has_tangents: bool = surf["has_tangents"]
	var tangents := PackedFloat32Array()
	var orig_tangents := PackedFloat32Array()
	if has_tangents:
		tangents = arrays[Mesh.ARRAY_TANGENT]
		orig_tangents = surf["orig_tangents"]
	for key in affected:
		var v: int = key
		var base: Vector3 = orig_normals[v]
		var sum := Vector3.ZERO
		for k in range(adj_offsets[v], adj_offsets[v + 1]):
			var t := adj_tris[k]
			if not rotations.has(t):
				rotations[t] = _tri_rotation(t, indices, orig, verts)
			var q: Quaternion = rotations[t]
			sum += q * base
		if sum.length_squared() < 1e-12:
			continue
		var n := sum.normalized()
		normals[v] = n
		if has_tangents and base.length_squared() > 1e-8:
			var turn := _arc(base.normalized(), n)
			var t0 := Vector3(orig_tangents[v * 4], orig_tangents[v * 4 + 1], orig_tangents[v * 4 + 2])
			var t1 := turn * t0
			tangents[v * 4] = t1.x
			tangents[v * 4 + 1] = t1.y
			tangents[v * 4 + 2] = t1.z
	arrays[Mesh.ARRAY_NORMAL] = normals
	if has_tangents:
		arrays[Mesh.ARRAY_TANGENT] = tangents


## Поворот исходной нормали треугольника к текущей.
func _tri_rotation(t: int, indices: PackedInt32Array, orig: PackedVector3Array, verts: PackedVector3Array) -> Quaternion:
	var a := indices[t * 3]
	var b := indices[t * 3 + 1]
	var c := indices[t * 3 + 2]
	var before := (orig[b] - orig[a]).cross(orig[c] - orig[a])
	var after := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	if before.length_squared() < 1e-14 or after.length_squared() < 1e-14:
		return Quaternion.IDENTITY
	return _arc(before.normalized(), after.normalized())


## Кратчайший поворот между единичными векторами; на развороте — без поворота
## (сложенный пополам треугольник не должен выворачивать соседей).
func _arc(from: Vector3, to: Vector3) -> Quaternion:
	if from.dot(to) < -0.995:
		return Quaternion.IDENTITY
	return Quaternion(from, to)


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


# ── Прикреплённые детали ────────────────────────────────────────────────────

## Мелкие детали, прикреплённые к панели (дочерние узлы меша кузова) или
## отмеченные группой rally_damage_follow, едут вместе со вмятиной целиком.
func _collect_followers(model: Node3D) -> void:
	var panel_nodes: Dictionary = {}
	for panel in _panels:
		panel_nodes[panel["inst"]] = true
	var picked: Array[Node3D] = []
	for panel in _panels:
		for child in (panel["inst"] as Node).get_children():
			var part := child as Node3D
			if part != null and not panel_nodes.has(part):
				picked.append(part)
	for node in model.find_children("*", "Node3D", true, false):
		if node.is_in_group("rally_damage_follow") and not panel_nodes.has(node) and not picked.has(node):
			picked.append(node as Node3D)
	for part in picked:
		var anchor := Vector3.ZERO
		var to_space := _to_space(part)
		var mesh_part := part as MeshInstance3D
		if mesh_part != null and mesh_part.mesh != null:
			anchor = to_space * mesh_part.mesh.get_aabb().get_center()
		else:
			anchor = to_space.origin
		_followers.append({
			"node": part,
			"rest_position": part.position,
			"anchor": anchor,
			"offset": Vector3.ZERO,
		})


func _move_followers(shape: DentShape, max_offset: float) -> void:
	for follower in _followers:
		var part := follower["node"] as Node3D
		if part == null or not is_instance_valid(part):
			continue
		var offset: Vector3 = follower["offset"]
		var anchor: Vector3 = follower["anchor"]
		var current := anchor + offset
		if current.distance_squared_to(shape.center) > shape.bound2:
			continue
		var off := shape.offset_at(current)
		if off.length_squared() < 1e-10:
			continue
		offset += off
		if offset.length() > max_offset:
			offset = offset.normalized() * max_offset
		follower["offset"] = offset
		var parent := part.get_parent() as Node3D
		var parent_basis := _to_space(parent).basis if parent != null else Basis.IDENTITY
		part.position = Vector3(follower["rest_position"]) + parent_basis.inverse() * offset


func _restore_followers() -> void:
	for follower in _followers:
		var part := follower["node"] as Node3D
		if part != null and is_instance_valid(part):
			part.position = follower["rest_position"]
		follower["offset"] = Vector3.ZERO


# ── Следы на краске ─────────────────────────────────────────────────────────

func _reset_marks() -> void:
	_mark_pos.resize(MARK_SLOTS)
	_mark_axis.resize(MARK_SLOTS)
	_mark_normal.resize(MARK_SLOTS)
	_mark_data.resize(MARK_SLOTS)
	_mark_pos.fill(Vector3.ZERO)
	_mark_axis.fill(Vector4(1.0, 0.0, 0.0, 1.0))
	_mark_normal.fill(Vector4(0.0, 0.0, -1.0, 0.0))
	_mark_data.fill(Vector4.ZERO)
	_next_mark = 0
	_scrape_slot = -1
	_scrape_idle = 1000.0


## След удара: рядом со старым — усиливает его, иначе занимает новый слот.
func _add_impact_mark(pos: Vector3, push: Vector3, slide: Vector3, strength: float, radius: float,
		soot: float, stretch: float) -> void:
	for i in range(MARK_SLOTS):
		var data := _mark_data[i]
		if data.x < 0.01 or _mark_normal[i].w > 0.5:
			continue
		if _mark_pos[i].distance_to(pos) > maxf(data.y, radius) * MARK_MERGE_RATIO:
			continue
		var old_normal := Vector3(_mark_normal[i].x, _mark_normal[i].y, _mark_normal[i].z)
		if old_normal.dot(push) < 0.5:
			continue
		data.x = minf(1.0, maxf(data.x, strength) + strength * 0.35)
		data.y = maxf(data.y, radius)
		data.w = maxf(data.w, soot)
		_mark_data[i] = data
		_marks_dirty = true
		return
	_add_mark(pos, push, slide, strength, radius, 0.0, soot, stretch)


func _add_mark(pos: Vector3, push: Vector3, axis: Vector3, strength: float, radius: float,
		kind: float, soot: float, stretch: float) -> int:
	var tuning := cfg()
	var slots := clampi(tuning.marks_max, 1, MARK_SLOTS)
	var index := _next_mark % slots
	_next_mark = (index + 1) % slots
	if index == _scrape_slot:
		_scrape_slot = -1
	var dir := axis
	if dir.length_squared() < 1e-6:
		dir = push.cross(Vector3.UP)
		if dir.length_squared() < 1e-6:
			dir = push.cross(Vector3.RIGHT)
	dir = dir.normalized()
	_mark_pos[index] = pos
	_mark_axis[index] = Vector4(dir.x, dir.y, dir.z, maxf(stretch, 1.0))
	_mark_normal[index] = Vector4(push.x, push.y, push.z, kind)
	_mark_data[index] = Vector4(clampf(strength, 0.0, 1.0), maxf(radius, 0.04),
		_rng.randf_range(1.0, 60.0), clampf(soot, 0.0, 1.0))
	_marks_dirty = true
	return index


## Раздать следы overlay-слоям панелей. Слой грязи (SurfaceEffects) может
## появиться или смениться после setup() — поэтому сверяемся каждый кадр.
func _sync_mark_materials(force: bool) -> void:
	var has_marks: bool = mark_count() > 0
	var tuning := cfg()
	for panel in _panels:
		var inst := panel["inst"] as MeshInstance3D
		if inst == null or not is_instance_valid(inst):
			continue
		var overlay := inst.material_overlay
		if overlay == null and has_marks and tuning.marks_enabled:
			inst.material_overlay = _own_material()
			overlay = inst.material_overlay
		var shader_mat := overlay as ShaderMaterial
		if shader_mat == null or not _supports_marks(shader_mat):
			continue
		var id := inst.get_instance_id()
		if force or _marks_dirty or _synced_materials.get(id) != shader_mat:
			_write_marks(shader_mat)
			_synced_materials[id] = shader_mat
	_marks_dirty = false


func _supports_marks(material: ShaderMaterial) -> bool:
	var shader := material.shader
	if shader == null:
		return false
	var id := shader.get_instance_id()
	if not _shader_support.has(id):
		_shader_support[id] = shader == MarksShader or shader.code.contains("damage_marks")
	return bool(_shader_support[id])


func _write_marks(material: ShaderMaterial) -> void:
	var tuning := cfg()
	material.set_shader_parameter("damage_mark_pos", _mark_pos)
	material.set_shader_parameter("damage_mark_axis", _mark_axis)
	material.set_shader_parameter("damage_mark_normal", _mark_normal)
	material.set_shader_parameter("damage_mark_data", _mark_data)
	material.set_shader_parameter("damage_primer_color", tuning.primer_color)
	material.set_shader_parameter("damage_metal_color", tuning.metal_color)
	material.set_shader_parameter("damage_soot_color", tuning.soot_color)
	material.set_shader_parameter("damage_metal_gloss", tuning.metal_gloss)
	material.set_shader_parameter("damage_scratch_frequency", tuning.scratch_frequency)
	material.set_shader_parameter("damage_marks_opacity", tuning.marks_opacity)


func _own_material() -> ShaderMaterial:
	if _own_marks_material == null:
		_own_marks_material = ShaderMaterial.new()
		_own_marks_material.shader = MarksShader
		var to_car := Transform3D.IDENTITY
		if _space != null and is_instance_valid(_space) and _space.is_inside_tree():
			to_car = _space.global_transform.affine_inverse()
		_own_marks_material.set_shader_parameter("world_to_car", to_car)
	return _own_marks_material


## Форма одной вмятины — гладкое поле смещений в системе машины.
##
## Смещение зависит только от положения точки: совпадающие вершины соседних
## треугольников (и разных панелей) получают одно и то же смещение, поэтому
## кузов не рвётся по швам. Профиль поперёк удара — гладкий купол
## (1 − s²)², без излома на краю; вглубь кузова смятие затухает на длине
## crush, поэтому удар в бампер сминает и край капота за ним.
class DentShape:
	var center := Vector3.ZERO
	var push := Vector3.BACK
	var radius := 0.4
	var depth := 0.1
	var crush := 0.5
	var rim_bulge := 0.0
	var rim_width := 0.3
	var buckle := 0.0
	var wavelength := 0.4
	var phase := 0.0
	var crumple := 0.0
	var body_center := Vector3.ZERO
	var noise: FastNoiseLite = null
	## Квадрат радиуса сферы, за которой поле заведомо ноль (быстрый отсев).
	var bound2 := 0.0
	## Вдавливание последней точки (без края и складок), м.
	var last_push := 0.0

	func prepare() -> void:
		var lateral := radius * (1.0 + rim_width)
		var along := maxf(crush, radius * 2.0)
		bound2 = lateral * lateral + along * along

	func offset_at(p: Vector3) -> Vector3:
		last_push = 0.0
		var d := p - center
		var a := d.dot(push)
		if a > crush or a < -radius * 2.0:
			return Vector3.ZERO
		var s := (d - push * a).length() / radius
		var outer := 1.0 + rim_width
		if s >= outer:
			return Vector3.ZERO
		# Вглубь кузова смятие затухает; всё, что торчит наружу перед точкой
		# удара (угол бампера), получает полную силу и плавно гаснет дальше
		# радиуса — без скачка, иначе на этой границе сетка порвалась бы.
		var wa := 1.0
		if a > 0.0:
			var u := a / crush
			wa = (1.0 - u) * (1.0 - u)
		elif a < -radius:
			wa = 1.0 - smoothstep(radius, radius * 2.0, -a)
		var wl := 0.0
		if s < 1.0:
			var q := 1.0 - s * s
			wl = q * q
		var w := wl * wa
		last_push = depth * w
		var off := push * last_push
		if rim_bulge > 0.0:
			var r0 := 1.0 - rim_width
			if s > r0:
				var r := (s - r0) / (2.0 * rim_width)
				var bump := sin(PI * r)
				off -= push * (depth * rim_bulge * bump * bump * wa)
		if w > 0.0:
			if buckle > 0.0:
				var outward := p - body_center
				outward -= push * outward.dot(push)
				if outward.length_squared() > 1e-8:
					off += outward.normalized() * (depth * buckle * w * sin(a * TAU / wavelength + phase))
			if crumple > 0.0 and noise != null:
				var wobble := Vector3(
					noise.get_noise_3dv(p),
					noise.get_noise_3dv(p + Vector3(17.3, 3.1, -5.7)),
					noise.get_noise_3dv(p + Vector3(-9.4, 29.1, 11.2)))
				off += wobble * (depth * crumple * w)
		return off
