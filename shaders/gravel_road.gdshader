shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Вершинный цвет задаёт покрытие и обочины, UV.x — метры от оси,
// UV.y — расстояние по дороге. Детали привязаны к миру, не к камере.
uniform float detail_strength : hint_range(0.0, 0.5) = 0.16;
uniform float track_strength : hint_range(0.0, 0.4) = 0.12;
uniform float road_roughness : hint_range(0.0, 1.0) = 0.92;

varying vec3 world_position;

float hash_2d(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 blend = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash_2d(cell), hash_2d(cell + vec2(1.0, 0.0)), blend.x),
		mix(hash_2d(cell + vec2(0.0, 1.0)), hash_2d(cell + vec2(1.0, 1.0)), blend.x),
		blend.y
	);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float gravel = value_noise(world_position.xz * 3.5) - 0.5;
	float broad = value_noise(world_position.xz * 0.18) - 0.5;
	// Две мягкие накатанные колеи без заметного повторяющегося рисунка.
	float ruts = 1.0 - smoothstep(0.12, 0.40, abs(abs(UV.x) - 0.95));
	float rut_variation = mix(0.7, 1.0, value_noise(vec2(UV.y * 0.12, UV.x)));
	float surface = 1.0 + gravel * detail_strength + broad * detail_strength * 0.5;
	surface *= 1.0 - ruts * rut_variation * track_strength;
	ALBEDO = COLOR.rgb * surface;
	ROUGHNESS = road_roughness;
	SPECULAR = 0.22;
}
