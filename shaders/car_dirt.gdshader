shader_type spatial;
render_mode blend_mix, depth_draw_never;

// Отдельный слой поверх исходных материалов. Координаты кузова, не мира:
// пятна не «плывут» при движении и не требуют уникальной UV-развёртки.
uniform mat4 world_to_car;
uniform vec3 wheels[4];
uniform vec4 dirt_amount = vec4(0.0);
uniform vec4 damp_amount = vec4(0.0);
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
	float coverage = 0.0;
	float damp = 0.0;
	for (int i = 0; i < 4; i++) {
		vec3 p = body_position - wheels[i];
		// Грязь за арками, на порогах и нижней части дверей; крыша остаётся чистой.
		float height = 1.0 - smoothstep(0.30, 1.05, p.y + (coarse - 0.5) * 0.35);
		float side = exp(-pow(p.x / 0.48, 2.0));
		float behind = exp(-pow((p.z + 0.45) / 1.0, 2.0));
		float zone = side * behind * height;
		float threshold = 1.0 - dirt_amount[i] * zone;
		float patches = smoothstep(threshold - 0.13, threshold + 0.06,
			coarse * 0.65 + speckle * 0.25 + streaks * 0.10);
		coverage = max(coverage, patches * smoothstep(0.0, 0.05, dirt_amount[i]) * zone);
		damp = max(damp, damp_amount[i] * zone);
	}
	if (coverage < 0.015) { discard; }
	ALBEDO = mix(vec3(0.32, 0.235, 0.14), vec3(0.115, 0.073, 0.038), damp);
	ALBEDO *= 0.75 + coarse * 0.4 + speckle * 0.2;
	ROUGHNESS = mix(0.98, 0.48, damp);
	SPECULAR = mix(0.12, 0.35, damp);
	// Микрорельеф налёта и крупинок, а не однотонная перекраска кузова.
	float relief = speckle * 0.5 + coarse * 0.5;
	NORMAL = normalize(NORMAL - 0.45 * (dFdx(relief) * normalize(dFdx(VERTEX)) + dFdy(relief) * normalize(dFdy(VERTEX))));
	ALPHA = clamp(coverage * 1.7, 0.0, 0.96);
}
