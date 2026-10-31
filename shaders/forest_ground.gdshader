shader_type spatial;
render_mode specular_schlick_ggx;

#include "res://shaders/ps1_vertex.gdshaderinc"

// Цвет вершин: R — расстояние от дороги, G — скала, B — вариация.
// Туман применяется окружением ко всем объектам, а не только к земле.
uniform sampler2D ground_texture : source_color, repeat_enable, filter_nearest_mipmap;
uniform sampler2D rock_texture : source_color, repeat_enable, filter_nearest_mipmap;
uniform sampler2D ground_texture_smooth : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D rock_texture_smooth : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform bool ps1_textures = true;
uniform vec3 ground_color : source_color = vec3(0.10, 0.17, 0.07);
uniform vec3 ground_color_2 : source_color = vec3(0.21, 0.26, 0.11);
uniform vec3 road_edge_color : source_color = vec3(0.31, 0.25, 0.17);
uniform vec3 rock_color : source_color = vec3(0.29, 0.31, 0.32);
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.97;
uniform float grain_scale : hint_range(0.1, 6.0) = 2.4;
uniform float flat_shading : hint_range(0.0, 1.0) = 1.0;
uniform float vertex_snap : hint_range(0.0, 1.0) = 0.0;
uniform float resolution_y : hint_range(180.0, 720.0) = 270.0;
// Погода: сырая земля темнее, снег ложится на пологие места.
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float snow_cover : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec4 vertex_info;

float hash_2d(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	vec2 blend = local * local * (3.0 - 2.0 * local);
	float a = hash_2d(cell);
	float b = hash_2d(cell + vec2(1.0, 0.0));
	float c = hash_2d(cell + vec2(0.0, 1.0));
	float d = hash_2d(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, blend.x), mix(c, d, blend.x), blend.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	vertex_info = COLOR;
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	// Проекции теней/отражений не квантуем — только изображение камеры.
	bool main_camera = distance(INV_VIEW_MATRIX[3].xyz, MAIN_CAM_INV_VIEW_MATRIX[3].xyz) < 0.01;
	POSITION = ps1_snap_vertex(clip, VIEWPORT_SIZE, resolution_y, main_camera ? vertex_snap : 0.0);
}

void fragment() {
	vec3 normal = normalize(world_normal);
	if (flat_shading > 0.5) {
		vec3 face = cross(dFdx(world_pos), dFdy(world_pos));
		if (dot(face, normal) < 0.0) {
			face = -face;
		}
		if (dot(face, face) > 0.00000001) {
			normal = normalize(face);
			// NORMAL в fragment находится в пространстве камеры. Раньше плоская
			// нормаль использовалась только для скал, но не для освещения.
			NORMAL = normalize(mat3(VIEW_MATRIX) * normal);
		}
	}
	float slope = clamp(1.0 - normal.y, 0.0, 1.0);
	float broad_noise = value_noise(world_pos.xz * 0.05);
	float fine_noise = value_noise(world_pos.xz * grain_scale);

	vec3 ground = mix(ground_color, ground_color_2, broad_noise);
	ground *= mix(0.80, 1.14, fine_noise);
	vec2 ground_uv = world_pos.xz * 0.25;
	vec3 ground_detail = ps1_textures ? texture(ground_texture, ground_uv).rgb : texture(ground_texture_smooth, ground_uv).rgb;
	ground *= 0.65 + ground_detail * 1.5;

	float shoulder = smoothstep(0.0, 0.3, vertex_info.r);
	vec3 albedo = mix(road_edge_color, ground, shoulder);
	float rock_amt = smoothstep(0.55, 0.85, slope) * vertex_info.g;
	vec2 rock_uv = world_pos.xz * 0.22;
	vec3 rock_detail = ps1_textures ? texture(rock_texture, rock_uv).rgb : texture(rock_texture_smooth, rock_uv).rgb;
	albedo = mix(albedo, rock_color * (0.65 + rock_detail * 1.3) * mix(0.80, 1.15, vertex_info.b), rock_amt);

	albedo *= mix(1.0, 0.78, wetness);
	float snow_amount = snow_cover * (1.0 - smoothstep(0.15, 0.65, slope));
	albedo = mix(albedo, vec3(0.88, 0.91, 0.96) * mix(0.92, 1.04, fine_noise), snow_amount);
	ALBEDO = albedo;
	ROUGHNESS = mix(surface_roughness, 0.62, snow_amount);
	SPECULAR = mix(mix(0.16, 0.42, wetness), 0.10, snow_amount);
}
