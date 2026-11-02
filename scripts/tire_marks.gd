## Следы шин и комья грунта. Ограниченный кольцевой буфер геометрии, никаких
## дополнительных raycast. Узел находится в мире, поэтому следы не
## перемещаются вместе с машиной.
##
## ВСЕ ЧИСЛА (буфер, дистанции, цвета, прозрачность, размеры комьев) живут в
## ресурсе RallyFxProfile (data/stage/default_fx_profile.tres) и читаются
## отсюда. Хотите другие следы — правьте профиль в инспекторе, не этот файл.
extends Node3D

const MarkShader = preload("res://shaders/tire_marks.gdshader")
const SoilShader = preload("res://shaders/loose_soil.gdshader")
const FxProfileType = preload("res://scripts/data/rally_fx_profile.gd")

## Значения по умолчанию, если профиль не назначен (совпадают с .tres).
const CHUNK_SIZE := 128
const CHUNK_COUNT := 16
const MIN_DISTANCE := 0.18
const MAX_DISTANCE := 5.0
const FLUSH_INTERVAL := 0.08
const SOIL_SPACING := 0.7
const MIN_LOOSENESS := 0.25

## Профиль эффектов из инспектора. Если пуст — берётся общий из проекта.
@export var fx: FxProfileType = null

var road_surface := "Гравий"
var snow_cover := 0.0
var wetness := 0.0
var _soil_material: ShaderMaterial
var _trails := {}
var _chunks: Array = []
var _next_segment := 0
var _flush_timer := 0.0
var _material: ShaderMaterial
var _chunk_size := CHUNK_SIZE
var _chunk_count := CHUNK_COUNT


func _ready() -> void:
	_apply_profile()
	_material = ShaderMaterial.new()
	_material.shader = MarkShader
	_soil_material = ShaderMaterial.new()
	_soil_material.shader = SoilShader
	for i in range(_chunk_count):
		var visual := MeshInstance3D.new()
		visual.name = "Marks%d" % i
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.material_override = _material
		add_child(visual)
		var soil := MeshInstance3D.new()
		soil.name = "LooseSoil%d" % i
		soil.material_override = _soil_material
		add_child(soil)
		_chunks.append({"visual": visual, "soil": soil, "segments": [], "dirty": false})


## Забрать числа из профиля в локальные поля (null-safe).
func _apply_profile() -> void:
	if fx == null:
		return
	_chunk_size = maxi(1, fx.chunk_size)
	_chunk_count = maxi(1, fx.chunk_count)


func _p(name: String, fallback: float) -> float:
	return float(fx.get(name)) if fx != null else fallback


func _pc(name: String, fallback: Color) -> Color:
	return fx.get(name) as Color if fx != null else fallback


func break_trails() -> void:
	_trails.clear()


func _process(delta: float) -> void:
	_flush_timer += delta
	if _flush_timer < _p("flush_interval", FLUSH_INTERVAL):
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
		if not wheel.is_colliding() or collider == null or speed < _p("min_speed", 0.8):
			_trails.erase(key)
			continue
		var road: bool = collider.is_in_group("Dirt") or collider.is_in_group("Road")
		var grass: bool = collider.is_in_group("Grass")
		if not road and not grass:
			_trails.erase(key)
			continue
		var surface := _surface_kind(road, grass)
		var slip: float = maxf(absf(wheel.slip_vector.x), absf(wheel.slip_vector.y))
		var intensity: float = smoothstep(_p("slip_start", 0.18), _p("slip_full", 0.8), slip)
		var alpha_min: float = _p("alpha_min", 0.07)
		var alpha_max: float = _p("alpha_max", 0.38)
		# На рыхлом грунте остаётся слабая колея даже без заноса.
		var alpha: float = lerpf(alpha_min, alpha_max, intensity) if surface != "asphalt" else intensity * _p("alpha_asphalt_scale", 0.5)
		# Глубокая колея шире и темнее обычного отпечатка протектора.
		var rut: float = clampf(float(wheel.get("surface_depth")) / maxf(0.001, _p("rut_depth_scale", 0.065)), 0.0, 1.0) if "surface_depth" in wheel else 0.0
		if surface != "asphalt":
			alpha = minf(_p("alpha_limit", 0.55), alpha + rut * _p("rut_alpha_bonus", 0.2))
		var point: Vector3 = to_local(wheel.last_collision_point + wheel.last_collision_normal * _p("surface_offset", 0.012))
		var normal: Vector3 = (global_basis.inverse() * wheel.last_collision_normal).normalized()
		var previous: Dictionary = _trails.get(key, {})
		var current := {"point": point, "normal": normal, "alpha": alpha, "surface": surface, "collider": collider.get_instance_id(), "distance": 0.0, "looseness": maxf(rut, intensity * 0.75)}
		if previous.is_empty() or previous.surface != surface or previous.collider != current.collider:
			if alpha >= _p("alpha_cutoff", 0.025):
				# Плавное начало вместо обрубленного прямоугольника.
				current.alpha = 0.0
				current.looseness = 0.0
				_trails[key] = current
			else:
				_trails.erase(key)
			continue
		var distance: float = point.distance_to(previous.point)
		if distance < _p("min_distance", MIN_DISTANCE):
			if alpha < _p("alpha_cutoff", 0.025):
				_trails.erase(key)
			continue
		if distance <= _p("max_distance", MAX_DISTANCE):
			current.distance = previous.distance + distance
			var width: float = clampf(
				float(wheel.tire_width) / 1000.0,
				_p("tire_width_min_m", 0.12),
				_p("tire_width_max_m", 0.45)
			) * _p("width_scale", 1.0) * (1.0 + rut * _p("rut_width_bonus", 0.3))
			_add_segment(previous, current, width)
		else:
			# Телепортация: новый след начинается отдельно.
			current.alpha = 0.0
			current.looseness = 0.0
		if alpha < _p("alpha_cutoff", 0.025):
			_trails.erase(key)
		else:
			_trails[key] = current


func _surface_kind(road: bool, grass: bool) -> String:
	if snow_cover > _p("snow_track_threshold", 0.45):
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
		"asphalt": return _pc("asphalt_mark_color", Color(0.035, 0.03, 0.027))
		"grass": return _pc("grass_mark_color", Color(0.18, 0.14, 0.075))
		"mud": return _pc("mud_mark_color", Color(0.13, 0.085, 0.05))
		"snow": return _pc("snow_mark_color", Color(0.42, 0.48, 0.51))
		_: return _pc("gravel_mark_color", Color(0.22, 0.17, 0.12))


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
	var soil_color: Color = _surface_color(a.surface).lightened(_p("soil_lighten", 0.18)).lerp(
		_pc("wet_soil_color", Color(0.12, 0.075, 0.035)), wetness * _p("soil_wet_darken", 0.6)
	)
	var segment := {"vertices": [a.point - side_a, a.point + side_a, b.point - side_b, b.point + side_b], "colors": [color_a, color_a, color_b, color_b], "start_distance": a.distance, "end_distance": b.distance, "soil": _soil_vertices(a, b, side_a, side_b), "soil_color": soil_color}
	var chunk_index: int = int(_next_segment / _chunk_size) % _chunk_count
	var slot: int = _next_segment % _chunk_size
	var chunk: Dictionary = _chunks[chunk_index]
	if slot == 0:
		chunk.segments.clear()
	chunk.segments.append(segment)
	chunk.dirty = true
	_next_segment = (_next_segment + 1) % (_chunk_size * _chunk_count)


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
	_rebuild_soil(chunk)
	chunk.dirty = false


## Один отпечаток на колесо. Рыхлый грунт — отдельные комочки,
## а не два непрерывных валика, похожих на дополнительные следы шин.
func _soil_vertices(a: Dictionary, b: Dictionary, side_a: Vector3, side_b: Vector3) -> PackedVector3Array:
	var result := PackedVector3Array()
	if a.surface == "asphalt":
		return result
	var loose_a: float = a.get("looseness", 0.0)
	var loose_b: float = b.get("looseness", 0.0)
	if maxf(loose_a, loose_b) <= _p("min_looseness", MIN_LOOSENESS):
		return result
	var length: float = b.distance - a.distance
	if length <= 0.0:
		return result
	# Фиксированный шаг вдоль пути: частота вызовов и длина сегмента
	# не превращают комочки обратно в сплошную полосу.
	var spacing: float = maxf(0.01, _p("soil_spacing", SOIL_SPACING))
	var first := maxi(0, ceili(a.distance / spacing - 0.5))
	var last := ceili(b.distance / spacing - 0.5)
	var r_min: float = _p("soil_radius_min", 0.012)
	var r_max: float = _p("soil_radius_max", 0.028)
	for index in range(first, last):
		var along := (float(index) + 0.5) * spacing
		var t := clampf((along - a.distance) / length, 0.0, 1.0)
		var loose := lerpf(loose_a, loose_b, t)
		if loose <= _p("min_looseness", MIN_LOOSENESS):
			continue
		var normal: Vector3 = a.normal.lerp(b.normal, t).normalized()
		var side := side_a.lerp(side_b, t)
		if side.length_squared() < 0.00001:
			continue
		var point: Vector3 = a.point.lerp(b.point, t)
		var seed_value := sin(point.x * 12.9898 + point.z * 78.233) * 43758.5453
		var variation := fposmod(seed_value, 1.0)
		# Только один комочек в сечении, сторона и смещение нерегулярные.
		var sign_side := -1.0 if variation < 0.5 else 1.0
		var center := point + side * sign_side * lerpf(_p("soil_side_min", 0.85), _p("soil_side_max", 1.15), variation) - normal * _p("soil_offset", 0.01)
		var radius := lerpf(r_min, r_max, loose)
		var across := side.normalized() * radius
		var forward := normal.cross(side.normalized()) * radius
		var p0 := center - across - forward * 0.6
		var p1 := center + across - forward * 0.6
		var p2 := center + forward
		var top := center + normal * _p("soil_height", 0.035) * loose * lerpf(0.7, 1.0, variation)
		result.append_array(PackedVector3Array([p0, p1, top, p1, p2, top, p2, p0, top, p0, p2, p1]))
	return result


func _rebuild_soil(chunk: Dictionary) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for segment in chunk.segments:
		var soil: PackedVector3Array = segment.soil
		for i in range(0, soil.size(), 3):
			var normal := (soil[i + 1] - soil[i]).cross(soil[i + 2] - soil[i]).normalized()
			if normal.y < 0.0:
				normal = -normal
			for j in range(3):
				vertices.append(soil[i + j])
				normals.append(normal)
				colors.append(segment.soil_color)
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	chunk.soil.mesh = mesh
