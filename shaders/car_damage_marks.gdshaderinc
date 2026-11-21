// Следы ударов на краске: царапины, сколы до грунта, голый металл и копоть.
//
// Общий кусок для слоя грязи кузова (car_dirt.gdshader) и отдельного слоя
// следов (car_damage_marks.gdshader), когда грязи на машине нет. Положения
// следов — в системе машины, как у грязи и крови: следы не «плывут» на ходу.
// Массивы заполняет CarDamageVisual (scripts/car_damage_visual.gd), а цвета и
// частоту штрихов — из RallyDamageVisualConfig (data/car/default_damage_visual.tres).
//
// Значений по умолчанию у массивов нет (Godot их не принимает): пустые слоты
// приходят нулями, сила 0 — и след пропускается.

// Центр следа в системе машины.
uniform vec3 damage_mark_pos[16];
// xyz — направление скольжения (вдоль него тянутся царапины), w — вытянутость.
uniform vec4 damage_mark_axis[16];
// xyz — куда вдавлен металл (внутрь кузова), w — 0 удар, 1 царапина вдоль забора.
uniform vec4 damage_mark_normal[16];
// x — сила 0..1, y — радиус, м, z — случайное зерно, w — копоть 0..1.
uniform vec4 damage_mark_data[16];
uniform vec3 damage_primer_color : source_color = vec3(0.58, 0.58, 0.55);
uniform vec3 damage_metal_color : source_color = vec3(0.78, 0.79, 0.81);
uniform vec3 damage_soot_color : source_color = vec3(0.05, 0.045, 0.04);
uniform float damage_metal_gloss : hint_range(0.0, 1.0) = 0.7;
uniform float damage_scratch_frequency : hint_range(10.0, 300.0) = 70.0;
uniform float damage_marks_opacity : hint_range(0.0, 1.0) = 0.95;

float dmg_hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float dmg_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(dmg_hash(i), dmg_hash(i + vec3(1.0, 0.0, 0.0)), f.x),
		mix(dmg_hash(i + vec3(0.0, 1.0, 0.0)), dmg_hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(dmg_hash(i + vec3(0.0, 0.0, 1.0)), dmg_hash(i + vec3(1.0, 0.0, 1.0)), f.x),
		mix(dmg_hash(i + vec3(0.0, 1.0, 1.0)), dmg_hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

// pos и nrm — точка и нормаль поверхности в системе машины.
// Возвращает непрозрачность слоя следов; цвет и блеск — через out.
float damage_marks(vec3 pos, vec3 nrm, out vec3 albedo, out float roughness, out float specular) {
	float primer = 0.0;
	float metal = 0.0;
	float soot = 0.0;
	for (int i = 0; i < 16; i++) {
		vec4 data = damage_mark_data[i];
		if (data.x < 0.01) { continue; }
		vec3 into = damage_mark_normal[i].xyz;
		float into_len = length(into);
		into = into_len > 0.001 ? into / into_len : vec3(0.0, 0.0, -1.0);
		float scrape = clamp(damage_mark_normal[i].w, 0.0, 1.0);
		vec3 axis = damage_mark_axis[i].xyz;
		float axis_len = length(axis);
		axis = axis_len > 0.001 ? axis / axis_len : normalize(cross(into, vec3(0.0, 1.0, 0.01)));
		float stretch = max(damage_mark_axis[i].w, 1.0);
		float radius = max(data.y, 0.04);
		float seed = data.z;

		vec3 d = pos - damage_mark_pos[i];
		float depth_d = dot(d, into);
		vec3 lat = d - into * depth_d;
		float along = dot(lat, axis);
		float across = length(lat - axis * along);
		// Только грани, повёрнутые к удару: след не пробивает кузов насквозь
		// и не ложится на противоположный борт.
		float facing = smoothstep(-0.3, 0.25, dot(nrm, -into));
		float depth_fade = 1.0 - smoothstep(radius * 0.9, radius * 1.8, abs(depth_d));
		float e = length(vec2(along / (radius * stretch), across / radius));
		vec3 seed3 = vec3(seed, seed * 1.37, seed * 0.71);
		float edge_noise = dmg_noise(d * 9.0 + seed3);
		float region = 1.0 - smoothstep(0.5, 1.05, e + (edge_noise - 0.5) * 0.5);
		region *= facing * depth_fade * clamp(data.x, 0.0, 1.0);
		if (region < 0.002) { continue; }

		// Штрихи: частые поперёк скольжения, длинные вдоль.
		float lines = dmg_noise(vec3(across * damage_scratch_frequency, along * 2.5, seed));
		float fine = dmg_noise(vec3(across * damage_scratch_frequency * 2.3, along * 5.0, seed * 2.1));
		float scratch = smoothstep(0.60, 0.80, lines * 0.7 + fine * 0.3);
		// Сколы краски пятнами до грунта — гуще в центре удара.
		float chips_n = dmg_noise(d * 24.0 + seed3 * 1.9);
		float chips = smoothstep(0.62 - region * 0.35, 0.80 - region * 0.35, chips_n);
		float scratch_w = mix(0.55, 1.0, scrape);
		float chip_w = mix(1.0, 0.45, scrape);
		primer = max(primer, max(chips * chip_w, scratch * scratch_w * 0.6) * region);
		metal = max(metal, scratch * scratch_w * smoothstep(0.25, 0.85, region) * region);
		float core = 1.0 - smoothstep(0.0, 0.7, e + (edge_noise - 0.5) * 0.3);
		soot = max(soot, core * clamp(data.w, 0.0, 1.0) * facing * depth_fade * (0.6 + 0.4 * chips_n));
	}
	float alpha = clamp(max(primer, metal) + soot * 0.7, 0.0, 1.0) * damage_marks_opacity;
	float metal_mix = clamp(metal / max(max(primer, metal), 0.001), 0.0, 1.0);
	vec3 col = mix(damage_primer_color, damage_metal_color, metal_mix);
	float soot_mix = clamp(soot / max(alpha, 0.001), 0.0, 1.0);
	albedo = mix(col, damage_soot_color, soot_mix * 0.85);
	roughness = mix(mix(0.8, 1.0 - damage_metal_gloss * 0.8, metal_mix), 0.95, soot_mix);
	specular = mix(mix(0.25, 0.5 + damage_metal_gloss * 0.4, metal_mix), 0.1, soot_mix);
	return alpha;
}
