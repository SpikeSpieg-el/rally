shader_type sky;
render_mode use_debanding;

// Луна следует за направленным источником света, поэтому направление теней
// и положение светила всегда совпадают. Параметры задаются ресурсом трассы.
uniform vec4 sky_top_color : source_color = vec4(0.025, 0.045, 0.105, 1.0);
uniform vec4 sky_horizon_color : source_color = vec4(0.13, 0.19, 0.29, 1.0);
uniform float star_intensity : hint_range(0.0, 2.0) = 0.8;

float hash_2d(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void sky() {
	float elevation = max(EYEDIR.y, 0.0);
	float gradient = smoothstep(0.0, 0.72, elevation);
	vec3 sky_color = mix(sky_horizon_color.rgb, sky_top_color.rgb, gradient);
	if (EYEDIR.y < 0.0) {
		sky_color = sky_horizon_color.rgb * 0.24;
	}

	// Редкие неподвижные звёзды. Не добавляем их в радианс-кубмап,
	// чтобы отдельные пиксели не давали шумные отражения на машине.
	if (!AT_CUBEMAP_PASS && EYEDIR.y > 0.0) {
		vec2 star_uv = SKY_COORDS * vec2(360.0, 180.0);
		vec2 cell = floor(star_uv);
		float seed = hash_2d(cell);
		vec2 offset = vec2(hash_2d(cell + 11.3), hash_2d(cell + 39.7));
		float distance_to_star = length(fract(star_uv) - offset);
		float star = step(0.994, seed) * (1.0 - smoothstep(0.03, 0.15, distance_to_star));
		star *= smoothstep(0.04, 0.24, EYEDIR.y) * star_intensity;
		sky_color += vec3(0.65, 0.75, 1.0) * star;
	}

	if (LIGHT0_ENABLED && EYEDIR.y > 0.0) {
		float moon_dot = dot(normalize(LIGHT0_DIRECTION), EYEDIR);
		float halo = pow(max(moon_dot, 0.0), 350.0) * 0.12;
		float disc = smoothstep(0.99965, 0.99980, moon_dot);
		sky_color += LIGHT0_COLOR * (halo + disc * 1.25);
	}
	COLOR = sky_color;
}
