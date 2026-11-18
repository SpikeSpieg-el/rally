# godot --headless --path . --script res://tests/car_liveries.gd
extends SceneTree

const Game = preload("res://scripts/game_state.gd")
const Garage = preload("res://scenes/garage_menu.tscn")
const Config = preload("res://data/rally_game_config.tres")
const Subaru = preload("res://scenes/rally_car3.tscn")
const Golf = preload("res://scenes/rally_car2.tscn")
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
	check(garage._livery_labels() == ["Заводская", "Тёмный", "Синий иташа", "Тёмный иташа"],
		"у Subaru четыре своих ливреи из её сцены")
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
	# Golf R32: своих ливрей нет, поэтому в гараже одна «заводская» краска, а тон
	# кузова ложится на поверхность кузова, не перекрывая стёкла и фонари.
	garage.select_vehicle("golf")
	check(garage._livery_textures().is_empty(), "у Golf нет текстур ливрей")
	check(garage._livery_labels() == ["Заводская"], "у Golf единственная краска — заводская")
	garage._refresh()
	var livery_choice: OptionButton = garage._controls["livery"] as OptionButton
	check(livery_choice != null and livery_choice.item_count == 1,
		"в списке ливрей Golf один пункт")
	check(livery_choice != null and livery_choice.disabled,
		"выбор ливреи у Golf недоступен: выбирать нечего")
	check(livery_choice != null and not livery_choice.tooltip_text.is_empty(),
		"недоступный выбор ливреи объясняется подсказкой")
	var golf_preview: Node3D = garage._vehicle_models.get("golf")
	var preview_paint := Visuals.body_mesh(golf_preview)
	check(preview_paint != null, "кузов Golf помечен группой покраски")
	if preview_paint != null and preview_paint.mesh != null:
		var factory := preview_paint.mesh.surface_get_material(0) as StandardMaterial3D
		var painted := preview_paint.get_surface_override_material(0) as StandardMaterial3D
		check(factory != null and painted != null and painted.albedo_color == factory.albedo_color,
			"нейтральный тон оставляет заводскую краску Golf")
	var golf_car = Golf.instantiate()
	golf_car.mouse_look_enabled = false
	golf_car.freeze = true
	root.add_child(golf_car)
	var tint := RallyCarSetup.new()
	tint.body_color = Color(0.75, 0.1, 0.15)
	tint.paint_finish = 1
	Visuals.apply_body(golf_car._find_body_model(), tint, [])
	var golf_paint := Visuals.body_mesh(golf_car._find_body_model())
	var golf_surface: StandardMaterial3D = null
	if golf_paint != null:
		golf_surface = golf_paint.get_surface_override_material(0) as StandardMaterial3D
	check(golf_surface != null and golf_surface.albedo_color == tint.body_color,
		"выбранный тон красит кузов Golf")
	check(golf_surface != null and is_equal_approx(golf_surface.roughness, 0.18),
		"покрытие «Глянец» работает и без ливрей")
	check(golf_paint != null and golf_paint.material_override == null,
		"стёкла и фонари Golf остаются со своими материалами")
	golf_car.free()
	garage.select_vehicle("mitsubishi")
	check(garage._livery_labels().size() == 3 and garage._livery_labels()[0] == "Ралли · красная", "переключение машины не смешивает ливреи")
	garage.free()
	game.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://liveries_test.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://liveries_records.cfg"))
	print("Ливреи: %d ошибок" % failures)
	quit(0 if failures == 0 else 1)
