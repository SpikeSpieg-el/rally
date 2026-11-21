# Временный зонд: аркада — изгороди разрушаемые, коллизии на месте, без ошибок.
extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _walk(node: Node, stats: Dictionary) -> void:
	if node.has_method("item_count") and node.has_method("restore_all"):
		stats["managers"] += 1
		stats["items"] += int(node.call("item_count"))
	if node is StaticBody3D:
		var count := PhysicsServer3D.body_get_shape_count((node as StaticBody3D).get_rid())
		var key := String(node.name).rstrip("0123456789@").split("_")[0]
		stats["kinds"][key] = int(stats["kinds"].get(key, 0)) + count
	for child in node.get_children():
		_walk(child, stats)


func _run() -> void:
	var started := Time.get_ticks_msec()
	var packed: PackedScene = load("res://scenes/rally_arcade.tscn")
	var stage = packed.instantiate()
	root.add_child(stage)
	for i in range(900):
		await process_frame
	var stats := {"managers": 0, "items": 0, "kinds": {}}
	_walk(stage, stats)
	print("PROBE arcade ms=%d managers=%d items=%d" % [Time.get_ticks_msec() - started, stats["managers"], stats["items"]])
	print("PROBE arcade kinds=%s" % str(stats["kinds"]))
	stage.queue_free()
	await process_frame
	quit(0)
