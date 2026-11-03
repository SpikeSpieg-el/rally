# Проверка радио, обложек, шин и 3D-магнитолы без запуска звукового драйвера.
# godot --headless --path . --fixed-fps 120 --script res://tests/radio.gd
extends SceneTree

const RadioScript = preload("res://scripts/radio/rally_radio.gd")
const ConfigType = preload("res://scripts/data/rally_radio_config.gd")

const COVERS := [
	"res://textures/radio/night_stage.png",
	"res://textures/radio/gravel_ghost.png",
	"res://textures/radio/red_mist.png",
	"res://textures/radio/snow_line.png",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _run() -> void:
	# 1. Ресурс станции и разбор имён OGG. Имя трека берётся из файла,
	#    а не из жёстко зашитого списка: библиотеку можно пополнять.
	_check(FileAccess.file_exists("res://data/radio/default_radio.tres"),
		"нет ресурса настроек радио")
	var cfg: Resource = ResourceLoader.load("res://data/radio/default_radio.tres")
	_check(cfg != null and cfg is ConfigType, "ресурс радио имеет неверный скрипт")
	if cfg is ConfigType:
		var typed := cfg as ConfigType
		_check(typed.cover_paths.size() == 4, "должно быть четыре обложки")
		_check(typed.crossfade_seconds >= 1.0, "crossfade должен быть не короче секунды")
		_check(typed.music_volume_db < 0.0, "музыке нужен запас громкости")

	var radio = RadioScript.new()
	radio.set("config", ConfigType.new())
	var meta: Dictionary = radio.call("_metadata_for",
		"res://audio/music/4KPLAYA - Higher Love (SPOTISAVER).ogg")
	_check(String(meta.get("artist", "")) == "4KPLAYA", "исполнитель не разобран из имени OGG")
	_check(String(meta.get("title", "")) == "Higher Love", "название не разобрано из имени OGG")
	_check(String(meta.get("cover_path", "")).begins_with("res://textures/radio/"),
		"у трека должна быть обложка")
	_check(meta.get("accent") is Color, "у трека должен быть акцентный цвет")
	_check(not radio.call("_sort_by_path",
		{"path": "b.ogg"}, {"path": "a.ogg"}), "сортировка путей не работает")
	_check(float(radio.call("_gain_db", 1.0)) > -0.01,
		"equal-power gain 1.0 должен быть 0 дБ")
	_check(float(radio.call("_gain_db", 0.0)) <= -59.9,
		"нулевой gain кроссфейда должен уходить в тишину")

	# 2. Случайная колода не даёт один трек дважды подряд.
	var fake_tracks: Array[Dictionary] = []
	for i in range(12):
		fake_tracks.append({"path": "res://audio/music/%02d.ogg" % i})
	radio.set("tracks", fake_tracks)
	radio.set("_current_index", -1)
	var rng = radio.get("_rng")
	rng.seed = 12345
	radio.call("_refill_bag")
	var previous := -1
	for i in range(60):
		var index := int(radio.call("_pick_next_index"))
		_check(index >= 0 and index < fake_tracks.size(),
			"плейлист вернул индекс вне диапазона")
		_check(index != previous, "один трек не должен повторяться дважды подряд")
		previous = index
	radio.free()

	# 3. Автозагрузка, действия ввода и аудио-шины.
	var project_text := _read_text("res://project.godot")
	_check(project_text.contains("RallyRadio=\"*res://scripts/radio/rally_radio.gd\""),
		"в project.godot нет автозагрузки RallyRadio")
	_check(project_text.contains("radio_next={") and project_text.contains("radio_toggle={"),
		"нет действий N/M для радио")
	var bus_text := _read_text("res://default_bus_layout.tres")
	_check(bus_text.contains("bus/1/name = &\"Music\""), "нет шины Music")
	_check(bus_text.contains("bus/2/name = &\"Vehicle\""), "нет шины Vehicle")
	_check(bus_text.contains("AudioEffectLimiter_music")
		and bus_text.contains("AudioEffectLimiter_vehicle"),
		"на шинах Music/Vehicle должны быть ограничители")

	# 4. Обложки и их .import: Godot должен увидеть PNG без VRAM-пережатия.
	for path in COVERS:
		_check(FileAccess.file_exists(path), "нет обложки " + path)
		_check(FileAccess.file_exists(path + ".import"), "нет .import у " + path)
		var import_text := _read_text(path + ".import")
		_check(import_text.contains("importer=\"texture\""),
			"неверный импортёр у " + path)
		_check(import_text.contains("compress/mode=0"),
			"обложка должна импортироваться без потерь: " + path)
		_check(import_text.contains("source_file=\"" + path + "\""),
			"неверный source_file у " + path)

	# 5. Библиотека OGG живёт в main. На ветке без неё проверка пропускается,
	#    после слияния проверяем каждую пару .ogg/.ogg.import.
	var dir := DirAccess.open("res://audio/music")
	if dir == null:
		print("INFO: audio/music отсутствует в этой ветке — проверка OGG пропущена")
	else:
		var ogg_count := 0
		var import_count := 0
		for file_name in dir.get_files():
			if file_name.ends_with(".ogg"):
				ogg_count += 1
			elif file_name.ends_with(".ogg.import"):
				import_count += 1
				var import_text := _read_text("res://audio/music/" + file_name)
				_check(import_text.contains("loop=false"),
					"плейлист требует loop=false: " + file_name)
				_check(import_text.contains("importer=\"oggvorbisstr\""),
					"неверный импортёр OGG: " + file_name)
		_check(ogg_count > 0, "папка музыки пуста")
		_check(ogg_count == import_count,
			"у каждого OGG должен быть собственный .import")

	# 6. UI-карточка, HUD и 3D-магнитола подключены в сценах.
	var menu_text := _read_text("res://scenes/main_menu.tscn")
	_check(menu_text.contains("res://scripts/ui/rally_radio_card.gd")
		and menu_text.contains("node name=\"RadioCard\""),
		"в главном меню нет карточки «обложка + имя»")
	var hud_text := _read_text("res://scenes/ui/rally_hud.tscn")
	_check(hud_text.contains("node name=\"RadioCard\"")
		and hud_text.contains("compact = true"), "в HUD нет компактной карточки радио")
	var car_text := _read_text("res://scenes/rally_car.tscn")
	_check(car_text.contains("res://scripts/ui/rally_cockpit_radio.gd"),
		"в машине нет скрипта 3D-магнитолы")
	_check(car_text.contains("node name=\"RadioHeadUnit\"")
		and car_text.contains("parent=\"RallyCockpit/Dashboard/CenterConsole\""),
		"магнитола должна стоять на центральной консоли кабины")
	var cockpit_text := _read_text("res://scenes/rally_cockpit.tscn.tscn")
	_check(cockpit_text.contains("node name=\"RadioHeadUnit\""),
		"в отдельной сцене кабины нет магнитолы")
	var bindings_text := _read_text("res://scripts/input/input_bindings.gd")
	_check(bindings_text.contains("\"id\":\"radio_next\"")
		and bindings_text.contains("\"id\":\"radio_toggle\""),
		"настройки управления не знают о радио")
	var engine_text := _read_text("res://scripts/engine_sound.gd")
	_check(engine_text.contains("music_duck_db")
		and engine_text.contains("\"Vehicle\""),
		"двигатель не привязан к шине Vehicle и ducking радио")

	if failures.is_empty():
		print("PASS: радио, обложки, шины, кроссфейд и магнитола")
		quit(0)
	else:
		printerr("Ошибок: %d" % failures.size())
		quit(1)
