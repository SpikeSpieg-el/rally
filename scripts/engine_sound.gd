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

## Длительность кроссфейда между двумя лупами, с.
const CROSSFADE_TIME := 0.09
## Насколько допустимо тянуть тон лупа оборотными (питч-коррекция).
## Сетка логарифмическая, поэтому реальный разброс не превышает ~4.2 %.
const PITCH_LIMIT := 0.06
## Гистерезис переключения лупа: новый луп берём, только если он ближе к
## текущим оборотам хотя бы на столько (относительная разница ошибок).
## Без этого звук дёргается на границах сетки и звучит «заикающимся».
const SWITCH_MARGIN := 0.03
## Минимальный интервал между переключениями лупа, с.
const MIN_SWITCH_INTERVAL := 0.12
## Максимальная скорость изменения тона (доля/с): без неё на резком
## изменении оборотов слышены щелчки пересэмплинга.
const PITCH_SLEW := 1.2
## На сколько дБ приглушается двигатель при переключении передачи.
const SHIFT_DUCK_DB := 2.5
## Сколько одновременных одиночных звуков (хлопки, сброс турбины, передача).
const EVENT_SLOTS := 8
## Пауза перед повторным хлопком в выхлопе, с.
const POP_COOLDOWN := 0.6
## Пауза перед повторным сбросом турбины, с.
const BOV_COOLDOWN := 1.0
## Где стоит выхлоп относительно центра машины.
const EXHAUST_OFFSET := Vector3(0.0, 0.45, -1.85)


## Состояние одного банка лупов: два игрока, между которыми идёт кроссфейд.
class EngineBank:
	var bank_name: String = ""
	var players: Array = []
	var cur: int = 0
	var prev: int = -1
	var fade: float = 1.0
	var index: Array = [-1, -1]
	var pitch: Array = [1.0, 1.0]
	var cooldown: float = 0.0


@export_group("Громкость")
@export var enabled: bool = true
## Общая громкость звука машины, дБ.
@export var master_volume_db: float = -2.0
@export var engine_volume_db: float = -3.0
@export var road_volume_db: float = -14.0
@export var wind_volume_db: float = -23.0
@export var events_volume_db: float = -2.0

@export_group("Вид камеры")
## В кабине двигатель слышно ближе и громче.
@export var cockpit_engine_boost_db: float = 0.0
@export var cockpit_road_boost_db: float = 5.0
@export var cockpit_wind_boost_db: float = 4.0
## Вид сзади — наоборот, двигатель приглушён.
@export var chase_engine_boost_db: float = 0.0

@export_group("Расстояние")
## Радиус источника звука, м. Меньше — тише на расстоянии.
@export var unit_size: float = 4.0
@export var max_distance: float = 70.0
## Как звук затухает с расстоянием. Квадратичное затухание — физичное:
## из кабины мотор слышно близко, сзади — далеко и тихо.
@export_enum("Обратная", "Обратная квадратичная", "Логарифмическая", "Без затухания")
var attenuation_model: int = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
## Фильтр низких частот для удалённого звука: из-за капота мотор звучит
## глуше, чем в кабине.
@export var attenuation_lowpass_hz: float = 4000.0
@export var attenuation_lowpass_db: float = -18.0

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
var _bov_cooldown: float = 0.0
var _duck: float = 0.0
var _muted: bool = false

@onready var car: CarType = get_parent() as CarType


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
		for entry in bank.players:
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
	var wav := resource as AudioStreamWAV
	if wav != null:
		# Одиночный звук не должен повторяться: если бы он остался
		# зацикленным, хлопок в выхлопе превратился бы в непрерывный треск.
		wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
		wav.loop_begin = 0
		wav.loop_end = 0
	return resource as AudioStream


# ---------------------------------------------------------------------------
# Игроки
# ---------------------------------------------------------------------------


func _build_players() -> void:
	for bank_name in BANKS:
		var bank := EngineBank.new()
		bank.bank_name = str(bank_name)
		for i in range(2):
			var player := _make_player("Engine_%s_%d" % [str(bank_name), i])
			player.position = EXHAUST_OFFSET
			bank.players.append(player)
		_banks.append(bank)

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

	for i in range(EVENT_SLOTS):
		var player := _make_player("Event_%d" % i)
		player.position = EXHAUST_OFFSET
		_event_players.append(player)


func _make_player(node_name: String) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = node_name
	player.unit_size = unit_size
	player.max_distance = max_distance
	# Затухание по квадрату расстояния: из кабины мотор слышно близко,
	# сзади — далеко и тихо. Обратная зависимость (как в Godot по умолчанию)
	# на дистанции камеры почти не влияла, и звук был слишком громким.
	player.attenuation_model = attenuation_model
	player.attenuation_filter_cutoff_hz = attenuation_lowpass_hz
	player.attenuation_filter_db = attenuation_lowpass_db
	player.max_polyphony = 1
	player.volume_db = -60.0
	add_child(player)
	return player


# ---------------------------------------------------------------------------
# Основной цикл
# ---------------------------------------------------------------------------


func _process(delta: float) -> void:
	if not _audio_ready or car == null:
		return
	if not enabled:
		_mute(true)
		return
	_mute(false)

	var rpm: float = clampf(car.current_rpm, 0.0, 9000.0)
	var throttle: float = clampf(car.throttle_input, 0.0, 1.0)
	var speed: float = maxf(car.speed_kmh, 0.0)

	# Нагрузка: газ плюс доля от оборота. Чем больше нагрузка, тем звонче звук.
	var target_load: float = clampf(throttle * 0.88 + 0.12 * clampf(rpm / 7000.0, 0.0, 1.0), 0.0, 1.0)
	_load = lerpf(_load, target_load, clampf(delta * 9.0, 0.0, 1.0))

	# На время переключения передачи двигатель приглушается: так щелчок
	# переключения слышно, а не тонет в шуме мотора.
	if car.is_shifting:
		_duck = 1.0
	else:
		_duck = maxf(0.0, _duck - delta * 5.0)

	_update_engine(rpm, delta)
	_update_road(speed)
	_update_wind(speed)
	_update_events(rpm, throttle, delta)


func _mute(muted: bool) -> void:
	if muted == _muted:
		return
	_muted = muted
	for bank in _banks:
		for entry in bank.players:
			var player := entry as AudioStreamPlayer3D
			if player != null:
				player.volume_db = -60.0
	if _road_player != null:
		_road_player.volume_db = -60.0
	if _wind_player != null:
		_wind_player.volume_db = -60.0


func _update_engine(rpm: float, delta: float) -> void:
	# Заглохший двигатель больше не звучит как работающий на холостых.
	# Шум дороги и ветра остаётся слышен, если машина продолжает катиться.
	if car != null and car.engine_stalled:
		for bank in _banks:
			for entry in bank.players:
				var player := entry as AudioStreamPlayer3D
				if player != null:
					player.volume_db = -60.0
		return
	if _streams.is_empty():
		return
	var index := _grid_index(rpm)
	# Равномощностное смешивание режимов нагрузки: суммарная громкость
	# двигателя не «прыгает» при переходе от холостых к полному газу.
	var gains := {"light": sqrt(1.0 - _load), "full": sqrt(_load)}
	# Правка камеры задана в децибелах, поэтому её нельзя умножать на
	# линейную громкость — только складывать.
	var camera_db := _camera_engine_gain() - SHIFT_DUCK_DB * _duck
	for bank in _banks:
		var gain: float = float(gains.get(bank.bank_name, 0.0))
		_update_bank(bank, index, rpm, gain, camera_db, delta)


func _update_bank(bank: EngineBank, index: int, rpm: float, gain: float,
		camera_db: float, delta: float) -> void:
	var key := "%04d_%s" % [int(RPM_GRID[index]), bank.bank_name]
	var stream: AudioStream = _streams.get(key)
	if stream == null:
		return

	bank.cooldown = maxf(0.0, bank.cooldown - delta)

	# Выбор лупа с гистерезисом: на границе двух точек сетки звук не должен
	# прыгать туда-сюда, иначе появляется «заикание».
	var cur_index: int = int(bank.index[bank.cur])
	var target_index := index
	if cur_index >= 0 and target_index != cur_index:
		# Если текущий луп уже не вытягивает тон (резкий разгон), переключаемся
		# сразу: точность тона важнее защиты от дрожания.
		var error_now := absf(rpm / maxf(1.0, float(RPM_GRID[cur_index])) - 1.0)
		var urgent := error_now > PITCH_LIMIT
		if not urgent and (bank.cooldown > 0.0
				or not _worth_switch(cur_index, target_index, rpm)):
			target_index = cur_index

	if int(bank.index[bank.cur]) != target_index:
		_switch_loop(bank, target_index, rpm)

	var volume := master_volume_db + engine_volume_db + camera_db
	var cur_player: AudioStreamPlayer3D = bank.players[bank.cur]
	if bank.prev >= 0:
		var fade: float = minf(1.0, bank.fade + delta / CROSSFADE_TIME)
		bank.fade = fade
		var prev_player: AudioStreamPlayer3D = bank.players[bank.prev]
		# Равномощностный кроссфейд: сумма мощностей двух лупов постоянна,
		# поэтому в момент переключения нет ни провала, ни всплеска громкости.
		cur_player.volume_db = _to_db(gain * sin(fade * PI * 0.5)) + volume
		prev_player.volume_db = _to_db(gain * cos(fade * PI * 0.5)) + volume
		if fade >= 1.0:
			prev_player.stop()
			prev_player.volume_db = -60.0
			bank.index[bank.prev] = -1
			bank.prev = -1
			bank.fade = 1.0
	else:
		cur_player.volume_db = _to_db(gain) + volume

	# Питч-коррекция: тон лупа подтягиваем к текущим оборотам, чтобы звук
	# не «ступенчатовал» по сетке. Скорость изменения ограничена, иначе на
	# резких оборотах слышны щелчки пересэмплинга.
	for i in range(bank.players.size()):
		var idx: int = int(bank.index[i])
		if idx < 0:
			continue
		var player: AudioStreamPlayer3D = bank.players[i]
		var target := _pitch_for(idx, rpm)
		var current := float(bank.pitch[i])
		var step := PITCH_SLEW * delta
		var pitch := clampf(target, current - step, current + step)
		bank.pitch[i] = pitch
		player.pitch_scale = pitch


func _switch_loop(bank: EngineBank, index: int, rpm: float) -> void:
	var key := "%04d_%s" % [int(RPM_GRID[index]), bank.bank_name]
	var stream: AudioStream = _streams.get(key)
	if stream == null:
		return
	var cur := bank.cur
	var other := 1 - cur
	var player: AudioStreamPlayer3D = bank.players[other]
	player.stream = stream
	bank.pitch[other] = _pitch_for(index, rpm)
	player.pitch_scale = float(bank.pitch[other])
	player.volume_db = -60.0
	player.play()
	bank.index[other] = index
	bank.cooldown = MIN_SWITCH_INTERVAL
	if int(bank.index[cur]) >= 0:
		# Обычное переключение: старый луп доигрывает и гаснет.
		bank.prev = cur
		bank.cur = other
		bank.fade = 0.0
	else:
		# Первый запуск: кроссфейд не нужен.
		bank.cur = other
		bank.prev = -1
		bank.fade = 1.0


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


func _worth_switch(current: int, candidate: int, rpm: float) -> bool:
	"""Стоит ли менять луп: кандидат должен быть заметно ближе к оборотам."""
	if rpm <= 0.0:
		return false
	var current_error := absf(rpm - float(RPM_GRID[current])) / rpm
	var candidate_error := absf(rpm - float(RPM_GRID[candidate])) / rpm
	return candidate_error < current_error - SWITCH_MARGIN


func _pitch_for(index: int, rpm: float) -> float:
	var base := float(RPM_GRID[clampi(index, 0, RPM_GRID.size() - 1)])
	if base <= 0.0:
		return 1.0
	# Моторы, которые крутятся выше верхнего сэмпла (атмо 9000 об/мин),
	# продолжают «тянуться» вверх по питчу, а не упираются в потолок:
	# иначе на последней тысяче оборотов звук стоит на месте.
	var top := float(RPM_GRID[RPM_GRID.size() - 1])
	var limit: float = PITCH_LIMIT if rpm <= top else 0.25
	return clampf(rpm / base, 1.0 - limit, 1.0 + limit)


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
	_bov_cooldown = maxf(0.0, _bov_cooldown - delta)

	# Наддув оцениваем по оборотам и газу: точное давление в игре не
	# моделируется, но для звука хватает.
	var boost_target: float = clampf(rpm / 6500.0, 0.0, 1.0) * throttle
	_boost = lerpf(_boost, boost_target, clampf(delta * 3.0, 0.0, 1.0))

	var shifting: bool = car.is_shifting
	# Хлопки в выхлопе бывают только на сброс газа: если сыпать ими
	# постоянно, звук превращается в треск и мотор «захлёбывается».
	var lifted: bool = _prev_throttle > 0.5 and throttle < 0.1
	if lifted and not shifting and _turbo_enabled():
		if _boost > 0.3 and _bov_cooldown <= 0.0 and not _bov_streams.is_empty():
			_play_event(_bov_streams[randi() % _bov_streams.size()], 0.7, 0.06)
			_bov_cooldown = BOV_COOLDOWN
			_boost *= 0.2
		elif rpm > 3000.0 and _pop_cooldown <= 0.0 and not _pop_streams.is_empty():
			_play_event(_pop_streams[randi() % _pop_streams.size()], 0.6, 0.12)
			_pop_cooldown = POP_COOLDOWN
	_prev_throttle = throttle

	var gear: int = car.current_gear
	if gear != _prev_gear:
		_prev_gear = gear
		if _shift_stream != null:
			_play_event(_shift_stream, 0.9, 0.0)


## У атмосферного мотора нет blow-off и «антилаг»-хлопков: пресет мотора
## выключает их одним флагом turbo = false.
func _turbo_enabled() -> bool:
	if car == null or car.active_setup == null:
		return true
	return car.active_setup.turbo


func _play_event(stream: AudioStream, volume: float, pitch_jitter: float = 0.0) -> void:
	if stream == null:
		return
	for entry in _event_players:
		var player := entry as AudioStreamPlayer3D
		if player == null or player.playing:
			continue
		player.stream = stream
		player.volume_db = master_volume_db + events_volume_db + _to_db(volume)
		player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
		player.play()
		return
	# Все слоты заняты — лучше пропустить звук, чем оборвать уже играющий:
	# обрыв слышен как щелчок.


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
