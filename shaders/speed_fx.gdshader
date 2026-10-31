shader_type canvas_item;

// Экран читается после 3D и осадков, но до HUD. Виртуальная сетка сохраняет
// квадратные пиксели при любом соотношении сторон и размере окна.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float retro_strength : hint_range(0.0, 1.0) = 1.0;
uniform float resolution_y : hint_range(180.0, 720.0) = 270.0;
// 31 ступень на канал = 5 бит, 0 выключает ограничение палитры.
uniform float color_levels : hint_range(0.0, 255.0) = 31.0;
uniform float dither_strength : hint_range(0.0, 1.0) = 1.0;
uniform float speed_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float blur_strength : hint_range(0.0, 0.03) = 0.012;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.12;

// Упорядоченная матрица Bayer 4x4: стабильна во времени и привязана к
// виртуальным пикселям, поэтому туман не мерцает случайным шумом.
float bayer2(vec2 p) {
	vec2 cell = mod(p, 2.0);
	if (cell.y < 1.0) {
		return cell.x < 1.0 ? 0.0 : 2.0;
	}
	return cell.x < 1.0 ? 3.0 : 1.0;
}

float bayer4(vec2 p) {
	return (4.0 * bayer2(p) + bayer2(floor(p * 0.5)) + 0.5) / 16.0;
}

vec2 pixel_uv(vec2 uv, vec2 grid) {
	return (floor(clamp(uv, vec2(0.0), vec2(0.999999)) * grid) + 0.5) / grid;
}

vec3 sample_world(vec2 uv, vec2 grid, vec2 screen_pixel_size) {
	uv = clamp(uv, screen_pixel_size * 0.5, vec2(1.0) - screen_pixel_size * 0.5);
	if (retro_strength <= 0.0) {
		return texture(screen_texture, uv).rgb;
	}
	vec3 pixel = texture(screen_texture, pixel_uv(uv, grid)).rgb;
	if (retro_strength >= 1.0) {
		return pixel;
	}
	return mix(texture(screen_texture, uv).rgb, pixel, retro_strength);
}

void fragment() {
	vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
	float height = min(max(resolution_y, 1.0), screen_size.y);
	vec2 grid = vec2(max(1.0, floor(height * screen_size.x / screen_size.y + 0.5)), height);
	vec2 uv = SCREEN_UV;
	vec2 effect_uv = mix(uv, pixel_uv(uv, grid), retro_strength);
	vec2 from_center = effect_uv - vec2(0.5);
	float radius = length(from_center);
	vec2 dir = radius > 0.0001 ? from_center / radius : vec2(0.0);
	float intensity = smoothstep(0.0, 1.0, speed_intensity);
	float mask = smoothstep(0.32, 0.85, radius) * intensity;

	vec3 color = sample_world(uv, grid, SCREEN_PIXEL_SIZE);
	if (mask > 0.001) {
		// Симметричные выборки не сдвигают картинку; центр дороги остаётся резким.
		vec3 blurred = vec3(0.0);
		for (int i = 0; i < 4; i++) {
			float t = float(i) / 3.0 - 0.5;
			blurred += sample_world(effect_uv + dir * t * blur_strength * mask, grid, SCREEN_PIXEL_SIZE);
		}
		color = mix(color, blurred * 0.25, mask);
	}

	// Чуть приглушённая палитра сохраняет различия дня, ночи, снега и фар.
	float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(color, vec3(luminance), retro_strength * 0.08);
	float vignette = smoothstep(0.35, 0.90, radius) * (retro_strength * vignette_strength + intensity * 0.18);
	color *= 1.0 - vignette;

	if (retro_strength > 0.0 && color_levels >= 1.0) {
		float threshold = mix(0.5, bayer4(floor(uv * grid)), dither_strength);
		vec3 quantized = floor(clamp(color, 0.0, 1.0) * color_levels + threshold) / color_levels;
		color = mix(color, quantized, retro_strength);
	}
	COLOR = vec4(color, 1.0);
}
