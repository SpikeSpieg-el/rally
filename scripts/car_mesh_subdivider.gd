## Сгущение сетки кузова перед деформацией.
##
## Низкополигональная дверь или капот — это пара больших треугольников. Если
## мять такую панель, сдвигается одна-две вершины, и треугольники тянутся
## острыми перекошенными клиньями. Поэтому до первого удара длинные рёбра
## делятся пополам, пока все не станут короче заданной длины.
##
## Деление без «Т-стыков»: решение «делить ребро или нет» зависит только от
## положения двух его концов, поэтому оба треугольника по сторонам ребра
## делят его одинаково, а середина считается как (a + b) * 0.5 — от порядка
## концов результат не зависит даже в последнем бите. Значит, и вершины на
## швах UV/жёстких рёбер (разные индексы, одинаковые координаты) получают
## одинаковые середины, и после вмятины в кузове не появляется щелей.
##
## Новые вершины лежат строго на старых гранях, атрибуты (UV, UV2, цвет,
## нормаль, касательная) интерполируются — целая машина выглядит как раньше.
extends RefCounted

## Кэш по ресурсу меша: перезапуск заезда не делит сетку заново.
static var _cache: Dictionary = {}


## Готовая (возможно, сгущённая) поверхность меша со смежностью для нормалей.
## Возвращает словарь: arrays — массивы поверхности (свои копии для правки),
## adj_offsets/adj_tris — какие треугольники касаются вершины, subdivided —
## делилась ли сетка. Повторный вызов с теми же параметрами берёт кэш.
static func prepared_surface(mesh: Mesh, surface: int, max_edge: float, max_passes: int,
		vertex_limit: int) -> Dictionary:
	var key := "%d:%d:%.4f:%d:%d" % [mesh.get_instance_id(), surface, max_edge, max_passes, vertex_limit]
	if _cache.has(key):
		var cached: Dictionary = _cache[key]
		var ref: WeakRef = cached["ref"]
		if ref.get_ref() == mesh:
			return _copy_entry(cached)
		_cache.erase(key)
	var arrays := mesh.surface_get_arrays(surface)
	var subdivided := false
	if mesh.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES:
		var before: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		arrays = ensure_indexed(arrays)
		if max_edge > 0.0 and max_passes > 0:
			arrays = subdivide(arrays, max_edge, max_passes, vertex_limit)
		var after: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		subdivided = after.size() != before.size()
	var entry := {
		"ref": weakref(mesh),
		"arrays": arrays,
		"subdivided": subdivided,
	}
	_build_adjacency(entry)
	_cache[key] = entry
	return _copy_entry(entry)


static func _copy_entry(entry: Dictionary) -> Dictionary:
	# Упакованные массивы копируются при записи, но сам Array — ссылка:
	# дублируем его, чтобы правка вершин одной машины не попала в кэш.
	var arrays: Array = entry["arrays"]
	return {
		"arrays": arrays.duplicate(),
		"adj_offsets": entry["adj_offsets"],
		"adj_tris": entry["adj_tris"],
		"subdivided": entry["subdivided"],
	}


## Неиндексированная поверхность → индексированная (0, 1, 2, …), чтобы дальше
## работать с одним видом геометрии.
static func ensure_indexed(arrays: Array) -> Array:
	if arrays[Mesh.ARRAY_INDEX] != null:
		var existing: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if not existing.is_empty():
			return arrays
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices := PackedInt32Array()
	indices.resize(verts.size() - verts.size() % 3)
	for i in range(indices.size()):
		indices[i] = i
	var out := arrays.duplicate()
	out[Mesh.ARRAY_INDEX] = indices
	return out


## Делить рёбра длиннее max_edge, пока они есть (не больше max_passes проходов).
## Поверхности со скелетной анимацией или пользовательскими каналами не
## трогаются: их атрибуты нельзя честно интерполировать.
static func subdivide(arrays: Array, max_edge: float, max_passes: int, vertex_limit: int) -> Array:
	for skip in [Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_CUSTOM0,
			Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		if arrays[skip] != null:
			return arrays
	var builder := Builder.new(arrays)
	if not builder.valid:
		return arrays
	var max2 := max_edge * max_edge
	for pass_index in range(max_passes):
		# Лимит проверяется только между проходами: если оборвать проход на
		# середине, одна сторона ребра разделится, а другая нет — будет щель.
		if builder.verts.size() >= vertex_limit:
			break
		if not builder.split_pass(max2):
			break
	return builder.to_arrays(arrays)


## Для каждой вершины — список треугольников, которые её касаются (CSR).
static func _build_adjacency(entry: Dictionary) -> void:
	var arrays: Array = entry["arrays"]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	var count := verts.size()
	var offsets := PackedInt32Array()
	offsets.resize(count + 1)
	offsets.fill(0)
	var tri_count := indices.size() / 3
	for i in range(tri_count * 3):
		offsets[indices[i] + 1] += 1
	for v in range(count):
		offsets[v + 1] += offsets[v]
	var cursor := offsets.duplicate()
	var tris := PackedInt32Array()
	tris.resize(tri_count * 3)
	for t in range(tri_count):
		for k in range(3):
			var v := indices[t * 3 + k]
			tris[cursor[v]] = t
			cursor[v] += 1
	entry["adj_offsets"] = offsets
	entry["adj_tris"] = tris


## Рабочие копии атрибутов и сам алгоритм деления.
class Builder:
	var valid := false
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var indices := PackedInt32Array()
	var has_normals := false
	var has_tangents := false
	var has_colors := false
	var has_uv := false
	var has_uv2 := false
	var _edge_mid: Dictionary = {}

	func _init(arrays: Array) -> void:
		verts = arrays[Mesh.ARRAY_VERTEX]
		if verts.is_empty() or arrays[Mesh.ARRAY_INDEX] == null:
			return
		indices = arrays[Mesh.ARRAY_INDEX]
		var n := verts.size()
		if arrays[Mesh.ARRAY_NORMAL] != null:
			normals = arrays[Mesh.ARRAY_NORMAL]
			has_normals = normals.size() == n
		if arrays[Mesh.ARRAY_TANGENT] != null:
			tangents = arrays[Mesh.ARRAY_TANGENT]
			has_tangents = tangents.size() == n * 4
		if arrays[Mesh.ARRAY_COLOR] != null:
			colors = arrays[Mesh.ARRAY_COLOR]
			has_colors = colors.size() == n
		if arrays[Mesh.ARRAY_TEX_UV] != null:
			uv = arrays[Mesh.ARRAY_TEX_UV]
			has_uv = uv.size() == n
		if arrays[Mesh.ARRAY_TEX_UV2] != null:
			uv2 = arrays[Mesh.ARRAY_TEX_UV2]
			has_uv2 = uv2.size() == n
		valid = indices.size() >= 3

	## Середина ребра a–b: одна вершина на ребро в пределах поверхности.
	func _mid(a: int, b: int) -> int:
		var key: int = mini(a, b) * 4294967296 + maxi(a, b)
		if _edge_mid.has(key):
			return _edge_mid[key]
		var index := verts.size()
		verts.append((verts[a] + verts[b]) * 0.5)
		if has_normals:
			var n := normals[a] + normals[b]
			normals.append(n.normalized() if n.length_squared() > 1e-12 else normals[a])
		if has_tangents:
			var t := Vector3(
				tangents[a * 4] + tangents[b * 4],
				tangents[a * 4 + 1] + tangents[b * 4 + 1],
				tangents[a * 4 + 2] + tangents[b * 4 + 2])
			if t.length_squared() > 1e-12:
				t = t.normalized()
			else:
				t = Vector3(tangents[a * 4], tangents[a * 4 + 1], tangents[a * 4 + 2])
			tangents.append(t.x)
			tangents.append(t.y)
			tangents.append(t.z)
			tangents.append(tangents[a * 4 + 3])
		if has_colors:
			colors.append((colors[a] + colors[b]) * 0.5)
		if has_uv:
			uv.append((uv[a] + uv[b]) * 0.5)
		if has_uv2:
			uv2.append((uv2[a] + uv2[b]) * 0.5)
		_edge_mid[key] = index
		return index

	## Один проход деления. Вернёт false, если делить было нечего.
	func split_pass(max2: float) -> bool:
		_edge_mid.clear()
		var out := PackedInt32Array()
		var any := false
		var tri_count := indices.size() / 3
		for t in range(tri_count):
			var a := indices[t * 3]
			var b := indices[t * 3 + 1]
			var c := indices[t * 3 + 2]
			var s0 := verts[a].distance_squared_to(verts[b]) > max2
			var s1 := verts[b].distance_squared_to(verts[c]) > max2
			var s2 := verts[c].distance_squared_to(verts[a]) > max2
			var splits := int(s0) + int(s1) + int(s2)
			if splits == 0:
				out.append(a)
				out.append(b)
				out.append(c)
				continue
			any = true
			if splits == 3:
				var m0 := _mid(a, b)
				var m1 := _mid(b, c)
				var m2 := _mid(c, a)
				_tri(out, a, m0, m2)
				_tri(out, m0, b, m1)
				_tri(out, m2, m1, c)
				_tri(out, m0, m1, m2)
			elif splits == 1:
				# Поворачиваем треугольник так, чтобы делимое ребро было x–y:
				# поворот вершин по кругу сохраняет направление обхода.
				if s0:
					_split_one(out, a, b, c)
				elif s1:
					_split_one(out, b, c, a)
				else:
					_split_one(out, c, a, b)
			else:
				# Целое ребро — z–x, делятся x–y и y–z.
				if not s2:
					_split_two(out, a, b, c)
				elif not s0:
					_split_two(out, b, c, a)
				else:
					_split_two(out, c, a, b)
		indices = out
		return any

	func _tri(out: PackedInt32Array, a: int, b: int, c: int) -> void:
		out.append(a)
		out.append(b)
		out.append(c)

	func _split_one(out: PackedInt32Array, x: int, y: int, z: int) -> void:
		var m := _mid(x, y)
		_tri(out, x, m, z)
		_tri(out, m, y, z)

	func _split_two(out: PackedInt32Array, x: int, y: int, z: int) -> void:
		var m1 := _mid(x, y)
		var m2 := _mid(y, z)
		_tri(out, m1, y, m2)
		# Оставшийся четырёхугольник x–m1–m2–z режем по короткой диагонали:
		# так меньше узких треугольников.
		if verts[x].distance_squared_to(verts[m2]) <= verts[m1].distance_squared_to(verts[z]):
			_tri(out, x, m1, m2)
			_tri(out, x, m2, z)
		else:
			_tri(out, x, m1, z)
			_tri(out, m1, m2, z)

	func to_arrays(source: Array) -> Array:
		var out := source.duplicate()
		out[Mesh.ARRAY_VERTEX] = verts
		out[Mesh.ARRAY_INDEX] = indices
		if has_normals:
			out[Mesh.ARRAY_NORMAL] = normals
		if has_tangents:
			out[Mesh.ARRAY_TANGENT] = tangents
		if has_colors:
			out[Mesh.ARRAY_COLOR] = colors
		if has_uv:
			out[Mesh.ARRAY_TEX_UV] = uv
		if has_uv2:
			out[Mesh.ARRAY_TEX_UV2] = uv2
		return out
