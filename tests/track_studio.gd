# godot --headless --path . --script res://tests/track_studio.gd
## Проверки «Студии трассы» без самого редактора: вся математика разметки
## и все данные, на которые опирается плагин.
extends SceneTree

const Analysis = preload("res://scripts/track/route_analysis.gd")
const Settings = preload("res://scripts/data/rally_track_studio_settings.gd")
const Track = preload("res://scripts/data/rally_track_config.gd")
const Dock = preload("res://addons/rally_track_studio/dock.gd")


func _straight() -> Curve3D:
	var curve := Curve3D.new()
	curve.add_point(Vector3(0.0, 0.0, 0.0), Vector3.ZERO, Vector3(200.0, 0.0, 0.0))
	curve.add_point(Vector3(400.0, 0.0, 0.0), Vector3(-200.0, 0.0, 0.0), Vector3(200.0, 0.0, 0.0))
	curve.add_point(Vector3(800.0, 0.0, 0.0), Vector3(-200.0, 0.0, 0.0), Vector3.ZERO)
	return curve


func _elbow() -> Curve3D:
	var curve := Curve3D.new()
	curve.add_point(Vector3(0.0, 0.0, 0.0), Vector3.ZERO, Vector3(150.0, 0.0, 0.0))
	curve.add_point(Vector3(300.0, 0.0, 0.0), Vector3(-150.0, 0.0, 0.0), Vector3(0.0, 0.0, 150.0))
	curve.add_point(Vector3(300.0, 0.0, 300.0), Vector3(0.0, 0.0, -150.0), Vector3.ZERO)
	return curve


func _initialize() -> void:
	var settings = load("res://data/editor/track_studio.tres")
	assert(settings is RallyTrackStudioSettings, "ресурс настроек студии на месте")
	assert(settings.mode_names.size() == 4, "четыре режима: трасса, полотно, лес, зоны")
	assert(settings.surface_names.size() == settings.surface_colors.size(), "покрытия и цвета сходятся")
	assert(settings.hints_route.size() > 0 and settings.hints_props.size() > 0)
	# Быстродействие разметки: подсказка под курсором и «призрак» точки по
	# умолчанию выключены, а полигоны рисуются мелкими выпуклыми кусками.
	assert(not settings.show_cursor, "подсказка под курсором выключена по умолчанию")
	assert(not settings.show_ghost_point, "призрак новой точки выключен по умолчанию")
	assert(settings.profile_fill_max_quads >= 16, "заливка профиля — столбики")
	assert(settings.min_polygon_area > 0.0, "мелкие полигоны отбрасываются")

	var samples: Dictionary = Analysis.sample_curve(_straight(), settings.sample_step, settings.max_samples)
	var length: float = float(samples.get("length", 0.0))
	assert(absf(length - 800.0) < 1.0, "длина прямой трассы 800 м")
	assert(int(samples.get("points", PackedVector3Array()).size()) >= 8)

	# Километраж и точка по нему.
	var mid: Vector3 = Analysis.point_at_distance(samples, 400.0)
	assert(absf(mid.x - 400.0) < 2.0, "середина трассы на 400 м")
	assert(absf(Analysis.point_at_distance(samples, -50.0).x) < 1.0, "за началом — начало")
	assert(absf(Analysis.point_at_distance(samples, 5000.0).x - 800.0) < 2.0, "за концом — конец")

	# Ближайшая точка: смещение вбок и километраж.
	var probe: Dictionary = Analysis.nearest(samples, Vector3(200.0, 5.0, 3.0))
	assert(absf(float(probe.get("distance", 0.0)) - 200.0) < 6.0, "километраж ближайшей точки")
	assert(absf(float(probe.get("gap", 0.0)) - 3.0) < 0.5, "поперечный зазор 3 м")
	assert(absf(absf(float(probe.get("offset", 0.0))) - 3.0) < 0.5, "знаковое смещение 3 м")

	# Направление и повороты.
	var dir: Vector3 = Analysis.direction_at(samples.get("points", PackedVector3Array()), 20)
	assert(absf(dir.x) > 0.99, "прямая едет по +X")
	assert(absf(Analysis.signed_turn(Vector3.FORWARD, Vector3.FORWARD)) < 0.001)
	assert(Analysis.severity_for(30.0, 30.0, 165.0) == 6, "пологий поворот — 6")
	assert(Analysis.severity_for(165.0, 30.0, 165.0) == 1, "шпилька — 1")

	var elbow: Dictionary = Analysis.sample_curve(_elbow(), 2.0, 4000)
	var corners: Array = Analysis.find_corners(elbow, settings.corner_window,
		settings.corner_threshold_deg, settings.pace_note_min_angle, settings.pace_note_max_angle)
	assert(corners.size() >= 1, "в Г-образной трассе есть поворот")
	var corner: Dictionary = corners[0]
	assert(absf(float(corner.get("distance", 0.0)) - 300.0) < 60.0, "поворот около 300 м")
	assert(int(corner.get("severity", 0)) >= 1 and int(corner.get("severity", 9)) <= 6)
	assert(absf(int(corner.get("direction", 0))) == 1, "направление поворота задано")
	assert(float(corner.get("radius", 0.0)) > 0.0, "радиус поворота оценён")

	var warnings: Array = Analysis.find_warnings(elbow, corners, settings.min_radius_warning,
		settings.max_grade_warning, settings.min_gap_warning, settings.gap_along_margin)
	assert(warnings.size() >= 1, "узкий радиус попадает в предупреждения")
	for warning in warnings:
		assert(float(warning.get("distance", -1.0)) >= 0.0)
		assert(not String(warning.get("text", "")).is_empty())

	# Профиль, сводка и полосы покрытий.
	var profile: Dictionary = Analysis.profile(elbow, 64)
	assert(int(profile.get("values", PackedFloat32Array()).size()) == 64, "профиль по бинам")
	var stats: Dictionary = Analysis.stats(elbow, corners, settings.estimate_speed_kmh)
	assert(absf(float(stats.get("length", 0.0)) - float(elbow.get("length", 0.0))) < 0.01)
	assert(float(stats.get("seconds", 0.0)) > 0.0, "время проезда оценено")
	var flat_stats: Dictionary = Analysis.stats(samples, [], settings.estimate_speed_kmh)
	assert(float(flat_stats.get("max_grade", 1.0)) < 0.01, "на ровной трассе уклон нулевой")
	assert(int(flat_stats.get("corners", -1)) == 0)

	assert(Analysis.surface_index("Асфальт", settings.surface_names) == 1)
	assert(Analysis.surface_index("Нет такого", settings.surface_names) == 0)
	var fallback_bands: Array = Analysis.section_bands(null, 500.0, Color.WHITE)
	assert(fallback_bands.size() == 1, "без участков — одна полоса")
	assert(absf(float(fallback_bands[0].get("end", 0.0)) - 500.0) < 0.01)

	var forest = load("res://data/tracks/stage_forest2.tres") as Track
	assert(forest != null, "ресурс лесного этапа на месте")
	var bands: Array = Analysis.section_bands(forest, 1000.0, Color.WHITE)
	assert(bands.size() >= 1)
	assert(absf(float(bands[0].get("start", -1.0))) < 0.01, "полосы начинаются с нуля")
	assert(float(bands[bands.size() - 1].get("end", 0.0)) <= 1000.01)

	# Ползунки дока должны писать в реальные поля ресурса трассы.
	for entry in Dock.ROWS:
		var property := String(entry.get("property", ""))
		assert(not property.is_empty())
		var raw = forest.get(StringName(property))
		assert(raw is float or raw is int, "у трассы есть поле %s" % property)
		assert(float(entry.get("max", 0.0)) > float(entry.get("min", 0.0)))

	# «ЛЕС2» открывается в редакторе, а плагин включён в проекте.
	var scene_text := FileAccess.get_file_as_string("res://scenes/rally_stage2_forest.tscn")
	var stage_settings_text := FileAccess.get_file_as_string("res://scripts/data/rally_stage_settings.gd")
	assert(not scene_text.contains("preview_in_editor = false") and (scene_text.contains("preview_in_editor = true") or stage_settings_text.contains("var preview_in_editor: bool = true")), "у лесного этапа включён предпросмотр в редакторе")
	assert(scene_text.contains("stage_forest_route2.tres"), "сцена ссылается на кривую ЛЕС2")
	var project_text := FileAccess.get_file_as_string("res://project.godot")
	assert(project_text.contains("addons/rally_track_studio/plugin.cfg"), "плагин включён в проекте")
	var plugin_cfg := FileAccess.get_file_as_string("res://addons/rally_track_studio/plugin.cfg")
	assert(plugin_cfg.contains("script=\"plugin.gd\""), "у плагина есть точка входа")

	print("Track studio: OK")
	quit(0)
