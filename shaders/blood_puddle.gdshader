shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// Лужа на полотне: depth test включён, depth write нет — как следы шин.
// Без no_depth_test, иначе прямоугольник рисуется поверх машины.
uniform vec4 blood_color : source_color = vec4(0.38, 0.02, 0.04, 0.82);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float angle = atan(p.y, p.x);
	float radius = length(p);
	float wobble = 0.18 * sin(angle * 5.0) + 0.08 * sin(angle * 11.0 + 1.7);
	float blot = 1.0 - smoothstep(0.28, 0.92, radius + wobble);
	float grit = 0.75 + 0.25 * sin(UV.x * 37.0 + UV.y * 19.0) * sin(UV.y * 29.0);
	float coverage = blot * grit;
	if (coverage < 0.04) {
		discard;
	}
	ALBEDO = blood_color.rgb * (0.65 + 0.35 * grit);
	ALPHA = blood_color.a * coverage;
}
