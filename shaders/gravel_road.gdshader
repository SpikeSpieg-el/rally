shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/ps1_vertex.gdshaderinc"

// Вершинный цвет задаёт покрытие и обочины, UV.x — метры от оси,
// UV.y — расстояние по дороге. Детали привязаны к миру, не к камере.
// Все числа ниже — uniform'ы: их можно менять из ресурса RallyStageSettings
// (data/stage/default_stage_settings.tres) и из материала в инспекторе.
uniform sampler2D gravel_texture : source_color, repeat_enable, filter_nearest_mipmap;
uniform sampler2D gravel_texture_smooth : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform bool ps1_textures = true;
uniform float vertex_snap : hint_range(0.0, 1.0) = 0.0;
uniform float resolution_y : hint_range(180.0, 720.0) = 270.0;
uniform float loose_relief : hint_range(0.0, 1.0) = 1.0;
uniform float detail_strength : hint_range(0.0, 0.5) = 0.16;
uniform float track_strength : hint_range(0.0, 0.4) = 0.12;
uniform float road_roughness : hint_range(0.0, 1.0) = 0.92;
// Погода: мокрое полотно темнее и глянцевее, снег — светлее и матовее.
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float snow_cover : hint_range(0.0, 1.0) = 0.0;

// Скользкие полосы: те же числа, что в физике (RallyFxProfile).
uniform float zone_offset = 1.5;
uniform float stage_length = 0.0;
uniform float zone_period = 240.0;
uniform float zone_start = 150.0;
uniform float zone_end_margin = 40.0;
uniform float zone_length = 20.0;
uniform float zone_half_width = 1.5;
uniform float zone_softness = 0.7;
uniform float zone_fade = 3.0;
uniform float zone_contrast : hint_range(0.0, 1.0) = 0.8;
uniform float zone_wet_darken : hint_range(0.0, 1.0) = 0.38;
uniform float zone_dry_lighten : hint_range(0.0, 1.0) = 0.28;

// Мир: масштаб мелкой текстуры и колеи.
uniform float gravel_uv_scale : hint_range(0.01, 3.0) = 0.3;
uniform float detail_scale : hint_range(0.1, 20.0) = 3.5;
uniform float broad_scale : hint_range(0.01, 2.0) = 0.18;
uniform float rut_center : hint_range(0.0, 5.0) = 0.95;
uniform float rut_inner : hint_range(0.0, 2.0) = 0.12;
uniform float rut_outer : hint_range(0.0, 2.0) = 0.40;
uniform float relief_strength : hint_range(0.0, 2.0) = 0.32;
uniform float snow_tint_strength : hint_range(0.0, 1.0) = 0.85;
uniform vec3 snow_tint : source_color = vec3(0.87, 0.90, 0.95);
uniform float wet_roughness : hint_range(0.0, 1.0) = 0.22;
uniform float wet_specular : hint_range(0.0, 1.0) = 0.55;
uniform float snow_roughness : hint_range(0.0, 1.0) = 0.72;
uniform float snow_specular : hint_range(0.0, 1.0) = 0.08;
uniform float wet_darken : hint_range(0.0, 1.0) = 0.62;
uniform float dry_specular : hint_range(0.0, 1.0) = 0.22;
uniform float texture_gain : hint_range(0.0, 3.0) = 1.25;
uniform float texture_base : hint_range(0.0, 2.0) = 0.65;
uniform float puddle_roughness : hint_range(0.0, 1.0) = 0.18;
uniform float puddle_mix : hint_range(0.0, 1.0) = 0.8;

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
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	bool main_camera = distance(INV_VIEW_MATRIX[3].xyz, MAIN_CAM_INV_VIEW_MATRIX[3].xyz) < 0.01;
	POSITION = ps1_snap_vertex(clip, VIEWPORT_SIZE, resolution_y, main_camera ? vertex_snap : 0.0);
}

void fragment() {
	// Мелкий рельеф не должен превращаться в чёрные пятна под фарами,
	// когда одна экранная точка покрывает несколько камешков.
	vec2 detail_coord = world_position.xz * detail_scale;
	vec2 detail_footprint = fwidth(detail_coord);
	float detail_fade = 1.0 - smoothstep(0.3, 1.2, max(detail_footprint.x, detail_footprint.y));
	float gravel_noise = value_noise(detail_coord) - 0.5;
	float gravel = gravel_noise * detail_fade;
	float broad = value_noise(world_position.xz * broad_scale) - 0.5;
	// Две мягкие накатанные колеи без заметного повторяющегося рисунка.
	float ruts = 1.0 - smoothstep(rut_inner, rut_outer, abs(abs(UV.x) - rut_center));
	float rut_variation = mix(0.7, 1.0, value_noise(vec2(UV.y * 0.12, UV.x)));
	float surface = 1.0 + gravel * detail_strength + broad * detail_strength * 0.5;
	surface *= 1.0 - ruts * rut_variation * track_strength;
	vec2 gravel_uv = vec2(UV.x, UV.y) * gravel_uv_scale;
	vec3 gravel_detail = ps1_textures ? texture(gravel_texture, gravel_uv).rgb : texture(gravel_texture_smooth, gravel_uv).rgb;
	vec3 albedo = COLOR.rgb * surface * (texture_base + gravel_detail * texture_gain);
	// Дождь: гравий темнеет, колеи блестят. Снег: полотно укрыто почти целиком.
	albedo *= mix(1.0, 1.0 - wet_darken, wetness);
	albedo = mix(albedo, snow_tint * surface, snow_cover * snow_tint_strength);
	// Полосы совпадают с физикой колёс: тёмная лужа и светлый рыхлый гравий.
	float index = floor((UV.y - zone_start) / zone_period);
	float along = mod(UV.y - zone_start, zone_period);
	float parity = mod(index, 2.0);
	float side = mix(1.0, -1.0, parity);
	float zone = smoothstep(0.0, zone_fade, along) * (1.0 - smoothstep(zone_length - zone_fade, zone_length, along));
	zone *= 1.0 - smoothstep(zone_half_width - zone_softness, zone_half_width, abs(UV.x - side * zone_offset));
	if (UV.y < zone_start || UV.y > stage_length - zone_end_margin) { zone = 0.0; }
	albedo = mix(albedo, mix(albedo * (1.0 - zone_wet_darken), albedo * (1.0 + zone_dry_lighten), parity), zone * zone_contrast);
	// Рельеф остаётся у машины, но плавно исчезает за пределами частоты
	// дискретизации; иначе блики фар усиливают алиасинг до чёрных пятен.
	float relief = gravel_noise * loose_relief * (1.0 - snow_cover * 0.65);
	NORMAL = normalize(NORMAL - relief_strength * detail_fade * (dFdx(relief) * normalize(dFdx(VERTEX)) + dFdy(relief) * normalize(dFdy(VERTEX))));
	ALBEDO = albedo;
	ROUGHNESS = mix(mix(road_roughness, wet_roughness, wetness), snow_roughness, snow_cover * snow_tint_strength);
	SPECULAR = mix(mix(dry_specular, wet_specular, wetness), snow_specular, snow_cover * snow_tint_strength);
	ROUGHNESS = mix(ROUGHNESS, puddle_roughness, zone * (1.0 - parity) * puddle_mix);
}
