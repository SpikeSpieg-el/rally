## Живой двухсторонний трафик аркадного режима.
##
## Машины держат свою полосу (встречные — левую, попутные — правую),
## заранее притормаживают перед крутыми поворотами, в деревнях и на мостах,
## тормозят перед впереди идущим транспортом И перед машиной игрока (вплоть
## до полной остановки) и смещаются к обочине, уступая дорогу при сближении.
##
## Реализованы на `AnimatableBody3D` (слой 2, как и отбойники/деревья):
## при столкновении передают честный физический импульс машине игрока, не
## проваливаясь под дорогу и не тратя CPU на 4-колёсную подвеску вдали.
class_name RallyArcadeTraffic
extends Node3D

const RoadType = preload("res://scripts/arcade/arcade_road.gd")
const ChunkType = preload("res://scripts/arcade/arcade_chunk.gd")
const LegType = preload("res://scripts/data/rally_arcade_leg.gd")
const ArcadeSettingsType = preload("res://scripts/data/rally_arcade_settings.gd")

const MAX_ACTIVE_CARS: int = 10
const SPAWN_AHEAD_MIN: float = 105.0
const SPAWN_AHEAD_MAX: float = 315.0
const DESPAWN_BEHIND: float = 115.0
const DESPAWN_AHEAD: float = 360.0
const MIN_SEPARATION_SAME_LANE: float = 42.0

## Палитра кузовов и типы кузова: седан, хэтчбек, фургон.
const LIVERY_COLORS := [
	Color(0.76, 0.78, 0.80, 1.0),
	Color(0.16, 0.28, 0.44, 1.0),
	Color(0.62, 0.16, 0.14, 1.0),
	Color(0.18, 0.34, 0.22, 1.0),
	Color(0.78, 0.64, 0.22, 1.0),
	Color(0.32, 0.34, 0.38, 1.0),
	Color(0.84, 0.82, 0.74, 1.0),
	Color(0.22, 0.20, 0.26, 1.0),
]

enum BodyKind { SEDAN, HATCH, VAN }

class TrafficUnit:
	extends RefCounted
	var body: AnimatableBody3D
	var wheels: Array[Node3D] = []
	var headlight_spot: SpotLight3D = null
	var brake_mats: Array[StandardMaterial3D] = []
	var along: float = 0.0
	var lane_dir: float = 1.0
	var base_speed: float = 13.0
	var current_speed: float = 11.0
	var yield_offset: float = 0.0
	var yield_hold: float = 0.0
	var smooth_steer_yaw: float = 0.0
	var wheel_spin: float = 0.0
	var wheel_radius: float = 0.35
	var hit_pause: float = 0.0
	var overtaken: bool = false
	var near_missed: bool = false
	var active: bool = false
	var last_lateral: float = 0.0


var road_seed: int = 0
var network = null
var is_night: bool = false
var overtakes: int = 0
var last_events: Array[Dictionary] = []
var cfg: ArcadeSettingsType = null

var _units: Array[TrafficUnit] = []
var _spawn_counter: int = 0
var _wheel_mat: StandardMaterial3D = null
var _glass_mat: StandardMaterial3D = null
var _bumper_mat: StandardMaterial3D = null
var _headlight_mat: StandardMaterial3D = null


func setup(p_seed: int, p_network, p_is_night: bool, p_cfg: ArcadeSettingsType = null) -> void:
	road_seed = p_seed
	network = p_network
	is_night = p_is_night
	cfg = p_cfg
	overtakes = 0
	last_events.clear()
	for child in get_children():
		child.queue_free()
	_units.clear()
	_spawn_counter = 0
	_ensure_shared_materials()

	var enabled: bool = true if cfg == null else cfg.traffic_enabled
	if not enabled:
		return
	var total: int = MAX_ACTIVE_CARS if cfg == null else maxi(0, cfg.traffic_count)
	for i in range(total):
		var unit := _create_unit(i)
		_units.append(unit)
		add_child(unit.body)


func prime(player_along: float) -> void:
	var spawn_max: float = cfg.traffic_spawn_max_m if cfg != null else SPAWN_AHEAD_MAX
	for i in range(_units.size()):
		var unit := _units[i]
		var lane_dir: float = -1.0 if (i % 2 == 0) else 1.0
		var dist: float = player_along + lerpf(85.0, spawn_max, float(i) / float(maxi(1, _units.size() - 1)))
		_place_unit_at(unit, dist, lane_dir, i)


func step(delta: float, player_along: float, player_pos: Vector3, player_vel: Vector3) -> void:
	last_events.clear()
	if network == null or _units.is_empty():
		return

	var player_dir: Vector3 = network.direction_at(maxf(0.0, player_along))
	var player_side := Vector3(player_dir.z, 0.0, -player_dir.x)
	var player_pt: Vector3 = network.point_at(maxf(0.0, player_along))
	var player_lat: float = player_side.dot(player_pos - player_pt)
	var player_speed: float = Vector2(player_vel.x, player_vel.z).length()
	var player_fwd_speed: float = player_vel.x * player_dir.x + player_vel.z * player_dir.z

	for i in range(_units.size()):
		var unit := _units[i]
		if not unit.active:
			continue

		if unit.hit_pause > 0.0:
			unit.hit_pause = maxf(0.0, unit.hit_pause - delta)

		# 1. Рецикл машин, ушедших далеко назад или вперёд.
		var behind_lim: float = cfg.traffic_despawn_behind_m if cfg != null else DESPAWN_BEHIND
		var ahead_lim: float = cfg.traffic_despawn_ahead_m if cfg != null else DESPAWN_AHEAD
		var rel: float = unit.along - player_along
		if rel < -behind_lim or rel > ahead_lim:
			var new_dir: float = -1.0 if (i % 2 == 0) else 1.0
			var spawn_dist: float = _pick_spawn_distance(player_along, new_dir, i)
			if spawn_dist > 8.0:
				_place_unit_at(unit, spawn_dist, new_dir, i)
			continue

		# Засчитываем чистый обгон попутной машины.
		if unit.lane_dir > 0.0 and not unit.overtaken and unit.along < player_along - 5.0 and player_speed > 8.0:
			unit.overtaken = true
			if unit.hit_pause <= 0.0:
				overtakes += 1
				last_events.append({"kind": "overtake"})

		# Опасный разъезд со встречной машиной на высокой скорости без касания.
		if unit.lane_dir < 0.0 and not unit.near_missed and unit.hit_pause <= 0.0 and player_speed > 20.0:
			if absf(unit.along - player_along) < 4.5 and absf(unit.last_lateral - player_lat) < 4.1:
				unit.near_missed = true
				last_events.append({"kind": "near_miss", "speed": player_speed})

		# 2. Целевая скорость с учётом домена, кривой впереди, трафика и игрока.
		var desired_speed: float = _target_speed_for(unit)
		var lead_info: Vector2 = _nearest_ahead_gap(unit)
		var lead_gap: float = lead_info.x
		var lead_speed: float = lead_info.y
		if lead_gap < 45.0:
			if lead_gap <= 9.5:
				desired_speed = 0.0
			else:
				var follow_t: float = clampf((lead_gap - 9.5) / 28.0, 0.0, 1.0)
				desired_speed = minf(desired_speed, lerpf(0.0, lead_speed + 1.5, follow_t))

		var hazard_speed: float = _player_hazard_speed(unit, player_along, player_lat, player_fwd_speed)
		desired_speed = minf(desired_speed, hazard_speed)

		# Проверка контакта/перекрытия с игроком: сразу тормозим в ноль и не тараним.
		var touching: bool = (
			absf(unit.along - player_along) < 4.7
			and absf(unit.last_lateral - player_lat) < 2.4
		)
		if touching:
			if unit.hit_pause <= 0.0:
				var unit_dir: Vector3 = network.direction_at(maxf(0.0, unit.along)) * unit.lane_dir
				var unit_vel: Vector3 = unit_dir * unit.current_speed
				var rel_spd: float = (player_vel - unit_vel).length()
				last_events.append({"kind": "impact", "rel_speed": rel_spd})
			unit.hit_pause = 2.8
			unit.current_speed = minf(unit.current_speed, 0.4)
		if unit.hit_pause > 0.0:
			desired_speed = 0.0

		var braking: bool = desired_speed < unit.current_speed - 0.8 or desired_speed <= 0.5
		var accel_normal: float = cfg.traffic_accel_rate if cfg != null else 3.2
		var brake_normal: float = cfg.traffic_brake_rate if cfg != null else 11.5
		var brake_emerg: float = cfg.traffic_emergency_brake_rate if cfg != null else 16.5
		var accel_rate: float = brake_emerg if desired_speed < 1.0 else (brake_normal if braking else accel_normal)
		unit.current_speed = move_toward(unit.current_speed, desired_speed, accel_rate * delta)

		# Двигаемся вперёд по полосе (не уходим в отрицательный километраж).
		var next_along: float = unit.along + unit.lane_dir * unit.current_speed * delta
		if next_along < 6.0 and unit.lane_dir < 0.0:
			var respawn_dist: float = _pick_spawn_distance(player_along, -1.0, i)
			_place_unit_at(unit, respawn_dist, -1.0, i)
			continue
		unit.along = next_along

		# 3. Уступчивость: сдвиг к обочине своей полосы при сближении с игроком.
		var half: float = ChunkType.half_width_at(unit.along, road_seed)
		var lane_frac: float = cfg.traffic_lane_fraction if cfg != null else 0.50
		var base_lat: float = unit.lane_dir * half * lane_frac
		var target_yield: float = _compute_yield_offset(unit, player_along, player_lat, player_speed, half)
		if absf(target_yield) > 0.01:
			unit.yield_hold = 0.65
		elif unit.yield_hold > 0.0:
			unit.yield_hold = maxf(0.0, unit.yield_hold - delta)
			target_yield = unit.yield_offset
		var prev_yield: float = unit.yield_offset
		var desired_yield: float = lerpf(unit.yield_offset, target_yield, clampf(delta * 3.2, 0.0, 1.0))
		unit.yield_offset = move_toward(unit.yield_offset, desired_yield, 2.2 * delta)
		var lateral_vel: float = (unit.yield_offset - prev_yield) / maxf(delta, 0.001)
		var max_lat: float = maxf(half - 1.10, 1.5)
		var actual_lat: float = clampf(base_lat + unit.yield_offset, -max_lat, max_lat)
		unit.last_lateral = actual_lat

		# 4. Точная посадка на полотно с уклоном, поворотом и вращением колёс.
		var speed_factor: float = clampf(unit.current_speed / 4.5, 0.0, 1.0)
		var target_steer_yaw: float = clampf(-lateral_vel * unit.lane_dir * 0.11 * speed_factor, -0.16, 0.16)
		unit.smooth_steer_yaw = move_toward(unit.smooth_steer_yaw, target_steer_yaw, 1.1 * delta)
		_apply_transform(unit, actual_lat, unit.smooth_steer_yaw)
		_update_lights_and_wheels(unit, delta, braking, absf(unit.along - player_along))


func _target_speed_for(unit: TrafficUnit) -> float:
	var leg_index: int = RoadType.leg_index_at(unit.along)
	var built: RoadType.Leg = RoadType.leg(leg_index, road_seed)
	var limit_mps: float = unit.base_speed
	if built != null:
		var dom: int = built.domain_at(unit.along)
		if dom == LegType.Kind.VILLAGE:
			limit_mps = minf(limit_mps, cfg.traffic_village_speed_mps if cfg != null else 9.5)
		elif dom == LegType.Kind.BRIDGE:
			limit_mps = minf(limit_mps, cfg.traffic_bridge_speed_mps if cfg != null else 12.5)
		elif dom == LegType.Kind.SERPENTINE:
			limit_mps = minf(limit_mps, cfg.traffic_serpentine_speed_mps if cfg != null else 10.5)
		elif dom == LegType.Kind.FAST:
			var fast_cap: float = cfg.traffic_fast_speed_mps if cfg != null else 17.5
			limit_mps = minf(unit.base_speed * 1.12, fast_cap)

	# Заблаговременное торможение перед поворотами: смотрим на 16, 34 и 55 м вперёд.
	var d0: Vector3 = network.direction_at(maxf(0.0, unit.along))
	var h0: float = atan2(d0.z, d0.x)
	var worst_turn: float = 0.0
	for probe in [16.0, 34.0, 55.0]:
		var probe_d: float = maxf(2.0, unit.along + unit.lane_dir * float(probe))
		var dp: Vector3 = network.direction_at(probe_d)
		var turn: float = absf(wrapf(atan2(dp.z, dp.x) - h0, -PI, PI))
		worst_turn = maxf(worst_turn, turn)
	var hairpin_cap: float = cfg.traffic_hairpin_speed_mps if cfg != null else 6.5
	if worst_turn > 0.48:
		limit_mps = minf(limit_mps, hairpin_cap)
	elif worst_turn > 0.24:
		limit_mps = minf(limit_mps, maxf(hairpin_cap + 2.5, 9.5))
	elif worst_turn > 0.12:
		limit_mps = minf(limit_mps, maxf(hairpin_cap + 5.0, 12.2))
	return limit_mps


## Возвращает Vector2(расстояние до ближайшей машины впереди в той же полосе, её скорость).
func _nearest_ahead_gap(unit: TrafficUnit) -> Vector2:
	var best: float = INF
	var best_speed: float = unit.base_speed
	for other in _units:
		if other == unit or not other.active or other.lane_dir != unit.lane_dir:
			continue
		var diff: float = (other.along - unit.along) * unit.lane_dir
		if diff > 0.0 and diff < best:
			best = diff
			best_speed = other.current_speed
	return Vector2(best, best_speed)


## Ограничение скорости при угрозе столкновения с игроком на полосе движения.
func _player_hazard_speed(
	unit: TrafficUnit, player_along: float, player_lat: float, player_fwd_speed: float
) -> float:
	var ahead_of_unit: float = (player_along - unit.along) * unit.lane_dir
	if ahead_of_unit < -1.5 or ahead_of_unit > 68.0:
		return INF
	var lat_diff: float = absf(player_lat - unit.last_lateral)
	if unit.lane_dir > 0.0:
		# Попутная машина: тормозим за игроком и останавливаемся при сближении.
		if ahead_of_unit < 56.0 and lat_diff < 2.95:
			if ahead_of_unit <= 9.5:
				return 0.0
			var p_spd: float = maxf(0.0, player_fwd_speed)
			var t: float = clampf((ahead_of_unit - 9.5) / 34.0, 0.0, 1.0)
			return p_spd + t * 8.0
	else:
		# Встречная машина: при лобовом курсе резко сбрасываем скорость до остановки.
		if lat_diff < 2.90:
			if ahead_of_unit <= 14.0:
				return 0.0
			return clampf((ahead_of_unit - 14.0) * 0.28, 0.0, 10.0)
		elif lat_diff < 3.70 and ahead_of_unit < 46.0:
			return 8.5
	return INF


func _compute_yield_offset(
	unit: TrafficUnit, player_along: float, player_lat: float, player_speed: float, half: float
) -> float:
	var delta_along: float = unit.along - player_along
	var lane_frac: float = cfg.traffic_lane_fraction if cfg != null else 0.50
	var yield_str: float = cfg.traffic_yield_strength if cfg != null else 0.90
	var room: float = maxf(0.0, (half - 1.15) - half * lane_frac)
	if unit.lane_dir > 0.0:
		# Попутная машина: если игрок быстро нагоняет сзади, сдвигаемся к внешнему краю.
		if delta_along > -5.0 and delta_along < 64.0 and player_speed > unit.current_speed + 1.5:
			return room * yield_str
	else:
		# Встречная: если игрок вылез к встречной полосе или быстро сближается, жмёмся к обочине.
		if delta_along > -5.0 and delta_along < 76.0:
			if player_lat < 1.25 or player_speed > 20.0:
				return -room * yield_str
	return 0.0


func _pick_spawn_distance(player_along: float, lane_dir: float, slot: int) -> float:
	_spawn_counter += 1
	var s_min: float = cfg.traffic_spawn_min_m if cfg != null else SPAWN_AHEAD_MIN
	var s_max: float = cfg.traffic_spawn_max_m if cfg != null else SPAWN_AHEAD_MAX
	var sep: float = cfg.traffic_min_separation_m if cfg != null else MIN_SEPARATION_SAME_LANE
	var base_min: float = s_min if lane_dir < 0.0 else maxf(60.0, s_min * 0.78)
	var span: float = maxf(20.0, s_max - base_min)
	var candidate: float = player_along + base_min + RoadType.roll(_spawn_counter * 17 + slot, road_seed, 951) * span
	# Не сажаем машину поверх другой машины в той же полосе.
	for attempt in range(5):
		var clear: bool = true
		for other in _units:
			if not other.active or other.lane_dir != lane_dir:
				continue
			if absf(other.along - candidate) < sep:
				clear = false
				break
		if clear:
			return candidate
		candidate += sep * 0.9
	return candidate


func _place_unit_at(unit: TrafficUnit, dist: float, lane_dir: float, slot: int) -> void:
	_spawn_counter += 1
	unit.along = maxf(18.0, dist)
	unit.lane_dir = lane_dir
	var min_s: float = cfg.traffic_min_speed_mps if cfg != null else 10.5
	var max_s: float = cfg.traffic_max_speed_mps if cfg != null else 15.5
	unit.base_speed = RoadType.roll_range(_spawn_counter + slot * 7, road_seed, 952, min_s, maxf(min_s, max_s))
	unit.current_speed = minf(unit.base_speed, _target_speed_for(unit))
	unit.yield_offset = 0.0
	unit.yield_hold = 0.0
	unit.smooth_steer_yaw = 0.0
	unit.hit_pause = 0.0
	unit.overtaken = false
	unit.near_missed = false
	unit.active = true
	var half: float = ChunkType.half_width_at(unit.along, road_seed)
	var lane_frac: float = cfg.traffic_lane_fraction if cfg != null else 0.50
	var lat: float = lane_dir * half * lane_frac
	unit.last_lateral = lat
	_apply_transform(unit, lat, 0.0)


func _apply_transform(unit: TrafficUnit, lateral: float, steer_yaw: float) -> void:
	var step_d: float = 2.0
	var a_fwd: float = maxf(0.0, unit.along + unit.lane_dir * step_d)
	var a_back: float = maxf(0.0, unit.along - unit.lane_dir * step_d)
	var p_fwd: Vector3 = network.point_at(a_fwd)
	var p_back: Vector3 = network.point_at(a_back)
	var p_mid: Vector3 = network.point_at(unit.along)
	var dir_mid: Vector3 = network.direction_at(unit.along)
	var side_mid := Vector3(dir_mid.z, 0.0, -dir_mid.x)

	var d_fwd: Vector3 = network.direction_at(a_fwd)
	var d_back: Vector3 = network.direction_at(a_back)
	var w_fwd: Vector3 = p_fwd + Vector3(d_fwd.z, 0.0, -d_fwd.x) * lateral
	var w_back: Vector3 = p_back + Vector3(d_back.z, 0.0, -d_back.x) * lateral
	var w_mid: Vector3 = p_mid + side_mid * lateral

	w_fwd.y = ChunkType.surface_height(a_fwd, lateral, road_seed)
	w_back.y = ChunkType.surface_height(a_back, lateral, road_seed)
	w_mid.y = ChunkType.surface_height(unit.along, lateral, road_seed)

	var fwd_vec: Vector3 = w_fwd - w_back
	if fwd_vec.length_squared() < 0.0001:
		fwd_vec = dir_mid * unit.lane_dir
	fwd_vec = fwd_vec.normalized()
	if absf(steer_yaw) > 0.001:
		fwd_vec = fwd_vec.rotated(Vector3.UP, steer_yaw).normalized()

	var right_axis: Vector3 = Vector3.UP.cross(fwd_vec)
	if right_axis.length_squared() < 0.0001:
		right_axis = Vector3.RIGHT
	right_axis = right_axis.normalized()
	var up_axis: Vector3 = fwd_vec.cross(right_axis).normalized()
	var car_basis := Basis(right_axis, up_axis, fwd_vec)
	unit.body.global_transform = Transform3D(car_basis, w_mid)


func _update_lights_and_wheels(
	unit: TrafficUnit, delta: float, braking: bool, dist_to_player: float
) -> void:
	unit.wheel_spin = fmod(unit.wheel_spin + (unit.current_speed / maxf(unit.wheel_radius, 0.1)) * delta, TAU)
	for w in unit.wheels:
		w.rotation.x = unit.wheel_spin
	for bmat in unit.brake_mats:
		bmat.emission_energy_multiplier = 3.2 if braking else 0.9
	if unit.headlight_spot != null:
		unit.headlight_spot.visible = is_night and dist_to_player < 190.0


# ------------------------------------------------------------ сборка машин


func _create_unit(index: int) -> TrafficUnit:
	var unit := TrafficUnit.new()
	var kind: int = index % 3
	var palette: Array[Color] = cfg.traffic_livery_colors if cfg != null and not cfg.traffic_livery_colors.is_empty() else []
	var livery: Color = palette[index % palette.size()] if not palette.is_empty() else LIVERY_COLORS[index % LIVERY_COLORS.size()]

	var body := AnimatableBody3D.new()
	body.name = "TrafficCar_%d" % index
	body.collision_layer = 2
	body.collision_mask = 0
	body.sync_to_physics = true

	var custom_scene: PackedScene = null
	if cfg != null and not cfg.traffic_body_scenes.is_empty():
		custom_scene = cfg.traffic_body_scenes[index % cfg.traffic_body_scenes.size()]

	var car_width: float = 1.98
	var car_length: float = 4.55
	var body_height: float = 0.68
	var cabin_height: float = 0.58
	var cabin_len: float = 2.30
	var cabin_z: float = -0.20
	if kind == BodyKind.HATCH:
		car_width = 1.92
		car_length = 4.15
		cabin_len = 2.50
		cabin_z = -0.38
	elif kind == BodyKind.VAN:
		car_width = 2.12
		car_length = 4.95
		body_height = 0.94
		cabin_height = 0.78
		cabin_len = 3.35
		cabin_z = -0.36

	if custom_scene != null:
		var custom_visual := custom_scene.instantiate() as Node3D
		if custom_visual != null:
			body.add_child(custom_visual)
	else:
		var body_mat := StandardMaterial3D.new()
		body_mat.albedo_color = livery
		body_mat.roughness = 0.52
		body_mat.metallic = 0.15

		var lower := MeshInstance3D.new()
		var lower_mesh := BoxMesh.new()
		lower_mesh.size = Vector3(car_width, body_height, car_length)
		lower.mesh = lower_mesh
		lower.material_override = body_mat
		lower.position = Vector3(0.0, 0.36 + body_height * 0.5, 0.0)
		body.add_child(lower)

		var roof := MeshInstance3D.new()
		var roof_mesh := BoxMesh.new()
		roof_mesh.size = Vector3(car_width * 0.86, cabin_height, cabin_len)
		roof.mesh = roof_mesh
		roof.material_override = body_mat if kind == BodyKind.VAN else _glass_mat
		roof.position = Vector3(0.0, 0.36 + body_height + cabin_height * 0.45, cabin_z)
		body.add_child(roof)

		# Лобовое и заднее стекло поверх фургона/кабины.
		if kind == BodyKind.VAN:
			var wind := MeshInstance3D.new()
			var wind_mesh := BoxMesh.new()
			wind_mesh.size = Vector3(car_width * 0.82, cabin_height * 0.65, cabin_len + 0.04)
			wind.mesh = wind_mesh
			wind.material_override = _glass_mat
			wind.position = Vector3(0.0, 0.36 + body_height + cabin_height * 0.42, cabin_z)
			body.add_child(wind)

		# Бамперы (+Z = перед, -Z = зад).
		var bumper_mesh := BoxMesh.new()
		bumper_mesh.size = Vector3(car_width * 1.02, 0.24, 0.18)
		for bz in [car_length * 0.5 + 0.02, -car_length * 0.5 - 0.02]:
			var bmp := MeshInstance3D.new()
			bmp.mesh = bumper_mesh
			bmp.material_override = _bumper_mat
			bmp.position = Vector3(0.0, 0.38, bz)
			body.add_child(bmp)

		# Передние фары (+Z).
		var lamp_mesh := BoxMesh.new()
		lamp_mesh.size = Vector3(0.36, 0.15, 0.08)
		for lx in [-car_width * 0.34, car_width * 0.34]:
			var hl := MeshInstance3D.new()
			hl.mesh = lamp_mesh
			hl.material_override = _headlight_mat
			hl.position = Vector3(lx, 0.66, car_length * 0.5 + 0.02)
			body.add_child(hl)

		# Задние фонари (-Z) со стоп-сигналами.
		var tail_mat := StandardMaterial3D.new()
		tail_mat.albedo_color = Color(0.85, 0.10, 0.08, 1.0)
		tail_mat.emission_enabled = true
		tail_mat.emission = Color(1.0, 0.14, 0.08, 1.0)
		tail_mat.emission_energy_multiplier = 0.9
		unit.brake_mats.append(tail_mat)
		for lx in [-car_width * 0.34, car_width * 0.34]:
			var tl := MeshInstance3D.new()
			tl.mesh = lamp_mesh
			tl.material_override = tail_mat
			tl.position = Vector3(lx, 0.68, -car_length * 0.5 - 0.02)
			body.add_child(tl)

		# 4 колеса (вращаются вокруг оси X).
		var w_mesh := CylinderMesh.new()
		w_mesh.top_radius = unit.wheel_radius
		w_mesh.bottom_radius = unit.wheel_radius
		w_mesh.height = 0.26
		w_mesh.radial_segments = 10
		var axle_z: float = car_length * 0.33
		var track_x: float = car_width * 0.48
		for wz in [axle_z, -axle_z]:
			for wx in [-track_x, track_x]:
				var w_pivot := Node3D.new()
				w_pivot.position = Vector3(wx, unit.wheel_radius, wz)
				var w_vis := MeshInstance3D.new()
				w_vis.mesh = w_mesh
				w_vis.material_override = _wheel_mat
				w_vis.rotation.z = PI * 0.5
				w_pivot.add_child(w_vis)
				body.add_child(w_pivot)
				unit.wheels.append(w_pivot)

	var spot := SpotLight3D.new()
	spot.name = "HeadlightBeam"
	spot.position = Vector3(0.0, 0.72, car_length * 0.5 + 0.08)
	spot.rotation_degrees = Vector3(-8.0, 180.0, 0.0)
	spot.light_color = Color(1.0, 0.92, 0.78, 1.0)
	spot.light_energy = cfg.traffic_headlight_energy if cfg != null else 5.5
	spot.spot_range = cfg.traffic_headlight_range if cfg != null else 42.0
	spot.spot_angle = 36.0
	spot.shadow_enabled = false
	spot.visible = is_night
	body.add_child(spot)
	unit.headlight_spot = spot

	# Коллайдер кузова.
	var col_shape := BoxShape3D.new()
	col_shape.size = Vector3(car_width * 0.96, body_height + cabin_height * 0.8, car_length * 0.96)
	var col := CollisionShape3D.new()
	col.shape = col_shape
	col.position = Vector3(0.0, 0.32 + col_shape.size.y * 0.5, 0.0)
	body.add_child(col)

	unit.body = body
	return unit


func _ensure_shared_materials() -> void:
	if _wheel_mat == null:
		_wheel_mat = StandardMaterial3D.new()
		_wheel_mat.albedo_color = Color(0.07, 0.07, 0.08, 1.0)
		_wheel_mat.roughness = 0.92
	if _glass_mat == null:
		_glass_mat = StandardMaterial3D.new()
		_glass_mat.albedo_color = Color(0.11, 0.15, 0.20, 1.0)
		_glass_mat.roughness = 0.25
		_glass_mat.metallic = 0.2
	if _bumper_mat == null:
		_bumper_mat = StandardMaterial3D.new()
		_bumper_mat.albedo_color = Color(0.16, 0.16, 0.18, 1.0)
		_bumper_mat.roughness = 0.85
	if _headlight_mat == null:
		_headlight_mat = StandardMaterial3D.new()
		_headlight_mat.albedo_color = Color(1.0, 0.96, 0.86, 1.0)
		_headlight_mat.emission_enabled = true
		_headlight_mat.emission = Color(1.0, 0.93, 0.78, 1.0)
		_headlight_mat.emission_energy_multiplier = 2.0
