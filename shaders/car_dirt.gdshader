shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

// Слой пыли и грязи поверх краски. Положения привязаны к кузову (не к миру):
// пятна не «плывут», пока машина едет.
//
// Настройки — в RallyFxProfile (data/stage/default_fx_profile.tres):
//   dirt_color / body_snow_color — базовые цвета пыли и снега;
//   body_coverage — густота покрытия (1 — заводской вид, больше — грязнее);
//   body_edge_softness — мягкость краёв пятен.
//
// У каждого колеса свой цвет и характер пятна (dirt_colors / dirt_looks):
// гравий оставляет светлую пыль, грязь — тёмный налипший слой, трава —
// зеленоватый налёт. Значения приходят из профиля покрытия, поэтому одна
// и та же машина на разных дорогах выглядит по-разному.
uniform mat4 world_to_car;
// Значений по умолчанию у массивов быть не может: Godot 4 отвергает
// `uniform vec3 wheels[4] = vec3[4](...)` целиком («Setting default values to
// uniform arrays is not supported»), шейдер не компилируется, и вместо слоя
// грязи на кузове остаётся голая краска. Массивы обязан выставлять код —
// SurfaceEffects делает это каждый кадр в update().
uniform vec3 wheels[4];
uniform vec3 dirt_colors[4];
// x — густота пятна, y — разлёт от колеса, z — предел непрозрачности, w — резерв.
uniform vec4 dirt_looks[4];
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
	float dirt_pattern = clamp(pattern + random_bias, 0.0, 1.0);
	float soft = clamp(edge_softness, 0.05, 2.0) * 0.02;

	// Цвет и предел прозрачности собираются из вклада всех колёс: у каждого
	// покрытия свой оттенок, и при смене дороги пятно плавно перекрашивается.
	vec3 tint_sum = vec3(0.0);
	float tint_weight = 0.0;
	float alpha_sum = 0.0;
	float alpha_weight = 0.0;
	float mud = 0.0;
	float snow = 0.0;
	float damp = 0.0;

	for (int i = 0; i < 4; i++) {
		vec4 look = dirt_looks[i];
		float spread = max(body_spread * max(look.y, 0.05), 0.05);
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
		float wheel_deposit = clamp(wheel_pattern + wheel_bias, 0.0, 1.0);

		float dirt_zone = dirt_amount[i] * zone * mix(0.78, 1.18, local_splatter);
		float dirt_fill = clamp(dirt_zone * dirt_coverage * max(look.x, 0.05) * dirt_strength, 0.0, 1.0);
		float dirt_threshold = mix(0.74, 0.10, dirt_fill);
		float dirt_mask = smoothstep(dirt_threshold,
			dirt_threshold + mix(0.34, 0.07, dirt_fill) + soft, wheel_deposit)
			* smoothstep(0.0, 0.03, dirt_zone) * sqrt(dirt_fill);
		mud = max(mud, dirt_mask);

		float color_weight = dirt_zone * max(look.x, 0.05);
		tint_sum += dirt_colors[i] * color_weight;
		tint_weight += color_weight;
		alpha_sum += clamp(look.z, 0.0, 1.0) * color_weight;
		alpha_weight += color_weight;

		float snow_zone = snow_amount[i] * zone * mix(0.88, 1.12, local_splatter);
		float snow_fill = clamp(snow_zone * dirt_coverage * snow_strength, 0.0, 1.0);
		float snow_threshold = mix(0.70, 0.08, snow_fill);
		float snow_mask = smoothstep(snow_threshold,
			snow_threshold + mix(0.30, 0.06, snow_fill) + soft, wheel_deposit)
			* smoothstep(0.0, 0.03, snow_zone) * sqrt(snow_fill);
		snow = max(snow, snow_mask);

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
	float front_dirt = 0.85 * max(dirt_amount.x, dirt_amount.y) * front_zone;
	float rear_dirt = 0.85 * max(dirt_amount.z, dirt_amount.w) * rear_zone;
	float bumper_dirt = max(front_dirt, rear_dirt);
	float front_sum = max(dirt_amount.x + dirt_amount.y, 0.0001);
	float rear_sum = max(dirt_amount.z + dirt_amount.w, 0.0001);
	float front_cov = (dirt_looks[0].x * dirt_amount.x + dirt_looks[1].x * dirt_amount.y) / front_sum;
	float rear_cov = (dirt_looks[2].x * dirt_amount.z + dirt_looks[3].x * dirt_amount.w) / rear_sum;
	float front_alpha = (dirt_looks[0].z * dirt_amount.x + dirt_looks[1].z * dirt_amount.y) / front_sum;
	float rear_alpha = (dirt_looks[2].z * dirt_amount.z + dirt_looks[3].z * dirt_amount.w) / rear_sum;
	float bumper_cov = max(front_cov * front_dirt, rear_cov * rear_dirt) / max(bumper_dirt, 0.0001);
	float bumper_alpha = max(front_alpha * front_dirt, rear_alpha * rear_dirt) / max(bumper_dirt, 0.0001);
	float bumper_fill = clamp(bumper_dirt * dirt_coverage * max(bumper_cov, 0.05) * dirt_strength, 0.0, 1.0);
	float bumper_threshold = mix(0.74, 0.10, bumper_fill);
	float bumper_mask = smoothstep(bumper_threshold,
		bumper_threshold + mix(0.34, 0.07, bumper_fill) + soft, dirt_pattern)
		* smoothstep(0.0, 0.03, bumper_dirt) * sqrt(bumper_fill);
	mud = max(mud, bumper_mask);
	vec3 front_color = (dirt_colors[0] * dirt_amount.x + dirt_colors[1] * dirt_amount.y) / front_sum;
	vec3 rear_color = (dirt_colors[2] * dirt_amount.z + dirt_colors[3] * dirt_amount.w) / rear_sum;
	float front_weight = front_dirt * max(front_cov, 0.05);
	float rear_weight = rear_dirt * max(rear_cov, 0.05);
	tint_sum += front_color * front_weight + rear_color * rear_weight;
	tint_weight += front_weight + rear_weight;
	alpha_sum += front_alpha * front_weight + rear_alpha * rear_weight;
	alpha_weight += front_weight + rear_weight;

	float front_snow = 0.85 * max(snow_amount.x, snow_amount.y) * front_zone;
	float rear_snow = 0.85 * max(snow_amount.z, snow_amount.w) * rear_zone;
	float bumper_snow = max(front_snow, rear_snow);
	float bumper_snow_fill = clamp(bumper_snow * dirt_coverage * snow_strength, 0.0, 1.0);
	float bumper_snow_threshold = mix(0.70, 0.08, bumper_snow_fill);
	float bumper_snow_mask = smoothstep(bumper_snow_threshold,
		bumper_snow_threshold + mix(0.30, 0.06, bumper_snow_fill) + soft, dirt_pattern)
		* smoothstep(0.0, 0.03, bumper_snow) * sqrt(bumper_snow_fill);
	snow = max(snow, bumper_snow_mask);
	damp = max(damp, max(max(damp_amount.x, damp_amount.y) * front_zone,
		max(damp_amount.z, damp_amount.w) * rear_zone));

	float coverage_mask = max(mud, snow);
	if (coverage_mask < 0.012) { discard; }
	vec3 base_dirt = tint_weight > 0.0001 ? tint_sum / tint_weight : dirt_color;
	vec3 dry = base_dirt * (0.85 + coarse * 0.3 + speckle * 0.18);
	vec3 wet = mix(dry, dry * 0.42, clamp(damp, 0.0, 1.0));
	float snow_mix = clamp(snow / max(mud, 0.001), 0.0, 1.0);
	ALBEDO = mix(wet, snow_color * (0.82 + coarse * 0.22), snow_mix);
	ROUGHNESS = mix(mix(0.98, 0.45, clamp(damp, 0.0, 1.0)), 0.86, snow_mix);
	SPECULAR = mix(mix(0.12, 0.38, clamp(damp, 0.0, 1.0)), 0.16, snow_mix);
	float relief = speckle * 0.5 + coarse * 0.5;
	NORMAL = normalize(NORMAL - 0.45 * (dFdx(relief) * normalize(dFdx(VERTEX)) + dFdy(relief) * normalize(dFdy(VERTEX))));
	// Пыль от гравия полупрозрачная, налипшая грязь — плотная: предел
	// непрозрачности тоже приходит из профиля покрытия.
	float alpha_cap = alpha_weight > 0.0001 ? alpha_sum / alpha_weight : 1.0;
	ALPHA = clamp(coverage_mask * 2.1, 0.0, body_alpha * clamp(alpha_cap, 0.0, 1.0));
}
