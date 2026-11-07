shader_type canvas_item;

void fragment() {
	float fade = 1.0 - smoothstep(0.23, 0.72, UV.x);
	float edge = smoothstep(0.45, 1.0, UV.y) * 0.22;
	COLOR = vec4(0.025, 0.035, 0.031, max(fade * 0.94, edge));
}
