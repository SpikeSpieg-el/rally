shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

// Кровь на кузове: пятна живут в системе машины, поэтому не «плывут»
// по трассе. Положения и направления ударов выставляет RallyBloodFx.
// У uniform-массивов в Godot 4 не может быть значений по умолчанию.
uniform mat4 world_to_car;
uniform vec3 splat_pos[8];
uniform vec3 splat_dir[8];
uniform vec4 splat_data[8];
uniform vec3 blood_color : source_color = vec3(0.42, 0.03, 0.045);
uniform float blood_gloss : hint_range(0.0, 1.0) = 0.42;

varying vec3 body_position;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
		mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
		mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	body_position = (world_to_car * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float mask = 0.0;
	float drip_mask = 0.0;
	for (int i = 0; i < 8; i++) {
		float amount = splat_data[i].x;
		if (amount < 0.02) {
			continue;
		}
		float radius = max(splat_data[i].y, 0.06);
		float stretch = max(splat_data[i].z, 0.8);
		float seed = splat_data[i].w;
		vec3 origin = splat_pos[i];
		vec3 dir = splat_dir[i];
		float dir_len = length(dir);
		dir = dir_len > 0.001 ? dir / dir_len : vec3(0.0, 0.0, 1.0);
		vec3 delta = body_position - origin;
		float along = dot(delta, dir);
		vec3 across_vec = delta - dir * along;
		float across = length(across_vec);
		vec3 noise_seed = origin + vec3(seed, seed * 1.7, seed * 0.31);
		float blot = noise3(delta * vec3(18.0, 22.0, 16.0) + noise_seed);
		float grit = noise3(delta * vec3(54.0, 40.0, 62.0) + noise_seed * 2.1);
		float along_span = radius * stretch * mix(0.85, 1.25, blot);
		float across_span = radius * mix(0.55, 1.05, grit);
		float blob = exp(-pow(across / max(across_span, 0.02), 2.0))
			* exp(-pow(along / max(along_span, 0.02), 2.0));
		float edge = smoothstep(0.12, 0.72, blot * 0.65 + grit * 0.35);
		float splat = blob * mix(0.55, 1.15, edge) * amount;
		// Потёки вниз по кузову от каждого удара.
		float drip_width = mix(0.045, 0.11, hash3(noise_seed));
		float drip_across = length(vec2(delta.x, delta.z));
		float drip = exp(-pow(drip_across / max(drip_width, 0.02), 2.0))
			* smoothstep(0.12, -0.02, delta.y)
			* (1.0 - smoothstep(0.15, 1.15 * stretch, -delta.y))
			* mix(0.4, 1.0, noise3(vec3(body_position.x, body_position.y * 4.0, body_position.z) * 9.0 + noise_seed));
		mask = max(mask, splat);
		drip_mask = max(drip_mask, drip * amount * 0.85);
	}
	float coverage = max(mask, drip_mask);
	if (coverage < 0.04) {
		discard;
	}
	float speckle = noise3(body_position * 90.0);
	vec3 wet = blood_color * (0.55 + speckle * 0.28);
	ALBEDO = mix(wet * 0.55, wet, clamp(coverage, 0.0, 1.0));
	ROUGHNESS = mix(0.22, 0.55, speckle);
	SPECULAR = mix(0.18, 0.55, blood_gloss);
	EMISSION = blood_color * 0.08 * coverage;
	ALPHA = clamp(coverage * 1.65, 0.0, 0.92);
}
