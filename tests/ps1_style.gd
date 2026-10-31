# godot --headless --path . --script res://tests/ps1_style.gd
# Контракты PS1-стиля, погоды, фильтрации материалов и отключения эффекта.
extends SceneTree

const Config = preload("res://data/rally_game_config.tres")
const Forest = preload("res://data/tracks/stage_forest.tres")
const Fog = preload("res://data/weather/weather_fog.tres")
const Rain = preload("res://data/weather/weather_rain.tres")
const Stage = preload("res://scripts/rally_stage.gd")
const Ps1 = preload("res://scripts/ps1_materials.gd")
const ScreenShader = preload("res://shaders/speed_fx.gdshader")
const GroundShader = preload("res://shaders/forest_ground.gdshader")
const RoadShader = preload("res://shaders/gravel_road.gdshader")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)


func _has_uniform(shader: Shader, name: String) -> bool:
	for entry in shader.get_shader_uniform_list():
		if entry.name == name:
			return true
	return false


func _run() -> void:
	for i in range(Config.track_count()):
		var configured_track = Config.get_track(i)
		_check(configured_track != null and configured_track.ps1_style, "PS1-стиль должен быть включён на трассе %d" % i)
	_check_shaders_and_palette()
	_check_fog_and_ground()
	_check_effect_order()
	_check_material_copies()
	if failures.is_empty():
		print("PASS: PS1-палитра, единый туман, погода и безопасные копии материалов")
		quit(0)
	else:
		printerr("FAIL: PS1-стиль: %d проблем(ы)" % failures.size())
		quit(1)


func _check_shaders_and_palette() -> void:
	for name in ["retro_strength", "resolution_y", "color_levels", "dither_strength", "speed_intensity"]:
		_check(_has_uniform(ScreenShader, name), "экранный шейдер должен иметь uniform %s" % name)
	for shader in [GroundShader, RoadShader]:
		_check(_has_uniform(shader, "vertex_snap"), "земля и дорога должны поддерживать сетку вершин")
		_check(_has_uniform(shader, "ps1_textures"), "земля и дорога должны переключать фильтрацию")
	var material := ShaderMaterial.new()
	material.shader = ScreenShader
	Ps1.configure_post_effect(material, true, 1.0, 270.0, 5, true)
	_check(is_equal_approx(float(material.get_shader_parameter("retro_strength")), 1.0), "стиль должен быть заметным по умолчанию")
	_check(is_equal_approx(float(material.get_shader_parameter("color_levels")), 31.0), "5 бит дают 31 ступень на канал")
	_check(is_equal_approx(float(material.get_shader_parameter("dither_strength")), 1.0), "дизер должен быть включён")
	Ps1.configure_post_effect(material, true, 0.5, 360.0, 0, false)
	_check(is_equal_approx(float(material.get_shader_parameter("retro_strength")), 0.5), "сила стиля должна настраиваться")
	_check(is_zero_approx(float(material.get_shader_parameter("color_levels"))), "0 бит отключает постеризацию")
	_check(is_zero_approx(float(material.get_shader_parameter("dither_strength"))), "дизер можно отключить")
	Ps1.configure_post_effect(material, false, 1.0, 270.0, 5, true)
	_check(is_zero_approx(float(material.get_shader_parameter("retro_strength"))), "ps1_style=false отключает экранный PS1-эффект")
	_check(is_zero_approx(float(material.get_shader_parameter("color_levels"))), "отключённый стиль не ограничивает палитру")


func _check_fog_and_ground() -> void:
	var stage = Stage.new()
	var environment := WorldEnvironment.new()
	stage.world_environment = environment
	stage.track = Forest.duplicate()
	stage._configure_world()
	var env: Environment = environment.environment
	_check(env.fog_enabled and env.fog_mode == Environment.FOG_MODE_DEPTH, "PS1-туман должен охватывать весь 3D-мир")
	_check(is_equal_approx(env.fog_density, 1.0), "depth-туман должен полностью скрывать дальний горизонт")
	_check(is_equal_approx(env.fog_depth_begin, stage.track.fog_near), "начало тумана должно браться из трассы")
	_check(is_equal_approx(env.fog_depth_end, stage.track.fog_far), "конец тумана должен браться из трассы")
	_check(env.volumetric_fog_enabled, "лучи фар не должны пропадать в PS1-режиме")
	var material: ShaderMaterial = stage._make_ground_material()
	_check(bool(material.get_shader_parameter("ps1_textures")), "земля должна использовать point-фильтрацию")
	_check(float(material.get_shader_parameter("flat_shading")) == 1.0, "фасетное освещение земли должно быть включено")
	_check(is_equal_approx(float(material.get_shader_parameter("vertex_snap")), stage.retro_vertex_snap), "сетка вершин должна настраиваться")

	stage.weather = Fog
	stage._configure_world()
	env = environment.environment
	_check(is_equal_approx(env.fog_depth_begin, stage.track.fog_near * Fog.visibility_scale), "туманная погода должна приближать начало тумана")
	_check(is_equal_approx(env.fog_depth_end, stage.track.fog_far * Fog.visibility_scale), "туманная погода должна приближать горизонт")
	_check(env.fog_depth_end > env.fog_depth_begin, "границы тумана не должны совпадать")
	_check(env.fog_light_color.is_equal_approx(stage._effective_fog_color()), "цвет тумана должен учитывать погоду")
	stage.weather = Rain
	material = stage._make_ground_material()
	_check(is_equal_approx(float(material.get_shader_parameter("wetness")), Rain.wetness), "мокрость земли должна сохраниться")

	stage.track.ps1_style = false
	stage._configure_world()
	env = environment.environment
	material = stage._make_ground_material()
	_check(env.fog_mode == Environment.FOG_MODE_EXPONENTIAL, "без PS1 должен вернуться обычный туман")
	_check(not bool(material.get_shader_parameter("ps1_textures")), "без PS1 должна вернуться гладкая фильтрация")
	_check(is_zero_approx(float(material.get_shader_parameter("flat_shading"))), "без PS1 фасетное освещение выключено")
	_check(is_zero_approx(float(material.get_shader_parameter("vertex_snap"))), "без PS1 вершины не должны сдвигаться")
	stage.free()
	environment.free()


func _check_effect_order() -> void:
	var stage = Stage.new()
	var hud := CanvasLayer.new()
	var ui := Control.new()
	ui.name = "RallyHUD"
	hud.add_child(ui)
	stage.hud = hud
	stage.track = Forest.duplicate()
	stage.track.enable_speed_fx = false
	stage.weather = Rain
	stage._setup_world_effects()
	var weather_rect := hud.get_node_or_null("WeatherMotionRect") as ColorRect
	var effect_rect := hud.get_node_or_null("SpeedShaderRect") as ColorRect
	_check(weather_rect != null and effect_rect != null, "дождь и экранный эффект должны создаваться")
	if weather_rect != null and effect_rect != null:
		_check(weather_rect.get_index() < effect_rect.get_index() and effect_rect.get_index() < ui.get_index(), "осадки должны быть под PS1-эффектом, HUD — над ним")
		_check(weather_rect.mouse_filter == Control.MOUSE_FILTER_IGNORE and effect_rect.mouse_filter == Control.MOUSE_FILTER_IGNORE, "эффекты не должны перехватывать мышь")
		_check(is_equal_approx(float(stage.speed_fx_material.get_shader_parameter("retro_strength")), 1.0), "выключение скорости не должно выключать PS1")
	stage.free()
	hud.free()


func _check_material_copies() -> void:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var original := StandardMaterial3D.new()
	original.albedo_texture = texture
	original.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var mesh := BoxMesh.new()
	mesh.material = original
	var root_node := Node3D.new()
	var first := MeshInstance3D.new()
	var second := MeshInstance3D.new()
	first.mesh = mesh
	second.mesh = mesh
	root_node.add_child(first)
	root_node.add_child(second)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = 1
	var multi_instance := MultiMeshInstance3D.new()
	multi_instance.multimesh = multi
	root_node.add_child(multi_instance)
	var shader_override := ShaderMaterial.new()
	shader_override.shader = GroundShader
	var custom := MeshInstance3D.new()
	custom.mesh = mesh
	custom.material_override = shader_override
	root_node.add_child(custom)

	Ps1.apply_nearest(root_node)
	var first_material := first.get_surface_override_material(0) as BaseMaterial3D
	var second_material := second.get_surface_override_material(0) as BaseMaterial3D
	_check(first_material != null and first_material != original, "ресурс оригинального материала нельзя менять")
	if first_material != null:
		_check(first_material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS, "копия должна использовать ближайший тексель и mipmaps")
	_check(first_material == second_material and multi_instance.material_override == first_material, "одинаковые материалы должны делить одну копию")
	_check(original.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "исходная фильтрация должна сохраниться")
	_check(custom.material_override == shader_override, "пользовательские шейдеры нельзя заменять")
	root_node.free()
