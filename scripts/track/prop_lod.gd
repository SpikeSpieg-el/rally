## LOD для простых мешей сцены обстановки. Варианты используют настоящие
## упрощённые примитивы, а не удаление случайных треугольников (дырки в меше).
## Переключает индексы сам рендерер Godot по экранному размеру, без _process.
@tool
extends RefCounted


static func primitive_at_level(source: Mesh, level: int) -> Mesh:
	if level <= 0 or not (source is CylinderMesh or source is SphereMesh):
		return source
	var reduced: PrimitiveMesh = source.duplicate() as PrimitiveMesh
	var factor := 0.8 if level == 1 else 0.6
	if reduced is CylinderMesh:
		var cylinder := reduced as CylinderMesh
		cylinder.radial_segments = maxi(4, roundi(cylinder.radial_segments * factor))
		if level >= 2:
			cylinder.rings = 0
	elif reduced is SphereMesh:
		var sphere := reduced as SphereMesh
		sphere.radial_segments = maxi(4, roundi(sphere.radial_segments * factor))
		sphere.rings = maxi(1, roundi(sphere.rings * factor))
	return reduced


static func has_reducible_primitive(node: Node) -> bool:
	if node is MeshInstance3D:
		var source: Mesh = (node as MeshInstance3D).mesh
		if source is CylinderMesh:
			var cylinder := source as CylinderMesh
			if cylinder.radial_segments > 4 or cylinder.rings > 0:
				return true
		if source is SphereMesh:
			var sphere := source as SphereMesh
			if sphere.radial_segments > 4 or sphere.rings > 1:
				return true
	for child in node.get_children():
		if has_reducible_primitive(child):
			return true
	return false


## Объединить вершины трёх вариантов в один surface; только индексный буфер
## переключается на GPU. Если вариант не уменьшился или несовместим по каналам,
## он пропускается: квадрат и так имеет всего два треугольника.
static func surface_with_lods(base: Array, middle: Array, far: Array, scale: float) -> Dictionary:
	var result: Array = base.duplicate()
	var indices := _indices(base)
	if indices.is_empty():
		return {"arrays": base, "lods": {}}
	result[Mesh.ARRAY_INDEX] = indices
	var lods := {}
	var previous_count := indices.size()
	for level in range(1, 3):
		var variant: Array = middle if level == 1 else far
		var simplified := _indices(variant)
		if simplified.is_empty() or simplified.size() >= previous_count or not _compatible(result, variant):
			continue
		var offset: int = (result[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		for channel in range(Mesh.ARRAY_INDEX):
			if result[channel] == null:
				continue
			var data = result[channel]
			data.append_array(variant[channel])
			result[channel] = data
		for i in range(simplified.size()):
			simplified[i] += offset
		# Это геометрическая ошибка в пространстве меша, а не метры от камеры.
		# Godot дополнительно учитывает масштаб, разрешение и поле зрения.
		var error: float = maxf(0.0001, scale * (0.02 if level == 1 else 0.08))
		lods[error] = simplified
		previous_count = simplified.size()
	return {"arrays": result, "lods": lods}


static func _indices(arrays: Array) -> PackedInt32Array:
	if arrays.size() != Mesh.ARRAY_MAX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
		return PackedInt32Array()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
		indices = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).duplicate()
	else:
		indices.resize(vertices.size())
		for i in range(vertices.size()):
			indices[i] = i
	if indices.is_empty() or indices.size() % 3 != 0:
		return PackedInt32Array()
	return indices


static func _compatible(base: Array, other: Array) -> bool:
	if other.size() != Mesh.ARRAY_MAX:
		return false
	for channel in range(Mesh.ARRAY_INDEX):
		if (base[channel] == null) != (other[channel] == null):
			return false
		if base[channel] != null and typeof(base[channel]) != typeof(other[channel]):
			return false
	return true


## Для обычного MeshInstance3D кисти. Материалы и узлы не меняются; коллизии
## остаются у исходной сцены. Непримитивные меши оставляем как есть (они могут
## уже содержать импортированные LOD или анимацию/skinning).
static func mesh_with_lods(source: Mesh) -> Mesh:
	if not (source is CylinderMesh or source is SphereMesh) or source.get_surface_count() != 1:
		return source
	var middle := primitive_at_level(source, 1)
	var far := primitive_at_level(source, 2)
	var size := source.get_aabb().size
	var scale := maxf(size.x, maxf(size.y, size.z))
	var built := surface_with_lods(source.surface_get_arrays(0), middle.surface_get_arrays(0), far.surface_get_arrays(0), scale)
	var lods: Dictionary = built["lods"]
	if lods.is_empty():
		return source
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, built["arrays"], [], lods)
	result.surface_set_material(0, source.surface_get_material(0))
	return result
