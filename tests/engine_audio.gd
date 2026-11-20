# Проверка звуковой системы: наличие лупов, их корректность и логика выбора.
# godot --headless --path . --fixed-fps 120 --script res://tests/engine_audio.gd
extends SceneTree

const EngineSoundScript = preload("res://scripts/engine_sound.gd")
const CarModels = preload("res://scripts/car_models.gd")
const CONFIG_PATH := "res://data/rally_game_config.tres"

const EXPECTED_RATE := 32000
## Длительность лупа должна быть целым числом периодов вспышек (rpm/30),
## иначе на стыке будет слышен щелчок.
const MIN_LOOP_SECONDS := 0.9
const MAX_LOOP_SECONDS := 1.2
## Одиночные звуки: их нельзя зацикливать, иначе получится непрерывный треск.
## Переключение и запуск нужны любой машине, хлопки и сброс турбины — только
## той, у которой есть турбо-пресет (у атмосферника их неоткуда взять).
const ONESHOT_ALWAYS := ["shift.wav", "start.wav"]
const ONESHOT_TURBO := ["bov_01.wav", "bov_02.wav", "bov_03.wav", "pop_01.wav",
	"pop_02.wav", "pop_03.wav", "pop_04.wav", "pop_05.wav", "pop_06.wav"]
## Общие шумы дороги и ветра: всегда из папки первой машины.
const SHARED_NAMES := ["gravel_road.wav", "wind.wav"]

var failures: Array[String] = []


## Реестр машин: откуда звук берёт папку лупов, сетку оборотов и события.
func _vehicle_config() -> RallyGameConfig:
	return load(CONFIG_PATH) as RallyGameConfig


## Есть ли у машины хотя бы один турбо-пресет: только тогда движок играет
## blow-off и хлопки в выхлопе, а значит и файлы должны лежать в её папке.
func _has_turbo_setup(config: RallyGameConfig, vehicle_id: String) -> bool:
	if config == null:
		return false
	for resource in config.setups_for(vehicle_id):
		var setup := resource as RallyCarSetup
		if setup != null and setup.turbo:
			return true
	return false


## Лупы одного банка: частота, моно, длина в целых периодах, smpl и .import.
func _check_loops(loops_dir: String, grid: Array, label: String) -> void:
	for rpm in grid:
		for bank in ["light", "full"]:
			var path: String = "%sengine_%04d_%s.wav" % [loops_dir, int(rpm), str(bank)]
			_check(FileAccess.file_exists(path), "нет лупа " + path)
			_check(FileAccess.file_exists(path + ".import"), "нет .import для " + path)
			if not FileAccess.file_exists(path):
				continue
			var header: Dictionary = _read_wav_header(path)
			_check(int(header["rate"]) == EXPECTED_RATE,
				"частота дискретизации в %s должна быть %d" % [path, EXPECTED_RATE])
			_check(int(header["channels"]) == 1, "%s должен быть моно" % path)
			var seconds: float = float(header["frames"]) / float(maxi(1, int(header["rate"])))
			_check(seconds >= MIN_LOOP_SECONDS and seconds <= MAX_LOOP_SECONDS,
				"длительность лупа %s вне диапазона: %.2f с" % [path, seconds])
			_check(bool(header["has_smpl"]),
				"в %s нет блока smpl, луп не будет бесшовным" % path)
			# Точки зацикливания в .import должны совпадать с длиной файла.
			var import_text: String = _read_text(path + ".import")
			_check(import_text.contains("edit/loop_mode=2"),
				"%s должен импортироваться как луп (edit/loop_mode=2)" % path)
			_check(import_text.contains("edit/loop_end=%d" % int(header["frames"])),
				"в .import для %s неверная точка конца лупа" % path)
	# Сетка в коде и файлы на диске совпадают: лишних лупов нет.
	var dir: DirAccess = DirAccess.open(loops_dir)
	_check(dir != null, "нет папки с лупами " + loops_dir)
	if dir == null:
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".wav"):
			continue
		var parts: PackedStringArray = file_name.get_basename().split("_")
		_check(parts.size() == 3, "%s: неожиданное имя файла %s" % [label, file_name])
		if parts.size() != 3:
			continue
		_check(grid.has(int(parts[1])),
			"%s: файл %s не соответствует сетке оборотов" % [label, file_name])


## Какие одиночные звуки нужны машине: хлопки и blow-off играет только мотор
## с турбиной, а у атмосферника их нет ни в пресетах, ни на диске.
func _one_shot_names(turbo: bool) -> Array:
	if turbo:
		return ONESHOT_ALWAYS + ONESHOT_TURBO
	return ONESHOT_ALWAYS.duplicate()


## Одиночные звуки одного банка: без smpl и без зацикливания в .import.
func _check_one_shots(events_dir: String, names: Array, label: String) -> void:
	for name in names:
		var path: String = events_dir + str(name)
		_check(FileAccess.file_exists(path), "%s: нет звука %s" % [label, path])
		if not FileAccess.file_exists(path):
			continue
		var header: Dictionary = _read_wav_header(path)
		_check(not bool(header["has_smpl"]),
			"в %s не должно быть блока smpl: это одиночный звук" % path)
		var import_text: String = _read_text(path + ".import")
		_check(import_text.contains("edit/loop_mode=1"),
			"%s должен импортироваться без зацикливания (edit/loop_mode=1)" % path)


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _read_wav_header(path: String) -> Dictionary:
	"""Читает заголовок WAV: частота, каналы, число кадров и наличие smpl."""
	var result: Dictionary = {"rate": 0, "channels": 0, "frames": 0, "has_smpl": false}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	if bytes.size() < 44:
		return result
	var riff: String = bytes.slice(0, 4).get_string_from_ascii()
	if riff != "RIFF":
		return result
	var pos: int = 12
	while pos + 8 <= bytes.size():
		var chunk_id: String = bytes.slice(pos, pos + 4).get_string_from_ascii()
		var chunk_size: int = bytes.decode_u32(pos + 4)
		if chunk_id == "fmt ":
			result["channels"] = int(bytes.decode_u16(pos + 10))
			result["rate"] = int(bytes.decode_u32(pos + 12))
		elif chunk_id == "data":
			# Половина размера чанка: деление намеренно целое (кадры, не секунды).
			@warning_ignore("integer_division")
			result["frames"] = chunk_size / 2
		elif chunk_id == "smpl":
			result["has_smpl"] = true
		pos += 8 + chunk_size + (chunk_size % 2)
	return result


func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _run() -> void:
	var sound = EngineSoundScript.new()
	_check(sound != null, "скрипт звука должен создаваться")
	var grid: Array = sound.RPM_GRID
	_check(grid.size() >= 10, "сетка оборотов должна быть непустой")

	# 1–4. Банк каждой машины реестра: свои лупы, своя сетка оборотов и свои
	#      одиночные звуки. Пути и сетка берутся из data/vehicles/*.tres, а не
	#      из констант кода, поэтому новая машина проверяется сама.
	var config := _vehicle_config()
	_check(config != null, "реестр машин должен читаться")
	if config == null:
		config = RallyGameConfig.new()
	var roster := config.vehicles
	_check(roster.size() >= 3, "в реестре должно быть не меньше трёх машин: %d" % roster.size())
	for resource in roster:
		var data := resource as RallyVehicle
		if data == null:
			continue
		var label: String = data.id
		var loops_dir: String = data.loops_dir(sound.ENGINE_DIR)
		var events_dir: String = data.events_dir(sound.VEHICLE_DIR)
		var own_grid: Array = data.rpm_grid(sound.RPM_GRID)
		_check(not loops_dir.is_empty(), "%s: не указана папка лупов" % label)
		_check(not events_dir.is_empty(), "%s: не указана папка одиночных звуков" % label)
		_check(own_grid.size() >= 10, "%s: сетка оборотов должна быть непустой" % label)
		# Сетка возрастает, а шаг между точками укладывается в предел питч-коррекции.
		for i in range(own_grid.size() - 1):
			_check(int(own_grid[i]) < int(own_grid[i + 1]),
				"%s: сетка оборотов должна возрастать" % label)
			var low: float = float(own_grid[i])
			var high: float = float(own_grid[i + 1])
			var middle: float = sqrt(low * high)
			_check(absf(middle - low) / middle <= 0.055,
				"%s: питч-коррекция не укладывается в предел между %d и %d об/мин"
				% [label, int(low), int(high)])
		# Отсечка сетки совпадает с отсечкой стокового пресета этой машины.
		var stock := config.get_setup(0, data.id) as RallyCarSetup
		_check(stock != null, "%s: у машины должен быть стоковый пресет" % label)
		if stock != null and not own_grid.is_empty():
			_check(int(own_grid[own_grid.size() - 1]) <= int(stock.max_rpm),
				"%s: последний луп (%d) не должен быть выше отсечки (%d)"
				% [label, int(own_grid[own_grid.size() - 1]), int(stock.max_rpm)])
			_check(int(own_grid[0]) <= int(stock.idle_rpm),
				"%s: первый луп (%d) должен покрывать холостые (%d)"
				% [label, int(own_grid[0]), int(stock.idle_rpm)])
		_check_loops(loops_dir, own_grid, label)
		# Хлопки и blow-off нужны только машине с турбо-пресетом.
		var turbo: bool = _has_turbo_setup(config, data.id)
		var names: Array = _one_shot_names(turbo)
		_check_one_shots(events_dir, names, label)
		if not turbo:
			for extra in ONESHOT_TURBO:
				_check(not FileAccess.file_exists(events_dir + str(extra)),
					"%s: у машины без турбо-пресетов не должно быть %s" % [label, str(extra)])

	# 4a. Общие шумы дороги и ветра лежат в папке первой машины: движок берёт
	#     их оттуда независимо от выбранного автомобиля.
	for name in SHARED_NAMES:
		_check(FileAccess.file_exists(sound.VEHICLE_DIR + str(name)),
			"нет общего звука " + str(name))

	# 5. Логика выбора лупа.
	_check(sound._grid_index(0.0) == 0, "на нулевых оборотах берётся первый луп")
	_check(sound._grid_index(100000.0) == grid.size() - 1,
		"на максимальных оборотах берётся последний луп")
	_check(sound._grid_index(int(grid[3])) == 3,
		"обороты из сетки должны выбирать свой луп")
	# Сетка геометрическая, поэтому граница между точками — геометрическое
	# среднее, а не арифметическое.
	var low_rpm: float = float(grid[3])
	var high_rpm: float = float(grid[4])
	var middle: float = sqrt(low_rpm * high_rpm)
	_check(sound._grid_index(int(middle * 0.99)) == 3,
		"между точками сетки берётся нижний луп")
	_check(sound._grid_index(int(middle * 1.01)) == 4,
		"выше геометрической середины берётся верхний луп")
	_check(is_equal_approx(sound._pitch_for(3, float(grid[3])), 1.0),
		"на оборотах своей точки сетки тон не корректируется")
	var corrected: float = sound._pitch_for(3, float(grid[3]) * 1.05)
	_check(corrected > 1.0, "питч-коррекция должна подтягивать тон вверх")
	var limit: float = float(sound.PITCH_LIMIT)
	_check(absf(sound._pitch_for(3, float(grid[3]) * 2.0) - (1.0 + limit)) < 0.001,
		"питч-коррекция ограничена, чтобы тембр не «плыл»")
	_check(sound._to_db(0.0) <= -59.0, "нулевая громкость должна давать тишину")
	_check(sound._to_db(1.0) > -0.1, "единичная громкость должна давать 0 дБ")

	# 6. Сетка оборотов должна быть возрастающей и логарифмической: только
	#    тогда питч-коррекция укладывается в предел на всём диапазоне.
	for i in range(grid.size() - 1):
		_check(int(grid[i]) < int(grid[i + 1]), "сетка оборотов должна возрастать")
	for i in range(grid.size() - 1):
		var low: float = float(grid[i])
		var high: float = float(grid[i + 1])
		var middle_loop: float = sqrt(low * high)
		var error: float = absf(middle_loop - low) / middle_loop
		_check(error <= 0.055,
			"питч-коррекция не укладывается в предел между %d и %d об/мин"
			% [int(low), int(high)])
	_check(absf(sound._grid_index(1050.0) - 1) <= 1,
		"выбор лупа должен идти по ближайшей точке сетки")

	# 7. Гистерезис переключения: на границе двух точек сетки луп не должен
	#    прыгать туда-сюда, иначе двигатель «заикается».
	var low_index: int = grid.find(2850)
	var high_index: int = grid.find(3080)
	_check(low_index >= 0 and high_index == low_index + 1,
		"в сетке должны быть точки 2850 и 3080")
	if low_index >= 0 and high_index == low_index + 1:
		_check(not sound._worth_switch(low_index, high_index, 2850.0),
			"на точке сетки переключать луп нельзя")
		_check(not sound._worth_switch(low_index, high_index, 3000.0),
			"в середине между точками луп меняться не должен (гистерезис)")
		_check(sound._worth_switch(low_index, high_index, 3060.0),
			"близко к следующей точке сетки луп должен смениться")
	_check(float(sound.SWITCH_MARGIN) > 0.0,
		"гистерезис переключения должен быть включён")
	_check(float(sound.MIN_SWITCH_INTERVAL) > 0.0,
		"минимальный интервал между переключениями должен быть включён")
	_check(float(sound.PITCH_SLEW) > 0.0,
		"скорость изменения тона должна быть ограничена")

	# 8. Микс не должен быть перегружен: громкость двигателя в сумме с
	#    общей не должна уходить в плюс.
	_check(float(sound.master_volume_db) + float(sound.engine_volume_db) <= 0.0,
		"двигатель не должен играть громче unity по сумме каналов")
	_check(float(sound.engine_volume_db) <= 0.0,
		"громкость двигателя должна быть выставлена в минус")
	_check(float(sound.unit_size) > 0.0 and float(sound.max_distance) > 0.0,
		"должны быть заданы размер источника и максимальная дистанция")
	_check(int(sound.attenuation_model) == 1,
		"звук должен затухать по квадрату расстояния")
	_check(int(sound.EVENT_SLOTS) >= 4,
		"должно быть достаточно слотов для одиночных звуков")

	# 9. На Master должен быть ограничитель, иначе сумма голосов даёт
	#    цифровые перегрузки и характерное потрескивание.
	_check(FileAccess.file_exists("res://default_bus_layout.tres"),
		"нет раскладки аудио-шины с ограничителем")
	var bus_text: String = _read_text("res://default_bus_layout.tres")
	_check(bus_text.contains("AudioEffectLimiter"),
		"в раскладке шины должен быть AudioEffectLimiter")

	# 9а. Радио и машина сведены раздельно: в кабине нет прежнего перегруза,
	#     а при звучащей музыке двигатель мягко уступает ей место.
	_check(float(sound.master_volume_db) + float(sound.engine_volume_db) <= -6.0,
		"общий запас громкости двигателя должен быть не менее 6 дБ")
	_check(float(sound.cockpit_road_boost_db) <= 2.0,
		"буст гравия в кабине больше не должен забивать микс")
	_check(float(sound.cockpit_wind_boost_db) <= 1.0,
		"буст ветра в кабине больше не должен забивать микс")
	_check(float(sound.music_duck_db) < 0.0,
		"двигатель должен мягко уступать место радио")
	_check(sound.has_method("_radio_is_playing"),
		"нет проверки активности радио для ducking")
	_check(bus_text.contains("bus/1/name = &\"Music\""),
		"музыка должна идти через отдельную шину Music")
	_check(bus_text.contains("bus/2/name = &\"Vehicle\""),
		"звуки машины должны идти через отдельную шину Vehicle")

	# 10. Узел звука есть в сцене каждой машины реестра.
	for scene_path in CarModels.car_scene_paths():
		var car_scene := load(scene_path) as PackedScene
		_check(car_scene != null, "сцена машины читается: " + scene_path)
		if car_scene == null:
			continue
		var car: Node = car_scene.instantiate()
		var audio_node: Node = car.get_node_or_null("EngineAudio")
		_check(audio_node != null,
			"в сцене %s должен быть узел EngineAudio" % scene_path.get_file())
		if audio_node != null:
			_check(audio_node.get_script() == EngineSoundScript,
				"узел EngineAudio в %s должен использовать скрипт звука"
				% scene_path.get_file())
		car.free()

	# 11. Предел сцепления: слой россыпи от скольжения и темпра покрытий.
	var gravel_t: Dictionary = EngineSoundScript.surface_timbre("gravel")
	var asphalt_t: Dictionary = EngineSoundScript.surface_timbre("asphalt")
	var mud_t: Dictionary = EngineSoundScript.surface_timbre("mud")
	_check(absf(float(gravel_t["gain_db"])) < 0.001,
		"гравий — базовая темпра шума дороги")
	_check(float(asphalt_t["gain_db"]) < float(gravel_t["gain_db"]),
		"на асфальте гравийный шум должен быть тише")
	_check(float(asphalt_t["pitch"]) > 1.0,
		"на асфальте шум выше по тону")
	_check(float(mud_t["pitch"]) < 1.0,
		"в грязи шум ниже и глухой")
	var unknown_t: Dictionary = EngineSoundScript.surface_timbre("basalt")
	_check(float(unknown_t["gain_db"]) == float(gravel_t["gain_db"]),
		"неизвестное покрытие должно звучать как гравий")
	var none_slip: float = EngineSoundScript.slip_spray_level(0.0, 0.12)
	var mid_slip: float = EngineSoundScript.slip_spray_level(0.3, 0.12)
	var full_slip: float = EngineSoundScript.slip_spray_level(1.0, 0.12)
	_check(none_slip <= 0.001, "без скольжения россыпь не слышна")
	_check(mid_slip > none_slip and full_slip > mid_slip,
		"россыпь должна расти со скольжением")
	_check(full_slip >= 0.99,
		"при полном скольжении россыпь должна быть полной")
	_check(float(sound.slip_boost_db) > 0.0,
		"слой россыпи должен добавлять громкость")
	_check(float(sound.slip_onset) > 0.0,
		"порог скольжения должен быть больше нуля")
	sound.free()

	if failures.is_empty():
		print("PASS: звуковые лупы, сетка оборотов и логика выбора")
		quit(0)
	else:
		printerr("Ошибок: %d" % failures.size())
		quit(1)
