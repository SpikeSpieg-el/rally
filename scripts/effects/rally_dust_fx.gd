class_name RallyDustFx
extends RefCounted

enum Style {
	CRISP_CLOUDS, # Как на 1-й картинке: плотные чёткие облака без точек
	SOFT_FOR_BAYER, # Как на 2-й картинке: плотный мягкий дым, который экранный шейдер сам порежет в красивый PS1-дизер
}

const STYLE := Style.CRISP_CLOUDS # <-- Попробуйте оба!

static var _puff_texture: Texture2D = null
static var _fade_ramp: GradientTexture1D = null
static var _growth_curves: Dictionary = {}
static var _debris_fade: GradientTexture1D = null


static func puff_texture() -> Texture2D:
	if _puff_texture != null:
		return _puff_texture

	var size := 48
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 42
	noise.frequency = 0.08
	noise.fractal_octaves = 2

	for y in size:
		for x in size:
			var uv := Vector2(x, y) / float(size - 1) * 2.0 - Vector2.ONE
			var dist := uv.length()
			var n := noise.get_noise_2d(float(x), float(y)) * 0.28
			# Более жирное плотное ядро, чтобы не пропадало в дырки
			var alpha := clampf(1.0 - smoothstep(0.45, 0.96, dist + n), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	_puff_texture = ImageTexture.create_from_image(img)
	return _puff_texture


static func fade_ramp() -> GradientTexture1D:
	if _fade_ramp != null:
		return _fade_ramp
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.7))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.15, Color(1.0, 1.0, 1.0, 1.0))
	gradient.add_point(0.65, Color(1.0, 1.0, 1.0, 0.9))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 256
	_fade_ramp = texture
	return texture


static func debris_fade() -> GradientTexture1D:
	if _debris_fade != null:
		return _debris_fade
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.75, Color(1.0, 1.0, 1.0, 1.0))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 256
	_debris_fade = texture
	return texture


static func growth_curve(growth: float = 2.4) -> CurveTexture:
	var target: float = clampf(growth, 1.0, 6.0)
	var key := "%.3f" % target
	if _growth_curves.has(key):
		return _growth_curves[key] as CurveTexture
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.55))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(0.65, lerpf(1.0, target, 0.6)))
	curve.add_point(Vector2(1.0, target))
	var texture := CurveTexture.new()
	texture.curve = curve
	texture.resource_name = key
	_growth_curves[key] = texture
	return texture


static func puff_material(texture: Texture2D, unshaded: bool = true) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	if STYLE == Style.CRISP_CLOUDS:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.25
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	else:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED

	material.shading_mode = (
		BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = texture
	material.albedo_color = Color.WHITE
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	material.roughness = 1.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return material
