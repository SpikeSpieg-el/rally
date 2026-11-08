## Пятна крови на кузове, бампере и стекле. Сцена `scenes/effects/blood_stains.tscn` —
## пульт: цвет, блеск, размер пятна, какие меши пачкать. Всплеск частиц живёт
## отдельно в `scenes/effects/blood_burst.tscn` и инстансируется при ударе.
@tool
class_name RallyBloodFx
extends Node

const BloodShader = preload("res://shaders/car_blood.gdshader")
const PuddleShader = preload("res://shaders/blood_puddle.gdshader")
const DEFAULT_BURST := "res://scenes/effects/blood_burst.tscn"
const BURST_POOL_NAME := "BloodBurstPool"
const PREWARM_META := "blood_prewarm"
const PREWARM_LOCAL := Vector3(0.0, 0.55, 0.4)
const PREWARM_SECONDS := 1.7
const WARM_SPRITE_NAME := "BloodSpriteWarmup"
const SPLAT_CAP := 8
const DECAL_CAP := 12
const BLOCKER_NAME := "BloodParticleBlocker"
const GLASS_NAME := "BloodGlassSmear"
const LAYER_NAME := "BloodLayer"

const GLASS_WIPER_SHADER_CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4 blood_color : source_color = vec4(0.40, 0.025, 0.04, 0.9);
uniform float dirt_amount : hint_range(0.0, 1.0) = 0.0;
uniform float wipe_clean : hint_range(0.0, 1.0) = 0.0;
uniform float wiper_pos : hint_range(0.0, 1.0) = 0.0;
uniform float swept_max : hint_range(0.0, 1.0) = 0.0;
uniform float wiper_active : hint_range(0.0, 1.0) = 0.0;
uniform float angle_park = -1.43;
uniform float angle_top = 0.17;
uniform float hit_side : hint_range(-1.0, 1.0) = 0.0;
uniform float splat_seed = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * noise2(p);
		p *= 2.07;
		amp *= 0.5;
	}
	return v;
}

// Расчёт одного дворника в координатах стекла p (x: -1..1, y: 0..1 снизу вверх)
void eval_wiper(
	vec2 p,
	vec2 pivot,
	float a_park,
	float a_top,
	float w_pos,
	float s_max,
	out float in_sector,
	out float is_swept,
	out float arc_streak,
	out float rim_mask,
	out float blade_line
) {
	vec2 d = p - pivot;
	float r = length(d);
	float ang = atan(d.x, d.y);

	float r_min = 0.14;
	float r_max = 0.88;
	float radial = smoothstep(r_min - 0.03, r_min + 0.02, r) * (1.0 - smoothstep(r_max - 0.03, r_max + 0.02, r));

	float span = a_top - a_park;
	float dir = sign(span);
	float span_abs = max(abs(span), 0.05);
	float t_px = ((ang - a_park) * dir) / span_abs;

	float angular = smoothstep(-0.03, 0.02, t_px) * (1.0 - smoothstep(0.98, 1.04, t_px));
	in_sector = radial * angular;

	// Где щётка уже успела пройти с момента удара
	float passed = 1.0 - smoothstep(s_max - 0.02, s_max + 0.02, t_px);
	is_swept = in_sector * passed * step(0.005, s_max);

	// Концентрические дуговые следы-полосы вдоль радиуса щётки
	float ring_n1 = noise2(vec2(r * 52.0 + splat_seed * 1.7, t_px * 3.5));
	float ring_n2 = noise2(vec2(r * 135.0 - splat_seed * 2.3, t_px * 6.0));
	float grooves = pow(clamp(ring_n1 * 0.65 + ring_n2 * 0.55, 0.0, 1.0), 2.2);
	arc_streak = is_swept * grooves;

	// Кровавая кромка (валик) по внешнему/внутреннему радиусу и на краях разворота щётки
	float outer_rim = exp(-pow((r - r_max) / 0.028, 2.0)) * angular * step(0.02, s_max);
	float inner_rim = exp(-pow((r - r_min) / 0.022, 2.0)) * angular * step(0.02, s_max);
	float stop_rim = exp(-pow((t_px - s_max) / 0.026, 2.0)) * radial * step(0.02, s_max);
	float park_rim = exp(-pow(t_px / 0.026, 2.0)) * radial * step(0.02, s_max);
	rim_mask = clamp(outer_rim + inner_rim * 0.7 + stop_rim * 0.9 + park_rim * 0.5, 0.0, 1.0);

	// Мокрый след прямо на лезвии движущейся щётки
	blade_line = in_sector * exp(-pow((t_px - w_pos) / 0.022, 2.0)) * wiper_active;
}

void fragment() {
	if (dirt_amount <= 0.001) {
		ALPHA = 0.0;
	} else {
		// p.x: -1.1 .. +1.1, p.y: 0.0 (низ стекла) .. 1.0 (верх стекла)
		vec2 p = vec2((UV.x - 0.5) * 2.2, 1.0 - UV.y);

		// Органическая форма брызг крови на стекле
		vec2 seed_ofs = vec2(splat_seed * 3.17, splat_seed * 5.71);
		float n_big = fbm(p * 3.2 + seed_ofs);
		float n_fine = fbm(p * 9.5 - seed_ofs * 1.4);

		// Основное пятно со стороны удара + разлёт брызг на обе половины стекла
		vec2 c1 = vec2(hit_side * 0.42, 0.42);
		vec2 c2 = vec2(-hit_side * 0.25, 0.36);
		vec2 c3 = vec2(hit_side * 0.15, 0.62);

		float d1 = length((p - c1) * vec2(0.85, 1.15)) - n_big * 0.38 - n_fine * 0.14;
		float d2 = length((p - c2) * vec2(0.95, 1.25)) - n_big * 0.34 - n_fine * 0.14;
		float d3 = length((p - c3) * vec2(0.80, 1.10)) - n_big * 0.30;

		float splat1 = 1.0 - smoothstep(0.18, 0.52, d1);
		float splat2 = (1.0 - smoothstep(0.14, 0.46, d2)) * 0.85;
		float splat3 = (1.0 - smoothstep(0.12, 0.42, d3)) * 0.75;
		// Мелкие капли по всему стеклу (особенно видны по углам)
		float droplets = smoothstep(0.64, 0.78, n_fine + n_big * 0.35) * smoothstep(1.15, 0.2, length(p - vec2(0.0, 0.45)));

		float raw_blood = clamp(max(max(splat1, splat2), splat3) + droplets * 0.65, 0.0, 1.0);
		raw_blood *= dirt_amount;

		// Два дворника: левый и правый пивоты у нижней кромки стекла
		float in_l, swept_l, streak_l, rim_l, blade_l;
		float in_r, swept_r, streak_r, rim_r, blade_r;

		eval_wiper(p, vec2(-0.38, -0.06), angle_park, angle_top, wiper_pos, swept_max, in_l, swept_l, streak_l, rim_l, blade_l);
		eval_wiper(p, vec2(0.26, -0.06), angle_park, angle_top, wiper_pos, swept_max, in_r, swept_r, streak_r, rim_r, blade_r);

		float swept = clamp(swept_l + swept_r, 0.0, 1.0);
		float streaks = max(streak_l, streak_r);
		float rims = clamp(rim_l + rim_r, 0.0, 1.0);
		float blade = clamp(blade_l + blade_r, 0.0, 1.0);

		// Насколько в точке было много крови, чтобы размазывать её по дуге
		float blood_presence = smoothstep(0.05, 0.35, raw_blood + 0.25 * dirt_amount);

		// 1. Непротёртая кровь (в углах стекла и там, куда щётка ещё не дошла)
		// Внутри протёртого сектора густая кровь срезается щёткой:
		float unwiped_blood = raw_blood * (1.0 - swept * (0.72 + 0.28 * wipe_clean));

		// 2. Дуговые полосы-разводы от щётки внутри сектора (остаются видимыми следами!)
		float streak_intensity = streaks * blood_presence * mix(0.85, 0.32, wipe_clean);

		// 3. Сдвинутый щёткой контур крови по краям дуги
		float rim_intensity = rims * blood_presence * mix(0.95, 0.62, wipe_clean * 0.7);

		// 4. Мокрый валик прямо перед движущейся щёткой
		float blade_intensity = blade * blood_presence * 0.85;

		float final_alpha = clamp(unwiped_blood + streak_intensity + rim_intensity + blade_intensity, 0.0, 1.0);
		// Плавное затухание у самых краёв квада
		float edge_fade = smoothstep(0.0, 0.06, UV.x) * smoothstep(1.0, 0.94, UV.x)
			* smoothstep(0.0, 0.06, UV.y) * smoothstep(1.0, 0.94, UV.y);

		// Чуть темнее и гуще на кромках дуги, чуть светлее в тонких разводах
		vec3 col = blood_color.rgb;
		col = mix(col * 1.15, col * 0.65, clamp(rim_intensity + unwiped_blood * 0.5, 0.0, 1.0));

		ALBEDO = col;
		ALPHA = final_alpha * blood_color.a * edge_fade;
	}
}
"""

@export_group("Вкл и цвет")
@export var enabled: bool = true
@export var blood_color: Color = Color(0.40, 0.025, 0.04, 1.0)
@export_range(0.0, 1.0, 0.01) var blood_gloss: float = 0.42
@export_multiline var description: String = "Пятна на бампере, кузове и стекле. Всплеск — сцена Blood Burst."

@export_group("Всплеск")
@export var burst_scene: PackedScene

@export_group("Какие меши пачкать")
@export var body_prefixes: PackedStringArray = PackedStringArray(["Mitsubishi_Body"])
@export var body_skip: PackedStringArray = PackedStringArray(
	["wheel", "light", "disc", "tire", "cabin", "seat", "interior", "cockpit", "charm", "robe"]
)

@export_group("Размер пятна от скорости")
@export var amount_from_speed: Vector2 = Vector2(0.82, 0.012)
@export var radius_from_speed: Vector2 = Vector2(0.34, 0.007)
@export var stretch_from_speed: Vector2 = Vector2(1.25, 0.04)
@export var amount_limits: Vector2 = Vector2(0.65, 1.0)
@export var radius_limits: Vector2 = Vector2(0.28, 0.82)
@export var stretch_limits: Vector2 = Vector2(1.15, 3.4)

@export_group("Куда класть на кузове")
@export var splat_min: Vector3 = Vector3(-1.05, 0.08, -2.20)
@export var splat_max: Vector3 = Vector3(1.05, 1.38, 2.35)
@export var bumper_point: Vector3 = Vector3(0.0, 0.34, 2.08)
@export var hood_point: Vector3 = Vector3(0.0, 0.62, 1.48)
@export var glass_point: Vector3 = Vector3(0.0, 1.14, 0.96)
@export var glass_extent: Vector2 = Vector2(1.32, 0.58)

var _material: ShaderMaterial
var _glass_shader: Shader
var _splat_pos: Array[Vector3] = []
var _splat_dir: Array[Vector3] = []
var _splat_data: Array[Vector4] = []
var _next_splat: int = 0
var _decals: Array[Decal] = []
var _next_decal: int = 0
var _stain_tex: Texture2D
var _rng := RandomNumberGenerator.new()
var _car: Node3D = null
var _smear: MeshInstance3D = null
var _decal_glass: Array[bool] = []

## Состояние стекла для дуговых следов дворников:
var _glass_dirt: float = 0.0
var _glass_wetness: float = 0.0
var _wipe_clean: float = 0.0
var _swept_max: float = 0.0
var _wiper_pos: float = 0.0
var _splat_seed: float = 1.0
var _hit_side: float = 0.0


func install(car: Node3D) -> void:
	_car = car
	_rng.seed = int(Time.get_ticks_usec()) ^ int(car.get_instance_id()) ^ 911
	_splat_pos.resize(SPLAT_CAP)
	_splat_dir.resize(SPLAT_CAP)
	_splat_data.resize(SPLAT_CAP)
	for i in range(SPLAT_CAP):
		_splat_pos[i] = Vector3.ZERO
		_splat_dir[i] = Vector3(0.0, 0.0, 1.0)
		_splat_data[i] = Vector4.ZERO
	_material = ShaderMaterial.new()
	_material.shader = BloodShader
	_material.set_shader_parameter("world_to_car", car.global_transform.affine_inverse())
	_write_look()
	_write_splats()
	_attach_to_body(car)
	ensure_particle_blocker(car)
	_stain_texture()
	_prime_glass_smear(car)
	_prime_decals(car)
	_prime_warm_sprite(car)
	_install_burst_pool(car)


func add_splat(car: Node3D, world_point: Vector3, world_velocity: Vector3) -> void:
	if not enabled:
		return
	if _material == null:
		install(car)
	var local_hit: Vector3 = car.to_local(world_point)
	local_hit.x = clampf(local_hit.x, splat_min.x, splat_max.x)
	local_hit.y = clampf(local_hit.y, splat_min.y, splat_max.y)
	local_hit.z = clampf(local_hit.z, splat_min.z, splat_max.z)
	var local_dir: Vector3 = car.global_transform.basis.inverse() * world_velocity
	if local_dir.length() < 0.4:
		local_dir = Vector3(local_hit.x, 0.12, 1.0)
	local_dir = local_dir.normalized()
	var speed: float = world_velocity.length()
	var amount: float = clampf(amount_from_speed.x + speed * amount_from_speed.y, amount_limits.x, amount_limits.y)
	var radius: float = clampf(radius_from_speed.x + speed * radius_from_speed.y, radius_limits.x, radius_limits.y)
	var stretch: float = clampf(stretch_from_speed.x + speed * stretch_from_speed.y, stretch_limits.x, stretch_limits.y)
	var side: float = clampf(local_hit.x, -0.45, 0.45)
	var edge_side: float = -0.52 if side < 0.0 else 0.52

	# Следы на кузове, бампере, капоте и по стойкам/краям стекла
	_store_splat(local_hit, local_dir, amount, radius, stretch)
	_store_splat(Vector3(side * 0.55, bumper_point.y, bumper_point.z), Vector3(0.0, 0.12, 1.0), amount, radius * 1.15, stretch * 0.85)
	_store_splat(Vector3(side * 0.4, hood_point.y, hood_point.z), Vector3(0.0, 0.35, 0.8), amount * 0.9, radius * 1.05, stretch)
	# На самом стекле краевые брызги ближе к стойкам, а центр рисует шейдер дворников:
	_store_splat(Vector3(edge_side, glass_point.y + 0.12, glass_point.z), Vector3(0.0, 0.45, 0.7), amount * 0.75, radius * 0.75, stretch * 0.7)
	_write_look()
	_write_splats()
	_attach_to_body(car)
	_add_decal(car, local_hit, Vector3(-local_hit.x, 0.1, -local_hit.z), radius * 1.6)
	_add_decal(car, Vector3(side * 0.45, bumper_point.y, bumper_point.z), Vector3(0.0, 0.08, -1.0), radius * 1.8)
	_add_decal(car, Vector3(side * 0.3, hood_point.y, hood_point.z), Vector3(0.0, -1.0, -0.15), radius * 1.5)
	_add_decal(car, Vector3(edge_side, glass_point.y + 0.10, glass_point.z), Vector3(0.0, -0.2, -1.0), radius * 0.9)
	_ensure_glass_smear(car, side)


func update(car: Node3D) -> void:
	if _material == null or car == null:
		return
	_material.set_shader_parameter("world_to_car", car.global_transform.affine_inverse())


static func spray(host: Node, world_point: Vector3, world_velocity: Vector3, scene: PackedScene = null) -> void:
	if host == null or not is_instance_valid(host):
		return
	var burst := _burst_for(host, scene)
	if burst == null:
		return
	if burst.has_meta(PREWARM_META):
		_finish_prewarm(burst)
	if burst.get_parent() != host:
		host.add_child(burst)
	burst.top_level = false
	burst.global_position = world_point
	if host is Node3D:
		ensure_particle_blocker(host as Node3D)
	var away := Vector3.ZERO
	if host is Node3D:
		away = world_point - (host as Node3D).global_position
	if burst.has_method("play"):
		burst.call("play", world_velocity, away)


static func _burst_for(host: Node, scene: PackedScene) -> Node3D:
	var pooled := host.get_node_or_null(BURST_POOL_NAME) as Node3D
	if pooled != null:
		return pooled
	var packed: PackedScene = scene
	if packed == null and ResourceLoader.exists(DEFAULT_BURST):
		packed = load(DEFAULT_BURST) as PackedScene
	if packed == null:
		return null
	var burst := packed.instantiate() as Node3D
	if burst == null:
		return null
	burst.name = "BloodBurst"
	return burst


static func _install_burst_pool(car: Node3D) -> void:
	if car.get_node_or_null(BURST_POOL_NAME) != null:
		return
	if not ResourceLoader.exists(DEFAULT_BURST):
		return
	var packed := load(DEFAULT_BURST) as PackedScene
	if packed == null:
		return
	var burst := packed.instantiate() as Node3D
	if burst == null:
		return
	burst.name = BURST_POOL_NAME
	car.add_child(burst)
	burst.top_level = false
	burst.set("free_after", 0.0)
	burst.position = PREWARM_LOCAL
	_prewarm_burst(burst)


static func _prewarm_burst(burst: Node3D) -> void:
	if Engine.is_editor_hint():
		return
	if burst == null or not is_instance_valid(burst) or not burst.is_inside_tree():
		return
	var saved: Dictionary = {}
	for path in [^"Droplets", ^"Mist"]:
		var particles := burst.get_node_or_null(path) as GPUParticles3D
		if particles == null:
			continue
		var mat := particles.process_material as ParticleProcessMaterial
		if mat == null:
			continue
		saved[String(path)] = [mat.initial_velocity_min, mat.initial_velocity_max, mat.gravity]
		mat.initial_velocity_min = 0.0
		mat.initial_velocity_max = 0.0
		mat.gravity = Vector3.ZERO
	burst.set_meta(PREWARM_META, saved)
	if burst.has_method("play"):
		burst.call("play", Vector3.ZERO, Vector3.ZERO)
	var tree := burst.get_tree()
	if tree == null:
		_finish_prewarm(burst)
		return
	var timer := tree.create_timer(PREWARM_SECONDS)
	timer.timeout.connect(func() -> void: _finish_prewarm(burst))


static func _finish_prewarm(burst: Node3D) -> void:
	if burst == null or not is_instance_valid(burst):
		return
	if not burst.has_meta(PREWARM_META):
		return
	var saved: Variant = burst.get_meta(PREWARM_META)
	burst.remove_meta(PREWARM_META)
	if not (saved is Dictionary):
		return
	var values_by_path := saved as Dictionary
	for path in [^"Droplets", ^"Mist"]:
		var key := String(path)
		if not values_by_path.has(key):
			continue
		var values: Variant = values_by_path[key]
		if not (values is Array) or (values as Array).size() < 3:
			continue
		var particles := burst.get_node_or_null(path) as GPUParticles3D
		if particles == null:
			continue
		var mat := particles.process_material as ParticleProcessMaterial
		if mat == null:
			continue
		var trio := values as Array
		mat.initial_velocity_min = float(trio[0])
		mat.initial_velocity_max = float(trio[1])
		mat.gravity = trio[2] as Vector3


static func ensure_particle_blocker(car: Node3D) -> void:
	if car == null or not is_instance_valid(car):
		return
	if car.get_node_or_null(BLOCKER_NAME) != null:
		return
	var blocker := GPUParticlesCollisionBox3D.new()
	blocker.name = BLOCKER_NAME
	blocker.size = Vector3(1.85, 1.35, 4.35)
	blocker.position = Vector3(0.0, 0.52, 0.05)
	car.add_child(blocker)


func _store_splat(local_point: Vector3, local_dir: Vector3, amount: float, radius: float, stretch: float) -> void:
	var point: Vector3 = Vector3(
		clampf(local_point.x, splat_min.x, splat_max.x),
		clampf(local_point.y, splat_min.y, splat_max.y),
		clampf(local_point.z, splat_min.z, splat_max.z)
	)
	var direction: Vector3 = local_dir
	if direction.length() < 0.2:
		direction = Vector3(0.0, 0.15, 1.0)
	direction = direction.normalized()
	var index: int = _next_splat
	_next_splat = (_next_splat + 1) % SPLAT_CAP
	_splat_pos[index] = point
	_splat_dir[index] = direction
	_splat_data[index] = Vector4(amount, radius, stretch, _rng.randf() * 31.0)


func _write_look() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("blood_color", Vector3(blood_color.r, blood_color.g, blood_color.b))
	_material.set_shader_parameter("blood_gloss", blood_gloss)


func _write_splats() -> void:
	if _material == null:
		return
	var positions := PackedVector3Array()
	var directions := PackedVector3Array()
	var data := PackedVector4Array()
	positions.resize(SPLAT_CAP)
	directions.resize(SPLAT_CAP)
	data.resize(SPLAT_CAP)
	for i in range(SPLAT_CAP):
		positions[i] = _splat_pos[i] if i < _splat_pos.size() else Vector3.ZERO
		directions[i] = _splat_dir[i] if i < _splat_dir.size() else Vector3(0.0, 0.0, 1.0)
		data[i] = _splat_data[i] if i < _splat_data.size() else Vector4.ZERO
	_material.set_shader_parameter("splat_pos", positions)
	_material.set_shader_parameter("splat_dir", directions)
	_material.set_shader_parameter("splat_data", data)


func _attach_to_body(car: Node) -> void:
	if _material == null:
		return
	for mesh in _body_meshes(car):
		var layer := mesh.get_node_or_null(LAYER_NAME) as MeshInstance3D
		if layer == null:
			layer = MeshInstance3D.new()
			layer.name = LAYER_NAME
			mesh.add_child(layer)
			layer.mesh = mesh.mesh
			layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			layer.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			layer.position = Vector3.ZERO
			layer.rotation = Vector3.ZERO
			layer.scale = Vector3.ONE
			layer.extra_cull_margin = 0.45
		layer.material_override = _material


func _add_decal(car: Node3D, local_point: Vector3, into: Vector3, span: float) -> void:
	if car == null:
		return
	var inward: Vector3 = into
	if inward.length() < 0.08:
		inward = Vector3(0.0, 0.0, -1.0)
	inward = inward.normalized()
	var on_glass: bool = _is_glass_zone(local_point)
	var decal: Decal
	if _decals.size() < DECAL_CAP:
		decal = Decal.new()
		decal.name = "BloodDecal%d" % _decals.size()
		decal.texture_albedo = _stain_texture()
		decal.cull_mask = 0xFFFFF
		car.add_child(decal)
		_decals.append(decal)
		_decal_glass.append(on_glass)
	else:
		var index: int = _next_decal
		_next_decal = (_next_decal + 1) % _decals.size()
		decal = _decals[index]
		if index < _decal_glass.size():
			_decal_glass[index] = on_glass
	decal.modulate = Color(blood_color.r, blood_color.g, blood_color.b, 0.92)
	decal.albedo_mix = 0.9
	decal.normal_fade = 0.55
	decal.upper_fade = 0.35
	decal.lower_fade = 0.35
	var y_axis: Vector3 = -inward
	var x_axis: Vector3 = y_axis.cross(Vector3.UP)
	if x_axis.length_squared() < 0.04:
		x_axis = y_axis.cross(Vector3.FORWARD)
	x_axis = x_axis.normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	decal.transform = Transform3D(Basis(x_axis, y_axis, z_axis), local_point - inward * 0.1)
	var extent: float = clampf(span, 0.45, 1.35)
	decal.size = Vector3(extent, 0.42, extent * 0.72)


func _get_glass_shader() -> Shader:
	if _glass_shader == null:
		_glass_shader = Shader.new()
		_glass_shader.code = GLASS_WIPER_SHADER_CODE
	return _glass_shader


func _ensure_glass_smear(car: Node3D, local_x: float) -> void:
	var smear := car.get_node_or_null(GLASS_NAME) as MeshInstance3D
	if smear == null:
		smear = MeshInstance3D.new()
		smear.name = GLASS_NAME
		var quad := QuadMesh.new()
		quad.size = Vector2(maxf(glass_extent.x, 1.32), maxf(glass_extent.y, 0.58))
		var paint := ShaderMaterial.new()
		paint.shader = _get_glass_shader()
		quad.material = paint
		smear.mesh = quad
		smear.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		smear.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		car.add_child(smear)
	_smear = smear
	_hit_side = clampf(local_x / 0.45, -1.0, 1.0)
	_splat_seed = _rng.randf_range(1.0, 25.0)
	_glass_dirt = 1.0
	_glass_wetness = 1.0
	_wipe_clean = 0.0
	_swept_max = 0.0
	smear.position = Vector3(0.0, glass_point.y, glass_point.z)
	smear.rotation_degrees = Vector3(-16.0, 0.0, 0.0)
	smear.visible = true
	_sync_glass_shader(0.0)


func _sync_glass_shader(active_val: float) -> void:
	if _smear == null or not is_instance_valid(_smear):
		return
	var paint := (_smear.mesh as QuadMesh).material as ShaderMaterial
	if paint == null:
		return
	paint.set_shader_parameter("blood_color", Color(blood_color.r, blood_color.g, blood_color.b, 0.92))
	paint.set_shader_parameter("dirt_amount", _glass_dirt)
	paint.set_shader_parameter("wipe_clean", _wipe_clean)
	paint.set_shader_parameter("wiper_pos", _wiper_pos)
	paint.set_shader_parameter("swept_max", _swept_max)
	paint.set_shader_parameter("wiper_active", active_val)
	paint.set_shader_parameter("hit_side", _hit_side)
	paint.set_shader_parameter("splat_seed", _splat_seed)


## Вызывается каждый кадр из RallyWindshieldWipers во время хода щёток:
## двигает границу среза и мокрый след прямо за 3D-щётками.
func set_wiper_state(k: float, park_rad: float, top_rad: float, active: bool, delta: float = 0.016) -> void:
	if _smear == null or not is_instance_valid(_smear):
		return
	_wiper_pos = clampf(k, 0.0, 1.0)
	if active:
		_swept_max = maxf(_swept_max, _wiper_pos)
		_wipe_clean = clampf(_wipe_clean + delta * 0.42, 0.0, 1.0)
	var paint := (_smear.mesh as QuadMesh).material as ShaderMaterial
	if paint != null:
		paint.set_shader_parameter("angle_park", park_rad)
		paint.set_shader_parameter("angle_top", top_rad)
	_sync_glass_shader(1.0 if active else 0.0)


func _is_glass_zone(point: Vector3) -> bool:
	return point.y >= glass_point.y - 0.30 \
		and point.z >= glass_point.z - 0.60 \
		and point.z <= glass_point.z + 0.90


## Есть ли на лобовом стекле ещё свежая неразмазанная кровь, требующая работы щёток.
func glass_dirty() -> bool:
	if not enabled:
		return false
	return _glass_wetness > 0.06


## Завершение очередного прохода щёток: уменьшаем свежесть крови, но НЕ прячем
## дуговые разводы, кромку взмаха и брызги в углах стекла.
func wipe_glass(strength: float = 0.5) -> void:
	if not enabled:
		return
	var k: float = clampf(strength, 0.0, 1.0)
	if k <= 0.0:
		return
	_swept_max = 1.0
	_glass_wetness *= (1.0 - k)
	if _glass_wetness < 0.06:
		_glass_wetness = 0.0
	_wipe_clean = clampf(_wipe_clean + k * 0.55, 0.0, 1.0)
	_sync_glass_shader(0.0)

	# На кузове и декалях в зоне стекла немного приглушаем центральную часть,
	# но оставляем часть крови по краям (~25%), чтобы углы не становились стерильными.
	var changed := false
	for i in range(SPLAT_CAP):
		if _splat_data[i].x <= 0.02 or not _is_glass_zone(_splat_pos[i]):
			continue
		var data := _splat_data[i]
		data.x = maxf(0.22, data.x * (1.0 - k * 0.5))
		_splat_data[i] = data
		changed = true
	if changed:
		_write_splats()
	for i in range(_decals.size()):
		if i >= _decal_glass.size() or not _decal_glass[i]:
			continue
		var decal := _decals[i]
		if decal == null or not is_instance_valid(decal):
			continue
		var tint_decal := decal.modulate
		tint_decal.a = maxf(0.25, tint_decal.a * (1.0 - k * 0.5))
		decal.modulate = tint_decal


func _prime_glass_smear(car: Node3D) -> void:
	_ensure_glass_smear(car, 0.0)
	_glass_dirt = 0.0
	_glass_wetness = 0.0
	_sync_glass_shader(0.0)


func _prime_decals(car: Node3D) -> void:
	while _decals.size() < DECAL_CAP:
		var decal := Decal.new()
		decal.name = "BloodDecal%d" % _decals.size()
		decal.texture_albedo = _stain_texture()
		decal.cull_mask = 0xFFFFF
		decal.modulate = Color(1.0, 1.0, 1.0, 0.0)
		decal.size = Vector3(0.05, 0.05, 0.05)
		car.add_child(decal)
		_decals.append(decal)
		_decal_glass.append(false)


func _prime_warm_sprite(car: Node3D) -> void:
	if car.get_node_or_null(WARM_SPRITE_NAME) != null:
		return
	var warm := Sprite3D.new()
	warm.name = WARM_SPRITE_NAME
	warm.texture = _stain_texture()
	warm.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	warm.pixel_size = 0.001
	warm.modulate = Color(1.0, 1.0, 1.0, 0.0)
	warm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	warm.position = PREWARM_LOCAL
	car.add_child(warm)


func _stain_texture() -> Texture2D:
	if _stain_tex != null:
		return _stain_tex
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.2, 0.55, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.45, 0.03, 0.045, 0.95),
		Color(0.34, 0.02, 0.03, 0.72),
		Color(0.2, 0.01, 0.02, 0.28),
		Color(0.08, 0.0, 0.0, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	_stain_tex = tex
	return _stain_tex


func _body_meshes(car: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	_collect_meshes(car, car, result)
	return result


func _collect_meshes(node: Node, car: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if String(mesh_node.name) != LAYER_NAME and String(mesh_node.name) != GLASS_NAME:
			if not _is_skipped(mesh_node, car):
				var mesh_id := String(mesh_node.name)
				var matches := body_prefixes.is_empty()
				for prefix in body_prefixes:
					if mesh_id.begins_with(String(prefix)):
						matches = true
						break
				if matches or mesh_node.material_overlay != null:
					result.append(mesh_node)
	for child in node.get_children():
		_collect_meshes(child, car, result)


func _is_skipped(mesh_node: Node, car: Node) -> bool:
	var cursor: Node = mesh_node
	while cursor != null and cursor != car:
		var part := String(cursor.name).to_lower()
		for token in body_skip:
			if part.find(String(token)) >= 0:
				return true
		cursor = cursor.get_parent()
	return false
