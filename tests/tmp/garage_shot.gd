extends SceneTree

const GameScript = preload("res://scripts/game_state.gd")
const GarageScene = preload("res://scenes/garage_menu.tscn")
const ShowroomScene = preload("res://scenes/garage_showroom.tscn")
const Config = preload("res://data/rally_game_config.tres")


func _initialize() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _shot(index: int) -> void:
	RenderingServer.force_draw(false)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.resize(960, 540, Image.INTERPOLATE_BILINEAR)
	img.save_jpg("/tmp/shots/shot_%d.jpg" % index, 0.6)


func _run() -> void:
	# 0: сама сцена бокса без скрипта гаража — так её видит камера редактора.
	var showroom = ShowroomScene.instantiate()
	root.add_child(showroom)
	await _frames(30)
	await _shot(0)
	showroom.queue_free()
	await _frames(2)
	var game = GameScript.new()
	game.config = Config
	root.add_child(game)
	var garage = GarageScene.instantiate()
	root.add_child(garage)
	garage.open(Config, 0, game)
	garage.select_vehicle("mitsubishi")
	await _frames(60)
	await _shot(1)
	garage.open_group("engine")
	await _frames(120)
	await _shot(2)
	quit(0)
