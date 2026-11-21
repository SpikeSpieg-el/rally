## Обломки снесённых пропсов и эффекты разрушения: одна копия на сцену.
##
## Сюда стекаются все удары по разрушаемым пропсам (BreakableProps): здесь
## живут физические обломки (общий потолок количества на всю сцену), пулы щепок
## и пыли, звуки треска. Обломки лежат на слое 3: колёса и камера их не видят,
## а с машиной у них исключение коллизии — на доске не подпрыгнешь и под
## кузовом она не застрянет (RallyBreakableConfig.pieces_hit_car включает это).
##
## Узел создаёт BreakableProps по первому удару — в корне текущей сцены, —
## поэтому чанки стриминга можно выгружать, не обрывая летящие обломки.
extends Node3D

const Collision = preload("res://scripts/track/prop_collision.gd")
const DustFx = preload("res://scripts/effects/rally_dust_fx.gd")

const GROUP := "rally_breakable_debris"
## Слой обломков (третий бит): не земля и не препятствие кузова.
const PIECE_LAYER := 4
## Обломки падают на землю (1) и бьются о препятствия (2).
const PIECE_MASK := 3
const BURST_POOL := 4
const SOUND_SLOTS := 4
const SAMPLE_RATE := 22050

static var _crack_stream: AudioStreamWAV = null

var config: RallyBreakableConfig = null

var _pieces: Array[Dictionary] = []
var _splinters: Array[GPUParticles3D] = []
var _dust: Array[GPUParticles3D] = []
var _next_burst := 0
var _players: Array[AudioStreamPlayer3D] = []
var _next_player := 0
var _built_for: RallyBreakableConfig = null
var _material: PhysicsMaterial = null
var _rng := RandomNumberGenerator.new()
var _spawned_total := 0


func _ready() -> void:
	add_to_group(GROUP)
	_rng.seed = 90210


func cfg() -> RallyBreakableConfig:
	if config == null:
		config = RallyBreakableConfig.new()
	return config


## Живых обломков сейчас.
func piece_count() -> int:
	return _pieces.size()


## Сколько обломков рождено за всё время (для проверок).
func spawned_total() -> int:
	return _spawned_total


## Убрать все обломки (рестарт заезда).
func clear_pieces() -> void:
	for piece in _pieces:
		var body: Node = piece["body"]
		if is_instance_valid(body):
			body.queue_free()
	_pieces.clear()


## Рассыпать пропс на обломки.
##   parts — детали [{mesh, xform, aabb}] в системе пропса;
##   world — пропс в мире (с масштабом); mass — масса целого пропса;
##   car_velocity — скорость машины; contact — точка удара; car — кто снёс.
func spawn(parts: Array, world: Transform3D, mass: float, car_velocity: Vector3, contact: Vector3, car: Node) -> int:
	var tuning := cfg()
	var pieces := _split(parts, world, tuning.split_longer_than_m)
	if pieces.is_empty():
		return 0
	var total_volume := 0.0
	for piece in pieces:
		total_volume += float(piece["volume"])
	var speed := car_velocity.length()
	var strength := tuning.strength(speed)
	var forward := car_velocity / speed if speed > 0.05 else Vector3.ZERO
	var count := 0
	for piece in pieces:
		var full: Transform3D = piece["full"]
		var aabb: AABB = piece["aabb"]
		var center: Vector3 = full * aabb.get_center()
		var body_xform := Transform3D(full.basis.orthonormalized(), center)
		var body := RigidBody3D.new()
		body.name = "Debris_%d" % _spawned_total
		body.collision_layer = PIECE_LAYER
		body.collision_mask = PIECE_MASK
		body.mass = maxf(0.3, mass * float(piece["volume"]) / maxf(total_volume, 1e-6))
		body.physics_material_override = _physics_material()
		body.continuous_cd = false
		body.can_sleep = true
		var visual := MeshInstance3D.new()
		visual.name = "Mesh"
		visual.mesh = piece["mesh"]
		visual.transform = body_xform.affine_inverse() * full
		body.add_child(visual)
		var shape := CollisionShape3D.new()
		shape.shape = Collision.shape_for(Collision.Kind.BOX, (piece["size"] as Vector3).max(Vector3.ONE * 0.03))
		body.add_child(shape)
		add_child(body)
		body.global_transform = body_xform
		if car is PhysicsBody3D and not tuning.pieces_hit_car:
			body.add_collision_exception_with(car)
		var away := center - contact
		away.y = 0.0
		away = away.normalized() if away.length_squared() > 1e-6 else forward
		var velocity := car_velocity * tuning.velocity_transfer
		if velocity.length() < tuning.min_kick_mps:
			var push := forward if forward != Vector3.ZERO else away
			velocity = push * tuning.min_kick_mps
		velocity += away * tuning.scatter_mps * _rng.randf_range(0.35, 1.0)
		velocity += Vector3.UP * tuning.lift_mps * maxf(strength, 0.15) * _rng.randf_range(0.5, 1.0)
		velocity += _random_unit() * tuning.scatter_mps * 0.3
		body.linear_velocity = velocity
		body.angular_velocity = _random_unit() * tuning.spin_rad_s * _rng.randf_range(0.3, 1.0) * maxf(strength, 0.3)
		_pieces.append({"body": body, "visual": visual, "age": 0.0, "scale": visual.scale})
		_spawned_total += 1
		count += 1
	_enforce_limit()
	return count


## Пропс улетает целиком: готовый узел (копия сцены пропса с надписями и т. п.).
func spawn_node(node: Node3D, world: Transform3D, bounds: AABB, mass: float, car_velocity: Vector3, contact: Vector3, car: Node) -> void:
	if node == null:
		return
	var tuning := cfg()
	var world_scale := world.basis.get_scale()
	var center: Vector3 = world * bounds.get_center()
	var body_xform := Transform3D(world.basis.orthonormalized(), center)
	var body := RigidBody3D.new()
	body.name = "Debris_%d" % _spawned_total
	body.collision_layer = PIECE_LAYER
	body.collision_mask = PIECE_MASK
	body.mass = maxf(0.3, mass)
	body.physics_material_override = _physics_material()
	node.transform = body_xform.affine_inverse() * world
	body.add_child(node)
	var shape := CollisionShape3D.new()
	shape.shape = Collision.shape_for(Collision.Kind.BOX, (bounds.size * world_scale).max(Vector3.ONE * 0.05))
	body.add_child(shape)
	add_child(body)
	body.global_transform = body_xform
	if car is PhysicsBody3D and not tuning.pieces_hit_car:
		body.add_collision_exception_with(car)
	var speed := car_velocity.length()
	var forward := car_velocity / speed if speed > 0.05 else Vector3.FORWARD
	var velocity := car_velocity * tuning.velocity_transfer
	if velocity.length() < tuning.min_kick_mps:
		velocity = forward * tuning.min_kick_mps
	var away := center - contact
	away.y = 0.0
	velocity += away.normalized() * tuning.scatter_mps * 0.5 if away.length_squared() > 1e-6 else Vector3.ZERO
	velocity += Vector3.UP * tuning.lift_mps * maxf(tuning.strength(speed), 0.2)
	body.linear_velocity = velocity
	body.angular_velocity = _random_unit() * tuning.spin_rad_s * 0.6
	_pieces.append({"body": body, "visual": node, "age": 0.0, "scale": node.scale})
	_spawned_total += 1
	_enforce_limit()


## Щепки, пыль и треск в точке удара. strength 0..1, color — цвет щепок.
func burst(point: Vector3, car_velocity: Vector3, strength: float, color: Color) -> void:
	var tuning := cfg()
	if _built_for != tuning:
		_rebuild()
	if not is_inside_tree():
		return
	var feel := lerpf(0.3, 1.0, clampf(strength, 0.0, 1.0))
	var direction := car_velocity.normalized() * 0.7 + Vector3.UP * 0.6
	if tuning.splinters_enabled and not _splinters.is_empty():
		var emitter := _splinters[_next_burst % _splinters.size()]
		emitter.global_transform = Transform3D(_basis_y(direction), point)
		(emitter.process_material as ParticleProcessMaterial).color = color
		emitter.amount_ratio = feel
		emitter.restart()
		emitter.emitting = true
	if tuning.dust_enabled and not _dust.is_empty():
		var puff := _dust[_next_burst % _dust.size()]
		puff.global_transform = Transform3D(Basis.IDENTITY, point)
		puff.amount_ratio = feel
		puff.restart()
		puff.emitting = true
	_next_burst += 1
	if tuning.sound_enabled and not _players.is_empty():
		var player := _players[_next_player]
		_next_player = (_next_player + 1) % _players.size()
		var stream: AudioStream = null
		if not tuning.break_sounds.is_empty():
			stream = tuning.break_sounds[_rng.randi_range(0, tuning.break_sounds.size() - 1)]
		if stream == null:
			stream = crack_stream()
		player.stream = stream
		player.global_position = point
		player.volume_db = lerpf(tuning.volume_min_db, tuning.volume_max_db, clampf(strength, 0.0, 1.0))
		player.pitch_scale = 1.0 + _rng.randf_range(-tuning.pitch_jitter, tuning.pitch_jitter)
		player.unit_size = tuning.sound_unit_size
		player.play()


func _process(delta: float) -> void:
	if _pieces.is_empty():
		return
	var tuning := cfg()
	var life := tuning.piece_lifetime_sec
	var fade := maxf(tuning.piece_fade_sec, 0.001)
	var i := 0
	while i < _pieces.size():
		var piece: Dictionary = _pieces[i]
		var body: RigidBody3D = piece["body"]
		if not is_instance_valid(body):
			_pieces.remove_at(i)
			continue
		var age: float = piece["age"] + delta
		piece["age"] = age
		# Провалился под мир — убираем сразу.
		if age > life + fade or body.global_position.y < -2000.0:
			body.queue_free()
			_pieces.remove_at(i)
			continue
		if age > life:
			var k := clampf(1.0 - (age - life) / fade, 0.0, 1.0)
			var visual: Node3D = piece["visual"]
			if is_instance_valid(visual):
				visual.scale = (piece["scale"] as Vector3) * maxf(k, 0.001)
		i += 1


func _enforce_limit() -> void:
	var limit := maxi(1, cfg().max_pieces)
	while _pieces.size() > limit:
		var oldest: Dictionary = _pieces.pop_front()
		var body: Node = oldest["body"]
		if is_instance_valid(body):
			body.queue_free()


## Детали пропса в мире; длинные доски ломаются пополам.
func _split(parts: Array, world: Transform3D, split_m: float) -> Array:
	var out: Array = []
	for part in parts:
		var mesh: Mesh = part["mesh"]
		var aabb: AABB = part["aabb"]
		if mesh == null or aabb.size.length_squared() < 1e-8:
			continue
		var full: Transform3D = world * (part["xform"] as Transform3D)
		var size := Vector3(aabb.size.x * full.basis.x.length(), aabb.size.y * full.basis.y.length(),
			aabb.size.z * full.basis.z.length())
		var axis := 0
		if size.y > size[axis]:
			axis = 1
		if size.z > size[axis]:
			axis = 2
		if split_m > 0.0 and size[axis] > split_m:
			var center := aabb.get_center()
			for side in [-1.0, 1.0]:
				var squash := Vector3.ONE
				squash[axis] = 0.5
				var shift := Vector3.ZERO
				shift[axis] = aabb.size[axis] * 0.25 * side
				# Половина меша: сжать вдвое вокруг центра и сдвинуть к своему краю.
				var half := Transform3D(Basis.from_scale(squash), center + shift - center * squash)
				var half_size := size
				half_size[axis] *= 0.5
				out.append({"mesh": mesh, "full": full * half, "aabb": aabb, "size": half_size,
					"volume": half_size.x * half_size.y * half_size.z})
		else:
			out.append({"mesh": mesh, "full": full, "aabb": aabb, "size": size,
				"volume": size.x * size.y * size.z})
	return out


func _physics_material() -> PhysicsMaterial:
	var tuning := cfg()
	if _material == null:
		_material = PhysicsMaterial.new()
	_material.friction = tuning.piece_friction
	_material.bounce = tuning.piece_bounce
	return _material


func _random_unit() -> Vector3:
	var v := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0))
	return v.normalized() if v.length_squared() > 1e-6 else Vector3.UP


func _basis_y(direction: Vector3) -> Basis:
	var y := direction.normalized()
	if y.length_squared() < 1e-6:
		y = Vector3.UP
	var helper := Vector3.FORWARD if absf(y.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var x := helper.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## Пересобрать пулы под текущие числа настройки.
func _rebuild() -> void:
	var tuning := cfg()
	_built_for = tuning
	for emitter in _splinters:
		emitter.queue_free()
	for puff in _dust:
		puff.queue_free()
	for player in _players:
		player.queue_free()
	_splinters.clear()
	_dust.clear()
	_players.clear()
	for i in range(BURST_POOL):
		var splinters := _make_splinters(tuning)
		splinters.name = "Splinters_%d" % i
		add_child(splinters)
		_splinters.append(splinters)
		var dust := _make_dust(tuning)
		dust.name = "BreakDust_%d" % i
		add_child(dust)
		_dust.append(dust)
	for i in range(SOUND_SLOTS):
		var player := AudioStreamPlayer3D.new()
		player.name = "BreakSound_%d" % i
		player.max_polyphony = 1
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.max_distance = 140.0
		add_child(player)
		_players.append(player)


func _new_emitter(amount: int, lifetime: float) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.top_level = true
	emitter.local_coords = false
	emitter.one_shot = true
	emitter.emitting = false
	emitter.amount = maxi(1, amount)
	emitter.lifetime = maxf(lifetime, 0.05)
	emitter.explosiveness = 0.9
	emitter.randomness = 0.4
	emitter.interpolate = true
	emitter.visibility_aabb = AABB(Vector3(-12.0, -12.0, -12.0), Vector3(24.0, 24.0, 24.0))
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return emitter


func _make_splinters(tuning: RallyBreakableConfig) -> GPUParticles3D:
	var emitter := _new_emitter(tuning.splinter_amount, tuning.splinter_lifetime)
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 75.0
	process.initial_velocity_min = tuning.splinter_speed_min
	process.initial_velocity_max = maxf(tuning.splinter_speed_max, tuning.splinter_speed_min)
	process.gravity = Vector3(0.0, -9.8, 0.0)
	process.damping_min = 0.3
	process.damping_max = 1.2
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.angular_velocity_min = -900.0
	process.angular_velocity_max = 900.0
	process.particle_flag_rotate_y = true
	var base := maxf(tuning.splinter_size_m.y, 0.005)
	process.scale_min = clampf(tuning.splinter_size_m.x / base, 0.05, 1.0)
	process.scale_max = 1.0
	process.scale_curve = DustFx.debris_scale_curve()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.4, 0.35, 0.15)
	process.color = tuning.splinter_color
	emitter.process_material = process
	var mesh := BoxMesh.new()
	mesh.size = Vector3(base, base * 0.18, base * 0.35)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.9
	mesh.material = material
	emitter.draw_pass_1 = mesh
	return emitter


func _make_dust(tuning: RallyBreakableConfig) -> GPUParticles3D:
	var emitter := _new_emitter(tuning.dust_amount, 1.1)
	emitter.explosiveness = 0.85
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 80.0
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 2.0
	process.gravity = Vector3(0.0, 0.2, 0.0)
	process.damping_min = 1.5
	process.damping_max = 3.0
	process.scale_min = 0.7
	process.scale_max = 1.3
	process.scale_curve = DustFx.growth_curve(2.4)
	process.color = tuning.dust_color
	process.color_ramp = DustFx.fade_ramp()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.6, 0.2, 0.3)
	emitter.process_material = process
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * 0.7
	mesh.material = DustFx.puff_material(DustFx.puff_texture(), false)
	emitter.draw_pass_1 = mesh
	return emitter


## Синтезированный треск дерева: сухой щелчок, рваные «волокна» и глухой удар.
## Генерируется один раз на всю игру.
static func crack_stream() -> AudioStreamWAV:
	if _crack_stream != null:
		return _crack_stream
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var frames := int(0.55 * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var low := 0.0
	var band := 0.0
	var snap := 0.0
	for i in range(frames):
		var t := float(i) / SAMPLE_RATE
		var noise := rng.randf_range(-1.0, 1.0)
		low += (noise - low) * 0.18
		band += (noise - low - band) * 0.55
		# Волокна рвутся сериями: редкие щелчки, гуще в начале.
		if rng.randf() < 0.02 * exp(-t * 7.0) + 0.002:
			snap = rng.randf_range(0.5, 1.0) * exp(-t * 4.0)
		snap *= 0.86
		var thump := sin(TAU * 118.0 * t * (1.0 - t * 0.5)) * exp(-t * 16.0)
		var crack := band * exp(-t * 22.0) * 1.6
		var attack := minf(1.0, t * 900.0)
		samples[i] = (crack + snap * rng.randf_range(-1.0, 1.0) * 0.9 + thump * 0.7 + low * exp(-t * 9.0) * 0.4) * attack
	var peak := 0.001
	for s in samples:
		peak = maxf(peak, absf(s))
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in range(frames):
		data.encode_s16(i * 2, int(clampf(samples[i] * 0.9 / peak, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	_crack_stream = stream
	return stream
