shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

// Отдельный слой следов ударов для машин без слоя грязи (лаборатория
// деформации, витрины). В заезде следы рисует тот же проход, что и грязь
// (car_dirt.gdshader), — прозрачные слои кузова не мерцают друг о друга.
#include "res://shaders/car_damage_marks.gdshaderinc"

uniform mat4 world_to_car;

varying vec3 body_position;
varying vec3 body_normal;

void vertex() {
	body_position = (world_to_car * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	body_normal = normalize((world_to_car * MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 albedo;
	float rough;
	float spec;
	float alpha = damage_marks(body_position, normalize(body_normal), albedo, rough, spec);
	if (alpha < 0.01) { discard; }
	ALBEDO = albedo;
	ROUGHNESS = rough;
	SPECULAR = spec;
	ALPHA = alpha;
}
