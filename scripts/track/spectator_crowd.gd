## «Островок жизни» на повороте: спрайтовые зрители в стиле PS1, лагерь
## болельщиков, костёр и фотовспышки.
##
## Люди — плоские билборды из процедурной пиксельной текстуры 24×40
## (силуэт в яркой куртке), никаких 3D-моделей и скелетов. Два фотографа
## стоят у самой кромки и ОТСКАКИВАЮТ назад, когда машина подходит ближе
## ~22 м, — классика ралли-игр. Вспышки срабатывают только когда машина
## в радиусе 130 м: днём их не видно, ночью они и дают эффект CMR 2.0.
##
## Один узел = один поворот. _process дёшев: проверка дистанции до машины
## раз в кадр и пара lerp'ов; физика и коллизии зрителям не нужны.
class_name RallySpectatorCrowd
extends Node3D

const PERSON_W := 24
const PERSON_H := 40
const JACKETS: Array[Color] = [
	Color(0.95, 0.25, 0.15), Color(0.98, 0.75, 0.10), Color(0.15, 0.45, 0.95),
	Color(0.20, 0.80, 0.35), Color(0.95, 0.55, 0.10), Color(0.85, 0.85, 0.90),
]

static var _person_textures: Array = []
static var _flash_texture: Texture2D = null

var _stage: Node = null
var _flashes: Array[Sprite3D] = []
var _flash_timers: PackedFloat32Array = PackedFloat32Array()
var _fleeing: Array = []  # [{sprite, home: Vector3, away: Vector3, t: float}]
var _fire_light: OmniLight3D = null
var _rng := RandomNumberGenerator.new()
var _time: float = 0.0


static func _person_texture(variant: int) -> Texture2D:
	if not _person_textures.is_empty():
		return _person_textures[variant % _person_textures.size()]
	for v in range(JACKETS.size()):
		var image := Image.create(PERSON_W, PERSON_H, false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 0))
		var jacket: Color = JACKETS[v]
		var pants := Color(0.12, 0.12, 0.16)
		var skin := Color(0.92, 0.72, 0.55)
		# Ноги, куртка, голова, шапка — прямоугольники, как на спрайтах PS1.
		image.fill_rect(Rect2i(8, 28, 3, 11), pants)
		image.fill_rect(Rect2i(13, 28, 3, 11), pants)
		image.fill_rect(Rect2i(7, 13, 10, 16), jacket)
		image.fill_rect(Rect2i(5, 14, 2, 10), jacket.darkened(0.15))
		image.fill_rect(Rect2i(17, 14, 2, 10), jacket.darkened(0.15))
		image.fill_rect(Rect2i(9, 5, 6, 7), skin)
		image.fill_rect(Rect2i(8, 3, 8, 3), jacket.darkened(0.35))
		_person_textures.append(ImageTexture.create_from_image(image))
	return _person_textures[variant % _person_textures.size()]


static func _make_flash_texture() -> Texture2D:
	if _flash_texture != null:
		return _flash_texture
	var size: int = 32
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var center := Vector2(size, size) * 0.5
	for y in range(size):
		for x in range(size):
			var d: float = Vector2(x, y).distance_to(center) / (float(size) * 0.5)
			if d < 1.0:
				var a: float = pow(1.0 - d, 2.0)
				image.set_pixel(x, y, Color(1.0, 1.0, 0.95, a))
	_flash_texture = ImageTexture.create_from_image(image)
	return _flash_texture


func _make_person(variant: int, pos: Vector3, flee_away: Vector3) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = _person_texture(variant)
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.shaded = false
	sprite.pixel_size = 0.045
	sprite.position = pos + Vector3(0.0, 0.88, 0.0)
	add_child(sprite)
	if flee_away != Vector3.ZERO:
		_fleeing.append({"sprite": sprite, "home": sprite.position, "away": sprite.position + flee_away, "t": 0.0})
	return sprite


func _box(size: Vector3, pos: Vector3, color: Color, yaw: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = pos
	instance.rotation.y = yaw
	add_child(instance)
	return instance


## Собрать лагерь. Вызывать один раз после добавления в дерево этапа.
## local +Z смотрит на дорогу (узел разворачивает RallyStage).
func setup(stage: Node, rng_seed: int, people: int, with_camp: bool) -> void:
	_stage = stage
	_rng.seed = rng_seed
	# Толпа — полукругом в 2 ряда, а не шеренгой.
	for i in range(people):
		var row: int = i % 2
		var x: float = -4.5 + float(i / 2) * 1.6 + _rng.randf_range(-0.3, 0.3)
		var z: float = 1.2 + float(row) * 1.1 + _rng.randf_range(-0.2, 0.2)
		_make_person(_rng.randi_range(0, JACKETS.size() - 1), Vector3(x, 0.0, z), Vector3.ZERO)
	# Два фотографа у самой кромки: эти отскакивают.
	_make_person(1, Vector3(-2.2, 0.0, -2.6), Vector3(0.0, 0.0, 2.4))
	_make_person(3, Vector3(2.6, 0.0, -2.4), Vector3(0.5, 0.0, 2.4))
	# Вспышки прячем над толпой до проезда машины.
	for i in range(3):
		var flash := Sprite3D.new()
		flash.texture = _make_flash_texture()
		flash.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		flash.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		flash.shaded = false
		flash.pixel_size = 0.03
		flash.position = Vector3(-3.5 + float(i) * 3.0, 1.7, 0.8)
		flash.modulate = Color(1, 1, 1, 0)
		add_child(flash)
		_flashes.append(flash)
		_flash_timers.append(_rng.randf_range(0.2, 1.6))
	if with_camp:
		_build_camp()
	set_process(true)


func _build_camp() -> void:
	# Кемпер: белый фургон с полосой и тёмными окнами.
	_box(Vector3(4.6, 1.9, 1.9), Vector3(-8.5, 0.95, 5.5), Color(0.88, 0.87, 0.82), 0.25)
	_box(Vector3(4.7, 0.35, 1.92), Vector3(-8.5, 1.25, 5.5), Color(0.75, 0.15, 0.12), 0.25)
	_box(Vector3(4.2, 0.5, 1.92), Vector3(-8.5, 1.62, 5.5), Color(0.15, 0.18, 0.22), 0.25)
	for wheel_x in [-1.6, 1.6]:
		var wheel := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.36
		cylinder.bottom_radius = 0.36
		cylinder.height = 0.25
		cylinder.radial_segments = 8
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.05, 0.05, 0.05)
		cylinder.surface_set_material(0, dark)
		wheel.mesh = cylinder
		wheel.rotation.x = PI * 0.5
		wheel.position = Vector3(-8.5 + wheel_x, 0.36, 6.45)
		add_child(wheel)
	# Палатка: две наклонные «стенки»-коробки.
	var tent_left: MeshInstance3D = _box(Vector3(2.2, 0.08, 1.9), Vector3(6.8, 0.65, 5.2), Color(0.15, 0.35, 0.65))
	tent_left.rotation.z = 0.75
	var tent_right: MeshInstance3D = _box(Vector3(2.2, 0.08, 1.9), Vector3(8.35, 0.65, 5.2), Color(0.12, 0.29, 0.55))
	tent_right.rotation.z = -0.75
	# Костёр: кольцо брёвен, тёплый свет, частицы огня и дыма.
	for i in range(5):
		var angle: float = TAU * float(i) / 5.0
		var log_instance := MeshInstance3D.new()
		var log_mesh := CylinderMesh.new()
		log_mesh.top_radius = 0.09
		log_mesh.bottom_radius = 0.09
		log_mesh.height = 0.9
		log_mesh.radial_segments = 6
		var bark := StandardMaterial3D.new()
		bark.albedo_color = Color(0.30, 0.20, 0.11)
		log_mesh.surface_set_material(0, bark)
		log_instance.mesh = log_mesh
		log_instance.rotation.z = PI * 0.5
		log_instance.rotation.y = angle
		log_instance.position = Vector3(cos(angle) * 0.35, 0.10, 4.2 + sin(angle) * 0.35)
		add_child(log_instance)
	_fire_light = OmniLight3D.new()
	_fire_light.position = Vector3(0.0, 0.7, 4.2)
	_fire_light.light_color = Color(1.0, 0.55, 0.22)
	_fire_light.light_energy = 1.6
	_fire_light.omni_range = 9.0
	_fire_light.shadow_enabled = false
	add_child(_fire_light)
	var fire := GPUParticles3D.new()
	fire.amount = 20
	fire.lifetime = 0.7
	fire.position = Vector3(0.0, 0.25, 4.2)
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0, 1, 0)
	process.spread = 18.0
	process.initial_velocity_min = 0.7
	process.initial_velocity_max = 1.3
	process.gravity = Vector3(0, 0.6, 0)
	process.scale_min = 0.25
	process.scale_max = 0.55
	fire.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.7)
	var fire_material := StandardMaterial3D.new()
	var fire_texture: Texture2D = load("res://textures/fire.png") as Texture2D
	if fire_texture != null:
		fire_material.albedo_texture = fire_texture
	fire_material.albedo_color = Color(1.0, 0.62, 0.25, 0.85)
	fire_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fire_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.surface_set_material(0, fire_material)
	fire.draw_pass_1 = quad
	add_child(fire)


func _process(delta: float) -> void:
	_time += delta
	if _fire_light != null:
		_fire_light.light_energy = 1.5 + sin(_time * 11.0) * 0.18 + sin(_time * 23.7) * 0.12
	var car: Node3D = null
	if _stage != null and is_instance_valid(_stage):
		var candidate = _stage.get("car")
		if candidate is Node3D:
			car = candidate as Node3D
	if car == null:
		return
	var car_local: Vector3 = to_local(car.global_position)
	var distance: float = Vector2(car_local.x, car_local.z).length()
	# Вспышки: случайные короткие блики, только когда машина рядом.
	for i in range(_flashes.size()):
		_flash_timers[i] -= delta
		var flash: Sprite3D = _flashes[i]
		if _flash_timers[i] <= 0.0:
			_flash_timers[i] = _rng.randf_range(0.25, 1.8)
			flash.modulate.a = 0.95 if distance < 130.0 else 0.0
		else:
			flash.modulate.a = maxf(0.0, flash.modulate.a - delta * 9.0)
	# Фотографы отскакивают от кромки при приближении машины.
	for entry in _fleeing:
		var sprite: Sprite3D = entry["sprite"]
		var target: float = 1.0 if distance < 22.0 else 0.0
		var t: float = clampf(float(entry["t"]) + delta * (6.0 if target > 0.5 else 2.0) * (1.0 if target > 0.5 else -1.0), 0.0, 1.0)
		entry["t"] = t
		var home: Vector3 = entry["home"]
		var away: Vector3 = entry["away"]
		sprite.position = home.lerp(away, t)
