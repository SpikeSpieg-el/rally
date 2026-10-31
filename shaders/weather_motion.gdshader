shader_type canvas_item;

// Ближний слой осадков дополняет мировые частицы; HUD рисуется поверх него.
uniform float weather_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float speed_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float is_snow : hint_range(0.0, 1.0) = 0.0;
uniform float phase = 0.0;
uniform vec2 flow = vec2(0.0, 1.0);

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	// Несколько ячеек на экран: положение частиц детерминировано, без шума кадра.
	vec2 grid = vec2(36.0, 23.0);
	vec2 p = uv * grid - flow * phase;
	vec2 cell = floor(p);
	vec2 local = fract(p) - vec2(0.5);
	float seed = hash21(cell);
	local.x += (hash21(cell + 9.3) - 0.5) * 0.65;
	local.y += (hash21(cell + 2.7) - 0.5) * 0.65;
	// Косые штрихи становятся длиннее по мере набора скорости.
	float tilt = clamp(flow.x * 0.5, -0.65, 0.65);
	local.x -= local.y * tilt;
	float width = mix(0.045, 0.085, is_snow);
	float height = mix(mix(0.12, 0.38, speed_intensity), mix(0.09, 0.20, speed_intensity), is_snow);
	float shape = (1.0 - smoothstep(width * 0.35, width, abs(local.x))) *
		(1.0 - smoothstep(height * 0.45, height, abs(local.y)));
	float density = step(0.56, seed);
	// Центральная часть дороги остаётся хорошо читаемой.
	float edge = smoothstep(0.08, 0.55, length(uv - vec2(0.5)));
	float alpha = shape * density * weather_intensity * speed_intensity * mix(0.10, 0.28, edge);
	COLOR = vec4(mix(vec3(0.70, 0.82, 0.95), vec3(0.94, 0.97, 1.0), is_snow), alpha);
}
