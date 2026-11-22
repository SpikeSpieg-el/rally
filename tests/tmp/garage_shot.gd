extends SceneTree

const GameScript = preload("res://scripts/game_state.gd")
const GarageScene = preload("res://scenes/garage_menu.tscn")
const Config = preload("res://data/rally_game_config.tres")


func _initialize() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _shot(index: int) -> void:
	var img := root.get_texture().get_image()
	img.resize(960, 540, Image.INTERPOLATE_BILINEAR)
	img.save_jpg("/tmp/shot_%d.jpg" % index, 0.72)


func _run() -> void:
	var game = GameScript.new()
	game.config = Config
	root.add_child(game)
	var garage = GarageScene.instantiate()
	root.add_child(garage)
	garage.open(Config, 0, game)
	await _frames(60)
	_shot(0)
	garage.open_group("engine")
	await _frames(90)
	_shot(1)
	garage.close_group()
	garage.select_vehicle("subaru")
	await _frames(90)
	_shot(2)
	var track = game.current_track.duplicate()
	track.ps1_style = false
	game.current_track = track
	garage._configure_preview_style()
	garage.select_vehicle("golf")
	await _frames(90)
	_shot(3)
	quit(0)
