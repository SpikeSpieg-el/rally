shader_type canvas_item;
uniform vec4 shade_color : source_color = vec4(0.012, 0.020, 0.025, 1.0);
uniform float solid_until : hint_range(0.0, 1.0) = 0.22;
uniform float fade_until : hint_range(0.0, 1.0) = 0.65;
uniform float left_opacity : hint_range(0.0, 1.0) = 0.96;
uniform float bottom_opacity : hint_range(0.0, 1.0) = 0.13;
void fragment() {
	float left = 1.0 - smoothstep(solid_until, max(fade_until, solid_until + 0.001), UV.x);
	float bottom = smoothstep(0.6, 1.0, UV.y) * bottom_opacity;
	COLOR = vec4(shade_color.rgb, max(left * left_opacity, bottom) * shade_color.a);
}
