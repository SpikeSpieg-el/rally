shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;

#include "res://shaders/ps1_vertex.gdshaderinc"

// Вода центральной реки: тёмная, почти чёрная в глубине, с бегущей рябью и
// пеной у берегов. Цвет вершины: R — «кромка» (0 середина, 1 берег),
// G — зерно шума, B — доля быстрого течения (пороги).
uniform vec3 shallow_color : source_color = vec3(0.055, 0.075, 0.070);
uniform vec3 deep_color : source_color = vec3(0.012, 0.020, 0.022);
uniform vec3 foam_color : source_color = vec3(0.52, 0.58, 0.56);
uniform float flow_speed : hint_range(0.0, 8.0) = 1.4;
uniform float foam_amount : hint_range(0.0, 1.0) = 0.45;
uniform float foam_width : hint_range(0.2, 20.0) = 2.4;
uniform float gloss : hint_range(0.0, 1.0) = 0.55;
uniform float opacity : hint_range(0.0, 1.0) = 0.88;
uniform float wave_height : hint_range(0.0, 1.0) = 0.07;
uniform float ripple_scale : hint_range(0.05, 4.0) = 0.55;
uniform float vertex_snap : hint_range(0.0, 1.0) = 0.0;
uniform float resolution_y : hint_range(180.0, 720.0) = 270.0;
// Погода: дождь рябит сильнее, снег гасит блик.
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float snow_cover : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_pos;
varying vec3 edge_color;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(cell);
	float b = hash(cell + vec2(1.0, 0.0));
	float c = hash(cell + vec2(0.0, 1.0));
	float d = hash(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	edge_color = COLOR.rgb;
	float travel = TIME * flow_speed;
	// Две несовпадающие волны: зеркало не выглядит «рябью из строк».
	VERTEX.y += wave_height * (
		sin(world_pos.x * 1.7 + travel * 2.3) * 0.5
		+ sin(world_pos.z * 2.9 - travel * 3.1) * 0.35
		+ sin((world_pos.x + world_pos.z) * 0.8 + travel) * 0.15
	);
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	bool main_camera = distance(INV_VIEW_MATRIX[3].xyz, MAIN_CAM_INV_VIEW_MATRIX[3].xyz) < 0.01;
	POSITION = ps1_snap_vertex(clip, VIEWPORT_SIZE, resolution_y, main_camera ? vertex_snap : 0.0);
}

void fragment() {
	float travel = TIME * flow_speed;
	vec2 flow_uv = vec2(UV.x * 3.0 * ripple_scale, UV.y * 12.0 * ripple_scale - travel);
	vec2 cross_uv = vec2(UV.x * 7.0 * ripple_scale + 0.37, UV.y * 20.0 * ripple_scale - travel * 1.7);
	float ripple = noise(flow_uv) * 0.6 + noise(cross_uv) * 0.4;
	float quick = clamp(edge_color.b, 0.0, 1.0);
	ripple = mix(ripple, ripple * 1.6, quick);

	// R вершины = 1 на кромке воды у берега, 0.15 на стремнине.
	float edge = clamp(edge_color.r, 0.0, 1.0);
	float foam_band = smoothstep(0.25, 0.95, edge);
	foam_band = pow(foam_band, mix(1.6, 0.7, clamp(foam_width / 8.0, 0.0, 1.0)));
	float foam = smoothstep(0.55, 0.92, foam_band * (0.75 + ripple * 0.7) + quick * 0.25);
	foam *= clamp(foam_amount * (0.75 + wetness * 0.5), 0.0, 1.0);

	vec3 water = mix(deep_color, shallow_color, ripple * 0.85 + edge * 0.15);
	water = mix(water, foam_color, foam);
	ALBEDO = water;
	ROUGHNESS = clamp(1.0 - gloss * (0.55 + ripple * 0.35) + foam * 0.6 + snow_cover * 0.4, 0.03, 1.0);
	METALLIC = 0.05;
	SPECULAR = 0.35 + gloss * 0.4;
	ALPHA = clamp(opacity + foam * 0.12, 0.0, 1.0);
	// Мелкая рябь по нормали: блики фар «дышат» на воде. NORMAL во фрагменте
	// уже в пространстве вида, поэтому возмущаем его в экранных осях.
	vec2 slope = vec2(
		noise(flow_uv * 1.7) - 0.5,
		noise(cross_uv * 1.3) - 0.5
	) * mix(0.45, 0.15, gloss);
	NORMAL = normalize(NORMAL + vec3(slope, 0.0));
	if (snow_cover > 0.35) {
		ALBEDO = mix(ALBEDO, vec3(0.86, 0.90, 0.94), (snow_cover - 0.35) * 0.8);
	}
}
