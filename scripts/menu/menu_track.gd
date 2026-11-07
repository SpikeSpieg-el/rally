@tool
## Editable closed Path3D. Rebuild creates the road mesh and wheel collision;
## the curve is also a guide for the optional physics-driven demo driver.
extends Path3D

@export_range(2.0, 20.0, 0.1) var half_width := 5.5
@export_range(0.5, 8.0, 0.5) var sample_step := 2.0
@export var road_material: Material
@export var road_color := Color(0.40, 0.33, 0.24)
@export_tool_button("Пересобрать дорогу") var rebuild_button = rebuild


func _ready() -> void:
	rebuild()
	if Engine.is_editor_hint() and curve != null and not curve.changed.is_connected(_queue_rebuild):
		curve.changed.connect(_queue_rebuild)


func _queue_rebuild() -> void:
	call_deferred("rebuild")


func rebuild() -> void:
	if curve == null or curve.point_count < 2:
		return
	var visual := get_node_or_null("RoadMesh") as MeshInstance3D
	var collider := get_node_or_null("RoadSurface/CollisionShape3D") as CollisionShape3D
	if visual == null or collider == null:
		return
	var length := curve.get_baked_length()
	if length < 1.0:
		return
	var rows := maxi(3, ceili(length / maxf(sample_step, 0.5)))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in range(rows + 1):
		var d := length * float(i) / float(rows)
		var point := curve.sample_baked(d, true)
		var before := curve.sample_baked(fposmod(d - 0.5, length), true)
		var after := curve.sample_baked(fposmod(d + 0.5, length), true)
		var direction := (after - before).normalized()
		var side := Vector3(direction.z, 0.0, -direction.x).normalized()
		for lateral in [-half_width, 0.0, half_width]:
			vertices.append(point + side * lateral)
			normals.append(Vector3.UP)
			colors.append(road_color if lateral == 0.0 else road_color.darkened(0.12))
			uvs.append(Vector2(lateral, d))
	for i in range(rows):
		for lane in range(2):
			var a := i * 3 + lane
			var b := a + 3
			indices.append_array(PackedInt32Array([a, a + 1, b, a + 1, b + 1, b]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	visual.mesh = result
	visual.material_override = road_material
	var shape := result.create_trimesh_shape()
	if shape is ConcavePolygonShape3D:
		shape.backface_collision = true
	collider.shape = shape
