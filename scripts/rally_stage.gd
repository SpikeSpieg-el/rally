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
##
## ПРАВИЛО РЕДАКТИРУЕМОСТИ (для людей и агентов): этот скрипт НЕ хранит
## настроек. Числа, цвета, размеры и пороги эффектов берутся из ресурсов,
## которые видны в инспекторе корня сцены:
##   settings      — RallyStageSettings (PS1, скорость, осадки, окружение,
##                   материалы обстановки, редактор);
##   spawn_layout  — RallySpawnLayout (старт/финиш, столбики, КПП, знаки,
##                   точка появления и «спасение» машины);
##   fx_profile    — RallyFxProfile (следы шин, грязь, брызги, пыль,
##                   скользкие полосы, физика колеи);
##   scenery       — RallySceneryConfig (какой лес/камни и как часто).
## Если поле пустое, подставляется файл из res://data/stage/. Меняйте
## значения в инспекторе — код подхватит их при следующей сборке (кнопка
## «Пересобрать трассу»).
@tool
class_name RallyStage
extends Node3D

const CarType = preload("res://scripts/rally_car.gd")
const InputSettings = preload("res://scripts/ui/input_settings.gd")
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
const BarkTexture = preload("res://textures/environment/bark.png")
const SpeedShader = preload("res://shaders/speed_fx.gdshader")
const Ps1Materials = preload("res://scripts/ps1_materials.gd")
const NightSkyShader = preload("res://shaders/night_sky.gdshader")
const RoadSignScene = preload("res://scenes/props/road_sign.tscn")
const StageSettingsType = preload("res://scripts/data/rally_stage_settings.gd")
const SpawnLayoutType = preload("res://scripts/data/rally_spawn_layout.gd")
const FxProfileType = preload("res://scripts/data/rally_fx_profile.gd")
const SceneryType = preload("res://scripts/data/rally_scenery_config.gd")
const VisualEffectsType = preload("res://scripts/effects/rally_visual_effects.gd")
const VisualEffectsScene = preload("res://scenes/effects/visual_effects.tscn")

## Файлы-«пульты» по умолчанию (если поле в сцене пустое).
const DEFAULT_SETTINGS_PATH := "res://data/stage/default_stage_settings.tres"
const DEFAULT_SPAWN_PATH := "res://data/stage/default_spawn_layout.tres"
const DEFAULT_FX_PATH := "res://data/stage/default_fx_profile.tres"
const DEFAULT_SCENERY_PATH := "res://data/stage/default_scenery.tres"

@export_group("Данные (перетащите ресурсы в инспектор)")
@export var game_config: GameConfigType = null
@export var track_override: TrackConfigType = null
@export var car_setup_override: CarSetupType = null

@export_group("Совместимость со старыми настройками")
## Старый общий ресурс. Новые визуальные настройки живут в VisualEffects и HUD/RetroScreen.
@export var settings: StageSettingsType = null
@export_storage var legacy_effects_imported: bool = false
@export_tool_button("Перенести старый ресурс в эффекты сцены") var import_legacy_button = import_legacy_effects
## Старт/финиш, столбики, арки КПП, знаки поворотов, спавн и спасение машины.
@export var spawn_layout: SpawnLayoutType = null
## Следы шин, грязь на кузове, брызги, пыль, скользкие полосы, физика колеи.
@export var fx_profile: FxProfileType = null
## Что и как часто генерируется вдоль трассы (лес, камни, подлесок).
@export var scenery: SceneryType = null

@export_group("Материалы (правятся прямо в сцене)")
## Материал земли. Пусто — создаётся из шейдера и настроек (рекомендуется).
@export var ground_material_override: Material = null
## Материал полотна. Пусто — создаётся из шейдера и настроек.
@export var road_material_override: Material = null

@export_group("Редактор")
@export_tool_button("Пересобрать трассу") var rebuild_button = rebuild_preview
@export_tool_button("Посадить ассеты на землю") var snap_button = snap_props_to_ground

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
var fx_nodes: VisualEffectsType = null
## Осадки (дождь/снег) летят вокруг машины, а не по всей карте.
var _weather_particles: GPUParticles3D = null
## Материал земли живёт столько же, сколько сцена: инспекторские правки
## не теряются при пересборке трассы.
var _ground_material: ShaderMaterial = null
## Материал полотна тоже переиспользуется между пересборками.
var _road_material: ShaderMaterial = null
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
# Сама задержка — поле settings.auto_rebuild_delay.
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
var clutch_notice: Label = null
var input_settings = null
var resume_button: Button = null
var again_button: Button = null
var pause_buttons: Array[Button] = []
var speed_rect: ColorRect = null


func _enter_tree() -> void:
	# Родитель входит в дерево до _ready дочерней машины. Сценический
	# setup_override сохраняется при прямом F6, но заезд из меню обязан
	# использовать выбранную и сохранённую настройку гаража.
	if Engine.is_editor_hint():
		return
	var game: Node = get_node_or_null("/root/RallyGame")
	var selected_setup: CarSetupType = car_setup_override
	if game != null:
		if car_setup_override != null:
			game.set("current_setup", car_setup_override)
		elif game.has_method("get_race_setup_override"):
			selected_setup = game.call("get_race_setup_override") as CarSetupType
		if track_override != null:
			game.set("current_track", track_override)
	var stage_car := get_node_or_null("RallyCar") as CarType
	if stage_car != null and selected_setup != null:
		stage_car.setup_override = selected_setup


## Подставить «пульты» из res://data/stage/, если в сцене поле пустое.
## В редакторе ресурсы читаются напрямую: правка .tres сразу видна на кнопке
## «Пересобрать трассу», без перезапуска.
func _load_resources() -> void:
	var has_explicit_settings := settings != null
	if game_config == null and ResourceLoader.exists("res://data/rally_game_config.tres"):
		game_config = ResourceLoader.load("res://data/rally_game_config.tres") as GameConfigType
	if settings == null:
		settings = _load_resource(DEFAULT_SETTINGS_PATH) as StageSettingsType
	if settings != null:
		settings = settings.duplicate() as StageSettingsType
	if settings == null:
		settings = StageSettingsType.new()
	_bind_visual_effects()
	if fx_nodes != null:
		# Явно назначенный старый ресурс переносим один раз. Обычный дефолтный
		# .tres не имеет права затирать художественные правки новых узлов сцены.
		if has_explicit_settings and not legacy_effects_imported:
			fx_nodes.adopt_from_settings(settings)
			legacy_effects_imported = true
		fx_nodes.sync_to_settings(settings)
	if spawn_layout == null:
		spawn_layout = _load_resource(DEFAULT_SPAWN_PATH) as SpawnLayoutType
	if spawn_layout == null:
		spawn_layout = SpawnLayoutType.new()
	if fx_profile == null:
		fx_profile = _load_resource(DEFAULT_FX_PATH) as FxProfileType
	if fx_profile == null:
		fx_profile = FxProfileType.new()
	if scenery == null:
		scenery = _load_resource(DEFAULT_SCENERY_PATH) as SceneryType
	if scenery == null:
		scenery = SceneryType.new()
	surface_state.fx = fx_profile


func _bind_visual_effects() -> void:
	if fx_nodes == null:
		fx_nodes = get_node_or_null("VisualEffects") as VisualEffectsType


func _validate_property(property: Dictionary) -> void:
	if property.name == "settings":
		property.usage = PROPERTY_USAGE_STORAGE


func import_legacy_effects() -> void:
	_bind_visual_effects()
	if fx_nodes == null:
		push_warning("В сцене нет узла VisualEffects: переносить настройки некуда.")
		return
	fx_nodes.adopt_from_settings(s_settings())
	fx_nodes.sync_to_settings(settings)
	legacy_effects_imported = true
	fx_nodes.configure_screen(track)
	print("Визуальные настройки перенесены в узлы сцены. Сохраните сцену (Ctrl+S).")


func _sync_visual_settings() -> void:
	_bind_visual_effects()
	if fx_nodes != null and settings != null:
		fx_nodes.sync_to_settings(settings)
		fx_nodes.configure_screen(track)


func _load_resource(path: String) -> Resource:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path)


## Настройки сцены (никогда null после _load_resources).
func s_settings() -> StageSettingsType:
	if settings == null:
		_load_resources()
	return settings


## Раскладка спавнов (никогда null).
func s_spawn() -> SpawnLayoutType:
	if spawn_layout == null:
		_load_resources()
	return spawn_layout


## Профиль эффектов (никогда null).
func s_fx() -> FxProfileType:
	if fx_profile == null:
		_load_resources()
	return fx_profile


## Конфиг обстановки (никогда null).
func s_scenery() -> SceneryType:
	if scenery == null:
		_load_resources()
	return scenery


func _ready() -> void:
	_load_resources()
	if Engine.is_editor_hint():
		set_process(true)
		if s_settings().preview_in_editor:
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
	if track != null and s_settings().is_retro(track) and s_settings().apply_ps1_materials:
		# Только визуальные копии: настройки краски, слои грязи и ресурсы
		# редактора остаются нетронутыми.
		Ps1Materials.apply_nearest(self)
	var marks = TireMarksType.new()
	marks.name = "TireMarks"
	marks.fx = s_fx()
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
## пересборку в очередь (через settings.auto_rebuild_delay после правки).
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
		total += _snap_children(root)
	return total


## Рекурсивно сажает на землю и вложенные узлы (ветку дерева, щит на столбе),
## а не только прямых детей корня.
func _snap_children(root: Node3D) -> int:
	var total: int = 0
	for child in root.get_children():
		var node3d := child as Node3D
		if node3d == null:
			continue
		if node3d is CollisionShape3D or node3d is Marker3D:
			continue
		if node3d.get_child_count() > 0 and not (node3d is MeshInstance3D):
			# Группа объектов — сажаем каждый лист по отдельности.
			total += _snap_children(node3d)
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
	_sync_visual_settings()
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
	if s_settings().snap_props_on_build and track.use_baked_props:
		# Только «лес» из Props (запечённая обстановка лесной трассы):
		# ручные объекты в ManualProps не двигаем, их можно поставить
		# руками на нужную высоту. У трасс без запечённых пропсов
		# обстановка генерируется своя.
		_snap_prop_nodes(false)
	if s_spawn().spawn_route_markers and track.spawn_route_markers:
		_spawn_route_markers()
	if s_spawn().edge_posts and track.spawn_edge_posts:
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
	# Свой материал (из сцены или из настроек) главнее сгенерированного:
	# его шейдер и параметры целиком в инспекторе.
	if ground_material_override is ShaderMaterial:
		return ground_material_override as ShaderMaterial
	var surfaces := fx_nodes.surfaces() if fx_nodes != null else null
	if surfaces != null and surfaces.ground_material != null:
		_ground_material = surfaces.ground_material
	elif s_settings().ground_material is ShaderMaterial:
		return s_settings().ground_material as ShaderMaterial
	# Сгенерированный материал один на сцену: параметры обновляются, а не
	# создаются заново, поэтому материал не «плодится» при пересборке.
	if _ground_material == null:
		_ground_material = ShaderMaterial.new()
		_ground_material.shader = GroundShader
	var material := _ground_material
	material.set_shader_parameter("ground_texture", GroundTexture)
	material.set_shader_parameter("rock_texture", RockTexture)
	material.set_shader_parameter("ground_texture_smooth", GroundTexture)
	material.set_shader_parameter("rock_texture_smooth", RockTexture)
	material.set_shader_parameter("ps1_textures", track.ps1_style)
	material.set_shader_parameter("ground_color", track.ground_color)
	material.set_shader_parameter("ground_color_2", track.ground_color_2)
	material.set_shader_parameter("road_edge_color", track.shoulder_color)
	material.set_shader_parameter("rock_color", track.rock_color)
	material.set_shader_parameter("surface_roughness", s_settings().ground_surface_roughness)
	material.set_shader_parameter("grain_scale", s_settings().ground_grain_scale)
	material.set_shader_parameter("flat_shading", 1.0 if track.ps1_style and track.flat_shading else 0.0)
	material.set_shader_parameter("vertex_snap", s_settings().retro_vertex_snap if s_settings().is_retro(track) else 0.0)
	material.set_shader_parameter("resolution_y", float(s_settings().retro_resolution_height))
	material.set_shader_parameter("wetness", _weather_wetness())
	material.set_shader_parameter("snow_cover", _weather_snow_cover())
	s_settings().apply_shader_overrides(material, s_settings().ground_shader_overrides)
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

	# Материал полотна один на сцену: свой (из сцены/настроек) или
	# сгенерированный — в обоих случаях живёт между пересборками.
	var surfaces := fx_nodes.surfaces() if fx_nodes != null else null
	var road_override: Material = road_material_override
	if road_override == null and surfaces != null:
		road_override = surfaces.road_material
	if road_override == null:
		road_override = s_settings().road_material
	if road_override is ShaderMaterial:
		_road_material = road_override as ShaderMaterial
	elif _road_material == null:
		_road_material = ShaderMaterial.new()
	var road_material := _road_material
	if road_material.shader == null:
		road_material.shader = RoadShader
	road_material.set_shader_parameter("gravel_texture", GravelTexture)
	road_material.set_shader_parameter("gravel_texture_smooth", GravelTexture)
	road_material.set_shader_parameter("ps1_textures", track.ps1_style)
	road_material.set_shader_parameter("vertex_snap", s_settings().retro_vertex_snap if s_settings().is_retro(track) else 0.0)
	road_material.set_shader_parameter("resolution_y", float(s_settings().retro_resolution_height))
	road_material.set_shader_parameter("road_roughness", s_settings().road_roughness)
	road_material.set_shader_parameter("detail_strength", s_settings().road_detail_strength)
	road_material.set_shader_parameter("track_strength", s_settings().road_track_strength)
	var road_kind: String = surface_state.surface_kind(track.surface_name, false, _weather_snow_cover())
	road_material.set_shader_parameter(
		"loose_relief",
		s_settings().road_loose_relief_asphalt if road_kind == "asphalt" else s_settings().road_loose_relief
	)
	# Мокрое полотно темнее и глянцевее, снег — светлее и матовее.
	road_material.set_shader_parameter("stage_length", network.total_length)
	road_material.set_shader_parameter("zone_offset", _zone_lateral_offset())
	_apply_zone_shader_parameters(road_material)
	s_settings().apply_shader_overrides(road_material, s_settings().road_shader_overrides)
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
	var fx := s_fx()
	if not fx.grip_zones_enabled or network == null or track == null:
		return 1.0
	var p: Vector3 = to_local(world_point)
	var along: float = network.along_road(p.x, p.z)
	var start: float = fx.zone_start
	var limit: float = network.total_length - fx.zone_end_margin
	if along < start or along > limit:
		return 1.0
	var period: float = maxf(1.0, fx.zone_period)
	var cell_index: int = floori((along - start) / period)
	var local_along: float = fposmod(along - start, period)
	var center: Vector3 = network.point_at(along)
	var dir: Vector3 = network.direction_at(along)
	var side := Vector3(dir.z, 0.0, -dir.x)
	var lateral: float = (p - center).dot(side)
	var zone_side: float = 1.0 if cell_index % 2 == 0 else -1.0
	var fade: float = maxf(0.05, fx.zone_shader_fade)
	var softness: float = maxf(0.01, fx.zone_shader_softness)
	var length_scale: float = clampf(fx.zone_length / period, 0.0, 1.0)
	var longitudinal: float = smoothstep(0.0, fade, local_along) * (1.0 - smoothstep(period * length_scale - fade, period * length_scale, local_along))
	var across: float = 1.0 - smoothstep(fx.zone_half_width - softness, fx.zone_half_width, absf(lateral - zone_side * _zone_lateral_offset()))
	var loss: float = fx.zone_grip_loss_strong if cell_index % 2 == 0 else fx.zone_grip_loss_weak
	return 1.0 - longitudinal * across * loss


## Все числа скользких полос — в один материал полотна (шейдер совпадает с
## физикой live_surface_grip).
func _apply_zone_shader_parameters(material: ShaderMaterial) -> void:
	var fx := s_fx()
	material.set_shader_parameter("zone_period", fx.zone_period)
	material.set_shader_parameter("zone_start", fx.zone_start)
	material.set_shader_parameter("zone_end_margin", fx.zone_end_margin)
	material.set_shader_parameter("zone_length", fx.zone_length)
	material.set_shader_parameter("zone_half_width", fx.zone_shader_half_width)
	material.set_shader_parameter("zone_softness", fx.zone_shader_softness)
	material.set_shader_parameter("zone_fade", fx.zone_shader_fade)
	material.set_shader_parameter("zone_contrast", fx.zone_shader_contrast)
	material.set_shader_parameter("zone_wet_darken", fx.zone_wet_darken)
	material.set_shader_parameter("zone_dry_lighten", fx.zone_dry_lighten)
	material.set_shader_parameter("puddle_roughness", fx.zone_puddle_roughness)
	material.set_shader_parameter("puddle_mix", fx.zone_puddle_mix)


## Поперечное смещение скользкой полосы от оси дороги, м.
func _zone_lateral_offset() -> float:
	var fx := s_fx()
	if track == null:
		return 0.0
	return minf(track.road_half_width * fx.zone_lateral_fraction, fx.zone_lateral_limit)


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


## Дополнительный лес и мелкие объекты расставляются по обе стороны маршрута.
## Все позиции детерминированы сидом; ближайший виток дороги всегда остаётся
## свободным. Визуальные объекты разбиты на пространственные MultiMesh-ячейки.
func _spawn_procedural_scenery(light: bool = false) -> void:
	if generated == null or network == null:
		return
	var cfg := s_scenery()
	var container := Node3D.new()
	container.name = "Scenery"
	generated.add_child(container)
	var rng := RandomNumberGenerator.new()
	rng.seed = track.terrain_seed ^ 8237431
	var corridor: float = corridor_half()
	var firs: Array[Transform3D] = []
	var pines: Array[Transform3D] = []
	var trunks_visual: Array[Transform3D] = []
	var bushes: Array[Transform3D] = []
	var rocks: Array[Transform3D] = []
	var grass: Array[Transform3D] = []
	var stumps: Array[Transform3D] = []
	var logs: Array[Transform3D] = []
	var trunks: Array[Vector3] = []
	var distance: float = cfg.start_margin
	var trunk_since: float = -100.0
	var step_count: int = 0
	var step: float = maxf(1.0, cfg.sample_step)
	var total_steps: float = maxf(1.0, (network.total_length - cfg.start_margin - cfg.end_margin) / step)
	var density: float = clampf(track.scenery_density, 0.0, 2.0)
	var attempt_count: int = ceili(float(cfg.attempts_per_step) * density)
	var attempt_chance: float = float(cfg.attempts_per_step) * density * cfg.success_chance / float(maxi(attempt_count, 1))
	var minimum_offset: float = cfg.min_offset_baked if track.use_baked_props else cfg.min_offset_plain
	while distance < network.total_length - cfg.end_margin:
		var center: Vector3 = network.point_at(distance)
		var dir: Vector3 = network.direction_at(distance)
		var side := Vector3(dir.z, 0.0, -dir.x)
		for side_sign in [-1.0, 1.0]:
			for _attempt in range(attempt_count):
				if rng.randf() > attempt_chance:
					continue
				# На ручной лесной трассе не дублируем запечённые деревья у дороги.
				var lateral: float = corridor + rng.randf_range(minimum_offset, cfg.max_offset)
				var point: Vector3 = center + side * (lateral * side_sign) + dir * rng.randf_range(-cfg.along_jitter, cfg.along_jitter)
				if not terrain_rect.has_point(Vector2(point.x, point.z)) or network.distance_to_road(point.x, point.z) < corridor + cfg.road_clearance:
					continue
				var ground: float = ground_height(point.x, point.z)
				var angle: float = rng.randf_range(0.0, TAU)
				var kind: String = cfg.pick_kind(rng.randf())
				var size: float = 1.0
				match kind:
					"fir", "pine":
						var range_size: Vector2 = cfg.fir_size if kind == "fir" else cfg.pine_size
						size = rng.randf_range(range_size.x, range_size.y)
						var tree_basis := Basis(Vector3.UP, angle) * Basis.from_scale(Vector3.ONE * size)
						var crown_height: float = cfg.fir_crown_height if kind == "fir" else cfg.pine_crown_height
						var tree_transform := Transform3D(tree_basis, Vector3(point.x, ground + crown_height * size, point.z))
						if kind == "fir":
							firs.append(tree_transform)
						else:
							pines.append(tree_transform)
						trunks_visual.append(Transform3D(tree_basis, Vector3(point.x, ground + cfg.trunk_height * size, point.z)))
						if lateral < corridor + cfg.collider_max_offset and distance - trunk_since > cfg.collider_spacing:
							trunks.append(Vector3(point.x, ground, point.z))
							trunk_since = distance
					"bush":
						size = rng.randf_range(cfg.bush_size.x, cfg.bush_size.y)
						var bush_scale := Vector3(
							size * rng.randf_range(cfg.bush_width_jitter.x, cfg.bush_width_jitter.y),
							size,
							size * rng.randf_range(cfg.bush_width_jitter.x, cfg.bush_width_jitter.y)
						)
						bushes.append(Transform3D(Basis(Vector3.UP, angle) * Basis.from_scale(bush_scale), Vector3(point.x, ground + cfg.bush_height_factor * size, point.z)))
					"boulder":
						size = rng.randf_range(cfg.boulder_size.x, cfg.boulder_size.y)
						var rock_scale := Vector3(
							size * rng.randf_range(cfg.boulder_width_jitter.x, cfg.boulder_width_jitter.y),
							size * rng.randf_range(cfg.boulder_height_jitter.x, cfg.boulder_height_jitter.y),
							size
						)
						rocks.append(Transform3D(Basis(Vector3.UP, angle) * Basis.from_scale(rock_scale), Vector3(point.x, ground + cfg.boulder_height_factor * rock_scale.y, point.z)))
					"stump":
						size = rng.randf_range(cfg.stump_size.x, cfg.stump_size.y)
						stumps.append(Transform3D(Basis(Vector3.UP, angle) * Basis.from_scale(Vector3.ONE * size), Vector3(point.x, ground + cfg.stump_height_factor * size, point.z)))
					"log":
						size = rng.randf_range(cfg.log_size.x, cfg.log_size.y)
						var log_basis := Basis(Vector3.UP, angle) * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3.ONE * size)
						logs.append(Transform3D(log_basis, Vector3(point.x, ground + cfg.log_height_factor * size, point.z)))
				# Мелкий подлесок не имеет физики и не отбрасывает тень.
				if kind != "fir" and kind != "pine" and rng.randf() < cfg.undergrowth_chance:
					var gs: float = rng.randf_range(cfg.grass_size.x, cfg.grass_size.y)
					grass.append(Transform3D(Basis(Vector3.UP, angle) * Basis.from_scale(Vector3(gs * cfg.grass_width_factor, gs, gs)), Vector3(point.x, ground + cfg.grass_height_factor * gs, point.z)))
		step_count += 1
		if light and step_count % 64 == 63:
			_report_progress(lerpf(0.90, 0.97, minf(1.0, float(step_count) / total_steps)), "Лес, камни и знаки…")
			await get_tree().process_frame
		distance += step
	_add_scenery_multimesh(container, "Firs", _make_scenery_mesh("fir"), firs)
	_add_scenery_multimesh(container, "Pines", _make_scenery_mesh("pine"), pines)
	_add_scenery_multimesh(container, "TrunkVisuals", _make_scenery_mesh("trunk"), trunks_visual)
	_add_scenery_multimesh(container, "Bushes", _make_scenery_mesh("bush"), bushes)
	_add_scenery_multimesh(container, "Boulders", _make_scenery_mesh("boulder"), rocks)
	_add_scenery_multimesh(container, "Grass", _make_scenery_mesh("grass"), grass, true)
	_add_scenery_multimesh(container, "Stumps", _make_scenery_mesh("stump"), stumps, true)
	_add_scenery_multimesh(container, "Logs", _make_scenery_mesh("log"), logs, true)
	_add_trunk_colliders(container, trunks)
	_spawn_corner_signs(container)


func _add_trunk_colliders(parent: Node3D, trunks: Array[Vector3]) -> void:
	var cfg := s_scenery()
	var bodies: Dictionary = {}
	var shape := CylinderShape3D.new()
	shape.radius = cfg.collider_radius
	shape.height = cfg.collider_height
	for point in trunks:
		var key := _scenery_cell(point)
		if not bodies.has(key):
			var body := StaticBody3D.new()
			body.name = "TreeTrunks_%d_%d" % [key.x, key.y]
			parent.add_child(body)
			bodies[key] = body
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position = point + Vector3(0.0, cfg.collider_height * 0.5 + cfg.collider_y_offset, 0.0)
		(bodies[key] as StaticBody3D).add_child(collider)


## Размер ячейки MultiMesh — из настроек сцены (инспектор).
func _scenery_cell(point: Vector3) -> Vector2i:
	var size: float = maxf(1.0, s_settings().scenery_cell_size)
	return Vector2i(floori(point.x / size), floori(point.z / size))


func _make_scenery_mesh(kind: String) -> Mesh:
	var cfg := s_scenery()
	var material := StandardMaterial3D.new()
	material.roughness = cfg.roughness
	material.vertex_color_use_as_albedo = true
	if cfg.ps1_filter:
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	if kind == "fir" or kind == "pine":
		material.albedo_texture = NeedleTexture
		material.albedo_color = cfg.fir_color if kind == "fir" else cfg.pine_color
		var crown := CylinderMesh.new()
		crown.top_radius = 0.0
		crown.bottom_radius = cfg.fir_radius if kind == "fir" else cfg.pine_radius
		crown.height = cfg.fir_mesh_height if kind == "fir" else cfg.pine_mesh_height
		crown.radial_segments = cfg.crown_segments
		crown.rings = 1
		crown.material = material
		return crown
	if kind in ["trunk", "stump", "log"]:
		material.albedo_texture = BarkTexture
		material.albedo_color = cfg.trunk_color
		var wood := CylinderMesh.new()
		wood.top_radius = cfg.trunk_top_radius if kind == "trunk" else cfg.stump_top_radius
		wood.bottom_radius = cfg.trunk_bottom_radius if kind == "trunk" else cfg.stump_bottom_radius
		wood.height = cfg.trunk_mesh_height if kind == "trunk" else (cfg.log_mesh_height if kind == "log" else cfg.stump_mesh_height)
		wood.radial_segments = cfg.wood_segments
		wood.material = material
		return wood
	if kind == "grass":
		material.albedo_texture = NeedleTexture
		material.albedo_color = cfg.grass_color
		var tuft := CylinderMesh.new()
		tuft.top_radius = 0.0
		tuft.bottom_radius = cfg.grass_radius
		tuft.height = cfg.grass_mesh_height
		tuft.radial_segments = cfg.grass_segments
		tuft.material = material
		return tuft
	if kind == "bush":
		material.albedo_texture = NeedleTexture
		material.albedo_color = cfg.bush_color
		var mesh_bush := SphereMesh.new()
		mesh_bush.radius = cfg.bush_radius
		mesh_bush.height = cfg.bush_mesh_height
		mesh_bush.radial_segments = cfg.bush_radial_segments
		mesh_bush.rings = cfg.bush_rings
		mesh_bush.material = material
		return mesh_bush
	material.albedo_texture = RockTexture
	material.albedo_color = cfg.boulder_color
	var mesh_rock := SphereMesh.new()
	mesh_rock.radius = cfg.boulder_radius
	mesh_rock.height = cfg.boulder_mesh_height
	mesh_rock.radial_segments = cfg.boulder_radial_segments
	mesh_rock.rings = cfg.boulder_rings
	mesh_rock.material = material
	return mesh_rock


func _add_scenery_multimesh(parent: Node3D, node_name: String, mesh: Mesh, transforms: Array[Transform3D], small: bool = false) -> void:
	if transforms.is_empty():
		return
	var cfg := s_settings()
	var groups: Dictionary = {}
	for transform in transforms:
		var key := _scenery_cell(transform.origin)
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(transform)
	var group_root := Node3D.new()
	group_root.name = node_name
	parent.add_child(group_root)
	for key in groups:
		var chunk: Array = groups[key]
		var chunk_origin := Vector3.ZERO
		for transform: Transform3D in chunk:
			chunk_origin += transform.origin
		chunk_origin /= float(chunk.size())
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = mesh
		multimesh.instance_count = chunk.size()
		for i in range(chunk.size()):
			var transform: Transform3D = chunk[i]
			multimesh.set_instance_transform(i, Transform3D(transform.basis, transform.origin - chunk_origin))
			var shade: float = cfg.scenery_shade_base + cfg.scenery_shade_spread * TrackConfigType.hash_noise(transform.origin.x, transform.origin.z)
			multimesh.set_instance_color(i, Color(shade, shade, shade, 1.0))
		var instance := MultiMeshInstance3D.new()
		instance.name = "Cell_%d_%d" % [key.x, key.y]
		instance.position = chunk_origin
		instance.multimesh = multimesh
		# Мелочи исчезают дальше, чем размер ячейки, с запасом на её радиус.
		instance.visibility_range_end = cfg.scenery_range_small if small else cfg.scenery_range_large
		instance.visibility_range_end_margin = cfg.scenery_range_margin
		instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if small:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		group_root.add_child(instance)


func _spawn_corner_signs(parent: Node3D) -> void:
	var cfg := s_spawn()
	if not cfg.corner_signs:
		return
	var threshold: float = deg_to_rad(cfg.corner_turn_threshold_deg)
	var last_sign: float = -10000.0
	var distance: float = cfg.corner_sign_start
	while distance < network.total_length - cfg.corner_sign_end:
		var turn: float = _turn_ahead(distance, cfg.corner_lookahead)
		if absf(turn) > threshold and distance - last_sign > cfg.corner_sign_spacing:
			var center: Vector3 = network.point_at(distance)
			var dir: Vector3 = network.direction_at(distance)
			var side := Vector3(dir.z, 0.0, -dir.x)
			# side указывает в сторону роста heading, наружу поворота —
			# противоположная сторона.
			var outer: float = -1.0 if turn > 0.0 else 1.0
			var point: Vector3 = center + side * (outer * (corridor_half() + cfg.corner_sign_lateral))
			var sign_node: Node3D = RoadSignScene.instantiate()
			sign_node.position = Vector3(point.x, ground_height(point.x, point.z), point.z)
			sign_node.rotation.y = atan2(-dir.x, -dir.z) + deg_to_rad(cfg.corner_sign_yaw_offset)
			sign_node.scale = Vector3.ONE * cfg.corner_sign_scale
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
	var cfg := s_spawn()
	var container := Node3D.new()
	container.name = "RouteMarkers"
	generated.add_child(container)
	var finish_distance: float = maxf(0.0, network.total_length - cfg.finish_margin)
	_create_gate(container, network.point_at(minf(cfg.start_distance, finish_distance)), network.direction_at(minf(cfg.start_distance, finish_distance)), cfg.start_gate_color)
	_create_gate(container, network.point_at(finish_distance), network.direction_at(finish_distance), cfg.finish_gate_color)


func _create_gate(container: Node3D, pos: Vector3, dir: Vector3, color: Color) -> void:
	var cfg := s_spawn()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * cfg.gate_emission_multiplier
	material.emission_energy_multiplier = cfg.gate_emission_energy
	var post_mesh := BoxMesh.new()
	post_mesh.size = cfg.gate_post_size
	post_mesh.surface_set_material(0, material)
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(track.road_half_width * 2.0 + cfg.gate_width_extra, cfg.gate_bar_thickness, cfg.gate_bar_thickness)
	bar_mesh.surface_set_material(0, material)
	var gate := Node3D.new()
	gate.position = Vector3(pos.x, height_at(pos.x, pos.z), pos.z)
	gate.rotation.y = atan2(dir.x, dir.z)
	for side_sign in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		post.mesh = post_mesh
		post.position = Vector3(float(side_sign) * (track.road_half_width + cfg.gate_post_lateral), cfg.gate_post_size.y * 0.5, 0.0)
		gate.add_child(post)
	var bar := MeshInstance3D.new()
	bar.mesh = bar_mesh
	bar.position = Vector3(0.0, cfg.gate_bar_height, 0.0)
	gate.add_child(bar)
	container.add_child(gate)


## Красно-белые столбики по обочинам.
func _spawn_edge_posts() -> void:
	if generated == null or network == null:
		return
	var cfg := s_spawn()
	var container := Node3D.new()
	container.name = "EdgePosts"
	generated.add_child(container)
	var material := StandardMaterial3D.new()
	material.albedo_color = track.edge_post_color
	material.roughness = cfg.edge_post_roughness
	var post_mesh := BoxMesh.new()
	post_mesh.size = cfg.edge_post_size
	post_mesh.surface_set_material(0, material)
	var white := StandardMaterial3D.new()
	white.albedo_color = cfg.edge_post_cap_color
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = cfg.edge_post_cap_size
	cap_mesh.surface_set_material(0, white)
	var transforms: Array[Transform3D] = []
	var lateral: float = corridor_half() + cfg.edge_post_lateral
	for distance in cfg.resolve_edge_post_distances(network.total_length):
		var center: Vector3 = network.point_at(distance)
		var dir: Vector3 = network.direction_at(distance)
		var side := Vector3(dir.z, 0.0, -dir.x)
		for side_sign in [-1.0, 1.0]:
			var point: Vector3 = center + side * (lateral * float(side_sign))
			var y: float = ground_height(point.x, point.z)
			transforms.append(Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), Vector3(point.x, y, point.z)))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = post_mesh
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
		cap_multimesh.set_instance_transform(i, Transform3D(t.basis, t.origin + Vector3(0.0, cfg.edge_post_cap_height, 0.0)))
	var cap_instance := MultiMeshInstance3D.new()
	cap_instance.name = "EdgePostCaps"
	cap_instance.multimesh = cap_multimesh
	container.add_child(cap_instance)


func _spawn_checkpoints() -> void:
	checkpoints.clear()
	if generated == null or network == null:
		return
	var cfg := s_spawn()
	var distances: PackedFloat32Array = cfg.resolve_checkpoint_distances(
		network.total_length, track.checkpoint_interval, cfg.start_distance
	)
	if distances.is_empty():
		return
	var container := Node3D.new()
	container.name = "Checkpoints"
	generated.add_child(container)
	var material := StandardMaterial3D.new()
	material.albedo_color = cfg.checkpoint_color
	material.emission_enabled = true
	material.emission = cfg.checkpoint_color * cfg.checkpoint_emission_strength
	material.emission_energy_multiplier = cfg.checkpoint_emission_energy
	var post_mesh := BoxMesh.new()
	post_mesh.size = cfg.checkpoint_post_size
	post_mesh.surface_set_material(0, material)
	var banner_mesh := BoxMesh.new()
	banner_mesh.size = Vector3(
		track.road_half_width * 2.0 + cfg.checkpoint_width_extra,
		cfg.checkpoint_bar_thickness,
		cfg.checkpoint_bar_depth
	)
	banner_mesh.surface_set_material(0, material)
	for distance in distances:
		var point: Vector3 = network.point_at(distance)
		var dir: Vector3 = network.direction_at(distance)
		var gate := Node3D.new()
		gate.name = "Checkpoint_%02d" % checkpoints.size()
		gate.position = Vector3(point.x, height_at(point.x, point.z), point.z)
		gate.rotation.y = atan2(dir.x, dir.z)
		for side_sign in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			post.mesh = post_mesh
			post.position = Vector3(float(side_sign) * (track.road_half_width + cfg.checkpoint_post_lateral), cfg.checkpoint_post_size.y * 0.5, 0.0)
			gate.add_child(post)
		var banner := MeshInstance3D.new()
		banner.mesh = banner_mesh
		banner.position = Vector3(0.0, cfg.checkpoint_bar_height, 0.0)
		gate.add_child(banner)
		container.add_child(gate)
		checkpoints.append({
			"pos": Vector2(point.x, point.z),
			"tangent": Vector2(dir.x, dir.z),
			"distance": distance,
		})


# ---------------------------------------------------------------- окружение


func _configure_world() -> void:
	# Погода «КАК НА ТРАССЕ» (weather == null) оставляет всё как в .tres.
	# Все константы постобработки живут в RallyStageSettings (инспектор).
	var cfg := s_settings()
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
			day_material.sky_curve = 0.55 if track.ps1_style and track.sky_flat else 0.18
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
		env.glow_intensity = cfg.glow_intensity_ps1 if track.ps1_style else cfg.glow_intensity_normal
		env.glow_bloom = cfg.glow_bloom_ps1 if track.ps1_style else cfg.glow_bloom_normal
		env.ssao_enabled = cfg.ssao_enabled and track.screen_space_ao
		env.ssao_radius = cfg.ssao_radius
		env.ssao_intensity = cfg.ssao_intensity
		# Лучи фар и погодный объёмный туман остаются доступны и в PS1-режиме.
		env.volumetric_fog_enabled = volumetric
		env.volumetric_fog_density = volumetric_density
		env.volumetric_fog_albedo = cfg.volumetric_fog_albedo
		if weather != null:
			env.volumetric_fog_albedo = weather.fog_color.lerp(
				cfg.volumetric_fog_albedo, 1.0 - cfg.volumetric_weather_tint
			)
		env.volumetric_fog_anisotropy = cfg.volumetric_fog_anisotropy
		env.volumetric_fog_length = cfg.volumetric_fog_length
		env.fog_enabled = fog_density > 0.0
		env.fog_light_color = fog_color
		if track.ps1_style:
			# Единый туман по расстоянию для земли, машин и деревьев. В Godot
			# плотность depth-тумана — максимальная непрозрачность (не экспонента).
			var fog_begin: float = maxf(0.0, track.fog_near * _weather_visibility_scale())
			var fog_end: float = maxf(fog_begin + 1.0, track.fog_far * _weather_visibility_scale())
			env.fog_mode = Environment.FOG_MODE_DEPTH
			env.fog_depth_end = fog_end
			env.fog_depth_begin = fog_begin
			env.fog_depth_curve = cfg.fog_depth_curve
			env.fog_density = cfg.fog_ps1_opacity if fog_density > 0.0 else 0.0
			# Видно небо и луну; в густом тумане горизонт сильнее сливается с ним.
			env.fog_sky_affect = clampf(
				1.0 - 0.65 * _weather_visibility_scale(), cfg.fog_sky_affect_min, cfg.fog_sky_affect_max
			)
		else:
			env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
			env.fog_density = fog_density
			env.fog_sky_affect = 1.0
		world_environment.environment = env
	if sun_light != null:
		sun_light.rotation = Vector3(deg_to_rad(track.sun_pitch), deg_to_rad(track.sun_yaw), 0.0)
		sun_light.light_color = sun_color
		sun_light.light_energy = sun_energy


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


## Осадки существуют в мире: генератор обновляет только область рождения,
## частицы не наследуют движение машины и закрываются геометрией сцены.
## Все коэффициенты — из RallyStageSettings; статическая точка входа
## нужна тестам, сцена зовёт _anchor_for() с теми же настройками.
static func precipitation_anchor(position: Vector3, velocity: Vector3) -> Vector3:
	var cfg: StageSettingsType = null
	if ResourceLoader.exists(DEFAULT_SETTINGS_PATH):
		cfg = ResourceLoader.load(DEFAULT_SETTINGS_PATH) as StageSettingsType
	if cfg == null:
		cfg = StageSettingsType.new()
	var lead := Vector3(velocity.x, 0.0, velocity.z).limit_length(cfg.anchor_velocity_limit) * cfg.anchor_velocity_lead
	var center := position + lead
	# Перемещение области порциями не двигает уже существующие частицы.
	var grid: float = maxf(0.5, cfg.anchor_grid)
	return Vector3(
		roundf(center.x / grid) * grid,
		position.y + cfg.anchor_height,
		roundf(center.z / grid) * grid
	)


func _setup_precipitation() -> void:
	if _weather_particles != null:
		_weather_particles.queue_free()
		_weather_particles = null
	if not s_settings().precipitation_enabled:
		return
	if weather == null or not weather.has_precipitation():
		return
	if DisplayServer.get_name() == "headless":
		return
	var particles := _make_precipitation_particles()
	if particles == null:
		return
	add_child(particles)
	if car != null:
		particles.global_position = _anchor_for(car.global_position, car.linear_velocity)
	particles.emitting = true
	_weather_particles = particles


## Мировая точка рождения осадков для позиции/скорости машины. Отдельный
## метод: сцена использует его и в _process, а тесты проверяют без GPU.
func _anchor_for(position: Vector3, velocity: Vector3) -> Vector3:
	_bind_visual_effects()
	if fx_nodes != null:
		return fx_nodes.anchor_for(position, velocity)
	var cfg := s_settings()
	if cfg == null:
		return precipitation_anchor(position, velocity)
	var lead := Vector3(velocity.x, 0.0, velocity.z).limit_length(cfg.anchor_velocity_limit) * cfg.anchor_velocity_lead
	var center := position + lead
	var grid: float = maxf(0.5, cfg.anchor_grid)
	return Vector3(
		roundf(center.x / grid) * grid,
		position.y + cfg.anchor_height,
		roundf(center.z / grid) * grid
	)


func _make_precipitation_particles() -> GPUParticles3D:
	_bind_visual_effects()
	if fx_nodes != null:
		return fx_nodes.make_weather_particles(weather)
	# Совместимость с тестами/старым кодом без дерева сцены: временный владелец
	# использует те же сцены эффектов и переносит значения старого ресурса.
	var owner_node := VisualEffectsScene.instantiate() as VisualEffectsType
	owner_node.adopt_from_settings(s_settings())
	var particles := owner_node.make_weather_particles(weather)
	owner_node.free()
	return particles


# ---------------------------------------------------------------- машина


## Отдельно от мокрой или заснеженной дороги: осадки могут уже закончиться.
func _precipitation_levels() -> Vector2:
	if weather == null or not weather.has_precipitation():
		return Vector2.ZERO
	var intensity: float = clampf(weather.precipitation_intensity, 0.0, 1.0)
	if weather.precipitation == WeatherType.Precipitation.RAIN:
		return Vector2(intensity, 0.0)
	if weather.precipitation == WeatherType.Precipitation.SNOW:
		return Vector2(0.0, intensity)
	return Vector2.ZERO


func _configure_car() -> void:
	car = get_node_or_null("RallyCar") as CarType
	if car == null:
		push_warning("RallyStage: узел RallyCar не найден.")
		return
	car.process_mode = Node.PROCESS_MODE_PAUSABLE
	var precipitation := _precipitation_levels()
	car.set_precipitation(precipitation.x, precipitation.y)
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
	return height_at(car.global_position.x, car.global_position.z) - s_spawn().car_fall_depth


## Точка сброса по клавише R: ближайшая точка дороги впереди/рядом, чтобы
## машина, застрявшая на обочине или в кювете, вернулась на трассу.
func _rescue_transform() -> Transform3D:
	if network == null:
		return _make_spawn_transform()
	var cfg := s_spawn()
	var here: Vector2 = Vector2(car.global_position.x, car.global_position.z)
	var margin: float = cfg.car_rescue_margin
	var along: float = clampf(network.along_road(here.x, here.y), margin, network.total_length - margin)
	var point: Vector3 = network.point_at(along)
	var dir: Vector3 = network.direction_at(along)
	var y: float = height_at(point.x, point.z) + (car.get_spawn_height_offset() + cfg.car_rescue_height_extra)
	return Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), Vector3(point.x, y, point.z))


func _make_spawn_transform() -> Transform3D:
	var cfg := s_spawn()
	var start: float = 0.0
	if network != null:
		start = clampf(cfg.car_spawn_distance, 0.0, maxf(0.0, network.total_length))
	var point: Vector3 = network.point_at(start) if network != null else Vector3.ZERO
	var dir: Vector3 = network.direction_at(start) if network != null else Vector3.FORWARD
	var height_offset: float = cfg.car_spawn_height_extra
	if car != null:
		height_offset = car.get_spawn_height_offset() + cfg.car_spawn_height_extra
	var y: float = (height_at(point.x, point.z) if network != null else 0.0) + height_offset
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


## Постобработка 3D до отрисовки интерфейса.
func _setup_world_effects() -> void:
	_bind_visual_effects()
	if fx_nodes != null and fx_nodes.screen() != null:
		speed_rect = fx_nodes.screen()
		speed_fx_material = speed_rect.material as ShaderMaterial
		speed_rect.visible = true
		fx_nodes.configure_screen(track)
		if speed_rect.get_parent() == hud and hud.get_node_or_null("RallyHUD") != null:
			hud.move_child(speed_rect, 0)
		return
	# Старые сцены без VisualEffects продолжают работать.
	var cfg := s_settings()
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
		Ps1Materials.configure_post_effect(
			speed_fx_material, cfg.is_retro(track), cfg.retro_style_strength,
			float(cfg.retro_resolution_height), cfg.color_bits_for(track), cfg.dither_for(track)
		)
		speed_fx_material.set_shader_parameter("blur_strength", cfg.speed_blur_strength)
		speed_fx_material.set_shader_parameter("vignette_strength", cfg.vignette_strength)
		cfg.apply_shader_overrides(speed_fx_material, cfg.screen_shader_overrides)


func _setup_hud() -> void:
	if hud == null:
		return
	if _hud_ready:
		return
	_hud_ready = true
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_world_effects()

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
		["RallyHUD/PausePanel/Box/ControlsButton", "controls_pressed"],
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
	clutch_notice = _hud_node("RallyHUD/ClutchNotice") as Label
	_update_input_hint()
	var controller := _controller_manager()
	if controller != null and controller.has_signal("active_device_changed"):
		if not controller.is_connected("active_device_changed", _on_active_input_device_changed):
			controller.connect("active_device_changed", _on_active_input_device_changed)
		if controller.has_signal("bindings_changed") and not controller.is_connected("bindings_changed", _update_input_hint):
			controller.connect("bindings_changed", _update_input_hint)


func _controller_manager() -> Node:
	return get_node_or_null("/root/ControllerManager")


func _on_active_input_device_changed(_gamepad_active: bool) -> void:
	_update_input_hint()


## Подсказка отражает текущие, а не заводские назначения активного устройства.
func _update_input_hint() -> void:
	if hint_label == null:
		return
	var controller := _controller_manager()
	if controller == null or not controller.has_method("binding_label"):
		return
	var device := "gamepad" if bool(controller.get("gamepad_active")) else "keyboard"
	var label := func(action: String) -> String: return String(controller.call("binding_label", action, device))
	hint_label.text = "[%s/%s] ГАЗ/ТОРМОЗ  •  [%s/%s] РУЛЬ  •  [%s] РУЧНИК  •  [%s/%s] КПП" % [
		label.call("throttle"), label.call("brake"), label.call("steer_left"), label.call("steer_right"),
		label.call("handbrake"), label.call("shift_down"), label.call("shift_up"),
	]
	if car != null and car.manual_clutch_control:
		hint_label.text += "  •  [%s] СЦЕПЛЕНИЕ" % label.call("clutch")
	hint_label.text += "  •  [%s] КАМЕРА  •  [%s] ПАУЗА" % [label.call("camera_switch"), label.call("pause")]
	if device == "keyboard":
		hint_label.text += "  •  [%s] ТРЕК  •  [%s] RADIO" % [
			label.call("radio_next"), label.call("radio_toggle")
		]


func _on_button_pressed(action: String) -> void:
	match action:
		"controls_pressed":
			_open_input_settings()
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
		if s_settings().show_debug_info:
			split_label.text += "  | cell %.1f" % track.terrain_cell
	# Спидометр.
	if speed_label != null:
		speed_label.text = str(int(round(car.speed_kmh))).lpad(3, "0")
	if gear_label != null:
		gear_label.text = "%s  |  %s  |  %s" % [car.get_gear_label(), car.get_transmission_label(), car.get_drivetrain_label()]
	if clutch_notice != null:
		clutch_notice.visible = car.engine_stalled or car.shift_notice_time > 0.0
		if car.engine_stalled:
			clutch_notice.text = "ДВИГАТЕЛЬ ЗАГЛОХ — ВЫЖМИТЕ СЦЕПЛЕНИЕ ДЛЯ ЗАПУСКА"
		elif car.shift_notice_time > 0.0:
			clutch_notice.text = car.shift_notice
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
	# Меняем только место рождения новых капель. Уже выпавшие частицы
	# остаются в мировых координатах и не перемещаются вместе с машиной.
	if _weather_particles != null and car != null and not get_tree().paused:
		_weather_particles.global_position = _anchor_for(car.global_position, car.linear_velocity)
	# Во время переназначения и в кадре закрытия клавиша паузы не должна
	# закрывать саму паузу или запускать повторно назначенное действие.
	if input_settings != null and input_settings.blocks_actions():
		return
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
		if car != null:
			car.driving_feedback_active = true
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
	if fx_nodes != null:
		fx_nodes.update_speed(speed, track)
	elif speed_fx_material != null:
		var intensity: float = s_settings().speed_fx_amount(speed, track)
		speed_fx_material.set_shader_parameter("speed_intensity", intensity)
	_frame_delta = delta
	_update_hud()


## Отложенная пересборка в редакторе (см. settings.auto_rebuild_delay).
func _process_editor(delta: float) -> void:
	if not _rebuild_pending:
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		# Пока тянем точку мышью — не пересобираем, чтобы редактор не подвисал
		# посреди перетаскивания.
		_rebuild_timer = 0.0
		return
	_rebuild_timer += delta
	if _rebuild_timer < s_settings().auto_rebuild_delay:
		return
	_rebuild_pending = false
	_rebuild_timer = 0.0
	var from_track: bool = _pending_from_track
	_pending_from_track = false
	if not s_settings().preview_in_editor or not is_inside_tree():
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
	if car != null:
		car.driving_feedback_active = false
	var feedback_controller := _controller_manager()
	if feedback_controller != null and feedback_controller.has_method("stop_driving_feedback"):
		feedback_controller.call("stop_driving_feedback")
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
		if input_settings != null and input_settings.visible:
			input_settings.close()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if car != null and car.mouse_look_enabled else Input.MOUSE_MODE_VISIBLE
		if not stage_finished and is_inside_tree():
			get_viewport().gui_release_focus()


func _open_input_settings() -> void:
	var hud_root := _hud_node("RallyHUD") as Control
	if hud_root == null:
		return
	if input_settings == null:
		input_settings = InputSettings.new()
		input_settings.name = "InputSettings"
		hud_root.add_child(input_settings)
	# Окно настроек всегда выше карточки радио, панели паузы и HUD.
	hud_root.move_child(input_settings, hud_root.get_child_count() - 1)
	input_settings.open()


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
