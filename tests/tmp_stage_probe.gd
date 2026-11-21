# Временный зонд: настоящая сцена этапа после сборки — разрушаемые пропсы и коллизии.
extends SceneTree

const Collision = preload("res://scripts/track/prop_collision.gd")


func _initialize() -> void:
	call_deferred("_run")


func _walk(node: Node, stats: Dictionary) -> void:
	if node.has_method("item_count") and node.has_method("collidable_count") and node.has_method("restore_all"):
		stats["managers"] += 1
		stats["items"] += int(node.call("item_count"))
		stats["sensors"] += int(node.call("collidable_count"))
		stats["names"][node.name] = true
	if node is StaticBody3D:
		var count := PhysicsServer3D.body_get_shape_count((node as StaticBody3D).get_rid())
		stats["bodies"] += 1
		stats["shapes"] += count
		var key := String(node.name).split("_")[0]
		stats["kinds"][key] = int(stats["kinds"].get(key, 0)) + count
	for child in node.get_children():
		_walk(child, stats)


func _run() -> void:
	var started := Time.get_ticks_msec()
	var packed: PackedScene = load("res://scenes/rally_stage.tscn")
	var stage = packed.instantiate()
	root.add_child(stage)
	var deadline := Time.get_ticks_msec() + 240000
	while not stage._stage_live and Time.get_ticks_msec() < deadline:
		await process_frame
	print("PROBE live=%s build_ms=%d" % [str(stage._stage_live), Time.get_ticks_msec() - started])
	for i in range(30):
		await process_frame
	var stats := {"managers": 0, "items": 0, "sensors": 0, "bodies": 0, "shapes": 0, "kinds": {}, "names": {}}
	_walk(stage, stats)
	print("PROBE managers=%d items=%d sensors=%d bodies=%d shapes=%d cached_shapes=%d" % [
		stats["managers"], stats["items"], stats["sensors"], stats["bodies"], stats["shapes"], Collision.cached_shape_count()])
	print("PROBE kinds=%s" % str(stats["kinds"]))
	print("PROBE manager_names=%s" % str(stats["names"].keys()))
	print("PROBE corner_fence_breakable=%s" % str(stage.s_props().by_id(stage.s_spawn().corner_fence_prop_id).breakable))
	stage.queue_free()
	await process_frame
	quit(0)
