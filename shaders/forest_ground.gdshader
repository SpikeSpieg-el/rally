shader_type spatial;
render_mode specular_schlick_ggx;

// PS1-ландшафт (Colin McRae Rally): плоское тиснение, вершинные цвета
// (R — влияние дороги, G — крутизна склона, B — шум), жёсткий дизер-туман.
// Параметры выставляются из scripts/rally_stage.gd — те же значения,
// что использует генератор рельефа и коллизий. Всё редактируется ресурсом трассы.
uniform vec3 ground_color : source_color = vec3(0.10, 0.17, 0.07);
uniform vec3 ground_color_2 : source_color = vec3(0.21, 0.26, 0.11);
uniform vec3 road_edge_color : source_color = vec3(0.31, 0.25, 0.17);
uniform vec3 rock_color : source_color = vec3(0.29, 0.31, 0.32);
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.97;
uniform float grain_scale : hint_range(0.1, 6.0) = 2.4;

uniform float flat_shading : hint_range(0.0, 1.0) = 1.0;
uniform float dither_fog : hint_range(0.0, 1.0) = 1.0;
uniform float banding_levels : hint_range(0.0, 8.0) = 5.0;
uniform vec3 fog_color : source_color = vec3(0.72, 0.79, 0.88);
uniform float fog_near : hint_range(10.0, 400.0) = 130.0;
uniform float fog_far : hint_range(50.0, 800.0) = 320.0;
// Погода: сырая земля темнее, снег ложится на пологие места.
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float snow_cover : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec4 vertex_info;

float hash_2d(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float value_noise(vec2 p) {
    vec2 cell = floor(p);
    vec2 local = fract(p);
    vec2 blend = local * local * (3.0 - 2.0 * local);
    float a = hash_2d(cell);
    float b = hash_2d(cell + vec2(1.0, 0.0));
    float c = hash_2d(cell + vec2(0.0, 1.0));
    float d = hash_2d(cell + vec2(1.0, 1.0));
    return mix(mix(a, b, blend.x), mix(c, d, blend.x), blend.y);
}

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
    vertex_info = COLOR;
}

void fragment() {
    vec3 normal = normalize(world_normal);
    if (flat_shading > 0.5) {
        // PS1-тиснение: плоская нормаль поверхность-специфичная.
        vec3 fn = cross(dFdx(world_pos), dFdy(world_pos));
        if (fn.y < 0.0) {
            fn = -fn;
        }
        normal = normalize(fn);
    }
    float slope = clamp(1.0 - normal.y, 0.0, 1.0);

    float broad_noise = value_noise(world_pos.xz * 0.05);
    float fine_noise = value_noise(world_pos.xz * grain_scale);

    vec3 ground = mix(ground_color, ground_color_2, broad_noise);
    ground *= mix(0.80, 1.14, fine_noise);

    // Обочина: твёрдый грунт рядом с дорогой (по вершинному цвету R).
    float road_influence = vertex_info.r;  // 0 = дорога, 1 = вне дороги
    float shoulder = smoothstep(0.0, 0.3, road_influence);
    vec3 albedo = mix(road_edge_color, ground, shoulder);

    // Камни на крутых склонах (по вершинному цвету G).
    float rock_amt = smoothstep(0.55, 0.85, slope) * vertex_info.g;
    albedo = mix(albedo, rock_color * mix(0.80, 1.15, vertex_info.b), rock_amt);

    // Дождь темнит и «лакирует» грунт, снег укрывает ровные места.
    albedo *= mix(1.0, 0.78, wetness);
    float snow_amount = snow_cover * (1.0 - smoothstep(0.15, 0.65, slope));
    albedo = mix(albedo, vec3(0.88, 0.91, 0.96) * mix(0.92, 1.04, fine_noise), snow_amount);
    ALBEDO = albedo;
    ROUGHNESS = mix(surface_roughness, 0.62, snow_amount);
    SPECULAR = mix(mix(0.16, 0.42, wetness), 0.10, snow_amount);

    // PS1-дизер-туман: жёсткие прямоугольные полосы вместо плавного затенения.
	if (dither_fog > 0.5) {
		vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
        float dist = length(world_pos - cam);
        float dith = fract(sin(dot(world_pos.xz * 0.31 + cam.xz * 0.17, vec2(12.9898, 78.233))) * 43758.5453);
        float band = step(fog_near + dith * (fog_far - fog_near), dist);
        ALBEDO = mix(ALBEDO, fog_color, band * smoothstep(fog_near, fog_near + 30.0, dist));
    }

    // Постеризация (PS1-палитра).
    if (banding_levels >= 2.0) {
        ALBEDO = floor(ALBEDO * banding_levels + 0.5) / banding_levels;
    }
}
