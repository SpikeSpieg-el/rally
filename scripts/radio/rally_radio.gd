## Автозагрузка RallyRadio. Радио живёт между сценами: меню → загрузка →
## заезд → пауза → меню продолжают звучать без обрыва.
##
## Музыка НЕ загружается вся сразу: сканируются только имена OGG в
## res://audio/music, а два AudioStreamPlayer держат текущий и входящий трек.
## Переход идёт равномощностным кроссфейдом с наложением, порядок — случайная
## «колода» без повтора одного трека дважды подряд.
##
## Отдельные шины Music и Vehicle нужны, чтобы музыка, двигатель, гравий и
## ветер не боролись за один и тот же запас громкости на Master.
extends Node

const ConfigType = preload("res://scripts/data/rally_radio_config.gd")

const DEFAULT_CONFIG_PATH := "res://data/radio/default_radio.tres"
const FALLBACK_COVERS := [
	"res://textures/radio/night_stage.png",
	"res://textures/radio/gravel_ghost.png",
	"res://textures/radio/red_mist.png",
	"res://textures/radio/snow_line.png",
]

signal track_changed(track: Dictionary)
signal state_changed(playing: bool, muted: bool)

@export_file("*.tres") var config_path: String = DEFAULT_CONFIG_PATH
var config: ConfigType = null
## Текущая (уже объявленная в UI) композиция: path/title/artist/cover/accent.
var current_track: Dictionary = {}
var tracks: Array[Dictionary] = []
var is_muted: bool = false

var _players: Array[AudioStreamPlayer] = []
var _active: int = 0
var _incoming: int = -1
var _crossfading: bool = false
var _fade_elapsed: float = 0.0
var _fade_duration: float = 6.0
var _next_fade_duration: float = 6.0
var _current_index: int = -1
var _bag: Array[int] = []
var _rng := RandomNumberGenerator.new()
var _audio_ready: bool = true
var _music_bus_db: float = -1.0
var _bus_volume: float = -1.0
var _stream_cache: Dictionary = {}
var _cache_order: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_unhandled_input(true)
	_rng.randomize()
	_load_config()
	_music_bus_db = float(config.music_bus_db)
	_bus_volume = _music_bus_db
	_ensure_buses()
	_build_players()
	_scan_music()
	if DisplayServer.get_name() == "headless" or AudioServer.get_driver_name() == "Dummy":
		_audio_ready = false
	if tracks.is_empty():
		push_warning("RallyRadio: в %s нет OGG — радио будет молчать" % config.music_dir)
		return
	_start_track(_pick_next_index())


func _load_config() -> void:
	if ResourceLoader.exists(config_path):
		var loaded: Resource = ResourceLoader.load(config_path)
		if loaded is ConfigType:
			config = loaded as ConfigType
	if config == null:
		config = ConfigType.new()


# ---------------------------------------------------------------------------
# Шины
# ---------------------------------------------------------------------------


func _ensure_buses() -> void:
	_ensure_bus("Music", float(config.music_bus_db), -2.0)
	_ensure_bus("Vehicle", float(config.vehicle_bus_db), -3.0)


func _ensure_bus(bus_name: String, volume_db: float, ceiling_db: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")
	AudioServer.set_bus_volume_db(index, volume_db)
	if AudioServer.get_bus_effect_count(index) == 0:
		var limiter := AudioEffectLimiter.new()
		limiter.resource_name = bus_name + " Limiter"
		limiter.ceiling_db = ceiling_db
		limiter.threshold_db = -10.0
		AudioServer.add_bus_effect(index, limiter)


func _build_players() -> void:
	var bus_name := "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	for i in range(2):
		var player := AudioStreamPlayer.new()
		player.name = "RadioPlayer%d" % i
		player.bus = bus_name
		player.volume_db = -60.0
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		player.finished.connect(_on_player_finished.bind(i))
		_players.append(player)


# ---------------------------------------------------------------------------
# Плейлист
# ---------------------------------------------------------------------------


func _scan_music() -> void:
	tracks.clear()
	var dir := DirAccess.open(config.music_dir)
	if dir == null:
		push_warning("RallyRadio: папка не найдена: " + config.music_dir)
		return
	for file_name in dir.get_files():
		# В экспортированном проекте импортированные ресурсы представлены
		# файлами .ogg.remap; загружать их нужно по исходному пути .ogg.
		if file_name.ends_with(".ogg.remap"):
			file_name = file_name.trim_suffix(".remap")
		elif not file_name.ends_with(".ogg"):
			continue
		var path := config.music_dir.path_join(file_name)
		tracks.append(_metadata_for(path))
	# Стабильный порядок нужен только для проверок; проигрывание всё равно
	# перемешивается случайной колодой.
	tracks.sort_custom(Callable(self, "_sort_by_path"))


func _metadata_for(path: String) -> Dictionary:
	var stem := path.get_file().get_basename()
	stem = stem.replace(" (SPOTISAVER)", "").strip_edges()
	var artist := "RALLY FM"
	var title := stem
	var parts := stem.split(" - ", true, 1)
	if parts.size() > 1:
		artist = String(parts[0]).strip_edges()
		title = String(parts[1]).strip_edges()
	if title.is_empty():
		title = stem
	var cover_index := _cover_index(path)
	return {
		"path": path,
		"title": title,
		"artist": artist,
		"display_name": "%s — %s" % [artist, title],
		"cover_path": String(_covers()[cover_index]) if not _covers().is_empty() else "",
		"accent": _accent_for(cover_index),
		"cover_index": cover_index,
	}


func _sort_by_path(a: Dictionary, b: Dictionary) -> bool:
	return String(a.get("path", "")) < String(b.get("path", ""))


func _covers() -> Array:
	if config != null and not config.cover_paths.is_empty():
		return config.cover_paths
	return FALLBACK_COVERS


func _cover_index(path: String) -> int:
	var covers := _covers()
	if covers.is_empty():
		return 0
	return absi(path.hash()) % covers.size()


func _accent_for(index: int) -> Color:
	match index:
		0:
			return Color(1.0, 0.48, 0.08, 1.0)
		1:
			return Color(0.98, 0.34, 0.20, 1.0)
		2:
			return Color(1.0, 0.22, 0.18, 1.0)
		_:
			return Color(0.43, 0.82, 1.0, 1.0)


func _refill_bag() -> void:
	_bag.clear()
	for i in range(tracks.size()):
		_bag.append(i)
	for i in range(_bag.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var swap := int(_bag[i])
		_bag[i] = _bag[j]
		_bag[j] = swap
	# Крайняя карта выпадет первой: не даём ей совпасть с текущим треком.
	var last := _bag.size() - 1
	if last > 0 and int(_bag[last]) == _current_index:
		var first := int(_bag[0])
		_bag[0] = _bag[last]
		_bag[last] = first


func _pick_next_index() -> int:
	if tracks.is_empty():
		return -1
	if tracks.size() == 1:
		_current_index = 0
		return 0
	if _bag.is_empty():
		_refill_bag()
	var index := int(_bag.pop_back())
	if index == _current_index:
		if _bag.is_empty():
			_refill_bag()
		var retry := int(_bag.pop_back())
		_bag.append(index)
		index = retry
	_current_index = index
	return index


# ---------------------------------------------------------------------------
# Потоки и воспроизведение
# ---------------------------------------------------------------------------


func _load_stream(path: String) -> AudioStream:
	if _stream_cache.has(path):
		_touch_cache(path)
		return _stream_cache[path] as AudioStream
	if not ResourceLoader.exists(path):
		return null
	var stream := ResourceLoader.load(path) as AudioStream
	if stream == null:
		return null
	if stream is AudioStreamOggVorbis:
		stream.set("loop", false)
	_remember_stream(path, stream)
	return stream


func _touch_cache(path: String) -> void:
	_cache_order.erase(path)
	_cache_order.append(path)


func _remember_stream(path: String, stream: AudioStream) -> void:
	_stream_cache[path] = stream
	_touch_cache(path)
	var limit := maxi(2, int(config.stream_cache_size))
	while _cache_order.size() > limit:
		var old := String(_cache_order.pop_front())
		_stream_cache.erase(old)


func _start_track(index: int) -> void:
	if index < 0 or index >= tracks.size():
		return
	_stop_all()
	var stream := _load_stream(String(tracks[index]["path"]))
	if stream == null:
		return
	_active = 0
	_incoming = -1
	_crossfading = false
	current_track = tracks[index]
	var player := _players[_active]
	player.stream = stream
	player.volume_db = float(config.music_volume_db)
	_prepare_next_fade()
	if _audio_ready:
		player.play()
	track_changed.emit(current_track)
	state_changed.emit(is_playing(), is_muted)


func _begin_crossfade(duration: float) -> void:
	if tracks.is_empty():
		return
	var index := _pick_next_index()
	if index < 0:
		return
	if not _audio_ready:
		current_track = tracks[index]
		track_changed.emit(current_track)
		return
	var stream := _load_stream(String(tracks[index]["path"]))
	if stream == null:
		return
	# _active ещё не переключён: это и есть затухающий трек, отдельная
	# переменная не нужна (осталась бы объявленной, но неиспользованной).
	_incoming = 1 - _active
	var incoming := _players[_incoming]
	incoming.stream = stream
	incoming.volume_db = -60.0
	incoming.play()
	_fade_duration = clampf(duration, 0.8, 12.0)
	_fade_elapsed = 0.0
	_crossfading = true
	current_track = tracks[index]
	track_changed.emit(current_track)


func _prepare_next_fade() -> void:
	var variation := _rng.randf_range(0.85, 1.15)
	var duration := float(config.crossfade_seconds) * variation
	var player := _players[_active]
	if player.stream != null:
		var length := player.stream.get_length()
		if length > 0.0:
			duration = minf(duration, maxf(2.0, length * 0.30))
	_next_fade_duration = clampf(duration, 2.0, 10.0)


func _process(delta: float) -> void:
	_update_bus_fade(delta)
	if not _audio_ready or tracks.is_empty():
		return
	if _crossfading:
		_fade_elapsed += delta
		var t := clampf(_fade_elapsed / maxf(0.01, _fade_duration), 0.0, 1.0)
		var angle := t * PI * 0.5
		_players[_active].volume_db = float(config.music_volume_db) + _gain_db(cos(angle))
		_players[_incoming].volume_db = float(config.music_volume_db) + _gain_db(sin(angle))
		if t >= 1.0:
			_players[_active].stop()
			_players[_active].volume_db = -60.0
			_active = _incoming
			_incoming = -1
			_crossfading = false
			_players[_active].volume_db = float(config.music_volume_db)
			_prepare_next_fade()
		return
	var player := _players[_active]
	if player.playing and player.stream != null:
		var length := player.stream.get_length()
		if length > 0.0 and length - player.get_playback_position() <= _next_fade_duration + 0.15:
			_begin_crossfade(_next_fade_duration)


func _gain_db(linear: float) -> float:
	if linear <= 0.001:
		return -60.0
	return linear_to_db(clampf(linear, 0.001, 1.0))


func _update_bus_fade(delta: float) -> void:
	var index := AudioServer.get_bus_index("Music")
	if index < 0:
		return
	var target := -60.0 if is_muted else _music_bus_db
	_bus_volume = lerpf(_bus_volume, target, clampf(delta * 8.0, 0.0, 1.0))
	AudioServer.set_bus_volume_db(index, _bus_volume)


func _on_player_finished(index: int) -> void:
	if not _audio_ready or _crossfading:
		return
	if index == _active:
		_begin_crossfade(0.9)


func _stop_all() -> void:
	for player in _players:
		player.stop()
		player.volume_db = -60.0


# ---------------------------------------------------------------------------
# Публичный интерфейс для UI, HUD и магнитолы
# ---------------------------------------------------------------------------


func station_name() -> String:
	return config.station_name if config != null else "RALLY FM"


func station_tagline() -> String:
	return config.station_tagline if config != null else ""


func is_playing() -> bool:
	if not _audio_ready or is_muted:
		return false
	for player in _players:
		if player.playing:
			return true
	return false


func current_position() -> float:
	var index := _incoming if _crossfading and _incoming >= 0 else _active
	if index < 0 or index >= _players.size():
		return 0.0
	var player := _players[index]
	return player.get_playback_position() if player.playing else 0.0


func current_length() -> float:
	var index := _incoming if _crossfading and _incoming >= 0 else _active
	if index < 0 or index >= _players.size():
		return 0.0
	var stream := _players[index].stream
	return stream.get_length() if stream != null else 0.0


func skip_track() -> void:
	if tracks.is_empty() or _crossfading:
		return
	_begin_crossfade(1.25)


func set_muted(value: bool) -> void:
	if is_muted == value:
		return
	is_muted = value
	state_changed.emit(is_playing(), is_muted)


func toggle_mute() -> void:
	set_muted(not is_muted)


func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action("radio_next") and event.is_action_pressed("radio_next"):
		skip_track()
		get_tree().root.set_input_as_handled()
	elif InputMap.has_action("radio_toggle") and event.is_action_pressed("radio_toggle"):
		toggle_mute()
		get_tree().root.set_input_as_handled()
