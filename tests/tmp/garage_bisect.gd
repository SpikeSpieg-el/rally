extends SceneTree

const GameScript = preload("res://scripts/game_state.gd")
const GarageScene = preload("res://scenes/garage_menu.tscn")
const Config = preload("res://data/rally_game_config.tres")

var garage


func _initialize() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _cut_row(img: Image) -> int:
	var h := img.get_height()
	var w := img.get_width()
	var first := h
	for y in range(h - 1, -1, -2):
		var noisy := 0
		for x in range(0, w - 2, 7):
			var a := img.get_pixel(x, y)
			var b := img.get_pixel(x + 1, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.08:
				noisy += 1
		if noisy * 7 > w * 0.6:
			first = y
		else:
			break
	return first


func _measure(label: String) -> void:
	await _frames(20)
	RenderingServer.force_draw(false)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var vimg: Image = garage.get_node("Preview/Viewport").get_texture().get_image()
	print("[bisect] ", label, ": root cut=", _cut_row(img), "/", img.get_height(), " vp cut=", _cut_row(vimg), "/", vimg.get_height())


func _toggle(path: String, on: bool) -> void:
	var n = garage.get_node(path)
	n.visible = on


func _run() -> void:
	var game = GameScript.new()
	game.config = Config
	root.add_child(game)
	garage = GarageScene.instantiate()
	root.add_child(garage)
	garage.open(Config, 0, game)
	garage.select_vehicle("mitsubishi")
	await _frames(40)
	await _measure("full")
	RenderingServer.force_draw(false)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	print("[bisect] format=", img.get_format(), " mip=", img.has_mipmaps(), " size=", img.get_size(), " raw cut=", _cut_row(img))
	var a := img.duplicate() as Image
	a.resize(960, 540, Image.INTERPOLATE_BILINEAR)
	print("[bisect] bilinear cut=", _cut_row(a), "/540")
	var b := img.duplicate() as Image
	b.resize(960, 540, Image.INTERPOLATE_LANCZOS)
	print("[bisect] lanczos cut=", _cut_row(b), "/540")
	var c := img.duplicate() as Image
	c.convert(Image.FORMAT_RGB8)
	c.resize(960, 540, Image.INTERPOLATE_BILINEAR)
	print("[bisect] rgb8+bilinear cut=", _cut_row(c), "/540")
	a.save_jpg("/tmp/shots/a.jpg", 0.72)
	var back := Image.load_from_file("/tmp/shots/a.jpg")
	print("[bisect] jpg reload cut=", _cut_row(back), "/540")
	c.save_jpg("/tmp/shots/c.jpg", 0.72)
	print("[bisect] c jpg reload cut=", _cut_row(Image.load_from_file("/tmp/shots/c.jpg")), "/540")
	quit(0)
