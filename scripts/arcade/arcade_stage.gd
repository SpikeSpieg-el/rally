## Аркадный заезд: бесконечная двухполосная дорога, без финиша и без мини-карты.
##
## Почему отдельная сцена, а не «ещё одна трасса» в RallyStage. У этапа вся
## жизнь привязана к конечной сети: финиш в `network.total_length`, мини-карта
## рисует маршрут из `network`, гейты и время спецучастка считаются от длины.
## Аркаде это не нужно и, хуже того, мешает: дорога бесконечная, финиша нет, а
## `network.total_length` растёт по мере езды.
##
## Аркадный этап реализует ТОТ ЖЕ контракт, который машина ждёт от родителя
## (`surface_contact`, `live_surface_grip`, `speed_shake_offset`,
## `speed_shake_angles`, `surface_kind_at`), и использует те же ресурсы:
## настройки сцены, покрытие, HUD, машину. Физика машины от этого не меняется
## вообще — аркада едет на той же машине тем же кодом; меняется только мир
## вокруг.
##
## Порядок: сначала дорога на старте, потом стример догоняет остальное в
## `_process`. Финиша нет — заезд не заканчивается по достижению дистанции.
class_name RallyArcadeStage
extends Node3D

const RoadType = preload("res://scripts/arcade/arcade_road.gd")
const NetworkType = preload("res://scripts/arcade/arcade_network.gd")
const StreamerType = preload("res://scripts/arcade/arcade_streamer.gd")
const ChunkType = preload("res://scripts/arcade/arcade_chunk.gd")
const TrackType = preload("res://scripts/data/rally_track_config.gd")
const SettingsType = preload("res://scripts/data/rally_stage_settings.gd")
const SpawnType = preload("res://scripts/data/rally_spawn_layout.gd")
const SurfaceType = preload("res://scripts/road_surface.gd")
const RoadShader = preload("res://shaders/gravel_road.gdshader")
const GroundShader = preload("res://shaders/forest_ground.gdshader")
const GravelTexture = preload("res://textures/environment/gravel.png")
const GroundTexture = preload("res://textures/environment/forest_floor.png")
const RockTexture = preload("res://textures/environment/rock.png")
const HudType = preload("res://scripts/ui/rally_hud.gd")
const ScreenLookType = preload("res://scripts/effects/rally_screen_look.gd")
const SpeedFeelType = preload("res://scripts/effects/rally_speed_feel.gd")
const DEFAULT_TRACK_PATH := "res://data/tracks/stage_arcade.tres"
const DEFAULT_SETTINGS_PATH := "res://data/stage/default_stage_settings.tres"
const DEFAULT_SPAWN_PATH := "res://data/stage/default_spawn_layout.tres"
## За сколько метров до начала готовой дороги машина считается «на полотне».
const HUD_REFRESH: float = 0.1

## Сид генерации. 0 — взять сид заезда из RallyGame (он же повторяется при
## перезапуске, поэтому «рестарт» возвращает ту же дорогу).
@export var generation_seed: int = 0
## Трасса-«носитель»: только поверхность, HUD и погода, без геометрии.
@export var track: TrackType = null
@export var settings: SettingsType = null
@export var spawn_layout: SpawnType = null

var network: NetworkType = null
var car = null
var hud: HudType = null

var _streamer: StreamerType = null
var _surface = SurfaceType.new()
var _road_material: ShaderMaterial = null
var _ground_material: ShaderMaterial = null
var _last_along: float = 0.0
## Кэш «где полотно»: четыре колеса спрашивают почти одну и ту же точку в одном
## физическом кадре, а поиск дороги — самая дорогая операция в этом файле.
var _query_point := Vector3(INF, INF, INF)
var _query_half: float = 0.0
var _lateral_cache: float = 0.0
var _hud_clock: float = 0.0
var _is_paused: bool = false
var _pause_panel: CanvasItem = null
var _speed_label: Label = null
var _gear_label: Label = null
var _stage_label: Label = null


func _ready() -> void:
	add_to_group("rally_stage")
	_load_resources()
	_resolve_seed()
	network = NetworkType.new(generation_seed)
	var car_node := get_node_or_null("RallyCar") as RigidBody3D
	if car_node != null:
		car_node.freeze = true
	_build_world()
	# Машина настраивается ПЕРЕД HUD: HUD привязывается к машине (вид кабины,
	# прятание кузова), а привязка к null просто ничего не делает.
	_configure_car()
	_setup_hud()
	if car_node != null:
		car_node.freeze = false
	var game: Node = get_node_or_null("/root/RallyGame")
	if game != null and game.has_method("finish_loading"):
		game.call("finish_loading")


func _process(delta: float) -> void:
	if car == null or _streamer == null:
		return
	if _is_paused:
		return
	var here: Vector3 = car.global_position
	# Поиск дороги рядом с машиной — по подсказке прошлого километража: полный
	# перебор по всей собранной дороге на 100-м км стоил бы десятки мс.
	var near: Vector2 = network.nearest(here.x, here.z, _last_along)
	_last_along = near.y
	network.ensure_length(_last_along + StreamerType.LOOKAHEAD * StreamerType.CHUNK_LENGTH)
	_streamer.focus(_last_along)
	_hud_clock += delta
	if _hud_clock >= HUD_REFRESH:
		_hud_clock = 0.0
		_update_hud()


## Сид дороги. Явный сид в инспекторе главнее всего. Иначе берётся
## `generation_seed` трассы — он правится в меню и сохраняется между
## запусками. Перезапуск заезда (`restart_race`) перезагружает ту же сцену,
## поэтому дорога остаётся той же: «рестарт» — это повтор, а не новая трасса.
func _resolve_seed() -> void:
	if generation_seed == 0 and track != null:
		generation_seed = int(track.get("generation_seed"))
	if generation_seed == 0:
		generation_seed = int(Time.get_unix_time_from_system() * 1000.0) & 0x7fffffff
	RoadType.reset(generation_seed)


# --------------------------------------------------------------- ресурсы


func _load_resources() -> void:
	if track == null:
		track = _load(DEFAULT_TRACK_PATH) as TrackType
	if track == null:
		track = TrackType.new()
	if settings == null:
		settings = _load(DEFAULT_SETTINGS_PATH) as SettingsType
	if settings == null:
		settings = SettingsType.new()
	if spawn_layout == null:
		spawn_layout = _load(DEFAULT_SPAWN_PATH) as SpawnType
	if spawn_layout == null:
		spawn_layout = SpawnType.new()


func _load(path: String) -> Resource:
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path)


# ------------------------------------------------------------------ мир


func _build_world() -> void:
	_road_material = _make_road_material()
	_ground_material = _make_ground_material()
	_streamer = StreamerType.new()
	_streamer.name = "RoadStreamer"
	add_child(_streamer)
	_streamer.setup(generation_seed, _road_material, _ground_material)
	# Дорога на старте: несколько чанков вперёд, чтобы первый кадр не был
	# провалом в пустоту, и пара позади — для разворота.
	var behind: float = StreamerType.KEEP_BEHIND * StreamerType.CHUNK_LENGTH + 1.0
	network.ensure_length(StreamerType.CHUNK_LENGTH * 4.0)
	_streamer.focus(0.0)
	_streamer.prime(behind, StreamerType.LOOKAHEAD)


func _make_road_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = RoadShader
	material.set_shader_parameter("gravel_texture", GravelTexture)
	material.set_shader_parameter("gravel_texture_smooth", GravelTexture)
	material.set_shader_parameter("ps1_textures", false)
	material.set_shader_parameter("section_surfaces", false)
	# Дорога бесконечная: «длина трассы» для шейдера — заведомо больше любой
	# дистанции, иначе скользкие полосы перестанут появляться после неё.
	material.set_shader_parameter("stage_length", 1.0e9)
	material.set_shader_parameter("road_roughness", settings.road_roughness)
	material.set_shader_parameter("detail_strength", settings.road_detail_strength)
	material.set_shader_parameter("track_strength", settings.road_track_strength)
	material.set_shader_parameter("loose_relief", settings.road_loose_relief)
	return material


func _make_ground_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GroundShader
	material.set_shader_parameter("ground_texture", GroundTexture)
	material.set_shader_parameter("rock_texture", RockTexture)
	material.set_shader_parameter("ground_texture_smooth", GroundTexture)
	material.set_shader_parameter("rock_texture_smooth", RockTexture)
	material.set_shader_parameter("ps1_textures", false)
	material.set_shader_parameter("ground_color", track.ground_color)
	material.set_shader_parameter("ground_color_2", track.ground_color_2)
	material.set_shader_parameter("road_edge_color", track.shoulder_color)
	return material


# ------------------------------------------------------------------ HUD


func _setup_hud() -> void:
	hud = get_node_or_null("HUD/RallyHUD") as HudType
	if hud == null:
		return
	_stage_label = hud.get_node_or_null("StagePanel/StageBox/StageLabel") as Label
	_speed_label = hud.get_node_or_null("SpeedPanel/SpeedBox/SpeedLabel") as Label
	_gear_label = hud.get_node_or_null("SpeedPanel/SpeedBox/GearLabel") as Label
	# HUD сам переключает вид кабины и прячет кузов — без привязки к машине
	# переключение камеры в аркаде не работало бы.
	if car != null:
		hud.bind_vehicle(car)
	# Панель результатов и мини-карта в аркаде не нужны: заезд без финиша.
	for path in ["ResultsPanel", "MiniMapPanel", "MiniMap"]:
		var node := hud.get_node_or_null(path) as CanvasItem
		if node != null:
			node.visible = false
	_setup_pause()
	_setup_screen()


## Пауза. Панель уже нарисована в HUD — здесь к ней подключаются кнопки и
## клавиша Esc. Без этого из аркады нельзя было бы выйти вообще: заезд не
## заканчивается сам, а кнопок «выход» на трассе нет.
func _setup_pause() -> void:
	_pause_panel = hud.get_node_or_null("PausePanel") as CanvasItem
	if _pause_panel != null:
		_pause_panel.visible = false
	_connect_button("PausePanel/Box/ResumeButton", _on_resume_pressed)
	_connect_button("PausePanel/Box/MenuButton", _on_menu_pressed)
	_connect_button("PausePanel/Box/QuitButton", _on_quit_pressed)
	if hud.get_node_or_null("PausePanel/Box/RestartButton") != null:
		_connect_button("PausePanel/Box/RestartButton", _on_restart_pressed)


func _connect_button(path: String, action: Callable) -> void:
	var button := hud.get_node_or_null(path) as Button
	if button == null:
		return
	if not button.pressed.is_connected(action):
		button.pressed.connect(action)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_set_paused(not _is_paused)
		get_viewport().set_input_as_handled()


func _set_paused(value: bool) -> void:
	_is_paused = value
	get_tree().paused = value
	if _pause_panel != null:
		_pause_panel.visible = value
	if value:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		var capture: bool = car != null and car.mouse_look_enabled
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE
		if is_inside_tree():
			get_viewport().gui_release_focus()


func _on_resume_pressed() -> void:
	_set_paused(false)


func _on_restart_pressed() -> void:
	var game: Node = get_node_or_null("/root/RallyGame")
	if game != null and game.has_method("restart_race"):
		game.call("restart_race")
	else:
		get_tree().reload_current_scene()


func _on_menu_pressed() -> void:
	get_tree().paused = false
	var game: Node = get_node_or_null("/root/RallyGame")
	if game != null and game.has_method("goto_menu"):
		game.call("goto_menu")
	else:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_quit_pressed() -> void:
	var game: Node = get_node_or_null("/root/RallyGame")
	if game != null and game.has_method("quit_game"):
		game.call("quit_game")
	else:
		get_tree().quit()


## Пока пауза включена, физика мира в аркаде тоже стоит: чанки не должны
## собираться за спиной у игрока, пока он читает меню.
func _exit_tree() -> void:
	if get_tree() != null:
		get_tree().paused = false


## Ретро-экран и эффект скорости живут в сцене; здесь они связываются с
## аркадной трассой тем же способом, что и в раллийном этапе, иначе экран
## остался бы на числах материала (визуально — «эффект не работает»).
func _setup_screen() -> void:
	var screen := get_node_or_null("HUD/SpeedShaderRect") as ScreenLookType
	if screen == null:
		return
	var feel := get_node_or_null("VisualEffects/Speed") as SpeedFeelType
	if feel != null:
		screen.bind_speed(feel)
	screen.configure_for_track(track)
	screen.visible = true


func _update_hud() -> void:
	if hud == null or car == null:
		return
	hud.set_camera_mode(car.camera_mode)
	var screen := get_node_or_null("HUD/SpeedShaderRect") as ScreenLookType
	if screen != null:
		screen.set_preview_speed(car.speed_kmh, car.camera_mode)
	if _stage_label != null:
		_stage_label.text = "АРКАДА  |  %.0f м  |  %s" % [_last_along, track.surface_name]
	if _speed_label != null:
		_speed_label.text = str(int(round(car.speed_kmh))).lpad(3, "0")
	if _gear_label != null:
		_gear_label.text = "%s  |  %s" % [car.get_gear_label(), car.get_drivetrain_label()]
	hud.update_speed_telemetry(
		car.speed_kmh, car.current_rpm, car.max_rpm, car.get_gear_label(), car.motor_is_redline
	)


# --------------------------------------------------------------- машина


func _configure_car() -> void:
	car = get_node_or_null("RallyCar")
	if car == null:
		push_warning("RallyArcadeStage: узел RallyCar не найден.")
		return
	car.process_mode = Node.PROCESS_MODE_PAUSABLE
	car.apply_track_grip(track.grip_scale, track.rolling_resistance_scale, track.offroad_grip)
	car.spawn_transform = _spawn_transform()
	car.reset_to_spawn()
	car.reset_provider = Callable(self, "_rescue_transform")
	car.fall_limit_provider = Callable(self, "_fall_limit_y")
	_last_along = clampf(spawn_layout.car_spawn_distance, 0.0, 40.0)


func _spawn_transform() -> Transform3D:
	var along: float = clampf(spawn_layout.car_spawn_distance, 0.0, 40.0)
	return _frame_at(along, spawn_layout.car_spawn_height_extra)


func _rescue_transform() -> Transform3D:
	var here: Vector3 = car.global_position
	var near: Vector2 = network.nearest(here.x, here.z, _last_along)
	_last_along = near.y
	return _frame_at(near.y, spawn_layout.car_rescue_height_extra)


## Положение машины по километражу: ровно на поверхности полотна.
func _frame_at(along: float, extra_height: float) -> Transform3D:
	var point: Vector3 = network.point_at(along)
	var direction: Vector3 = network.direction_at(along)
	var height_offset: float = extra_height
	if car != null and car.has_method("get_spawn_height_offset"):
		height_offset += float(car.call("get_spawn_height_offset"))
	var y: float = ChunkType.surface_height(along, 0.0, generation_seed) + height_offset
	var facing := Basis(Vector3.UP, atan2(direction.x, direction.z))
	return Transform3D(facing, Vector3(point.x, y, point.z))


## Порог «машина ушла в бездну»: считается от полотна, а не от абсолюта —
## дорога уходит на десятки метров вверх и вниз по профилю.
func _fall_limit_y() -> float:
	var here: float = ChunkType.surface_height(_last_along, 0.0, generation_seed)
	return here - spawn_layout.car_fall_depth


# ----------------------------------------------- контракт для машины


## То же, что делает RallyStage: покрытие под колесом и след шин.
func surface_contact(
	point: Vector3, grass: bool, load_ratio: float, slip: float, speed: float, delta: float
) -> Dictionary:
	var kind: String = surface_kind_at(point, grass)
	var result: Dictionary = _surface.sample(point, kind, 0.0)
	result["kind"] = kind
	_surface.imprint(point, kind, load_ratio, slip, speed, delta)
	return result


## Поверхность в точке: полотно — асфальт, за кромкой (обочина и земля) —
## трава. Граница берётся по фактической ширине полотна в этом месте.
func surface_kind_at(world_point: Vector3, grass: bool = false) -> String:
	var on_road: bool = _on_surface(world_point)
	return _surface.surface_kind(track.surface_name, grass or not on_road, 0.0)


## Лежит ли точка на полотне (а не за кромкой). Поиск дороги кэшируется:
## четыре колеса спрашивают почти одну и ту же точку в одном физическом кадре,
## а `nearest` по 100 км дороги — не бесплатный.
func _on_surface(world_point: Vector3) -> bool:
	# Кэш живёт один физический кадр: колесо 2..4 попадают в него, потому что
	# стоят в пределах пары метров от первого.
	if world_point.distance_to(_query_point) > 2.0:
		var near: Vector2 = network.nearest(world_point.x, world_point.z, _last_along)
		var offset: Vector3 = world_point - network.point_at(near.y)
		var direction: Vector3 = network.direction_at(near.y)
		_query_half = ChunkType.half_width_at(near.y, generation_seed) + ChunkType.SHOULDER
		_lateral_cache = absf(Vector3(direction.z, 0.0, -direction.x).dot(offset))
		_query_point = world_point
	# Обочина ещё «держит» полотно: съезд на неё не даёт травяного сцепления
	# мгновенно, иначе машина «клюёт» на каждом расширении.
	return _lateral_cache <= _query_half


func live_surface_grip(_world_point: Vector3) -> float:
	return 1.0


## Тряска камеры от скорости — из того же узла VisualEffects/Speed, что и в
## раллийных заездах, чтобы «ощущение скорости» не отличалось.
func speed_shake_offset(speed_kmh: float, time_sec: float) -> Vector3:
	var feel := get_node_or_null("VisualEffects/Speed")
	if feel == null:
		return Vector3.ZERO
	if not feel.has_method("sample_camera_shake_offset"):
		return Vector3.ZERO
	return feel.call("sample_camera_shake_offset", speed_kmh, true, time_sec)


func speed_shake_angles(speed_kmh: float, time_sec: float) -> Vector3:
	var feel := get_node_or_null("VisualEffects/Speed")
	if feel == null:
		return Vector3.ZERO
	if not feel.has_method("sample_camera_shake_angles_rad"):
		return Vector3.ZERO
	return feel.call("sample_camera_shake_angles_rad", speed_kmh, true, time_sec)
