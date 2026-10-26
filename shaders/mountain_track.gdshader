shader_type spatial;
render_mode specular_schlick_ggx;

// Плоская трасса-полигон. Цвета и ширина полосы задаются ресурсом трассы.
uniform vec3 grass_color : source_color = vec3(0.16, 0.235, 0.105);
uniform vec3 dirt_color : source_color = vec3(0.36, 0.295, 0.205);
uniform float strip_half_width : hint_range(6.0, 60.0) = 24.0;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.96;

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

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
    float broad_noise = value_noise(world_pos.xz * 0.055);
    float grain = value_noise(world_pos.xz * 1.9);
    float driving_strip = 1.0 - smoothstep(strip_half_width - 8.0, strip_half_width + 10.0, abs(world_pos.x));

    vec3 grass = grass_color * mix(0.82, 1.15, broad_noise);
    vec3 packed_dirt = dirt_color * mix(0.80, 1.18, grain);
    vec3 surface_color = mix(grass, packed_dirt, driving_strip);

    float normal_light = mix(0.92, 1.0, clamp(world_normal.y, 0.0, 1.0));
    ALBEDO = surface_color * normal_light;
    ROUGHNESS = surface_roughness;
    SPECULAR = 0.18;
}
