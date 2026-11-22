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
	RenderingServer.force_draw(false)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.resize(960, 540, Image.INTERPOLATE_BILINEAR)
	img.save_jpg("/tmp/shots/shot_%d.jpg" % index, 0.6)


func _run() -> void:
	var probe := ColorRect.new()
	probe.color = Color(0.8, 0.1, 0.1)
	probe.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(probe)
	await _frames(10)
	await _shot(9)
	probe.queue_free()
	var game = GameScript.new()
	game.config = Config
	root.add_child(game)
	var garage = GarageScene.instantiate()
	root.add_child(garage)
	garage.open(Config, 0, game)
	await _frames(60)
	await _shot(0)
	print("[diag] window=", root.size, " visible_rect=", root.get_visible_rect(), " garage=", garage.size, " preview=", garage.get_node("Preview").size, " vp=", garage.get_node("Preview/Viewport").size, " screen=", DisplayServer.screen_get_size(), " winsize=", DisplayServer.window_get_size())
	var vimg: Image = garage.get_node("Preview/Viewport").get_texture().get_image()
	print("[diag] vimg=", vimg.get_size())
	vimg.resize(960, 540)
	vimg.save_jpg("/tmp/shots/shot_6.jpg", 0.72)
	garage.open_group("engine")
	await _frames(30)
	await _shot(1)
	await _frames(90)
	await _shot(4)
	garage.open_group("tires")
	await _frames(120)
	await _shot(5)
	garage.close_group()
	garage.select_vehicle("subaru")
	await _frames(90)
	await _shot(2)
	var track = game.current_track.duplicate()
	track.ps1_style = false
	game.current_track = track
	garage._configure_preview_style()
	garage.select_vehicle("golf")
	await _frames(90)
	await _shot(3)
	quit(0)
