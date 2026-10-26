shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float speed_intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    vec2 from_center = SCREEN_UV - vec2(0.5);
    float radius = length(from_center);
    vec2 radial_direction = radius > 0.0001 ? from_center / radius : vec2(0.0);

    float peripheral = smoothstep(0.12, 0.72, radius);
    float aberration = speed_intensity * peripheral * 0.007;
    vec2 offset = radial_direction * aberration;

    vec4 center_sample = texture(screen_texture, SCREEN_UV);
    float red = texture(screen_texture, clamp(SCREEN_UV + offset, vec2(0.001), vec2(0.999))).r;
    float blue = texture(screen_texture, clamp(SCREEN_UV - offset, vec2(0.001), vec2(0.999))).b;
    vec3 color = vec3(red, center_sample.g, blue);

    float vignette = smoothstep(0.28, 0.76, radius) * speed_intensity * 0.58;
    color *= 1.0 - vignette;
    COLOR = vec4(color, 1.0);
}
