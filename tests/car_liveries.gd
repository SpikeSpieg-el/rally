# godot --headless --path . --script res://tests/car_liveries.gd
extends SceneTree

const Game = preload("res://scripts/game_state.gd")
const Garage = preload("res://scenes/garage_menu.tscn")
const Config = preload("res://data/rally_game_config.tres")
const Subaru = preload("res://scenes/rally_car2.tscn")
const Visuals = preload("res://scripts/car_visual_customization.gd")

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var old_game := root.get_node_or_null("RallyGame")
	if old_game != null:
		root.remove_child(old_game)
		old_game.queue_free()
	var game := Game.new()
	game.name = "RallyGame"
	game.config = Config.duplicate(true)
	game.conditions_path = "user://liveries_test.cfg"
	game.records_path = "user://liveries_records.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.conditions_path))
	root.add_child(game)
	var garage = Garage.instantiate()
	root.add_child(garage)
	garage.open(game.config, 0, game)
	check(garage._livery_labels().size() == 3, "у Mitsubishi три исходные ливреи")
	garage.select_vehicle("subaru")
	var preview: Node3D = garage._vehicle_models.get("subaru")
	check(garage._livery_labels() == ["Заводская"], "у Subaru только её исходная текстура")
	# Четыре тестовых текстуры имитируют расширенный список в сцене машины.
	var textures: Array[Texture2D] = [
		load("res://Subaru Impreza Coupe WRX Type R STi_suba1.png"),
		load("res://textures/иташа2.jpg"),
		load("res://textures/иташа.jpg"),
		load("res://textures/иташа3.jpg"),
	]
	preview.set_meta("livery_textures", textures)
	preview.set_meta("livery_names", ["Заводская", "Одна", "Две", "Три"])
	garage._refresh()
	check(garage._livery_labels() == ["Заводская", "Одна", "Две", "Три"], "названия берутся из выбранной машины")
	garage._create_copy()
	garage._on_choice_changed(3, "livery")
	var preview_body := Visuals.body_mesh(preview)
	check(preview_body != null and (preview_body.material_override as StandardMaterial3D).albedo_texture == textures[3], "четвёртая ливрея на витрине")
	check(garage._save_drafts(), "сохранение ливреи Subaru")
	var saved: int = garage.selected_index
	game.select_setup(saved)
	game.load_conditions()
	game._restore_saved_selection()
	var restored := game.get_custom_setup(game.setup_index) as RallyCarSetup
	check(restored != null and restored.livery == 3, "индекс больше двух переживает сохранение")
	var car = Subaru.instantiate()
	car.livery_textures = textures
	car.setup_override = restored
	car.mouse_look_enabled = false
	car.freeze = true
	root.add_child(car)
	var body := Visuals.body_mesh(car._find_body_model())
	check(body != null and (body.material_override as StandardMaterial3D).albedo_texture == textures[3], "та же ливрея в машине заезда")
	check(body.material_overlay != null, "эффекты кузова остаются при смене ливреи")
	restored.livery = 999
	car.apply_setup(restored)
	check((body.material_override as StandardMaterial3D).albedo_texture == textures[0], "неизвестный индекс возвращает первую ливрею")
	car.free()
	garage.select_vehicle("mitsubishi")
	check(garage._livery_labels().size() == 3 and garage._livery_labels()[0] == "Ралли · красная", "переключение машины не смешивает ливреи")
	garage.free()
	game.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://liveries_test.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://liveries_records.cfg"))
	print("Ливреи: %d ошибок" % failures)
	quit(0 if failures == 0 else 1)
