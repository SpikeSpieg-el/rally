shader_type spatial;
render_mode blend_mix, depth_draw_never;

// Поверх исходной краски; положения стабильно привязаны к кузову, не к миру.
uniform mat4 world_to_car;
uniform vec3 wheels[4];
uniform vec4 dirt_amount = vec4(0.0);
uniform vec4 damp_amount = vec4(0.0);
uniform vec4 snow_amount = vec4(0.0);
// Одноразовый сид на машину: слой грязи стабилен в движении, но у каждой
// машины своя форма пятен, брызг и потёков.
uniform vec3 pattern_seed = vec3(0.0);
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
	// Несколько вытянутых и точечных слоёв вместо одного повторяющегося
	// шума. Частоты подобраны отдельно для пятен, пыли и потёков.
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
	for (int i = 0; i < 4; i++) {
		vec3 p = body_position - wheels[i];
		float height = 1.0 - smoothstep(0.30, 1.05, p.y + (coarse - 0.5) * 0.35);
		float side = exp(-pow(p.x / 0.60, 2.0));
		float behind = exp(-pow((p.z + 0.45) / 1.15, 2.0));
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
	// На бампере нет колеса по центру: отдельная поперечная маска
	// берёт накопление с соответствующей оси и затухает к капоту/багажнику.
	float front_z = (wheels[0].z + wheels[1].z) * 0.5;
	float rear_z = (wheels[2].z + wheels[3].z) * 0.5;
	float front_y = (wheels[0].y + wheels[1].y) * 0.5;
	float rear_y = (wheels[2].y + wheels[3].y) * 0.5;
	float front_zone = smoothstep(0.25, 0.9, body_position.z - front_z)
		* (1.0 - smoothstep(0.28, 0.92, body_position.y - front_y + (coarse - 0.5) * 0.2));
	float rear_zone = smoothstep(0.25, 0.9, rear_z - body_position.z)
		* (1.0 - smoothstep(0.28, 0.92, body_position.y - rear_y + (coarse - 0.5) * 0.2));
	dirt_deposit = max(dirt_deposit, 0.75 * max(max(dirt_amount.x, dirt_amount.y) * front_zone, max(dirt_amount.z, dirt_amount.w) * rear_zone));
	snow_deposit = max(snow_deposit, 0.75 * max(max(snow_amount.x, snow_amount.y) * front_zone, max(snow_amount.z, snow_amount.w) * rear_zone));
	damp = max(damp, max(max(damp_amount.x, damp_amount.y) * front_zone, max(damp_amount.z, damp_amount.w) * rear_zone));
	float mud = smoothstep(0.60 - 0.40 * dirt_deposit + random_bias, 0.74 - 0.18 * dirt_deposit + random_bias, dirt_pattern)
		* smoothstep(0.0, 0.08, dirt_deposit) * sqrt(dirt_deposit);
	float snow = smoothstep(0.60 - 0.35 * snow_deposit, 0.76 - 0.16 * snow_deposit, snow_pattern)
		* smoothstep(0.0, 0.08, snow_deposit) * sqrt(snow_deposit);
	float coverage = max(mud, snow);
	if (coverage < 0.015) { discard; }
	vec3 mud_color = mix(vec3(0.32, 0.235, 0.14), vec3(0.115, 0.073, 0.038), clamp(damp, 0.0, 1.0));
	mud_color *= 0.75 + coarse * 0.4 + speckle * 0.2;
	float snow_mix = clamp(snow / max(mud, 0.001), 0.0, 1.0);
	ALBEDO = mix(mud_color, vec3(0.78, 0.83, 0.86) * (0.8 + coarse * 0.2), snow_mix);
	ROUGHNESS = mix(mix(0.98, 0.48, clamp(damp, 0.0, 1.0)), 0.85, snow_mix);
	SPECULAR = mix(mix(0.12, 0.35, clamp(damp, 0.0, 1.0)), 0.15, snow_mix);
	float relief = speckle * 0.5 + coarse * 0.5;
	NORMAL = normalize(NORMAL - 0.45 * (dFdx(relief) * normalize(dFdx(VERTEX)) + dFdy(relief) * normalize(dFdy(VERTEX))));
	ALPHA = clamp(coverage * 1.7, 0.0, 0.96);
}
