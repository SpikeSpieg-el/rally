# godot --headless --path . --script res://tests/scenery_resource_smoke.gd
# Runtime loads rather than preloads so a broken dependency returns a failure.
extends SceneTree

func _initialize() -> void:
	var scenery := ResourceLoader.load("res://data/stage/default_scenery.tres")
	var scene := ResourceLoader.load("res://scenes/rally_stage.tscn") as PackedScene
	var ok := scenery != null and scene != null
	if scenery != null:
		ok = ok and is_equal_approx(float(scenery.get("ground_cover_density")), 2.5)
		ok = ok and is_equal_approx(float(scenery.get("extra_grass_density")), 2.5)
	if not ok:
		printerr("FAIL: default scenery resource or rally stage could not be loaded")
	print("Scenery resource loading: ", "OK" if ok else "FAIL")
	quit(0 if ok else 1)
