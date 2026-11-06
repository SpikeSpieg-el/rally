# godot --headless --path . --script res://tests/scene_effects.gd
## Контракты сценических эффектов: пресеты, локальные материалы, миграция,
## независимость дождя/снега и отсутствие скрытого пересоздания фильтра.
extends SceneTree

const EffectsScene = preload("res://scenes/effects/visual_effects.tscn")
const ScreenScene = preload("res://scenes/effects/retro_screen.tscn")
const Stage = preload("res://scripts/rally_stage.gd")
const Settings = preload("res://scripts/data/rally_stage_settings.gd")
const Forest = preload("res://data/tracks/stage_forest.tres")
const Rain = preload("res://data/weather/weather_rain.tres")
const Snow = preload("res://data/weather/weather_snow.tres")
const Clear = preload("res://data/weather/weather_clear.tres")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _run() -> void:
	var root := Node.new()
	var effects := EffectsScene.instantiate() as RallyVisualEffects
	root.add_child(effects)
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	root.add_child(hud)
	var screen := ScreenScene.instantiate() as RallyScreenLook
	screen.name = "SpeedShaderRect"
	hud.add_child(screen)
	_check(effects.screen() == screen, "путь к экранному эффекту ведёт на настоящий узел под HUD")
	_check(effects.speed() != null and effects.rain() != null and effects.snow() != null and effects.surfaces() != null, "эффекты являются отдельными узлами сцены")
	_check_presets(effects, screen)
	_check_precipitation(effects)
	_check_materials(effects)
	_check_stage_integration(effects)
	_check_migration(effects)
	root.free()
	if failures.is_empty():
		print("PASS: сценические эффекты, пресеты, локальные материалы и миграция")
		quit(0)
	else:
		printerr("FAIL: сценические эффекты: %d проблем(ы)" % failures.size())
		quit(1)


func _check_presets(effects: RallyVisualEffects, screen: RallyScreenLook) -> void:
	screen.look = RallyScreenLook.Look.CLASSIC_PS1
	_check(screen.pixel_height == 270 and screen.palette_bits == 5, "классический PS1 имеет понятные фиксированные значения")
	screen.look = RallyScreenLook.Look.SOFT_PS1
	_check(screen.pixel_height == 360 and screen.palette_bits == 6, "мягкий PS1 реально меняет пиксель и палитру")
	screen.look = RallyScreenLook.Look.CUSTOM
	screen.pixel_height = 300
	screen._refresh()
	_check(screen.pixel_height == 300, "обновление не затирает пользовательский вариант")
	effects.speed().feel = RallySpeedFeel.Feel.COMFORT
	_check(is_equal_approx(effects.speed().intensity_for(60.0, true), 0.0), "комфортный эффект молчит на малой скорости")
	_check(effects.speed().intensity_for(220.0, true) > 0.5, "комфортный эффект появляется на высокой скорости")
	_check(is_zero_approx(effects.speed().intensity_for(220.0, false)), "запрет трассы выключает эффект скорости")
	effects.configure_screen(Forest)
	screen.set_preview_speed(200.0)
	var mat := screen.material as ShaderMaterial
	_check(float(mat.get_shader_parameter("speed_intensity")) > 0.0, "скорость доходит до экранного материала")
	screen.set_compare_original(true)
	_check(is_zero_approx(float(mat.get_shader_parameter("retro_strength"))) and is_zero_approx(float(mat.get_shader_parameter("speed_intensity"))), "сравнение показывает оригинал без экранных эффектов")
	screen.set_compare_original(false)
	var other := ScreenScene.instantiate() as RallyScreenLook
	_check(other.material != screen.material, "материал экрана локален для экземпляра сцены")
	other.free()


func _check_precipitation(effects: RallyVisualEffects) -> void:
	var rain := effects.make_weather_particles(Rain)
	var snow := effects.make_weather_particles(Snow)
	_check(rain != null and snow != null, "дождь и снег создаются из отдельных сцен")
	_check(rain.kind == RallyPrecipitationEffect.Kind.RAIN and snow.kind == RallyPrecipitationEffect.Kind.SNOW, "тип осадков хранится в узле")
	_check(rain.process_material != effects.rain().process_material, "заезд не меняет материал шаблона дождя")
	_check(not rain.local_coords and not rain.emitting and rain.process_mode == Node.PROCESS_MODE_PAUSABLE, "мировые координаты, пауза и порядок запуска сохранены")
	_check(snow.lifetime > rain.lifetime, "снег живёт дольше дождя")
	_check(effects.make_weather_particles(Clear) == null, "ясная погода не создаёт частицы")
	effects.rain().enabled = false
	_check(effects.make_weather_particles(Rain) == null, "дождь можно выключить независимо от снега")
	effects.rain().enabled = true
	var anchor := effects.anchor_for(Vector3.ZERO, Vector3(100, 0, -100))
	_check(anchor.y == 11.0 and anchor.x > 0.0 and anchor.z < 0.0, "область рождения следует скорости машины")
	rain.free()
	snow.free()


func _check_materials(effects: RallyVisualEffects) -> void:
	var surfaces := effects.surfaces()
	surfaces.look = RallySurfaceLooks.Look.SOFT
	_check(is_equal_approx(float(surfaces.road_material.get_shader_parameter("detail_strength")), 0.08), "пресет поверхностей меняет настоящий материал")
	surfaces.look = RallySurfaceLooks.Look.CUSTOM
	surfaces.road_material.set_shader_parameter("wet_darken", 0.31)
	var stage := Stage.new()
	stage.fx_nodes = effects
	stage.settings = Settings.new()
	stage.track = Forest.duplicate()
	stage.weather = Rain
	stage._sync_visual_settings()
	var ground := stage._make_ground_material()
	_check(ground == surfaces.ground_material, "этап использует материал земли из сцены")
	_check(is_equal_approx(float(ground.get_shader_parameter("wetness")), Rain.wetness), "погода применяется поверх сценического материала")
	_check(is_equal_approx(float(surfaces.road_material.get_shader_parameter("wet_darken")), 0.31), "художественный uniform не затирается сборкой")
	stage.free()


## Этап берёт эффекты из сцены: не создаёт свои копии узлов и материалов.
func _check_stage_integration(effects: RallyVisualEffects) -> void:
	var stage := Stage.new()
	stage.fx_nodes = effects
	stage.settings = Settings.new()
	stage.track = Forest.duplicate()
	stage.weather = Rain
	var car_position := Vector3.ZERO
	var velocity := Vector3(100, 0, -100)
	_check(stage._anchor_for(car_position, velocity) == effects.anchor_for(car_position, velocity),
		"этап спрашивает область осадков у сцены эффектов")
	_check(effects.rain() != null and effects.snow() != null and effects.screen() != null,
		"узлы эффектов остаются на месте после запроса этапа")
	_check(effects.surfaces().ground_material != null and effects.surfaces().road_material != null,
		"материалы земли и полотна живут в сцене эффектов")
	stage.free()


func _check_migration(effects: RallyVisualEffects) -> void:
	var legacy := Settings.new()
	legacy.retro_resolution_height = 360
	legacy.retro_style_strength = 0.5
	legacy.speed_fx_start_kmh = 80.0
	legacy.rain_amount_max = 3000
	legacy.precipitation_density = 0.5
	effects.adopt_from_settings(legacy)
	_check(effects.screen().pixel_height == 360 and is_equal_approx(effects.screen().strength, 0.5), "старый ретро-ресурс переносится в узел экрана")
	_check(is_equal_approx(effects.speed().start_kmh, 80.0), "старые пороги скорости переносятся без угадывания")
	_check(effects.rain().amount_max == 3000 and is_equal_approx(effects.rain().density, 0.5), "старые осадки переносятся в сцену дождя")
	var mirror := Settings.new()
	effects.sync_to_settings(mirror)
	_check(mirror.retro_resolution_height == 360 and mirror.rain_amount_max == 3000, "старый ресурс остаётся совместимым зеркалом узлов")
