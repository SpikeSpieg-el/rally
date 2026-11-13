class_name RallyDustFx
extends RefCounted

enum Style {
	CRISP_CLOUDS, # Как на 1-й картинке: плотные чёткие облака без точек
	SOFT_FOR_BAYER, # Как на 2-й картинке: плотный мягкий дым, который экранный шейдер сам порежет в красивый PS1-дизер
}

const STYLE := Style.SOFT_FOR_BAYER # <-- Попробуйте оба!

static var _puff_texture: Texture2D = null
static var _fade_ramp: GradientTexture1D = null
static var _growth_curves: Dictionary = {}
static var _debris_fade: GradientTexture1D = null
static var _debris_scale_curve: CurveTexture = null
static var _debris_color_variation: GradientTexture1D = null


static func puff_texture() -> Texture2D:
	if _puff_texture != null:
		return _puff_texture

	if STYLE == Style.CRISP_CLOUDS:
		var crisp_size := 48
		var crisp_img := Image.create_empty(crisp_size, crisp_size, false, Image.FORMAT_RGBA8)
		var crisp_noise := FastNoiseLite.new()
		crisp_noise.seed = 42
		crisp_noise.frequency = 0.08
		crisp_noise.fractal_octaves = 2

		for y in crisp_size:
			for x in crisp_size:
				var uv := Vector2(x, y) / float(crisp_size - 1) * 2.0 - Vector2.ONE
				var dist := uv.length()
				var n := crisp_noise.get_noise_2d(float(x), float(y)) * 0.28
				var alpha := clampf(1.0 - smoothstep(0.45, 0.96, dist + n), 0.0, 1.0)
				crisp_img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

		_puff_texture = ImageTexture.create_from_image(crisp_img)
		return _puff_texture

	# SOFT_FOR_BAYER: многодольный мягкий клуб с плавным градиентом альфы к краям,
	# чтобы экранный PS1-шейдер красиво нарезал шлейф Bayer-дизером без рваных дыр.
	var size := 64
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 42
	noise.frequency = 0.075
	noise.fractal_octaves = 3
	noise.fractal_gain = 0.55

	var lobes := [
		Vector3(0.0, 0.05, 0.82),
		Vector3(-0.27, -0.10, 0.62),
		Vector3(0.28, -0.06, 0.60),
		Vector3(-0.08, 0.26, 0.54),
	]

	for y in size:
		for x in size:
			var uv := Vector2(x, y) / float(size - 1) * 2.0 - Vector2.ONE
			var dist := uv.length()
			var density := 0.0
			for lobe in lobes:
				var center := Vector2(lobe.x, lobe.y)
				var radius: float = lobe.z
				var d := (uv - center).length() / radius
				var falloff := pow(clampf(1.0 - d, 0.0, 1.0), 1.45)
				density = maxf(density, falloff)
			var n := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var edge_mask := 1.0 - smoothstep(0.68, 0.98, dist)
			var alpha := clampf(density * lerpf(0.76, 1.08, n) * edge_mask, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	_puff_texture = ImageTexture.create_from_image(img)
	return _puff_texture


static func fade_ramp() -> GradientTexture1D:
	if _fade_ramp != null:
		return _fade_ramp
	var gradient := Gradient.new()
	if STYLE == Style.CRISP_CLOUDS:
		gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.7))
		gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		gradient.add_point(0.15, Color(1.0, 1.0, 1.0, 1.0))
		gradient.add_point(0.65, Color(1.0, 1.0, 1.0, 0.9))
	else:
		gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
		gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		gradient.add_point(0.12, Color(1.0, 1.0, 1.0, 0.92))
		gradient.add_point(0.34, Color(1.0, 1.0, 1.0, 1.0))
		gradient.add_point(0.64, Color(1.0, 1.0, 1.0, 0.68))
		gradient.add_point(0.86, Color(1.0, 1.0, 1.0, 0.26))
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
	gradient.add_point(0.72, Color(1.0, 1.0, 1.0, 1.0))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 256
	_debris_fade = texture
	return texture


static func debris_scale_curve() -> CurveTexture:
	if _debris_scale_curve != null:
		return _debris_scale_curve
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.85))
	curve.add_point(Vector2(0.15, 1.0))
	curve.add_point(Vector2(0.58, 0.92))
	curve.add_point(Vector2(1.0, 0.25))
	var texture := CurveTexture.new()
	texture.curve = curve
	texture.resource_name = "debris_scale"
	_debris_scale_curve = texture
	return texture


static func debris_color_variation() -> GradientTexture1D:
	if _debris_color_variation != null:
		return _debris_color_variation
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.32, 0.29, 0.26, 1.0))
	gradient.set_color(1, Color(1.0, 0.96, 0.90, 1.0))
	gradient.add_point(0.45, Color(0.62, 0.58, 0.53, 1.0))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 64
	_debris_color_variation = texture
	return texture


static func growth_curve(growth: float = 2.4) -> CurveTexture:
	var target: float = clampf(growth, 1.0, 6.0)
	var key := "%.3f" % target
	if _growth_curves.has(key):
		return _growth_curves[key] as CurveTexture
	var curve := Curve.new()
	if STYLE == Style.CRISP_CLOUDS:
		curve.add_point(Vector2(0.0, 0.55))
		curve.add_point(Vector2(0.25, 1.0))
		curve.add_point(Vector2(0.65, lerpf(1.0, target, 0.6)))
		curve.add_point(Vector2(1.0, target))
	else:
		curve.add_point(Vector2(0.0, 0.35))
		curve.add_point(Vector2(0.18, 0.85))
		curve.add_point(Vector2(0.55, lerpf(0.85, target, 0.65)))
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
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	else:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
		material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR

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
	return material
