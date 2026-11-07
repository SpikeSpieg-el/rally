shader_type canvas_item;

void fragment() {
	// Плотный контраст под текстом постепенно уходит к живой трассе справа.
	float left_shade = 1.0 - smoothstep(0.28, 0.70, UV.x);
	float bottom_shade = smoothstep(0.55, 1.0, UV.y) * 0.18;
	COLOR = vec4(0.018, 0.031, 0.046, max(left_shade * 0.94, bottom_shade));
}
