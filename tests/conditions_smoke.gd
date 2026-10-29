# Проверка моторов, погоды, характера трассы и сохранения сида «Живой ленты».
# godot --headless --path . --fixed-fps 120 --script res://tests/conditions_smoke.gd
#
# Тест не рисует мир: он проверяет данные и те же функции, которыми этап
# накладывает условия, поэтому проходит и без GPU.
extends SceneTree

const ConfigResource = preload("res://data/rally_game_config.tres")
const TrackResource = preload("res://data/tracks/stage_forest.tres")
const StageScript = preload("res://scripts/rally_stage.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const WeatherType = preload("res://scripts/data/rally_weather_config.gd")
const ProfileType = preload("res://scripts/data/rally_track_profile.gd")
const SetupType = preload("res://scripts/data/rally_car_setup.gd")
const GameConfigType = preload("res://scripts/data/rally_game_config.gd")

var failures: Array[String] = []
## Типизированная ссылка на конфиг: у Resource без типа компилятор не знает
## методов weather_count()/profile_count().
var rally_config: GameConfigType = null


func _initialize() -> void:
	rally_config = ConfigResource as GameConfigType
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _run() -> void:
	_check_motors()
	_check_weather()
	_check_profiles()
	_check_seed_persistence()
	_check_stage_conditions()
	if failures.is_empty():
		print("PASS: моторы, погода, характер трассы и сохранение сида")
		quit(0)
	else:
		printerr("FAIL: %d проблем(ы)" % failures.size())
		quit(1)


func _check_motors() -> void:
	_check(rally_config.setup_count() == 3, "в конфиге должно быть три мотора")
	var stock: SetupType = rally_config.get_setup(0) as SetupType
	var group_a: SetupType = rally_config.get_setup(1) as SetupType
	var atmo: SetupType = rally_config.get_setup(2) as SetupType
	_check(stock != null and group_a != null and atmo != null, "все три сетапа должны читаться")
	if stock == null or group_a == null or atmo == null:
		return
	_check(not stock.engine_name.is_empty(), "у стока должно быть имя мотора")
	_check(not group_a.engine_name.is_empty(), "у Группы A должно быть имя мотора")
	_check(not atmo.engine_name.is_empty(), "у атмо должно быть имя мотора")
	_check(stock.max_torque < group_a.max_torque, "Группа A должна быть мощнее стока")
	_check(group_a.max_rpm < atmo.max_rpm, "атмо должно крутиться выше турбо")
	_check(atmo.drivetrain == SetupType.Drivetrain.RWD, "атмо-пресет — задний привод")
	_check(atmo.turbo == false, "у атмо не должно быть blow-off турбины")
	_check(stock.turbo and group_a.turbo, "у турбо-пресетов турбина включена")
	var stock_curve: Curve = stock.build_torque_curve()
	var atmo_curve: Curve = atmo.build_torque_curve()
	_check(stock_curve != null and atmo_curve != null, "кривые момента должны строиться")
	if stock_curve != null:
		_check(
			stock_curve.sample_baked(0.5) > stock_curve.sample_baked(1.0),
			"турбо-полка должна держать момент в середине"
		)
	if atmo_curve != null:
		_check(
			atmo_curve.sample_baked(0.95) > atmo_curve.sample_baked(0.15),
			"атмо должно тянуть в верхах"
		)


func _check_weather() -> void:
	_check(rally_config.weather_count() >= 5, "должно быть несколько погодных пресетов")
	var seen_precipitation := false
	var seen_fog := false
	for i in range(rally_config.weather_count()):
		var preset: WeatherType = rally_config.get_weather(i) as WeatherType
		_check(preset != null, "погодный пресет %d должен читаться" % i)
		if preset == null:
			continue
		if preset.has_precipitation():
			seen_precipitation = true
		if preset.fog_density_add > 0.001 or preset.visibility_scale < 0.6:
			seen_fog = true
		_check(
			preset.grip_scale >= 0.2 and preset.grip_scale <= 1.5,
			"сцепление погоды в разумных пределах"
		)
	_check(seen_precipitation, "должен быть хотя бы один пресет с дождём/снегом")
	_check(seen_fog, "должен быть хотя бы один пресет с густым туманом")
	var default_preset: WeatherType = rally_config.get_weather(0) as WeatherType
	_check(
		default_preset != null and default_preset.id == "default",
		"первый пресет — «как на трассе»"
	)
	if default_preset != null:
		_check(
			is_equal_approx(default_preset.grip_scale, 1.0)
			and is_equal_approx(default_preset.fog_density_scale, 1.0),
			"пресет по умолчанию не должен менять трассу"
		)


func _check_profiles() -> void:
	_check(rally_config.profile_count() >= 3, "должно быть несколько характеров трассы")
	var asphalt: ProfileType = null
	var mud: ProfileType = null
	for i in range(rally_config.profile_count()):
		var preset: ProfileType = rally_config.get_profile(i) as ProfileType
		_check(preset != null, "профиль %d должен читаться" % i)
		if preset == null:
			continue
		if preset.id == "asphalt":
			asphalt = preset
		elif preset.id == "mud":
			mud = preset
	_check(asphalt != null and mud != null, "должны быть асфальт и грязь")
	if asphalt == null or mud == null:
		return
	var original_grip: float = TrackResource.grip_scale
	var original_width: float = TrackResource.road_half_width
	var copy = TrackResource.duplicate()
	asphalt.apply_to(copy)
	_check(copy.grip_scale > original_grip, "асфальт должен повышать сцепление")
	_check(copy.road_half_width > original_width, "асфальт должен делать полотно шире")
	_check(
		is_equal_approx(TrackResource.grip_scale, original_grip)
		and is_equal_approx(TrackResource.road_half_width, original_width),
		"исходный .tres трассы не должен меняться"
	)
	var copy2 = TrackResource.duplicate()
	mud.apply_to(copy2)
	_check(copy2.grip_scale < original_grip, "грязь должна снижать сцепление")


func _check_seed_persistence() -> void:
	var game = GameStateScript.new()
	game.records_path = "user://rally_test_conditions_records.cfg"
	game.conditions_path = "user://rally_test_conditions.cfg"
	root.add_child(game)
	var track: Resource = rally_config.get_track(3)
	_check(track != null and bool(track.get("procedural")), "четвёртая трасса — «Живая лента»")
	if track == null:
		game.queue_free()
		return
	game.remember_live_seed(String(track.get("id")), 424242)
	_check(game.get_saved_seed(String(track.get("id")), 0) == 424242, "сид должен сохраняться")
	game.apply_saved_seed(track)
	_check(int(track.get("generation_seed")) == 424242, "сохранённый сид должен применяться")
	var rerolled: int = game.reroll_live_seed(track)
	_check(rerolled != 424242, "перегенерация должна выдавать новый сид")
	_check(int(track.get("generation_seed")) == rerolled, "новый сид должен попасть в трассу")
	_check(game.get_saved_seed(String(track.get("id")), 0) == rerolled, "новый сид должен сохраниться")
	var key: String = game.record_key_for(track)
	_check(key.contains(str(rerolled)), "ключ рекорда должен учитывать сид")
	var rain_index: int = -1
	for i in range(rally_config.weather_count()):
		var preset = rally_config.get_weather(i)
		if preset != null and String(preset.id) == "rain":
			rain_index = i
	if rain_index >= 0:
		game.select_weather(rain_index)
		_check(
			game.record_key_for(track).contains("rain"),
			"погода должна попадать в ключ рекорда"
		)
	game.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://rally_test_conditions.cfg"))
	var records_path: String = ProjectSettings.globalize_path(
		"user://rally_test_conditions_records.cfg"
	)
	DirAccess.remove_absolute(records_path)


func _check_stage_conditions() -> void:
	var rain: WeatherType = null
	var snow: WeatherType = null
	var mud: ProfileType = null
	for i in range(rally_config.weather_count()):
		var preset: WeatherType = rally_config.get_weather(i) as WeatherType
		if preset != null and preset.id == "rain":
			rain = preset
		elif preset != null and preset.id == "snow":
			snow = preset
	for i in range(rally_config.profile_count()):
		var preset: ProfileType = rally_config.get_profile(i) as ProfileType
		if preset != null and preset.id == "mud":
			mud = preset
	_check(rain != null and snow != null and mud != null, "нужны пресеты дождя, снега и грязи")
	if rain == null or snow == null or mud == null:
		return

	var stage = StageScript.new()
	var environment_node := WorldEnvironment.new()
	var sun := DirectionalLight3D.new()
	stage.world_environment = environment_node
	stage.sun_light = sun

	var track_copy = TrackResource.duplicate()
	stage.track = track_copy
	stage.weather = snow
	stage.track_profile = mud
	stage._apply_conditions_to_track()
	_check(track_copy.grip_scale < TrackResource.grip_scale, "снег по грязи должен снижать сцепление")
	_check(track_copy.road_half_width < TrackResource.road_half_width, "грязь должна сужать полотно")

	stage.track = TrackResource.duplicate()
	stage.weather = rain
	stage._configure_world()
	var env: Environment = environment_node.environment
	_check(env != null, "окружение должно создаваться")
	if env != null:
		_check(env.fog_density > TrackResource.fog_density, "дождь должен сгущать туман")
		_check(
			not env.fog_light_color.is_equal_approx(TrackResource.fog_color),
			"дождь должен подмешивать свой цвет тумана"
		)
	_check(sun.light_energy < TrackResource.sun_energy, "дождь должен приглушать солнце")

	stage.free()
	environment_node.free()
	sun.free()
