shader_type spatial;
render_mode specular_schlick_ggx;

uniform float map_profile = 1.0;

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
    if (map_profile < 1.5) {
        return 10.0 * sin(z * 0.025) + 5.0 * sin(z * 0.061);
    }
    return 8.0 * sin(z * 0.032) + 4.0 * sin(z * 0.075);
}

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
    float distance_to_road = abs(world_pos.x - route_center(world_pos.z));
    float road = 1.0 - smoothstep(3.9, 5.3, distance_to_road);
    float broad_noise = value_noise(world_pos.xz * 0.065);
    float fine_noise = value_noise(world_pos.xz * 2.4);

    vec3 forest_floor = mix(vec3(0.075, 0.15, 0.065), vec3(0.19, 0.245, 0.105), broad_noise);
    forest_floor *= mix(0.78, 1.12, fine_noise);
    vec3 gravel = mix(vec3(0.23, 0.18, 0.125), vec3(0.40, 0.325, 0.225), fine_noise);

    float wheel_track = exp(-pow((distance_to_road - 1.15) / 0.48, 2.0));
    gravel *= 1.0 - wheel_track * 0.12;
    float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
    forest_floor = mix(forest_floor, vec3(0.24, 0.205, 0.15), slope * 0.65);

    ALBEDO = mix(forest_floor, gravel, road);
    ROUGHNESS = 0.97;
    SPECULAR = 0.16;
}
