# Звук двигателя и машины.
#
# Раньше здесь был генератор, который рисовал «пилообразную» гармонику с
# частотой rpm/60*2 — из-за этого звук был тонким и пискливым. Теперь
# используется банк заранее рассчитанных лупов: физическая модель выхлопной
# системы (импульсы выпуска -> 1D-волновод трубы -> глушитель) плюс шум
# механизма, турбина и индукция. Лупы лежат в res://audio/engine, они
# бесшовные и сделаны по той же сетке оборотов, что и реальный мотор.
#
# Что можно менять без правки кода:
#   * res://audio/engine/engine_<об/мин>_<light|full>.wav — сами лупы
#     (перегенерировать: python3 tools/render_engine_audio.py);
#   * res://audio/vehicle/*.wav — гравий, ветер, хлопки, сброс турбины;
#   * экспортируемые ниже уровни громкости и дистанции.
#
# Формат имени лупа: engine_<об/мин>_light.wav (сброс газа, холостые) и
# engine_<об/мин>_full.wav (полный газ). Если файла нет — этот режим
# молча пропускается, машина всё равно едет.
class_name RallyEngineSound
extends Node3D

const CarType = preload("res://scripts/rally_car.gd")

const ENGINE_DIR := "res://audio/engine/"
const VEHICLE_DIR := "res://audio/vehicle/"

## Сетка оборотов, для которой сделаны лупы. Должна совпадать с той, что
## использует tools/render_engine_audio.py.
const RPM_GRID := [900, 970, 1050, 1130, 1220, 1320, 1430, 1540, 1670, 1800, 1940, 2100,
	2270, 2450, 2640, 2850, 3080, 3330, 3600, 3880, 4190, 4530, 4890, 5280,
	5710, 6160, 6660, 7190, 7600]

## Режимы нагрузки: «light» — холостые/сброс газа, «full» — полный газ.
const BANKS := ["light", "full"]

const CROSSFADE_TIME := 0.075
## Насколько допустимо тянуть тон лупа оборотными (питч-коррекция).
## Сетка логарифмическая, поэтому реальный разброс не превышает ~4.2 %.
const PITCH_LIMIT := 0.06
## Где стоит выхлоп относительно центра машины.
const EXHAUST_OFFSET := Vector3(0.0, 0.45, -1.85)

@export_group("Громкость")
@export var enabled: bool = true
@export var master_volume_db: float = -4.0
@export var engine_volume_db: float = 0.0
@export var road_volume_db: float = -10.0
@export var wind_volume_db: float = -18.0
@export var events_volume_db: float = -2.0

@export_group("Вид камеры")
## В кабине двигатель слышно ближе и громче.
@export var cockpit_engine_boost_db: float = 3.0
@export var cockpit_road_boost_db: float = 5.0
@export var cockpit_wind_boost_db: float = 4.0
## Вид сзади — наоборот, двигатель приглушён.
@export var chase_engine_boost_db: float = -3.0

@export_group("Расстояние")
@export var unit_size: float = 6.0
@export var max_distance: float = 90.0

@onready var car: CarType = get_parent() as CarType

var _banks: Array = []
var _streams: Dictionary = {}
var _road_stream: AudioStream = null
var _wind_stream: AudioStream = null
var _road_player: AudioStreamPlayer3D = null
var _wind_player: AudioStreamPlayer3D = null
var _event_players: Array = []
var _bov_streams: Array = []
var _pop_streams: Array = []
var _shift_stream: AudioStream = null

var _audio_ready: bool = false
var _load: float = 0.0
var _prev_throttle: float = 0.0
var _prev_gear: int = 0
var _boost: float = 0.0
var _pop_cooldown: float = 0.0


func _ready() -> void:
	# Без звукового устройства (headless, CI) игра работает, но молчит.
	if DisplayServer.get_name() == "headless" or AudioServer.get_driver_name() == "Dummy":
		return
	_audio_ready = true
	_load_streams()
	_build_players()
	if car != null:
		_prev_gear = car.current_gear
		_prev_throttle = car.throttle_input


func _exit_tree() -> void:
	for player in _event_players:
		var audio := player as AudioStreamPlayer3D
		if audio != null:
			audio.stop()
	for bank in _banks:
		for entry in bank["players"]:
			var audio := entry as AudioStreamPlayer3D
			if audio != null:
				audio.stop()
	if _road_player != null:
		_road_player.stop()
	if _wind_player != null:
		_wind_player.stop()


# ---------------------------------------------------------------------------
# Загрузка ресурсов
# ---------------------------------------------------------------------------


func _load_streams() -> void:
	for rpm in RPM_GRID:
		for bank_name in BANKS:
			var path := "%sengine_%04d_%s.wav" % [ENGINE_DIR, int(rpm), str(bank_name)]
			var stream := _load_loop(path)
			if stream != null:
				_streams["%04d_%s" % [int(rpm), str(bank_name)]] = stream

	_road_stream = _load_loop(VEHICLE_DIR + "gravel_road.wav")
	_wind_stream = _load_loop(VEHICLE_DIR + "wind.wav")
	for i in range(3):
		var bov := _load_oneshot(VEHICLE_DIR + "bov_%02d.wav" % (i + 1))
		if bov != null:
			_bov_streams.append(bov)
	for i in range(6):
		var pop := _load_oneshot(VEHICLE_DIR + "pop_%02d.wav" % (i + 1))
		if pop != null:
			_pop_streams.append(pop)
	_shift_stream = _load_oneshot(VEHICLE_DIR + "shift.wav")


func _load_loop(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var resource: Resource = ResourceLoader.load(path)
	if resource == null:
		return null
	var wav := resource as AudioStreamWAV
	if wav != null:
		# Включаем бесшовное воспроизведение принудительно: не зависит от
		# настроек импорта и от того, есть ли в файле блок smpl.
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		var frames := int(wav.get_length() * float(wav.mix_rate))
		if frames > 1:
			wav.loop_end = frames
	return resource as AudioStream


func _load_oneshot(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var resource: Resource = ResourceLoader.load(path)
	return resource as AudioStream


# ---------------------------------------------------------------------------
# Игроки
# ---------------------------------------------------------------------------


func _build_players() -> void:
	for bank_name in BANKS:
		var players: Array = []
		for i in range(2):
			var player := _make_player("Engine_%s_%d" % [str(bank_name), i])
			player.position = EXHAUST_OFFSET
			players.append(player)
		_banks.append({
			"name": str(bank_name),
			"players": players,
			"cur": 0,
			"prev": -1,
			"fade": 1.0,
			"index": [-1, -1],
		})

	if _road_stream != null:
		_road_player = _make_player("RoadLoop")
		_road_player.stream = _road_stream
		_road_player.position = Vector3(0.0, 0.1, -1.4)
		_road_player.play()
	if _wind_stream != null:
		_wind_player = _make_player("WindLoop")
		_wind_player.stream = _wind_stream
		_wind_player.position = Vector3.ZERO
		_wind_player.play()

	for i in range(6):
		var player := _make_player("Event_%d" % i)
		player.position = EXHAUST_OFFSET
		_event_players.append(player)


func _make_player(node_name: String) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = node_name
	player.unit_size = unit_size
	player.max_distance = max_distance
	player.volume_db = -60.0
	add_child(player)
	return player


# ---------------------------------------------------------------------------
# Основной цикл
# ---------------------------------------------------------------------------


func _process(delta: float) -> void:
	if not _audio_ready or car == null:
		return
	var rpm: float = clampf(car.current_rpm, 0.0, 9000.0)
	var throttle: float = clampf(car.throttle_input, 0.0, 1.0)
	var speed: float = maxf(car.speed_kmh, 0.0)

	# Нагрузка: газ плюс доля от оборота. Чем больше нагрузка, тем звонче звук.
	var target_load: float = clampf(throttle * 0.88 + 0.12 * clampf(rpm / 7000.0, 0.0, 1.0), 0.0, 1.0)
	_load = lerpf(_load, target_load, clampf(delta * 9.0, 0.0, 1.0))

	_update_engine(rpm, delta)
	_update_road(speed)
	_update_wind(speed)
	_update_events(rpm, throttle, delta)


func _update_engine(rpm: float, delta: float) -> void:
	if _streams.is_empty():
		return
	var index := _grid_index(rpm)
	# Громкость по режимам нагрузки: «light» на холостых, «full» под нагрузкой.
	var gains := {"light": 1.0 - _load, "full": _load}
	# Правка камеры задана в децибелах, поэтому её нельзя умножать на
	# линейную громкость — только складывать.
	var camera_db := _camera_engine_gain()
	for bank in _banks:
		var bank_name: String = bank["name"]
		var gain: float = float(gains.get(bank_name, 0.0))
		_update_bank(bank, index, rpm, gain, camera_db, delta)


func _update_bank(bank: Dictionary, index: int, rpm: float, gain: float,
		camera_db: float, delta: float) -> void:
	var players: Array = bank["players"]
	var cur: int = bank["cur"]
	var key := "%04d_%s" % [int(RPM_GRID[index]), str(bank["name"])]
	var stream: AudioStream = _streams.get(key)
	if stream == null:
		return

	if int(bank["index"][cur]) != index:
		# Переключаем луп: свободный игрок берёт новый поток, идёт кроссфейд.
		var other: int = 1 - cur
		var other_player: AudioStreamPlayer3D = players[other]
		other_player.stream = stream
		other_player.pitch_scale = _pitch_for(index, rpm)
		other_player.volume_db = -60.0
		other_player.play()
		bank["index"][other] = index
		bank["prev"] = cur
		bank["cur"] = other
		bank["fade"] = 0.0

	# Питч-коррекция: тон лупа подтягиваем к текущим оборотам, чтобы звук
	# не «ступенчатовал» по сетке.
	for i in range(players.size()):
		var idx: int = bank["index"][i]
		if idx >= 0:
			var player: AudioStreamPlayer3D = players[i]
			player.pitch_scale = _pitch_for(idx, rpm)

	var volume := master_volume_db + engine_volume_db + camera_db
	var fade: float = minf(1.0, float(bank["fade"]) + delta / CROSSFADE_TIME)
	bank["fade"] = fade
	var prev: int = bank["prev"]
	var cur_player: AudioStreamPlayer3D = players[cur]
	if prev >= 0:
		var prev_player: AudioStreamPlayer3D = players[prev]
		cur_player.volume_db = _to_db(gain * fade) + volume
		prev_player.volume_db = _to_db(gain * (1.0 - fade)) + volume
		if fade >= 1.0:
			prev_player.stop()
			prev_player.volume_db = -60.0
			bank["index"][prev] = -1
			bank["prev"] = -1
			bank["fade"] = 1.0
	else:
		cur_player.volume_db = _to_db(gain) + volume


func _grid_index(rpm: float) -> int:
	var count := RPM_GRID.size()
	if count == 0:
		return 0
	if rpm <= float(RPM_GRID[0]):
		return 0
	if rpm >= float(RPM_GRID[count - 1]):
		return count - 1
	for i in range(count - 1):
		var low := float(RPM_GRID[i])
		var high := float(RPM_GRID[i + 1])
		if rpm < high:
			# Берём ближайшую точку в геометрическом смысле: так питч-коррекция
			# остаётся минимальной на всём диапазоне.
			if rpm * rpm > low * high:
				return i + 1
			return i
	return count - 1


func _pitch_for(index: int, rpm: float) -> float:
	var base := float(RPM_GRID[clampi(index, 0, RPM_GRID.size() - 1)])
	if base <= 0.0:
		return 1.0
	return clampf(rpm / base, 1.0 - PITCH_LIMIT, 1.0 + PITCH_LIMIT)


func _to_db(linear: float) -> float:
	if linear <= 0.001:
		return -60.0
	return linear_to_db(clampf(linear, 0.001, 1.0))


# ---------------------------------------------------------------------------
# Дорога и ветер
# ---------------------------------------------------------------------------


func _update_road(speed: float) -> void:
	if _road_player == null:
		return
	var amount: float = clampf(speed / 55.0, 0.0, 1.0)
	if speed < 1.0:
		amount = 0.0
	var gain: float = amount * amount * (0.45 + 0.55 * clampf(speed / 120.0, 0.0, 1.0))
	_road_player.volume_db = (_to_db(gain) + master_volume_db + road_volume_db
		+ _camera_road_gain())
	_road_player.pitch_scale = clampf(0.75 + speed / 110.0, 0.6, 2.2)


func _update_wind(speed: float) -> void:
	if _wind_player == null:
		return
	var amount: float = clampf(speed / 130.0, 0.0, 1.0)
	var gain: float = amount * amount
	_wind_player.volume_db = (_to_db(gain) + master_volume_db + wind_volume_db
		+ _camera_wind_gain())
	_wind_player.pitch_scale = clampf(0.8 + speed / 160.0, 0.6, 2.2)


# ---------------------------------------------------------------------------
# События: сброс турбины, хлопки, переключение передачи
# ---------------------------------------------------------------------------


func _update_events(rpm: float, throttle: float, delta: float) -> void:
	_pop_cooldown = maxf(0.0, _pop_cooldown - delta)

	# Наддув оцениваем по оборотам и газу: точное давление в игре не
	# моделируется, но для звука хватает.
	var boost_target: float = clampf(rpm / 6500.0, 0.0, 1.0) * throttle
	_boost = lerpf(_boost, boost_target, clampf(delta * 3.0, 0.0, 1.0))

	var lifted: bool = _prev_throttle > 0.45 and throttle < 0.12
	if lifted:
		if _boost > 0.25 and not _bov_streams.is_empty():
			_play_event(_bov_streams[randi() % _bov_streams.size()], 0.9)
			_boost = 0.0
		elif rpm > 2200.0 and not _pop_streams.is_empty() and _pop_cooldown <= 0.0:
			_play_event(_pop_streams[randi() % _pop_streams.size()], 0.75)
			_pop_cooldown = 0.12
	_prev_throttle = throttle

	var gear: int = car.current_gear
	if gear != _prev_gear:
		_prev_gear = gear
		if _shift_stream != null:
			_play_event(_shift_stream, 0.8)


func _play_event(stream: AudioStream, volume: float) -> void:
	for entry in _event_players:
		var player := entry as AudioStreamPlayer3D
		if player == null:
			continue
		if not player.playing:
			player.stream = stream
			player.volume_db = master_volume_db + events_volume_db + _to_db(volume)
			player.play()
			return
	# Все заняты — переиспользуем первого.
	if _event_players.is_empty():
		return
	var first := _event_players[0] as AudioStreamPlayer3D
	if first != null:
		first.stream = stream
		first.volume_db = master_volume_db + events_volume_db + _to_db(volume)
		first.play()


# ---------------------------------------------------------------------------
# Камера
# ---------------------------------------------------------------------------


func _camera_engine_gain() -> float:
	if car == null:
		return 0.0
	match car.camera_mode:
		0:  # вид сзади
			return chase_engine_boost_db
		1:  # капот
			return 0.0
		2:  # кабина
			return cockpit_engine_boost_db
	return 0.0


func _camera_road_gain() -> float:
	if car == null:
		return 0.0
	match car.camera_mode:
		0:
			return 0.0
		1:
			return 1.0
		2:
			return cockpit_road_boost_db
	return 0.0


func _camera_wind_gain() -> float:
	if car == null:
		return 0.0
	match car.camera_mode:
		0:
			return 0.0
		1:
			return 0.0
		2:
			return cockpit_wind_boost_db
	return 0.0
