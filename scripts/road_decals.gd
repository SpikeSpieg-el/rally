## Пятна на полотне: лужи, грязь, рыхлый гравий, снежный накат, лёд и трещины.
##
## Это настоящие Decal-узлы: у каждого своя текстура, собранная из шума
## (NoiseTexture2D + FastNoiseLite + Gradient), своя карта нормалей и карта ORM
## (шероховатость/металл), поэтому лужа блестит, рыхлый гравий шершавый, а
## слякоть матовая. Набор пятен на каждый вид полотна задаёт
## RallyRoadDecalProfile — гравий, грязь, асфальт и снег выглядят по-разному.
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

@export_group("Профили")
## Свои наборы пятен по видам полотна. Пусто — встроенные (ProfileType.defaults()).
@export var profiles: Array[RallyRoadDecalProfile] = []

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
	var list: Array = profiles.duplicate()
	if list.is_empty():
		list = ProfileType.defaults()
	for profile in list:
		if profile == null:
			continue
		_profiles_by_kind[String(profile.kind_name())] = profile


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
			var footprint := Vector2(half_width * 2.1, piece_length * 1.35)
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
	var albedo := _make_noise_texture(spec, 1.0, false)
	var normal_map = null
	if use_normal_maps and float(spec.normal_strength) > 0.0:
		normal_map = _make_noise_texture(spec, maxf(0.1, float(spec.normal_scale)), true)
	var orm_map = null
	if use_orm:
		orm_map = _make_orm_texture(spec)
	var textures := {"albedo": albedo, "normal": normal_map, "orm": orm_map}
	_textures[key] = textures
	return textures


func _make_noise_texture(spec, frequency_scale: float, as_normal: bool) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = int(spec.noise_seed) + 17
	noise.noise_type = _noise_type(int(spec.noise_type))
	noise.frequency = maxf(0.001, float(spec.noise_frequency) * frequency_scale)
	noise.fractal_octaves = clampi(int(spec.noise_octaves), 1, 6)
	noise.fractal_lacunarity = float(spec.noise_lacunarity)
	noise.fractal_gain = float(spec.noise_gain)
	var texture := NoiseTexture2D.new()
	texture.noise = noise
	texture.width = texture_size
	texture.height = texture_size
	texture.generate_mipmaps = true
	texture.normalize = true
	if as_normal:
		texture.as_normal_map = true
		texture.bump_strength = float(spec.normal_strength)
		return texture
	texture.color_ramp = _ramp(spec)
	return texture


## Форма пятна: от прозрачного края через полупрозрачную середину к плотному ядру.
func _ramp(spec) -> Gradient:
	var edge: Color = spec.edge_color
	var core: Color = spec.core_color
	var middle: Color = edge.lerp(core, 0.6)
	middle.a = lerpf(edge.a, core.a, 0.45)
	var rim: float = clampf(float(spec.rim), 0.02, 0.6)
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, rim, clampf(rim + 0.28, 0.05, 0.95), 1.0])
	ramp.colors = PackedColorArray([edge, middle, core, core])
	return ramp


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
