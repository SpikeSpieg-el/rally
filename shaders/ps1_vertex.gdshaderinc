// Небольшая привязка вершин к экранной сетке. Коллизии и мировые
// координаты не меняются; вызов выполняется только для основной камеры.
vec4 ps1_snap_vertex(vec4 clip, vec2 viewport_size, float resolution_y, float strength) {
	if (strength <= 0.0 || clip.w <= 0.001) {
		return clip;
	}
	float height = min(max(resolution_y, 1.0), viewport_size.y);
	vec2 grid = vec2(height * viewport_size.x / max(viewport_size.y, 1.0), height);
	vec2 pixel = (clip.xy / clip.w) * grid * 0.5;
	vec2 snapped = floor(pixel + 0.5);
	clip.xy = mix(pixel, snapped, strength) * 2.0 / grid * clip.w;
	return clip;
}
