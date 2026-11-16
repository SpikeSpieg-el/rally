shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, shadows_disabled, unshaded;

// Материал 3D-призрака: Френель-контур, сканлайны, пульсация и мягкое
// затухание при сближении с машиной игрока или камерой.
uniform vec4 ghost_color : source_color = vec4(0.22, 0.86, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(0.70, 0.97, 1.0, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.42;
uniform float near_fade_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float fresnel_power : hint_range(0.5, 10.0) = 2.6;
uniform float rim_intensity : hint_range(0.0, 5.0) = 1.65;
uniform float emission_strength : hint_range(0.0, 5.0) = 1.15;
uniform float shading_contrast : hint_range(0.0, 1.0) = 0.45;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.18;
uniform float scanline_density : hint_range(1.0, 160.0) = 42.0;
uniform float scanline_speed : hint_range(-20.0, 20.0) = 2.5;
uniform float pulse_speed : hint_range(0.0, 10.0) = 2.0;
uniform float pulse_amount : hint_range(0.0, 0.5) = 0.08;
uniform float rim_alpha_boost : hint_range(0.0, 1.0) = 0.45;
uniform bool use_texture = false;
uniform float texture_mix : hint_range(0.0, 1.0) = 0.35;
uniform sampler2D albedo_tex : source_color, hint_default_white;

varying float v_local_y;
varying vec3 v_world_normal;

void vertex() {
	v_local_y = VERTEX.y;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float ndotv = clamp(abs(dot(n, v)), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, max(fresnel_power, 0.1));

	// Псевдо-освещение по мировой нормали, чтобы арки, спойлер и капот читались в 3D.
	float fake_light = clamp(dot(normalize(v_world_normal), normalize(vec3(0.35, 0.86, 0.38))) * 0.5 + 0.5, 0.0, 1.0);
	float shade = mix(1.0, 0.52 + fake_light * 0.68, shading_contrast);

	float scan = 0.5 + 0.5 * sin(v_local_y * scanline_density - TIME * scanline_speed);
	float scan_mod = mix(1.0, 0.65 + 0.35 * scan, scanline_strength);
	float pulse = 1.0 + sin(TIME * pulse_speed) * pulse_amount;

	vec3 tint_rgb = ghost_color.rgb;
	if (use_texture) {
		vec3 tex_rgb = texture(albedo_tex, UV).rgb;
		tint_rgb = mix(ghost_color.rgb, tex_rgb * ghost_color.rgb * 1.35, texture_mix);
	}

	vec3 base_rgb = tint_rgb * shade * scan_mod;
	vec3 final_rgb = (base_rgb + rim_color.rgb * (fresnel * rim_intensity)) * (1.0 + emission_strength * 0.45) * pulse;

	float base_alpha = clamp(opacity * ghost_color.a + fresnel * rim_alpha_boost, 0.0, 1.0);
	float final_alpha = clamp(base_alpha * scan_mod * near_fade_alpha, 0.0, 1.0);

	ALBEDO = final_rgb;
	ALPHA = final_alpha;
}
