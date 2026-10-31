shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

void fragment() {
	// Неровный, полупрозрачный отпечаток, а не сплошная нарисованная полоса.
	float edge = smoothstep(0.0, 0.22, UV.x) * smoothstep(0.0, 0.22, 1.0 - UV.x);
	float grooves = 0.86 + 0.14 * smoothstep(0.1, 0.7, abs(sin(UV.x * 25.0)));
	float grain = 0.88 + 0.12 * sin(UV.y * 23.0 + sin(UV.x * 17.0)) * sin(UV.y * 47.0 + UV.x * 13.0);
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * edge * grooves * grain;
}
