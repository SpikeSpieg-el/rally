## Пыль, дым, комья и капли из-под каждого колеса + слои грязи на кузове.
##
## Поведение: у каждого колеса два живых источника частиц —
##   * мягкие клубы пыли/брызг (билборд-облачка, расширяются и растворяются);
##   * комья и капли (настоящая баллистика, падают на землю).
## Оба источника плавно меняют плотность от состояния колеса: смещение, пробуксовка,
## мокрота, занос, ручник и поворот руля. Никогда не «дёргаются» между ступенями.
##
## Все числа — поля RallyFxProfile / RallySurfaceFxProfile
## (data/stage/default_fx_profile.tres). Хотите сильнее — правьте профиль,
## а не этот файл.
extends Node

const DirtShader = preload("res://shaders/car_dirt.gdshader")
const SurfaceType = preload("res://scripts/road_surface.gd")
const FxProfileType = preload("res://scripts/data/rally_fx_profile.gd")
const SurfaceFxProfileType = preload("res://scripts/data/rally_surface_fx_profile.gd")
const DustFx = preload("res://scripts/effects/rally_dust_fx.gd")
const SURFACE_KINDS: Array[String] = ["gravel", "mud", "grass", "snow", "asphalt"]

## Профиль эффектов из инспектора. Пусто — значения по умолчанию ресурса.
@export var fx: FxProfileType = null

var amounts := Vector4.ZERO
var damp := Vector4.ZERO
var snow_amounts := Vector4.ZERO
var _material: ShaderMaterial
## Комья и капли (по одному источнику на колесо). Публичное имя сохранено ради тестов.
var _sprays: Array[GPUParticles3D] = []
## Клубы пыли/дыма над каждым колесом.
var _foams: Array[GPUParticles3D] = []
var _spray_kinds: Array[String] = ["", "", "", ""]
## Цвет и вид пятна, накопленного каждым колесом. Свои у гравия, грязи,
## травы и асфальта: колесо плавно переходит на цвет нового покрытия.
var _dirt_colors: Array[Color] = []
var _dirt_looks: Array[Vector4] = []
var _profiles: Dictionary = {}
var _surface = SurfaceType.new()
var _rng := RandomNumberGenerator.new()
var _update_timer := 0.0
var _foam_material: StandardMaterial3D
var _grit_material: StandardMaterial3D
## Машина, на которой установлены эффекты (нужна для пересборки профиля).
var _car: Node3D = null


## Поле профиля по имени. Параметр называется field, а не name: name — это
## свойство самого Node, и GDScript ругается на его затенение в каждом геттере.
func _p(field: String, fallback: float) -> float:
	return float(fx.get(field)) if fx != null else fallback


func _pi(field: String, fallback: int) -> int:
	return int(fx.get(field)) if fx != null else fallback


func _pb(field: String, fallback: bool) -> bool:
	return bool(fx.get(field)) if fx != null else fallback


func _pc(field: String, fallback: Color) -> Color:
	return fx.get(field) as Color if fx != null else fallback


func _pv(field: String, fallback: Vector3) -> Vector3:
	return fx.get(field) as Vector3 if fx != null else fallback


## Числовое поле машины без падений на тестовых заглушках.
func _car_float(car: Object, field: String, fallback: float) -> float:
	var value: Variant = car.get(field)
	return float(value) if value is float or value is int else fallback


func install(car: Node3D) -> void:
	_car = car
	_rng.seed = int(Time.get_ticks_usec()) ^ int(car.get_instance_id())
	_reset_dirt_look()
	_install_body_dirt(car)
	_foam_material = _make_foam_material()
	_grit_material = _make_grit_material()
	for i in range(4):
		var foam := _make_pool("WheelFoam%d" % i)
		foam.draw_pass_1 = _make_foam_mesh()
		foam.process_material = _make_foam_process()
		car.add_child(foam)
		_foams.append(foam)
		var grit := _make_pool("WheelGrit%d" % i)
		grit.draw_pass_1 = _make_grit_mesh()
		grit.process_material = _make_grit_process()
		car.add_child(grit)
		_sprays.append(grit)
	refresh_profile()


## Применить профиль к уже созданным эффектам — вызывается из install().
## Количество, размеры и материал меняются на месте; уже нанесённая грязь
## остаётся, меняются только цвета и густота слоя.
func refresh_profile() -> void:
	_load_surface_profiles()
	if _car == null or _foams.is_empty():
		return
	_foam_material = _make_foam_material()
	_grit_material = _make_grit_material()
	for i in range(4):
		var foam := _foams[i]
		var foam_mesh := foam.draw_pass_1 as QuadMesh
		if foam_mesh != null:
			foam_mesh.material = _foam_material
		var grit := _sprays[i]
		var grit_mesh := grit.draw_pass_1 as SphereMesh
		if grit_mesh != null:
			grit_mesh.material = _grit_material
		foam.fixed_fps = maxi(10, _pi("fx_physics_fps", 60))
		grit.fixed_fps = maxi(10, _pi("fx_physics_fps", 60))
		# Количество и размеры живут в пулах: пересобрать их под новый профиль
		# можно только зная покрытие, с которым колесо работало до правки.
		var kind: String = _spray_kinds[i]
		if not kind.is_empty():
			_configure_for_profile(i, profile_for_kind(kind))
	_apply_body_look()


## Цвета и густота слоя на кузове: их можно менять на ходу, геометрия не важна.
func _apply_body_look() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("dirt_color", _pc("dirt_color", Color(0.3, 0.22, 0.13)))
	_material.set_shader_parameter("snow_color", _pc("body_snow_color", Color(0.82, 0.86, 0.9)))
	_material.set_shader_parameter("dirt_coverage", _p("body_coverage", 1.35))
	_material.set_shader_parameter("edge_softness", _p("body_edge_softness", 0.85))
	_material.set_shader_parameter("dirt_strength", _p("body_dirt_buildup", 1.0))
	_material.set_shader_parameter("snow_strength", _p("body_snow_buildup", 1.0))
	_material.set_shader_parameter("body_alpha", _p("body_alpha", 0.92))
	_material.set_shader_parameter("body_spread", _p("body_spread", 1.0))


## Чистый кузов: каждое колесо начинает с общего цвета пыли из профиля.
func _reset_dirt_look() -> void:
	var color := _pc("dirt_color", Color(0.32, 0.235, 0.14))
	_dirt_colors.resize(4)
	_dirt_looks.resize(4)
	for i in range(4):
		_dirt_colors[i] = color
		_dirt_looks[i] = Vector4.ONE
	_write_dirt_look()


## Передать в шейдер цвет и вид пятна каждого колеса.
func _write_dirt_look() -> void:
	if _material == null or _dirt_colors.size() < 4 or _dirt_looks.size() < 4:
		return
	var colors := PackedVector3Array()
	var looks := PackedVector4Array()
	for i in range(4):
		var color: Color = _dirt_colors[i]
		colors.append(Vector3(color.r, color.g, color.b))
		looks.append(_dirt_looks[i])
	_material.set_shader_parameter("dirt_colors", colors)
	_material.set_shader_parameter("dirt_looks", looks)


## Скорость налипания конкретного покрытия: своё поле профиля, иначе общее
## gravel/mud/grass_dirt_rate. Асфальт по умолчанию не пачкает кузов.
func _body_dirt_rate(kind: String, profile: RallySurfaceFxProfile) -> float:
	if profile != null and profile.body_dirt_rate >= 0.0:
		return profile.body_dirt_rate
	match kind:
		"gravel":
			return _p("gravel_dirt_rate", 0.018)
		"mud":
			return _p("mud_dirt_rate", 0.045)
		"grass":
			return _p("grass_dirt_rate", 0.008)
		_:
			return 0.0


## Плавно перевести пятно колеса на цвет и характер нового покрытия.
## Чистое колесо сразу берёт цвет покрытия; уже грязное — по доле свежего
## налипания, поэтому гравийная пыль не перекрашивает налипшую грязь.
func _blend_dirt_look(
	index: int, profile: RallySurfaceFxProfile, work: float, before: float
) -> void:
	if profile == null or work <= 0.0:
		return
	if _dirt_colors.size() < 4 or _dirt_looks.size() < 4:
		_reset_dirt_look()
	var target_color: Color = profile.body_dirt_color
	var target_look := Vector4(
		profile.body_dirt_coverage,
		profile.body_dirt_spread,
		profile.body_dirt_alpha,
		0.0
	)
	var blend: float = (
		1.0 if before < 0.005 else clampf(work / maxf(before + work, 0.001), 0.0, 1.0)
	)
	_dirt_colors[index] = _dirt_colors[index].lerp(target_color, blend)
	_dirt_looks[index] = _dirt_looks[index].lerp(target_look, blend)
	_write_dirt_look()


## Процедурный слой поверх краски: пятна, брызги и потёки у каждого колеса.
func _install_body_dirt(car: Node3D) -> void:
	_material = ShaderMaterial.new()
	_material.shader = DirtShader
	_material.set_shader_parameter(
		"pattern_seed",
		Vector3(
			_rng.randf_range(-31.0, 31.0),
			_rng.randf_range(-31.0, 31.0),
			_rng.randf_range(-31.0, 31.0)
		)
	)
	_apply_body_look()
	# Матрица и массивы колёс нужны уже на первом кадре: без них шейдер
	# считает позиции по нулевому world_to_car, и грязь на миг «съезжает»
	# с кузова (или не видна вовсе, если update() ещё не вызывался).
	_material.set_shader_parameter("world_to_car", car.global_transform.affine_inverse())
	_material.set_shader_parameter("wheels", PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]))
	_material.set_shader_parameter("dirt_amount", Vector4.ZERO)
	_material.set_shader_parameter("damp_amount", Vector4.ZERO)
	_material.set_shader_parameter("snow_amount", Vector4.ZERO)
	_write_dirt_look()
	for mesh in _body_meshes(car):
		mesh.material_overlay = _material


## Кузовные меши обеих машин. Префиксы и исключения — поля профиля.
func _body_meshes(car: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var prefixes: Array = []
	var blocked: Array = []
	if fx != null:
		prefixes = fx.get("dirt_body_prefixes")
		blocked = fx.get("dirt_body_skip")
	for child in _all_meshes(car):
		var mesh_name := String(child.name)
		var matches := prefixes.is_empty()
		for prefix in prefixes:
			if mesh_name.begins_with(String(prefix)):
				matches = true
				break
		if matches and not _is_blocked_mesh(child, blocked, car):
			result.append(child)
	return result


## Диски, стёкла, фары и салон грязью не покрываем.
func _is_blocked_mesh(mesh: Node, blocked: Array, car: Node) -> bool:
	var node: Node = mesh
	while node != null and node != car:
		var part := String(node.name).to_lower()
		for word in blocked:
			if not String(word).is_empty() and part.contains(String(word)):
				return true
		node = node.get_parent()
	return false


func _all_meshes(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in root.get_children():
		if child is MeshInstance3D:
			result.append(child)
		result.append_array(_all_meshes(child))
	return result


func _make_foam_material() -> StandardMaterial3D:
	var material := DustFx.puff_material(DustFx.puff_texture(), not _pb("foam_lit", true))
	var sparkle := _pb("fx_sparkle_enabled", true) and _p("fx_sparkle_strength", 0.0) > 0.001
	var self_glow := _p("foam_emission", 0.0)
	var total_glow := (
		(_p("fx_sparkle_strength", 0.0) * _p("fx_sparkle_emission", 0.85) if sparkle else 0.0)
		+ self_glow
	)
	material.emission_enabled = total_glow > 0.001
	if material.emission_enabled:
		material.emission = _pc("fx_sparkle_color", Color(1.0, 0.86, 0.58))
		material.emission_energy_multiplier = total_glow
	material.vertex_color_is_srgb = false
	return material


func _make_grit_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = (
		BaseMaterial3D.SHADING_MODE_PER_PIXEL
		if _pb("grit_lit", true)
		else BaseMaterial3D.SHADING_MODE_UNSHADED
	)
	material.albedo_color = Color.WHITE
	material.vertex_color_use_as_albedo = true
	# В Godot 4 свойство называется metallic_specular: `specular` — это
	# команда материала шейдера, и запись в него из GDScript не проходит
	# (движок сыплет «remapped parameter not found: specular»).
	var gloss: float = clampf(_p("grit_specular", 0.35), 0.0, 0.9)
	material.roughness = 1.0 - gloss
	material.metallic_specular = clampf(gloss * 1.6, 0.0, 1.0)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var grit_glow: float = _p("grit_light_boost", 0.05) * 0.35
	material.emission_enabled = _pb("fx_sparkle_enabled", true) and grit_glow > 0.001
	if material.emission_enabled:
		material.emission = _pc("fx_sparkle_color", Color(1.0, 0.86, 0.58))
		material.emission_energy_multiplier = grit_glow
	return material


func _make_pool(pool_name: String) -> GPUParticles3D:
	var pool := GPUParticles3D.new()
	pool.name = pool_name
	pool.emitting = false
	pool.local_coords = false
	pool.speed_scale = 1.0
	pool.fixed_fps = maxi(10, _pi("fx_physics_fps", 60))
	pool.fract_delta = true
	pool.randomness = 0.45
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pool.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	pool.visibility_aabb = AABB(Vector3(-10, -6, -10), Vector3(20, 16, 20))
	# Клубы и комья никогда не должны пропадать на краю экрана: запасной размер
	# кулинг-бокса больше всего, что успевает улететь за жизнь частицы.
	pool.extra_cull_margin = 8.0
	return pool


func _make_foam_mesh() -> QuadMesh:
	var mesh := QuadMesh.new()
	var size := maxf(0.01, _p("foam_size", 0.18))
	mesh.size = Vector2(size, size) * 2.0
	mesh.material = _foam_material
	return mesh


func _make_grit_mesh() -> SphereMesh:
	var mesh := SphereMesh.new()
	var grain := maxf(0.001, _p("spray_grain_radius", 0.026))
	mesh.radius = grain
	mesh.height = maxf(grain * 1.2, _p("spray_grain_height", 0.062))
	mesh.radial_segments = maxi(3, _pi("spray_grain_segments", 3))
	mesh.rings = maxi(1, _pi("spray_grain_rings", 1))
	mesh.material = _grit_material
	return mesh


func _make_foam_process() -> ParticleProcessMaterial:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = maxf(0.01, _p("foam_size", 0.18)) * _p(
		"foam_emission_radius", 0.55
	)
	process.direction = _pv("foam_direction", Vector3(0.0, 0.42, -0.65))
	process.spread = clampf(_p("foam_spread", 42.0), 0.0, 180.0)
	process.flatness = clampf(_p("foam_flatness", 0.25), 0.0, 1.0)
	process.gravity = _pv("foam_gravity", Vector3(0.0, -0.75, 0.0))
	process.initial_velocity_min = _p("foam_speed_min", 0.75)
	process.initial_velocity_max = _p("foam_speed_max", 3.1)
	process.scale_min = _p("foam_scale_min", 0.55)
	process.scale_max = _p("foam_scale_max", 1.35)
	process.scale_curve = DustFx.growth_curve(_p("foam_growth", 2.3))
	process.angle_min = 0.0
	process.angle_max = 360.0
	process.color_ramp = DustFx.fade_ramp()
	process.turbulence_enabled = _p("foam_turbulence", 2.0) > 0.0
	process.turbulence_noise_strength = _p("foam_turbulence", 2.0)
	process.turbulence_noise_scale = _p("foam_turbulence_scale", 3.0)
	process.turbulence_influence_min = 0.06
	process.turbulence_influence_max = 0.22
	process.inherit_velocity_ratio = _p("inherit_velocity_ratio", 0.22)
	process.lifetime_randomness = _p("foam_lifetime_randomness", 0.42)
	process.damping_min = _p("foam_damping_min", 0.55)
	process.damping_max = maxf(_p("foam_damping_min", 0.55), _p("foam_damping_max", 1.25))
	var spin := _p("foam_spin", 48.0)
	process.angular_velocity_min = -spin
	process.angular_velocity_max = spin
	return process


func _make_grit_process() -> ParticleProcessMaterial:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.14
	process.direction = _pv("spray_direction", Vector3(0.0, 0.7, -1.0))
	process.spread = clampf(_p("grit_spread", 42.0), 0.0, 180.0)
	process.gravity = _pv("grit_gravity", Vector3(0.0, -13.5, 0.0))
	process.initial_velocity_min = _p("grit_speed_min", 1.5)
	process.initial_velocity_max = _p("grit_speed_max", 5.2)
	process.scale_min = _p("grit_scale_min", 0.55)
	process.scale_max = _p("grit_scale_max", 2.3)
	process.scale_curve = DustFx.debris_scale_curve()
	process.color_ramp = DustFx.debris_fade()
	if _pb("grit_use_variation", true):
		process.color_initial_ramp = DustFx.debris_color_variation()
	# Крупинки почти не наследуют скорость машины: иначе на трассе они
	# вылетают вперёд ровным лучом и читаются как выстрел, а не как грунт
	# из-под колеса.
	process.inherit_velocity_ratio = _p("inherit_velocity_ratio", 0.22) * 0.8
	process.lifetime_randomness = _p("grit_lifetime_randomness", 0.5)
	# Торможение о воздух: комья теряют скорость и падают, а не летят по прямой.
	process.damping_min = _p("grit_damping_min", 0.35)
	process.damping_max = maxf(_p("grit_damping_min", 0.35), _p("grit_damping_max", 1.05))
	process.angle_min = 0.0
	process.angle_max = 360.0
	var spin := _p("grit_spin", 260.0)
	process.angular_velocity_min = -spin
	process.angular_velocity_max = spin
	return process


func _load_surface_profiles() -> void:
	_profiles.clear()
	if fx != null:
		for entry in fx.surface_fx_profiles:
			var profile := entry as SurfaceFxProfileType
			if profile != null:
				_profiles[profile.kind_name()] = profile
	for kind in SURFACE_KINDS:
		if not _profiles.has(kind):
			_profiles[kind] = _fallback_profile(kind)


## Совместимые значения на случай старой/custom FX-ресурса без профилей покрытий.
func _fallback_profile(kind: String) -> RallySurfaceFxProfile:
	var profile := SurfaceFxProfileType.new() as RallySurfaceFxProfile
	match kind:
		"gravel":
			profile.kind = SurfaceFxProfileType.Kind.GRAVEL
			profile.dry_color = _pc("spray_dry_color", profile.dry_color)
			profile.wet_color = _pc("spray_wet_color", profile.wet_color)
		"mud":
			profile.kind = SurfaceFxProfileType.Kind.MUD
			profile.dry_color = Color(0.31, 0.22, 0.14, 0.82)
			profile.wet_color = Color(0.12, 0.075, 0.04, 0.94)
			profile.gravity_scale = Vector3(0.8, 1.0, 0.8)
			profile.amount_scale = 1.1
			profile.particle_scale = 1.3
			profile.grain_scale = 1.45
			profile.speed_weight = 0.62
			profile.wet_weight = 0.38
		"grass":
			profile.kind = SurfaceFxProfileType.Kind.GRASS
			profile.dry_color = Color(0.34, 0.31, 0.17, 0.68)
			profile.wet_color = Color(0.2, 0.18, 0.1, 0.78)
			profile.amount_scale = 0.62
			profile.lifetime_scale = 0.78
			profile.spread_scale = 1.3
			profile.velocity_scale = 0.82
			profile.particle_scale = 0.78
			profile.grain_scale = 0.72
			profile.speed_weight = 0.48
			profile.slip_weight = 0.78
		"snow":
			profile.kind = SurfaceFxProfileType.Kind.SNOW
			profile.dry_color = _pc("spray_snow_color", Color(0.9, 0.95, 1.0, 0.78))
			profile.wet_color = profile.dry_color
			profile.gravity_scale = Vector3(0.18, 0.1, 0.18)
			profile.direction = Vector3(0, 0.9, 1)
			profile.lifetime_scale = 1.55
			profile.spread_scale = 1.45
			profile.velocity_scale = 0.88
			profile.particle_scale = 1.25
			profile.grain_scale = 0.68
			profile.speed_weight = 0.65
			profile.slip_weight = 0.9
		"asphalt":
			profile.kind = SurfaceFxProfileType.Kind.ASPHALT
			profile.dry_color = Color(0.24, 0.27, 0.3, 0.36)
			profile.wet_color = Color(0.72, 0.82, 0.92, 0.62)
			profile.gravity_scale = Vector3(0.08, 0.035, 0.08)
			profile.direction = Vector3(0, 0.28, 1)
			profile.amount_scale = 0.68
			profile.lifetime_scale = 1.4
			profile.spread_scale = 1.55
			profile.velocity_scale = 0.62
			profile.particle_scale = 1.55
			profile.speed_weight = 0.0
			profile.slip_weight = 1.0
			profile.wet_weight = 0.92
			profile.speed_start_kmh = 10.0
			profile.speed_full_kmh = 88.0
			profile.slip_start = 0.2
			profile.slip_full = 0.72
	# Старые общие пороги используются только для запасных профилей.
	profile.speed_start_kmh = maxf(
		profile.speed_start_kmh, _p("spray_min_speed", 3.0) * 3.6
	)
	profile.slip_start = maxf(
		profile.slip_start, _p("spray_slip_threshold", profile.slip_start)
	)
	var wet_threshold: float = clampf(_p("spray_wet_threshold", 0.3), 0.01, 1.0)
	profile.wet_weight = maxf(
		profile.wet_weight, profile.level_1_threshold / wet_threshold
	)
	return profile


func profile_for_kind(kind: String) -> RallySurfaceFxProfile:
	if _profiles.is_empty():
		_load_surface_profiles()
	return _profiles.get(kind, _profiles.get("gravel")) as RallySurfaceFxProfile


func effect_level_for(kind: String, speed_kmh: float, slip: float, wetness: float) -> int:
	var profile := profile_for_kind(kind)
	return profile.level_for(speed_kmh, slip, wetness) if profile != null else 0


## Поверхность конкретного колеса с учётом участка трассы, а не только общего пресета.
func kind_for_wheel(wheel: Object, road_name: String, snow: float) -> String:
	var cached_kind: String = str(wheel.get("surface_kind"))
	if not cached_kind.is_empty():
		return cached_kind
	var collider := wheel.get("last_collider") as Node
	if collider == null:
		return ""
	var grass: bool = collider.is_in_group("Grass")
	if not grass and not collider.is_in_group("Dirt") and not collider.is_in_group("Road"):
		return ""
	var stage: Node = get_parent().get_parent() if get_parent() != null else null
	if stage != null and stage.has_method("surface_kind_at"):
		return str(stage.call("surface_kind_at", wheel.get("last_collision_point"), grass))
	return _surface.surface_kind(road_name, grass, snow)


func accumulate(
	index: int, kind: String, wetness: float, speed: float, slip: float, delta: float
) -> void:
	if index < 0 or index >= 4 or speed < _p("dirt_min_speed", 1.0) or delta <= 0.0:
		return
	if kind == "snow":
		var snow_work := (
			_p("snow_rate", 0.025)
			* clampf(_p("fx_intensity", 1.0), 0.0, 4.0)
			* clampf(speed / 12.0, 0.0, 2.0)
			* (1.0 + minf(maxf(slip, 0.0), 2.0))
			* delta
		)
		snow_amounts[index] = clampf(snow_amounts[index] + snow_work, 0.0, 1.0)
		return
	if kind.is_empty():
		return
	var profile := profile_for_kind(kind)
	var base_rate: float = _body_dirt_rate(kind, profile)
	if base_rate <= 0.0:
		return
	wetness = clampf(wetness, 0.0, 1.0)
	# fx_intensity — общая «громкость»: грязь налипает в том же ритме, что
	# растёт пыль и комья, иначе при сильных эффектах кузов остаётся чистым.
	var intensity := clampf(_p("fx_intensity", 1.0), 0.0, 4.0)
	var rate := (
		base_rate
		* lerpf(_p("damp_dry_scale", 0.35), _p("damp_wet_scale", 1.8), wetness)
		* intensity
	)
	var work := rate * clampf(speed / 12.0, 0.0, 2.0) * (1.0 + clampf(slip, 0.0, 2.0)) * delta
	var before: float = amounts[index]
	amounts[index] = clampf(before + work, 0.0, 1.0)
	damp[index] = clampf(damp[index] + work * wetness, 0.0, 1.0)
	_blend_dirt_look(index, profile, work, before)


## Осадки воздействуют на уже нанесённый налёт даже когда машина стоит.
## Влажность полотна сама по себе не означает, что сейчас идёт дождь.
func update_weather(rain: float, snowfall: float, delta: float) -> void:
	if delta <= 0.0:
		return
	rain = clampf(rain, 0.0, 1.0)
	snowfall = clampf(snowfall, 0.0, 1.0)
	var wet_gain: float = _p("rain_wet_gain", 0.08)
	var dry_loss: float = _p("rain_dry_loss", 0.012)
	var wash: float = _p("rain_wash", 0.035)
	var snow_gain: float = _p("snow_gain", 0.035)
	var snow_wash: float = _p("snow_wash_by_rain", 0.035)
	var snow_melt: float = _p("snow_melt", 0.004)
	for i in range(4):
		damp[i] = move_toward(damp[i], rain, delta * (wet_gain if rain > damp[i] else dry_loss))
		amounts[i] = maxf(0.0, amounts[i] - rain * wash * delta)
		var snow_delta: float = snowfall * snow_gain - rain * snow_wash
		if snowfall <= 0.0:
			snow_delta -= snow_melt
		snow_amounts[i] = clampf(snow_amounts[i] + snow_delta * delta, 0.0, 1.0)


func update(
	car: Node3D,
	wheels: Array,
	road_name: String,
	wetness: float,
	snow: float,
	delta: float,
	rain: float = 0.0,
	snowfall: float = 0.0
) -> void:
	if _material == null:
		return
	update_weather(rain, snowfall, delta)
	var positions := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	var spring_scale: float = _p("dirt_center_spring_scale", 0.65)
	var emit_count: int = mini(4, wheels.size())
	_update_timer += delta
	# Частицы считает GPU: состояние колеса достаточно пересчитывать реже кадра,
	# иначе на слабых машинах и в вебе тратится ЦП без видимой разницы.
	var refresh: bool = _update_timer >= 1.0 / maxf(1.0, _p("fx_update_hz", 30.0))
	# Накопление грязи идёт по времени, прошедшему с прошлого такта, а не по
	# `delta` текущего кадра: такт выпадает примерно раз в 4 физических шага
	# (120 Гц), и при `delta` кадра налёт рос в 4–8 раз медленнее заданного в
	# профиле (и менялся от FPS/тактов). Поэтому передаём накопленное время.
	var elapsed: float = _update_timer
	if refresh:
		_update_timer = 0.0
	var steer := _car_float(car, "steer_input", 0.0)
	var handbrake := _car_float(car, "handbrake_input", 0.0)
	for i in range(emit_count):
		var wheel = wheels[i]
		# Центры масок — на кузове, не на движущейся подвеске:
		# уже нанесённые пятна не сдвигаются на кочках.
		positions[i] = (
			car.to_local(wheel.global_position) + Vector3.DOWN * wheel.spring_length * spring_scale
		)
	# Слой грязи на кузове — раньше источников частиц и без раннего выхода:
	# иначе при отсутствии пулов (тесты, отключённые эффекты, машина без
	# частиц) грязь не обновлялась вовсе и кузов оставался чистым.
	_material.set_shader_parameter("world_to_car", car.global_transform.affine_inverse())
	_material.set_shader_parameter("wheels", positions)
	_material.set_shader_parameter("dirt_amount", amounts)
	_material.set_shader_parameter("damp_amount", damp)
	_material.set_shader_parameter("snow_amount", snow_amounts)
	if _foams.is_empty() or _sprays.is_empty():
		return
	if not refresh:
		return
	for i in range(4):
		if i < emit_count:
			_drive_wheel(car, wheels[i], i, road_name, wetness, snow, elapsed, steer, handbrake)
		else:
			# Колёс меньше четырёх (недонастроенная машина): лишние источники
			# гасим, иначе они висят с последней ненулевой плотностью.
			_stop_pools(i)


## Один такт источника частиц конкретного колеса.
func _drive_wheel(
	car: Node3D,
	wheel: Object,
	index: int,
	road_name: String,
	wetness: float,
	snow: float,
	elapsed: float,
	steer: float,
	handbrake: float
) -> void:
	if not _wheel_has_ground(wheel):
		_stop_pools(index)
		return
	var kind: String = kind_for_wheel(wheel, road_name, snow)
	var speed: float = Vector2(wheel.local_velocity.x, wheel.local_velocity.z).length()
	var slip: float = wheel.slip_vector.length()
	accumulate(index, kind, wetness, speed, slip, elapsed)
	var profile: RallySurfaceFxProfile = null
	if not kind.is_empty():
		profile = profile_for_kind(kind)
	var enabled: bool = (
		profile != null
		and profile.enabled
		and (fx == null or fx.surface_fx_enabled)
		and (speed >= _p("spray_min_speed", 3.0) * 0.5 or slip > maxf(0.55, profile.slip_start))
	)
	if kind == "asphalt" and wetness < 0.04 and profile != null and slip < profile.slip_start:
		enabled = false
	if not enabled:
		_stop_pools(index)
		return
	var activity: float = profile.activity_for(speed * 3.6, slip, wetness)
	activity = clampf(activity * _drama_boost(wheel, speed, steer, handbrake), 0.0, 1.0)
	if activity <= 0.001:
		_stop_pools(index)
		return
	if _spray_kinds[index] != kind:
		_configure_for_profile(index, profile)
	_place_emitters(car, wheel, index, profile, activity, wetness)


func _wheel_has_ground(wheel: Object) -> bool:
	var collider := wheel.get("last_collider") as Node
	if not wheel.is_colliding() or collider == null or wheel.spring_force <= 0.0:
		return false
	return (
		collider.is_in_group("Grass")
		or collider.is_in_group("Dirt")
		or collider.is_in_group("Road")
	)


## Занос, ручник, поворот руля и скорость делают шлейф зрелищнее.
func _drama_boost(wheel: Object, speed: float, steer: float, handbrake: float) -> float:
	var slide: float = absf(wheel.local_velocity.x) / maxf(0.6, speed)
	var boost := 1.0
	boost += _p("steer_boost", 0.8) * absf(steer) * 0.6
	boost += _p("handbrake_boost", 1.0) * clampf(handbrake, 0.0, 1.0)
	boost += _p("steer_boost", 0.8) * clampf(slide, 0.0, 1.5)
	boost += _p("wind_pull", 0.55) * clampf(speed / 39.0, 0.0, 1.0) * 0.5
	return boost


## Позиция и направление источников: за колесом, по ходу будущего движения.
func _place_emitters(
	car: Node3D,
	wheel: Object,
	index: int,
	profile: RallySurfaceFxProfile,
	activity: float,
	wetness: float
) -> void:
	var forward_sign: float = 1.0
	if absf(wheel.local_velocity.z) > 0.2:
		forward_sign = signf(wheel.local_velocity.z)
	var side: float = 1.0 if index % 2 == 0 else -1.0
	var point: Vector3 = wheel.last_collision_point
	var normal: Vector3 = wheel.last_collision_normal
	var basis: Basis = car.global_transform.basis.orthonormalized()
	var splay: float = _p("side_splay", 0.35) * side
	var foam_dir := Vector3(
		profile.direction.x * 0.5 + splay,
		profile.direction.y,
		-absf(profile.direction.z) * forward_sign
	)
	var grit_dir := Vector3(
		profile.direction.x * 0.5 + splay * 1.3,
		profile.direction.y,
		-absf(profile.direction.z) * forward_sign
	)
	# Плотность облака = сила колеса × настроенная полка ступени. Доля дыма и
	# комьев делит её между двумя источниками.
	var scaled: float = activity * profile.amount_ratio_for_activity(activity)
	# Ступень скорости — от общей активности колеса: ровно три настроенные полки.
	var level: float = profile.velocity_scale_for_level(_level_of(activity))
	# Доля дыма и комьев задаётся профилем покрытия через плотность каждого
	# источника: дым гуще на мокром, комья — на рыхлом.
	var smoke: float = scaled * clampf(profile.smoke_share, 0.0, 1.0)
	var grits: float = scaled * clampf(profile.grit_share, 0.0, 1.0)
	# Вынос источника от центра колеса к внешней боковине шины. Раньше здесь
	# было произведение на splay (до 0.44 м) плюс полметра назад — пыль
	# рождалась заметно в стороне от колеса. Теперь смещение задаётся в метрах
	# напрямую и держится в пределах ширины покрышки.
	var outward: Vector3 = basis.x * side * _p("spawn_outward", 0.12)
	# Перед машины смотрит в +Z (колёса FL/FR стоят на z = +1.9), поэтому
	# «назад по ходу» = -forward_sign * basis.z: при движении вперёд
	# forward_sign = +1 и сдвиг уходит в -Z, за корму.
	var rearward: Vector3 = basis.z * (_p("spawn_behind", 0.05) * -forward_sign)
	var spawn: Vector3 = point + outward + rearward
	# Пол под источником: не даём клубу родиться ниже земли на уклоне.
	spawn.y = maxf(spawn.y, point.y)
	_emit_foam(
		index, profile, smoke, level, wetness,
		spawn + normal * 0.06 + Vector3.UP * _p("foam_height", 0.09), basis, foam_dir
	)
	_emit_grit(
		index, profile, grits, level, wetness,
		spawn + normal * 0.04, basis, grit_dir
	)


## Плавная заливка источника: плотность = amount × amount_ratio.
## density — доля облака для этого источника, level — скорость ступени,
## strength — общая активность (нужна для отдельных кривых покрытия).
func _emit_foam(
	index: int,
	profile: RallySurfaceFxProfile,
	density: float,
	level: float,
	wetness: float,
	point: Vector3,
	basis: Basis,
	direction: Vector3
) -> void:
	var pool := _foams[index]
	var process := pool.process_material as ParticleProcessMaterial
	var wet_boost := 1.0 + _p("foam_wet_boost", 1.7) * clampf(wetness, 0.0, 1.0) * 0.35
	var ratio := clampf(density * wet_boost, 0.0, 1.0)
	pool.amount_ratio = ratio
	process.direction = direction
	process.initial_velocity_min = _p("foam_speed_min", 0.4) * profile.velocity_scale * level
	process.initial_velocity_max = maxf(
		process.initial_velocity_min,
		_p("foam_speed_max", 2.4) * profile.velocity_scale * level
	)
	var color: Color = profile.color_for_wetness(wetness)
	color.a *= clampf(_p("foam_alpha", 0.56), 0.0, 1.0) * clampf(profile.particle_tint, 0.05, 3.0)
	process.color = color
	pool.global_transform = Transform3D(basis, point)
	pool.emitting = ratio > 0.0


func _emit_grit(
	index: int,
	profile: RallySurfaceFxProfile,
	density: float,
	level: float,
	wetness: float,
	point: Vector3,
	basis: Basis,
	direction: Vector3
) -> void:
	var pool := _sprays[index]
	var process := pool.process_material as ParticleProcessMaterial
	pool.amount_ratio = clampf(density, 0.0, 1.0)
	process.direction = direction
	var burst: float = maxf(0.05, profile.burst_scale)
	var speed_min: float = _p("grit_speed_min", 1.5) * profile.velocity_scale * level * burst
	var speed_max: float = _p("grit_speed_max", 5.2) * profile.velocity_scale * level * burst
	process.initial_velocity_min = maxf(0.0, speed_min)
	process.initial_velocity_max = maxf(speed_min, speed_max)
	var color: Color = profile.color_for_wetness(wetness)
	var kind: String = profile.kind_name()
	if kind == "gravel" or kind == "mud" or kind == "grass":
		color = color.darkened(0.16)
		color.a = clampf(_p("grit_alpha", 0.96), 0.0, 1.0) * clampf(
			profile.particle_tint, 0.05, 3.0
		)
	else:
		color.a *= clampf(profile.particle_tint, 0.05, 3.0)
	process.color = color
	pool.global_transform = Transform3D(basis, point)
	pool.emitting = pool.amount_ratio > 0.0


## Ступень для скорости частиц: чем активнее колесо, тем дальше летит выброс.
func _level_of(strength: float) -> int:
	if strength <= 0.001:
		return 1
	return clampi(ceili(clampf(strength, 0.0, 1.0) * 3.0), 1, 3)


## Выключить оба источника колеса. Уже вылетевшая пыль доживает свой век
## и плавно растворяется: резкого обрыва облака нет.
func _stop_pools(index: int) -> void:
	for pool in [_foams[index], _sprays[index]]:
		if pool != null:
			pool.emitting = false


## Пересчитать размер источника и материалы под покрытие (редко, при смене типа).
func _configure_for_profile(index: int, profile: RallySurfaceFxProfile) -> void:
	_spray_kinds[index] = profile.kind_name()
	var amount_scale: float = clampf(_p("fx_intensity", 1.0), 0.0, 4.0)
	_configure_foam(index, profile, amount_scale)
	_configure_grit(index, profile, amount_scale)


## Клубы: количество, жизнь, размер плоскости и разлёт под покрытие.
func _configure_foam(index: int, profile: RallySurfaceFxProfile, amount_scale: float) -> void:
	var foam := _foams[index]
	foam.name = "WheelFoam_%s_%d" % [profile.kind_name().capitalize(), index]
	foam.amount = maxi(1, roundi(_p("foam_amount", 72) * amount_scale * profile.amount_scale))
	foam.lifetime = maxf(0.1, _p("foam_lifetime", 1.55) * profile.lifetime_scale)
	var quad := foam.draw_pass_1 as QuadMesh
	if quad != null:
		var size := maxf(0.01, _p("foam_size", 0.18)) * profile.particle_scale
		quad.size = Vector2(size, size) * 2.0
	var process := foam.process_material as ParticleProcessMaterial
	if process == null:
		return
	process.spread = clampf(_p("foam_spread", 42.0) * profile.spread_scale, 0.0, 180.0)
	process.emission_sphere_radius = maxf(0.01, _p("foam_size", 0.18)) * _p(
		"foam_emission_radius", 0.55
	)
	process.scale_min = _p("foam_scale_min", 0.55) * profile.particle_scale
	process.scale_max = _p("foam_scale_max", 1.35) * profile.particle_scale
	process.gravity = _pv("foam_gravity", Vector3(0.0, -0.75, 0.0)) * profile.gravity_scale
	process.damping_min = _p("foam_damping_min", 0.55)
	process.damping_max = maxf(_p("foam_damping_min", 0.55), _p("foam_damping_max", 1.25))
	process.scale_curve = DustFx.growth_curve(_p("foam_growth", 2.3))
	process.turbulence_enabled = _p("foam_turbulence", 2.0) > 0.0
	process.turbulence_noise_strength = _p("foam_turbulence", 2.0)
	process.turbulence_noise_scale = _p("foam_turbulence_scale", 3.0)
	process.inherit_velocity_ratio = _p("inherit_velocity_ratio", 0.22)
	var spin := _p("foam_spin", 48.0)
	process.angular_velocity_min = -spin
	process.angular_velocity_max = spin


## Комья: количество, жизнь, размер зерна и разлёт под покрытие.
func _configure_grit(index: int, profile: RallySurfaceFxProfile, amount_scale: float) -> void:
	var grit := _sprays[index]
	grit.name = "WheelGrit_%s_%d" % [profile.kind_name().capitalize(), index]
	grit.amount = maxi(1, roundi(_p("grit_amount", 88) * amount_scale * profile.amount_scale))
	grit.lifetime = maxf(0.05, _p("grit_lifetime", 0.95) * profile.lifetime_scale)
	var grain := grit.draw_pass_1 as SphereMesh
	if grain != null:
		var radius := maxf(0.002, _p("spray_grain_radius", 0.026) * profile.grain_scale)
		grain.radius = radius
		grain.height = maxf(radius * 1.2, _p("spray_grain_height", 0.062) * profile.grain_scale)
		grain.radial_segments = maxi(3, _pi("spray_grain_segments", 3))
		grain.rings = maxi(1, _pi("spray_grain_rings", 1))
	var process := grit.process_material as ParticleProcessMaterial
	if process == null:
		return
	process.spread = clampf(_p("grit_spread", 42.0) * profile.spread_scale, 0.0, 180.0)
	process.scale_min = _p("grit_scale_min", 0.55) * profile.particle_scale
	process.scale_max = _p("grit_scale_max", 2.3) * profile.particle_scale
	process.scale_curve = DustFx.debris_scale_curve()
	process.color_initial_ramp = (
		DustFx.debris_color_variation() if _pb("grit_use_variation", true) else null
	)
	process.gravity = _pv("grit_gravity", Vector3(0.0, -13.5, 0.0)) * profile.gravity_scale
	process.lifetime_randomness = _p("grit_lifetime_randomness", 0.5)
	process.damping_min = _p("grit_damping_min", 0.35)
	process.damping_max = maxf(_p("grit_damping_min", 0.35), _p("grit_damping_max", 1.05))
	var spin := _p("grit_spin", 260.0)
	process.angular_velocity_min = -spin
	process.angular_velocity_max = spin


func clear() -> void:
	amounts = Vector4.ZERO
	damp = Vector4.ZERO
	snow_amounts = Vector4.ZERO
	_reset_dirt_look()
	for pool in _sprays + _foams:
		pool.emitting = false
	if _material != null:
		_material.set_shader_parameter("dirt_amount", amounts)
		_material.set_shader_parameter("damp_amount", damp)
		_material.set_shader_parameter("snow_amount", snow_amounts)
