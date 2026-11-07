## Общие «кирпичики» мягких эффектов: круглое облачко, кривые жизни и материал.
##
## Одни и те же процедурные текстуры используют шлейф за машиной
## (rally_car.gd) и пыль из-под каждого колеса (surface_effects.gd).
## Внешних картинок нет: форму, прозрачность и рост настраивают поля
## RallyFxProfile / RallySurfaceFxProfile, а не файлы в textures/.
class_name RallyDustFx
extends RefCounted

## Кэш общий на процесс: текстура и кривые создаются один раз.
static var _puff_texture: GradientTexture2D = null
static var _fade_ramp: GradientTexture1D = null
## Кривые роста кэшируются по значению: у клубов и комьев они разные.
static var _growth_curves: Dictionary = {}
static var _debris_fade: GradientTexture1D = null


## Мягкое круглое пятно: белый центр и плавно прозрачные края.
## Это классическое облачко пыли, а не «шарик» с резкой границей.
static func puff_texture() -> GradientTexture2D:
	if _puff_texture != null:
		return _puff_texture
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	# Плотное ядро и длинный прозрачный хвост — облако не выглядит диском.
	gradient.add_point(0.35, Color(1.0, 1.0, 1.0, 0.72))
	gradient.add_point(0.70, Color(1.0, 1.0, 1.0, 0.22))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	_puff_texture = texture
	return texture


## Прозрачность клуба по времени жизни: появился, раздуло, растворился.
static func fade_ramp() -> GradientTexture1D:
	if _fade_ramp != null:
		return _fade_ramp
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.12, Color(1.0, 1.0, 1.0, 0.85))
	gradient.add_point(0.45, Color(1.0, 1.0, 1.0, 0.55))
	gradient.add_point(0.75, Color(1.0, 1.0, 1.0, 0.22))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 256
	_fade_ramp = texture
	return texture


## Прозрачность комьев грунта: гаснут медленнее клубов, без резкого обрыва.
static func debris_fade() -> GradientTexture1D:
	if _debris_fade != null:
		return _debris_fade
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.9))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.65, Color(1.0, 1.0, 1.0, 0.75))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 256
	_debris_fade = texture
	return texture


## Во сколько раз клуб вырастает к концу жизни (1 — не растёт).
## Рост ровно 1 — кривая не нужна: частица не меняет размер (дешевле на GPU).
static func growth_curve(growth: float = 2.4) -> CurveTexture:
	var target: float = clampf(growth, 1.0, 6.0)
	var key := "%.3f" % target
	if _growth_curves.has(key):
		return _growth_curves[key] as CurveTexture
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(0.22, 0.95))
	curve.add_point(Vector2(0.6, lerpf(0.95, target, 0.55)))
	curve.add_point(Vector2(1.0, target))
	var texture := CurveTexture.new()
	texture.curve = curve
	texture.resource_name = key
	_growth_curves[key] = texture
	return texture


## Материал клуба: прозрачная билборд-карточка с процедурным пятном.
## vertex_color_use_as_albedo включает цвет и прозрачность из ParticleProcessMaterial.
static func puff_material(texture: Texture2D, unshaded: bool = true) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = (
		BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = texture
	material.albedo_color = Color.WHITE
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Глубину клуб не пишет осознанно: у билборда одна глубина на весь квад, и
	# запись превратила бы соседние клубы в жёсткие вырезанные диски. Глубинный
	# ТЕСТ при этом включён, поэтому клуб всё равно прячется за тем, что уже
	# нарисовано до него. Просвечивание сквозь кузов лечится не выносом
	# источника (пыль должна рождаться у колеса), а размером клуба: бюджет
	# foam_size × foam_growth проверяется в tools/check_project.py.
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.disable_receive_shadows = true
	material.roughness = 1.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	return material
