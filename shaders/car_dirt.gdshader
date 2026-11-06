shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

// Слой пыли и грязи поверх краски. Положения привязаны к кузову (не к миру):
// пятна не «плывут», пока машина едет.
//
// Настройки — в RallyFxProfile (data/stage/default_fx_profile.tres):
//   dirt_color / body_snow_color — цвета сухой пыли и снега;
//   body_coverage — густота покрытия (1 — заводской вид, больше — грязнее);
//   body_edge_softness — мягкость краёв пятен.
uniform mat4 world_to_car;
uniform vec3 wheels[4] = vec3[4](vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0));
uniform vec4 dirt_amount = vec4(0.0);
uniform vec4 damp_amount = vec4(0.0);
uniform vec4 snow_amount = vec4(0.0);
// Одноразовый сид на машину: у каждой машины своя форма пятен и потёков.
uniform vec3 pattern_seed = vec3(0.0);
uniform vec3 dirt_color : source_color = vec3(0.32, 0.235, 0.14);
uniform vec3 snow_color : source_color = vec3(0.80, 0.85, 0.90);
uniform float dirt_coverage : hint_range(0.1, 3.0) = 1.35;
uniform float edge_softness : hint_range(0.05, 2.0) = 0.85;
// Скорость налипания уже задана в физике; здесь — общая сила слоя.
uniform float dirt_strength : hint_range(0.0, 3.0) = 1.0;
uniform float snow_strength : hint_range(0.0, 3.0) = 1.0;
// Непрозрачность полного слоя и радиус пятна вокруг колеса (1 — заводской вид).
uniform float body_alpha : hint_range(0.0, 1.0) = 0.92;
uniform float body_spread : hint_range(0.2, 3.0) = 1.0;

varying vec3 body_position;

float hash3(vec3 p) {
	p += pattern_seed;
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1,0,0)), f.x),
		mix(hash3(i + vec3(0,1,0)), hash3(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0,0,1)), hash3(i + vec3(1,0,1)), f.x),
		mix(hash3(i + vec3(0,1,1)), hash3(i + vec3(1,1,1)), f.x), f.y), f.z);
}

void vertex() {
	body_position = (world_to_car * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Несколько слоёв вместо одного повторяющегося шума: крупные разводы,
	// мелкие брызги, вертикальные потёки и «крупа» от гравия.
	float coarse = noise3(body_position * vec3(8.0, 12.0, 9.0));
	float speckle = noise3(body_position * vec3(70.0, 52.0, 82.0) + pattern_seed * 0.83);
	float streaks = noise3(body_position * vec3(34.0, 4.5, 18.0) + pattern_seed * 1.71);
	float droplets = noise3(body_position * vec3(128.0, 82.0, 116.0) + pattern_seed * 2.37);
	float pattern = clamp(coarse * 0.24 + streaks * 0.27 + speckle * 0.31 + droplets * 0.18, 0.0, 1.0);
	float random_bias = (hash3(pattern_seed * 3.7 + vec3(2.3, 7.1, 11.9)) - 0.5) * 0.10;
	float dirt_deposit = 0.0;
	float snow_deposit = 0.0;
	float damp = 0.0;
	float dirt_pattern = clamp(pattern + random_bias, 0.0, 1.0);
	float snow_pattern = clamp(coarse * 0.34 + speckle * 0.28 + streaks * 0.20 + droplets * 0.18 + random_bias * 0.5, 0.0, 1.0);
	// Каждое колесо оставляет пятно вокруг арки. Маска шире и выше, чем раньше:
	// пыль реально видна на порогах, дверях и бампере, а не полоской у порога.
	float spread = max(body_spread, 0.05);
	for (int i = 0; i < 4; i++) {
		vec3 p = body_position - wheels[i];
		float height = 1.0 - smoothstep(0.32 * spread, 1.35 * spread,
			p.y + (coarse - 0.5) * 0.45);
		float side = exp(-pow(p.x / (0.78 * spread), 2.0));
		float behind = exp(-pow((p.z + 0.45) / (1.35 * spread), 2.0));
		float zone = side * behind * height;
		vec3 wheel_seed = vec3(float(i) * 17.1, float(i) * 6.7, float(i) * 23.4);
		float local_splatter = noise3(p * vec3(23.0, 14.0, 29.0) + wheel_seed + pattern_seed);
		float local_grit = noise3(p * vec3(78.0, 45.0, 88.0) + wheel_seed * 1.7 + pattern_seed * 2.1);
		float wheel_pattern = clamp(pattern * 0.56 + local_splatter * 0.31 + local_grit * 0.13, 0.0, 1.0);
		float wheel_bias = (hash3(wheel_seed + pattern_seed * 1.3) - 0.5) * 0.12;
		float dirt_zone = dirt_amount[i] * zone * mix(0.78, 1.18, local_splatter);
		float snow_zone = snow_amount[i] * zone * mix(0.88, 1.12, local_splatter);
		dirt_deposit = max(dirt_deposit, dirt_zone);
		snow_deposit = max(snow_deposit, snow_zone);
		float local_weight = smoothstep(0.02, 0.72, zone);
		dirt_pattern = mix(dirt_pattern, clamp(wheel_pattern + wheel_bias, 0.0, 1.0), local_weight * 0.72);
		snow_pattern = mix(snow_pattern, clamp(wheel_pattern * 0.8 + coarse * 0.2, 0.0, 1.0), local_weight * 0.48);
		damp = max(damp, damp_amount[i] * zone);
	}
	// У бампера нет колеса по центру: поперечная маска забирает накопление
	// с ближайшей оси и затухает к капоту/багажнику.
	float front_z = (wheels[0].z + wheels[1].z) * 0.5;
	float rear_z = (wheels[2].z + wheels[3].z) * 0.5;
	float front_y = (wheels[0].y + wheels[1].y) * 0.5;
	float rear_y = (wheels[2].y + wheels[3].y) * 0.5;
	float front_zone = smoothstep(0.25, 0.9, body_position.z - front_z)
		* (1.0 - smoothstep(0.32, 1.15, body_position.y - front_y + (coarse - 0.5) * 0.2));
	float rear_zone = smoothstep(0.25, 0.9, rear_z - body_position.z)
		* (1.0 - smoothstep(0.32, 1.15, body_position.y - rear_y + (coarse - 0.5) * 0.2));
	dirt_deposit = max(dirt_deposit, 0.85 * max(max(dirt_amount.x, dirt_amount.y) * front_zone, max(dirt_amount.z, dirt_amount.w) * rear_zone));
	snow_deposit = max(snow_deposit, 0.85 * max(max(snow_amount.x, snow_amount.y) * front_zone, max(snow_amount.z, snow_amount.w) * rear_zone));
	damp = max(damp, max(max(damp_amount.x, damp_amount.y) * front_zone, max(damp_amount.z, damp_amount.w) * rear_zone));
	// Чем больше накопилось, тем ниже порог рисунка и мягче край: пятно растёт
	// от отдельных брызг до сплошного налёта. Пороги всегда упорядочены.
	float soft = clamp(edge_softness, 0.05, 2.0) * 0.02;
	float dirt_fill = clamp(dirt_deposit * dirt_coverage * dirt_strength, 0.0, 1.0);
	float snow_fill = clamp(snow_deposit * dirt_coverage * snow_strength, 0.0, 1.0);
	float dirt_threshold = mix(0.74, 0.10, dirt_fill);
	float snow_threshold = mix(0.70, 0.08, snow_fill);
	float mud = smoothstep(dirt_threshold, dirt_threshold + mix(0.34, 0.07, dirt_fill) + soft, dirt_pattern)
		* smoothstep(0.0, 0.03, dirt_deposit) * sqrt(dirt_fill);
	float snow = smoothstep(snow_threshold, snow_threshold + mix(0.30, 0.06, snow_fill) + soft, snow_pattern)
		* smoothstep(0.0, 0.03, snow_deposit) * sqrt(snow_fill);
	float coverage_mask = max(mud, snow);
	if (coverage_mask < 0.012) { discard; }
	vec3 dry = dirt_color * (0.85 + coarse * 0.3 + speckle * 0.18);
	vec3 wet = mix(dry, dry * 0.42, clamp(damp, 0.0, 1.0));
	float snow_mix = clamp(snow / max(mud, 0.001), 0.0, 1.0);
	ALBEDO = mix(wet, snow_color * (0.82 + coarse * 0.22), snow_mix);
	ROUGHNESS = mix(mix(0.98, 0.45, clamp(damp, 0.0, 1.0)), 0.86, snow_mix);
	SPECULAR = mix(mix(0.12, 0.38, clamp(damp, 0.0, 1.0)), 0.16, snow_mix);
	float relief = speckle * 0.5 + coarse * 0.5;
	NORMAL = normalize(NORMAL - 0.45 * (dFdx(relief) * normalize(dFdx(VERTEX)) + dFdy(relief) * normalize(dFdy(VERTEX))));
	ALPHA = clamp(coverage_mask * 2.1, 0.0, body_alpha);
}
