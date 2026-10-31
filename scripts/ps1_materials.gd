## Point-фильтрация обычных материалов в заезде. Исходные ресурсы сцены
## не изменяются: общие материалы копируются только один раз на этап.
extends RefCounted


## Одинаковая палитра для камеры этапа и превью машины в гараже.
static func configure_post_effect(material: ShaderMaterial, enabled: bool, strength: float, resolution_y: float, color_bits: int, dither: bool) -> void:
	var bits := clampi(color_bits, 0, 8)
	var levels := (1 << bits) - 1 if enabled and bits > 0 else 0
	material.set_shader_parameter("retro_strength", clampf(strength, 0.0, 1.0) if enabled else 0.0)
	material.set_shader_parameter("resolution_y", clampf(resolution_y, 180.0, 720.0))
	material.set_shader_parameter("color_levels", float(levels))
	material.set_shader_parameter("dither_strength", 1.0 if enabled and dither else 0.0)


static func apply_nearest(root: Node) -> void:
	var cache: Dictionary = {}
	_visit(root, cache)


static func _visit(node: Node, cache: Dictionary) -> void:
	if node is MeshInstance3D:
		_style_mesh_instance(node as MeshInstance3D, cache)
	elif node is MultiMeshInstance3D:
		_style_multimesh_instance(node as MultiMeshInstance3D, cache)
	for child in node.get_children():
		_visit(child, cache)


static func _nearest_material(source: Material, cache: Dictionary) -> Material:
	if not source is BaseMaterial3D:
		return source
	var base := source as BaseMaterial3D
	var has_texture := false
	for i in range(BaseMaterial3D.TEXTURE_MAX):
		if base.get_texture(i) != null:
			has_texture = true
			break
	if not has_texture:
		return source
	if not cache.has(source):
		var copy := base.duplicate() as BaseMaterial3D
		copy.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		cache[source] = copy
	return cache[source] as Material


static func _style_mesh_instance(instance: MeshInstance3D, cache: Dictionary) -> void:
	if instance.material_override != null:
		instance.material_override = _nearest_material(instance.material_override, cache)
		return
	if instance.mesh == null:
		return
	for i in range(instance.mesh.get_surface_count()):
		var original := instance.get_surface_override_material(i)
		if original == null:
			original = instance.mesh.surface_get_material(i)
		var styled := _nearest_material(original, cache)
		if styled != original:
			instance.set_surface_override_material(i, styled)


static func _style_multimesh_instance(instance: MultiMeshInstance3D, cache: Dictionary) -> void:
	if instance.material_override != null:
		instance.material_override = _nearest_material(instance.material_override, cache)
		return
	var multimesh := instance.multimesh
	if multimesh == null or multimesh.mesh == null:
		return
	var mesh := multimesh.mesh
	# Большинство процедурных объектов имеют одну поверхность: не копируем
	# массив трансформаций деревьев ради одного материала.
	if mesh.get_surface_count() == 1:
		var original := mesh.surface_get_material(0)
		var styled := _nearest_material(original, cache)
		if styled != original:
			instance.material_override = styled
		return
	# Ручные MultiMesh могут иметь несколько поверхностей с разными материалами.
	var mesh_copy: Mesh = null
	for i in range(mesh.get_surface_count()):
		var original := mesh.surface_get_material(i)
		var styled := _nearest_material(original, cache)
		if styled != original:
			if mesh_copy == null:
				mesh_copy = mesh.duplicate() as Mesh
			mesh_copy.surface_set_material(i, styled)
	if mesh_copy != null:
		var multimesh_copy := multimesh.duplicate() as MultiMesh
		multimesh_copy.mesh = mesh_copy
		instance.multimesh = multimesh_copy
