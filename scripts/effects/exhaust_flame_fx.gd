## Выстрелы пламени из выхлопа (textures/fire.png): «антилаг» на сброс газа,
## очередь мелких хлопков, выстрел при переключении вверх и на отсечке.
##
## Ставится машиной (RallyCar._install_exhaust_flames) дочерним узлом.
## Настройка — RallyExhaustFlameConfig (res://data/car/default_exhaust_flame.tres
## или поле `exhaust_flame_config` у корня RallyCar).
##
## Язык пламени — два скрещённых прямоугольника с fire.png вдоль оси трубы
## (основание картинки у среза, кончик назад) и яркое ядро-билборд у среза.
## Все узлы создаются один раз (пул), во время езды только двигаются.
## На физику, мощность и звук мотора не влияет.
class_name ExhaustFlameFx
extends Node3D

## Выстрел: сила 0..1 (для проверок и эффектов поверх).
signal fired(strength: float)

var config: RallyExhaustFlameConfig = null
var car: Node3D = null

var _audio: Node = null
var _anchors: Array[Node3D] = []
var _flames: Array[Dictionary] = []
var _fireballs: Array[CPUParticles3D] = []
var _light: OmniLight3D = null
var _light_level := 0.0
var _jet_material: StandardMaterial3D = null
var _core_material: StandardMaterial3D = null
var _jet_mesh: ArrayMesh = null
var _core_mesh: QuadMesh = null
var _rng := RandomNumberGenerator.new()
var _cooldown := 0.0
var _crackle_left := 0.0
var _limiter_wait := 0.0
var _prev_throttle := 0.0
var _prev_rpm := 0.0
var _prev_gear := 0
var _shots := 0


## car — RallyCar, settings — настройка, audio — EngineAudio (может быть null).
func setup(p_car: Node3D, settings: RallyExhaustFlameConfig, audio: Node = null) -> void:
	car = p_car
	config = settings
	_rng.randomize()
	_build_materials()
	_build_outlets()
	_build_pool()
	_connect_audio(audio)
	if car != null:
		_prev_gear = int(car.get("current_gear"))


func cfg() -> RallyExhaustFlameConfig:
	if config == null:
		config = RallyExhaustFlameConfig.new()
	return config


## Сколько найдено труб.
func outlet_count() -> int:
	return _anchors.size()


## Срезы труб в координатах машины.
func outlets_local() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for anchor in _anchors:
		out.append(anchor.position)
	return out


## Сколько выстрелов было с последней очистки.
func shot_count() -> int:
	return _shots


## Сколько языков пламени горит прямо сейчас.
func active_flames() -> int:
	var count := 0
	for flame in _flames:
		if flame["active"]:
			count += 1
	return count


## Работает ли пламя на этой машине сейчас (пресет мотора может смениться).
func is_allowed() -> bool:
	if car == null:
		return false
	var setup_res = car.get("active_setup")
	var turbo := true
	if setup_res != null:
		turbo = bool(setup_res.get("turbo"))
	return cfg().applies_to(String(car.get("vehicle_id")), turbo)


## Выстрел силой 0..1 из всех труб. force — без паузы и проверки турбины.
func fire(strength: float, force: bool = false) -> bool:
	var tuning := cfg()
	if not force and (not is_allowed() or _cooldown > 0.0):
		return false
	if _anchors.is_empty() or _flames.is_empty():
		return false
	strength = clampf(strength, 0.05, 1.0)
	_cooldown = tuning.cooldown_sec
	_shots += 1
	for a in range(_anchors.size()):
		# Трубы стреляют почти одновременно, но не одинаково.
		_start_flame(a, strength * _rng.randf_range(0.8, 1.0))
		if (
			strength >= tuning.fireball_min_strength
			and tuning.fireball_enabled
			and a < _fireballs.size()
		):
			var fireball := _fireballs[a]
			fireball.restart()
			fireball.emitting = true
	if tuning.light_enabled and _light != null:
		_light_level = maxf(_light_level, strength)
	fired.emit(strength)
	return true


## Погасить всё (рестарт заезда).
func clear() -> void:
	for flame in _flames:
		flame["active"] = false
		(flame["root"] as Node3D).visible = false
	for fireball in _fireballs:
		fireball.emitting = false
	_light_level = 0.0
	if _light != null:
		_light.visible = false
	_crackle_left = 0.0
	_cooldown = 0.0
	_shots = 0


func _process(delta: float) -> void:
	if car == null:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	_update_triggers(delta)
	_update_flames(delta)
	_update_light(delta)


# ---------------------------------------------------------------------------
# Когда стрелять
# ---------------------------------------------------------------------------


func _update_triggers(delta: float) -> void:
	var tuning := cfg()
	var throttle := clampf(float(car.get("throttle_input")), 0.0, 1.0)
	var rpm := maxf(float(car.get("current_rpm")), 0.0)
	var gear := int(car.get("current_gear"))
	var shifting := bool(car.get("is_shifting"))
	if tuning.enabled:
		# Сброс газа: сам, если звук мотора не сообщает о хлопках.
		var lifted := (
			_prev_throttle >= tuning.lift_throttle_from and throttle < tuning.lift_throttle_to
		)
		if lifted and rpm >= tuning.lift_min_rpm:
			_crackle_left = tuning.crackle_duration_sec if tuning.crackle_enabled else 0.0
			if not _audio_drives_lift() and not shifting:
				fire(1.0)
		# Очередь мелких выстрелов, пока газ отпущен и обороты высоки.
		if throttle >= tuning.lift_throttle_from:
			_crackle_left = 0.0
		elif _crackle_left > 0.0:
			_crackle_left -= delta
			if rpm >= tuning.crackle_min_rpm and _rng.randf() < tuning.crackle_rate_hz * delta:
				fire(tuning.crackle_strength * _rng.randf_range(0.6, 1.0))
		# Переключение вверх под газом.
		if (
			tuning.upshift_enabled
			and gear > _prev_gear
			and _prev_gear > 0
			and _prev_rpm >= tuning.upshift_min_rpm
			and _prev_throttle >= tuning.lift_throttle_from
		):
			fire(tuning.upshift_strength)
		# Отсечка.
		if tuning.limiter_enabled and bool(car.get("motor_is_redline")) and throttle > 0.5:
			_limiter_wait -= delta
			if _limiter_wait <= 0.0:
				if fire(tuning.limiter_strength * _rng.randf_range(0.7, 1.0)):
					_limiter_wait = (
						1.0 / maxf(tuning.limiter_rate_hz, 0.1) * _rng.randf_range(0.6, 1.4)
					)
		else:
			_limiter_wait = 0.0
	_prev_throttle = throttle
	_prev_rpm = rpm
	_prev_gear = gear


func _audio_drives_lift() -> bool:
	return (
		cfg().sync_with_audio
		and _audio != null
		and is_instance_valid(_audio)
		and bool(_audio.get("enabled"))
		and bool(_audio.get("_audio_ready"))
	)


func _connect_audio(audio: Node) -> void:
	_audio = audio
	if (
		_audio != null
		and _audio.has_signal("exhaust_pop")
		and not _audio.is_connected("exhaust_pop", _on_audio_pop)
	):
		_audio.connect("exhaust_pop", _on_audio_pop)


func _on_audio_pop(strength: float) -> void:
	if cfg().sync_with_audio:
		fire(strength)


# ---------------------------------------------------------------------------
# Пламя
# ---------------------------------------------------------------------------


func _start_flame(anchor_index: int, strength: float) -> void:
	var tuning := cfg()
	# Свободный язык этой трубы, иначе самый старый.
	var pick := -1
	var oldest := -1.0
	for i in range(_flames.size()):
		var flame: Dictionary = _flames[i]
		if flame["anchor"] != anchor_index:
			continue
		if not flame["active"]:
			pick = i
			break
		if float(flame["age"]) > oldest:
			oldest = flame["age"]
			pick = i
	if pick < 0:
		return
	var item: Dictionary = _flames[pick]
	item["active"] = true
	item["age"] = 0.0
	item["life"] = tuning.flame_life_sec * lerpf(0.7, 1.15, strength) * _rng.randf_range(0.85, 1.15)
	item["length"] = (
		_rng.randf_range(tuning.flame_length_m.x, tuning.flame_length_m.y)
		* lerpf(0.45, 1.0, strength)
	)
	item["strength"] = strength
	var jitter := deg_to_rad(tuning.flame_jitter_deg)
	# Наклон вниз и случайный разброс; поворот вокруг оси — разный рисунок.
	item["basis"] = (
		Basis(
			Vector3.RIGHT,
			-deg_to_rad(tuning.flame_pitch_down_deg) + _rng.randf_range(-jitter, jitter)
		)
		* Basis(Vector3.UP, _rng.randf_range(-jitter, jitter))
		* Basis(Vector3.FORWARD, _rng.randf_range(0.0, TAU))
	)
	var root := item["root"] as Node3D
	root.visible = true
	_apply_flame(item)


func _update_flames(delta: float) -> void:
	for flame in _flames:
		if not flame["active"]:
			continue
		flame["age"] = float(flame["age"]) + delta
		if float(flame["age"]) >= float(flame["life"]):
			flame["active"] = false
			(flame["root"] as Node3D).visible = false
			continue
		_apply_flame(flame)


func _apply_flame(flame: Dictionary) -> void:
	var tuning := cfg()
	var t: float = clampf(float(flame["age"]) / maxf(float(flame["life"]), 0.001), 0.0, 1.0)
	var grow := smoothstep(0.0, maxf(tuning.flame_grow_part, 0.01), t)
	var length: float = float(flame["length"]) * lerpf(0.3, 1.0, grow) * lerpf(1.0, 1.15, t)
	var width: float = (
		length * tuning.flame_width_ratio * lerpf(0.75, 1.0, grow) * lerpf(1.0, 0.7, t)
	)
	var fade := clampf((t - 0.3) / 0.7, 0.0, 1.0)
	var root := flame["root"] as Node3D
	root.transform = Transform3D(flame["basis"], Vector3(0.0, 0.0, -tuning.flame_offset_m))
	var jet := flame["jet"] as MeshInstance3D
	jet.scale = Vector3(width, width, length)
	jet.transparency = fade
	var core := flame["core"] as MeshInstance3D
	var core_size: float = width * 0.7 * lerpf(1.0, 0.5, t)
	core.scale = Vector3.ONE * maxf(core_size, 0.001)
	core.transparency = clampf(t * 1.6, 0.0, 1.0)


func _update_light(delta: float) -> void:
	if _light == null:
		return
	var tuning := cfg()
	if _light_level <= 0.001 or not tuning.light_enabled:
		_light_level = 0.0
		_light.visible = false
		return
	_light.visible = true
	_light.light_energy = tuning.light_energy * _light_level * _rng.randf_range(0.8, 1.1)
	_light_level = maxf(0.0, _light_level - delta / maxf(tuning.flame_life_sec * 1.2, 0.02))


# ---------------------------------------------------------------------------
# Сборка
# ---------------------------------------------------------------------------


func _build_materials() -> void:
	var tuning := cfg()
	_jet_material = StandardMaterial3D.new()
	_jet_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_jet_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_jet_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_jet_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_jet_material.albedo_texture = tuning.flame_texture
	_jet_material.albedo_color = _energized(tuning.flame_color, tuning.flame_energy)
	_jet_material.disable_receive_shadows = true
	_jet_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_core_material = _jet_material.duplicate() as StandardMaterial3D
	_core_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_core_material.billboard_keep_scale = true
	_core_material.albedo_color = _energized(tuning.core_color, tuning.flame_energy)
	_jet_mesh = _make_jet_mesh()
	_core_mesh = QuadMesh.new()
	_core_mesh.size = Vector2.ONE


## Цвет с яркостью больше 1 (сложение даёт пересвет, как у настоящей вспышки).
static func _energized(color: Color, energy: float) -> Color:
	return Color(color.r * energy, color.g * energy, color.b * energy, color.a)


## Два скрещённых прямоугольника вдоль -Z длиной 1 и шириной 1: основание
## картинки (низ fire.png) у среза трубы, кончик пламени — на z = -1.
static func _make_jet_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for plane in range(2):
		var side := Vector3.RIGHT if plane == 0 else Vector3.UP
		var normal := Vector3.UP if plane == 0 else Vector3.RIGHT
		var base := verts.size()
		verts.append(-side * 0.5)
		verts.append(side * 0.5)
		verts.append(side * 0.5 + Vector3(0, 0, -1))
		verts.append(-side * 0.5 + Vector3(0, 0, -1))
		uvs.append(Vector2(0, 1))
		uvs.append(Vector2(1, 1))
		uvs.append(Vector2(1, 0))
		uvs.append(Vector2(0, 0))
		for i in range(4):
			normals.append(normal)
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_outlets() -> void:
	for anchor in _anchors:
		anchor.queue_free()
	_anchors.clear()
	var tuning := cfg()
	var outlets: Array[Transform3D] = []
	if car != null:
		var to_car := car.global_transform.affine_inverse()
		for node in car.find_children(tuning.outlet_marker_prefix + "*", "Node3D", true, false):
			var marker := node as Node3D
			if marker != null and not is_ancestor_of(marker):
				outlets.append((to_car * marker.global_transform).orthonormalized())
	if outlets.is_empty():
		for point in tuning.manual_outlets:
			outlets.append(Transform3D(_rear_basis(), point))
	if outlets.is_empty() and tuning.auto_detect:
		for point in detect_outlets(
			car,
			tuning.material_keywords,
			tuning.merge_distance_m,
			tuning.outlet_rear_zone_m,
			tuning.outlet_max_height_m
		):
			outlets.append(Transform3D(_rear_basis(), point))
	if outlets.is_empty():
		outlets.append(Transform3D(_rear_basis(), tuning.fallback_outlet))
	for i in range(outlets.size()):
		var anchor := Node3D.new()
		anchor.name = "Outlet_%d" % i
		anchor.transform = outlets[i]
		add_child(anchor)
		_anchors.append(anchor)


## Ось -Z якоря смотрит назад машины (перед машины — +Z): поворот не нужен.
static func _rear_basis() -> Basis:
	return Basis.IDENTITY


## Срезы выхлопных труб по материалам модели, в координатах машины.
## Вершины поверхностей с «выхлопными» материалами делятся на трубы по
## ширине (X); у каждой берётся самая задняя точка по центру сечения.
## Вершины выше max_height и дальше rear_zone от самой задней точки не
## считаются: тем же материалом бывают покрыты решётка, значок, молдинги.
static func detect_outlets(
	root: Node3D,
	keywords: Array[String],
	merge_distance: float,
	rear_zone: float = 0.6,
	max_height: float = 0.8
) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if root == null or keywords.is_empty():
		return out
	var to_root := root.global_transform.affine_inverse()
	var points: Array[Vector3] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := node as MeshInstance3D
		if mesh_inst == null or mesh_inst.mesh == null or not mesh_inst.is_visible_in_tree():
			continue
		var mesh := mesh_inst.mesh
		var xform := to_root * mesh_inst.global_transform
		for s in range(mesh.get_surface_count()):
			if not _surface_matches(mesh_inst, s, keywords):
				continue
			var arrays := mesh.surface_get_arrays(s)
			if arrays.is_empty() or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p := xform * v
				if p.y <= max_height:
					points.append(p)
	if points.is_empty():
		return out
	var rear := INF
	for p in points:
		rear = minf(rear, p.z)
	var rear_points: Array[Vector3] = []
	for p in points:
		if p.z <= rear + rear_zone:
			rear_points.append(p)
	points = rear_points
	points.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x < b.x)
	var cluster: Array[Vector3] = [points[0]]
	for i in range(1, points.size()):
		if points[i].x - points[i - 1].x > merge_distance:
			out.append(_cluster_outlet(cluster))
			cluster = []
		cluster.append(points[i])
	out.append(_cluster_outlet(cluster))
	return out


static func _surface_matches(
	mesh_inst: MeshInstance3D, surface: int, keywords: Array[String]
) -> bool:
	var names: Array[String] = []
	var mesh := mesh_inst.mesh
	if mesh is ArrayMesh:
		names.append((mesh as ArrayMesh).surface_get_name(surface))
	var material: Material = mesh_inst.get_surface_override_material(surface)
	if material == null:
		material = mesh.surface_get_material(surface)
	if material != null:
		names.append(material.resource_name)
	for name_text in names:
		var lower := name_text.to_lower()
		for keyword in keywords:
			if not keyword.is_empty() and lower.contains(keyword.to_lower()):
				return true
	return false


## Срез трубы: центр сечения у самого заднего края (перед машины — +Z).
static func _cluster_outlet(points: Array[Vector3]) -> Vector3:
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	# Сечение у среза: точки в последних 4 см трубы.
	var rear := box.position.z
	var center := Vector3.ZERO
	var count := 0
	for p in points:
		if p.z <= rear + 0.04:
			center += p
			count += 1
	center /= float(maxi(count, 1))
	return Vector3(center.x, center.y, rear)


func _build_pool() -> void:
	for flame in _flames:
		(flame["root"] as Node3D).queue_free()
	_flames.clear()
	for fireball in _fireballs:
		fireball.queue_free()
	_fireballs.clear()
	var tuning := cfg()
	for a in range(_anchors.size()):
		for i in range(tuning.flames_per_outlet):
			var root := Node3D.new()
			root.name = "Flame_%d" % i
			root.visible = false
			_anchors[a].add_child(root)
			var jet := MeshInstance3D.new()
			jet.name = "Jet"
			jet.mesh = _jet_mesh
			jet.material_override = _jet_material
			jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(jet)
			var core := MeshInstance3D.new()
			core.name = "Core"
			core.mesh = _core_mesh
			core.material_override = _core_material
			core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(core)
			_flames.append(
				{
					"root": root,
					"jet": jet,
					"core": core,
					"anchor": a,
					"active": false,
					"age": 0.0,
					"life": 0.1,
					"length": 0.5,
					"strength": 1.0,
					"basis": Basis.IDENTITY
				}
			)
		if tuning.fireball_enabled:
			_fireballs.append(_make_fireball(_anchors[a]))
	if tuning.light_enabled and not _anchors.is_empty():
		_light = OmniLight3D.new()
		_light.name = "FlameLight"
		var middle := Vector3.ZERO
		for anchor in _anchors:
			middle += anchor.position
		_light.position = middle / float(_anchors.size()) + Vector3(0.0, 0.1, -0.35)
		_light.light_color = tuning.light_color
		_light.omni_range = tuning.light_range_m
		_light.shadow_enabled = tuning.light_shadows
		_light.visible = false
		add_child(_light)


func _make_fireball(anchor: Node3D) -> CPUParticles3D:
	var tuning := cfg()
	var particles := CPUParticles3D.new()
	particles.name = "Fireball"
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = maxi(1, tuning.fireball_amount)
	particles.lifetime = tuning.fireball_life_sec
	particles.local_coords = true
	particles.direction = Vector3(0, 0, -1)
	particles.spread = 22.0
	particles.gravity = Vector3(0, 0.8, 0)
	particles.initial_velocity_min = tuning.fireball_speed_mps * 0.5
	particles.initial_velocity_max = tuning.fireball_speed_mps
	particles.scale_amount_min = tuning.fireball_size_m.x
	particles.scale_amount_max = tuning.fireball_size_m.y
	particles.angle_min = -180.0
	particles.angle_max = 180.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1.0, 1.3))
	particles.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.8, 1.0))
	ramp.set_color(1, Color(1.0, 0.35, 0.1, 0.0))
	ramp.add_point(0.35, Color(1.0, 0.6, 0.25, 0.85))
	particles.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = tuning.flame_texture
	material.albedo_color = _energized(Color.WHITE, tuning.flame_energy * 0.7)
	material.disable_receive_shadows = true
	quad.material = material
	particles.mesh = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	anchor.add_child(particles)
	return particles
