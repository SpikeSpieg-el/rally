# godot --headless --path . --fixed-fps 120 --script res://tests/menu_terrain.gd
extends SceneTree

const Stage = preload("res://scenes/menu/menu_stage.tscn")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var stage := Stage.instantiate()
	root.add_child(stage)
	var terrain = stage.get_node("Ground")
	var track = stage.get_node("Track")
	var props = stage.get_node("Props")
	var car: CollisionObject3D = stage.get_node("RallyCar")
	await physics_frame
	var low := INF
	var high := -INF
	for h in terrain._heights:
		low = minf(low, h)
		high = maxf(high, h)
	check(high - low > 15.0, "созданы холмы")
	check(terrain.get_node("CollisionShape3D").shape != null, "у рельефа есть коллизия")
	check(track.curve.point_count >= 10, "у трассы есть несколько поворотов")
	check(props.get_child_count() >= 100, "создано лесное окружение")
	var min_prop_distance := INF
	var max_prop_float := 0.0
	for prop in props.get_children():
		if prop is Node3D:
			var prop_pos: Vector3 = prop.position
			min_prop_distance = minf(min_prop_distance, terrain.network.distance_to_road(prop_pos.x, prop_pos.z))
			max_prop_float = maxf(max_prop_float, absf(prop_pos.y - terrain.ground_height(prop_pos.x, prop_pos.z)))
	check(min_prop_distance > float(track.half_width) + 0.5, "объекты не стоят на дороге")
	check(max_prop_float < 0.15, "объекты посажены на рельеф")
	var max_lift := 0.0
	var road_hits := 0
	for i in range(200):
		var d: float = track.curve.get_baked_length() * (float(i) + 0.5) / 200.0
		var center: Vector3 = track.curve.sample_baked(d, true)
		for lateral in [-3.5, 0.0, 3.5]:
			var ahead: Vector3 = track.curve.sample_baked(fposmod(d + 1.0, track.curve.get_baked_length()), true)
			var direction := (ahead - center).normalized()
			var side := Vector3(direction.z, 0.0, -direction.x).normalized()
			var p: Vector3 = center + side * lateral
			var query := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 5.0, p + Vector3.DOWN * 5.0)
			query.exclude = [car.get_rid()]
			var hit: Dictionary = stage.get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty():
				max_lift = maxf(max_lift, hit.position.y - p.y)
				if hit.collider.name == "RoadSurface":
					road_hits += 1
	check(road_hits >= 590, "дорога, а не рельеф, под колёсами (попаданий %d/600)" % road_hits)
	check(max_lift < 0.3, "рельеф не торчит сквозь дорогу")
	print("menu_terrain: failures=%d, высоты %.1f..%.1f, покрытие %d/600, max_lift %.2f, prop_distance %.1f, prop_height_error %.2f" % [failures, low, high, road_hits, max_lift, min_prop_distance, max_prop_float])
	quit(1 if failures else 0)
