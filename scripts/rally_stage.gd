## Одна универсальная сцена заезда.
##
## Трасса задана кривой в узле Route (Path3D) и параметрами ресурса
## data/tracks/*.tres. Меши земли и полотна собираются из них, а ассеты
## лежат обычными узлами в Props и ManualProps — их видно и можно двигать
## прямо в 3D-вьюпорте.
##
## Инвариант, из-за которого дорога больше не может пробить рельеф:
## высота ЛЮБОЙ точки мира считается одной функцией _height_at():
##     высота = высота_оси_дороги + рельеф * плавный_переход(расстояние_до_дороги)
## Внутри полотна переход = 0, поэтому земля ровно равна дороге, а за обочиной
## плавно (не круче embankment_slope_deg) уходит в холмы.
##
## Редактор: скрипт помечен @tool. В инспекторе есть две кнопки —
## «Пересобрать трассу» (пересчитать меши по текущей кривой) и «Посадить
## ассеты на землю» (поставить ассеты из Props/ManualProps на меш земли).
## Свои объекты кладутся руками в ManualProps — генератор их не трогает.
@tool
class_name RallyStage
extends Node3D

const CarType = preload("res://scripts/rally_car.gd")
const TrackConfigType = preload("res://scripts/data/rally_track_config.gd")
const CarSetupType = preload("res://scripts/data/rally_car_setup.gd")
const WeatherType = preload("res://scripts/data/rally_weather_config.gd")
const ProfileType = preload("res://scripts/data/rally_track_profile.gd")
const GameConfigType = preload("res://scripts/data/rally_game_config.gd")
const RoadNetworkType = preload("res://scripts/road_network.gd")
const RoadSurfaceType = preload("res://scripts/road_surface.gd")
var surface_state = RoadSurfaceType.new()

const TireMarksType = preload("res://scripts/tire_marks.gd")
const GroundShader = preload("res://shaders/forest_ground.gdshader")
const RoadShader = preload("res://shaders/gravel_road.gdshader")
const GroundTexture = preload("res://textures/environment/forest_floor.png")
const GravelTexture = preload("res://textures/environment/gravel.png")
const NeedleTexture = preload("res://textures/environment/needles.png")
const RockTexture = preload("res://textures/environment/rock.png")
const SpeedShader = preload("res://shaders/speed_fx.gdshader")
const WeatherMotionShader = preload("res://shaders/weather_motion.gdshader")
const NightSkyShader = preload("res://shaders/night_sky.gdshader")
const RoadSignScene = preload("res://scenes/props/road_sign.tscn")

@export_group("Данные (перетащите ресурсы в инспектор)")
@export var game_config: GameConfigType = null
@export var track_override: TrackConfigType = null
@export var car_setup_override: CarSetupType = null

@export_group("Редактор")
## Собирать трассу сразу при открытии сцены в редакторе.
@export var preview_in_editor: bool = true
@export_tool_button("Пересобрать трассу") var rebuild_button = rebuild_preview
@export_tool_button("Посадить ассеты на землю") var snap_button = snap_props_to_ground
## Автоматически ставить ассеты из Props/ManualProps на землю при сборке.
@export var snap_props_on_build: bool = true

@export_group("Стилизация и ощущение скорости")
## Сила мягкой ретро-палитры (0 — оригинальные цвета).
@export_range(0.0, 1.0, 0.05) var retro_style_strength: float = 0.35
## Общая интенсивность скоростного размытия и виньетки.
@export_range(0.0, 2.0, 0.05) var speed_effect_strength: float = 1.0
## Насыщенность ближнего слоя дождя/снега на скорости.
@export_range(0.0, 2.0, 0.05) var weather_motion_strength: float = 1.0
## Плотность мировых частиц осадков (относительно пресета погоды).
@export_range(0.1, 2.0, 0.1) var precipitation_density: float = 1.0

@export_group("Отладка")
@export var show_debug_info: bool = false

@onready var world_environment: WorldEnvironment = get_node_or_null("WorldEnvironment") as WorldEnvironment
@onready var sun_light: DirectionalLight3D = get_node_or_null("SunLight") as DirectionalLight3D
@onready var terrain: StaticBody3D = get_node_or_null("Terrain") as StaticBody3D
@onready var terrain_mesh: MeshInstance3D = get_node_or_null("Terrain/TerrainMesh") as MeshInstance3D
@onready var terrain_collider: CollisionShape3D = get_node_or_null("Terrain/TerrainCollider") as CollisionShape3D
@onready var generated: Node3D = get_node_or_null("Generated") as Node3D
@onready var hud: CanvasLayer = get_node_or_null("HUD") as CanvasLayer

var track: TrackConfigType = null
var setup: CarSetupType = null
## Погода и «характер трассы» текущего заезда (из автозагрузки RallyGame).
var weather: WeatherType = null
var track_profile: ProfileType = null
var car: CarType = null
var network: RoadNetworkType = null
var terrain_rect: Rect2 = Rect2()
var start_pos: Vector3 = Vector3.ZERO
var finish_pos: Vector3 = Vector3.ZERO
var start_dir: Vector3 = Vector3.FORWARD
var finish_dir: Vector3 = Vector3.FORWARD

var checkpoints: Array = []
var cp_triggered: Array[bool] = []
var cp_times: Array[float] = []
var last_cp_index: int = -1

var stage_time: float = 0.0
var timer_running: bool = false
var stage_finished: bool = false
var is_paused: bool = false
var best_time: float = 0.0
var is_new_record: bool = false
var speed_fx_material: ShaderMaterial = null
var weather_motion_material: ShaderMaterial = null
var _weather_phase: float = 0.0
## Осадки (дождь/снег) летят вокруг машины, а не по всей карте.
var _weather_particles: GPUParticles3D = null
## Условия уже наложены на копию трассы: повторный _resolve_track не должен
## умножать сцепление и кочки второй раз.
var _track_prepared := false
var _hud_ready := false
## Мир этапа готов, физика/HUD можно тикать (await в _ready разбил старт на кадры).
var _stage_live := false
var _prev_lin_vel: Vector3 = Vector3.ZERO
var _frame_delta: float = 0.016

# Автопересборка в редакторе: как только правка кривой/настроек затихла,
# трасса пересобирается сама (кнопка остаётся для ручного пересчёта).
const REBUILD_DELAY := 0.45
var _rebuild_pending: bool = false
var _rebuild_timer: float = 0.0
var _pending_from_track: bool = false
var _watched_curve: Curve3D = null
var _built_curve_signature: float = NAN

var _ground_grid := PackedFloat32Array()
var _ground_origin := Vector2.ZERO
var _ground_cell: float = 2.0
var _ground_cols: int = 0
var _ground_rows: int = 0

var _noise_hills: FastNoiseLite = null
var _noise_ridge: FastNoiseLite = null
var _noise_detail: FastNoiseLite = null
var _noise_bumps: FastNoiseLite = null
var _rng := RandomNumberGenerator.new()

# HUD-узлы живут в scenes/ui/rally_hud.tscn (разметка правится в редакторе),
# в _setup_hud() мы только находим их по путям и держим ссылки для _update_hud.
var timer_label: Label = null
var split_label: Label = null
var stage_label: Label = null
var best_label: Label = null
var speed_label: Label = null
var gear_label: Label = null
var drivetrain_label: Label = null
var rpm_bar: ProgressBar = null
var telemetry_label: Label = null
var throttle_bar: GaugeBar = null
var brake_bar: GaugeBar = null
var steer_bar: GaugeBar = null
var slip_bar: GaugeBar = null
var suspension_bar: GaugeBar = null
var gforce_bar: GaugeBar = null
var mini_map: MiniMap = null
var pause_panel: Control = null
var results_panel: Control = null
var results_label: Label = null
var hint_label: Label = null
var resume_button: Button = null
var again_button: Button = null
var pause_buttons: Array[Button] = []
var speed_rect: ColorRect = null


func _enter_tree() -> void:
	# Родительский _enter_tree выполняется раньше _ready дочерней машины:
	# успеваем передать конфигурацию, назначенную в инспекторе сцены.
	if Engine.is_editor_hint():
		return
	var game: Node = get_node_or_null("/root/RallyGame")
	if game == null:
		return
	if car_setup_override != null:
		game.set("current_setup", car_setup_override)
	if track_override != null:
		game.set("current_track", track_override)


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(true)
		if preview_in_editor:
			rebuild_preview()
		_watch_sources()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resolve_track()
	# На время генерации машина заморожена и _process молчит: физика и
	# телеметрия не тикают по «пустому» миру.
	var car_node := get_node_or_null("RallyCar") as RigidBody3D
	if car_node != null:
		car_node.freeze = true
	await _build_world_async()
	_configure_car()
	var marks = TireMarksType.new()
	marks.name = "TireMarks"
	marks.road_surface = track.surface_name
	marks.snow_cover = _weather_snow_cover()
	marks.wetness = _weather_wetness()
	add_child(marks)
	if car != null:
		car.tire_marks = marks
	_setup_precipitation()
	if car_node != null:
		car_node.freeze = false
	_setup_hud()
	_stage_live = true
	_update_hud()
	var game: Node = get_node_or_null("/root/RallyGame")
	if game != null and game.has_method("finish_loading"):
		game.call("finish_loading")


func _exit_tree() -> void:
	if get_tree() != null and not Engine.is_editor_hint():
		get_tree().paused = false


## Кнопка «Пересобрать трассу» в инспекторе (и предпросмотр в редакторе).
## Тот же пересчёт запускается автоматически, когда правка кривой затихла.
func rebuild_preview() -> void:
	if not is_inside_tree():
		return
	var started: int = Time.get_ticks_msec()
	_resolve_track()
	_build_world()
	_built_curve_signature = _curve_signature(_effective_curve())
	_watch_sources()
	if Engine.is_editor_hint() and network != null:
		var curve: Curve3D = _effective_curve()
		print("Трасса пересобрана: %.0f м, точек кривой %d, %.1f с" % [
			network.total_length,
			curve.point_count if curve != null else 0,
			float(Time.get_ticks_msec() - started) / 1000.0,
		])
		if track != null and curve != null and track.road_curve != curve:
			push_warning(
				"Кривая в узле Route отличается от road_curve в %s: мини-карта в меню "
				% track.resource_path + "будет рисовать старую. Назначьте эту же кривую "
				+ "в road_curve трассы (или наоборот)."
			)


## Следит за кривой дороги и настройками трассы: любое изменение ставит
## пересборку в очередь (через REBUILD_DELAY после последней правки).
func _watch_sources() -> void:
	if not Engine.is_editor_hint():
		return
	var curve: Curve3D = _effective_curve()
	if curve != null and curve != _watched_curve:
		if _watched_curve != null and _watched_curve.changed.is_connected(_queue_rebuild):
			_watched_curve.changed.disconnect(_queue_rebuild)
		_watched_curve = curve
		if not curve.changed.is_connected(_queue_rebuild):
			curve.changed.connect(_queue_rebuild)
	if track != null and not track.changed.is_connected(_queue_rebuild_from_track):
		track.changed.connect(_queue_rebuild_from_track)


## Сигнатура кривой: по ней видно, реально ли сдвинулись точки.
func _curve_signature(curve: Curve3D) -> float:
	if curve == null:
		return 0.0
	var total: float = float(curve.point_count)
	for i in range(curve.point_count):
		var p: Vector3 = curve.get_point_position(i)
		total += p.x * 0.7919 + p.y * 1.3171 + p.z * 2.1031 + float(i) * 0.017
	return total


func _queue_rebuild() -> void:
	# Сам пересчёт тяжёлый, поэтому не дёргаем его на каждый сдвиг точки:
	# ждём, пока правка затихнет.
	_rebuild_pending = true
	_rebuild_timer = 0.0


func _queue_rebuild_from_track() -> void:
	_pending_from_track = true
	_rebuild_pending = true
	_rebuild_timer = 0.0


## Ставит все ассеты из узлов Props и ManualProps ровно на землю (по мешу)
## и разворачивает их по склону. Работает в редакторе: результат сохраняется
## в сцене, поэтому расставленные руками объекты остаются на месте.
func snap_props_to_ground() -> void:
	var placed: int = _snap_prop_nodes(true)
	print("Ассеты посажены на землю: %d шт." % placed)


## Ставит каждый ассет ровно на нарисованный меш земли (по XZ-координате).
## Работает и в редакторе, и в игре; результат в редакторе сохраняется в сцене.
func _snap_prop_nodes(include_manual: bool) -> int:
	var total: int = 0
	var roots: Array[String] = ["Props"]
	if include_manual:
		roots.append("ManualProps")
	for node_name in roots:
		var root := get_node_or_null(node_name) as Node3D
		if root == null:
			continue
		for child in root.get_children():
			var node3d := child as Node3D
			if node3d == null:
				continue
			var p: Vector3 = node3d.position
			node3d.position.y = ground_height(p.x, p.z)
			total += 1
	return total


func _resolve_track() -> void:
	var game: Node = null if Engine.is_editor_hint() else get_node_or_null("/root/RallyGame")
	if game_config == null and game != null:
		var loaded: Variant = game.get("config")
		if loaded is GameConfigType:
			game_config = loaded
	if game_config == null and ResourceLoader.exists("res://data/rally_game_config.tres"):
		var loaded_config: Resource = ResourceLoader.load("res://data/rally_game_config.tres")
		if loaded_config is GameConfigType:
			game_config = loaded_config
	if track_override != null:
		track = track_override
	elif game != null:
		var current: Variant = game.get("current_track")
		if current is TrackConfigType:
			track = current
	if track == null and game_config != null and game_config.get_script() != null:
		var first: Variant = game_config.call("get_track", 0)
		if first is TrackConfigType:
			track = first
	if track == null:
		track = TrackConfigType.new()
	if not Engine.is_editor_hint() and not _track_prepared:
		# Погода и характер трассы применяются к КОПИИ конфига: исходный
		# .tres в репозитории остаётся нетронутым, а сцепление/ширина/кочки
		# не «накапливаются» от заезда к заезду.
		track = track.duplicate() as TrackConfigType
		_resolve_conditions(game)
		_apply_conditions_to_track()
		_track_prepared = true
	if not Engine.is_editor_hint() and track.procedural and track.reroll_seed_each_visit:
		# «Каждый заезд — новая трасса»: новый сид ещё до построения кривой.
		# Сид сразу сохраняется, поэтому трассу можно вернуть по номеру,
		# а рекорды честно считаются по фактическому сиду.
		if game != null and game.has_method("reroll_live_seed"):
			game.call("reroll_live_seed", track)
		else:
			var reroll := RandomNumberGenerator.new()
			reroll.seed = hash("reroll_%d_%d" % [Time.get_ticks_msec(), Time.get_unix_time_from_system()])
			track.generation_seed = reroll.randi_range(1, 999999999)
	if car_setup_override != null:
		setup = car_setup_override
	elif game != null:
		var current_setup: Variant = game.get("current_setup")
		if current_setup is CarSetupType:
			setup = current_setup
	if setup == null and game_config != null and game_config.get_script() != null:
		var first_setup: Variant = game_config.call("get_setup", 0)
		if first_setup is CarSetupType:
			setup = first_setup


## Погода и характер трассы выбраны в меню; автозагрузка RallyGame хранит их
## между сценами. Прямой запуск сцены (F6) работает без них — тогда трасса
## выглядит ровно так, как записана в своём .tres.
func _resolve_conditions(game: Node) -> void:
	if game == null:
		return
	var selected_weather: Variant = game.get("current_weather")
	if selected_weather is WeatherType:
		weather = selected_weather
		# «КАК НА ТРАССЕ» — это отсутствие погоды, а не отдельный эффект:
		# так день/ночь и туман трассы остаются ровно такими, как в .tres.
		if String(weather.id) == "default":
			weather = null
	var selected_profile: Variant = game.get("current_profile")
	if selected_profile is ProfileType:
		track_profile = selected_profile


## Накладывает профиль полотна и поправки погоды на копию конфига трассы.
## Сцепление перемножается: снег по грязи скользит сильнее, чем снег по
## асфальту, и это честно видно в меню (там показывается итог).
func _apply_conditions_to_track() -> void:
	if track == null:
		return
	if track_profile != null:
		track_profile.apply_to(track)
	if weather == null:
		return
	track.grip_scale = clampf(track.grip_scale * weather.grip_scale, 0.2, 2.0)
	track.rolling_resistance_scale = clampf(
		track.rolling_resistance_scale * weather.rolling_resistance_scale, 0.2, 4.0
	)
	track.offroad_grip = clampf(track.offroad_grip * weather.offroad_grip_scale, 0.05, 1.0)


# ---------------------------------------------------------------- сборка мира


## Осевая линия. В РЕДАКТОРЕ первый источник — узел Route (Path3D) прямо
## в сцене: его кривую видно и можно тянуть точками в 3D-вьюпорте.
## В ИГРЕ выбранный ресурс трассы главнее: в Route лежит авторская кривая
## лесного спецучастка, а заездить могли на перевал, северную дугу или
## сгенерированную трассу.
func _effective_curve() -> Curve3D:
	if not Engine.is_editor_hint() and track != null:
		if track.procedural:
			return track.get_effective_curve()
		if track.road_curve != null:
			return track.road_curve
	var path := get_node_or_null("Route") as Path3D
	if path != null and path.curve != null and path.curve.point_count >= 2:
		return path.curve
	if track != null and track.road_curve != null:
		return track.road_curve
	return null


## Прямоугольник карты вокруг кривой + отступ terrain_margin.
func _curve_terrain_rect(curve: Curve3D) -> Rect2:
	var points: PackedVector3Array = curve.get_baked_points()
	if points.is_empty():
		return Rect2(Vector2(-64, -64), Vector2(128, 128))
	var min_x: float = INF
	var min_z: float = INF
	var max_x: float = -INF
	var max_z: float = -INF
	for p in points:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	var margin: float = maxf(40.0, track.terrain_margin)
	return Rect2(
		Vector2(min_x - margin, min_z - margin),
		Vector2(max_x - min_x + margin * 2.0, max_z - min_z + margin * 2.0)
	)


func _build_world() -> void:
	# Обёртка для редактора (кнопка и предпросмотр): редакторский путь внутри
	# _build_world_async() синхронный — ожиданий там не выполняется.
	_build_world_async()


## Генерация мира в порциях по кадрам: в игре прогресс и статус «живой»
## полосой на экране загрузки (autoload RallyGame), в редакторе — синхронно.
func _build_world_async() -> void:
	surface_state.clear()
	var game: Node = null if Engine.is_editor_hint() else get_node_or_null("/root/RallyGame")
	var has_progress: bool = game != null and game.has_method("set_loading_progress")
	var curve: Curve3D
	if track != null and track.procedural:
		# Плетение трассы — тяжёлая синхронная работа: даём кадру
		# прорисоваться ДО неё, чтобы на экране загрузки висел статус,
		# а не молчание.
		if has_progress:
			_report_progress(0.04, "Плетение трассы (сид %d)…" % track.generation_seed)
			await get_tree().process_frame
		curve = _effective_curve()
	else:
		curve = _effective_curve()
	if track == null or curve == null:
		push_warning("RallyStage: нет осевой линии (road_curve в трассе или узел Route/Path3D).")
		return
	_clear_generated()
	_apply_baked_props_visibility()
	_setup_noise()
	if has_progress:
		_report_progress(0.08, "Поле дорог и осевая линия…")
		await get_tree().process_frame
	# Границы карты считаем по ТОЙ кривой, что реально используется
	# (узел Route в сцене), иначе правка кривой в 3D не меняла бы размер поля.
	terrain_rect = _curve_terrain_rect(curve)
	network = RoadNetworkType.build(curve, terrain_rect, maxf(1.5, track.terrain_cell))
	var length: float = network.total_length
	start_pos = network.point_at(0.0)
	finish_pos = network.point_at(length)
	start_dir = network.direction_at(0.0)
	finish_dir = network.direction_at(length)
	if not Engine.is_editor_hint():
		# Свет и небо применяем только в игре: иначе редактор помечает сцену
		# изменённой при каждом предпросмотре.
		_configure_world()
	if has_progress:
		await get_tree().process_frame
	await _build_terrain(has_progress, 0.15, 0.58)
	if has_progress:
		_report_progress(0.60, "Полотно дороги…")
		await get_tree().process_frame
	await _build_road(has_progress, 0.60, 0.80)
	if has_progress:
		_report_progress(0.82, "Ассеты, ворота и КПП…")
		await get_tree().process_frame
	if snap_props_on_build and track.use_baked_props:
		# Только «лес» из Props (запечённая обстановка лесной трассы):
		# ручные объекты в ManualProps не двигаем, их можно поставить
		# руками на нужную высоту. У трасс без запечённых пропсов
		# обстановка генерируется своя.
		_snap_prop_nodes(false)
	if track.spawn_route_markers:
		_spawn_route_markers()
	if track.spawn_edge_posts:
		_spawn_edge_posts()
	if track.spawn_checkpoints:
		_spawn_checkpoints()
	if track.procedural_scenery:
		if has_progress:
			_report_progress(0.90, "Лес, камни и знаки…")
			await get_tree().process_frame
		await _spawn_procedural_scenery(has_progress)
	cp_triggered.resize(checkpoints.size())
	cp_times.clear()
	for i in range(checkpoints.size()):
		cp_triggered[i] = false
		cp_times.append(0.0)
	if has_progress:
		_report_progress(1.0, "Готово")


func _report_progress(value: float, status: String) -> void:
	if Engine.is_editor_hint():
		return
	var game: Node = get_node_or_null("/root/RallyGame")
	if game != null and game.has_method("set_loading_progress"):
		game.call("set_loading_progress", value, status)


func _setup_noise() -> void:
	_noise_hills = _make_noise(track.terrain_seed, track.hills_frequency, 3)
	_noise_ridge = _make_noise(track.terrain_seed + 91, track.ridge_frequency, 4)
	_noise_detail = _make_noise(track.terrain_seed + 173, track.detail_frequency, 2)
	# Низкая частота: «шершавость» полотна должна быть длиной в метры, а не
	# в полметра — иначе на шаге строк меша она читается как рёбра.
	_noise_bumps = _make_noise(track.terrain_seed + 257, 0.08, 1)
	_rng.seed = track.terrain_seed


func _make_noise(seed_value: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	return noise


func _clear_generated() -> void:
	if generated == null:
		return
	for child in generated.get_children():
		generated.remove_child(child)
		child.queue_free()


# ---------------------------------------------------------------- высота


## ЕДИНСТВЕННЫЙ источник высоты в мире. Дорога, земля и ассеты — все здесь.
##
##   base = региональный уровень дороги + холмы (холмы включаются с расстоянием)
##   + выемка/насыпь: дорога «врезана» в рельеф и плавно с ним сливается.
##
## Получается height = base + (road_y - base) * (1 - t), где t — плавный
## переход по расстоянию до оси (0 на полотне, 1 вдали). На полотне высота
## ровно равна дороге, вдали — ровно рельефу, а между ними склон не круче
## embankment_slope_deg. Никаких «бугров под большим углом» и клиппинга.
func height_at(x: float, z: float) -> float:
	if network == null:
		return 0.0
	var distance: float = network.distance_to_road(x, z)
	return _height_with_distance(x, z, distance)


func _height_with_distance(x: float, z: float, distance: float) -> float:
	var corridor: float = track.road_half_width + track.road_shoulder
	var along: float = network.along_road(x, z)
	var road_y: float = network.height_at_along(along)
	var fade: float = smoothstep(
		track.hills_fade_start,
		track.hills_fade_start + track.hills_fade_length,
		distance
	)
	var base: float = network.regional_height(x, z) + _hills_at(x, z) * fade
	var max_slope: float = tan(deg_to_rad(maxf(6.0, track.embankment_slope_deg)))
	var blend_width: float = clampf(
		absf(road_y - base) / maxf(max_slope, 0.05),
		track.embankment_min_width,
		track.embankment_max_width
	)
	var t: float = smoothstep(corridor, corridor + blend_width, distance)
	var height: float = base + (road_y - base) * (1.0 - t)
	var near: float = 1.0 - t
	if near > 0.001:
		# Поперечный уклон полотна (крен к обочинам).
		var lateral_norm: float = clampf(distance / maxf(corridor, 0.01), 0.0, 1.0)
		height -= track.road_camber * lateral_norm * lateral_norm * near
		# Кочки/волны полотна — те же, что в меше дороги.
		height += _surface_bumps_along(along) * near
	return height


## Высота земли «как она нарисована» — с точностью до треугольника меша
## (сетка разбита по диагонали i00-i11). По ней садятся ассеты, разметка и
## внешняя кромка полотна, поэтому ничего не висит в воздухе и не тонет.
func ground_height(x: float, z: float) -> float:
	if _ground_grid.is_empty() or _ground_cols < 2 or _ground_rows < 2:
		return height_at(x, z)
	var fx: float = (x - _ground_origin.x) / _ground_cell
	var fz: float = (z - _ground_origin.y) / _ground_cell
	if fx < 0.0 or fz < 0.0 or fx > float(_ground_cols - 1) or fz > float(_ground_rows - 1):
		return height_at(x, z)
	var gx: int = clampi(int(floor(fx)), 0, _ground_cols - 2)
	var gz: int = clampi(int(floor(fz)), 0, _ground_rows - 2)
	var u: float = clampf(fx - float(gx), 0.0, 1.0)
	var v: float = clampf(fz - float(gz), 0.0, 1.0)
	var i00: int = gz * _ground_cols + gx
	var h00: float = _ground_grid[i00]
	var h10: float = _ground_grid[i00 + 1]
	var h01: float = _ground_grid[i00 + _ground_cols]
	var h11: float = _ground_grid[i00 + _ground_cols + 1]
	if u + v <= 1.0:
		return h00 + u * (h10 - h00) + v * (h01 - h00)
	return h11 * (u + v - 1.0) + h10 * (1.0 - v) + h01 * (1.0 - u)


## Полуширина коридора «дорога + обочина», м.
func corridor_half() -> float:
	return track.road_half_width + track.road_shoulder


## Ширина перехода «полотно → рельеф»: за ней насыпь/выемка уже слилась
## с базовым рельефом. Нужна ограничителю склонов, чтобы он не «сглаживал»
## готовый откос и не делал из него стенку.
func _embankment_width(x: float, z: float, distance: float) -> float:
	var along: float = network.along_road(x, z)
	var road_y: float = network.height_at_along(along)
	var fade: float = smoothstep(
		track.hills_fade_start,
		track.hills_fade_start + track.hills_fade_length,
		distance
	)
	var base: float = network.regional_height(x, z) + _hills_at(x, z) * fade
	var max_slope: float = tan(deg_to_rad(maxf(6.0, track.embankment_slope_deg)))
	return clampf(
		absf(road_y - base) / maxf(max_slope, 0.05),
		track.embankment_min_width,
		track.embankment_max_width
	)


## Кювет вдоль кромки: насколько опустить землю в этой точке.
func _road_ditch(distance: float) -> float:
	if track.road_ditch_depth <= 0.0:
		return 0.0
	var corridor: float = track.road_half_width + track.road_shoulder
	var t: float = smoothstep(corridor + 0.5, corridor + 4.0, distance)
	return track.road_ditch_depth * (1.0 - t)


## Базовый рельеф: крупные холмы, хребты и мелкая шершавость.
func _hills_at(x: float, z: float) -> float:
	if _noise_hills == null:
		return 0.0
	var value: float = _noise_hills.get_noise_2d(x, z) * track.hills_height
	if track.ridge_height > 0.0:
		var ridge: float = 1.0 - absf(_noise_ridge.get_noise_2d(x, z))
		value += (ridge - 0.5) * 2.0 * track.ridge_height
	value += _noise_detail.get_noise_2d(x, z) * track.detail_height
	return value


func _surface_bumps_along(along: float) -> float:
	if track.bumps_amplitude <= 0.0 and track.bumps_roughness <= 0.0:
		return 0.0
	# Волна длиной в несколько метров: короткую синусоиду шаг строк полотна
	# (1.5–2 м) превращает в пилу — та самая «гармошка» поперёк дороги.
	var wavelength: float = maxf(track.bumps_wavelength, 4.0)
	var wave: float = sin(along * TAU / wavelength)
	# «Шершавость» тоже низкочастотная (≈10 м): крупные мягкие волны,
	# а не случайный сдвиг каждой поперечной полосы меша на ±5 см.
	var roughness: float = _noise_bumps.get_noise_1d(along)
	var cross: float = 1.0 - track.bumps_cross * 0.5 * (roughness * 0.5 + 0.5)
	return (track.bumps_amplitude * wave + track.bumps_roughness * roughness) * cross


## Нормаль поверхности по нарисованному мешу (для наклона ассетов).
func normal_at(x: float, z: float, eps: float = 1.0) -> Vector3:
	var left: float = ground_height(x - eps, z)
	var right: float = ground_height(x + eps, z)
	var back: float = ground_height(x, z - eps)
	var front: float = ground_height(x, z + eps)
	return Vector3(left - right, 2.0 * eps, back - front).normalized()


# ---------------------------------------------------------------- рельеф


func _build_terrain(light: bool = false, from_pct: float = 0.0, to_pct: float = 0.0) -> void:
	if terrain == null or terrain_mesh == null or terrain_collider == null:
		push_warning("RallyStage: узлы Terrain не найдены.")
		return
	terrain.remove_from_group("Road")
	terrain.add_to_group("Grass")
	terrain_collider.position = Vector3.ZERO
	terrain_collider.rotation = Vector3.ZERO
	var cell: float = maxf(1.0, track.terrain_cell)
	var cols: int = maxi(2, ceili(terrain_rect.size.x / cell) + 1)
	var rows: int = maxi(2, ceili(terrain_rect.size.y / cell) + 1)
	var origin: Vector2 = terrain_rect.position

	# 1) Сетка высот и расстояний до дороги (одна выборка на ячейку).
	var heights := PackedFloat32Array()
	var distances := PackedFloat32Array()
	heights.resize(cols * rows)
	distances.resize(cols * rows)
	for gz in range(rows):
		var z: float = origin.y + float(gz) * cell
		for gx in range(cols):
			var x: float = origin.x + float(gx) * cell
			var index: int = gz * cols + gx
			var distance: float = network.distance_to_road(x, z)
			distances[index] = distance
			heights[index] = _height_with_distance(x, z, distance)
		if light and gz % 24 == 23:
			# Полоса прогресса: примерно до половины этого этапа — сетка высот.
			_report_progress(lerpf(from_pct, to_pct, 0.5 * float(gz + 1) / float(rows)), "Рельеф…")
			await get_tree().process_frame

	# «Крышки» дыры на старте и финише. Поле расстояний считает дыру
	# вокруг ЛИНИИ дороги, поэтому у оконечностей получается полукруг —
	# а лента полотна начинается прямо на оси и этого полукруга не закрывает.
	# Без обработки на старте/финише оставалась бы дырка в земле. Ячейки,
	# где ближайшая точка дороги — сам начальный/конечный отрезок, оставляем
	# как цельную землю (рельефом), и они перекрывают эти крышки.
	var cap := PackedByteArray()
	cap.resize(cols * rows)
	var start_xz: Vector2 = Vector2(start_pos.x, start_pos.z)
	var finish_xz: Vector2 = Vector2(finish_pos.x, finish_pos.z)
	for gz in range(rows):
		var z: float = origin.y + float(gz) * cell
		for gx in range(cols):
			var x: float = origin.x + float(gx) * cell
			var index: int = gz * cols + gx
			var nearest_end: float = minf(
				Vector2(x, z).distance_to(start_xz),
				Vector2(x, z).distance_to(finish_xz)
			)
			cap[index] = 1 if distances[index] >= nearest_end - 1.0 else 0

	# 2) Кювет: земля у кромки опускается. Полотно всегда выше земли, поэтому
	#    «протыкания» дороги рельефом не бывает даже на косогорах.
	#    На «крышках» кювета не нужны — там дороги спереди нет.
	var ditch_reach: float = corridor_half() + 5.0
	for index in range(cols * rows):
		if distances[index] < ditch_reach and cap[index] == 0:
			heights[index] -= _road_ditch(distances[index])

	# 3) Лимит склонов: страховка от «стенок» (тесные шпильки, косогоры).
	#    Весь переход «полотно → рельеф» уже задан height_at плавным откосом,
	#    поэтому он — якорь: раньше ограничитель «размазывал» и его, утягивая
	#    землю у дороги на несколько метров вниз и делая из откоса стенку.
	heights = _limit_terrain_slopes(heights, distances, cols, rows, cell, origin)
	_ground_grid = heights.duplicate()
	_ground_origin = origin
	_ground_cell = cell
	_ground_cols = cols
	_ground_rows = rows

	# 4) Вершины, нормали, вершинные цвета.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	vertices.resize(cols * rows)
	normals.resize(cols * rows)
	colors.resize(cols * rows)
	var corridor: float = track.road_half_width + track.road_shoulder
	for gz in range(rows):
		var z: float = origin.y + float(gz) * cell
		for gx in range(cols):
			var x: float = origin.x + float(gx) * cell
			var index: int = gz * cols + gx
			var h: float = heights[index]
			var h_left: float = heights[gz * cols + maxi(0, gx - 1)]
			var h_right: float = heights[gz * cols + mini(cols - 1, gx + 1)]
			var h_back: float = heights[maxi(0, gz - 1) * cols + gx]
			var h_front: float = heights[mini(rows - 1, gz + 1) * cols + gx]
			var normal := Vector3(h_left - h_right, 2.0 * cell, h_back - h_front).normalized()
			vertices[index] = Vector3(x, h, z)
			normals[index] = normal
			# Контракт шейдера: R — «не дорога» (0 = обочина), G — разрешение
			# рисовать камни на склоне, B — разброс оттенка камня.
			var road_influence: float = smoothstep(corridor * 0.85, corridor + 14.0, distances[index])
			var rock: float = smoothstep(corridor + 2.0, corridor + 10.0, distances[index])
			var grain: float = TrackConfigType.hash_noise(x * 7.3 + 11.0, z * 5.1 + 3.0)
			colors[index] = Color(road_influence, rock, grain, 1.0)
		if light and gz % 48 == 47:
			_report_progress(lerpf(from_pct, to_pct, 0.5 + 0.4 * float(gz + 1) / float(rows)), "Рельеф…")
			await get_tree().process_frame

	# 5) Индексы: строго под полотном треугольники не нужны — там лежит лента
	#    дороги (она закрывает дыру и держит коллизию). Считается по сетке
	#    расстояний, без повторных запросов к дороге. На «крышках» старта/
	#    финиша дыру не делаем — там ленты спереди нет, оставляем рельеф.
	var indices := PackedInt32Array()
	indices.resize((rows - 1) * (cols - 1) * 6)
	var index_count := 0
	var hole_distance: float = corridor * 0.92
	for gz in range(rows - 1):
		for gx in range(cols - 1):
			var i00: int = gz * cols + gx
			var i10: int = i00 + 1
			var i01: int = i00 + cols
			var i11: int = i01 + 1
			var hole_00: bool = distances[i00] < hole_distance and cap[i00] == 0
			var hole_10: bool = distances[i10] < hole_distance and cap[i10] == 0
			var hole_01: bool = distances[i01] < hole_distance and cap[i01] == 0
			var hole_11: bool = distances[i11] < hole_distance and cap[i11] == 0
			if hole_00 and hole_10 and hole_01 and hole_11:
				continue
			indices[index_count] = i00
			indices[index_count + 1] = i10
			indices[index_count + 2] = i01
			indices[index_count + 3] = i10
			indices[index_count + 4] = i11
			indices[index_count + 5] = i01
			index_count += 6
		if light and gz % 48 == 47:
			await get_tree().process_frame
	indices.resize(index_count)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	terrain_mesh.mesh = mesh
	terrain_mesh.material_override = _make_ground_material()
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	terrain_collider.shape = shape


## Ограничитель склонов: если где-то получилась «стенка» круче
## max_terrain_slope_deg, она размазывается на несколько ячеек.
## Работает по списку «грязных» ячеек, поэтому стоит копейки.
func _limit_terrain_slopes(
	heights: PackedFloat32Array,
	distances: PackedFloat32Array,
	cols: int,
	rows: int,
	cell: float,
	origin: Vector2
) -> PackedFloat32Array:
	var max_slope: float = tan(deg_to_rad(clampf(track.max_terrain_slope_deg, 20.0, 75.0)))
	var max_delta: float = cell * max_slope
	var corridor: float = corridor_half()
	var search_reach: float = corridor + track.embankment_max_width
	var anchored := PackedByteArray()
	anchored.resize(cols * rows)
	var dirty := PackedInt32Array()
	for gz in range(rows):
		for gx in range(cols):
			var index: int = gz * cols + gx
			# Якоря — дорога, обочина и весь готовый откос насыпи/выемки.
			if distances[index] < search_reach:
				var x: float = origin.x + float(gx) * cell
				var z: float = origin.y + float(gz) * cell
				if distances[index] < corridor + _embankment_width(x, z, distances[index]):
					anchored[index] = 1
					continue
			if gz == 0 or gx == 0 or gz == rows - 1 or gx == cols - 1:
				anchored[index] = 1
				continue
			var h: float = heights[index]
			if (
				absf(h - heights[index + 1]) > max_delta
				or absf(h - heights[index - 1]) > max_delta
				or absf(h - heights[index + cols]) > max_delta
				or absf(h - heights[index - cols]) > max_delta
			):
				dirty.append(index)
	var marks := PackedByteArray()
	marks.resize(cols * rows)
	for i in range(dirty.size()):
		marks[dirty[i]] = 1
	var passes: int = 0
	while not dirty.is_empty() and passes < 80:
		passes += 1
		var next := PackedInt32Array()
		for index in dirty:
			marks[index] = 0
			var gx: int = index % cols
			var gz: int = floori(float(index) / float(cols))
			if anchored[index]:
				continue
			for dz in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if dx == 0 and dz == 0:
						continue
					var nz: int = gz + dz
					var nx: int = gx + dx
					if nx < 0 or nz < 0 or nx >= cols or nz >= rows:
						continue
					var n_index: int = nz * cols + nx
					var delta: float = heights[index] - heights[n_index]
					var allowed: float = max_delta * (1.4142135 if (dx != 0 and dz != 0) else 1.0)
					if absf(delta) <= allowed:
						continue
					var excess: float = (absf(delta) - allowed) * 0.5
					var sign_value: float = 1.0 if delta > 0.0 else -1.0
					heights[index] -= excess * sign_value
					if not anchored[n_index]:
						heights[n_index] += excess * sign_value
					if marks[n_index] == 0:
						marks[n_index] = 1
						next.append(n_index)
					if marks[index] == 0:
						marks[index] = 1
						next.append(index)
		dirty = next
	return heights


func _make_ground_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GroundShader
	material.set_shader_parameter("ground_texture", GroundTexture)
	material.set_shader_parameter("rock_texture", RockTexture)
	material.set_shader_parameter("ground_color", track.ground_color)
	material.set_shader_parameter("ground_color_2", track.ground_color_2)
	material.set_shader_parameter("road_edge_color", track.shoulder_color)
	material.set_shader_parameter("rock_color", track.rock_color)
	material.set_shader_parameter("surface_roughness", 0.97)
	material.set_shader_parameter("grain_scale", 2.4)
	material.set_shader_parameter("flat_shading", 1.0 if track.flat_shading else 0.0)
	material.set_shader_parameter("dither_fog", 1.0 if track.dither_fog else 0.0)
	material.set_shader_parameter("banding_levels", float(track.color_banding))
	# Дизер-туман в шейдере должен совпадать с погодой, иначе земля
	# «просвечивает» светлее атмосферного тумана.
	material.set_shader_parameter("fog_color", _effective_fog_color())
	material.set_shader_parameter("fog_near", track.fog_near * _weather_visibility_scale())
	material.set_shader_parameter("fog_far", track.fog_far * _weather_visibility_scale())
	material.set_shader_parameter("wetness", _weather_wetness())
	material.set_shader_parameter("snow_cover", _weather_snow_cover())
	return material


func _weather_visibility_scale() -> float:
	return weather.visibility_scale if weather != null else 1.0


func _weather_wetness() -> float:
	return weather.wetness if weather != null else 0.0


func _weather_snow_cover() -> float:
	return weather.snow_cover if weather != null else 0.0


# ---------------------------------------------------------------- полотно


## Лента дороги: меш + коллизия. Высота краёв совпадает с землёй (та же
## функция height_at), поэтому стык не просвечивает.
func _build_road(light: bool = false, from_pct: float = 0.0, to_pct: float = 0.0) -> void:
	var step: float = maxf(0.5, track.road_step)
	if track.bumps_amplitude > 0.0 or track.bumps_roughness > 0.0:
		# Волну кочек рисуем плотнее, чем шаг из конфига: минимум ~10 строк
		# на длину волны, иначе синус превращается в треугольные рёбра.
		step = minf(step, maxf(0.6, track.bumps_wavelength / 10.0))
	var length: float = network.total_length
	var rows: int = maxi(2, ceili(length / step) + 1)
	var half: float = track.road_half_width
	var corridor: float = half + track.road_shoulder
	var outer: float = corridor + 1.5
	# Поперечные «полосы»: край -> обочина -> кромка -> центр -> …
	var lateral: Array[float] = [-outer, -corridor, -half, -half * 0.5, 0.0, half * 0.5, half, corridor, outer]
	var lanes: int = lateral.size()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	vertices.resize(rows * lanes)
	normals.resize(rows * lanes)
	colors.resize(rows * lanes)
	uvs.resize(rows * lanes)
	var color_rng := RandomNumberGenerator.new()
	color_rng.seed = track.terrain_seed ^ 0x5A17

	for row in range(rows):
		var distance: float = minf(length, float(row) * step)
		var center: Vector3 = network.point_at(distance)
		var dir: Vector3 = network.direction_at(distance)
		var side := Vector3(dir.z, 0.0, -dir.x)
		var shade: float = color_rng.randf_range(0.9, 1.1)
		for lane in range(lanes):
			var lat: float = lateral[lane]
			var point: Vector3 = center + side * lat
			var y: float = 0.0
			if absf(lat) <= half:
				# Полотно: высота осевой линии + крен + кочки (та же формула,
				# что и у земли, поэтому стык не просвечивает).
				var crown: float = track.road_camber * pow(absf(lat) / maxf(corridor, 0.01), 2.0)
				y = center.y + _surface_bumps_along(distance) - crown
			elif absf(lat) <= corridor:
				# Обочина: ровно та же функция, что и у земли в коридоре.
				y = height_at(point.x, point.z)
			else:
				# Внешняя кромка ложится на нарисованный меш земли (кювет),
				# поэтому между дорогой и рельефом нет ни щели, ни стыка.
				y = ground_height(point.x, point.z)
			y += 0.035
			vertices[row * lanes + lane] = Vector3(point.x, y, point.z)
			uvs[row * lanes + lane] = Vector2(lat, distance)

			var base_color: Color = track.road_color * shade
			base_color = base_color.lerp(track.road_color_2, color_rng.randf() * 0.45)
			var edge_factor: float = clampf((absf(lat) - half * 0.75) / maxf(half * 0.5, 0.01), 0.0, 1.0)
			if absf(lat) > half:
				base_color = base_color.lerp(track.shoulder_color, edge_factor)
			elif absf(lat) > half * 0.62:
				# Светлая кромка — «накатанная» полоса, по ней видно траекторию.
				base_color = base_color.lightened(0.08 * edge_factor)
			colors[row * lanes + lane] = base_color
		if light and row % 200 == 199:
			_report_progress(lerpf(from_pct, to_pct, float(row + 1) / float(rows)), "Полотно дороги…")
			await get_tree().process_frame

	for row in range(rows):
		for lane in range(lanes):
			var here: int = row * lanes + lane
			var across: Vector3 = vertices[row * lanes + mini(lanes - 1, lane + 1)] - vertices[row * lanes + maxi(0, lane - 1)]
			var along: Vector3 = vertices[mini(rows - 1, row + 1) * lanes + lane] - vertices[maxi(0, row - 1) * lanes + lane]
			var normal: Vector3 = along.cross(across)
			if normal.y < 0.0:
				normal = -normal
			normals[here] = normal.normalized() if normal.length() > 0.0001 else Vector3.UP

	var indices := PackedInt32Array()
	for row in range(rows - 1):
		for lane in range(lanes - 1):
			var i0: int = row * lanes + lane
			var i1: int = i0 + 1
			var i2: int = i0 + lanes
			var i3: int = i2 + 1
			indices.append(i0)
			indices.append(i1)
			indices.append(i2)
			indices.append(i1)
			indices.append(i3)
			indices.append(i2)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var road_mesh := ArrayMesh.new()
	road_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var road_material := ShaderMaterial.new()
	road_material.shader = RoadShader
	road_material.set_shader_parameter("gravel_texture", GravelTexture)
	var road_kind: String = surface_state.surface_kind(track.surface_name, false, _weather_snow_cover())
	road_material.set_shader_parameter("loose_relief", 0.08 if road_kind == "asphalt" else 1.0)
	# Мокрое полотно темнее и глянцевее, снег — светлее и матовее.
	road_material.set_shader_parameter("stage_length", network.total_length)
	road_material.set_shader_parameter("zone_offset", minf(track.road_half_width * 0.45, 1.5))
	road_material.set_shader_parameter("wetness", _weather_wetness())
	road_material.set_shader_parameter("snow_cover", _weather_snow_cover())

	var road_visual := MeshInstance3D.new()
	road_visual.name = "RoadMesh"
	road_visual.mesh = road_mesh
	road_visual.material_override = road_material
	if generated != null:
		generated.add_child(road_visual)

	# Коллизия — по всей видимой ленте, включая внешнюю «юбку» (outer):
	# она ложится на землю и плавно уводит край полотна в кювет. Если
	# обрывать коллизию на обочине, под видимым краем остаётся невидимая
	# ступенька в глубину кювета — машина упирается в неё, пытаясь
	# вернуться на трассу.
	var faces := PackedVector3Array()
	for row in range(rows - 1):
		for lane in range(0, lanes - 1):
			var i0: int = row * lanes + lane
			var i1: int = i0 + 1
			var i2: int = i0 + lanes
			var i3: int = i2 + 1
			faces.append(vertices[i0])
			faces.append(vertices[i1])
			faces.append(vertices[i2])
			faces.append(vertices[i1])
			faces.append(vertices[i3])
			faces.append(vertices[i2])
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	_set_shape_faces(shape, faces)
	var road_body := StaticBody3D.new()
	road_body.name = "RoadSurface"
	road_body.add_to_group("Dirt")
	var collider := CollisionShape3D.new()
	collider.shape = shape
	road_body.add_child(collider)
	if generated != null:
		generated.add_child(road_body)


## Контакт вызывается отдельно для каждого колеса, в локальных координатах этапа.
func surface_contact(point: Vector3, grass: bool, load_ratio: float, slip: float, speed: float, delta: float) -> Dictionary:
	if track == null:
		return {"grip": 1.0, "rolling": 1.0, "depth": 0.0}
	var p := to_local(point)
	var kind: String = surface_state.surface_kind(track.surface_name, grass, _weather_snow_cover())
	var result: Dictionary = surface_state.sample(p, kind, _weather_wetness())
	if not grass:
		result.grip *= live_surface_grip(point)
	surface_state.imprint(p, kind, load_ratio, slip, speed, delta)
	return result


## Локальные скользкие полосы: та же формула используется шейдером дороги.
## Начало и финиш свободны; полосы чередуются по сторонам и оставляют объезд.
func live_surface_grip(world_point: Vector3) -> float:
	if network == null or track == null:
		return 1.0
	var p: Vector3 = to_local(world_point)
	var along: float = network.along_road(p.x, p.z)
	if along < 150.0 or along > network.total_length - 40.0:
		return 1.0
	var cell_index: int = floori((along - 150.0) / 240.0)
	var local_along: float = fposmod(along - 150.0, 240.0)
	var center: Vector3 = network.point_at(along)
	var dir: Vector3 = network.direction_at(along)
	var side := Vector3(dir.z, 0.0, -dir.x)
	var lateral: float = (p - center).dot(side)
	var offset: float = minf(track.road_half_width * 0.45, 1.5)
	var zone_side: float = 1.0 if cell_index % 2 == 0 else -1.0
	var longitudinal: float = smoothstep(0.0, 3.0, local_along) * (1.0 - smoothstep(17.0, 20.0, local_along))
	var across: float = 1.0 - smoothstep(0.7, 1.5, absf(lateral - zone_side * offset))
	return 1.0 - longitudinal * across * (0.20 if cell_index % 2 == 0 else 0.13)


func _set_shape_faces(shape: ConcavePolygonShape3D, faces: PackedVector3Array) -> void:
	if shape.has_method("set_faces"):
		shape.call("set_faces", faces)
	else:
		shape.set("data", faces)


# ---------------------------------------------------------------- ассеты


## Запечённые в сцену Props/ManualProps расставлены под лесную трассу:
## перевалу, северной дуге и генерации они не подходят — прячем целиком.
func _apply_baked_props_visibility() -> void:
	for node_name in ["Props", "ManualProps"]:
		var root := get_node_or_null(node_name) as Node3D
		if root != null:
			root.visible = track.use_baked_props


## Живая обстановка вдоль трассы: ели, сосны, кусты, валуны (MultiMesh),
## коллизия стволов у самых обочин и знаки на входах в крутые повороты.
## Всё детерминировано terrain_seed: один и тот же сид — один и тот же лес.
func _spawn_procedural_scenery(light: bool = false) -> void:
	if generated == null or network == null:
		return
	var container := Node3D.new()
	container.name = "Scenery"
	generated.add_child(container)
	var rng := RandomNumberGenerator.new()
	rng.seed = track.terrain_seed ^ 8237431
	var corridor: float = corridor_half()
	var firs: Array[Transform3D] = []
	var pines: Array[Transform3D] = []
	var bushes: Array[Transform3D] = []
	var rocks: Array[Transform3D] = []
	var trunks: Array[Vector3] = []
	var distance: float = 6.0
	var trunk_since: float = -100.0
	var step_count: int = 0
	var total_steps: float = maxf(1.0, (network.total_length - 12.0) / 8.0)
	while distance < network.total_length - 6.0:
		var center: Vector3 = network.point_at(distance)
		var dir: Vector3 = network.direction_at(distance)
		var side := Vector3(dir.z, 0.0, -dir.x)
		for side_sign in [-1.0, 1.0]:
			for _attempt in range(2):
				if rng.randf() > track.scenery_density * 0.62:
					continue
				var lateral: float = corridor + rng.randf_range(4.0, 56.0)
				var point: Vector3 = center + side * (lateral * side_sign)
				# Виток своей трассы рядом: не сажаем ничего на чужое полотно.
				if network.distance_to_road(point.x, point.z) < corridor + 3.0:
					continue
				var ground: float = ground_height(point.x, point.z)
				var roll: float = rng.randf()
				var angle: float = rng.randf_range(0.0, TAU)
				if roll < 0.46:
					# ель
					var s_fir: float = rng.randf_range(0.8, 1.8)
					firs.append(Transform3D(
						Basis(Vector3.UP, angle) * Basis.from_scale(Vector3.ONE * s_fir),
						Vector3(point.x, ground + 3.25 * s_fir, point.z)
					))
					if lateral < corridor + 24.0 and distance - trunk_since > 38.0:
						trunks.append(Vector3(point.x, ground, point.z))
						trunk_since = distance
				elif roll < 0.70:
					# сосна
					var s_pine: float = rng.randf_range(0.9, 2.0)
					pines.append(Transform3D(
						Basis(Vector3.UP, angle) * Basis.from_scale(Vector3.ONE * s_pine),
						Vector3(point.x, ground + 4.5 * s_pine, point.z)
					))
					if lateral < corridor + 24.0 and distance - trunk_since > 38.0:
						trunks.append(Vector3(point.x, ground, point.z))
						trunk_since = distance
				elif roll < 0.85:
					# куст
					var s_bush: float = rng.randf_range(0.7, 1.4)
					bushes.append(Transform3D(
						Basis(Vector3.UP, angle) * Basis.from_scale(Vector3.ONE * s_bush),
						Vector3(point.x, ground + 0.45 * s_bush, point.z)
					))
				else:
					# валун (чуть врастает в землю)
					var s_rock: float = rng.randf_range(0.8, 2.4)
					rocks.append(Transform3D(
						Basis(Vector3.UP, angle) * Basis.from_scale(Vector3.ONE * s_rock),
						Vector3(point.x, ground + 0.75 * s_rock, point.z)
					))
		step_count += 1
		if light and step_count % 64 == 63:
			_report_progress(lerpf(0.90, 0.97, float(step_count) / total_steps), "Лес, камни и знаки…")
			await get_tree().process_frame
		distance += 8.0
	_add_scenery_multimesh(container, "Firs", _make_scenery_mesh("fir"), firs)
	_add_scenery_multimesh(container, "Pines", _make_scenery_mesh("pine"), pines)
	_add_scenery_multimesh(container, "Bushes", _make_scenery_mesh("bush"), bushes)
	_add_scenery_multimesh(container, "Boulders", _make_scenery_mesh("boulder"), rocks)
	if not trunks.is_empty():
		var body := StaticBody3D.new()
		body.name = "TreeTrunks"
		var shape := CylinderShape3D.new()
		shape.radius = 0.45
		shape.height = 9.0
		for t in trunks:
			var collider := CollisionShape3D.new()
			collider.shape = shape
			collider.position = Vector3(t.x, t.y + 4.5, t.z)
			body.add_child(collider)
		container.add_child(body)
	_spawn_corner_signs(container)


func _make_scenery_mesh(kind: String) -> Mesh:
	var material := StandardMaterial3D.new()
	material.roughness = 0.95
	if kind == "fir":
		material.albedo_texture = NeedleTexture
		material.albedo_color = Color(0.9, 1.0, 0.9)
		var mesh_fir := CylinderMesh.new()
		mesh_fir.top_radius = 0.0
		mesh_fir.bottom_radius = 1.7
		mesh_fir.height = 6.5
		mesh_fir.radial_segments = 7
		mesh_fir.rings = 1
		mesh_fir.material = material
		return mesh_fir
	if kind == "pine":
		material.albedo_texture = NeedleTexture
		material.albedo_color = Color(0.75, 0.85, 0.8)
		var mesh_pine := CylinderMesh.new()
		mesh_pine.top_radius = 0.0
		mesh_pine.bottom_radius = 1.35
		mesh_pine.height = 9.0
		mesh_pine.radial_segments = 7
		mesh_pine.rings = 1
		mesh_pine.material = material
		return mesh_pine
	if kind == "bush":
		material.albedo_texture = NeedleTexture
		material.albedo_color = Color(1.0, 1.0, 0.9)
		var mesh_bush := SphereMesh.new()
		mesh_bush.radius = 0.95
		mesh_bush.height = 1.5
		mesh_bush.radial_segments = 6
		mesh_bush.rings = 2
		mesh_bush.material = material
		return mesh_bush
	material.albedo_texture = RockTexture
	material.albedo_color = Color(0.85, 0.88, 0.9)
	material.roughness = 0.98
	var mesh_rock := SphereMesh.new()
	mesh_rock.radius = 1.2
	mesh_rock.height = 2.1
	mesh_rock.radial_segments = 7
	mesh_rock.rings = 3
	mesh_rock.material = material
	return mesh_rock


func _add_scenery_multimesh(parent: Node3D, node_name: String, mesh: Mesh, transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in range(transforms.size()):
		multimesh.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	parent.add_child(instance)


## Знаки на входах в крутые повороты: смотрим поворот на 55 м вперёд,
## знак ставим на ВНЕШНЮЮ сторону обочины, лицом к подъезжающей машине.
func _spawn_corner_signs(parent: Node3D) -> void:
	var last_sign: float = -10000.0
	var distance: float = 50.0
	while distance < network.total_length - 90.0:
		var turn: float = _turn_ahead(distance, 55.0)
		if absf(turn) > deg_to_rad(58.0) and distance - last_sign > 110.0:
			var center: Vector3 = network.point_at(distance)
			var dir: Vector3 = network.direction_at(distance)
			var side := Vector3(dir.z, 0.0, -dir.x)
			# side указывает в сторону роста heading, наружу поворота —
			# противоположная сторона.
			var outer: float = -1.0 if turn > 0.0 else 1.0
			var point: Vector3 = center + side * (outer * (corridor_half() + 2.6))
			var sign_node: Node3D = RoadSignScene.instantiate()
			sign_node.position = Vector3(point.x, ground_height(point.x, point.z), point.z)
			sign_node.rotation.y = atan2(-dir.x, -dir.z)
			parent.add_child(sign_node)
			last_sign = distance
		distance += 12.0


func _turn_ahead(distance: float, lookahead: float) -> float:
	var d0: Vector3 = network.direction_at(distance)
	var d1: Vector3 = network.direction_at(distance + lookahead)
	var h0: float = atan2(d0.x, d0.z)
	var h1: float = atan2(d1.x, d1.z)
	return atan2(sin(h1 - h0), cos(h1 - h0))


# ---------------------------------------------------------------- разметка


func _spawn_route_markers() -> void:
	if generated == null:
		return
	var container := Node3D.new()
	container.name = "RouteMarkers"
	generated.add_child(container)
	_create_gate(container, start_pos, start_dir, Color(0.20, 0.80, 1.0))
	_create_gate(container, finish_pos, finish_dir, Color(1.0, 0.48, 0.08))


func _create_gate(container: Node3D, pos: Vector3, dir: Vector3, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.35
	material.emission_energy_multiplier = 0.5
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.18, 3.2, 0.18)
	post_mesh.surface_set_material(0, material)
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(track.road_half_width * 2.0 + 1.0, 0.18, 0.18)
	bar_mesh.surface_set_material(0, material)
	var gate := Node3D.new()
	gate.position = Vector3(pos.x, height_at(pos.x, pos.z), pos.z)
	gate.rotation.y = atan2(dir.x, dir.z)
	for side_sign in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		post.mesh = post_mesh
		post.position = Vector3(float(side_sign) * (track.road_half_width + 0.35), 1.6, 0.0)
		gate.add_child(post)
	var bar := MeshInstance3D.new()
	bar.mesh = bar_mesh
	bar.position = Vector3(0.0, 3.2, 0.0)
	gate.add_child(bar)
	container.add_child(gate)


## Красно-белые столбики по обочинам.
func _spawn_edge_posts() -> void:
	if generated == null or network == null:
		return
	var container := Node3D.new()
	container.name = "EdgePosts"
	generated.add_child(container)
	var material := StandardMaterial3D.new()
	material.albedo_color = track.edge_post_color
	material.roughness = 0.85
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.12, 1.0, 0.12)
	post_mesh.surface_set_material(0, material)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.92, 0.92, 0.88)
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(0.13, 0.16, 0.13)
	cap_mesh.surface_set_material(0, white)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = post_mesh
	var transforms: Array[Transform3D] = []
	var spacing: float = 26.0
	var distance: float = 14.0
	var lateral: float = corridor_half() + 1.8
	while distance < network.total_length - 8.0:
		var center: Vector3 = network.point_at(distance)
		var dir: Vector3 = network.direction_at(distance)
		var side := Vector3(dir.z, 0.0, -dir.x)
		for side_sign in [-1.0, 1.0]:
			var point: Vector3 = center + side * (lateral * float(side_sign))
			var y: float = ground_height(point.x, point.z)
			transforms.append(Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), Vector3(point.x, y, point.z)))
		distance += spacing
	multimesh.instance_count = transforms.size()
	for i in range(transforms.size()):
		multimesh.set_instance_transform(i, transforms[i])
	var multimesh_instance := MultiMeshInstance3D.new()
	multimesh_instance.name = "EdgePostMesh"
	multimesh_instance.multimesh = multimesh
	container.add_child(multimesh_instance)
	# Белые «шапки» — второй MultiMesh со сдвигом по высоте.
	var cap_multimesh := MultiMesh.new()
	cap_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	cap_multimesh.mesh = cap_mesh
	cap_multimesh.instance_count = transforms.size()
	for i in range(transforms.size()):
		var t: Transform3D = transforms[i]
		cap_multimesh.set_instance_transform(i, Transform3D(t.basis, t.origin + Vector3(0.0, 0.85, 0.0)))
	var cap_instance := MultiMeshInstance3D.new()
	cap_instance.name = "EdgePostCaps"
	cap_instance.multimesh = cap_multimesh
	container.add_child(cap_instance)


func _spawn_checkpoints() -> void:
	checkpoints.clear()
	if generated == null or network == null or track.checkpoint_interval <= 0.0:
		return
	var container := Node3D.new()
	container.name = "Checkpoints"
	generated.add_child(container)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.85, 0.20)
	material.emission_enabled = true
	material.emission = Color(0.35, 0.32, 0.07)
	material.emission_energy_multiplier = 0.5
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.16, 3.0, 0.16)
	post_mesh.surface_set_material(0, material)
	var banner_mesh := BoxMesh.new()
	banner_mesh.size = Vector3(track.road_half_width * 2.0 + 1.0, 0.22, 0.3)
	banner_mesh.surface_set_material(0, material)
	var distance: float = track.checkpoint_interval
	while distance < network.total_length - 40.0:
		var point: Vector3 = network.point_at(distance)
		var dir: Vector3 = network.direction_at(distance)
		var gate := Node3D.new()
		gate.name = "Checkpoint_%02d" % checkpoints.size()
		gate.position = Vector3(point.x, height_at(point.x, point.z), point.z)
		gate.rotation.y = atan2(dir.x, dir.z)
		for side_sign in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			post.mesh = post_mesh
			post.position = Vector3(float(side_sign) * (track.road_half_width + 0.35), 1.5, 0.0)
			gate.add_child(post)
		var banner := MeshInstance3D.new()
		banner.mesh = banner_mesh
		banner.position = Vector3(0.0, 3.0, 0.0)
		gate.add_child(banner)
		container.add_child(gate)
		checkpoints.append({
			"pos": Vector2(point.x, point.z),
			"tangent": Vector2(dir.x, dir.z),
			"distance": distance,
		})
		distance += track.checkpoint_interval


# ---------------------------------------------------------------- окружение


func _configure_world() -> void:
	# Погода «КАК НА ТРАССЕ» (weather == null) оставляет всё как в .tres.
	var night: bool = track.night_mode
	if weather != null:
		night = weather.resolve_night(track.night_mode)
	var sky_top: Color = _weather_sky_color(track.sky_top_color)
	var sky_horizon: Color = _weather_sky_color(track.sky_horizon_color)
	var fog_color: Color = _effective_fog_color()
	var fog_density: float = track.fog_density
	var volumetric: bool = track.volumetric_fog
	var volumetric_density: float = track.volumetric_fog_density
	var ambient_energy: float = track.ambient_energy
	var exposure: float = track.exposure
	var sun_energy: float = track.sun_energy
	var sun_color: Color = track.sun_color
	if weather != null:
		fog_density = clampf(
			track.fog_density * weather.fog_density_scale + weather.fog_density_add, 0.0, 0.06
		)
		volumetric = volumetric or weather.volumetric_fog
		volumetric_density = clampf(
			track.volumetric_fog_density * weather.fog_density_scale
			+ weather.fog_density_add * 0.5, 0.0, 0.05
		)
		ambient_energy *= weather.ambient_energy_scale
		exposure *= weather.exposure_scale
		sun_energy *= weather.sun_energy_scale
		sun_color = track.sun_color.lerp(weather.sun_tint, weather.sun_tint_strength)
	if world_environment != null:
		var env: Environment = null
		if world_environment.environment != null:
			env = world_environment.environment.duplicate() as Environment
		if env == null:
			env = Environment.new()
		var sky := Sky.new()
		if night:
			var night_material := ShaderMaterial.new()
			night_material.shader = NightSkyShader
			night_material.set_shader_parameter("sky_top_color", sky_top)
			night_material.set_shader_parameter("sky_horizon_color", sky_horizon)
			night_material.set_shader_parameter("star_intensity", track.star_intensity)
			sky.sky_material = night_material
		else:
			var day_material := ProceduralSkyMaterial.new()
			day_material.sky_top_color = sky_top
			day_material.sky_horizon_color = sky_horizon
			day_material.ground_bottom_color = track.ground_color * 0.4
			day_material.ground_horizon_color = sky_horizon
			day_material.sky_curve = 0.55 if track.sky_flat else 0.18
			sky.sky_material = day_material
		env.background_mode = Environment.BG_SKY
		env.background_energy_multiplier = 1.0
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = track.ambient_color
		env.ambient_light_energy = ambient_energy
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = exposure
		env.glow_enabled = true
		env.glow_intensity = 0.45
		env.glow_bloom = 0.02
		env.ssao_enabled = track.screen_space_ao
		env.ssao_radius = 1.2
		env.ssao_intensity = 1.0
		env.volumetric_fog_enabled = volumetric and not track.ps1_style
		env.volumetric_fog_density = volumetric_density
		env.volumetric_fog_albedo = Color(0.68, 0.73, 0.82)
		if weather != null:
			env.volumetric_fog_albedo = weather.fog_color.lerp(
				Color(0.68, 0.73, 0.82), 0.4
			)
		env.volumetric_fog_anisotropy = 0.35
		env.volumetric_fog_length = 90.0
		env.fog_enabled = fog_density > 0.0
		env.fog_light_color = fog_color
		env.fog_density = fog_density
		world_environment.environment = env
	if sun_light != null:
		sun_light.rotation = Vector3(deg_to_rad(track.sun_pitch), deg_to_rad(track.sun_yaw), 0.0)
		sun_light.light_color = sun_color
		sun_light.light_energy = sun_energy


## Цвет неба трассы с поправкой погоды (подмешать тон + обесцветить).
func _weather_sky_color(base: Color) -> Color:
	if weather == null:
		return base
	var result: Color = base.lerp(weather.sky_tint, weather.sky_tint_strength)
	if weather.sky_desaturation > 0.0:
		var luminance: float = result.get_luminance()
		result = result.lerp(
			Color(luminance, luminance, luminance, result.a), weather.sky_desaturation
		)
	return result


func _effective_fog_color() -> Color:
	if weather == null:
		return track.fog_color
	return track.fog_color.lerp(weather.fog_color, weather.fog_color_strength)


## Осадки — настоящие частицы вокруг машины, а не «плёночный» фильтр:
## кубик эмиссии едет за автомобилем, сами частицы живут в мировых
## координатах, поэтому дождь не «прилипает» к камере.
func _setup_precipitation() -> void:
	if _weather_particles != null:
		_weather_particles.queue_free()
		_weather_particles = null
	if weather == null or not weather.has_precipitation():
		return
	# В headless (тесты, выделенный сервер) частицы не нужны.
	if DisplayServer.get_name() == "headless":
		return
	var intensity: float = clampf(weather.precipitation_intensity, 0.0, 1.0)
	var particles := GPUParticles3D.new()
	particles.name = "WeatherParticles"
	# Пауза останавливает и дождь: иначе капли «висят» над машиной в паузе.
	particles.process_mode = Node.PROCESS_MODE_PAUSABLE
	particles.amount = maxi(1, int(lerpf(700.0, 2600.0, intensity) * precipitation_density))
	particles.lifetime = 2.4
	particles.preprocess = 2.0
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-80.0, -40.0, -80.0), Vector3(160.0, 90.0, 160.0))
	var particle_material := ParticleProcessMaterial.new()
	particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	particle_material.emission_box_extents = Vector3(28.0, 10.0, 28.0)
	# Ветер сносит осадки в сторону — дождь идёт «по косой».
	var wind := Vector3(weather.wind_speed, 0.0, weather.wind_speed * 0.35)
	var quad := QuadMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if weather.precipitation == WeatherType.Precipitation.RAIN:
		particle_material.direction = (Vector3.DOWN + wind.normalized() * 0.15).normalized()
		particle_material.spread = 3.0
		particle_material.initial_velocity_min = 26.0
		particle_material.initial_velocity_max = 34.0
		particle_material.gravity = Vector3(0.0, -30.0, 0.0)
		particle_material.scale_min = 0.7
		particle_material.scale_max = 1.3
		quad.size = Vector2(0.028, 0.55)
		material.albedo_color = Color(0.72, 0.82, 0.95, 0.45)
	else:
		particle_material.direction = (Vector3.DOWN + wind.normalized() * 0.4).normalized()
		particle_material.spread = 25.0
		particle_material.initial_velocity_min = 1.2
		particle_material.initial_velocity_max = 3.0
		particle_material.gravity = Vector3(wind.x * 0.25, -1.6, wind.z * 0.25)
		particle_material.scale_min = 0.6
		particle_material.scale_max = 1.8
		quad.size = Vector2(0.09, 0.09)
		material.albedo_color = Color(0.96, 0.98, 1.0, 0.85)
	quad.material = material
	particles.process_material = particle_material
	particles.draw_pass_1 = quad
	add_child(particles)
	_weather_particles = particles


# ---------------------------------------------------------------- машина


func _configure_car() -> void:
	car = get_node_or_null("RallyCar") as CarType
	if car == null:
		push_warning("RallyStage: узел RallyCar не найден.")
		return
	car.process_mode = Node.PROCESS_MODE_PAUSABLE
	car.apply_track_grip(track.grip_scale, track.rolling_resistance_scale, track.offroad_grip)
	car.spawn_transform = _make_spawn_transform()
	car.reset_to_spawn()
	# Провайдер сброса появляется только после стартовой расстановки: иначе
	# первая же установка машины уехала бы в «ближайшую точку трассы».
	car.reset_provider = Callable(self, "_rescue_transform")
	# Порог падения считаем от земли, а не от абсолютного нуля: сгенерированная
	# «Живая лента» уходит на десятки метров ниже 0, и старый порог −20 м
	# бесконечно возвращал машину в ту же низкую точку.
	car.fall_limit_provider = Callable(self, "_fall_limit_y")


## Нижняя граница «машина упала в бездну»: на 25 м ниже земли под ней.
## Абсолютный порог здесь не годится — полотно может законно лежать ниже нуля
## (процедурная трасса, перевал), и тогда сброс срабатывал бы каждый кадр.
func _fall_limit_y() -> float:
	if car == null or network == null:
		return -1.0e9
	return height_at(car.global_position.x, car.global_position.z) - 25.0


## Точка сброса по клавише R: ближайшая точка дороги впереди/рядом, чтобы
## машина, застрявшая на обочине или в кювете, вернулась на трассу.
func _rescue_transform() -> Transform3D:
	if network == null:
		return _make_spawn_transform()
	var here: Vector2 = Vector2(car.global_position.x, car.global_position.z)
	var along: float = clampf(network.along_road(here.x, here.y), 8.0, network.total_length - 8.0)
	var point: Vector3 = network.point_at(along)
	var dir: Vector3 = network.direction_at(along)
	var y: float = height_at(point.x, point.z) + (car.get_spawn_height_offset() + 0.12)
	return Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), Vector3(point.x, y, point.z))


func _make_spawn_transform() -> Transform3D:
	var point: Vector3 = network.point_at(14.0)
	var dir: Vector3 = network.direction_at(14.0)
	var height_offset: float = 0.15
	if car != null:
		height_offset = car.get_spawn_height_offset() + 0.12
	var y: float = height_at(point.x, point.z) + height_offset
	# В проекте forward машины — basis.z (модель смотрит в +Z).
	return Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), Vector3(point.x, y, point.z))


# ---------------------------------------------------------------- HUD
# Разметка HUD живёт в scenes/ui/rally_hud.tscn (инстанс «RallyHUD» внутри
# CanvasLayer «HUD» в rally_stage.tscn). Панели, подписи, шкалы, модалки и
# мини-карта — настоящие узлы: стиль, тексты и позиции правятся в редакторе.
# Ниже — только связывание узлов с игровой логикой. Пути соответствуют
# дереву в rally_hud.tscn — поправьте их, если там переименуете узлы.


func _hud_node(path: String) -> Node:
	if hud == null:
		return null
	return hud.get_node_or_null(path)


func _setup_hud() -> void:
	if hud == null:
		return
	if _hud_ready:
		return
	_hud_ready = true
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	# Эффекты мира под HUD: даже при отключённом blur остаётся мягкая стилизация.
	speed_rect = hud.get_node_or_null("SpeedShaderRect") as ColorRect
	if speed_rect == null:
		speed_rect = ColorRect.new()
		speed_rect.name = "SpeedShaderRect"
		speed_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(speed_rect)
		speed_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hud.move_child(speed_rect, 0)
		speed_fx_material = ShaderMaterial.new()
		speed_fx_material.shader = SpeedShader
		speed_rect.material = speed_fx_material
	else:
		speed_fx_material = speed_rect.material as ShaderMaterial
	speed_rect.visible = true
	if speed_fx_material != null:
		speed_fx_material.set_shader_parameter("retro_strength", retro_style_strength)

	if weather != null and weather.has_precipitation():
		var weather_rect := ColorRect.new()
		weather_rect.name = "WeatherMotionRect"
		weather_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(weather_rect)
		weather_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hud.move_child(weather_rect, 1)
		weather_motion_material = ShaderMaterial.new()
		weather_motion_material.shader = WeatherMotionShader
		weather_motion_material.set_shader_parameter("weather_intensity", clampf(weather.precipitation_intensity * weather_motion_strength, 0.0, 1.0))
		weather_motion_material.set_shader_parameter("is_snow", 1.0 if weather.precipitation == WeatherType.Precipitation.SNOW else 0.0)
		weather_rect.material = weather_motion_material

	# Панель этапа (название трассы задаётся из конфига).
	var stage_title := _hud_node("RallyHUD/StagePanel/StageBox/StageTitle") as Label
	stage_label = _hud_node("RallyHUD/StagePanel/StageBox/StageLabel") as Label
	if stage_title != null:
		stage_title.text = track.display_name

	# Таймер и сплиты.
	timer_label = _hud_node("RallyHUD/TimerPanel/TimerBox/TimerLabel") as Label
	split_label = _hud_node("RallyHUD/TimerPanel/TimerBox/SplitLabel") as Label

	# Мини-карта — узел из сцены, экспорты (цвета) editable прямо в инспекторе.
	mini_map = _hud_node("RallyHUD/MiniMap") as MiniMap
	_populate_mini_map()

	# Спидометр.
	speed_label = _hud_node("RallyHUD/SpeedPanel/SpeedBox/SpeedLabel") as Label
	gear_label = _hud_node("RallyHUD/SpeedPanel/SpeedBox/GearLabel") as Label
	drivetrain_label = _hud_node("RallyHUD/SpeedPanel/SpeedBox/DrivetrainLabel") as Label
	rpm_bar = _hud_node("RallyHUD/SpeedPanel/SpeedBox/RPMBar") as ProgressBar

	# Телеметрия.
	telemetry_label = _hud_node("RallyHUD/TelemetryPanel/TeleBox/TelemetryLabel") as Label
	throttle_bar = _hud_node("RallyHUD/TelemetryPanel/TeleBox/ThrottleBar") as GaugeBar
	brake_bar = _hud_node("RallyHUD/TelemetryPanel/TeleBox/BrakeBar") as GaugeBar
	steer_bar = _hud_node("RallyHUD/TelemetryPanel/TeleBox/SteerBar") as GaugeBar
	slip_bar = _hud_node("RallyHUD/TelemetryPanel/TeleBox/SlipBar") as GaugeBar
	suspension_bar = _hud_node("RallyHUD/TelemetryPanel/TeleBox/SuspensionBar") as GaugeBar
	gforce_bar = _hud_node("RallyHUD/TelemetryPanel/TeleBox/GForceBar") as GaugeBar

	# Пауза / финиш: панели скрыты в сцене, кнопки связываем с обработчиками.
	pause_panel = _hud_node("RallyHUD/PausePanel") as PanelContainer
	var camera_settings := _hud_node("RallyHUD/PausePanel/Box/CameraOptions")
	if camera_settings != null and camera_settings.has_method("initialize"):
		camera_settings.call("initialize", car)
	results_panel = _hud_node("RallyHUD/ResultsPanel") as PanelContainer
	results_label = _hud_node("RallyHUD/ResultsPanel/Box/ResultsLabel") as Label
	var buttons := [
		["RallyHUD/PausePanel/Box/ResumeButton", "resume_pressed"],
		["RallyHUD/PausePanel/Box/RestartButton", "restart_pressed"],
		["RallyHUD/PausePanel/Box/MenuButton", "menu_pressed"],
		["RallyHUD/PausePanel/Box/QuitButton", "quit_pressed"],
		["RallyHUD/ResultsPanel/Box/AgainButton", "restart_pressed"],
		["RallyHUD/ResultsPanel/Box/MenuButton", "menu_pressed"],
	]
	pause_buttons.clear()
	for entry in buttons:
		var button := _hud_node(entry[0]) as Button
		if button != null:
			button.focus_mode = Control.FOCUS_ALL
			pause_buttons.append(button)
			if not button.pressed.is_connected(_on_button_pressed):
				button.pressed.connect(_on_button_pressed.bind(entry[1]))
	resume_button = _hud_node("RallyHUD/PausePanel/Box/ResumeButton") as Button
	again_button = _hud_node("RallyHUD/ResultsPanel/Box/AgainButton") as Button

	# Слайдеры и кнопки в модалках тоже должны принимать фокус: иначе
	# стрелками/D-pad в паузе нельзя дойти до настроек.
	for panel in [pause_panel, results_panel]:
		if panel == null:
			continue
		for node in panel.find_children("*", "Control", true, false):
			var control := node as Control
			if control is BaseButton or control is Range:
				control.focus_mode = Control.FOCUS_ALL

	hint_label = _hud_node("RallyHUD/Hint") as Label
	_update_input_hint()
	var controller := _controller_manager()
	if controller != null and controller.has_signal("active_device_changed"):
		if not controller.is_connected("active_device_changed", _on_active_input_device_changed):
			controller.connect("active_device_changed", _on_active_input_device_changed)


func _controller_manager() -> Node:
	return get_node_or_null("/root/ControllerManager")


func _on_active_input_device_changed(_gamepad_active: bool) -> void:
	_update_input_hint()


## Подсказка внизу HUD: на геймпаде — его собственные символы кнопок
## (✕/○/□/△, A/B/X/Y, B/A/Y/X), на клавиатуре — прежняя строка.
func _update_input_hint() -> void:
	if hint_label == null:
		return
	var controller := _controller_manager()
	if controller != null and bool(controller.get("gamepad_active")) and controller.has_method("get_glyphs"):
		var glyphs: Dictionary = controller.call("get_glyphs")
		hint_label.text = "[%s] ГАЗ  •  [%s] ТОРМОЗ  •  [%s] РУЛЬ  •  [%s] РУЧНИК  •  [%s] КАМЕРА  •  [%s/%s] КПП  •  [%s] ПРИВОД  •  [%s] ПАУЗА" % [
			String(glyphs["r2"]), String(glyphs["l2"]), String(glyphs["stick"]),
			String(glyphs["cancel"]), String(glyphs["north"]),
			String(glyphs["r1"]), String(glyphs["l1"]),
			String(glyphs["l3"]), String(glyphs["start"]),
		]
	else:
		hint_label.text = "[W/S] ГАЗ/ТОРМОЗ  •  [A/D] РУЛЬ  •  [SPACE] РУЧНИК  •  [C] КАМЕРА  •  [V] ПРИВОД  •  [R] СБРОС  •  [ESC] ПАУЗА"


func _on_button_pressed(action: String) -> void:
	match action:
		"resume_pressed":
			_on_resume_pressed()
		"restart_pressed":
			_on_restart_pressed()
		"menu_pressed":
			_on_menu_pressed()
		"quit_pressed":
			_on_quit_pressed()


func _update_hud() -> void:
	if car == null:
		return
	if timer_label != null:
		timer_label.text = _format_time(stage_time)
	if rpm_bar != null:
		rpm_bar.max_value = car.max_rpm
		rpm_bar.value = car.current_rpm
	if stage_label != null:
		var conditions: String = ""
		if weather != null:
			conditions += "  |  %s" % weather.display_name
		if track_profile != null:
			conditions += "  |  %s" % track_profile.display_name
		stage_label.text = "%s  |  %.0f м  |  %s  |  УРОВЕНЬ %d/5%s" % [
			track.display_name,
			network.total_length if network != null else 0.0,
			track.surface_name,
			track.difficulty,
			conditions
		]
	if split_label != null:
		if stage_finished:
			split_label.text = "ФИНИШ!  %s" % _format_time(stage_time)
		elif last_cp_index >= 0 and cp_times[last_cp_index] > 0.0:
			var best_split: float = 0.0
			var game: Node = get_node_or_null("/root/RallyGame")
			if game != null:
				best_split = float(game.call("get_best_split", _split_key(last_cp_index)))
			var line: String = "КПП%d %s" % [last_cp_index + 1, _format_time(cp_times[last_cp_index])]
			if best_split > 0.0:
				line += "  |  РЕКОРД %s" % _format_time(best_split)
			split_label.text = line
		else:
			split_label.text = "ЦЕЛЬ %s" % _format_time(track.target_time)
		if show_debug_info:
			split_label.text += "  | cell %.1f" % track.terrain_cell
	# Спидометр.
	if speed_label != null:
		speed_label.text = str(int(round(car.speed_kmh))).lpad(3, "0")
	if gear_label != null:
		gear_label.text = "%s  |  %s" % [car.get_gear_label(), car.get_drivetrain_label()]
	if drivetrain_label != null:
		drivetrain_label.text = car.get_drivetrain_label()
	# Телеметрия.
	if throttle_bar != null:
		throttle_bar.set_value(car.throttle_amount)
	if brake_bar != null:
		brake_bar.set_value(car.brake_amount)
	if steer_bar != null:
		steer_bar.set_value(car.steering_amount)
	if slip_bar != null:
		slip_bar.set_value(clampf(car.get_average_tire_slip(), 0.0, 1.0))
	if suspension_bar != null:
		suspension_bar.set_value(car.get_max_suspension_compression())
	if gforce_bar != null:
		var accel: Vector3 = (car.linear_velocity - _prev_lin_vel) / maxf(_frame_delta, 0.0001)
		_prev_lin_vel = car.linear_velocity
		gforce_bar.set_value(clampf(Vector2(accel.x, accel.z).length() / 9.81, 0.0, 1.0))
	# Мини-карта.
	if mini_map != null:
		var forward: Vector3 = car.global_transform.basis.z
		var heading: float = atan2(-forward.x, -forward.z)
		mini_map.set_car(Vector2(car.global_position.x, car.global_position.z), heading)
		var progress: float = 0.0
		if network != null and network.total_length > 0.0:
			progress = clampf(
				network.along_road(car.global_position.x, car.global_position.z) / network.total_length,
				0.0, 1.0
			)
		mini_map.set_progress(progress)


func _populate_mini_map() -> void:
	if mini_map == null or network == null:
		return
	var route := PackedVector2Array()
	for p in network.samples:
		route.append(Vector2(p.x, p.z))
	var cps := PackedVector2Array()
	for cp in checkpoints:
		cps.append(cp["pos"])
	mini_map.set_route(
		route,
		cps,
		Vector2(start_pos.x, start_pos.z),
		Vector2(finish_pos.x, finish_pos.z)
	)


## Рекорд с учётом условий заезда. Погода и профиль полотна меняют сцепление,
## поэтому сухой асфальт и мокрая глина — разные таблицы рекордов.
func _record_key() -> String:
	var game: Node = get_node_or_null("/root/RallyGame")
	if game != null and game.has_method("record_key_for"):
		return String(game.call("record_key_for", track))
	return track.get_record_key()


func _split_key(cp_index: int) -> String:
	return "%s_cp%d" % [_record_key(), cp_index]


func _format_time(seconds: float) -> String:
	var minutes: int = floori(seconds / 60.0)
	var remaining: float = fmod(seconds, 60.0)
	return "%02d:%06.3f" % [minutes, remaining]


# ---------------------------------------------------------------- цикл


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_process_editor(delta)
		return
	if not _stage_live:
		# Идёт генерация мира (экран загрузки): машину и HUD не трогаем.
		return
	# Осадки летят вокруг машины: эмиттер над капотом, частицы — в мире.
	if _weather_particles != null and car != null:
		# На скорости генератор смотрит вперёд по фактической скорости, а не
		# по направлению кузова: во время заноса перед камерой нет пустоты.
		var lead: Vector3 = car.linear_velocity * 0.35
		lead.y = 0.0
		_weather_particles.global_position = car.global_position + lead.limit_length(18.0) + Vector3(0.0, 12.0, 0.0)
	if Input.is_action_just_pressed("pause"):
		_set_paused(not is_paused)
		return
	if is_paused:
		# B/○ на геймпаде и Esc на клавиатуре закрывают паузу.
		if Input.is_action_just_pressed("ui_cancel"):
			_set_paused(false)
		return
	if Input.is_action_just_pressed("reset_car"):
		stage_time = 0.0
		timer_running = false
		stage_finished = false
		last_cp_index = -1
		cp_triggered.fill(false)
		cp_times.fill(0.0)
	if not stage_finished:
		if Input.get_action_strength("throttle") > 0.05:
			timer_running = true
		if timer_running:
			stage_time += delta
		_check_checkpoints()
		_check_finish()
	var speed: float = car.speed_kmh if car != null else 0.0
	if speed_fx_material != null:
		var intensity: float = clampf((speed - 65.0) / 115.0 * speed_effect_strength, 0.0, 1.0) if track.enable_speed_fx else 0.0
		speed_fx_material.set_shader_parameter("speed_intensity", intensity)
	if weather_motion_material != null and car != null:
		var motion: float = smoothstep(20.0, 120.0, speed)
		_weather_phase += delta * lerpf(2.0, 13.0, motion)
		# Скорость проецируем в систему активной камеры: вид с капота,
		# кабины, камеры сзади и боковой занос работают одинаково.
		var camera: Camera3D = car.active_camera
		var sideways: float = 0.0
		if camera != null:
			var camera_velocity: Vector3 = camera.global_basis.inverse() * car.linear_velocity
			sideways = clampf(-camera_velocity.x / 25.0, -1.5, 1.5)
		weather_motion_material.set_shader_parameter("flow", Vector2(sideways, 1.0))
		weather_motion_material.set_shader_parameter("phase", _weather_phase)
		weather_motion_material.set_shader_parameter("speed_intensity", motion)
	_frame_delta = delta
	_update_hud()


## Отложенная пересборка в редакторе (см. REBUILD_DELAY).
func _process_editor(delta: float) -> void:
	if not _rebuild_pending:
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		# Пока тянем точку мышью — не пересобираем, чтобы редактор не подвисал
		# посреди перетаскивания.
		_rebuild_timer = 0.0
		return
	_rebuild_timer += delta
	if _rebuild_timer < REBUILD_DELAY:
		return
	_rebuild_pending = false
	_rebuild_timer = 0.0
	var from_track: bool = _pending_from_track
	_pending_from_track = false
	if not preview_in_editor or not is_inside_tree():
		return
	# Кривая могла «измениться» без реального сдвига точек (выделение,
	# повторный клик) — тогда тяжёлый пересчёт не нужен.
	var signature: float = _curve_signature(_effective_curve())
	if not from_track and is_equal_approx(signature, _built_curve_signature):
		return
	rebuild_preview()


func _check_checkpoints() -> void:
	if car == null or not timer_running:
		return
	var forward := car.global_transform.basis.z
	for i in range(checkpoints.size()):
		if cp_triggered[i]:
			continue
		var cp: Dictionary = checkpoints[i]
		var dx: float = car.global_position.x - cp["pos"].x
		var dz: float = car.global_position.z - cp["pos"].y
		if dx * dx + dz * dz < 16.0:
			var tangent := Vector3(cp["tangent"].x, 0.0, cp["tangent"].y)
			if forward.dot(tangent) > 0.3:
				cp_triggered[i] = true
				cp_times[i] = stage_time
				last_cp_index = i
				var game: Node = get_node_or_null("/root/RallyGame")
				if game != null:
					game.call("submit_split", _split_key(i), stage_time)
				var controller := _controller_manager()
				if controller != null and controller.has_method("rumble"):
					controller.call("rumble", 0.18, 0.22, 0.10)


func _check_finish() -> void:
	if car == null or not timer_running:
		return
	var dx: float = car.global_position.x - finish_pos.x
	var dz: float = car.global_position.z - finish_pos.z
	var tolerance: float = track.road_half_width + 4.0
	if dx * dx + dz * dz > tolerance * tolerance:
		return
	var forward := car.global_transform.basis.z
	if forward.dot(finish_dir) > 0.35:
		_finish_stage()


func _finish_stage() -> void:
	stage_finished = true
	timer_running = false
	var game: Node = get_node_or_null("/root/RallyGame")
	is_new_record = false
	if game != null:
		is_new_record = bool(game.call("submit_time", _record_key(), stage_time))
		best_time = float(game.call("get_best_time", _record_key()))
	if results_panel != null:
		results_panel.visible = true
		if results_label != null:
			var record_line: String = "НОВЫЙ РЕКОРД!" if is_new_record else "ЛУЧШЕЕ: %s" % _format_time(best_time)
			results_label.text = "%s\n\nВРЕМЯ  %s\n%s" % [track.display_name, _format_time(stage_time), record_line]
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if again_button != null:
		again_button.grab_focus()
	var controller := _controller_manager()
	if controller != null and controller.has_method("rumble"):
		controller.call("rumble", 0.45, 0.85, 0.45)


func _set_paused(value: bool) -> void:
	is_paused = value
	get_tree().paused = value
	if pause_panel != null:
		pause_panel.visible = value
	if value:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if resume_button != null:
			resume_button.grab_focus()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if car != null and car.mouse_look_enabled else Input.MOUSE_MODE_VISIBLE
		if not stage_finished and is_inside_tree():
			get_viewport().gui_release_focus()


func _on_resume_pressed() -> void:
	_set_paused(false)


func _on_restart_pressed() -> void:
	var game: Node = get_node_or_null("/root/RallyGame")
	if game != null:
		game.call("restart_race")
	else:
		_reload_scene()


func _on_menu_pressed() -> void:
	var game: Node = get_node_or_null("/root/RallyGame")
	if game != null:
		game.call("goto_menu")
	else:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_quit_pressed() -> void:
	var game: Node = get_node_or_null("/root/RallyGame")
	if game != null:
		game.call("quit_game")
	else:
		get_tree().quit()


func _reload_scene() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
