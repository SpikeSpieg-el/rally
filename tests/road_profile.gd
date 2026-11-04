# godot --headless --path . --script res://tests/road_profile.gd
extends SceneTree

const Profile = preload("res://scripts/road_profile.gd")
const Track = preload("res://scripts/data/rally_track_config.gd")

func _initialize() -> void:
	# Golden samples shared with the Python authoring model.
	var fixtures: Array = [[150.0, 0.8845699062902813], [400.0, 0.14472225534957037],
		[750.0, 0.54105001829043], [1250.0, 0.0], [1710.0, -0.2682183224792603]]
	for pair in fixtures:
		assert(absf(Profile.sample(pair[0], 8123, 0.9, 320.0, 0.05, 0.015, 9.0) - pair[1]) < 0.000001)
	for name in ["forest", "pereval", "north_arc", "dynamic", "mountain_100"]:
		var track = load("res://data/tracks/stage_%s.tres" % name) as Track
		assert(track != null)
		var flat: int = 0
		var last: float = 0.0
		for i in range(40001):
			var value: float = Profile.sample(i * 0.25, track.terrain_seed,
				track.road_feature_height, track.road_feature_spacing,
				track.bumps_amplitude, track.bumps_roughness, track.bumps_wavelength, 10000.0)
			if absf(value) < 0.0001:
				flat += 1
			assert(absf(value - last) / 0.25 < 0.09)
			last = value
		assert(flat > 18000, "не меньше 45% дороги без добавленных неровностей")
		assert(last == 0.0, "ровный финиш")
	for kind in range(5):
		assert(absf(Profile.shape(0.0, kind)) < 0.000001)
		assert(absf(Profile.shape(1.0, kind)) < 0.000001)
	print("Road profile: OK")
	quit(0)
