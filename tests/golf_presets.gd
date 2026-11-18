# godot --headless --path . --script res://tests/golf_presets.gd
# Третья машина игры — Volkswagen Golf R32 Mk4: свой реестр, свои пресеты,
# свой атмосферный VR6 и свой банк звука. Плюс проверка того, из-за чего в
# гараже появлялись лишние машины: каждая сцена занята ровно одним ресурсом.
extends SceneTree

const GameScript = preload("res://scripts/game_state.gd")
const Config = preload("res://data/rally_game_config.tres")
const CarModels = preload("res://scripts/car_models.gd")
const EngineSoundScript = preload("res://scripts/engine_sound.gd")

## Отсечка VR6 3.2: выше неё мотор Golf не крутится ни в одном пресете.
const VR6_REDLINE := 6800.0

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _run() -> void:
	var config := Config.duplicate(true) as RallyGameConfig
	var sound := EngineSoundScript.new()

	# 1. Реестр машин: три машины, и каждая сцена занята ровно одной.
	#    Лишние записи вида «RALLY CAR2» появляются, когда сцена ничья, —
	#    например из-за race_scene в uid://, который не совпал с res:// путём.
	var ids := config.vehicle_ids()
	_check(ids.size() == 3, "в гараже три машины, найдено %d" % ids.size())
	_check(ids.has("mitsubishi") and ids.has("subaru") and ids.has("golf"),
		"реестр: Mitsubishi, Subaru и Golf")
	for id in ids:
		_check(not id.begins_with("rally_car"),
			"в реестре не должно быть автоматических записей: " + id)
	for path in CarModels.car_scene_paths():
		var owners: Array[String] = []
		for id in ids:
			var data: RallyVehicle = config.vehicle(id)
			if data != null and CarModels.scene_path(data.race_scene) == path:
				owners.append(id)
		_check(owners.size() == 1,
			"сцену %s должна занимать ровно одна машина, найдено %s" % [path, str(owners)])
	# Реестр не должен ничего добавлять: все сцены уже заняты ресурсами.
	var before: int = config.vehicles.size()
	CarModels.sync_registry(config)
	_check(config.vehicles.size() == before,
		"sync_registry не должен создавать машины поверх описанных (%d -> %d)"
		% [before, config.vehicles.size()])

	# 2. У Golf свой список пресетов и свой атмосферный VR6.
	var golf: RallyVehicle = config.vehicle("golf")
	_check(golf != null, "в реестре машин есть Golf")
	_check(config.has_vehicle("golf"), "has_vehicle видит Golf")
	var golf_count: int = config.setup_count("golf")
	_check(golf_count == 5, "у Golf пять своих пресетов, найдено %d" % golf_count)
	_check(config.setups_for("golf") != config.setups_for(),
		"список пресетов Golf не должен совпадать со списком Mitsubishi")
	_check(config.setups_for("golf") != config.setups_for("subaru"),
		"список пресетов Golf не должен совпадать со списком Subaru")
	var ids_seen := {}
	for i in range(golf_count):
		var preset := config.get_setup(i, "golf") as RallyCarSetup
		_check(preset != null, "пресет Golf должен читаться: %d" % i)
		if preset == null:
			continue
		_check(preset.engine_name.begins_with("VR6"),
			"мотор Golf должен называться VR6: " + preset.engine_name)
		_check(not preset.turbo, "у атмосферного VR6 нет турбины: " + preset.id)
		_check(preset.max_rpm <= VR6_REDLINE,
			"VR6 3.2 не крутится выше %.0f об/мин: %s (%.0f)"
			% [VR6_REDLINE, preset.id, preset.max_rpm])
		_check(preset.max_rpm >= 6000.0,
			"отсечка VR6 не должна быть ниже 6000 об/мин: " + preset.id)
		_check(preset.idle_rpm >= 700.0 and preset.idle_rpm <= 900.0,
			"холостой ход VR6 — 700…900 об/мин: " + preset.id)
		_check(preset.drivetrain == RallyCarSetup.Drivetrain.AWD,
			"у R32 полный привод 4MOTION: " + preset.engine_name)
		_check(preset.gear_ratios.size() == 6, "у Golf шестиступенчатая коробка: " + preset.id)
		var descending := true
		for gear in range(preset.gear_ratios.size() - 1):
			if preset.gear_ratios[gear] <= preset.gear_ratios[gear + 1]:
				descending = false
		_check(descending, "передаточные числа Golf идут по убыванию: " + preset.id)
		_check(not ids_seen.has(preset.id), "id пресетов Golf не повторяются: " + preset.id)
		ids_seen[preset.id] = true
		_check(preset.description.length() > 20, "у пресета Golf должно быть описание: " + preset.id)
		_check(preset.vehicle_mass >= 1400.0 and preset.vehicle_mass <= 1500.0,
			"R32 весит около 1450 кг: " + preset.id)

	# 3. Каждая машина — свой ресурс: сцена, банк лупов и одиночные звуки свои.
	var lancer: RallyVehicle = config.vehicle("mitsubishi")
	var subaru: RallyVehicle = config.vehicle("subaru")
	_check(golf != null and golf.race_scene.ends_with("rally_car2.tscn"),
		"Golf ездит на сцене rally_car2.tscn")
	_check(golf != null and lancer != null and golf.race_scene != lancer.race_scene,
		"у Golf своя игровая сцена")
	_check(golf != null and subaru != null and golf.race_scene != subaru.race_scene,
		"сцены Golf и Subaru не совпадают")
	_check(golf != null and golf.loops_dir("") == "res://audio/engine/golf/",
		"у Golf свой банк лупов")
	_check(golf != null and golf.events_dir("") == "res://audio/vehicle/golf/",
		"у Golf свои одиночные звуки")
	_check(golf != null and golf.loops_dir("") != subaru.loops_dir(""),
		"банк Golf не должен совпадать с банком Subaru")
	_check(golf != null and golf.engine_event_pitch < 1.0,
		"события VR6 звучат ниже записи")

	# 4. Сетка оборотов Golf своя: от 750 до 6500, и под каждую точку запечены
	#    оба режима нагрузки. Хлопков и blow-off у атмосферника нет.
	var grid: Array = golf.rpm_grid(sound.RPM_GRID) if golf != null else []
	_check(grid != sound.RPM_GRID, "у Golf своя сетка оборотов, а не сетка Mitsubishi")
	_check(grid.size() >= 20, "сетка Golf должна покрывать диапазон: %d точек" % grid.size())
	if not grid.is_empty():
		_check(int(grid[0]) == 750, "холостые VR6 — 750 об/мин")
		_check(int(grid[grid.size() - 1]) == 6500, "отсечка VR6 — 6500 об/мин")
		for i in range(grid.size() - 1):
			_check(int(grid[i]) < int(grid[i + 1]), "сетка оборотов Golf должна возрастать")
	var loops: String = golf.loops_dir(sound.ENGINE_DIR) if golf != null else ""
	for rpm in grid:
		for bank in ["light", "full"]:
			var path: String = "%sengine_%04d_%s.wav" % [loops, int(rpm), str(bank)]
			_check(FileAccess.file_exists(path), "нет лупа " + path)
			_check(FileAccess.file_exists(path + ".import"), "нет .import для " + path)
	var events: String = golf.events_dir(sound.VEHICLE_DIR) if golf != null else ""
	for one_shot in ["start.wav", "shift.wav"]:
		_check(FileAccess.file_exists(events + one_shot), "нет звука Golf " + one_shot)
	for turbo_only in ["bov_01.wav", "pop_01.wav"]:
		_check(not FileAccess.file_exists(events + turbo_only),
			"у атмосферника не должно быть " + turbo_only)

	# 5. Пресеты других машин не изменились.
	_check(config.setup_count() == 10, "у Mitsubishi должно остаться десять пресетов")
	_check(config.setup_count("mitsubishi") == 10, "список Mitsubishi не меняется")
	_check(config.setup_count("subaru") == 5, "у Subaru остаётся пять пресетов")

	# 6. RallyGame считает пресеты по выбранной машине.
	var game = GameScript.new()
	game.config = config
	game.conditions_path = "user://golf_presets_test.cfg"
	game.records_path = "user://golf_presets_records.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.conditions_path))
	root.add_child(game)
	_check(game.setup_count() == 10, "по умолчанию машина — Mitsubishi")
	game.select_vehicle("golf")
	_check(game.vehicle_id == "golf", "Golf выбирается в гараже")
	_check(game.setup_count() == golf_count, "у Golf свой список пресетов")
	var selected := game.get_custom_setup(game.setup_index) as RallyCarSetup
	_check(selected != null and selected.engine_name.begins_with("VR6"),
		"в гараже Golf выбирается пресет Golf")
	_check(selected != null and not selected.turbo,
		"в пресете Golf турбина выключена")
	game.select_vehicle("mitsubishi")
	_check(game.setup_count() == 10, "возврат к Mitsubishi возвращает его список")
	var back := game.get_custom_setup(game.setup_index) as RallyCarSetup
	_check(back != null and back.engine_name.begins_with("4G63T"),
		"в гараже Mitsubishi снова его мотор")

	# 7. Свои настройки Golf не попадают в списки других машин.
	game.select_vehicle("golf")
	var source := game.get_custom_setup(0) as RallyCarSetup
	_check(source != null, "пресет Golf читается")
	if source != null:
		source.max_torque = 360.0
		var saved: int = game.save_user_setup(0, source, "Мой VR6", true)
		_check(saved >= golf_count, "свой пресет Golf добавлен в конец его списка")
		_check(game.setup_count() == golf_count + 1, "список Golf вырос")
		game.select_vehicle("mitsubishi")
		_check(game.setup_count() == 10, "свой пресет Golf не попадает в список Mitsubishi")
		game.select_vehicle("subaru")
		_check(game.setup_count() == 5, "свой пресет Golf не попадает в список Subaru")
	game.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.conditions_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.records_path))
	sound.free()

	if failures.is_empty():
		print("PASS: у Golf свои пресеты, свой VR6 и свой банк звука; лишних машин в реестре нет")
		quit(0)
	else:
		printerr("Ошибок: %d" % failures.size())
		quit(1)
