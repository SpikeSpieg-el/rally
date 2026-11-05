# godot --headless --path . --script res://tests/subaru_presets.gd
# Свои пресеты Subaru: отдельный список, свой мотор и своя физика.
# Mitsubishi при этом остаётся ровно таким, каким был.
extends SceneTree

const GameScript = preload("res://scripts/game_state.gd")
const Config = preload("res://data/rally_game_config.tres")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _run() -> void:
	var config := Config.duplicate(true) as RallyGameConfig

	# 1. У Mitsubishi всё по-прежнему: десять пресетов, десять разных моторов.
	_check(config.setup_count() == 10, "у Mitsubishi должно остаться десять пресетов")
	_check(config.setup_count("mitsubishi") == 10, "список Mitsubishi не меняется")
	var lancer_names := {}
	for i in range(config.setup_count()):
		var preset := config.get_setup(i) as RallyCarSetup
		_check(
			preset != null and not preset.engine_name.is_empty(),
			"каждый пресет Mitsubishi содержит двигатель"
		)
		if preset != null:
			lancer_names[preset.engine_name] = true
			_check(
				not preset.engine_name.begins_with("EJ25"), "мотор Lancer не должен называться EJ25"
			)
	_check(lancer_names.size() == 10, "двигатели Mitsubishi различаются")

	# 2. У Subaru свой список и свой мотор EJ25.
	var subaru_count: int = config.setup_count("subaru")
	_check(subaru_count >= 3, "у Subaru должно быть несколько своих пресетов")
	_check(
		config.setups_for("subaru") != config.setups_for(),
		"список пресетов Subaru не должен совпадать со списком Mitsubishi"
	)
	var ids := {}
	for i in range(subaru_count):
		var preset := config.get_setup(i, "subaru") as RallyCarSetup
		_check(preset != null, "пресет Subaru должен читаться: %d" % i)
		if preset == null:
			continue
		_check(
			preset.engine_name.begins_with("EJ25"),
			"мотор Subaru должен называться EJ25: " + preset.engine_name
		)
		_check(
			preset.max_rpm <= 7200.0,
			"боксер EJ25 не крутится выше 7200 об/мин: " + preset.engine_name
		)
		_check(
			preset.drivetrain == RallyCarSetup.Drivetrain.AWD,
			"у Impreza полный привод: " + preset.engine_name
		)
		_check(not ids.has(preset.id), "id пресетов Subaru не повторяются: " + preset.id)
		ids[preset.id] = true
		_check(
			not lancer_names.has(preset.engine_name),
			"пресет Subaru не должен повторять мотор Lancer: " + preset.engine_name
		)
		_check(
			preset.description.length() > 20, "у пресета Subaru должно быть описание: " + preset.id
		)

	# 3. Пресеты не меняются при чтении списка другой машины.
	_check(
		config.get_setup(0).id != (config.get_setup(0, "subaru") as RallyCarSetup).id,
		"первый пресет Subaru — не пресет Lancer"
	)

	# 4. RallyGame считает пресеты по выбранной машине.
	var game = GameScript.new()
	game.config = config
	game.conditions_path = "user://subaru_presets_test.cfg"
	game.records_path = "user://subaru_presets_records.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.conditions_path))
	root.add_child(game)
	_check(game.setup_count() == 10, "по умолчанию машина — Mitsubishi")
	game.select_vehicle("subaru")
	_check(game.setup_count() == subaru_count, "у Subaru свой список пресетов")
	var selected := game.get_custom_setup(game.setup_index) as RallyCarSetup
	_check(
		selected != null and selected.engine_name.begins_with("EJ25"),
		"в гараже Subaru выбирается пресет Subaru"
	)
	game.select_vehicle("mitsubishi")
	_check(game.setup_count() == 10, "возврат к Mitsubishi возвращает его список")
	var back := game.get_custom_setup(game.setup_index) as RallyCarSetup
	_check(
		back != null and back.engine_name.begins_with("4G63T"),
		"в гараже Mitsubishi снова его мотор"
	)

	# 5. Свои настройки не смешиваются: список пользовательских записей
	#    хранится отдельно у каждой машины.
	game.select_vehicle("subaru")
	var source := game.get_custom_setup(0) as RallyCarSetup
	_check(source != null, "пресет Subaru читается")
	if source != null:
		source.max_torque = 500.0
		var saved: int = game.save_user_setup(0, source, "Мой ЭЖ", true)
		_check(saved >= subaru_count, "свой пресет Subaru добавлен в конец его списка")
		_check(game.setup_count() == subaru_count + 1, "список Subaru вырос")
		game.select_vehicle("mitsubishi")
		_check(game.setup_count() == 10, "свой пресет Subaru не попадает в список Mitsubishi")
	game.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://subaru_presets_test.cfg"))

	if failures.is_empty():
		print("PASS: у Subaru свои пресеты и свой мотор, Mitsubishi не изменён")
		quit(0)
	else:
		printerr("Ошибок: %d" % failures.size())
		quit(1)
