shader_type spatial;
render_mode cull_disabled;

varying vec3 soil_position;
void vertex() {
	soil_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 cell = floor(soil_position * 145.0);
	float grain = fract(sin(dot(cell, vec3(127.1, 311.7, 74.7))) * 43758.5453);
	ALBEDO = COLOR.rgb * mix(0.68, 1.3, grain);
	ROUGHNESS = 0.98;
	SPECULAR = 0.14;
}
