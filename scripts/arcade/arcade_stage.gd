## Аркадный заезд: бесконечная двухполосная дорога, живая природа и погода,
## без финиша и без мини-карты.
##
## Реализует тот же контракт с машиной (`surface_contact`, `live_surface_grip`,
## `speed_shake_offset`, `speed_shake_angles`, `surface_kind_at`) и поддерживает
## все условия из меню (погоду, время суток, профиль покрытия, осадки, PS1-стиль
## и телеметрию HUD).
class_name RallyArcadeStage
extends Node3D

const RoadType = preload("res://scripts/arcade/arcade_road.gd")
const NetworkType = preload("res://scripts/arcade/arcade_network.gd")
const StreamerType = preload("res://scripts/arcade/arcade_streamer.gd")
const ChunkType = preload("res://scripts/arcade/arcade_chunk.gd")
const TerrainType = preload("res://scripts/arcade/arcade_terrain.gd")
const SceneryType = preload("res://scripts/arcade/arcade_scenery.gd")
const TrafficType = preload("res://scripts/arcade/arcade_traffic.gd")
const PedestriansType = preload("res://scripts/arcade/arcade_pedestrians.gd")
const RulesType = preload("res://scripts/arcade/arcade_rules.gd")
const ArcadeSettingsType = preload("res://scripts/data/rally_arcade_settings.gd")
const LegType = preload("res://scripts/data/rally_arcade_leg.gd")
const TrackType = preload("res://scripts/data/rally_track_config.gd")
const SettingsType = preload("res://scripts/data/rally_stage_settings.gd")
const SpawnType = preload("res://scripts/data/rally_spawn_layout.gd")
const WeatherType = preload("res://scripts/data/rally_weather_config.gd")
const ProfileType = preload("res://scripts/data/rally_track_profile.gd")
const SurfaceType = preload("res://scripts/road_surface.gd")
const RoadShader = preload("res://shaders/gravel_road.gdshader")
const GroundShader = preload("res://shaders/forest_ground.gdshader")
const NightSkyShader = preload("res://shaders/night_sky.gdshader")
const GravelTexture = preload("res://textures/environment/gravel.png")
const GroundTexture = preload("res://textures/environment/forest_floor.png")
const RockTexture = preload("res://textures/environment/rock.png")
const HudType = preload("res://scripts/ui/rally_hud.gd")
const CarType = preload("res://scripts/rally_car.gd")
const CarSetupType = preload("res://scripts/data/rally_car_setup.gd")
const CarModels = preload("res://scripts/car_models.gd")
const ScreenLookType = preload("res://scripts/effects/rally_screen_look.gd")
const SpeedFeelType = preload("res://scripts/effects/rally_speed_feel.gd")
const GaugeBar = preload("res://scripts/ui/telemetry_bar.gd")
const InputSettings = preload("res://scripts/ui/input_settings.gd")

const DEFAULT_TRACK_PATH := "res://data/tracks/stage_arcade.tres"
const DEFAULT_SETTINGS_PATH := "res://data/stage/default_stage_settings.tres"
const DEFAULT_SPAWN_PATH := "res://data/stage/default_spawn_layout.tres"
const DEFAULT_ARCADE_SETTINGS_PATH := "res://data/stage/default_arcade_settings.tres"
const HUD_REFRESH: float = 0.08

## Сид генерации. 0 — взять сид заезда из трассы / времени.
@export var generation_seed: int = 0
@export var track: TrackType = null
@export var settings: SettingsType = null
@export var spawn_layout: SpawnType = null
@export var arcade_settings: ArcadeSettingsType = null
@export var car_setup_override: CarSetupType = null

var network: NetworkType = null
var car = null
var hud: HudType = null
var weather: WeatherType = null
var track_profile: ProfileType = null
var time_choice: int = 0

var _streamer: StreamerType = null
var _terrain: TerrainType = null
var _scenery: SceneryType = null
var _traffic: TrafficType = null
var _pedestrians: PedestriansType = null
var _rules: RulesType = null
var _surface = SurfaceType.new()
var _road_material: ShaderMaterial = null
var _ground_material: ShaderMaterial = null
var _weather_particles: GPUParticles3D = null
var _input_settings = null

var _last_along: float = 0.0
var _max_along: float = 0.0
var _max_speed_kmh: float = 0.0
var _elapsed_time: float = 0.0
var _frame_delta: float = 0.016
var _prev_lin_vel := Vector3.ZERO
var _prev_physics_vel := Vector3.ZERO
var _is_night: bool = false
var _best_distance_m: float = 0.0

var _query_point := Vector3(INF, INF, INF)
var _query_half: float = 0.0
var _lateral_cache: float = 0.0
var _hud_clock: float = 0.0
var _is_paused: bool = false

var _alert_text: String = ""
var _alert_color := Color(1.0, 0.8, 0.2, 1.0)
var _alert_timer: float = 0.0

var _arcade_panel: PanelContainer = null
var _hp_bar: ProgressBar = null
var _hp_fill_style: StyleBoxFlat = null
var _hp_value_label: Label = null
var _score_label: Label = null
var _mult_label: Label = null
var _overtake_label: Label = null
var _results_panel: Control = null
var _results_title: Label = null
var _results_label: Label = null
var _again_button: Button = null

var _pause_panel: CanvasItem = null
var _resume_button: Button = null
var _stage_title: Label = null
var _stage_label: Label = null
var _timer_label: Label = null
var _split_label: Label = null
var _speed_label: Label = null
var _gear_label: Label = null
var _setup_label: Label = null
var _engine_label: Label = null
var _rpm_bar: ProgressBar = null
var _rpm_caption: Label = null
var _throttle_bar: GaugeBar = null
var _brake_bar: GaugeBar = null
var _steer_bar: GaugeBar = null
var _slip_bar: GaugeBar = null
var _suspension_bar: GaugeBar = null
var _gforce_bar: GaugeBar = null
var _clutch_notice: Label = null
var _hint_label: Label = null


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		return
	var game: Node = get_node_or_null("/root/RallyGame")
	if game != null:
		_swap_race_car(game)
	_apply_race_setup(game)


func _swap_race_car(game: Node) -> void:
	if not game.has_method("get_race_vehicle_id"):
		return
	var scene_path := CarModels.race_scene_path(String(game.call("get_race_vehicle_id")))
	var current := get_node_or_null("RallyCar") as Node3D
	if current == null or scene_path.is_empty() or current.scene_file_path == scene_path:
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_warning("RallyArcadeStage: сцена машины %s не открывается" % scene_path)
		return
	var replacement := packed.instantiate() as Node3D
	if replacement == null:
		return
	replacement.name = "RallyCar"
	replacement.transform = current.transform
	var idx := current.get_index()
	remove_child(current)
	current.free()
	add_child(replacement)
	move_child(replacement, idx)


func _apply_race_setup(game: Node) -> void:
	var car_node := get_node_or_null("RallyCar") as CarType
	if car_node == null:
		return
	var setup: CarSetupType = null
	if game != null and game.has_method("get_race_setup_override"):
		setup = game.call("get_race_setup_override") as CarSetupType
	if setup == null:
		setup = car_setup_override
	if setup != null:
		car_node.setup_override = setup
		if game != null:
			game.set("current_setup", setup)


func _ready() -> void:
	add_to_group("rally_stage")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_resources()
	_read_game_conditions()
	_apply_conditions_to_track()
	_resolve_seed()
	network = NetworkType.new(generation_seed)
	var car_node := get_node_or_null("RallyCar") as RigidBody3D
	if car_node != null:
		car_node.freeze = true
	_configure_world()
	_build_world()
	_configure_car()
	_setup_precipitation()
	_setup_hud()
	if car_node != null:
		car_node.freeze = false
	var game: Node = get_node_or_null("/root/RallyGame")
	if game != null and game.has_method("finish_loading"):
		game.call("finish_loading")


func _process(delta: float) -> void:
	if car == null or _streamer == null:
		return
	if _is_paused or (_rules != null and _rules.run_ended):
		return
	_frame_delta = maxf(delta, 0.0001)
	_elapsed_time += delta
	if _alert_timer > 0.0:
		_alert_timer = maxf(0.0, _alert_timer - delta)
	var here: Vector3 = car.global_position
	var near: Vector2 = network.nearest(here.x, here.z, _last_along)
	_last_along = near.y
	_max_along = maxf(_max_along, _last_along)
	_max_speed_kmh = maxf(_max_speed_kmh, float(car.speed_kmh))

	var lookahead_dist: float = _last_along + StreamerType.LOOKAHEAD * StreamerType.CHUNK_LENGTH
	network.ensure_length(lookahead_dist)
	if _terrain != null:
		_terrain.sync_road_to(lookahead_dist + StreamerType.CHUNK_LENGTH)
		_terrain.focus(here)
	_streamer.focus(_last_along)

	if _weather_particles != null and is_instance_valid(_weather_particles):
		var fx_root := get_node_or_null("VisualEffects")
		if fx_root != null and fx_root.has_method("anchor_for"):
			_weather_particles.global_position = fx_root.call("anchor_for", here, car.linear_velocity)

	_hud_clock += delta
	if _hud_clock >= HUD_REFRESH:
		_hud_clock = 0.0
		_update_hud()


func _physics_process(delta: float) -> void:
	if _is_paused or car == null:
		return
	if _rules != null and _rules.run_ended:
		return

	var vel: Vector3 = car.linear_velocity
	var cur_horiz := Vector2(vel.x, vel.z)
	var prev_horiz := Vector2(_prev_physics_vel.x, _prev_physics_vel.z)
	var dv_horiz: float = 0.0
	if _elapsed_time > 1.2:
		dv_horiz = cur_horiz.distance_to(prev_horiz)
	_prev_physics_vel = vel

	if _traffic != null:
		_traffic.step(delta, _last_along, car.global_position, vel)
		if _rules != null:
			for ev in _traffic.last_events:
				_push_alert(_rules.on_traffic_event(ev))

	if _pedestrians != null:
		var ped_events: Array[Dictionary] = _pedestrians.step(delta, _last_along, car.global_position, vel, car)
		if _rules != null:
			for ev in ped_events:
				_push_alert(_rules.on_pedestrian_event(ev))

	if _rules != null:
		var on_road: bool = _on_surface(car.global_position)
		var speed_mps: float = cur_horiz.length()
		var tick_alerts: Array[Dictionary] = _rules.tick(delta, speed_mps, on_road, _max_along, dv_horiz)
		for al in tick_alerts:
			_push_alert(al)
		if _rules.run_ended:
			_end_arcade_run()


func _resolve_seed() -> void:
	if generation_seed == 0 and track != null:
		generation_seed = int(track.get("generation_seed"))
	if generation_seed == 0:
		generation_seed = int(Time.get_unix_time_from_system() * 1000.0) & 0x7fffffff
	RoadType.reset(generation_seed)


# --------------------------------------------------------------- ресурсы и условия


func _load_resources() -> void:
	if track == null:
		track = _load(DEFAULT_TRACK_PATH) as TrackType
	if track != null:
		track = track.duplicate() as TrackType
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
	if arcade_settings == null:
		arcade_settings = _load(DEFAULT_ARCADE_SETTINGS_PATH) as ArcadeSettingsType
	if arcade_settings == null:
		arcade_settings = ArcadeSettingsType.new()


func _load(path: String) -> Resource:
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path)


func _read_game_conditions() -> void:
	var game: Node = get_node_or_null("/root/RallyGame")
	if game == null:
		return
	var selected_weather: Variant = game.get("current_weather")
	if selected_weather is WeatherType:
		var candidate := selected_weather as WeatherType
		weather = null if candidate.id == "default" else candidate
	var selected_profile: Variant = game.get("current_profile")
	if selected_profile is ProfileType:
		track_profile = selected_profile as ProfileType
	var selected_time: Variant = game.get("time_index")
	if selected_time is int:
		time_choice = clampi(int(selected_time), 0, 2)


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


# --------------------------------------------------------- небо, свет, погода


func _configure_world() -> void:
	var cfg := settings
	_is_night = WeatherType.resolve_night_choice(time_choice, weather, track.night_mode)
	var sky_top: Color = _weather_sky_color(track.sky_top_color)
	var sky_horizon: Color = _weather_sky_color(track.sky_horizon_color)
	var fog_col: Color = _weather_fog_tint(track.fog_color)
	var fog_density: float = track.fog_density
	var volumetric: bool = track.volumetric_fog
	var volumetric_density: float = track.volumetric_fog_density
	var ambient_energy: float = track.ambient_energy
	var exposure: float = track.exposure
	var sun_energy: float = track.sun_energy
	var sun_col: Color = track.sun_color
	var ambient_col: Color = track.ambient_color
	if weather != null:
		fog_density = clampf(
			track.fog_density * weather.fog_density_scale + weather.fog_density_add, 0.0, 0.06
		)
		volumetric = volumetric or weather.volumetric_fog
		volumetric_density = clampf(
			track.volumetric_fog_density * weather.fog_density_scale + weather.fog_density_add * 0.5,
			0.0,
			0.05
		)
		ambient_energy *= weather.ambient_energy_scale
		exposure *= weather.exposure_scale
		sun_energy *= weather.sun_energy_scale
		sun_col = track.sun_color.lerp(weather.sun_tint, weather.sun_tint_strength)
	if _is_night != track.night_mode:
		if _is_night:
			sun_energy *= cfg.night_sun_scale
			sun_col = sun_col.lerp(cfg.night_sun_tint, cfg.night_sun_tint_strength)
			ambient_energy *= cfg.night_ambient_scale
			ambient_col = cfg.night_ambient_color
			sky_top = _weather_sky_color(cfg.night_sky_top)
			sky_horizon = _weather_sky_color(cfg.night_sky_horizon)
			fog_col = _weather_fog_tint(cfg.night_fog_color)
		else:
			sun_energy = cfg.day_sun_energy
			sun_col = cfg.day_sun_color
			ambient_energy = cfg.day_ambient_energy
			ambient_col = cfg.day_ambient_color
			sky_top = _weather_sky_color(cfg.day_sky_top)
			sky_horizon = _weather_sky_color(cfg.day_sky_horizon)
			fog_col = _weather_fog_tint(cfg.day_fog_color)

	var world_env := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env != null:
		var env: Environment = null
		if world_env.environment != null:
			env = world_env.environment.duplicate() as Environment
		if env == null:
			env = Environment.new()
		var sky := Sky.new()
		if _is_night:
			var night_mat := ShaderMaterial.new()
			night_mat.shader = NightSkyShader
			night_mat.set_shader_parameter("sky_top_color", sky_top)
			night_mat.set_shader_parameter("sky_horizon_color", sky_horizon)
			night_mat.set_shader_parameter("star_intensity", track.star_intensity)
			sky.sky_material = night_mat
		else:
			var day_mat := ProceduralSkyMaterial.new()
			day_mat.sky_top_color = sky_top
			day_mat.sky_horizon_color = sky_horizon
			day_mat.ground_bottom_color = track.ground_color * 0.4
			day_mat.ground_horizon_color = sky_horizon
			day_mat.sky_curve = 0.55 if track.ps1_style and track.sky_flat else 0.18
			sky.sky_material = day_mat
		env.background_mode = Environment.BG_SKY
		env.background_energy_multiplier = 1.0
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = ambient_col
		env.ambient_light_energy = ambient_energy
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = exposure
		env.glow_enabled = true
		env.glow_intensity = cfg.glow_intensity_ps1 if track.ps1_style else cfg.glow_intensity_normal
		env.glow_bloom = cfg.glow_bloom_ps1 if track.ps1_style else cfg.glow_bloom_normal
		env.ssao_enabled = cfg.ssao_enabled and track.screen_space_ao
		env.ssao_radius = cfg.ssao_radius
		env.ssao_intensity = cfg.ssao_intensity
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
		env.fog_light_color = fog_col
		if track.ps1_style:
			var fog_begin: float = maxf(0.0, track.fog_near * _weather_visibility_scale())
			var fog_end: float = maxf(fog_begin + 1.0, track.fog_far * _weather_visibility_scale())
			env.fog_mode = Environment.FOG_MODE_DEPTH
			env.fog_depth_end = fog_end
			env.fog_depth_begin = fog_begin
			env.fog_depth_curve = cfg.fog_depth_curve
			env.fog_density = cfg.fog_ps1_opacity if fog_density > 0.0 else 0.0
			env.fog_sky_affect = clampf(
				1.0 - 0.65 * _weather_visibility_scale(), cfg.fog_sky_affect_min, cfg.fog_sky_affect_max
			)
		else:
			env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
			env.fog_density = fog_density
			env.fog_sky_affect = 1.0
		world_env.environment = env

	var sun_light := get_node_or_null("SunLight") as DirectionalLight3D
	if sun_light != null:
		sun_light.rotation = Vector3(deg_to_rad(track.sun_pitch), deg_to_rad(track.sun_yaw), 0.0)
		sun_light.light_color = sun_col
		sun_light.light_energy = sun_energy


func _weather_sky_color(base: Color) -> Color:
	if weather == null:
		return base
	var result: Color = base.lerp(weather.sky_tint, weather.sky_tint_strength)
	if weather.sky_desaturation > 0.0:
		var luminance: float = result.get_luminance()
		result = result.lerp(Color(luminance, luminance, luminance, result.a), weather.sky_desaturation)
	return result


func _weather_fog_tint(base: Color) -> Color:
	if weather == null:
		return base
	return base.lerp(weather.fog_color, weather.fog_color_strength)


func _weather_visibility_scale() -> float:
	return weather.visibility_scale if weather != null else 1.0


func _weather_wetness() -> float:
	return weather.wetness if weather != null else 0.0


func _weather_snow_cover() -> float:
	return weather.snow_cover if weather != null else 0.0


func _setup_precipitation() -> void:
	if _weather_particles != null:
		_weather_particles.queue_free()
		_weather_particles = null
	if not settings.precipitation_enabled:
		return
	if weather == null or not weather.has_precipitation():
		return
	if DisplayServer.get_name() == "headless":
		return
	var fx_root := get_node_or_null("VisualEffects")
	if fx_root == null or not fx_root.has_method("make_weather_particles"):
		return
	var particles := fx_root.call("make_weather_particles", weather) as GPUParticles3D
	if particles == null:
		return
	add_child(particles)
	if car != null and fx_root.has_method("anchor_for"):
		particles.global_position = fx_root.call("anchor_for", car.global_position, car.linear_velocity)
	particles.emitting = true
	_weather_particles = particles


# ------------------------------------------------------------------ мир


func _build_world() -> void:
	_road_material = _make_road_material()
	_ground_material = _make_ground_material()

	var use_scenery: bool = arcade_settings.scenery_enabled if arcade_settings != null else true
	var use_terrain: bool = arcade_settings.terrain_enabled if arcade_settings != null else true

	if use_scenery:
		_scenery = SceneryType.new()
		_scenery.configure(track.ps1_style and settings.scenery_ps1_filter, _is_night)
		_scenery.warm_up()
	else:
		_scenery = null

	var prime_dist: float = StreamerType.CHUNK_LENGTH * float(StreamerType.LOOKAHEAD + 2)
	network.ensure_length(prime_dist)
	if use_terrain:
		_terrain = TerrainType.new()
		_terrain.name = "ArcadeTerrain"
		add_child(_terrain)
		_terrain.setup(
			generation_seed,
			track.terrain_seed,
			track.hills_height,
			track.hills_frequency,
			track.ridge_height,
			track.ridge_frequency,
			track.detail_height,
			_ground_material
		)
		_terrain.sync_road_to(prime_dist)
		var spawn_pt: Vector3 = network.point_at(clampf(spawn_layout.car_spawn_distance, 0.0, 40.0))
		_terrain.prime(spawn_pt)
	else:
		_terrain = null

	_streamer = StreamerType.new()
	_streamer.name = "RoadStreamer"
	add_child(_streamer)
	var is_loose: bool = track.surface_name != "Асфальт"
	_streamer.setup(generation_seed, _road_material, _ground_material, {
		"terrain": _terrain,
		"scenery": _scenery,
		"road_color": track.road_color,
		"road_color_2": track.road_color_2,
		"shoulder_color": track.shoulder_color,
		"edge_post_color": track.edge_post_color,
		"loose_surface": is_loose,
	})
	var behind: float = StreamerType.KEEP_BEHIND * StreamerType.CHUNK_LENGTH + 1.0
	_streamer.focus(0.0)
	_streamer.prime(behind, StreamerType.LOOKAHEAD)

	var spawn_d: float = clampf(spawn_layout.car_spawn_distance, 0.0, 40.0)
	_traffic = get_node_or_null("ArcadeTraffic") as TrafficType
	if _traffic == null:
		_traffic = TrafficType.new()
		_traffic.name = "ArcadeTraffic"
		add_child(_traffic)
	_traffic.process_mode = Node.PROCESS_MODE_PAUSABLE
	_traffic.setup(generation_seed, network, _is_night, arcade_settings)
	_traffic.prime(spawn_d)

	_pedestrians = get_node_or_null("ArcadePedestrians") as PedestriansType
	if _pedestrians == null:
		_pedestrians = PedestriansType.new()
		_pedestrians.name = "ArcadePedestrians"
		add_child(_pedestrians)
	_pedestrians.process_mode = Node.PROCESS_MODE_PAUSABLE
	_pedestrians.setup(generation_seed, network, self, arcade_settings)
	_pedestrians.prime(spawn_d)

	_rules = RulesType.new()
	_rules.configure(arcade_settings)
	_best_distance_m = RulesType.best_distance(arcade_settings)


func _make_road_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = RoadShader
	mat.set_shader_parameter("gravel_texture", GravelTexture)
	mat.set_shader_parameter("gravel_texture_smooth", GravelTexture)
	mat.set_shader_parameter("ps1_textures", track.ps1_style)
	mat.set_shader_parameter("section_surfaces", true)
	mat.set_shader_parameter("stage_length", 1.0e9)
	mat.set_shader_parameter("road_roughness", settings.road_roughness)
	mat.set_shader_parameter("detail_strength", settings.road_detail_strength)
	mat.set_shader_parameter("track_strength", settings.road_track_strength)
	var relief: float = settings.road_loose_relief_asphalt if track.surface_name == "Асфальт" else settings.road_loose_relief
	mat.set_shader_parameter("loose_relief", relief)
	mat.set_shader_parameter("vertex_snap", settings.retro_vertex_snap if settings.is_retro(track) else 0.0)
	mat.set_shader_parameter("resolution_y", float(settings.retro_resolution_height))
	mat.set_shader_parameter("wetness", _weather_wetness())
	mat.set_shader_parameter("snow_cover", _weather_snow_cover())
	settings.apply_shader_overrides(mat, settings.road_shader_overrides)
	return mat


func _make_ground_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = GroundShader
	mat.set_shader_parameter("ground_texture", GroundTexture)
	mat.set_shader_parameter("rock_texture", RockTexture)
	mat.set_shader_parameter("ground_texture_smooth", GroundTexture)
	mat.set_shader_parameter("rock_texture_smooth", RockTexture)
	mat.set_shader_parameter("ps1_textures", track.ps1_style)
	mat.set_shader_parameter("ground_color", track.ground_color)
	mat.set_shader_parameter("ground_color_2", track.ground_color_2)
	mat.set_shader_parameter("road_edge_color", track.shoulder_color)
	mat.set_shader_parameter("rock_color", track.rock_color)
	mat.set_shader_parameter("surface_roughness", settings.ground_surface_roughness)
	mat.set_shader_parameter("grain_scale", settings.ground_grain_scale)
	mat.set_shader_parameter("flat_shading", 1.0 if track.ps1_style and track.flat_shading else 0.0)
	mat.set_shader_parameter("vertex_snap", settings.retro_vertex_snap if settings.is_retro(track) else 0.0)
	mat.set_shader_parameter("resolution_y", float(settings.retro_resolution_height))
	mat.set_shader_parameter("wetness", _weather_wetness())
	mat.set_shader_parameter("snow_cover", _weather_snow_cover())
	settings.apply_shader_overrides(mat, settings.ground_shader_overrides)
	return mat


# ------------------------------------------------------------------ HUD


func _setup_hud() -> void:
	hud = get_node_or_null("HUD/RallyHUD") as HudType
	if hud == null:
		return
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	_stage_title = hud.get_node_or_null("StagePanel/StageBox/StageTitle") as Label
	_stage_label = hud.get_node_or_null("StagePanel/StageBox/StageLabel") as Label
	if _stage_title != null:
		_stage_title.text = track.display_name

	_timer_label = hud.get_node_or_null("TimerPanel/TimerBox/TimerLabel") as Label
	_split_label = hud.get_node_or_null("TimerPanel/TimerBox/SplitLabel") as Label

	_speed_label = hud.get_node_or_null("SpeedPanel/SpeedBox/SpeedLabel") as Label
	_gear_label = hud.get_node_or_null("SpeedPanel/SpeedBox/GearLabel") as Label
	_setup_label = hud.get_node_or_null("SpeedPanel/SpeedBox/SetupLabel") as Label
	_engine_label = hud.get_node_or_null("SpeedPanel/SpeedBox/EngineLabel") as Label
	_rpm_bar = hud.get_node_or_null("SpeedPanel/SpeedBox/RPMBar") as ProgressBar
	_rpm_caption = hud.get_node_or_null("SpeedPanel/SpeedBox/RpmCaption") as Label

	_throttle_bar = hud.get_node_or_null("TelemetryPanel/TeleBox/ThrottleBar") as GaugeBar
	_brake_bar = hud.get_node_or_null("TelemetryPanel/TeleBox/BrakeBar") as GaugeBar
	_steer_bar = hud.get_node_or_null("TelemetryPanel/TeleBox/SteerBar") as GaugeBar
	_slip_bar = hud.get_node_or_null("TelemetryPanel/TeleBox/SlipBar") as GaugeBar
	_suspension_bar = hud.get_node_or_null("TelemetryPanel/TeleBox/SuspensionBar") as GaugeBar
	_gforce_bar = hud.get_node_or_null("TelemetryPanel/TeleBox/GForceBar") as GaugeBar

	_clutch_notice = hud.get_node_or_null("ClutchNotice") as Label
	_hint_label = hud.get_node_or_null("Hint") as Label

	if car != null:
		hud.bind_vehicle(car)
	for path in ["ResultsPanel", "MiniMapPanel", "MiniMap"]:
		var node := hud.get_node_or_null(path) as CanvasItem
		if node != null:
			node.visible = false
	_setup_arcade_hud()
	_setup_pause()
	_setup_screen()
	_update_input_hint()
	var controller := _controller_manager()
	if controller != null and controller.has_signal("active_device_changed"):
		if not controller.is_connected("active_device_changed", _on_active_input_device_changed):
			controller.connect("active_device_changed", _on_active_input_device_changed)
		if controller.has_signal("bindings_changed") and not controller.is_connected("bindings_changed", _update_input_hint):
			controller.connect("bindings_changed", _update_input_hint)
	_update_hud()


func _controller_manager() -> Node:
	return get_node_or_null("/root/ControllerManager")


func _on_active_input_device_changed(_gamepad_active: bool) -> void:
	_update_input_hint()


func _update_input_hint() -> void:
	if _hint_label == null:
		return
	var controller := _controller_manager()
	if controller == null or not controller.has_method("binding_label"):
		return
	var device := "gamepad" if bool(controller.get("gamepad_active")) else "keyboard"
	var label := func(action: String) -> String: return String(controller.call("binding_label", action, device))
	_hint_label.text = "[%s/%s] ГАЗ/ТОРМОЗ  •  [%s/%s] РУЛЬ  •  [%s] РУЧНИК  •  [%s/%s] КПП" % [
		label.call("throttle"), label.call("brake"), label.call("steer_left"), label.call("steer_right"),
		label.call("handbrake"), label.call("shift_down"), label.call("shift_up"),
	]
	if car != null and car.manual_clutch_control:
		_hint_label.text += "  •  [%s] СЦЕПЛЕНИЕ" % label.call("clutch")
	_hint_label.text += "  •  [%s] КАМЕРА  •  [%s] ПАУЗА" % [label.call("camera_switch"), label.call("pause")]
	if device == "keyboard":
		_hint_label.text += "  •  [%s] ТРЕК  •  [%s] RADIO" % [
			label.call("radio_next"), label.call("radio_toggle")
		]


func _setup_pause() -> void:
	_pause_panel = hud.get_node_or_null("PausePanel") as CanvasItem
	if _pause_panel != null:
		_pause_panel.visible = false
		for node in _pause_panel.find_children("*", "Control", true, false):
			var control := node as Control
			if control is BaseButton or control is Range:
				control.focus_mode = Control.FOCUS_ALL
	var camera_settings := hud.get_node_or_null("PausePanel/Box/CameraOptions")
	if camera_settings != null and camera_settings.has_method("initialize"):
		camera_settings.call("initialize", car)
	_resume_button = hud.get_node_or_null("PausePanel/Box/ResumeButton") as Button
	_connect_button("PausePanel/Box/ControlsButton", _open_input_settings)
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


func _open_input_settings() -> void:
	var hud_root := get_node_or_null("HUD")
	if hud_root == null:
		return
	if _input_settings == null:
		_input_settings = InputSettings.new()
		_input_settings.name = "InputSettings"
		hud_root.add_child(_input_settings)
	hud_root.move_child(_input_settings, hud_root.get_child_count() - 1)
	_input_settings.open()


func _unhandled_input(event: InputEvent) -> void:
	if _input_settings != null and _input_settings.blocks_actions():
		return
	if _rules != null and _rules.run_ended:
		return
	if event.is_action_pressed("ui_cancel"):
		_set_paused(not _is_paused)
		get_viewport().set_input_as_handled()


func _setup_arcade_hud() -> void:
	if hud == null:
		return
	_results_panel = hud.get_node_or_null("ResultsPanel") as Control
	_results_title = hud.get_node_or_null("ResultsPanel/Box/FinishTitle") as Label
	_results_label = hud.get_node_or_null("ResultsPanel/Box/ResultsLabel") as Label
	_again_button = hud.get_node_or_null("ResultsPanel/Box/AgainButton") as Button
	_connect_button("ResultsPanel/Box/AgainButton", _on_restart_pressed)
	_connect_button("ResultsPanel/Box/MenuButton", _on_menu_pressed)
	if _results_panel != null:
		_results_panel.custom_minimum_size = Vector2(560.0, 470.0)
	if _results_label != null:
		_results_label.add_theme_font_size_override("font_size", 16)

	var scene_panel := get_node_or_null("HUD/ArcadeStatusPanel") as PanelContainer
	if scene_panel != null:
		_arcade_panel = scene_panel
		_hp_value_label = scene_panel.get_node_or_null("Box/HpRow/HpValue") as Label
		_hp_bar = scene_panel.get_node_or_null("Box/HpBar") as ProgressBar
		_score_label = scene_panel.get_node_or_null("Box/ScoreRow/ScoreLabel") as Label
		_mult_label = scene_panel.get_node_or_null("Box/ScoreRow/MultiplierLabel") as Label
		_overtake_label = scene_panel.get_node_or_null("Box/StatsLabel") as Label
		if _hp_bar != null:
			_hp_bar.max_value = _rules.max_hp if _rules != null else RulesType.MAX_HP
			_hp_bar.value = _hp_bar.max_value
			var existing_fill := _hp_bar.get_theme_stylebox("fill")
			if existing_fill is StyleBoxFlat:
				_hp_fill_style = (existing_fill as StyleBoxFlat).duplicate() as StyleBoxFlat
				_hp_bar.add_theme_stylebox_override("fill", _hp_fill_style)
	else:
		if _arcade_panel != null and is_instance_valid(_arcade_panel):
			_arcade_panel.queue_free()
		var panel := PanelContainer.new()
		panel.name = "ArcadeStatusPanel"
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		panel.offset_left = -256.0
		panel.offset_top = 20.0
		panel.offset_right = -24.0
		panel.offset_bottom = 176.0
		var box_style := StyleBoxFlat.new()
		box_style.bg_color = Color(0.03, 0.04, 0.06, 0.88)
		box_style.skew = Vector2(0.06, 0.0)
		box_style.border_width_left = 4
		box_style.border_width_top = 1
		box_style.border_width_right = 1
		box_style.border_width_bottom = 1
		box_style.border_color = Color(1.0, 0.45, 0.05, 1.0)
		box_style.corner_radius_top_left = 4
		box_style.corner_radius_top_right = 10
		box_style.corner_radius_bottom_left = 6
		box_style.corner_radius_bottom_right = 4
		box_style.content_margin_left = 14.0
		box_style.content_margin_right = 14.0
		box_style.content_margin_top = 10.0
		box_style.content_margin_bottom = 10.0
		panel.add_theme_stylebox_override("panel", box_style)
		var vbox := VBoxContainer.new()
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_theme_constant_override("separation", 4)
		panel.add_child(vbox)
		var hp_row := HBoxContainer.new()
		hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(hp_row)
		var hp_title := Label.new()
		hp_title.text = "ПРОЧНОСТЬ"
		hp_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hp_title.add_theme_font_size_override("font_size", 11)
		hp_title.add_theme_color_override("font_color", Color(0.85, 0.90, 0.96, 0.92))
		hp_row.add_child(hp_title)
		_hp_value_label = Label.new()
		_hp_value_label.text = "100 / 100"
		_hp_value_label.add_theme_font_size_override("font_size", 12)
		_hp_value_label.add_theme_color_override("font_color", Color(0.32, 0.96, 0.58, 1.0))
		hp_row.add_child(_hp_value_label)
		_hp_bar = ProgressBar.new()
		_hp_bar.custom_minimum_size = Vector2(0.0, 14.0)
		_hp_bar.max_value = _rules.max_hp if _rules != null else RulesType.MAX_HP
		_hp_bar.value = _hp_bar.max_value
		_hp_bar.show_percentage = false
		var hp_bg := StyleBoxFlat.new()
		hp_bg.bg_color = Color(0.14, 0.16, 0.20, 0.9)
		_hp_fill_style = StyleBoxFlat.new()
		_hp_fill_style.bg_color = Color(0.28, 0.92, 0.52, 1.0)
		_hp_bar.add_theme_stylebox_override("background", hp_bg)
		_hp_bar.add_theme_stylebox_override("fill", _hp_fill_style)
		vbox.add_child(_hp_bar)
		var score_row := HBoxContainer.new()
		score_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(score_row)
		_score_label = Label.new()
		_score_label.text = "ОЧКИ: 0"
		_score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_score_label.add_theme_font_size_override("font_size", 18)
		score_row.add_child(_score_label)
		_mult_label = Label.new()
		_mult_label.text = "×1.0"
		_mult_label.add_theme_font_size_override("font_size", 16)
		_mult_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.18, 1.0))
		score_row.add_child(_mult_label)
		_overtake_label = Label.new()
		_overtake_label.text = "ОБГОНЫ 0  |  РАЗЪЕЗДЫ 0  |  НАЕЗДЫ 0"
		_overtake_label.add_theme_font_size_override("font_size", 11)
		vbox.add_child(_overtake_label)
		hud.add_child(panel)
		_arcade_panel = panel

	var fps_label := hud.get_node_or_null("FPSLabel") as Control
	if fps_label != null:
		fps_label.offset_top = 186.0
		fps_label.offset_bottom = 214.0


func _push_alert(alert: Dictionary) -> void:
	if alert.is_empty():
		return
	_alert_text = String(alert.get("text", ""))
	var col: Variant = alert.get("color", Color(1.0, 0.80, 0.22, 1.0))
	if col is Color:
		_alert_color = col as Color
	_alert_timer = arcade_settings.alert_duration_sec if arcade_settings != null else 2.4


func _end_arcade_run() -> void:
	_update_hud()
	if car != null:
		car.process_mode = Node.PROCESS_MODE_DISABLED
	if get_tree() != null:
		get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var vehicle_name: String = "Ралли-кар"
	if car != null and car.active_setup != null and not car.active_setup.display_name.is_empty():
		vehicle_name = car.active_setup.display_name

	var lb: Dictionary = RulesType.record_run({
		"distance_m": _max_along,
		"score": _rules.score,
		"max_speed_kmh": _max_speed_kmh,
		"overtakes": _rules.overtakes,
		"near_misses": _rules.near_misses,
		"ped_hits": _rules.ped_hits,
		"elapsed_sec": _elapsed_time,
		"vehicle": vehicle_name,
	}, arcade_settings)
	_best_distance_m = RulesType.best_distance(arcade_settings)

	if _results_panel == null:
		return
	if _results_title != null:
		var is_rec: bool = bool(lb.get("is_record", false))
		_results_title.text = "НОВЫЙ РЕКОРД ДИСТАНЦИИ!" if is_rec else "МАШИНА РАЗБИТА!"
		_results_title.add_theme_color_override(
			"font_color", Color(0.32, 0.98, 0.58, 1.0) if is_rec else Color(1.0, 0.30, 0.22, 1.0)
		)

	if _results_label != null:
		var lines: Array[String] = []
		lines.append("ДИСТАНЦИЯ: %.0f м (%.2f км)   •   ОЧКИ: %d" % [_max_along, _max_along / 1000.0, _rules.score])
		lines.append("МАКС. СКОРОСТЬ: %d КМ/Ч   •   ВРЕМЯ: %s" % [roundi(_max_speed_kmh), _format_time(_elapsed_time)])
		lines.append("ОБГОНЫ: %d   •   РАЗЪЕЗДЫ: %d   •   НАЕЗДЫ: %d" % [_rules.overtakes, _rules.near_misses, _rules.ped_hits])
		lines.append("")
		lines.append("ТАБЛИЦА РЕЗУЛЬТАТОВ ПО ДИСТАНЦИИ:")
		var entries: Array = lb.get("entries", []) as Array
		var my_rank: int = int(lb.get("rank", -1))
		for i in range(entries.size()):
			var row: Dictionary = entries[i] as Dictionary
			var marker: String = "  ◀" if (i + 1) == my_rank else ""
			lines.append("%d. %.0f м  |  %d очк.  |  %d км/ч  |  %s%s" % [
				i + 1,
				float(row.get("distance_m", 0.0)),
				int(row.get("score", 0)),
				roundi(float(row.get("max_speed_kmh", 0.0))),
				String(row.get("vehicle", "—")),
				marker,
			])
		_results_label.text = "\n".join(lines)

	_results_panel.visible = true
	if _again_button != null:
		_again_button.grab_focus()


func _set_paused(value: bool) -> void:
	_is_paused = value
	get_tree().paused = value
	if _pause_panel != null:
		_pause_panel.visible = value
	if value:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if _resume_button != null:
			_resume_button.grab_focus()
	else:
		if _input_settings != null and _input_settings.visible:
			_input_settings.close()
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


func _exit_tree() -> void:
	if get_tree() != null:
		get_tree().paused = false


func _setup_screen() -> void:
	var screen := get_node_or_null("HUD/SpeedShaderRect") as ScreenLookType
	if screen == null:
		return
	var feel := get_node_or_null("VisualEffects/Speed") as SpeedFeelType
	if feel != null:
		screen.bind_speed(feel)
	screen.configure_for_track(track)
	screen.visible = true


func _current_domain_name(along: float) -> String:
	var leg_index: int = RoadType.leg_index_at(along)
	var built: RoadType.Leg = RoadType.leg(leg_index, generation_seed)
	if built == null:
		return "ДОРОГА"
	return LegType.kind_name(built.domain_at(along))


func _format_time(seconds: float) -> String:
	var minutes: int = floori(seconds / 60.0)
	var remaining: float = fmod(seconds, 60.0)
	return "%02d:%06.3f" % [minutes, remaining]


func _update_hud() -> void:
	if hud == null or car == null:
		return
	hud.set_camera_mode(car.camera_mode)
	var screen := get_node_or_null("HUD/SpeedShaderRect") as ScreenLookType
	if screen != null:
		screen.set_preview_speed(car.speed_kmh, car.camera_mode)

	var time_str: String = _format_time(_elapsed_time)
	hud.update_timer_display(time_str)
	if _split_label != null:
		var best_m: float = maxf(_best_distance_m, _max_along)
		_split_label.text = "ПРОБЕГ %.0f м  |  МАКС %d КМ/Ч  |  РЕКОРД %.0f м" % [_max_along, roundi(_max_speed_kmh), best_m]

	if _rules != null:
		var hp_val: float = _rules.hp
		if _hp_bar != null:
			_hp_bar.value = hp_val
		var hp_col := Color(0.28, 0.92, 0.52, 1.0)
		if hp_val < 30.0:
			hp_col = Color(1.0, 0.24, 0.18, 1.0)
		elif hp_val < 60.0:
			hp_col = Color(1.0, 0.72, 0.18, 1.0)
		if _hp_fill_style != null:
			_hp_fill_style.bg_color = hp_col
		if _hp_value_label != null:
			_hp_value_label.text = "%d / %d" % [ceili(hp_val), int(_rules.max_hp)]
			_hp_value_label.add_theme_color_override("font_color", hp_col)
		if _score_label != null:
			_score_label.text = "ОЧКИ: %d" % _rules.score
		if _mult_label != null:
			_mult_label.text = "×%.1f" % _rules.multiplier
		if _overtake_label != null:
			_overtake_label.text = "ОБГОНЫ %d  |  РАЗЪЕЗДЫ %d  |  НАЕЗДЫ %d" % [
				_rules.overtakes, _rules.near_misses, _rules.ped_hits
			]

	if _stage_label != null:
		var domain_label: String = _current_domain_name(_last_along)
		var width_m: float = ChunkType.half_width_at(_last_along, generation_seed) * 2.0
		var conditions: String = ""
		if weather != null:
			conditions += "  |  %s" % weather.short_name
		if track_profile != null:
			conditions += "  |  %s" % track_profile.display_name
		_stage_label.text = "%.2f км  |  %s · %.1f м  |  %s%s" % [
			_last_along / 1000.0, domain_label, width_m, track.surface_name, conditions
		]

	if _rpm_bar != null:
		_rpm_bar.max_value = car.max_rpm
		_rpm_bar.value = car.current_rpm
	if _rpm_caption != null:
		_rpm_caption.text = "%d / %d ОБ/МИН%s" % [
			roundi(car.current_rpm), roundi(car.max_rpm), " · ОТСЕЧКА" if car.motor_is_redline else ""
		]
	if _setup_label != null:
		var active_setup: CarSetupType = car.active_setup
		_setup_label.text = active_setup.display_name if active_setup != null else "СЦЕНИЧЕСКАЯ МАШИНА"
	if _engine_label != null:
		var active: CarSetupType = car.active_setup
		var engine_name: String = active.engine_name if active != null and not active.engine_name.is_empty() else "ДВИГАТЕЛЬ"
		var turbo_text: String = " · TURBO" if active != null and active.turbo and not engine_name.to_upper().contains("TURBO") else ""
		_engine_label.text = "%s · %d Н·м%s" % [engine_name, roundi(car.max_torque), turbo_text]

	if _speed_label != null:
		_speed_label.text = str(int(round(car.speed_kmh))).lpad(3, "0")
	if _gear_label != null:
		_gear_label.text = "%s  |  %s  |  %s" % [car.get_gear_label(), car.get_transmission_label(), car.get_drivetrain_label()]
	hud.update_speed_telemetry(
		car.speed_kmh, car.current_rpm, car.max_rpm, car.get_gear_label(), car.motor_is_redline
	)

	if _throttle_bar != null:
		_throttle_bar.set_value(car.throttle_amount)
	if _brake_bar != null:
		_brake_bar.set_value(car.brake_amount)
	if _steer_bar != null:
		_steer_bar.set_value(car.steering_amount)
	if _slip_bar != null:
		_slip_bar.set_value(clampf(car.get_average_tire_slip(), 0.0, 1.0))
	if _suspension_bar != null:
		_suspension_bar.set_value(car.get_max_suspension_compression())
	if _gforce_bar != null:
		var accel: Vector3 = (car.linear_velocity - _prev_lin_vel) / maxf(_frame_delta, 0.0001)
		_prev_lin_vel = car.linear_velocity
		_gforce_bar.set_value(clampf(Vector2(accel.x, accel.z).length() / 9.81, 0.0, 1.0))

	if _clutch_notice != null:
		var show_notice: bool = car.engine_stalled or car.shift_notice_time > 0.0 or _alert_timer > 0.0
		_clutch_notice.visible = show_notice
		if car.engine_stalled:
			_clutch_notice.add_theme_color_override("font_color", Color(1.0, 0.72, 0.2, 1.0))
			_clutch_notice.text = "ДВИГАТЕЛЬ ЗАГЛОХ — ВЫЖМИТЕ СЦЕПЛЕНИЕ И ГАЗ"
		elif _alert_timer > 0.0 and not _alert_text.is_empty():
			_clutch_notice.add_theme_color_override("font_color", _alert_color)
			_clutch_notice.text = _alert_text
		elif car.shift_notice_time > 0.0:
			_clutch_notice.add_theme_color_override("font_color", Color(1.0, 0.72, 0.2, 1.0))
			_clutch_notice.text = car.shift_notice_text


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
	_prev_physics_vel = Vector3.ZERO
	if _elapsed_time > 1.5 and _rules != null and not _rules.run_ended:
		_push_alert(_rules.on_rescue())
		if _rules.run_ended:
			_end_arcade_run.call_deferred()
	return _frame_at(near.y, spawn_layout.car_rescue_height_extra)


func surface_height_at(x: float, z: float) -> float:
	if _terrain != null:
		return _terrain.height_at(x, z)
	return ChunkType.surface_height(_last_along, 0.0, generation_seed)


func _frame_at(along: float, extra_height: float) -> Transform3D:
	var point: Vector3 = network.point_at(along)
	var direction: Vector3 = network.direction_at(along)
	var lateral: float = _driving_lateral(along)
	var side: Vector3 = Vector3(direction.z, 0.0, -direction.x)
	point += side * lateral
	var height_offset: float = extra_height
	if car != null and car.has_method("get_spawn_height_offset"):
		height_offset += float(car.call("get_spawn_height_offset"))
	var y: float = ChunkType.surface_height(along, lateral, generation_seed) + height_offset
	var facing := Basis(Vector3.UP, atan2(direction.x, direction.z))
	return Transform3D(facing, Vector3(point.x, y, point.z))


func _driving_lateral(along: float) -> float:
	var half: float = ChunkType.half_width_at(along, generation_seed)
	var frac: float = arcade_settings.player_lane_fraction if arcade_settings != null else 0.50
	return half * frac


func _fall_limit_y() -> float:
	var here: float = ChunkType.surface_height(_last_along, 0.0, generation_seed)
	return here - spawn_layout.car_fall_depth


# ----------------------------------------------- контракт для машины


func surface_contact(
	point: Vector3, grass: bool, load_ratio: float, slip: float, speed: float, delta: float
) -> Dictionary:
	var kind: String = surface_kind_at(point, grass)
	var result: Dictionary = _surface.sample(point, kind, _weather_wetness())
	result["kind"] = kind
	_surface.imprint(point, kind, load_ratio, slip, speed, delta)
	return result


func surface_kind_at(world_point: Vector3, grass: bool = false) -> String:
	var on_road: bool = _on_surface(world_point)
	return _surface.surface_kind(track.surface_name, grass or not on_road, _weather_snow_cover())


func _on_surface(world_point: Vector3) -> bool:
	if world_point.distance_to(_query_point) > 2.0:
		var near: Vector2 = network.nearest(world_point.x, world_point.z, _last_along)
		var offset: Vector3 = world_point - network.point_at(near.y)
		var direction: Vector3 = network.direction_at(near.y)
		_query_half = ChunkType.half_width_at(near.y, generation_seed) + ChunkType.SHOULDER
		_lateral_cache = absf(Vector3(direction.z, 0.0, -direction.x).dot(offset))
		_query_point = world_point
	return _lateral_cache <= _query_half


func live_surface_grip(_world_point: Vector3) -> float:
	return 1.0


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
