## Ощущение удара: тряска и рывок камеры, «удар» угла обзора, искры, обломки,
## осколки, пыль, звук удара и скрежета, вибрация геймпада.
##
## Узел ставит RallyCar (см. _install_damage_visual) любой машине — от модели
## ничего не нужно. Машина сообщает о событиях из шага физики:
##   impact()  — удар (потеря скорости за кадр, точка и нормаль контакта);
##   scrape()  — каждый кадр, пока кузов скользит вдоль препятствия.
## Сами эффекты запускаются в _process, вне колбэка физики.
##
## Все числа — в RallyImpactFxConfig (data/car/default_impact_fx.tres).
## Слой косметический: на скорость, здоровье и очки не влияет.
class_name CarImpactFx
extends Node3D

const DustFx = preload("res://scripts/effects/rally_dust_fx.gd")

## Сколько одновременных вспышек каждого вида (удары подряд не обрывают друг друга).
const BURST_POOL := 3
## Частота синтезированных звуков, Гц.
const SAMPLE_RATE := 22050
## Сколько звуков удара может звучать одновременно.
const SOUND_SLOTS := 3
## Через сколько секунд без сообщений скольжение считается законченным.
const SCRAPE_TIMEOUT_SEC := 0.12
## Как часто дёргать вибрацию во время скрежета, с.
const SCRAPE_RUMBLE_PERIOD := 0.15

## Удар принят и показан: мировая точка и сила 0..1.
signal impacted(world_point: Vector3, strength: float)

static var _crash_light: AudioStreamWAV = null
static var _crash_heavy: AudioStreamWAV = null
static var _scrape_loop: AudioStreamWAV = null

## Настройка. Подставляет машина; без неё — значения по умолчанию.
var config: RallyImpactFxConfig = null

var _car: Node3D = null
var _rumble: Callable = Callable()
var _pending: Array[Dictionary] = []
var _cooldown := 0.0
var _impacts := 0
var _trauma := 0.0
var _kick := Vector3.ZERO
var _kick_velocity := Vector3.ZERO
var _fov_punch := 0.0
var _fov_applied := 0.0
var _time := 0.0
var _noise := FastNoiseLite.new()
var _scrape_target := 0.0
var _scrape_level := 0.0
var _scrape_seen := 1000.0
var _scrape_point := Vector3.ZERO
var _scrape_dir := Vector3.UP
var _scrape_rumble_timer := 0.0
var _pools: Dictionary = {}
var _pool_next: Dictionary = {}
var _scrape_sparks: GPUParticles3D = null
var _players: Array[AudioStreamPlayer3D] = []
var _next_player := 0
var _scrape_player: AudioStreamPlayer3D = null
var _hitstop_until_msec := 0
var _hitstop_active := false


func _init() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = 7


## Подготовить эффекты для машины. rumble — функция вибрации (weak, strong, duration).
func setup(car: Node3D, settings: RallyImpactFxConfig = null, rumble: Callable = Callable()) -> void:
	_car = car
	config = settings
	_rumble = rumble
	rebuild()


## Настройка — никогда не null.
func cfg() -> RallyImpactFxConfig:
	if config == null:
		config = RallyImpactFxConfig.new()
	return config


## Пересобрать частицы и звук под текущие значения настройки (после правки
## ресурса во время игры или в лаборатории).
func rebuild() -> void:
	for pool in _pools.values():
		for emitter in pool:
			(emitter as Node).queue_free()
	_pools.clear()
	_pool_next.clear()
	if _scrape_sparks != null:
		_scrape_sparks.queue_free()
	if _scrape_player != null:
		_scrape_player.queue_free()
	for player in _players:
		player.queue_free()
	_players.clear()
	var tuning := cfg()
	_build_pool("sparks", func() -> GPUParticles3D: return _make_sparks(tuning.sparks_amount, false))
	_build_pool("debris", func() -> GPUParticles3D: return _make_debris(tuning.debris_amount, false))
	_build_pool("glass", func() -> GPUParticles3D: return _make_debris(tuning.glass_amount, true))
	_build_pool("dust", func() -> GPUParticles3D: return _make_dust(tuning.dust_amount))
	_scrape_sparks = _make_sparks(maxi(8, int(tuning.scrape_sparks_per_sec * tuning.sparks_lifetime)), true)
	_scrape_sparks.name = "ScrapeSparks"
	add_child(_scrape_sparks)
	for i in range(SOUND_SLOTS):
		var player := _make_player("ImpactSound_%d" % i)
		_players.append(player)
	_scrape_player = _make_player("ScrapeSound")
	_scrape_player.stream = tuning.scrape_sound if tuning.scrape_sound != null else scrape_stream()
	_scrape_player.volume_db = -80.0


## Сообщить об ударе (можно из шага физики). world_point — точка контакта,
## world_into_car — куда вдавливается кузов, dv — потеря скорости, м/с,
## world_velocity — скорость машины после удара. Вернёт true, если удар принят.
func impact(world_point: Vector3, world_into_car: Vector3, dv: float, world_velocity: Vector3) -> bool:
	var tuning := cfg()
	if not tuning.enabled or dv < tuning.min_dv_mps or _cooldown > 0.0:
		return false
	_cooldown = tuning.cooldown_sec
	_impacts += 1
	var strength := tuning.strength(dv)
	# Даже слабый принятый удар чувствуется: минимум четверть силы.
	var feel := lerpf(0.25, 1.0, strength)
	if tuning.shake_enabled:
		_trauma = minf(1.0, _trauma + dv * tuning.shake_trauma_per_dv)
		var into := world_into_car.normalized()
		# Камеру бросает туда же, куда толкнуло кузов.
		var peak := tuning.kick_m * feel
		_kick_velocity += into * peak * maxf(tuning.kick_return, 0.1) * exp(1.0)
		_fov_punch = maxf(_fov_punch, tuning.fov_punch_deg * feel)
	_pending.append({
		"point": world_point,
		"into": world_into_car.normalized(),
		"dv": dv,
		"strength": strength,
		"velocity": world_velocity,
	})
	return true


## Скольжение вдоль препятствия: зовётся каждый кадр контакта.
## slide_speed — скорость вдоль стены, м/с.
func scrape(world_point: Vector3, world_into_car: Vector3, slide_speed: float, world_velocity: Vector3) -> void:
	var tuning := cfg()
	if not tuning.enabled:
		return
	var level := clampf((slide_speed - tuning.scrape_min_speed_mps)
		/ maxf(tuning.scrape_full_speed_mps - tuning.scrape_min_speed_mps, 0.1), 0.0, 1.0)
	if level <= 0.0:
		return
	_scrape_target = maxf(_scrape_target if _scrape_seen < SCRAPE_TIMEOUT_SEC else 0.0, level)
	_scrape_seen = 0.0
	_scrape_point = world_point
	var tangent := world_velocity - world_into_car * world_velocity.dot(world_into_car)
	var out := -world_into_car.normalized()
	# Искры летят назад по ходу и чуть от стены.
	var dir := -tangent.normalized() * 0.8 + out * 0.4 + Vector3.UP * 0.3
	_scrape_dir = dir.normalized() if dir.length_squared() > 1e-6 else Vector3.UP


## Лёгкий толчок без искр и звука удара — снесённый забор, конус, табличка:
## встряска (0..1), рывок камеры (доля kick_m) и вибрация. Свои щепки и треск
## показывает сам разрушаемый пропс.
func nudge(world_into_car: Vector3, shake: float, kick: float, rumble: float, rumble_duration: float) -> void:
	var tuning := cfg()
	if not tuning.enabled:
		return
	if tuning.shake_enabled:
		_trauma = minf(1.0, _trauma + maxf(shake, 0.0))
		if kick > 0.0 and world_into_car.length_squared() > 1e-6:
			_kick_velocity += world_into_car.normalized() * tuning.kick_m * kick \
				* maxf(tuning.kick_return, 0.1) * exp(1.0)
	if tuning.rumble_enabled and rumble > 0.0 and _rumble.is_valid():
		_rumble.call(rumble * 0.7, rumble, rumble_duration)


## Убрать подъём угла обзора прошлого кадра — до того, как машина сгладит FOV.
func restore_camera(camera: Camera3D) -> void:
	if camera != null and not is_zero_approx(_fov_applied):
		camera.fov -= _fov_applied
	_fov_applied = 0.0


## Тряска, рывок и FOV поверх уже поставленной камеры. inside — вид из кабины
## или с капота.
func apply_camera(camera: Camera3D, inside: bool) -> void:
	var tuning := cfg()
	if camera == null or not tuning.enabled or not tuning.shake_enabled:
		return
	var amount := maxf(_trauma * _trauma, tuning.scrape_shake * _scrape_level * _scrape_level)
	if inside:
		amount *= tuning.inside_shake_scale
	var t := _time * tuning.shake_frequency_hz
	if amount > 0.0005:
		var offset := Vector3(_noise.get_noise_2d(t, 0.0), _noise.get_noise_2d(t, 37.0),
			_noise.get_noise_2d(t, 91.0)) * tuning.shake_offset_m * amount
		camera.global_position += camera.global_transform.basis * offset
		var angle := deg_to_rad(tuning.shake_angle_deg) * amount
		camera.rotate_object_local(Vector3.RIGHT, _noise.get_noise_2d(t, 151.0) * angle)
		camera.rotate_object_local(Vector3.UP, _noise.get_noise_2d(t, 211.0) * angle)
		camera.rotate_object_local(Vector3.FORWARD, _noise.get_noise_2d(t, 263.0) * angle * 1.3)
	if _kick.length_squared() > 1e-8:
		camera.global_position += _kick * (tuning.inside_shake_scale if inside else 1.0)
	if _fov_punch > 0.01:
		_fov_applied = _fov_punch
		camera.fov = clampf(camera.fov + _fov_applied, 1.0, 179.0)


## Стереть всё: частицы, звук, тряску (рестарт заезда).
func clear() -> void:
	_pending.clear()
	_trauma = 0.0
	_kick = Vector3.ZERO
	_kick_velocity = Vector3.ZERO
	_fov_punch = 0.0
	_scrape_target = 0.0
	_scrape_level = 0.0
	_scrape_seen = 1000.0
	_cooldown = 0.0
	_impacts = 0
	for pool in _pools.values():
		for emitter in pool:
			(emitter as GPUParticles3D).emitting = false
	if _scrape_sparks != null:
		_scrape_sparks.emitting = false
	for player in _players:
		player.stop()
	if _scrape_player != null:
		_scrape_player.stop()
	_end_hitstop()


## Сколько ударов принято с прошлого рестарта.
func impact_count() -> int:
	return _impacts


## Текущая «встряска» камеры 0..1.
func trauma() -> float:
	return _trauma


## Текущая громкость скрежета 0..1.
func scrape_level() -> float:
	return _scrape_level


func _process(delta: float) -> void:
	var tuning := cfg()
	_time += delta
	_cooldown = maxf(0.0, _cooldown - delta)
	while not _pending.is_empty():
		_show_impact(_pending.pop_front(), tuning)
	_trauma = maxf(0.0, _trauma - tuning.shake_decay * delta)
	# Критически задемпфированная пружина: рывок плавно выходит и возвращается.
	var w := maxf(tuning.kick_return, 0.1)
	_kick_velocity += (-w * w * _kick - 2.0 * w * _kick_velocity) * delta
	_kick += _kick_velocity * delta
	if _kick.length_squared() < 1e-8 and _kick_velocity.length_squared() < 1e-8:
		_kick = Vector3.ZERO
		_kick_velocity = Vector3.ZERO
	_fov_punch *= exp(-w * delta)
	_update_scrape(delta, tuning)
	if _hitstop_active and Time.get_ticks_msec() >= _hitstop_until_msec:
		_end_hitstop()


func _exit_tree() -> void:
	_end_hitstop()


func _show_impact(event: Dictionary, tuning: RallyImpactFxConfig) -> void:
	var point: Vector3 = event["point"]
	var into: Vector3 = event["into"]
	var dv: float = event["dv"]
	var strength: float = event["strength"]
	var velocity: Vector3 = event["velocity"]
	var out := -into
	var tangent := velocity - into * velocity.dot(into)
	var bounce := out + Vector3.UP * 0.35
	if tangent.length_squared() > 1.0:
		bounce += tangent.normalized() * 0.45
	bounce = bounce.normalized()
	if tuning.sparks_enabled:
		_burst("sparks", point, bounce, lerpf(tuning.sparks_min_ratio, 1.0, strength))
	if tuning.debris_enabled and dv >= tuning.debris_min_dv_mps:
		var debris := _burst("debris", point, bounce, lerpf(0.3, 1.0, strength))
		if debris != null:
			var color := _paint_color() if tuning.debris_use_paint_color else tuning.debris_color
			(debris.process_material as ParticleProcessMaterial).color = color
	if tuning.glass_enabled and dv >= tuning.glass_min_dv_mps:
		_burst("glass", point + Vector3.UP * 0.25, bounce, lerpf(0.4, 1.0, strength))
	if tuning.dust_enabled:
		_burst("dust", point, (out + Vector3.UP).normalized(), lerpf(0.35, 1.0, strength))
	if tuning.sound_enabled:
		_play_impact_sound(point, dv, strength, tuning)
	if tuning.rumble_enabled and _rumble.is_valid():
		var feel := lerpf(0.3, 1.0, strength)
		_rumble.call(tuning.rumble_weak * feel, tuning.rumble_strong * feel,
			tuning.rumble_duration * lerpf(0.6, 1.0, strength))
	if tuning.hitstop_enabled and dv >= tuning.hitstop_min_dv_mps and not _hitstop_active \
			and is_equal_approx(Engine.time_scale, 1.0):
		_hitstop_active = true
		Engine.time_scale = tuning.hitstop_time_scale
		_hitstop_until_msec = Time.get_ticks_msec() + int(tuning.hitstop_duration_sec * 1000.0)
	impacted.emit(point, strength)


func _end_hitstop() -> void:
	if _hitstop_active:
		Engine.time_scale = 1.0
	_hitstop_active = false


func _update_scrape(delta: float, tuning: RallyImpactFxConfig) -> void:
	_scrape_seen += delta
	if _scrape_seen > SCRAPE_TIMEOUT_SEC:
		_scrape_target = 0.0
	var response := 14.0 if _scrape_target > _scrape_level else 6.0
	_scrape_level = lerpf(_scrape_level, _scrape_target, 1.0 - exp(-response * delta))
	if _scrape_level < 0.01 and _scrape_target <= 0.0:
		_scrape_level = 0.0
	var active: bool = _scrape_level > 0.02 and tuning.enabled
	if _scrape_sparks != null:
		var spark_on: bool = active and tuning.sparks_enabled and tuning.scrape_sparks_per_sec > 0.0
		if spark_on:
			_scrape_sparks.global_transform = Transform3D(_basis_y(_scrape_dir), _scrape_point)
			_scrape_sparks.amount_ratio = clampf(_scrape_level, 0.05, 1.0)
		if _scrape_sparks.emitting != spark_on:
			_scrape_sparks.emitting = spark_on
	if _scrape_player != null:
		var sound_on: bool = active and tuning.sound_enabled
		if sound_on:
			_scrape_player.global_position = _scrape_point
			_scrape_player.volume_db = tuning.scrape_volume_db + linear_to_db(maxf(_scrape_level, 0.001))
			_scrape_player.pitch_scale = lerpf(0.8, 1.25, _scrape_level)
			if not _scrape_player.playing and _scrape_player.is_inside_tree():
				_scrape_player.play()
		elif _scrape_player.playing:
			_scrape_player.stop()
	_scrape_rumble_timer -= delta
	if active and tuning.rumble_enabled and tuning.rumble_scrape > 0.0 and _rumble.is_valid() \
			and _scrape_rumble_timer <= 0.0:
		_scrape_rumble_timer = SCRAPE_RUMBLE_PERIOD
		_rumble.call(tuning.rumble_scrape * _scrape_level * 0.6, tuning.rumble_scrape * _scrape_level,
			SCRAPE_RUMBLE_PERIOD * 1.4)


# ── Частицы ────────────────────────────────────────────────────────────────

func _build_pool(kind: String, maker: Callable) -> void:
	var pool: Array[GPUParticles3D] = []
	for i in range(BURST_POOL):
		var emitter: GPUParticles3D = maker.call()
		emitter.name = "%s_%d" % [kind.capitalize(), i]
		add_child(emitter)
		pool.append(emitter)
	_pools[kind] = pool
	_pool_next[kind] = 0


## Выпустить вспышку из пула: точка, направление вылета и доля частиц.
func _burst(kind: String, point: Vector3, direction: Vector3, ratio: float) -> GPUParticles3D:
	if not _pools.has(kind) or not is_inside_tree():
		return null
	var pool: Array = _pools[kind]
	var index: int = _pool_next[kind]
	_pool_next[kind] = (index + 1) % pool.size()
	var emitter := pool[index] as GPUParticles3D
	emitter.global_transform = Transform3D(_basis_y(direction), point)
	emitter.amount_ratio = clampf(ratio, 0.02, 1.0)
	emitter.restart()
	emitter.emitting = true
	return emitter


func _basis_y(direction: Vector3) -> Basis:
	var y := direction.normalized()
	if y.length_squared() < 1e-6:
		y = Vector3.UP
	var helper := Vector3.FORWARD if absf(y.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var x := helper.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _new_emitter(amount: int, lifetime: float, one_shot: bool) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.top_level = true
	emitter.local_coords = false
	emitter.one_shot = one_shot
	emitter.emitting = false
	emitter.amount = maxi(1, amount)
	emitter.lifetime = maxf(lifetime, 0.05)
	emitter.explosiveness = 0.92 if one_shot else 0.0
	emitter.randomness = 0.4
	emitter.fixed_fps = 0
	emitter.interpolate = true
	emitter.visibility_aabb = AABB(Vector3(-12.0, -12.0, -12.0), Vector3(24.0, 24.0, 24.0))
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return emitter


func _make_sparks(amount: int, continuous: bool) -> GPUParticles3D:
	var tuning := cfg()
	var emitter := _new_emitter(amount, tuning.sparks_lifetime, not continuous)
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = tuning.sparks_spread_deg * (0.6 if continuous else 1.0)
	process.initial_velocity_min = tuning.sparks_speed_min
	process.initial_velocity_max = maxf(tuning.sparks_speed_max, tuning.sparks_speed_min)
	process.gravity = Vector3(0.0, -9.8 * tuning.sparks_gravity, 0.0)
	process.damping_min = 0.5
	process.damping_max = 2.5
	process.particle_flag_align_y = true
	process.scale_min = 0.5
	process.scale_max = 1.2
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.06
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 0.9, 1.0))
	ramp.set_color(1, Color(1.0, 0.25, 0.05, 0.0))
	ramp.add_point(0.35, Color(1.0, 0.8, 0.4, 1.0))
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	process.color_ramp = ramp_texture
	emitter.process_material = process
	var mesh := BoxMesh.new()
	mesh.size = Vector3(tuning.sparks_size.x, tuning.sparks_size.y, tuning.sparks_size.x)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.vertex_color_use_as_albedo = true
	var energy := tuning.sparks_energy
	material.albedo_color = Color(tuning.sparks_color.r * energy, tuning.sparks_color.g * energy,
		tuning.sparks_color.b * energy, tuning.sparks_color.a)
	material.disable_receive_shadows = true
	mesh.material = material
	emitter.draw_pass_1 = mesh
	return emitter


func _make_debris(amount: int, glass: bool) -> GPUParticles3D:
	var tuning := cfg()
	var emitter := _new_emitter(amount, tuning.debris_lifetime, true)
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 55.0
	process.initial_velocity_min = tuning.debris_speed_min
	process.initial_velocity_max = maxf(tuning.debris_speed_max, tuning.debris_speed_min)
	process.gravity = Vector3(0.0, -9.8, 0.0)
	process.damping_min = 0.2
	process.damping_max = 0.8
	process.particle_flag_rotate_y = true
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.angular_velocity_min = -720.0
	process.angular_velocity_max = 720.0
	process.scale_min = 0.4 if glass else 0.5
	process.scale_max = 0.9 if glass else 1.4
	process.scale_curve = DustFx.debris_scale_curve()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.12
	process.color = tuning.glass_color if glass else tuning.debris_color
	emitter.process_material = process
	var mesh := BoxMesh.new()
	var size := tuning.debris_size_m
	mesh.size = Vector3(size, size * (0.12 if glass else 0.3), size * 0.7)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.1 if glass else 0.6
	material.metallic_specular = 0.9 if glass else 0.5
	if glass:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = material
	emitter.draw_pass_1 = mesh
	return emitter


func _make_dust(amount: int) -> GPUParticles3D:
	var tuning := cfg()
	var emitter := _new_emitter(amount, tuning.dust_lifetime, true)
	emitter.explosiveness = 0.85
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 70.0
	process.initial_velocity_min = 0.6
	process.initial_velocity_max = 2.4
	process.gravity = Vector3(0.0, 0.25, 0.0)
	process.damping_min = 1.5
	process.damping_max = 3.0
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.scale_min = 0.7
	process.scale_max = 1.3
	process.scale_curve = DustFx.growth_curve(2.6)
	process.color = tuning.dust_color
	process.color_ramp = DustFx.fade_ramp()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.25
	emitter.process_material = process
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * tuning.dust_size_m
	mesh.material = DustFx.puff_material(DustFx.puff_texture(), false)
	emitter.draw_pass_1 = mesh
	return emitter


## Цвет краски кузова для обломков: меш rally_body_paint, его активный материал.
func _paint_color() -> Color:
	var fallback := cfg().debris_color
	if _car == null or not is_instance_valid(_car):
		return fallback
	for node in _car.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := node as MeshInstance3D
		if mesh_inst == null or not mesh_inst.is_in_group("rally_body_paint") or mesh_inst.mesh == null:
			continue
		for s in range(mesh_inst.mesh.get_surface_count()):
			var material := mesh_inst.get_active_material(s) as BaseMaterial3D
			if material != null:
				return material.albedo_color
		break
	return fallback


# ── Звук ───────────────────────────────────────────────────────────────────

func _make_player(node_name: String) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = node_name
	player.bus = "Vehicle" if AudioServer.get_bus_index("Vehicle") >= 0 else "Master"
	player.unit_size = cfg().sound_unit_size
	player.max_distance = 200.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	player.max_polyphony = 2
	add_child(player)
	return player


func _play_impact_sound(point: Vector3, dv: float, strength: float, tuning: RallyImpactFxConfig) -> void:
	if _players.is_empty():
		return
	var heavy: bool = dv >= tuning.heavy_dv_mps
	var stream: AudioStream = null
	var custom: Array[AudioStream] = tuning.heavy_impact_sounds if heavy and not tuning.heavy_impact_sounds.is_empty() \
		else tuning.impact_sounds
	if not custom.is_empty():
		stream = custom[randi() % custom.size()]
	if stream == null:
		stream = crash_stream(heavy)
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = stream
	player.global_position = point
	player.volume_db = lerpf(tuning.impact_volume_min_db, tuning.impact_volume_max_db, strength)
	player.pitch_scale = maxf(0.3, 1.0 + randf_range(-tuning.pitch_jitter, tuning.pitch_jitter)
		- (0.08 if heavy else 0.0))
	if player.is_inside_tree():
		player.play()


## Синтезированный удар: глухой «бум» кузова, хруст металла и звон панелей.
## Генерируется один раз и делится всеми машинами.
static func crash_stream(heavy: bool) -> AudioStreamWAV:
	if heavy and _crash_heavy != null:
		return _crash_heavy
	if not heavy and _crash_light != null:
		return _crash_light
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337 if heavy else 7331
	var duration := 1.0 if heavy else 0.5
	var frames := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var low := 0.0
	var band := 0.0
	var crackle := 0.0
	var thump_hz := 52.0 if heavy else 78.0
	var rings: Array[Vector2] = [Vector2(347.0, 7.0), Vector2(613.0, 9.0), Vector2(1187.0, 12.0),
		Vector2(1931.0, 16.0)]
	for i in range(frames):
		var t := float(i) / SAMPLE_RATE
		var noise := rng.randf_range(-1.0, 1.0)
		low += (noise - low) * 0.08
		band += (noise - low - band) * 0.45
		var body := sin(TAU * thump_hz * t * (1.0 - t * 0.6)) * exp(-t * (7.0 if heavy else 11.0))
		var crunch := band * exp(-t * (9.0 if heavy else 16.0)) * 1.4
		var ring := 0.0
		for r in rings:
			ring += sin(TAU * r.x * t + r.x) * exp(-t * r.y)
		ring *= 0.12 * exp(-t * 3.0)
		# Хруст: редкие щелчки — ломающийся пластик и стекло.
		if rng.randf() < (0.012 if heavy else 0.006) * exp(-t * 3.0):
			crackle = rng.randf_range(0.4, 1.0)
		crackle *= 0.9
		var click := crackle * rng.randf_range(-1.0, 1.0)
		var attack := minf(1.0, t * 400.0)
		samples[i] = (body * (1.0 if heavy else 0.8) + crunch + ring + click * 0.5) * attack
	var stream := _to_wav(samples, false)
	if heavy:
		_crash_heavy = stream
	else:
		_crash_light = stream
	return stream


## Синтезированный скрежет: шершавый шум и тонкий визг металла, зациклен.
static func scrape_stream() -> AudioStreamWAV:
	if _scrape_loop != null:
		return _scrape_loop
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var frames := SAMPLE_RATE
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var low := 0.0
	var band := 0.0
	for i in range(frames):
		var t := float(i) / SAMPLE_RATE
		var noise := rng.randf_range(-1.0, 1.0)
		low += (noise - low) * 0.12
		band += (noise - low - band) * 0.6
		# Целые частоты: за секунду укладывается целое число периодов, и
		# петля склеивается без щелчка.
		var grind := 0.6 + 0.4 * sin(TAU * 9.0 * t) * sin(TAU * 4.0 * t)
		var squeal := sin(TAU * 1830.0 * t + 2.0 * sin(TAU * 3.0 * t)) * (0.5 + 0.5 * sin(TAU * 2.0 * t))
		samples[i] = band * grind * 0.9 + squeal * 0.12 + low * 0.5
	_scrape_loop = _to_wav(samples, true)
	return _scrape_loop


static func _to_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var peak := 0.001
	for s in samples:
		peak = maxf(peak, absf(s))
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	var gain := 0.9 / peak
	for i in range(samples.size()):
		data.encode_s16(i * 2, int(clampf(samples[i] * gain, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream
