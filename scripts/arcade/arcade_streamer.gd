## Стример аркадной дороги: держит вокруг машины только те чанки, что нужны,
## и строит их по одному в кадр — без «замираний» при подъезде к границе.
##
## Чанк — отрезок [k·CHUNK_LENGTH, (k+1)·CHUNK_LENGTH) по километражу.
## Стример строит полотно, придорожную юбку и передаёт постройку леса,
## отбойников, деревень и мостов генератору обстановки.
class_name RallyArcadeStreamer
extends Node3D

const ChunkType = preload("res://scripts/arcade/arcade_chunk.gd")

## Длина одного чанка, м. Должна делить LEG_LENGTH (260) нацело.
const CHUNK_LENGTH: float = 130.0
## Сколько чанков держать позади машины.
const KEEP_BEHIND: int = 2
## Сколько впереди строить.
const LOOKAHEAD: int = 8
## Бюджет сборки на кадр, мкс.
const BUDGET_USEC: int = 4000

var arcade_seed: int = 0
var road_material: Material = null
var ground_material: Material = null
var terrain = null
var scenery = null
var chunk_style: Dictionary = {}

var _chunks: Dictionary = {}
var _queue: Array[int] = []
var _last_center: int = -9999
var _generated_count: int = 0


func setup(
	seed_value: int,
	road: Material,
	ground: Material,
	extra: Dictionary = {}
) -> void:
	arcade_seed = seed_value
	road_material = road
	ground_material = ground
	terrain = extra.get("terrain", null)
	scenery = extra.get("scenery", null)
	chunk_style = extra.duplicate()
	var geometry: Variant = extra.get("geometry", {})
	if geometry is Dictionary:
		ChunkType.configure_geometry(geometry as Dictionary)
	for child in get_children():
		child.queue_free()
	_chunks.clear()
	_queue.clear()
	_last_center = -9999


## Центр внимания — пробег машины (м).
func focus(distance: float) -> void:
	var center: int = int(floor(distance / CHUNK_LENGTH))
	if center == _last_center:
		return
	_last_center = center
	_refresh_wanted(center)


func _refresh_wanted(center: int) -> void:
	var wanted: Dictionary = {}
	for offset in range(-KEEP_BEHIND, LOOKAHEAD + 1):
		wanted[center + offset] = true
	for key in _chunks.keys():
		if not wanted.has(key):
			var node: Variant = _chunks[key]
			_chunks.erase(key)
			if is_instance_valid(node):
				(node as Node).queue_free()
	_queue.clear()
	for offset in range(0, LOOKAHEAD + 1):
		var key: int = center + offset
		if not is_ready(float(key) * CHUNK_LENGTH):
			_queue.append(key)
	_queue.sort()


## Собрать нужные чанки СРАЗУ, не растягивая на кадры (на старте).
func prime(behind: float, ahead_chunks: int) -> void:
	var center: int = int(floor(maxf(behind, 0.0) / CHUNK_LENGTH))
	_last_center = center
	for offset in range(-KEEP_BEHIND, ahead_chunks + 1):
		var key: int = center + offset
		if key < 0 or is_ready(float(key) * CHUNK_LENGTH):
			continue
		_build(key)


func ready_chunks() -> int:
	return _chunks.size()


func generated_chunks() -> int:
	return _generated_count


func is_ready(distance: float) -> bool:
	var key: int = int(floor(distance / CHUNK_LENGTH))
	return _chunks.has(key) and is_instance_valid(_chunks[key])


func _process(_delta: float) -> void:
	if _queue.is_empty():
		return
	var started: int = Time.get_ticks_usec()
	while not _queue.is_empty() and Time.get_ticks_usec() - started < BUDGET_USEC:
		var key: int = _queue.pop_front()
		if is_ready(float(key) * CHUNK_LENGTH):
			continue
		_build(key)


func covered_ahead(from_distance: float) -> float:
	var key: int = int(floor(from_distance / CHUNK_LENGTH))
	var end: float = from_distance
	for offset in range(0, LOOKAHEAD + 1):
		if not is_ready(float(key + offset) * CHUNK_LENGTH):
			break
		end = float(key + offset + 1) * CHUNK_LENGTH
	return end


func _build(key: int) -> void:
	var start_along: float = float(key) * CHUNK_LENGTH
	var end_along: float = start_along + CHUNK_LENGTH
	if terrain != null and terrain.has_method("sync_road_to"):
		terrain.sync_road_to(end_along + CHUNK_LENGTH)
	var materials: Dictionary = {
		"road": road_material,
		"ground": ground_material,
		"terrain": terrain,
		"scenery": scenery,
		"road_color": chunk_style.get("road_color", Color(0.22, 0.22, 0.24)),
		"road_color_2": chunk_style.get("road_color_2", Color(0.29, 0.29, 0.31)),
		"shoulder_color": chunk_style.get("shoulder_color", Color(0.31, 0.26, 0.18)),
		"edge_post_color": chunk_style.get("edge_post_color", Color(0.88, 0.14, 0.10)),
		"loose_surface": bool(chunk_style.get("loose_surface", false)),
	}
	var built := ChunkType.build(start_along, end_along, arcade_seed, materials)
	built.root.name = "Chunk%d" % key
	add_child(built.root)
	for i in range(built.shapes.size()):
		var body := StaticBody3D.new()
		var collider := CollisionShape3D.new()
		collider.shape = built.shapes[i]
		body.add_child(collider)
		body.name = "Surface"
		if built.kinds[i] == "road":
			body.add_to_group("Road")
		else:
			body.add_to_group("Grass")
		built.root.add_child(body)
	_chunks[key] = built.root
	_generated_count += 1
