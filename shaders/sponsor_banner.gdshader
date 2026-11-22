shader_type spatial;
render_mode blend_mix, depth_draw_always, unshaded;

// LSD-экран спонсора: светящаяся «жидкокристаллическая» панель на трассе.
// Показывает текущий баннер, а за `crossfade` секунд плавно растворяет его в
// следующем (смешение делает GDScript-скрипт — он даёт сюда готовое значение),
// затем снова держит и так повторяет цикл. Пока картинки заглушки, панель всё
// равно светится и мигает как настоящий рекламный экран.
//
// Поверх изображения всегда рисуется характерная для таких дисплеев рябь из
// горизонтальных «строк» (scanline) и блестящая полоса-блик сверху панели.

uniform sampler2D banner_a : source_color = null; // Баннер, который сейчас показан.
uniform sampler2D banner_b : source_color = null; // Следующий баннер для перехода.
uniform float crossfade : hint_range(0.0, 1.0) = 1.0;   // Прогресс перехода (0…1).
uniform bool lsd_scanlines : hint_default_false = true;  // Рябь «строк» экрана.
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.30;
uniform float scanline_frequency : hint_range(3.0, 80.0) = 26.0;

// Верхний «блик» на стекле панели — узкая горизонтальная полоса блеска (LCD).
uniform bool lsd_gloss_band : hint_default_false = true;
uniform float gloss_width : hint_range(0.01, 0.35) = 0.08;

// Лёгкое мерцание светимости — чтобы экран «дышал».
uniform float flicker_strength : hint_range(0.0, 0.4) = 0.06;

varying float v_flicker;

void fragment() {
	// Мерцание: от 1 до (1 + strength).
	v_flicker = 1.0 + sin(TIME * 9.0) * flicker_strength;

	// Текущая и следующая картинки с альфой, если баннер ещё не задан — подставляем
	// тёмно-серую поверхность панели вместо пустоты (чтобы экран не был чёрным).
	vec3 a_rgb = banner_a != null ? texture(banner_a, UV).rgb : vec3(0.16);
	float a_alpha = banner_a != null ? texture(banner_a, UV).a : clamp(v_flicker * 0.5, 0.0, 1.0);
	vec3 b_rgb = banner_b != null ? texture(banner_b, UV).rgb : vec3(0.24);
	float b_alpha = banner_b != null ? texture(banner_b, UV).a : clamp(v_flicker * 0.5, 0.0, 1.0);

	// Растворяем текущий баннер в следующем — градиент альфы тоже уходит вместе с ним.
	vec3 color := mix(a_rgb, b_rgb, crossfade) * v_flicker;
	float alpha := mix(a_alpha, b_alpha, crossfade);

	ALBEDO = vec4(color, 1.0);
	// Альфу вычисляем отдельно, чтобы панель растворилась плавно между логотипами,
	// а не исчезла целиком — читается как работающий ЖК-дисплей.
	ALPHA = clamp(alpha, 0.0, 1.0);

	// Верхний «блик» на стекле панели — узкая полоса блеска у верхнего края.
	if (lsd_gloss_band) {
		float gloss = smoothstep(gloss_width, 0.0, abs(UV.y - 0.04)) * color.a;
		ALBEDO.rgb += vec3(1.0) * gloss * 0.95;
	}

	// Рябь «строк» у жидкокристаллических экранов: горизонтальные тёмные полоски с
	// лёгким скроллом по вертикали — признак живого, работающего дисплея.
	if (lsd_scanlines) {
		float row = sin(UV.y * scanline_frequency + TIME * 1.5);
		row = clamp(pow(2.0 - abs(row), 4.0), 0.0, 1.0) * scanline_strength;
		ALPHA *= (1.0 - row * 0.85);
	}
}
