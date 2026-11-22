shader_type spatial;
render_mode unshaded, cull_back;

// ЖК-экран спонсора: светящаяся панель, которая показывает баннеры из атласа
// (по умолчанию textures/4XSponsorBanners.png — 2×2 картинки) и каждые
// cycle_time секунд плавно растворяет текущий в следующем. Поверх — рябь
// строк, мерцание и блик стекла, как у работающего рекламного дисплея.
//
// Всё переключение считается здесь по TIME, без скрипта: щиты вдоль трассы
// запекаются в MultiMesh, где скрипты не работают, а шейдер — работает.
// Фаза берётся из положения щита, поэтому соседние щиты не мигают хором.

// Атлас баннеров: картинки одинакового размера, сеткой atlas_grid (колонки, строки).
uniform sampler2D banner_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform ivec2 atlas_grid = ivec2(2, 2);
// Сколько ячеек атласа реально занято (считаются слева направо, сверху вниз).
uniform int banner_count : hint_range(1, 16) = 4;
// Сколько секунд показывается один баннер, включая переход.
uniform float cycle_time : hint_range(0.5, 60.0) = 3.0;
// Длительность плавного перехода в конце цикла, секунды.
uniform float crossfade_time : hint_range(0.0, 5.0) = 0.6;
// Разносить щиты по времени (фаза зависит от положения щита в мире).
uniform bool random_phase = true;

// Яркость свечения экрана (больше 1 — подсвечивает glow окружения).
uniform float brightness : hint_range(0.0, 4.0) = 1.15;
// Рябь горизонтальных «строк» экрана.
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.3;
uniform float scanline_frequency : hint_range(3.0, 400.0) = 140.0;
// Лёгкое мерцание яркости.
uniform float flicker_strength : hint_range(0.0, 0.4) = 0.04;
// Блестящая полоса-блик у верхнего края (стекло LCD).
uniform float gloss_strength : hint_range(0.0, 1.0) = 0.35;
uniform float gloss_width : hint_range(0.01, 0.35) = 0.08;

varying float v_phase;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	v_phase = random_phase ? fract(sin(dot(origin, vec3(12.9898, 78.233, 37.719))) * 43758.5453) : 0.0;
}

vec3 banner_color(int index, vec2 uv) {
	int cols = max(atlas_grid.x, 1);
	int rows = max(atlas_grid.y, 1);
	vec2 cell = vec2(float(index % cols), float((index / cols) % rows));
	vec2 cell_size = vec2(1.0 / float(cols), 1.0 / float(rows));
	// Полпикселя отступа от края ячейки, чтобы не подмешивался соседний баннер.
	vec2 inset = 0.5 / vec2(textureSize(banner_atlas, 0));
	vec2 local = clamp(uv, inset / cell_size, 1.0 - inset / cell_size);
	return texture(banner_atlas, (cell + local) * cell_size).rgb;
}

void fragment() {
	int count = max(banner_count, 1);
	float cycle = max(cycle_time, 0.1);
	float fade = clamp(crossfade_time, 0.0, cycle * 0.9);
	float t = TIME / cycle + v_phase * float(count);
	float step_index = floor(t);
	float in_cycle = (t - step_index) * cycle;
	int current = int(mod(step_index, float(count)));
	int next = (current + 1) % count;
	float mix_amount = 0.0;
	if (fade > 0.0) {
		mix_amount = smoothstep(cycle - fade, cycle, in_cycle);
	}

	vec3 color = mix(banner_color(current, UV), banner_color(next, UV), mix_amount);

	// Строки экрана медленно ползут вниз — признак живого дисплея.
	float row = 0.5 + 0.5 * sin((UV.y * scanline_frequency - TIME * 3.0) * 6.2831853);
	color *= 1.0 - scanline_strength * 0.5 * row;
	color *= 1.0 + sin(TIME * 9.0 + v_phase * 40.0) * flicker_strength;
	color *= brightness;
	// Блик стекла у верхнего края.
	float gloss = smoothstep(gloss_width, 0.0, abs(UV.y - gloss_width));
	color += vec3(gloss * gloss_strength);

	ALBEDO = color;
}
