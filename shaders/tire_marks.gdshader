shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

void fragment() {
	// Мягкие края и тонкие продольные канавки без отдельной текстуры.
	float edge = smoothstep(0.0, 0.16, UV.x) * smoothstep(0.0, 0.16, 1.0 - UV.x);
	float tread = 0.8 + 0.2 * smoothstep(0.2, 0.8, abs(sin(UV.x * 31.4)));
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * edge * tread;
}
