shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
// Лёгкая ретро-палитра и субпиксельная зернистость только для мира, не HUD.
uniform float retro_strength : hint_range(0.0, 1.0) = 0.35;
uniform float speed_intensity : hint_range(0.0, 1.0) = 0.0;

// Очень аккуратные значения, которые не искажают геометрию экрана
uniform float blur_strength : hint_range(0.0, 0.03) = 0.012;
uniform float aberration_strength : hint_range(0.0, 0.01) = 0.0025;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;

const int SAMPLES = 8;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 from_center = uv - vec2(0.5);
	float radius = length(from_center);
	vec2 dir = radius > 0.0001 ? from_center / radius : vec2(0.0);

	// Плавная кривая: убирает резкие скачки при колебаниях скорости
	float intensity = smoothstep(0.0, 1.0, speed_intensity);

	// Размываем только периферию экрана (центр от 0.0 до 0.35 вообще не трогаем)
	float mask = smoothstep(0.32, 0.85, radius) * intensity;

	vec3 accum = vec3(0.0);

	// Симметричное размытие (от -0.5 до +0.5): картинка НЕ смещается к центру или краям!
	for (int i = 0; i < SAMPLES; i++) {
		float t = (float(i) / float(SAMPLES - 1)) - 0.5;
		vec2 sample_uv = clamp(uv + dir * (t * blur_strength * mask), vec2(0.001), vec2(0.999));
		accum += texture(screen_texture, sample_uv).rgb;
	}
	vec3 color = accum / float(SAMPLES);
	// Небольшое смешивание с сеткой 720p вместо жёсткого пикселизации.
	vec2 retro_grid = vec2(1280.0, 720.0);
	vec2 pixel_uv = (floor(uv * retro_grid) + 0.5) / retro_grid;
	color = mix(color, texture(screen_texture, pixel_uv).rgb, retro_strength * 0.30);

	// Легкая хроматическая аберрация строго вокруг текущей точки
	vec2 ca_offset = dir * (aberration_strength * mask);
	color.r = texture(screen_texture, clamp(uv + ca_offset, vec2(0.001), vec2(0.999))).r * 0.5 + color.r * 0.5;
	color.b = texture(screen_texture, clamp(uv - ca_offset, vec2(0.001), vec2(0.999))).b * 0.5 + color.b * 0.5;

	// Виньетка
	float vignette = smoothstep(0.35, 0.90, radius) * intensity * vignette_strength;
	color *= 1.0 - vignette;

	float grain = fract(sin(dot(floor(FRAGCOORD.xy / 2.0), vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	vec3 retro_color = floor(clamp(color + grain / 64.0, 0.0, 1.0) * 40.0 + 0.5) / 40.0;
	color = mix(color, retro_color, retro_strength);
	COLOR = vec4(color, 1.0);
}