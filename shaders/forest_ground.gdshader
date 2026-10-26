shader_type spatial;
render_mode specular_schlick_ggx;

// Параметры маршрута выставляются из scripts/rally_stage.gd — те же значения,
// что использует генератор рельефа и коллизий. Всё редактируется ресурсом трассы.
uniform vec3 route_amp = vec3(11.0, 5.0, 1.0);
uniform vec3 route_freq = vec3(0.026, 0.061, 0.011);
uniform vec3 route_phase = vec3(0.0, 0.0, 0.0);
uniform float road_half_width : hint_range(2.0, 14.0) = 4.3;

uniform vec3 ground_color : source_color = vec3(0.085, 0.165, 0.070);
uniform vec3 ground_color_2 : source_color = vec3(0.20, 0.255, 0.105);
uniform vec3 road_color : source_color = vec3(0.34, 0.275, 0.19);
uniform vec3 road_color_2 : source_color = vec3(0.46, 0.375, 0.265);
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.97;
uniform float grain_scale : hint_range(0.1, 6.0) = 2.4;

varying vec3 world_pos;
varying vec3 world_normal;

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

float route_center(float z) {
    return route_amp.x * sin(z * route_freq.x + route_phase.x)
        + route_amp.y * sin(z * route_freq.y + route_phase.y)
        + route_amp.z * sin(z * route_freq.z + route_phase.z);
}

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
    float distance_to_road = abs(world_pos.x - route_center(world_pos.z));
    float road = 1.0 - smoothstep(road_half_width - 0.35, road_half_width + 1.1, distance_to_road);
    float broad_noise = value_noise(world_pos.xz * 0.065);
    float fine_noise = value_noise(world_pos.xz * grain_scale);

    vec3 forest_floor = mix(ground_color, ground_color_2, broad_noise);
    forest_floor *= mix(0.80, 1.14, fine_noise);
    vec3 gravel = mix(road_color, road_color_2, fine_noise);

    float wheel_track = exp(-pow((distance_to_road - road_half_width * 0.28) / 0.48, 2.0));
    gravel *= 1.0 - wheel_track * 0.12;
    float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
    forest_floor = mix(forest_floor, road_color * 0.8, slope * 0.55);

    ALBEDO = mix(forest_floor, gravel, road);
    ROUGHNESS = surface_roughness;
    SPECULAR = 0.16;
}
