# godot --headless --path . --script res://tests/surface_effects.gd
extends SceneTree

const Effects = preload("res://scripts/surface_effects.gd")
const FxProfile = preload("res://scripts/data/rally_fx_profile.gd")
const Stage = preload("res://scripts/rally_stage.gd")
const Track = preload("res://scripts/data/rally_track_config.gd")
const RouteSection = preload("res://scripts/data/rally_route_section.gd")
const Network = preload("res://scripts/road_network.gd")
var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var effects = Effects.new()
	effects.fx = ResourceLoader.load("res://data/stage/default_fx_profile.tres") as FxProfile
	check(
		effects.fx != null and effects.fx.surface_fx_profiles.size() == 5,
		"пять типов покрытия имеют отдельные профили в ресурсе"
	)
	check(effects.amounts == Vector4.ZERO, "новая машина чистая")
	check(
		effects.profile_for_kind("gravel").kind_name() == "gravel",
		"у гравия отдельный профиль эффектов"
	)
	check(
		effects.profile_for_kind("mud").kind_name() == "mud", "у грязи отдельный профиль эффектов"
	)
	check(
		effects.profile_for_kind("grass").kind_name() == "grass",
		"у травы отдельный профиль эффектов"
	)
	check(
		effects.profile_for_kind("snow").kind_name() == "snow", "у снега отдельный профиль эффектов"
	)
	check(
		effects.profile_for_kind("asphalt").kind_name() == "asphalt",
		"у асфальта отдельный профиль эффектов"
	)
	check(
		effects.profile_for_kind("gravel").dry_color != effects.profile_for_kind("mud").dry_color,
		"покрытия отличаются цветом и характером частиц"
	)
	check(
		effects.effect_level_for("asphalt", 80.0, 0.0, 0.0) == 0,
		"сухой асфальт не пылит при обычном движении"
	)
	check(
		effects.effect_level_for("asphalt", 80.0, 0.0, 1.0) == 3,
		"мокрый асфальт даёт сильный водяной шлейф на скорости"
	)
	check(
		effects.effect_level_for("gravel", 25.0, 0.0, 0.0) == 1,
		"гравий имеет лёгкий уровень пыли"
	)
	check(
		effects.effect_level_for("gravel", 45.0, 0.0, 0.0) == 2,
		"гравий имеет средний уровень пыли"
	)
	check(
		effects.effect_level_for("gravel", 45.0, 1.0, 0.0) == 3,
		"сильная пробуксовка поднимает пыль до третьего уровня"
	)
	for kind in ["gravel", "mud", "grass", "snow", "asphalt"]:
		var profile := effects.profile_for_kind(kind)
		var low_slip: float = lerpf(profile.slip_start, profile.slip_full, 0.3)
		var medium_slip: float = lerpf(profile.slip_start, profile.slip_full, 0.6)
		check(profile.level_for(0.0, low_slip, 0.0) == 1, "первый уровень доступен для " + kind)
		check(profile.level_for(0.0, medium_slip, 0.0) == 2, "второй уровень доступен для " + kind)
		check(profile.level_for(0.0, profile.slip_full, 0.0) == 3, "третий уровень доступен для " + kind)
	effects.accumulate(0, "asphalt", 1.0, 20.0, 1.0, 10.0)
	check(effects.amounts == Vector4.ZERO, "чистый асфальт не создаёт грязь")
	effects.accumulate(0, "mud", 1.0, 0.0, 1.0, 10.0)
	check(effects.amounts == Vector4.ZERO, "стоящая машина не пачкается сама")
	effects.accumulate(0, "mud", 1.0, 12.0, 1.0, 1.0)
	check(effects.amounts.x > 0.0 and effects.damp.x > 0.0, "мокрый грунт даёт налёт")
	check(effects.amounts.y == 0.0 and effects.amounts.z == 0.0 and effects.amounts.w == 0.0, "загрязняется только зона активного колеса")
	effects.accumulate(1, "gravel", 0.0, 12.0, 0.0, 1.0)
	check(effects.amounts.y > 0.0 and effects.amounts.y < effects.amounts.x, "сухая пыль накапливается медленнее грязи")
	check(effects.damp.y == 0.0, "сухая пыль не становится мокрой")
	effects.accumulate(2, "mud", 1.0, 100.0, 100.0, 10000.0)
	check(effects.amounts.z == 1.0 and effects.damp.z == 1.0, "насыщение ограничено")
	var previous_dirt: float = effects.amounts.x
	var previous_damp: float = effects.damp.x
	effects.update_weather(1.0, 0.0, 10.0)
	check(effects.damp.x > previous_damp and effects.amounts.x < previous_dirt, "дождь увлажняет и постепенно смывает грязь даже без движения")
	previous_damp = effects.damp.x
	effects.update_weather(0.0, 0.0, 10.0)
	check(effects.damp.x < previous_damp, "без дождя налёт высыхает")
	var dry_amount: Vector4 = effects.amounts
	effects.update_weather(0.0, 1.0, 10.0)
	check(effects.snow_amounts.x > 0.0 and effects.amounts == dry_amount, "снег накапливается поверх грязи, не смывая её")
	var snow_before: float = effects.snow_amounts.z
	effects.accumulate(2, "snow", 0.0, 12.0, 1.0, 1.0)
	check(effects.snow_amounts.z > snow_before and effects.amounts == dry_amount, "снег из-под колёс оставляет снег, а не грязь")
	snow_before = effects.snow_amounts.x
	effects.update_weather(1.0, 0.0, 1.0)
	check(effects.snow_amounts.x < snow_before, "дождь постепенно убирает снежный налёт")
	effects.update_weather(0.0, 0.0, 1000.0)
	check(effects.damp == Vector4.ZERO and effects.snow_amounts == Vector4.ZERO, "в сухую погоду налёт высыхает и снег постепенно сходит")
	var car := Node3D.new()
	var model := Node3D.new()
	model.name = "low poly lance evo"
	car.add_child(model)
	var body := MeshInstance3D.new()
	body.name = "Mitsubishi_Body"
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color.RED
	body.material_override = paint
	model.add_child(body)
	effects.install(car)
	var pattern_seed: Vector3 = effects._material.get_shader_parameter("pattern_seed")
	check(
		pattern_seed != Vector3.ZERO, "процедурный рисунок получает случайный стабильный сид"
	)
	var other_effects = Effects.new()
	other_effects.fx = effects.fx
	var other_car := Node3D.new()
	other_effects.install(other_car)
	var other_seed: Vector3 = other_effects._material.get_shader_parameter("pattern_seed")
	check(pattern_seed != other_seed, "у разных машин разные варианты рисунка грязи")
	other_effects.clear()
	other_car.free()
	other_effects.free()
	check(body.material_overlay != null, "грязь — отдельный слой на кузове")
	check(body.material_override == paint and paint.albedo_color == Color.RED, "исходная краска не меняется")
	check(effects._sprays.size() == 4, "каждое колесо имеет собственный выброс грунта")
	var soil_mesh := effects._sprays[0].draw_pass_1 as SphereMesh
	check((soil_mesh.material as StandardMaterial3D).vertex_color_use_as_albedo, "частицы используют цвет снега и грязи")
	root.add_child(car)
	effects.snow_amounts = Vector4.ONE * 0.3
	effects.update(car, [], "gravel", 1.0, 0.0, 1.0, 1.0, 0.0)
	check(effects.damp.x > 0.0, "осадки обновляют налёт даже без контакта с дорогой")
	check(effects.snow_amounts.x > 0.0 and effects._material.get_shader_parameter("snow_amount") == effects.snow_amounts, "снежный налёт передаётся в шейдер")
	var stage = Stage.new()
	var track = Track.new()
	track.surface_name = "Гравий"
	var curve := Curve3D.new()
	curve.add_point(Vector3(0, 0, 0))
	curve.add_point(Vector3(0, 0, 100))
	var asphalt_section = RouteSection.new()
	asphalt_section.start_distance = 0.0
	asphalt_section.surface_name = "Асфальт"
	var mud_section = RouteSection.new()
	mud_section.start_distance = 40.0
	mud_section.surface_name = "Грязь"
	track.route_sections.append(asphalt_section)
	track.route_sections.append(mud_section)
	stage.track = track
	stage.network = Network.build_sparse(curve)
	check(
		stage.surface_kind_at(Vector3(0, 0, 20)) == "asphalt",
		"эффект определяется по асфальтовому участку под колесом"
	)
	check(
		stage.surface_kind_at(Vector3(0, 0, 80)) == "mud",
		"эффект переключается на грязь внутри смешанной трассы"
	)
	stage.free()
	effects.clear()
	check(effects.amounts == Vector4.ZERO and effects.damp == Vector4.ZERO and effects.snow_amounts == Vector4.ZERO, "сброс загрязнения и снега")
	car.free()
	effects.free()
	if failures == 0:
		print("PASS: профили покрытий, три уровня, случайная грязь, дождь и снег")
	quit(0 if failures == 0 else 1)
