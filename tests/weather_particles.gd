# godot --headless --path . --script res://tests/weather_particles.gd
extends SceneTree

const Stage = preload("res://scripts/rally_stage.gd")
const Car = preload("res://scripts/rally_car.gd")
const Rain = preload("res://data/weather/weather_rain.tres")
const Snow = preload("res://data/weather/weather_snow.tres")
var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var stage = Stage.new()
	stage.weather = Rain
	check(is_equal_approx(stage._precipitation_levels().x, Rain.precipitation_intensity), "этап передаёт машине именно интенсивность дождя")
	var wet_but_dry = Rain.duplicate()
	wet_but_dry.precipitation = 0
	stage.weather = wet_but_dry
	check(stage._precipitation_levels() == Vector2.ZERO, "мокрая дорога без осадков не считается дождём")
	stage.weather = Rain
	var rain: GPUParticles3D = stage._make_precipitation_particles()
	var rain_quad := rain.draw_pass_1 as QuadMesh
	var rain_material := rain_quad.material as StandardMaterial3D
	check(not rain.local_coords and not rain.emitting, "капли рождаются в мировых координатах после позиционирования")
	check(rain.process_mode == Node.PROCESS_MODE_PAUSABLE, "осадки останавливаются на паузе")
	check(rain_material.billboard_mode == BaseMaterial3D.BILLBOARD_FIXED_Y, "дождь вертикален относительно мира, а не экрана")
	check(rain_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and rain_material.albedo_color.a < 0.5, "капли полупрозрачные")
	check(rain_quad.size.x < 0.03 and rain_quad.size.y > rain_quad.size.x, "капли — тонкие полоски")
	var anchor: Vector3 = Stage.precipitation_anchor(Vector3.ZERO, Vector3(100, 0, -100))
	check(anchor.x > 0.0 and anchor.z < 0.0 and anchor.y == 11.0, "область рождения смещается по реальной скорости, в том числе при заносе")
	check(anchor.distance_to(Vector3(0, 11, 0)) < 24.0, "смещение ограничено и камера остаётся внутри области осадков")
	check(Stage.precipitation_anchor(Vector3(0.5, 0, 0.5), Vector3.ZERO) == Vector3(0, 11, 0), "небольшие перемещения не двигают источник")
	var baseline_amount: int = rain.amount
	stage.precipitation_density = 0.5
	var sparse: GPUParticles3D = stage._make_precipitation_particles()
	check(sparse.amount < baseline_amount, "плотность осадков настраивается")
	stage.weather = Snow
	check(is_equal_approx(stage._precipitation_levels().y, Snow.precipitation_intensity) and stage._precipitation_levels().x == 0.0, "этап передаёт снег отдельно от дождя")
	var snow: GPUParticles3D = stage._make_precipitation_particles()
	check(not snow.local_coords and snow.lifetime > rain.lifetime, "снег тоже остаётся в мире и падает медленнее")
	var car = Car.new()
	car.set_precipitation(Rain.precipitation_intensity, 0.0)
	check(is_equal_approx(car.precipitation_rain, Rain.precipitation_intensity) and car.precipitation_snow == 0.0, "интенсивности осадков передаются отдельно от мокроты дороги")
	car.set_precipitation(0.0, Snow.precipitation_intensity)
	check(car.precipitation_rain == 0.0 and is_equal_approx(car.precipitation_snow, Snow.precipitation_intensity), "режим осадков можно переключить на снег")
	rain.free()
	sparse.free()
	snow.free()
	car.free()
	stage.free()
	if failures == 0:
		print("PASS: мировые дождь и снег, область эмиссии и интенсивность погоды")
	quit(0 if failures == 0 else 1)
