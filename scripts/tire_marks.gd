## Ограниченный кольцевой буфер геометрии следов; никаких дополнительных raycast.
## Узел находится в мире, поэтому следы не перемещаются вместе с машиной.
extends Node3D

const CHUNK_SIZE := 128
const CHUNK_COUNT := 16
const MIN_DISTANCE := 0.18
const MAX_DISTANCE := 5.0
const FLUSH_INTERVAL := 0.08
const MarkShader = preload("res://shaders/tire_marks.gdshader")

var road_surface := "Гравий"
var snow_cover := 0.0
var _trails := {}
var _chunks: Array = []
var _next_segment := 0
var _flush_timer := 0.0
var _material: ShaderMaterial


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = MarkShader
	for i in range(CHUNK_COUNT):
		var visual := MeshInstance3D.new()
		visual.name = "Marks%d" % i
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.material_override = _material
		add_child(visual)
		_chunks.append({"visual": visual, "segments": [], "dirty": false})


func break_trails() -> void:
	_trails.clear()


func _process(delta: float) -> void:
	_flush_timer += delta
	if _flush_timer < FLUSH_INTERVAL:
		return
	_flush_timer = 0.0
	for chunk in _chunks:
		if chunk.dirty:
			_rebuild_chunk(chunk)


func update_wheels(wheels: Array, speed: float) -> void:
	for wheel in wheels:
		var key: int = wheel.get_instance_id()
		var collider: Node = wheel.last_collider as Node
		# Следы только на проезжаемых поверхностях, не на камнях и реквизите.
		if not wheel.is_colliding() or collider == null or speed < 0.8:
			_trails.erase(key)
			continue
		var road: bool = collider.is_in_group("Dirt") or collider.is_in_group("Road")
		var grass: bool = collider.is_in_group("Grass")
		if not road and not grass:
			_trails.erase(key)
			continue
		var surface := _surface_kind(road, grass)
		var slip: float = maxf(absf(wheel.slip_vector.x), absf(wheel.slip_vector.y))
		var intensity: float = smoothstep(0.18, 0.8, slip)
		# На рыхлом грунте остаётся слабая колея даже без заноса.
		var alpha: float = lerpf(0.07, 0.38, intensity) if surface != "asphalt" else intensity * 0.5
		var point: Vector3 = to_local(wheel.last_collision_point + wheel.last_collision_normal * 0.012)
		var normal: Vector3 = (global_basis.inverse() * wheel.last_collision_normal).normalized()
		var previous: Dictionary = _trails.get(key, {})
		var current := {"point": point, "normal": normal, "alpha": alpha, "surface": surface, "collider": collider.get_instance_id(), "distance": 0.0}
		if previous.is_empty() or previous.surface != surface or previous.collider != current.collider:
			if alpha >= 0.025:
				# Плавное начало вместо обрубленного прямоугольника.
				current.alpha = 0.0
				_trails[key] = current
			else:
				_trails.erase(key)
			continue
		var distance: float = point.distance_to(previous.point)
		if distance < MIN_DISTANCE:
			if alpha < 0.025:
				_trails.erase(key)
			continue
		if distance <= MAX_DISTANCE:
			current.distance = previous.distance + distance
			_add_segment(previous, current, clampf(wheel.tire_width / 1000.0, 0.12, 0.45))
		else:
			# Телепортация: новый след начинается отдельно.
			current.alpha = 0.0
		if alpha < 0.025:
			_trails.erase(key)
		else:
			_trails[key] = current


func _surface_kind(road: bool, grass: bool) -> String:
	if snow_cover > 0.45:
		return "snow"
	if grass:
		return "grass"
	var name_lower := road_surface.to_lower()
	if road and ("асфальт" in name_lower or "asphalt" in name_lower or "tarmac" in name_lower):
		return "asphalt"
	if "снег" in name_lower or "snow" in name_lower or "ice" in name_lower:
		return "snow"
	if "гряз" in name_lower or "mud" in name_lower:
		return "mud"
	return "gravel"


func _surface_color(surface: String) -> Color:
	match surface:
		"asphalt": return Color(0.035, 0.03, 0.027)
		"grass": return Color(0.18, 0.14, 0.075)
		"mud": return Color(0.13, 0.085, 0.05)
		"snow": return Color(0.42, 0.48, 0.51)
		_: return Color(0.22, 0.17, 0.12)


func _add_segment(a: Dictionary, b: Dictionary, width: float) -> void:
	var direction: Vector3 = (b.point - a.point).normalized()
	var side_b: Vector3 = b.normal.cross(direction).normalized() * width * 0.5
	# Общие вершины соседних отрезков исключают щели и нахлёсты в повороте.
	var side_a: Vector3 = a.get("side", a.normal.cross(direction).normalized() * width * 0.5)
	if side_a.length_squared() < 0.00001 or side_b.length_squared() < 0.00001:
		return
	b.side = side_b
	var color_a: Color = _surface_color(a.surface)
	var color_b: Color = color_a
	color_a.a = a.alpha
	color_b.a = b.alpha
	var segment := {"vertices": [a.point - side_a, a.point + side_a, b.point - side_b, b.point + side_b], "colors": [color_a, color_a, color_b, color_b], "start_distance": a.distance, "end_distance": b.distance}
	var chunk_index: int = int(_next_segment / CHUNK_SIZE) % CHUNK_COUNT
	var slot: int = _next_segment % CHUNK_SIZE
	var chunk: Dictionary = _chunks[chunk_index]
	if slot == 0:
		chunk.segments.clear()
	chunk.segments.append(segment)
	chunk.dirty = true
	_next_segment = (_next_segment + 1) % (CHUNK_SIZE * CHUNK_COUNT)


func _rebuild_chunk(chunk: Dictionary) -> void:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for segment in chunk.segments:
		var base := vertices.size()
		vertices.append_array(PackedVector3Array(segment.vertices))
		colors.append_array(PackedColorArray(segment.colors))
		uvs.append_array(PackedVector2Array([Vector2(0, segment.start_distance), Vector2(1, segment.start_distance), Vector2(0, segment.end_distance), Vector2(1, segment.end_distance)]))
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	chunk.visual.mesh = mesh
	chunk.dirty = false
