# godot --headless --path . --script res://tests/mountain_sections.gd
extends SceneTree

func _initialize() -> void:
	var track = load("res://data/tracks/stage_mountain_100.tres")
	assert(track != null)
	assert(track.route_sections.size() == 11)
	assert(absf(track.get_route_length() - 100000.0) < 5.0)
	assert(track.section_at(0.0).weather.id == "clear")
	assert(track.section_at(50000.0).surface_name == "Снег")
	assert(track.section_at(99000.0).surface_name == "Асфальт")
	assert(is_equal_approx(track.half_width_at(40000.0), 2.4))
	assert(is_equal_approx(track.half_width_at(38000.0), 2.7))
	assert(track.half_width_at(38175.0) > 2.4)
	assert(track.half_width_at(38175.0) < 2.7)
	var last_width: float = track.half_width_at(0.0)
	for distance in range(1, 100001):
		var width: float = track.half_width_at(float(distance))
		assert(width >= 2.4 and width <= 4.6)
		assert(absf(width - last_width) < 0.02)
		last_width = width
	print("Mountain sections: OK")
	quit(0)
