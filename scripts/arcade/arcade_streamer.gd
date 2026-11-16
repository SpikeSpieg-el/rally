## Стример аркадной дороги: держит вокруг машины только те чанки, что нужны,
## и строит их по одному в кадр — без «замираний» при подъезде к границе.
##
## Ключевое отличие от WorldStreamer: там дорога — конечная сеть с тайлами
## рельефа на плоскости, а здесь дорога бесконечная и живёт в километраже.
## Поэтому:
##   * чанк — это отрезок [k·CHUNK_LENGTH, (k+1)·CHUNK_LENGTH) по километражу;
##   * нужные чанки берутся из пробега машины (вперёд с запасом на скорость),
##     а не из радиуса в плане: на серпантине два берега шпильки рядом по
##     координатам, но далеко по дороге, и «радиусный» стример тянул бы лишнее;
##   * готовый чанк помнит свой километраж, поэтому возврат назад ничего не
##     пересобирает.
##
## Строительство чанка занимает несколько миллисекунд, поэтому в кадре
## собирается не больше одного, а бюджет кадра ограничен BUDGET_USEC. Если
## машина уже на неготовой дороге, чанк под ней собирается вне очереди —
## лучше короткий подлаг, чем провал в пустоту.
class_name RallyArcadeStreamer
extends Node3D

const ChunkType = preload("res://scripts/arcade/arcade_chunk.gd")

## Длина одного чанка, м. Должна делить LEG_LENGTH (260) нацело, иначе чанк
## начнётся посреди домена и меш порвётся на смене ширины.
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

var _chunks: Dictionary = {}
var _queue: Array[int] = []
var _last_center: int = -9999
var _generated_count: int = 0


func setup(seed_value: int, road: Material, ground: Material) -> void:
	arcade_seed = seed_value
	road_material = road
	ground_material = ground
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
	# Ближние — первыми: если бюджет кончится, дальние подождут кадр.
	_queue.sort()


## Собрать нужные чанки СРАЗУ, не растягивая на кадры. Нужен только на старте:
## первый кадр не должен показывать машину над пустотой.
func prime(behind: float, ahead_chunks: int) -> void:
	var center: int = int(floor(maxf(behind, 0.0) / CHUNK_LENGTH))
	_last_center = center
	for offset in range(-KEEP_BEHIND, ahead_chunks + 1):
		var key: int = center + offset
		if key < 0 or is_ready(float(key) * CHUNK_LENGTH):
			continue
		_build(key)


## Сколько чанков готово (для HUD/отладки).
func ready_chunks() -> int:
	return _chunks.size()


func generated_chunks() -> int:
	return _generated_count


## Готов ли чанк, накрывающий километраж. Проверяется именно живой узел:
## выгруженный чанк остаётся в дереве до конца кадра, и «ключ есть» ещё не
## значит «меш на месте».
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


## Пробег, до которого дорога гарантированно есть: для проверки «машина в
## пустоте» и для физики (нужно знать, где заканчивается полотно).
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
	var materials: Dictionary = {"road": road_material, "ground": ground_material}
	var built := ChunkType.build(start_along, end_along, arcade_seed, materials)
	built.root.name = "Chunk%d" % key
	add_child(built.root)
	for i in range(built.shapes.size()):
		var body := StaticBody3D.new()
		var collider := CollisionShape3D.new()
		collider.shape = built.shapes[i]
		body.add_child(collider)
		body.name = "Surface"
		# Группа — контракт с колесом (`wheel.gd`): покрытие спрашивается только
		# у коллайдеров из Road/Dirt/Grass. Коллайдер без группы молча ехал бы
		# как трава — с другим сцеплением и без пыли.
		if built.kinds[i] == "road":
			body.add_to_group("Road")
		else:
			body.add_to_group("Grass")
		built.root.add_child(body)
	_chunks[key] = built.root
	_generated_count += 1
