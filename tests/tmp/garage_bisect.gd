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
	var show = garage.get_node("Preview/Viewport/Showroom")
	for path in ["Callouts", "Shade", "Preview/Viewport/PostFX/RetroShaderRect", "Preview"]:
		_toggle(path, false)
		await _measure("hide " + path)
		_toggle(path, true)
	for child in show.get_children():
		if child is Node3D and not child is Camera3D:
			child.visible = false
			await _measure("hide 3D " + child.name)
			child.visible = true
	var room = show.get_node("Room")
	for child in room.get_children():
		child.visible = false
		await _measure("hide room " + child.name)
		child.visible = true
	for child in show.get_children():
		if child is Light3D:
			child.shadow_enabled = false
	await _measure("no shadows")
	var env: Environment = show.get_node("WorldEnvironment").environment
	print("[bisect] env glow=", env.glow_enabled, " ssao=", env.ssao_enabled, " fog=", env.fog_enabled, " volfog=", env.volumetric_fog_enabled, " tonemap=", env.tonemap_mode)
	show.get_node("WorldEnvironment").environment = null
	await _measure("no env")
	quit(0)
