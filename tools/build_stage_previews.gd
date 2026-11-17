# godot --headless --path . --script res://tools/build_stage_previews.gd
## Пакетная сборка 2D-планов трасс (PNG) в res://docs/previews/ средствами Godot.
## Обрабатывает все RallyTrackConfig из data/tracks/, у которых задана road_curve.
extends SceneTree

const PlanPreview = preload("res://scripts/track/stage_plan_preview.gd")
const TrackConfigType = preload("res://scripts/data/rally_track_config.gd")
const TRACKS_DIR := "res://data/tracks"


func _initialize() -> void:
	var dir: DirAccess = DirAccess.open(TRACKS_DIR)
	if dir == null:
		push_error("Не удалось открыть каталог трасс: %s" % TRACKS_DIR)
		quit(1)
		return
	var files: PackedStringArray = dir.get_files()
	files.sort()
	var built_count: int = 0
	for file_name in files:
		if not file_name.ends_with(".tres"):
			continue
		var res_path: String = TRACKS_DIR.path_join(file_name)
		var loaded: Resource = ResourceLoader.load(res_path)
		if not (loaded is TrackConfigType):
			continue
		var track: TrackConfigType = loaded as TrackConfigType
		if track.road_curve == null:
			continue
		var out_path: String = PlanPreview.export_for_track(track)
		if out_path.is_empty():
			push_error("Не удалось сохранить план для %s" % res_path)
			quit(1)
			return
		print("План сохранён: %s" % out_path)
		built_count += 1
	print("Готово планов: %d" % built_count)
	quit(0)
