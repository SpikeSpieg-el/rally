## «Островок жизни» на повороте: зрители, лагерь болельщиков, костёр и
## фотовспышки. Вся геометрия — в сцене scenes/props/spectator_crowd.tscn
## (люди, фотографы, кемпер, палатка, костёр расставлены прямо в ней и
## правятся в редакторе); этот скрипт только ОЖИВЛЯЕТ сцену:
##   * раздаёт спрайтам случайные куртки (текстуры textures/sprites/);
##   * прячет лишних зрителей под заданный размер толпы;
##   * включает/выключает лагерь и заставляет свет костра дрожать;
##   * зажигает вспышки, когда машина в радиусе 130 м;
##   * отодвигает двух фотографов от кромки при приближении машины.
##
## Локальная -Z сцены смотрит на дорогу (узел разворачивает RallyStage),
## фотографы стоят у отрицательного Z и отскакивают в +Z.
class_name RallySpectatorCrowd
extends Node3D

@export_group("Фотографы и вспышки")
## С какого расстояния фотографы чуть отступают, м.
@export_range(4.0, 40.0, 0.5, "suffix:м") var photographer_dodge_distance: float = 12.0
## Куда отступают в локали сцены (локальный +Z — от дороги).
@export var photographer_dodge_offset: Vector3 = Vector3(0.2, 0.0, 0.7)
@export_range(20.0, 250.0, 1.0, "suffix:м") var flash_distance: float = 130.0

const PERSON_TEXTURES: Array[String] = [
	"res://textures/sprites/spectator_red.png",
	"res://textures/sprites/spectator_yellow.png",
	"res://textures/sprites/spectator_blue.png",
	"res://textures/sprites/spectator_green.png",
	"res://textures/sprites/spectator_orange.png",
	"res://textures/sprites/spectator_white.png",
]

var _stage: Node = null
var _persons: Array[Node3D] = []
var _photographers: Array = []  # [{root, home: Vector3, away: Vector3, t: float}]
var _flashes: Array[Sprite3D] = []
var _flash_timers: PackedFloat32Array = PackedFloat32Array()
var _fire_light: OmniLight3D = null
var _rng := RandomNumberGenerator.new()
var _time: float = 0.0


func _collect() -> void:
	_persons.clear()
	_photographers.clear()
	_flashes.clear()
	_flash_timers.clear()
	var Crowd := get_node_or_null("Crowd")
	if Crowd != null:
		for child in Crowd.get_children():
			if child is Node3D:
				_persons.append(child as Node3D)
	var photographers := get_node_or_null("Photographers")
	if photographers != null:
		for child in photographers.get_children():
			if child is Node3D:
				var root := child as Node3D
				_photographers.append({
					"root": root,
					"home": root.position,
					"away": root.position + photographer_dodge_offset,
					"t": 0.0,
				})
	var flashes := get_node_or_null("Flashes")
	if flashes != null:
		for child in flashes.get_children():
			var sprite := child.get_node_or_null("Sprite") as Sprite3D
			if sprite != null:
				_flashes.append(sprite)
				_flash_timers.append(_rng.randf_range(0.2, 1.6))


func _sprite_of(person_root: Node3D) -> Sprite3D:
	return person_root.get_node_or_null("Sprite") as Sprite3D


func _randomize_jackets() -> void:
	var textures: Array[Texture2D] = []
	for path in PERSON_TEXTURES:
		var texture := load(path) as Texture2D
		if texture != null:
			textures.append(texture)
	if textures.is_empty():
		return
	for person in _persons:
		var sprite := _sprite_of(person)
		if sprite != null:
			sprite.texture = textures[_rng.randi_range(0, textures.size() - 1)]
	for entry in _photographers:
		var sprite := _sprite_of(entry["root"] as Node3D)
		if sprite != null:
			sprite.texture = textures[_rng.randi_range(0, textures.size() - 1)]
	for sprite in _flashes:
		sprite.modulate.a = 0.0


## Собрать лагерь. Вызывать один раз после добавления в дерево этапа.
## people — сколько зрителей показать из расставленных в сцене,
## with_camp — показывать ли кемпер, палатку и костёр.
func setup(stage: Node, rng_seed: int, people: int, with_camp: bool) -> void:
	_stage = stage
	_rng.seed = rng_seed
	_collect()
	_randomize_jackets()
	_arm_people()
	for i in range(_persons.size()):
		_persons[i].visible = i < people
	var camp := get_node_or_null("Camp")
	if camp != null:
		camp.visible = with_camp
		if with_camp:
			_fire_light = camp.get_node_or_null("Campfire/FireLight") as OmniLight3D
	set_process(true)


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
			flash.modulate.a = 0.95 if distance < flash_distance else 0.0
		else:
			flash.modulate.a = maxf(0.0, flash.modulate.a - delta * 9.0)
	# Фотографы едва отступают: слишком любят ралли, чтобы уходить далеко.
	for entry in _photographers:
		var root := entry["root"] as Node3D
		if root.has_method("is_crushed") and bool(root.call("is_crushed")):
			continue
		var target: float = 1.0 if distance < photographer_dodge_distance else 0.0
		var step: float = delta * (4.0 if target > 0.5 else -1.6)
		var t: float = clampf(float(entry["t"]) + step, 0.0, 1.0)
		entry["t"] = t
		var home: Vector3 = entry["home"]
		var away: Vector3 = entry["away"]
		root.position = home.lerp(away, t)


func _arm_people() -> void:
	for person in _persons:
		if person.has_method("setup"):
			person.call("setup", _stage, false, Vector3.ZERO)
	for entry in _photographers:
		var root := entry["root"] as Node3D
		if root.has_method("setup"):
			root.call("setup", _stage, false, Vector3.ZERO)
