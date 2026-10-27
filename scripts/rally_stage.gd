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
const GameConfigType = preload("res://scripts/data/rally_game_config.gd")
const RoadNetworkType = preload("res://scripts/road_network.gd")
const GroundShader = preload("res://shaders/forest_ground.gdshader")
const MiniMapType = preload("res://scripts/ui/mini_map.gd")
const GaugeBarType = preload("res://scripts/ui/gauge_bar.gd")

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
var _hud_ready := false
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

# HUD-узлы строятся кодом в _setup_hud(): гоночная панель, телеметрия и
# мини-карта. Ссылки держим, чтобы обновлять их в _update_hud.
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
	_build_world()
	_configure_car()
	_setup_hud()
	_update_hud()


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


# ---------------------------------------------------------------- сборка мира


## Осевая линия. ПЕРВЫЙ источник — узел Route (Path3D) прямо в сцене: его
## кривую видно и можно тянуть точками в 3D-вьюпорте. Ресурс road_curve —
## только запасной вариант для сцен без Path3D.
func _effective_curve() -> Curve3D:
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
	var curve: Curve3D = _effective_curve()
	if track == null or curve == null:
		push_warning("RallyStage: нет осевой линии (road_curve в трассе или узел Route/Path3D).")
		return
	_clear_generated()
	_setup_noise()
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
	_build_terrain()
	_build_road()
	if snap_props_on_build:
		# Только «лес» из Props: ручные объекты в ManualProps не двигаем,
		# их можно поставить руками на нужную высоту.
		_snap_prop_nodes(false)
	if track.spawn_route_markers:
		_spawn_route_markers()
	if track.spawn_edge_posts:
		_spawn_edge_posts()
	if track.spawn_checkpoints:
		_spawn_checkpoints()
	cp_triggered.resize(checkpoints.size())
	cp_times.clear()
	for i in range(checkpoints.size()):
		cp_triggered[i] = false
		cp_times.append(0.0)


func _setup_noise() -> void:
	_noise_hills = _make_noise(track.terrain_seed, track.hills_frequency, 3)
	_noise_ridge = _make_noise(track.terrain_seed + 91, track.ridge_frequency, 4)
	_noise_detail = _make_noise(track.terrain_seed + 173, track.detail_frequency, 2)
	_noise_bumps = _make_noise(track.terrain_seed + 257, 0.35, 2)
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
	var corridor: float = track.road_half_width + track.road_shoulder
	var distance: float = network.distance_to_road(x, z)
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
	var wave: float = sin(along * TAU / maxf(track.bumps_wavelength, 0.5))
	var roughness: float = _noise_bumps.get_noise_1d(along * 5.0)
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


func _build_terrain() -> void:
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
			heights[index] = height_at(x, z)
			distances[index] = network.distance_to_road(x, z)

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
	#    Ячейки у самой дороги не двигаются — там всё уже сходится с полотном.
	heights = _limit_terrain_slopes(heights, distances, cols, rows, cell)
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

	# 5) Индексы: строго под полотном треугольники не нужны — там лежит лента
	#    дороги (она закрывает дыру и держит коллизию). Считается по сетке
	#    расстояний, без повторных запросов к дороге. На «крышках» старта/
	#    финиша дыру не делаем — там ленты спереди нет, оставляем рельеф.
	var indices := PackedInt32Array()
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
			indices.append(i00)
			indices.append(i10)
			indices.append(i01)
			indices.append(i10)
			indices.append(i11)
			indices.append(i01)

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
	cell: float
) -> PackedFloat32Array:
	var max_slope: float = tan(deg_to_rad(clampf(track.max_terrain_slope_deg, 20.0, 75.0)))
	var max_delta: float = cell * max_slope
	# Якоря — только сама дорога и обочина (полотно + 0.5 м), иначе у тесной
	# шпильки между двумя «жёсткими» ячейками остаётся стенка.
	var anchor_distance: float = track.road_half_width + track.road_shoulder + 0.5
	var anchored := PackedByteArray()
	anchored.resize(cols * rows)
	var dirty := PackedInt32Array()
	for gz in range(rows):
		for gx in range(cols):
			var index: int = gz * cols + gx
			if distances[index] < anchor_distance:
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
	material.set_shader_parameter("ground_color", track.ground_color)
	material.set_shader_parameter("ground_color_2", track.ground_color_2)
	material.set_shader_parameter("road_edge_color", track.shoulder_color)
	material.set_shader_parameter("rock_color", track.rock_color)
	material.set_shader_parameter("surface_roughness", 0.97)
	material.set_shader_parameter("grain_scale", 2.4)
	material.set_shader_parameter("flat_shading", 1.0 if track.flat_shading else 0.0)
	material.set_shader_parameter("dither_fog", 1.0 if track.dither_fog else 0.0)
	material.set_shader_parameter("banding_levels", float(track.color_banding))
	material.set_shader_parameter("fog_color", track.fog_color)
	material.set_shader_parameter("fog_near", track.fog_near)
	material.set_shader_parameter("fog_far", track.fog_far)
	return material


# ---------------------------------------------------------------- полотно


## Лента дороги: меш + коллизия. Высота краёв совпадает с землёй (та же
## функция height_at), поэтому стык не просвечивает.
func _build_road() -> void:
	var step: float = maxf(0.5, track.road_step)
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
	vertices.resize(rows * lanes)
	normals.resize(rows * lanes)
	colors.resize(rows * lanes)
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

			var base_color: Color = track.road_color * shade
			base_color = base_color.lerp(track.road_color_2, color_rng.randf() * 0.45)
			var edge_factor: float = clampf((absf(lat) - half * 0.75) / maxf(half * 0.5, 0.01), 0.0, 1.0)
			if absf(lat) > half:
				base_color = base_color.lerp(track.shoulder_color, edge_factor)
			elif absf(lat) > half * 0.62:
				# Светлая кромка — «накатанная» полоса, по ней видно траекторию.
				base_color = base_color.lightened(0.08 * edge_factor)
			colors[row * lanes + lane] = base_color

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
	arrays[Mesh.ARRAY_INDEX] = indices
	var road_mesh := ArrayMesh.new()
	road_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var road_material := StandardMaterial3D.new()
	road_material.albedo_color = Color.WHITE
	road_material.vertex_color_use_as_albedo = true
	road_material.roughness = 1.0
	road_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	var road_visual := MeshInstance3D.new()
	road_visual.name = "RoadMesh"
	road_visual.mesh = road_mesh
	road_visual.material_override = road_material
	if generated != null:
		generated.add_child(road_visual)

	# Коллизия только по проезжей части (полотно + обочина).
	var faces := PackedVector3Array()
	for row in range(rows - 1):
		for lane in range(1, lanes - 2):
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


func _set_shape_faces(shape: ConcavePolygonShape3D, faces: PackedVector3Array) -> void:
	if shape.has_method("set_faces"):
		shape.call("set_faces", faces)
	else:
		shape.set("data", faces)


# ---------------------------------------------------------------- ассеты


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
	if world_environment != null:
		var env: Environment = null
		if world_environment.environment != null:
			env = world_environment.environment.duplicate() as Environment
		if env == null:
			env = Environment.new()
		var sky := Sky.new()
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = track.sky_top_color
		sky_material.sky_horizon_color = track.sky_horizon_color
		sky_material.ground_bottom_color = track.ground_color * 0.4
		sky_material.ground_horizon_color = track.sky_horizon_color
		sky_material.sky_curve = 0.55 if track.sky_flat else 0.18
		sky.sky_material = sky_material
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = 1.05
		env.glow_enabled = true
		env.volumetric_fog_enabled = not track.ps1_style
		env.volumetric_fog_density = 0.02
		env.volumetric_fog_albedo = track.fog_color
		env.fog_enabled = true
		env.fog_light_color = track.fog_color
		env.fog_density = 0.0032
		world_environment.environment = env
	if sun_light != null:
		sun_light.rotation = Vector3(deg_to_rad(track.sun_pitch), deg_to_rad(track.sun_yaw), 0.0)
		sun_light.light_energy = track.sun_energy


# ---------------------------------------------------------------- машина


func _configure_car() -> void:
	car = get_node_or_null("RallyCar") as CarType
	if car == null:
		push_warning("RallyStage: узел RallyCar не найден.")
		return
	car.process_mode = Node.PROCESS_MODE_PAUSABLE
	car.apply_track_grip(track.grip_scale, track.rolling_resistance_scale)
	car.spawn_transform = _make_spawn_transform()
	car.reset_to_spawn()
	# Провайдер сброса появляется только после стартовой расстановки: иначе
	# первая же установка машины уехала бы в «ближайшую точку трассы».
	car.reset_provider = Callable(self, "_rescue_transform")


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


func _hud_stylebox() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.content_margin_left = 16.0
	box.content_margin_top = 10.0
	box.content_margin_right = 16.0
	box.content_margin_bottom = 10.0
	box.bg_color = Color(0.03, 0.05, 0.07, 0.82)
	box.border_width_left = 2
	box.border_width_top = 2
	box.border_width_right = 2
	box.border_width_bottom = 2
	box.border_color = Color(0.95, 0.62, 0.12, 0.85)
	box.corner_radius_top_left = 6
	box.corner_radius_top_right = 6
	box.corner_radius_bottom_right = 6
	box.corner_radius_bottom_left = 6
	return box


func _styled_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _hud_stylebox())
	return panel


func _make_label(text: String, size: int, color: Color, outline: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if outline:
		label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.95))
		label.add_theme_constant_override("outline_size", maxi(3, int(size / 8)))
	return label


func _add_gauge_row(parent: VBoxContainer, title: String, color: Color, centered: bool) -> GaugeBar:
	parent.add_child(_make_label(title, 11, Color(0.62, 0.72, 0.82, 1.0)))
	var gauge := GaugeBarType.new()
	gauge.custom_minimum_size = Vector2(230.0, 10.0)
	gauge.bar_color = color
	gauge.centered = centered
	parent.add_child(gauge)
	return gauge


func _add_button(parent: Control, text: String, method: String) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(250, 40)
	button.add_theme_font_size_override("font_size", 16)
	parent.add_child(button)
	if not button.pressed.is_connected(Callable(self, method)):
		button.pressed.connect(Callable(self, method))


func _make_modal(title: String) -> PanelContainer:
	var panel := _styled_panel()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -240.0
	panel.offset_top = -190.0
	panel.offset_right = 240.0
	panel.offset_bottom = 190.0
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var heading := _make_label(title, 30, Color(1.0, 0.72, 0.25, 1.0))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)
	panel.add_child(box)
	return panel


func _setup_hud() -> void:
	if hud == null:
		return
	if _hud_ready:
		return
	_hud_ready = true
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	speed_rect = hud.get_node_or_null("SpeedShaderRect") as ColorRect
	if speed_rect != null:
		speed_fx_material = speed_rect.material as ShaderMaterial
		speed_rect.visible = track.enable_speed_fx

	# ---- панель этапа (верхний левый угол) ----
	var stage_panel := _styled_panel()
	stage_panel.anchor_left = 0.0
	stage_panel.anchor_top = 0.0
	stage_panel.offset_left = 14.0
	stage_panel.offset_top = 14.0
	stage_panel.offset_right = 334.0
	stage_panel.offset_bottom = 118.0
	var stage_box := VBoxContainer.new()
	stage_box.add_theme_constant_override("separation", 3)
	stage_panel.add_child(stage_box)
	var stage_title := _make_label(track.display_name, 20, Color(1.0, 0.72, 0.25, 1.0))
	stage_label = _make_label("", 14, Color(0.72, 0.83, 0.92, 1.0))
	stage_box.add_child(stage_title)
	stage_box.add_child(stage_label)
	hud.add_child(stage_panel)

	# ---- таймер (верхний центр) ----
	var timer_panel := _styled_panel()
	timer_panel.anchor_left = 0.5
	timer_panel.anchor_right = 0.5
	timer_panel.anchor_top = 0.0
	timer_panel.offset_left = -250.0
	timer_panel.offset_right = 250.0
	timer_panel.offset_top = 14.0
	timer_panel.offset_bottom = 146.0
	var timer_box := VBoxContainer.new()
	timer_box.add_theme_constant_override("separation", 2)
	timer_panel.add_child(timer_box)
	timer_label = _make_label("00:00.000", 58, Color(1.0, 0.97, 0.88, 1.0), true)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	split_label = _make_label("ЦЕЛЬ 00:00.000", 18, Color(0.30, 0.95, 0.55, 1.0), true)
	split_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_box.add_child(timer_label)
	timer_box.add_child(split_label)
	hud.add_child(timer_panel)

	# ---- мини-карта (верхний правый угол) ----
	mini_map = MiniMapType.new()
	mini_map.name = "MiniMap"
	mini_map.anchor_right = 1.0
	mini_map.anchor_top = 0.0
	mini_map.offset_right = -14.0
	mini_map.offset_top = 14.0
	mini_map.offset_left = -244.0
	mini_map.offset_bottom = 164.0
	hud.add_child(mini_map)
	_populate_mini_map()

	# ---- спидометр (нижний левый угол) ----
	var speed_panel := _styled_panel()
	speed_panel.anchor_left = 0.0
	speed_panel.anchor_bottom = 1.0
	speed_panel.offset_left = 14.0
	speed_panel.offset_bottom = -14.0
	speed_panel.offset_right = 334.0
	speed_panel.offset_top = -190.0
	var speed_box := VBoxContainer.new()
	speed_box.add_theme_constant_override("separation", 3)
	speed_panel.add_child(speed_box)
	speed_label = _make_label("000", 66, Color(1.0, 0.97, 0.88, 1.0), true)
	gear_label = _make_label("КПП 1  A", 20, Color(1.0, 0.72, 0.25, 1.0))
	drivetrain_label = _make_label("AWD 38:62", 14, Color(0.72, 0.83, 0.92, 1.0))
	rpm_bar = ProgressBar.new()
	rpm_bar.name = "RPMBar"
	rpm_bar.custom_minimum_size = Vector2(270.0, 12)
	rpm_bar.max_value = car.max_rpm if car != null else 7600.0
	rpm_bar.value = 900.0
	rpm_bar.show_percentage = false
	var rpm_caption := _make_label("РУГ 7600", 11, Color(0.60, 0.70, 0.80, 1.0))
	speed_box.add_child(speed_label)
	speed_box.add_child(gear_label)
	speed_box.add_child(drivetrain_label)
	speed_box.add_child(rpm_caption)
	speed_box.add_child(rpm_bar)
	hud.add_child(speed_panel)

	# ---- телеметрия (нижний правый угол) ----
	var tele_panel := _styled_panel()
	tele_panel.anchor_right = 1.0
	tele_panel.anchor_bottom = 1.0
	tele_panel.offset_right = -14.0
	tele_panel.offset_bottom = -14.0
	tele_panel.offset_left = -304.0
	tele_panel.offset_top = -244.0
	var tele_box := VBoxContainer.new()
	tele_box.add_theme_constant_override("separation", 6)
	telemetry_label = _make_label("ТЕЛЕМЕТРИЯ", 14, Color(1.0, 0.72, 0.25, 1.0))
	tele_box.add_child(telemetry_label)
	throttle_bar = _add_gauge_row(tele_box, "ГАЗ", Color(0.30, 0.90, 0.42, 1.0), false)
	brake_bar = _add_gauge_row(tele_box, "ТОРМОЗ", Color(0.95, 0.30, 0.30, 1.0), false)
	steer_bar = _add_gauge_row(tele_box, "РУЛЬ", Color(0.98, 0.78, 0.20, 1.0), true)
	slip_bar = _add_gauge_row(tele_box, "СКОЛЬЗ.", Color(0.98, 0.55, 0.15, 1.0), false)
	suspension_bar = _add_gauge_row(tele_box, "ХОД", Color(0.35, 0.65, 0.98, 1.0), false)
	gforce_bar = _add_gauge_row(tele_box, "G", Color(0.75, 0.45, 0.98, 1.0), false)
	tele_panel.add_child(tele_box)
	hud.add_child(tele_panel)

	# ---- пауза / финиш ----
	pause_panel = _make_modal("ПАУЗА")
	var pause_box := pause_panel.get_child(0) as VBoxContainer
	_add_button(pause_box, "ПРОДОЛЖИТЬ", "_on_resume_pressed")
	_add_button(pause_box, "ЗАЕЗД ЗАНОВО", "_on_restart_pressed")
	_add_button(pause_box, "ГЛАВНОЕ МЕНЮ", "_on_menu_pressed")
	_add_button(pause_box, "ВЫХОД ИЗ ИГРЫ", "_on_quit_pressed")
	pause_panel.visible = false
	hud.add_child(pause_panel)

	results_panel = _make_modal("ФИНИШ")
	var results_box := results_panel.get_child(0) as VBoxContainer
	results_label = _make_label("", 22, Color(1.0, 0.95, 0.85, 1.0))
	results_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results_box.add_child(results_label)
	_add_button(results_box, "ЕЩЁ ЗАЕЗД", "_on_restart_pressed")
	_add_button(results_box, "ГЛАВНОЕ МЕНЮ", "_on_menu_pressed")
	results_panel.visible = false
	hud.add_child(results_panel)

	# ---- подсказка управления ----
	var hint := _make_label("[W/S] ГАЗ / ТОРМОЗ   [A/D] РУЛЬ   [SPACE] РУЧНИК   [C] КАМЕРА   [V] ПРИВОД   [R] СБРОС   [ESC] ПАУЗА", 13, Color(0.60, 0.70, 0.80, 0.75), true)
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.anchor_bottom = 1.0
	hint.offset_left = -340.0
	hint.offset_right = 340.0
	hint.offset_bottom = -14.0
	hint.offset_top = -46.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(hint)


func _update_hud() -> void:
	if car == null:
		return
	if timer_label != null:
		timer_label.text = _format_time(stage_time)
	if rpm_bar != null:
		rpm_bar.max_value = car.max_rpm
		rpm_bar.value = car.current_rpm
	if stage_label != null:
		stage_label.text = "%s  |  %.0f м  |  %s  |  УРОВЕНЬ %d/5" % [
			track.display_name,
			network.total_length if network != null else 0.0,
			track.surface_name,
			track.difficulty
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
		speed_label.text = str(int(round(car.speed_kmh))).rpad("0", 3)
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
		mini_map.set_progress(car_race_progress)


func _populate_mini_map() -> void:
	if mini_map == null or network == null:
		return
	var route := PackedVector2Array()
	for p in network.samples:
		route.append(Vector2(p.x, p.z))
	var cps := PackedVector2Array()
	for cp in checkpoints:
		var pos: Vector3 = cp["pos"]
		cps.append(Vector2(pos.x, pos.z))
	mini_map.set_route(
		route,
		cps,
		Vector2(start_pos.x, start_pos.z),
		Vector2(finish_pos.x, finish_pos.z)
	)


func _split_key(cp_index: int) -> String:
	return "%s_cp%d" % [track.id, cp_index]


func _format_time(seconds: float) -> String:
	var minutes: int = floori(seconds / 60.0)
	var remaining: float = fmod(seconds, 60.0)
	return "%02d:%06.3f" % [minutes, remaining]


# ---------------------------------------------------------------- цикл


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_process_editor(delta)
		return
	if Input.is_action_just_pressed("pause"):
		_set_paused(not is_paused)
	if is_paused:
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
	if speed_fx_material != null:
		var intensity: float = clampf(((car.speed_kmh if car != null else 0.0) - 70.0) / 130.0, 0.0, 1.0)
		speed_fx_material.set_shader_parameter("speed_intensity", intensity)
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
		is_new_record = bool(game.call("submit_time", track.get_record_key(), stage_time))
		best_time = float(game.call("get_best_time", track.get_record_key()))
	if results_panel != null:
		results_panel.visible = true
		if results_label != null:
			var record_line: String = "НОВЫЙ РЕКОРД!" if is_new_record else "ЛУЧШЕЕ: %s" % _format_time(best_time)
			results_label.text = "%s\n\nВРЕМЯ  %s\n%s" % [track.display_name, _format_time(stage_time), record_line]
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _set_paused(value: bool) -> void:
	is_paused = value
	get_tree().paused = value
	if pause_panel != null:
		pause_panel.visible = value
	if value:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if car != null and car.mouse_look_enabled else Input.MOUSE_MODE_VISIBLE


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
