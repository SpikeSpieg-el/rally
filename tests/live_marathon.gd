# godot --headless --path . --script res://tests/live_marathon.gd
# Марафон, повтор, финиш и профиль «Живой ленты» без сборки тяжёлого мира.
extends SceneTree

const Config = preload("res://data/rally_game_config.tres")
const Generator = preload("res://scripts/track_generator.gd")
const MainScene = preload("res://scenes/main_menu.tscn")

class TestGame:
	extends "res://scripts/game_state.gd"
	var restarts := 0
	var starts := 0
	func start_race() -> void:
		starts += 1
	func restart_race() -> void:
		restarts += 1

class TestStage:
	extends "res://scripts/rally_stage.gd"
	func _ready() -> void:
		pass

var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var previous := root.get_node_or_null("RallyGame")
	if previous != null:
		root.remove_child(previous)
		previous.queue_free()
	var game := TestGame.new()
	game.name = "RallyGame"
	game.config = Config.duplicate(true)
	game.conditions_path = "user://marathon_test.cfg"
	game.records_path = "user://marathon_test_records.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.conditions_path))
	root.add_child(game)
	game.select_track(3)
	var selected_seed: int = int(game.current_track.get("generation_seed"))
	var menu = MainScene.instantiate()
	root.add_child(menu)
	check(menu._seed_box.visible and menu._marathon_choice.item_count == 3, "режимы показаны в меню Живой ленты")
	menu._marathon_choice.select(2)
	menu._marathon_choice.item_selected.emit(2)
	menu._on_garage_start(0, game.current_setup as RallyCarSetup)
	check(game.starts == 1 and game.marathon_seeds.size() == 5, "выбор пяти этапов запускается из гаража")
	menu.queue_free()
	game.clear_marathon()
	check(not game.begin_marathon(4), "только три или пять этапов")
	for count in [3, 5]:
		check(game.begin_marathon(count), "старт марафона")
		check(game.marathon_seeds.size() == count, "полный календарь")
		var seen := {}
		for value in game.marathon_seeds:
			seen[value] = true
		check(seen.size() == count, "разные случайные сиды")
		for i in range(count):
			var stage := TestStage.new()
			root.add_child(stage)
			stage._resolve_track()
			stage._resolve_track() # Повторное разрешение не меняет источник и сид.
			check(stage.track.generation_seed == game.marathon_seeds[i], "этап получает свой сид")
			check(stage.track.terrain_seed == game.marathon_seeds[i], "рельеф и кочки следуют сиду этапа")
			check(int(game.current_track.get("generation_seed")) == selected_seed, "сид одиночного заезда не меняется")
			var paused_seed := game.marathon_seed()
			stage._on_restart_pressed()
			check(game.marathon_seed() == paused_seed and game.marathon_times.size() == i, "рестарт не меняет сид или счёт")
			stage.results_panel = PanelContainer.new()
			stage.results_label = Label.new()
			stage.again_button = Button.new()
			stage.add_child(stage.results_panel)
			stage.results_panel.add_child(stage.results_label)
			stage.results_panel.add_child(stage.again_button)
			stage.stage_time = 100.0 + i
			stage._finish_stage()
			stage._finish_stage()
			check(game.marathon_times.size() == i + 1, "повторный финиш не засчитывается дважды")
			check(stage.results_label.text.contains("ОБЩЕЕ ВРЕМЯ"), "итог показан на финише")
			if i < count - 1:
				check(stage.again_button.text.contains("СЛЕДУЮЩИЙ"), "кнопка следующего этапа")
				stage._on_restart_pressed()
				stage._on_restart_pressed()
				check(game.marathon_index == i + 1, "переход ровно на один этап")
			else:
				check(not game.marathon_has_next(), "после последнего этапа продолжения нет")
				check(stage.results_label.text.contains("ЗАВЕРШЁН"), "показано завершение марафона")
			stage.queue_free()
		check(is_equal_approx(game.marathon_total(), count * 100.0 + count * (count - 1) / 2.0), "сумма времени всех этапов")
	game.clear_marathon()
	game.select_track(0)
	check(not game.begin_marathon(3), "на обычной трассе марафон не запускается")

	var live := Config.get_track(3).duplicate() as RallyTrackConfig
	var same := live.duplicate() as RallyTrackConfig
	var other := live.duplicate() as RallyTrackConfig
	other.generation_seed += 1
	var different := false
	var narrow := false
	var wide := false
	var last := live.half_width_at(0.0)
	for d in range(1, 8000):
		var width := live.half_width_at(float(d))
		check(is_equal_approx(width, same.half_width_at(float(d))), "ширина повторяется по сиду")
		check(absf(width - last) < 0.04, "ширина меняется плавно")
		narrow = narrow or width < live.road_half_width * 0.9
		wide = wide or width > live.road_half_width * 1.05
		different = different or not is_equal_approx(width, other.half_width_at(float(d)))
		last = width
	check(narrow and wide and different, "есть сужения, расширения и разные сиды")
	check(live.get_record_key().contains("_v2_"), "новая геометрия не использует старый рекорд")
	var sample_stage := TestStage.new()
	root.add_child(sample_stage)
	sample_stage.track = live
	live.terrain_seed = live.generation_seed
	other.terrain_seed = other.generation_seed
	var first_values: Array[float] = []
	for d in range(120, 2200, 5):
		first_values.append(sample_stage._surface_bumps_along(float(d)))
	sample_stage.track = other
	var bumps_differ := false
	var sample_index := 0
	for d in range(120, 2200, 5):
		bumps_differ = bumps_differ or not is_equal_approx(first_values[sample_index], sample_stage._surface_bumps_along(float(d)))
		sample_index += 1
	check(bumps_differ, "рисунок кочек зависит от сида")
	sample_stage.queue_free()
	var builder := Generator.Builder.new(12345, 2000.0, 2500.0, 15.0, 32.0)
	var climb: Array = builder._feature("steep_climb", 0.0)
	check(absf(float(climb[0][2]) / float(climb[0][1])) >= 0.09, "крутой подъём или спуск")
	check(builder._feature("hairpin", 0.0).size() == 3, "шпилька с полками")
	check(builder._feature("crest", 0.0).size() == 3, "гребень-трамплин")
	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://marathon_test.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://marathon_test_records.cfg"))
	if failures.is_empty():
		print("PASS: марафон и разнообразие Живой ленты")
		quit(0)
	else:
		printerr("FAIL: %d проблем(ы)" % failures.size())
		quit(1)
