## Механика пешеходных переходов в деревнях аркадного режима.
##
## На каждой «зебре» в зоне видимости игрока спавнятся 2–3 пешехода
## (`scenes/props/spectator_person.tscn`), переходящие дорогу туда-обратно.
##   * Если игрок сбивает пешехода на скорости >= 4 м/с — вызывается
##     `person.crush(car)` (брызги крови на кузове и стекле, лужа, тело),
##     а этап получает событие `"pedestrian_hit"` (жёсткий штраф по HP и очкам).
##   * Если игрок проезжает переход аккуратно, не задев никого — событие
##     `"crosswalk_courtesy"` (бонус за чистый проезд).
class_name RallyArcadePedestrians
extends Node3D

const RoadType = preload("res://scripts/arcade/arcade_road.gd")
const ChunkType = preload("res://scripts/arcade/arcade_chunk.gd")
const PersonScript = preload("res://scripts/track/spectator_person.gd")
const ArcadeSettingsType = preload("res://scripts/data/rally_arcade_settings.gd")

const PERSON_SCENE_PATH := "res://scenes/props/spectator_person.tscn"
const SPAWN_AHEAD: float = 240.0
const DESPAWN_BEHIND: float = 90.0

class PedWalker:
	extends RefCounted
	var node: Node3D
	var crossing_along: float = 0.0
	var lateral: float = 0.0
	var walk_dir: float = 1.0
	var walk_speed: float = 1.8
	var max_lat: float = 5.0
	var crushed: bool = false


class CrossingZone:
	extends RefCounted
	var along: float = 0.0
	var walkers: Array[PedWalker] = []
	var warned: bool = false
	var resolved: bool = false
	var min_approach_speed: float = INF


var road_seed: int = 0
var network = null
var cfg: ArcadeSettingsType = null
var _stage_ref: Node = null
var _person_scene: PackedScene = null
var _zones: Dictionary = {} # int(round(crossing_along)) -> CrossingZone
var last_events: Array[Dictionary] = []


func setup(p_seed: int, p_network, stage_ref: Node, p_cfg: ArcadeSettingsType = null) -> void:
	road_seed = p_seed
	network = p_network
	_stage_ref = stage_ref
	cfg = p_cfg
	last_events.clear()
	for child in get_children():
		child.queue_free()
	_zones.clear()
	if cfg != null and cfg.pedestrian_scene != null:
		_person_scene = cfg.pedestrian_scene
	elif _person_scene == null and ResourceLoader.exists(PERSON_SCENE_PATH):
		_person_scene = load(PERSON_SCENE_PATH) as PackedScene


func prime(player_along: float) -> void:
	_sync_zones(player_along)


func step(
	delta: float, player_along: float, player_pos: Vector3, player_vel: Vector3, car: Node3D
) -> Array[Dictionary]:
	last_events.clear()
	if network == null or (cfg != null and not cfg.pedestrians_enabled):
		return last_events

	_sync_zones(player_along)

	var player_dir: Vector3 = network.direction_at(maxf(0.0, player_along))
	var player_side := Vector3(player_dir.z, 0.0, -player_dir.x)
	var player_pt: Vector3 = network.point_at(maxf(0.0, player_along))
	var player_lat: float = player_side.dot(player_pos - player_pt)
	var player_speed: float = Vector2(player_vel.x, player_vel.z).length()
	var warn_dist: float = cfg.pedestrian_warning_distance_m if cfg != null else 78.0
	var hit_min_speed: float = cfg.pedestrian_hit_min_speed_mps if cfg != null else 4.0
	var courtesy_max_speed: float = cfg.crosswalk_courtesy_max_speed_mps if cfg != null else 20.0

	for key in _zones.keys():
		var zone: CrossingZone = _zones[key] as CrossingZone
		var dist_to_crossing: float = zone.along - player_along

		# Предупреждение о приближении к зебре.
		if not zone.warned and dist_to_crossing > 22.0 and dist_to_crossing < warn_dist:
			zone.warned = true
			last_events.append({"kind": "crosswalk_ahead", "along": zone.along})

		if absf(dist_to_crossing) < 28.0:
			zone.min_approach_speed = minf(zone.min_approach_speed, player_speed)

		var any_crushed: bool = false
		for walker in zone.walkers:
			if walker.crushed or not is_instance_valid(walker.node):
				any_crushed = true
				continue

			# Пешеход переходит полотно от одной обочины к другой.
			walker.lateral += walker.walk_dir * walker.walk_speed * delta
			if walker.lateral > walker.max_lat:
				walker.lateral = walker.max_lat
				walker.walk_dir = -1.0
			elif walker.lateral < -walker.max_lat:
				walker.lateral = -walker.max_lat
				walker.walk_dir = 1.0

			_place_walker(walker)

			# Проверка наезда машиной игрока.
			if player_speed >= hit_min_speed and absf(walker.crossing_along - player_along) < 2.55:
				if absf(walker.lateral - player_lat) < 1.48:
					walker.crushed = true
					any_crushed = true
					if car != null and walker.node.has_method("crush"):
						walker.node.call("crush", car)
					last_events.append({
						"kind": "pedestrian_hit",
						"along": zone.along,
						"speed": player_speed,
					})

		# Проезд перехода без наезда и с безопасной скоростью в зоне зебры.
		if not zone.resolved and player_along > zone.along + 10.0:
			zone.resolved = true
			if not any_crushed and zone.min_approach_speed < courtesy_max_speed:
				last_events.append({"kind": "crosswalk_courtesy", "along": zone.along})

	return last_events


func _sync_zones(player_along: float) -> void:
	var min_keep: float = player_along - DESPAWN_BEHIND
	var max_keep: float = player_along + SPAWN_AHEAD

	# Удаляем ушедшие назад переходы.
	var remove_keys: Array = []
	for key in _zones.keys():
		var zone: CrossingZone = _zones[key] as CrossingZone
		if zone.along < min_keep or zone.along > max_keep + 60.0:
			for w in zone.walkers:
				if is_instance_valid(w.node):
					w.node.queue_free()
			remove_keys.append(key)
	for rk in remove_keys:
		_zones.erase(rk)

	if _person_scene == null:
		return

	var first_leg: int = maxi(0, RoadType.leg_index_at(maxf(0.0, min_keep)))
	var last_leg: int = RoadType.leg_index_at(max_keep)
	for leg_index in range(first_leg, last_leg + 1):
		var built: RoadType.Leg = RoadType.leg(leg_index, road_seed)
		if built == null:
			continue
		for c_along in built.crossings:
			if c_along < player_along + 15.0 or c_along > max_keep:
				continue
			var key: int = int(round(c_along))
			if _zones.has(key):
				continue
			_spawn_zone(key, c_along)


func _spawn_zone(key: int, crossing_along: float) -> void:
	var zone := CrossingZone.new()
	zone.along = crossing_along
	var half: float = ChunkType.half_width_at(crossing_along, road_seed)
	var c_min: int = maxi(0, cfg.pedestrians_min_per_crossing) if cfg != null else 2
	var c_max: int = maxi(c_min, cfg.pedestrians_max_per_crossing) if cfg != null else 3
	var count: int = c_min if c_max <= c_min else roundi(RoadType.roll_range(key, road_seed, 961, float(c_min), float(c_max)))
	var w_min: float = cfg.pedestrian_walk_speed_min if cfg != null else 1.55
	var w_max: float = maxf(w_min, cfg.pedestrian_walk_speed_max if cfg != null else 2.35)
	var road_dir: Vector3 = network.direction_at(crossing_along)
	var road_side: Vector3 = Vector3(road_dir.z, 0.0, -road_dir.x)

	for i in range(count):
		var inst := _person_scene.instantiate() as Node3D
		if inst == null:
			continue
		inst.name = "CrosswalkPed_%d_%d" % [key, i]
		add_child(inst)

		var offset_along: float = lerpf(-1.1, 1.1, float(i) / float(maxi(1, count - 1)))
		var w := PedWalker.new()
		w.node = inst
		w.crossing_along = crossing_along + offset_along
		w.max_lat = half + 1.8
		w.walk_dir = 1.0 if (i % 2 == 0) else -1.0
		w.lateral = RoadType.roll_range(key + i * 13, road_seed, 962, -half * 0.75, half * 0.75)
		w.walk_speed = RoadType.roll_range(key + i * 19, road_seed, 963, w_min, w_max)

		if inst.has_method("setup"):
			inst.call("setup", _stage_ref, false, road_side * (-w.walk_dir))
		# Движением и хитбоксом управляет RallyArcadePedestrians.
		inst.set_physics_process(false)
		var hb := inst.get_node_or_null("Hitbox") as Area3D
		if hb != null:
			hb.monitoring = false
			hb.monitorable = false

		_place_walker(w)
		zone.walkers.append(w)

	_zones[key] = zone


func _place_walker(walker: PedWalker) -> void:
	var center: Vector3 = network.point_at(walker.crossing_along)
	var dir: Vector3 = network.direction_at(walker.crossing_along)
	var side := Vector3(dir.z, 0.0, -dir.x)
	var pos: Vector3 = center + side * walker.lateral
	pos.y = ChunkType.surface_height(walker.crossing_along, walker.lateral, road_seed)
	walker.node.global_position = pos
	walker.node.rotation.y = atan2(dir.x, dir.z)
