# godot --headless --path . --fixed-fps 120 --script res://tests/live_track_selection.gd
# «Живая лента» делит сцену с ночным лесом. Заезд из меню обязан ехать
# выбранную процедурную трассу, а прямой запуск сцены (F6) — сценический
# track_override: именно из-за этой развилки выбор «ЖИВОЙ ЛЕНТЫ» раньше
# приводил в ночной лес.
extends SceneTree

const StageScene = preload("res://scenes/rally_stage.tscn")
const Config = preload("res://data/rally_game_config.tres")
const GameStateScript = preload("res://scripts/game_state.gd")

## Настоящая сцена и настоящий _enter_tree, но без тяжёлой сборки мира.
class MinimalStage:
	extends "res://scripts/rally_stage.gd"
	func _ready() -> void:
		pass


var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var existing := root.get_node_or_null("RallyGame")
	if existing != null:
		root.remove_child(existing)
		existing.queue_free()
	var game := GameStateScript.new()
	game.name = "RallyGame"
	game.config = Config.duplicate(true)
	game.conditions_path = "user://live_track_selection.cfg"
	game.records_path = "user://live_track_selection_records.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.conditions_path))
	root.add_child(game)

	var live_index := -1
	for i in range(game.track_count()):
		var track: Resource = game.get_track(i)
		if track != null and String(track.get("id")) == "dynamic_stage":
			live_index = i
	check(live_index >= 0, "«Живая лента» есть в конфиге")
	if live_index < 0:
		await _finish(game)
		return
	game.select_track(live_index)

	# Заезд из меню: сцена не подменяет выбранную трассу.
	game.set("_race_uses_selected_setup", true)
	var stage := StageScene.instantiate()
	var scene_override: Resource = stage.track_override
	stage.set_script(MinimalStage)
	stage.track_override = scene_override
	(stage.get_node("RallyCar") as RigidBody3D).freeze = true
	root.add_child(stage)
	stage._resolve_track()
	check(game.current_track != null and String(game.current_track.get("id")) == "dynamic_stage",
		"заезд из меню не подменяет трассу сценическим override")
	check(stage.track != null and String(stage.track.get("id")) == "dynamic_stage",
		"этап собирает выбранную «Живую ленту», а не ночной лес")
	stage.queue_free()
	await process_frame

	# Прямой F6: сценический track_override остаётся главным.
	game.set("_race_uses_selected_setup", false)
	var direct := StageScene.instantiate()
	var direct_override: Resource = direct.track_override
	direct.set_script(MinimalStage)
	direct.track_override = direct_override
	(direct.get_node("RallyCar") as RigidBody3D).freeze = true
	root.add_child(direct)
	direct._resolve_track()
	check(direct.track != null and String(direct.track.get("id")) == "forest_stage2",
		"прямой F6 берёт трассу из сцены")
	check(game.current_track != null and String(game.current_track.get("id")) == "forest_stage2",
		"прямой F6 возвращает сценическую трассу в RallyGame")
	direct.queue_free()
	await _finish(game)


func _finish(game: Node) -> void:
	if game != null:
		root.remove_child(game)
		game.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://live_track_selection.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://live_track_selection_records.cfg"))
	if failures.is_empty():
		print("PASS: выбор «Живой ленты» не подменяется ночным лесом")
		quit(0)
	else:
		printerr("FAIL: выбор трассы: %d проблем(ы)" % failures.size())
		quit(1)
