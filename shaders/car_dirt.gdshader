shader_type spatial;
render_mode blend_mix, depth_draw_never;

// Поверх исходной краски; положения стабильно привязаны к кузову, не к миру.
uniform mat4 world_to_car;
uniform vec3 wheels[4];
uniform vec4 dirt_amount = vec4(0.0);
uniform vec4 damp_amount = vec4(0.0);
uniform vec4 snow_amount = vec4(0.0);
varying vec3 body_position;

float hash3(vec3 p) {
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
	float coarse = noise3(body_position * 13.0);
	float speckle = noise3(body_position * 95.0);
	float streaks = noise3(body_position * vec3(32.0, 3.0, 25.0));
	float dirt_deposit = 0.0;
	float snow_deposit = 0.0;
	float damp = 0.0;
	for (int i = 0; i < 4; i++) {
		vec3 p = body_position - wheels[i];
		float height = 1.0 - smoothstep(0.30, 1.05, p.y + (coarse - 0.5) * 0.35);
		float side = exp(-pow(p.x / 0.60, 2.0));
		float behind = exp(-pow((p.z + 0.45) / 1.15, 2.0));
		float zone = side * behind * height;
		dirt_deposit = max(dirt_deposit, dirt_amount[i] * zone);
		snow_deposit = max(snow_deposit, snow_amount[i] * zone);
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
	float pattern = coarse * 0.65 + speckle * 0.25 + streaks * 0.10;
	float mud = smoothstep(0.60 - 0.40 * dirt_deposit, 0.74 - 0.18 * dirt_deposit, pattern)
		* smoothstep(0.0, 0.08, dirt_deposit) * sqrt(dirt_deposit);
	float snow = smoothstep(0.60 - 0.35 * snow_deposit, 0.76 - 0.16 * snow_deposit, pattern)
		* smoothstep(0.0, 0.08, snow_deposit) * sqrt(snow_deposit);
	float coverage = max(mud, snow);
	if (coverage < 0.015) { discard; }
	vec3 mud_color = mix(vec3(0.32, 0.235, 0.14), vec3(0.115, 0.073, 0.038), clamp(damp, 0.0, 1.0));
	mud_color *= 0.75 + coarse * 0.4 + speckle * 0.2;
	float snow_mix = clamp(snow / max(mud + snow, 0.001), 0.0, 1.0);
	ALBEDO = mix(mud_color, vec3(0.78, 0.83, 0.86) * (0.8 + coarse * 0.2), snow_mix);
	ROUGHNESS = mix(mix(0.98, 0.48, clamp(damp, 0.0, 1.0)), 0.85, snow_mix);
	SPECULAR = mix(mix(0.12, 0.35, clamp(damp, 0.0, 1.0)), 0.15, snow_mix);
	float relief = speckle * 0.5 + coarse * 0.5;
	NORMAL = normalize(NORMAL - 0.45 * (dFdx(relief) * normalize(dFdx(VERTEX)) + dFdy(relief) * normalize(dFdy(VERTEX))));
	ALPHA = clamp(coverage * 1.7, 0.0, 0.96);
}
