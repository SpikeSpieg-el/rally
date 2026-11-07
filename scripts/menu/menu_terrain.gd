@tool
## Компактный рельеф меню. Как на спецучастке, используем RoadNetwork для
## расстояния до трассы и плавно сводим шумовые холмы к высоте полотна.
extends StaticBody3D

const RoadNetworkType = preload("res://scripts/road_network.gd")
signal terrain_rebuilt

@export_range(2.0, 12.0, 0.5, "suffix:m") var terrain_cell := 4.0
@export var terrain_size := Vector2(520.0, 420.0)
@export var seed_value := 4711
@export_range(0.0, 50.0, 0.5, "suffix:m") var hills_height := 18.0
@export_range(0.001, 0.04, 0.001) var hills_frequency := 0.008
@export_range(5.0, 80.0, 1.0, "suffix:m") var blend_distance := 25.0
@export var ground_material: Material
@export_tool_button("Пересобрать рельеф") var rebuild_button = rebuild

var network: RoadNetwork
var _heights := PackedFloat32Array()
var _origin := Vector2.ZERO
var _cols := 0
var _rows := 0
var _cell := 4.0
var _rebuild_pending := false

func _ready() -> void:
	var track := get_node_or_null("../Track") as Path3D
	if track == null or track.curve == null:
		return
	rebuild()
	if Engine.is_editor_hint() and not track.curve.changed.is_connected(_queue_rebuild):
		track.curve.changed.connect(_queue_rebuild)

func _queue_rebuild() -> void:
	if not _rebuild_pending:
		_rebuild_pending = true
		call_deferred("rebuild")

func rebuild() -> void:
	_rebuild_pending = false
	var track = get_node_or_null("../Track")
	var visual := get_node_or_null("Mesh") as MeshInstance3D
	var collider := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if track == null or track.curve == null or track.curve.point_count < 2 or visual == null or collider == null:
		return
	_cell = maxf(terrain_cell, 2.0)
	_origin = -terrain_size * 0.5
	var area := Rect2(_origin, terrain_size)
	network = RoadNetworkType.build(track.curve, area, _cell)
	_cols = network.cols
	_rows = network.rows
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = hills_frequency
	noise.fractal_octaves = 3
	var detail := FastNoiseLite.new()
	detail.seed = seed_value + 173
	detail.frequency = 0.035
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	_heights.resize(_cols * _rows)
	vertices.resize(_cols * _rows)
	normals.resize(_cols * _rows)
	colors.resize(_cols * _rows)
	var corridor: float = track.half_width + track.shoulder_width
	for z in range(_rows):
		for x in range(_cols):
			var index := z * _cols + x
			var px := _origin.x + float(x) * _cell
			var pz := _origin.y + float(z) * _cell
			var sample: Vector2 = network.sample_grid(x, z)
			var road_y: float = network.height_at_along(sample.y)
			var base: float = network.regional_height(px, pz) + noise.get_noise_2d(px, pz) * hills_height + detail.get_noise_2d(px, pz) * 1.5
			var blend := smoothstep(corridor, corridor + blend_distance, sample.x)
			# Под полотном земля чуть ниже: коллизия гравия остаётся главной.
			var height := lerpf(road_y - 0.65, base, blend)
			_heights[index] = height
			vertices[index] = Vector3(px, height, pz)
			colors[index] = Color(smoothstep(corridor * 0.8, corridor + 14.0, sample.x), smoothstep(corridor + 2.0, corridor + 10.0, sample.x), 0.5 + detail.get_noise_2d(px, pz) * 0.5, 1.0)
	for z in range(_rows):
		for x in range(_cols):
			var left := _heights[z * _cols + maxi(x - 1, 0)]
			var right := _heights[z * _cols + mini(x + 1, _cols - 1)]
			var back := _heights[maxi(z - 1, 0) * _cols + x]
			var front := _heights[mini(z + 1, _rows - 1) * _cols + x]
			normals[z * _cols + x] = Vector3(left - right, _cell * 2.0, back - front).normalized()
	var indices := PackedInt32Array()
	for z in range(_rows - 1):
		for x in range(_cols - 1):
			var i := z * _cols + x
			indices.append_array(PackedInt32Array([i, i + 1, i + _cols, i + 1, i + _cols + 1, i + _cols]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	visual.mesh = result
	visual.material_override = ground_material
	var shape := result.create_trimesh_shape()
	shape.backface_collision = true
	collider.shape = shape
	terrain_rebuilt.emit()

## Высота именно треугольника, а не приблизительного аналитического шума.
func ground_height(x: float, z: float) -> float:
	if _heights.is_empty():
		return 0.0
	var fx := (x - _origin.x) / _cell
	var fz := (z - _origin.y) / _cell
	var gx := clampi(floori(fx), 0, _cols - 2)
	var gz := clampi(floori(fz), 0, _rows - 2)
	var u := clampf(fx - float(gx), 0.0, 1.0)
	var v := clampf(fz - float(gz), 0.0, 1.0)
	var i := gz * _cols + gx
	var h00 := _heights[i]
	var h10 := _heights[i + 1]
	var h01 := _heights[i + _cols]
	var h11 := _heights[i + _cols + 1]
	if u + v <= 1.0:
		return h00 + u * (h10 - h00) + v * (h01 - h00)
	return h11 * (u + v - 1.0) + h10 * (1.0 - v) + h01 * (1.0 - u)
