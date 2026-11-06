## CPU-only terrain preparation. Never touches the scene tree, RenderingServer,
## or PhysicsServer. A job owns its arrays and, on desktop, a private sampler;
## the immutable road index may be shared with the game thread.
extends RefCounted

var source
var network
var key: Vector2i
var origin: Vector3
var divisions: int
var width: int
var halo: int
var cell: float
var use_road_sample: bool
var sample_cache

var heights := PackedFloat32Array()
var distances := PackedFloat32Array()
var alongs := PackedFloat32Array()
var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()
var faces := PackedVector3Array()
var phase: int = 0
var cursor: int = 0
var work_usec: int = 0

func _init(owner, tile: Vector2i, tile_size: float, tile_divisions: int, cache = null) -> void:
	source = owner
	sample_cache = cache
	network = source.network
	key = tile
	divisions = tile_divisions
	width = divisions + 1
	halo = width + 2
	cell = tile_size / float(divisions)
	origin = Vector3(float(key.x) * tile_size, 0.0, float(key.y) * tile_size)
	use_road_sample = source.has_method("_height_with_sample")
	heights.resize(halo * halo)
	distances.resize(halo * halo)
	alongs.resize(halo * halo)
	vertices.resize(width * width)
	normals.resize(width * width)
	colors.resize(width * width)
	indices.resize(divisions * divisions * 6)
	faces.resize(divisions * divisions * 6)


## WorkerThreadPool entry point; no waits or scene tree access here.
func run() -> void:
	advance(0)


## A zero budget finishes the job; otherwise continue in a later frame. Even
## Web builds without threads therefore have small, interruptible CPU slices.
func advance(budget_usec: int) -> bool:
	var started: int = Time.get_ticks_usec()
	var deadline: int = started + budget_usec
	while phase < 3:
		# Check more often than once per row: a single sparse query can be
		# relatively expensive at a dense switchback or far from the road.
		if budget_usec > 0 and cursor % 4 == 0 and Time.get_ticks_usec() >= deadline:
			work_usec += Time.get_ticks_usec() - started
			return false
		if phase == 0:
			var x: int = cursor % halo
			# Деление намеренно целое: это индекс строки в решётке.
			@warning_ignore("integer_division")
			var z: int = cursor / halo
			var px: float = origin.x + float(x - 1) * cell
			var pz: float = origin.z + float(z - 1) * cell
			# Adjacent 96 m tiles overlap by a one-vertex halo. Reuse their
			# exact global lattice samples instead of finding the same road and
			# evaluating noise again at both sides of every boundary.
			var lattice := Vector2i(key.x * divisions + x - 1, key.y * divisions + z - 1)
			var cached = sample_cache.get_sample(lattice) if sample_cache != null else null
			if cached == null:
				var distance: float = network.distance_to_road(px, pz)
				var along: float = network.along_road(px, pz)
				var height: float = source._height_with_sample(px, pz, distance, along) if use_road_sample else source.height_at(px, pz)
				cached = Vector3(distance, along, height - source._road_ditch(distance))
				if sample_cache != null:
					sample_cache.put_sample(lattice, cached)
			distances[cursor] = cached.x
			alongs[cursor] = cached.y
			heights[cursor] = cached.z
			cursor += 1
			if cursor == halo * halo:
				phase = 1
				cursor = 0
		elif phase == 1:
			var x: int = cursor % width
			@warning_ignore("integer_division")
			var z: int = cursor / width
			var h: int = (z + 1) * halo + x + 1
			var point := Vector3(float(x) * cell, heights[h], float(z) * cell)
			var normal := Vector3(heights[h - 1] - heights[h + 1], 2.0 * cell, heights[h - halo] - heights[h + halo]).normalized()
			vertices[cursor] = point
			normals[cursor] = normal
			var corridor: float = source.track.half_width_at(alongs[h]) + source.track.road_shoulder
			var influence: float = smoothstep(corridor * 0.85, corridor + 14.0, distances[h])
			colors[cursor] = Color(influence, (1.0 - normal.y) * influence, 0.5, 1.0)
			cursor += 1
			if cursor == width * width:
				phase = 2
				cursor = 0
		else:
			var x: int = cursor % divisions
			@warning_ignore("integer_division")
			var z: int = cursor / divisions
			var i: int = z * width + x
			var offset: int = cursor * 6
			indices[offset] = i
			indices[offset + 1] = i + 1
			indices[offset + 2] = i + width
			indices[offset + 3] = i + 1
			indices[offset + 4] = i + width + 1
			indices[offset + 5] = i + width
			for n in range(6):
				faces[offset + n] = vertices[indices[offset + n]]
			cursor += 1
			if cursor == divisions * divisions:
				phase = 3
	work_usec += Time.get_ticks_usec() - started
	return true


func mesh_arrays() -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays
