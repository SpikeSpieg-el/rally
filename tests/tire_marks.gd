# godot --headless --path . --script res://tests/tire_marks.gd
extends SceneTree

const Marks = preload("res://scripts/tire_marks.gd")

class FakeWheel extends Node3D:
	var last_collider: Object
	var last_collision_point := Vector3.ZERO
	var last_collision_normal := Vector3.UP
	var slip_vector := Vector2.ZERO
	var tire_width := 205.0
	var contact := true
	func is_colliding() -> bool:
		return contact

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var marks = Marks.new()
	root.add_child(marks)
	var ground := StaticBody3D.new()
	ground.add_to_group("Dirt")
	root.add_child(ground)
	var wheel := FakeWheel.new()
	root.add_child(wheel)
	wheel.last_collider = ground
	marks.road_surface = "Асфальт"
	marks.update_wheels([wheel], 10.0)
	wheel.last_collision_point.z = 1.0
	marks.update_wheels([wheel], 10.0)
	var ok: bool = marks._next_segment == 0 # асфальт без проскальзывания
	wheel.slip_vector = Vector2(0.8, 0.0)
	marks.update_wheels([wheel], 10.0)
	wheel.last_collision_point.z = 2.0
	marks.update_wheels([wheel], 10.0)
	ok = ok and marks._next_segment == 1
	var first: Dictionary = marks._chunks[0].segments[0]
	ok = ok and first.colors[0].a == 0.0 and first.colors[2].a > 0.0
	# Поворот: общая кромка и непрерывные координаты текстуры.
	wheel.last_collision_point = Vector3(0.5, 0.0, 3.0)
	marks.update_wheels([wheel], 10.0)
	var second: Dictionary = marks._chunks[0].segments[1]
	ok = ok and first.vertices[2].is_equal_approx(second.vertices[0])
	ok = ok and first.vertices[3].is_equal_approx(second.vertices[1])
	ok = ok and is_equal_approx(first.end_distance, second.start_distance)
	# При восстановлении сцепления след постепенно заканчивается.
	wheel.slip_vector = Vector2.ZERO
	wheel.last_collision_point.z = 4.0
	marks.update_wheels([wheel], 10.0)
	var last: Dictionary = marks._chunks[0].segments[2]
	ok = ok and last.colors[0].a > 0.0 and last.colors[2].a == 0.0
	marks._process(1.0)
	ok = ok and marks._chunks[0].visual.mesh.get_surface_count() == 1
	# Разрыв контакта и телепортация не соединяются длинной полосой.
	wheel.contact = false
	marks.update_wheels([wheel], 10.0)
	wheel.contact = true
	wheel.last_collision_point.z = 30.0
	marks.update_wheels([wheel], 10.0)
	ok = ok and marks._next_segment == 3
	marks.road_surface = "Грязь"
	wheel.slip_vector = Vector2.ZERO
	wheel.last_collision_point.z = 31.0
	marks.update_wheels([wheel], 10.0)
	wheel.last_collision_point.z = 32.0
	marks.update_wheels([wheel], 10.0)
	ok = ok and marks._next_segment == 4
	ok = ok and marks._surface_kind(true, false) == "mud"
	marks.snow_cover = 1.0
	ok = ok and marks._surface_kind(false, true) == "snow"
	marks.snow_cover = 0.0
	ok = ok and marks._surface_kind(false, true) == "grass"
	marks.road_surface = "Гравий"
	ok = ok and marks._surface_kind(true, false) == "gravel"
	for i in range(Marks.CHUNK_SIZE * Marks.CHUNK_COUNT + 10):
		wheel.last_collision_point.z += 0.5
		marks.update_wheels([wheel], 10.0)
	var count := 0
	for chunk in marks._chunks:
		count += chunk.segments.size()
	ok = ok and count <= Marks.CHUNK_SIZE * Marks.CHUNK_COUNT
	wheel.free()
	ground.free()
	marks.free()
	if ok:
		print("PASS: покрытия, разрывы и ограниченный буфер следов")
		quit(0)
	else:
		printerr("FAIL: следы шин")
		quit(1)
