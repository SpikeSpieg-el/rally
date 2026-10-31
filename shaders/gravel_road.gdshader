shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Вершинный цвет задаёт покрытие и обочины, UV.x — метры от оси,
// UV.y — расстояние по дороге. Детали привязаны к миру, не к камере.
uniform sampler2D gravel_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float detail_strength : hint_range(0.0, 0.5) = 0.16;
uniform float track_strength : hint_range(0.0, 0.4) = 0.12;
uniform float road_roughness : hint_range(0.0, 1.0) = 0.92;
// Погода: мокрое полотно темнее и глянцевее, снег — светлее и матовее.
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float snow_cover : hint_range(0.0, 1.0) = 0.0;

uniform float zone_offset = 1.5;
uniform float stage_length = 0.0;

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
	vec3 gravel_detail = texture(gravel_texture, vec2(UV.x, UV.y) * 0.3).rgb;
	vec3 albedo = COLOR.rgb * surface * (0.65 + gravel_detail * 1.25);
	// Дождь: гравий темнеет, колеи блестят. Снег: полотно укрыто почти целиком.
	albedo *= mix(1.0, 0.62, wetness);
	albedo = mix(albedo, vec3(0.87, 0.90, 0.95) * surface, snow_cover * 0.85);
	// Полосы совпадают с физикой колёс: тёмная лужа и светлый рыхлый гравий.
	float index = floor((UV.y - 150.0) / 240.0);
	float along = mod(UV.y - 150.0, 240.0);
	float parity = mod(index, 2.0);
	float side = mix(1.0, -1.0, parity);
	float zone = smoothstep(0.0, 3.0, along) * (1.0 - smoothstep(17.0, 20.0, along));
	zone *= 1.0 - smoothstep(0.7, 1.5, abs(UV.x - side * zone_offset));
	if (UV.y < 150.0 || UV.y > stage_length - 40.0) { zone = 0.0; }
	albedo = mix(albedo, mix(albedo * 0.38, albedo * 1.28, parity), zone * 0.8);
	ALBEDO = albedo;
	ROUGHNESS = mix(mix(road_roughness, 0.22, wetness), 0.72, snow_cover * 0.85);
	SPECULAR = mix(mix(0.22, 0.55, wetness), 0.08, snow_cover * 0.85);
	ROUGHNESS = mix(ROUGHNESS, 0.18, zone * (1.0 - parity) * 0.8);
}
