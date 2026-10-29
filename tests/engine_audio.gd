# Проверка звуковой системы: наличие лупов, их корректность и логика выбора.
# godot --headless --path . --fixed-fps 120 --script res://tests/engine_audio.gd
extends SceneTree

const EngineSoundScript = preload("res://scripts/engine_sound.gd")
const CarScene = preload("res://scenes/rally_car.tscn")

const ENGINE_DIR := "res://audio/engine/"
const VEHICLE_DIR := "res://audio/vehicle/"
const EXPECTED_RATE := 32000
## Длительность лупа должна быть целым числом периодов вспышек (rpm/30),
## иначе на стыке будет слышен щелчок.
const MIN_LOOP_SECONDS := 0.9
const MAX_LOOP_SECONDS := 1.2
## Одиночные звуки (хлопки, сброс турбины, переключение, запуск): их нельзя
## зацикливать, иначе получится непрерывный треск.
const ONESHOT_NAMES := ["bov_01.wav", "bov_02.wav", "bov_03.wav", "shift.wav",
	"start.wav", "pop_01.wav", "pop_02.wav", "pop_03.wav", "pop_04.wav",
	"pop_05.wav", "pop_06.wav"]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _read_wav_header(path: String) -> Dictionary:
	"""Читает заголовок WAV: частота, каналы, число кадров и наличие smpl."""
	var result := {"rate": 0, "channels": 0, "frames": 0, "has_smpl": false}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result
	var bytes := file.get_buffer(file.get_length())
	file.close()
	if bytes.size() < 44:
		return result
	var riff := bytes.slice(0, 4).get_string_from_ascii()
	if riff != "RIFF":
		return result
	var pos := 12
	while pos + 8 <= bytes.size():
		var chunk_id := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var chunk_size := bytes.decode_u32(pos + 4)
		if chunk_id == "fmt ":
			result["channels"] = int(bytes.decode_u16(pos + 10))
			result["rate"] = int(bytes.decode_u32(pos + 12))
		elif chunk_id == "data":
			result["frames"] = chunk_size / 2
		elif chunk_id == "smpl":
			result["has_smpl"] = true
		pos += 8 + chunk_size + (chunk_size % 2)
	return result


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _run() -> void:
	var sound = EngineSoundScript.new()
	_check(sound != null, "скрипт звука должен создаваться")
	var grid: Array = sound.RPM_GRID
	_check(grid.size() >= 10, "сетка оборотов должна быть непустой")

	# 1. Для каждой точки сетки есть оба режима нагрузки.
	for rpm in grid:
		for bank in ["light", "full"]:
			var path := "%sengine_%04d_%s.wav" % [ENGINE_DIR, int(rpm), str(bank)]
			_check(FileAccess.file_exists(path), "нет лупа " + path)
			_check(FileAccess.file_exists(path + ".import"),
				"нет .import для " + path)
			if not FileAccess.file_exists(path):
				continue
			var header := _read_wav_header(path)
			_check(int(header["rate"]) == EXPECTED_RATE,
				"частота дискретизации в %s должна быть %d" % [path, EXPECTED_RATE])
			_check(int(header["channels"]) == 1, "%s должен быть моно" % path)
			var seconds := float(header["frames"]) / float(maxi(1, int(header["rate"])))
			_check(seconds >= MIN_LOOP_SECONDS and seconds <= MAX_LOOP_SECONDS,
				"длительность лупа %s вне диапазона: %.2f с" % [path, seconds])
			_check(bool(header["has_smpl"]),
				"в %s нет блока smpl, луп не будет бесшовным" % path)
			# Точки зацикливания в .import должны совпадать с длиной файла.
			var import_text := _read_text(path + ".import")
			_check(import_text.contains("edit/loop_mode=2"),
				"%s должен импортироваться как луп (edit/loop_mode=2)" % path)
			_check(import_text.contains("edit/loop_end=%d" % int(header["frames"])),
				"в .import для %s неверная точка конца лупа" % path)

	# 2. На диске нет лишних лупов: сетка в коде и в файлах совпадают.
	var dir := DirAccess.open(ENGINE_DIR)
	_check(dir != null, "нет папки с лупами")
	if dir != null:
		for file_name in dir.get_files():
			if not file_name.ends_with(".wav"):
				continue
			var stem := file_name.get_basename()
			var parts := stem.split("_")
			_check(parts.size() == 3, "неожиданное имя файла " + file_name)
			if parts.size() != 3:
				continue
			_check(grid.has(int(parts[1])),
				"файл %s не соответствует сетке оборотов" % file_name)

	# 3. Звуки машины на месте.
	for name in ["gravel_road.wav", "wind.wav", "shift.wav", "start.wav"]:
		_check(FileAccess.file_exists(VEHICLE_DIR + name),
			"нет звука машины " + name)
	for i in range(3):
		_check(FileAccess.file_exists(VEHICLE_DIR + "bov_%02d.wav" % (i + 1)),
			"нет звука сброса турбины bov_%02d.wav" % (i + 1))
	for i in range(6):
		_check(FileAccess.file_exists(VEHICLE_DIR + "pop_%02d.wav" % (i + 1)),
			"нет хлопка pop_%02d.wav" % (i + 1))

	# 4. Одиночные звуки не зациклены: иначе хлопок в выхлопе превращается
	#    в непрерывный треск.
	for name in ONESHOT_NAMES:
		var path := VEHICLE_DIR + name
		if not FileAccess.file_exists(path):
			continue
		var header := _read_wav_header(path)
		_check(not bool(header["has_smpl"]),
			"в %s не должно быть блока smpl: это одиночный звук" % path)
		var import_text := _read_text(path + ".import")
		_check(import_text.contains("edit/loop_mode=1"),
			"%s должен импортироваться без зацикливания (edit/loop_mode=1)" % path)

	# 5. Логика выбора лупа.
	_check(sound._grid_index(0.0) == 0, "на нулевых оборотах берётся первый луп")
	_check(sound._grid_index(100000.0) == grid.size() - 1,
		"на максимальных оборотах берётся последний луп")
	_check(sound._grid_index(int(grid[3])) == 3,
		"обороты из сетки должны выбирать свой луп")
	# Сетка геометрическая, поэтому граница между точками — геометрическое
	# среднее, а не арифметическое.
	var low_rpm := float(grid[3])
	var high_rpm := float(grid[4])
	var middle := sqrt(low_rpm * high_rpm)
	_check(sound._grid_index(int(middle * 0.99)) == 3,
		"между точками сетки берётся нижний луп")
	_check(sound._grid_index(int(middle * 1.01)) == 4,
		"выше геометрической середины берётся верхний луп")
	_check(is_equal_approx(sound._pitch_for(3, float(grid[3])), 1.0),
		"на оборотах своей точки сетки тон не корректируется")
	var corrected := sound._pitch_for(3, float(grid[3]) * 1.05)
	_check(corrected > 1.0, "питч-коррекция должна подтягивать тон вверх")
	var limit := float(sound.PITCH_LIMIT)
	_check(absf(sound._pitch_for(3, float(grid[3]) * 2.0) - (1.0 + limit)) < 0.001,
		"питч-коррекция ограничена, чтобы тембр не «плыл»")
	_check(sound._to_db(0.0) <= -59.0, "нулевая громкость должна давать тишину")
	_check(sound._to_db(1.0) > -0.1, "единичная громкость должна давать 0 дБ")

	# 6. Сетка оборотов должна быть возрастающей и логарифмической: только
	#    тогда питч-коррекция укладывается в предел на всём диапазоне.
	for i in range(grid.size() - 1):
		_check(int(grid[i]) < int(grid[i + 1]), "сетка оборотов должна возрастать")
	for i in range(grid.size() - 1):
		var low := float(grid[i])
		var high := float(grid[i + 1])
		var middle := sqrt(low * high)
		var error := absf(middle - low) / middle
		_check(error <= 0.055,
			"питч-коррекция не укладывается в предел между %d и %d об/мин"
			% [int(low), int(high)])
	_check(absf(sound._grid_index(1050.0) - 1) <= 1,
		"выбор лупа должен идти по ближайшей точке сетки")

	# 7. Гистерезис переключения: на границе двух точек сетки луп не должен
	#    прыгать туда-сюда, иначе двигатель «заикается».
	var low_index := grid.find(2850)
	var high_index := grid.find(3080)
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
	var bus_text := _read_text("res://default_bus_layout.tres")
	_check(bus_text.contains("AudioEffectLimiter"),
		"в раскладке шины должен быть AudioEffectLimiter")

	# 10. Машина содержит узел звука с нужным скриптом.
	var car := CarScene.instantiate()
	var audio_node := car.get_node_or_null("EngineAudio")
	_check(audio_node != null, "в сцене машины должен быть узел EngineAudio")
	if audio_node != null:
		_check(audio_node.get_script() == EngineSoundScript,
			"узел EngineAudio должен использовать скрипт звука")
	car.free()
	sound.free()

	if failures.is_empty():
		print("PASS: звуковые лупы, сетка оборотов и логика выбора")
		quit(0)
	else:
		printerr("Ошибок: %d" % failures.size())
		quit(1)
