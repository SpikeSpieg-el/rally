## Пятна на полотне: лужи, грязь, рыхлый гравий, снежный накат, лёд и трещины.
##
## Это настоящие Decal-узлы. Текстура пятна не готовая картинка и не «шум на
## весь квадрат»: маска печётся здесь же — несколько капель с радиальным
## затуханием, край рвётся шумом, альфа уходит в ноль к краю. Поэтому пятно
## читается как лужа или размазанная грязь, а не как прямоугольник. Дополнительно
## делаются карта нормалей (рельеф) и карта ORM (шероховатость), так что лужа
## блестит, а рыхлый гравий шершавый.
##
## Что выпадает на каждом покрытии, какого цвета и размера — это ресурсы
## RallyRoadDecalProfile (data/stage/road_decals/*.tres), правятся в инспекторе.
## Этот скрипт только раскладывает их по трассе.
##
## Раскладка детерминированная: позиции берутся из хеша расстояния по трассе,
## поэтому пятна стоят на одних и тех же местах при каждом заезде и не
## пересобираются, когда машина проезжает мимо.
##
## Скользкие полосы из физики (RallyStage.live_surface_grip) отмечаются теми же
## декалями: лужа на мокрой полосе и рыхлая грязь на сухой, ровно там, где
## сцепление ниже. Геометрию полос считает этап и передаёт в build().
class_name RoadDecals
extends Node3D

const SpecType = preload("res://scripts/data/rally_road_decal_spec.gd")
const ProfileType = preload("res://scripts/data/rally_road_decal_profile.gd")
const TrackConfigType = preload("res://scripts/data/rally_track_config.gd")

## Высота коробки проекции: пятно достаёт до полотна даже на кочках.
const DECAL_HEIGHT := 1.6
## Насколько шум сдвигает точку выборки маски (рваный контур пятна).
const WARP_STRENGTH := 0.12

@export_group("Профили")
## Наборы пятен по видам полотна (data/stage/road_decals/*.tres). Пусто —
## читаются эти же файлы, а если их нет — простой заводской набор.
@export var profiles: Array[Resource] = []

@export_group("Раскладка")
## Предел числа пятен на трассу: генерация обрывается на нём.
@export_range(0, 2000, 4) var max_decals: int = 200
## Множитель к плотности из профиля вида полотна.
@export_range(0.0, 4.0, 0.05) var density_scale: float = 1.0
## Отмечать скользкие полосы физики лужами и рыхлой грязью.
@export var mark_grip_zones: bool = true

@export_group("Вид")
## Во сколько раз пятна крупнее/мельче задуманного профилем.
@export_range(0.2, 3.0, 0.05) var size_scale: float = 1.0
## Общая непрозрачность пятен (1 — как в профиле).
@export_range(0.0, 1.0, 0.01) var opacity: float = 1.0
## Размер текстуры пятна: больше — чётче, дороже по памяти.
@export_range(32, 512, 16) var texture_size: int = 160
## Карты нормалей (рельеф пятна). Выключить, если нужен максимум FPS.
@export var use_normal_maps: bool = true
## Карта ORM: глянец луж и льда. Выключить, если нужен максимум FPS.
@export var use_orm: bool = true
## Дальность, с которой пятна начинают гаснуть, м (0 — не гасить).
@export_range(0.0, 400.0, 5.0) var fade_begin: float = 90.0
@export_range(0.0, 200.0, 5.0) var fade_length: float = 40.0

## Сколько пятен реально создано (для отладки и тестов).
var built_count: int = 0

var _network = null
var _track = null
var _surface_state = null
var _snow_cover: float = 0.0
var _zones: Array = []
var _profiles_by_kind: Dictionary = {}
var _textures: Dictionary = {}


## Разложить пятна по трассе. zones — геометрия скользких полос от этапа:
## {distance, length, half_width, offset, strong}.
func build(network, track, surface_state, snow_cover: float, zones: Array) -> int:
	_network = network
	_track = track
	_surface_state = surface_state
	_snow_cover = clampf(snow_cover, 0.0, 1.0)
	_zones = zones.duplicate()
	rebuild()
	return built_count


## Пересобрать пятна после смены погоды (снег поверх летнего покрытия).
## Полосы физики за заезд не меняются, поэтому берутся те, что пришли в build().
func set_snow_cover(value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	if absf(clamped - _snow_cover) < 0.2:
		return
	_snow_cover = clamped
	rebuild()


func rebuild() -> void:
	_clear_decals()
	built_count = 0
	if _network == null or _track == null:
		return
	var total: float = _network.total_length
	if total < 8.0:
		return
	_ensure_profiles()
	if _profiles_by_kind.is_empty():
		return
	# Скользкие полосы идут первыми: они связаны с физикой, и им нужен бюджет
	# даже на длинной трассе. Остальное добирается пятнами по виду покрытия.
	if mark_grip_zones:
		_place_slippery_zones()
	var count := _target_count(total)
	if count <= 0:
		return
	var step: float = total / float(count)
	for index in range(count):
		if built_count >= max_decals:
			break
		var along: float = (float(index) + 0.5) * step
		along += (TrackConfigType.hash_noise(along, 11.0) - 0.5) * step * 0.85
		along = clampf(along, 2.0, total - 2.0)
		_place_from_profile(along)


func _clear_decals() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


func _ensure_profiles() -> void:
	if not _profiles_by_kind.is_empty():
		return
	for profile in profiles:
		_register_profile(profile)
	if _profiles_by_kind.is_empty():
		for profile in _file_profiles():
			_register_profile(profile)
	# Недостающие виды покрытия добираем встроенными: пусть лучше пятна
	# будут заводские, чем на снегу вообще ничего.
	for profile in ProfileType.defaults():
		if profile == null:
			continue
		var key := String(profile.kind_name())
		if not _profiles_by_kind.has(key):
			_profiles_by_kind[key] = profile


func _register_profile(profile) -> void:
	if not (profile is RallyRoadDecalProfile):
		return
	var typed := profile as RallyRoadDecalProfile
	_profiles_by_kind[String(typed.kind_name())] = typed


func _file_profiles() -> Array:
	return ProfileType.load_files()


## Сколько пятен вообще нужно: средняя плотность профилей на метраж трассы.
func _target_count(total: float) -> int:
	var average := 0.0
	var kinds := 0
	for key in _profiles_by_kind:
		var profile = _profiles_by_kind[key]
		average += float(profile.density)
		kinds += 1
	if kinds > 0:
		average /= float(kinds)
	var estimate := int(round(total * average * density_scale / 100.0))
	return clampi(estimate, 0, maxi(0, max_decals))


func _road_kind_at(along: float) -> String:
	var surface_name := ""
	if _track != null:
		surface_name = String(_track.surface_name)
		var section = _track.section_at(along)
		if section != null:
			surface_name = String(section.surface_name)
	if _surface_state != null and _surface_state.has_method("surface_kind"):
		return String(_surface_state.surface_kind(surface_name, false, _snow_cover))
	return "gravel"


func _profile_at(along: float):
	var key := _road_kind_at(along)
	if _profiles_by_kind.has(key):
		return _profiles_by_kind[key]
	if _profiles_by_kind.has("gravel"):
		return _profiles_by_kind["gravel"]
	return null


func _across(along: float) -> Vector3:
	var dir: Vector3 = _network.direction_at(along)
	return Vector3(dir.z, 0.0, -dir.x).normalized()


func _place_from_profile(along: float) -> void:
	var profile = _profile_at(along)
	if profile == null:
		return
	var spec = _pick_spec(profile, TrackConfigType.hash_noise(along, 23.0))
	if spec == null:
		return
	var half: float = maxf(1.0, float(_track.half_width_at(along)))
	var side: float = -1.0 if TrackConfigType.hash_noise(along, 31.0) < 0.5 else 1.0
	var spread: float = clampf(float(profile.spread), 0.05, 1.0)
	var reach: float = spread * (0.18 + 0.82 * TrackConfigType.hash_noise(along, 37.0))
	var spot: Vector3 = _network.point_at(along) + _across(along) * side * reach * half
	var footprint := Vector2(
		lerpf(spec.size_min.x, spec.size_max.x, TrackConfigType.hash_noise(along, 41.0)),
		lerpf(spec.size_min.y, spec.size_max.y, TrackConfigType.hash_noise(along, 43.0))
	)
	var yaw_angle: float = TrackConfigType.hash_noise(along, 47.0) * TAU
	_place_decal(spec, spot, yaw_angle, footprint)


## Взвешенный выбор пятна: чем больше weight, тем чаще оно выпадает.
func _pick_spec(profile, roll: float):
	var total: float = float(profile.total_weight())
	if total <= 0.0:
		return null
	var target: float = clampf(roll, 0.0, 1.0) * total
	var last = null
	for spec in profile.decals:
		if spec == null:
			continue
		last = spec
		target -= maxf(0.0, float(spec.weight))
		if target <= 0.0:
			return spec
	return last


## Скользкие полосы физики: мокрая — лужами, сухая — рыхлой грязью или снегом.
## Полоса режется на несколько пятен, иначе один декаль растягивался на 20 м и
## шум превращался в полоски.
func _place_slippery_zones() -> void:
	for span in _zones:
		if built_count >= max_decals:
			return
		if not (span is Dictionary):
			continue
		var center_distance: float = float(span.get("distance", -1.0))
		if center_distance < 2.0:
			continue
		var profile = _profile_at(center_distance)
		if profile == null:
			continue
		var spec = _zone_spec(profile, bool(span.get("strong", true)))
		if spec == null:
			continue
		var offset: float = float(span.get("offset", 0.0))
		var length: float = maxf(1.0, float(span.get("length", 8.0)))
		var half_width: float = maxf(0.5, float(span.get("half_width", 1.5)))
		var pieces: int = clampi(int(round(length / 5.0)), 1, 6)
		var piece_length: float = length / float(pieces)
		var start: float = center_distance - length * 0.5
		for piece in range(pieces):
			if built_count >= max_decals:
				return
			var distance: float = start + (float(piece) + 0.5) * piece_length
			var jitter: float = (TrackConfigType.hash_noise(distance, 59.0) - 0.5) * half_width * 0.5
			var spot: Vector3 = _network.point_at(distance) + _across(distance) * (offset + jitter)
			# Коробка заметно больше самого пятна: соседние куски перекрываются
			# и полоса читается как одна мокрая лента, а не как набор пятен.
			var footprint := Vector2(half_width * 2.2, piece_length * 1.7)
			var dir: Vector3 = _network.direction_at(distance)
			_place_decal(spec, spot, atan2(dir.x, dir.z), footprint)


func _zone_spec(profile, strong: bool):
	var wanted: Array = (
		[SpecType.Kind.PUDDLE, SpecType.Kind.ICE, SpecType.Kind.WET]
		if strong
		else [SpecType.Kind.LOOSE, SpecType.Kind.MUD, SpecType.Kind.WET]
	)
	for wanted_kind in wanted:
		for spec in profile.decals:
			if spec != null and int(spec.kind) == int(wanted_kind):
				return spec
	return null


func _place_decal(spec, spot: Vector3, yaw_angle: float, footprint: Vector2) -> void:
	var decal := Decal.new()
	decal.name = "Decal%d" % built_count
	var textures := _textures_for(spec)
	decal.texture_albedo = textures.get("albedo")
	var normal_map = textures.get("normal")
	if normal_map != null:
		decal.texture_normal = normal_map
	var orm_map = textures.get("orm")
	if orm_map != null:
		decal.texture_orm = orm_map
	decal.albedo_mix = clampf(float(spec.albedo_mix) * opacity, 0.0, 1.0)
	decal.modulate = Color(1.0, 1.0, 1.0, clampf(float(spec.opacity) * opacity, 0.01, 1.0))
	decal.size = Vector3(
		maxf(0.2, footprint.x * size_scale), DECAL_HEIGHT, maxf(0.2, footprint.y * size_scale)
	)
	# Полотно должно проходить через середину коробки проекции: у самого
	# нижнего края декаль гаснет (lower_fade) и была бы невидимой.
	decal.position = spot + Vector3(0.0, 0.1, 0.0)
	decal.rotation = Vector3(0.0, yaw_angle, 0.0)
	decal.upper_fade = 0.2
	decal.lower_fade = 0.2
	decal.normal_fade = 0.0
	# Только слой мира и полотна: кузов и реквизит пятна не получают.
	decal.cull_mask = 1
	if fade_begin > 0.0:
		decal.distance_fade_enabled = true
		decal.distance_fade_begin = fade_begin
		decal.distance_fade_length = maxf(1.0, fade_length)
	add_child(decal)
	built_count += 1


## Текстуры одного пятна собираются один раз и живут до конца заезда.
func _textures_for(spec) -> Dictionary:
	var key: int = spec.get_instance_id()
	if _textures.has(key):
		return _textures[key]
	var albedo := _bake_albedo(spec)
	var normal_map = null
	if use_normal_maps and float(spec.normal_strength) > 0.0:
		normal_map = _make_normal_texture(spec)
	var orm_map = null
	if use_orm:
		orm_map = _make_orm_texture(spec)
	var textures := {"albedo": albedo, "normal": normal_map, "orm": orm_map}
	_textures[key] = textures
	return textures


## Маска пятна — самое важное. Альбедо печётся по пикселям: несколько «капель»
## с радиальным затуханием, радиус «дышит» от шума, внутри маску проедает
## фрактальный шум. Альфа на краю текстуры ровно ноль, поэтому декаль не видна
## прямоугольником — только самим пятном.
func _bake_albedo(spec) -> ImageTexture:
	var size: int = clampi(texture_size, 32, 512)
	# Шум частотой «на 128 пикселей» — чтобы рисунок не зависел от размера текстуры.
	var pixel_scale: float = float(size) / 128.0
	var noise := _make_noise(spec, 1.0, 0)
	var warp := _make_noise(spec, 0.5, 331)
	var blobs := _blob_centers(spec)
	var stretch: Vector2 = spec.blob_stretch
	var stretch_x: float = maxf(0.15, float(stretch.x))
	var stretch_y: float = maxf(0.15, float(stretch.y))
	var feather: float = clampf(float(spec.edge_feather), 0.05, 0.95)
	var threshold: float = clampf(float(spec.mask_threshold), 0.0, 0.85)
	var gain: float = clampf(float(spec.mask_gain), 0.2, 4.0)
	var edge: Color = spec.edge_color
	var core: Color = spec.core_color
	var data := PackedByteArray()
	data.resize(size * size * 4)
	var index := 0
	for y in range(size):
		for x in range(size):
			var u := (float(x) + 0.5) / float(size)
			var v := (float(y) + 0.5) / float(size)
			# Доменный варп: точку выборки сдвигает шум, поэтому контур капли
			# получается рваным и с заливами, а не ровным овалом.
			var warp_x := (
				float(warp.get_noise_2d(float(x) * pixel_scale * 0.5, float(y) * pixel_scale * 0.5))
			)
			var warp_y := (
				float(
					warp.get_noise_2d(
						float(x) * pixel_scale * 0.5 + 137.0,
						float(y) * pixel_scale * 0.5 - 91.0
					)
				)
			)
			var sample_u := u + warp_x * WARP_STRENGTH
			var sample_v := v + warp_y * WARP_STRENGTH
			var mask := 0.0
			for blob in blobs:
				var du: float = (sample_u - float(blob.x)) / stretch_x
				var dv: float = (sample_v - float(blob.y)) / stretch_y
				var radius: float = float(blob.z)
				var fall := 1.0 - smoothstep(radius * (1.0 - feather), radius, sqrt(du * du + dv * dv))
				if fall > mask:
					mask = fall
			var value := 0.0
			if mask > 0.0:
				var grain := (
					float(noise.get_noise_2d(float(x) * pixel_scale, float(y) * pixel_scale)) * 0.5
					+ 0.5
				)
				# Шум сильнее всего рвёт край (там пятно тает), в ядре остаётся
				# лёгкая мраморность: иначе пятно выглядит залитым аэрографом.
				var erosion := smoothstep(threshold, 1.0, grain)
				var rim := clampf(1.0 - mask, 0.0, 1.0)
				value = mask * lerpf(1.0, erosion, 0.35 + 0.65 * rim)
				value *= 0.72 + 0.28 * grain
			value = pow(clampf(value, 0.0, 1.0), gain)
			var color: Color = edge
			if value > 0.0:
				color = edge.lerp(core, sqrt(value))
				color.a = lerpf(edge.a, core.a, value)
			data[index] = int(clampf(color.r, 0.0, 1.0) * 255.0)
			data[index + 1] = int(clampf(color.g, 0.0, 1.0) * 255.0)
			data[index + 2] = int(clampf(color.b, 0.0, 1.0) * 255.0)
			data[index + 3] = int(clampf(color.a, 0.0, 1.0) * 255.0)
			index += 4
	var image := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## Центры «капель» в координатах текстуры (0..1), радиус — в долях её ширины.
## Детерминированно от noise_seed: одно и то же пятно каждый заезд одинаково.
func _blob_centers(spec) -> Array:
	var count: int = clampi(int(spec.blob_count), 1, 6)
	var seed_value: int = int(spec.noise_seed) + 41
	var stretch: Vector2 = spec.blob_stretch
	var stretch_x: float = maxf(0.15, float(stretch.x))
	var stretch_y: float = maxf(0.15, float(stretch.y))
	var result: Array = []
	if count <= 1:
		result.append(Vector3(0.5, 0.5, 0.46))
		return result
	var base_radius: float = 0.44 / sqrt(float(count))
	for i in range(count):
		var h1 := TrackConfigType.hash_noise(float(i) * 3.7 + 1.0, float(seed_value))
		var h2 := TrackConfigType.hash_noise(float(i) * 7.3 + 2.0, float(seed_value))
		var h3 := TrackConfigType.hash_noise(float(i) * 5.1 + 3.0, float(seed_value))
		var radius: float = clampf(base_radius * (0.7 + 0.6 * h3), 0.06, 0.45)
		# Центр выбираем внутри того места, где капля ещё целиком влезает в
		# текстуру: край маски всегда гаснет до края декали, а не обрезается им.
		var span_x: float = maxf(0.0, 0.5 - radius * 1.02 * stretch_x - WARP_STRENGTH)
		var span_y: float = maxf(0.0, 0.5 - radius * 1.02 * stretch_y - WARP_STRENGTH)
		result.append(
			Vector3(
				0.5 + (h1 * 2.0 - 1.0) * span_x,
				0.5 + (h2 * 2.0 - 1.0) * span_y,
				radius
			)
		)
	return result


func _make_noise(spec, frequency_scale: float, seed_offset: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = int(spec.noise_seed) + seed_offset
	noise.noise_type = _noise_type(int(spec.noise_type))
	noise.frequency = maxf(0.001, float(spec.noise_frequency) * frequency_scale)
	noise.fractal_octaves = clampi(int(spec.noise_octaves), 1, 6)
	noise.fractal_lacunarity = float(spec.noise_lacunarity)
	noise.fractal_gain = float(spec.noise_gain)
	return noise


## Рельеф пятна. Влияние карты нормалей декаль домножает на альфу альбедо,
## поэтому она сама ограничена формой пятна.
func _make_normal_texture(spec) -> NoiseTexture2D:
	var noise := _make_noise(spec, maxf(0.1, float(spec.normal_scale)), 17)
	var texture := NoiseTexture2D.new()
	texture.noise = noise
	texture.width = texture_size
	texture.height = texture_size
	texture.generate_mipmaps = true
	texture.as_normal_map = true
	texture.bump_strength = float(spec.normal_strength)
	return texture


## ORM: R — затенение (не затемняем), G — шероховатость, B — металл.
func _make_orm_texture(spec) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = int(spec.noise_seed) + 977
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.055
	noise.fractal_octaves = 2
	var rough: float = clampf(float(spec.roughness), 0.0, 1.0)
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 1.0])
	ramp.colors = PackedColorArray([
		Color(1.0, clampf(rough * 0.6, 0.0, 1.0), float(spec.metallic), 1.0),
		Color(1.0, rough, float(spec.metallic), 1.0),
	])
	var texture := NoiseTexture2D.new()
	texture.noise = noise
	texture.width = maxi(16, texture_size / 2)
	texture.height = maxi(16, texture_size / 2)
	texture.generate_mipmaps = true
	texture.color_ramp = ramp
	return texture


func _noise_type(value: int) -> int:
	match clampi(value, 0, 4):
		0:
			return FastNoiseLite.TYPE_VALUE
		1:
			return FastNoiseLite.TYPE_PERLIN
		3:
			return FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		4:
			return FastNoiseLite.TYPE_CELLULAR
		_:
			return FastNoiseLite.TYPE_SIMPLEX
