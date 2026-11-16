## Живой двухсторонний трафик аркадного режима.
##
## Машины держат свою полосу (встречные — левую, попутные — правую),
## замедляются перед крутыми шпильками серпантина и в деревнях, соблюдают
## дистанцию за впереди идущим транспортом и смещаются к обочине, уступая
## дорогу игроку при приближении.
##
## Реализованы на `AnimatableBody3D` (слой 2, как и отбойники/деревья):
## при столкновении передают честный физический импульс машине игрока, не
## проваливаясь под дорогу и не тратя CPU на 4-колёсную подвеску вдали.
class_name RallyArcadeTraffic
extends Node3D

const RoadType = preload("res://scripts/arcade/arcade_road.gd")
const ChunkType = preload("res://scripts/arcade/arcade_chunk.gd")
const LegType = preload("res://scripts/data/rally_arcade_leg.gd")

const MAX_ACTIVE_CARS: int = 10
const SPAWN_AHEAD_MIN: float = 95.0
const SPAWN_AHEAD_MAX: float = 310.0
const DESPAWN_BEHIND: float = 115.0
const DESPAWN_AHEAD: float = 360.0
const MIN_SEPARATION_SAME_LANE: float = 38.0

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
	var base_speed: float = 18.0
	var current_speed: float = 18.0
	var yield_offset: float = 0.0
	var wheel_spin: float = 0.0
	var wheel_radius: float = 0.32
	var hit_pause: float = 0.0
	var overtaken: bool = false
	var active: bool = false
	var last_lateral: float = 0.0


var road_seed: int = 0
var network = null
var is_night: bool = false
var overtakes: int = 0

var _units: Array[TrafficUnit] = []
var _spawn_counter: int = 0
var _reposition_clock: float = 0.0
var _wheel_mat: StandardMaterial3D = null
var _glass_mat: StandardMaterial3D = null
var _bumper_mat: StandardMaterial3D = null
var _headlight_mat: StandardMaterial3D = null


func setup(p_seed: int, p_network, p_is_night: bool) -> void:
	road_seed = p_seed
	network = p_network
	is_night = p_is_night
	overtakes = 0
	for child in get_children():
		child.queue_free()
	_units.clear()
	_spawn_counter = 0
	_ensure_shared_materials()

	for i in range(MAX_ACTIVE_CARS):
		var unit := _create_unit(i)
		_units.append(unit)
		add_child(unit.body)


func prime(player_along: float) -> void:
	for i in range(_units.size()):
		var unit := _units[i]
		var lane_dir: float = -1.0 if (i % 2 == 0) else 1.0
		var dist: float = player_along + lerpf(70.0, SPAWN_AHEAD_MAX, float(i) / float(maxi(1, _units.size() - 1)))
		_place_unit_at(unit, dist, lane_dir, i)


func step(delta: float, player_along: float, player_pos: Vector3, player_vel: Vector3) -> void:
	if network == null or _units.is_empty():
		return

	var player_dir: Vector3 = network.direction_at(maxf(0.0, player_along))
	var player_side := Vector3(player_dir.z, 0.0, -player_dir.x)
	var player_pt: Vector3 = network.point_at(maxf(0.0, player_along))
	var player_lat: float = player_side.dot(player_pos - player_pt)
	var player_speed: float = Vector2(player_vel.x, player_vel.z).length()

	for i in range(_units.size()):
		var unit := _units[i]
		if not unit.active:
			continue

		if unit.hit_pause > 0.0:
			unit.hit_pause = maxf(0.0, unit.hit_pause - delta)

		# 1. Рецикл машин, ушедших далеко назад или вперёд.
		var rel: float = unit.along - player_along
		if rel < -DESPAWN_BEHIND or rel > DESPAWN_AHEAD:
			var new_dir: float = -1.0 if (i % 2 == 0) else 1.0
			var spawn_dist: float = _pick_spawn_distance(player_along, new_dir, i)
			if spawn_dist > 8.0:
				_place_unit_at(unit, spawn_dist, new_dir, i)
			continue

		# Засчитываем чистый обгон попутной машины.
		if unit.lane_dir > 0.0 and not unit.overtaken and unit.along < player_along - 4.0 and player_speed > 8.0:
			unit.overtaken = true
			overtakes += 1

		# 2. Целевая скорость с учётом домена, поворотов впереди и трафика впереди.
		var desired_speed: float = _target_speed_for(unit)
		var lead_gap: float = _nearest_ahead_gap(unit)
		if lead_gap < 28.0:
			var follow_scale: float = clampf((lead_gap - 7.5) / 20.5, 0.0, 1.0)
			desired_speed = minf(desired_speed, unit.current_speed * follow_scale + 2.0 * follow_scale)
		if unit.hit_pause > 0.0:
			desired_speed = minf(desired_speed, 3.0)

		var braking: bool = desired_speed < unit.current_speed - 1.8
		var accel_rate: float = 9.0 if braking else 4.5
		unit.current_speed = move_toward(unit.current_speed, desired_speed, accel_rate * delta)

		# Двигаемся вперёд по полосе (не уходим в отрицательный километраж).
		var next_along: float = unit.along + unit.lane_dir * unit.current_speed * delta
		if next_along < 6.0 and unit.lane_dir < 0.0:
			var respawn_dist: float = _pick_spawn_distance(player_along, -1.0, i)
			_place_unit_at(unit, respawn_dist, -1.0, i)
			continue
		unit.along = next_along

		# 3. Уступчивость: если игрок близко и нагоняет / сместился на полосу,
		# трафик сдвигается ближе к своей обочине.
		var half: float = ChunkType.half_width_at(unit.along, road_seed)
		var base_lat: float = unit.lane_dir * half * 0.50
		var target_yield: float = _compute_yield_offset(unit, player_along, player_lat, player_speed, half)
		var prev_yield: float = unit.yield_offset
		unit.yield_offset = move_toward(unit.yield_offset, target_yield, 2.2 * delta)
		var lateral_vel: float = (unit.yield_offset - prev_yield) / maxf(delta, 0.001)
		var max_lat: float = maxf(half - 0.88, 1.2)
		var actual_lat: float = clampf(base_lat + unit.yield_offset, -max_lat, max_lat)
		unit.last_lateral = actual_lat

		# Проверка контакта/наезда с игроком (легкий сброс скорости при касании).
		var unit_pos_flat := Vector2(unit.body.global_position.x, unit.body.global_position.z)
		if unit_pos_flat.distance_to(Vector2(player_pos.x, player_pos.z)) < 2.9:
			unit.hit_pause = 1.6
			braking = true

		# 4. Точная посадка на полотно с уклоном, поворотом и вращением колёс.
		var steer_yaw: float = clampf(-lateral_vel * unit.lane_dir * 0.14, -0.22, 0.22)
		_apply_transform(unit, actual_lat, steer_yaw)
		_update_lights_and_wheels(unit, delta, braking, absf(unit.along - player_along))


func _target_speed_for(unit: TrafficUnit) -> float:
	var leg_index: int = RoadType.leg_index_at(unit.along)
	var built: RoadType.Leg = RoadType.leg(leg_index, road_seed)
	var limit_mps: float = unit.base_speed
	if built != null:
		var dom: int = built.domain_at(unit.along)
		if dom == LegType.Kind.VILLAGE:
			limit_mps = minf(limit_mps, 13.0)
		elif dom == LegType.Kind.BRIDGE:
			limit_mps = minf(limit_mps, 15.5)
		elif dom == LegType.Kind.SERPENTINE:
			limit_mps = minf(limit_mps, 14.5)
		elif dom == LegType.Kind.FAST:
			limit_mps = unit.base_speed * 1.18

	# Притормаживаем перед крутым поворотом впереди по курсу.
	var ahead_d: float = maxf(2.0, unit.along + unit.lane_dir * 22.0)
	var d0: Vector3 = network.direction_at(maxf(0.0, unit.along))
	var d1: Vector3 = network.direction_at(ahead_d)
	var turn: float = absf(wrapf(atan2(d1.z, d1.x) - atan2(d0.z, d0.x), -PI, PI))
	if turn > 0.55:
		limit_mps = minf(limit_mps, 10.5)
	elif turn > 0.28:
		limit_mps = minf(limit_mps, 14.5)
	return limit_mps


func _nearest_ahead_gap(unit: TrafficUnit) -> float:
	var best: float = INF
	for other in _units:
		if other == unit or not other.active or other.lane_dir != unit.lane_dir:
			continue
		var diff: float = (other.along - unit.along) * unit.lane_dir
		if diff > 0.0 and diff < best:
			best = diff
	return best


func _compute_yield_offset(
	unit: TrafficUnit, player_along: float, player_lat: float, player_speed: float, half: float
) -> float:
	var delta_along: float = unit.along - player_along
	var room: float = maxf(0.0, (half - 0.92) - half * 0.50)
	if unit.lane_dir > 0.0:
		# Попутная машина: если игрок быстро нагоняет сзади, сдвигаемся вправо к обочине.
		if delta_along > -6.0 and delta_along < 52.0 and player_speed > unit.current_speed + 2.5:
			return room * 0.92
	else:
		# Встречная: если игрок вылез на встречную полосу или несётся близко, жмёмся левее к краю.
		if delta_along > -6.0 and delta_along < 62.0:
			if player_lat < 0.65 or player_speed > 26.0:
				return -room * 0.95
	return 0.0


func _pick_spawn_distance(player_along: float, lane_dir: float, slot: int) -> float:
	_spawn_counter += 1
	var base_min: float = SPAWN_AHEAD_MIN if lane_dir < 0.0 else 75.0
	var span: float = SPAWN_AHEAD_MAX - base_min
	var candidate: float = player_along + base_min + RoadType.roll(_spawn_counter * 17 + slot, road_seed, 951) * span
	# Не сажаем машину поверх другой машины в той же полосе.
	for attempt in range(5):
		var clear: bool = true
		for other in _units:
			if not other.active or other.lane_dir != lane_dir:
				continue
			if absf(other.along - candidate) < MIN_SEPARATION_SAME_LANE:
				clear = false
				break
		if clear:
			return candidate
		candidate += MIN_SEPARATION_SAME_LANE * 0.9
	return candidate


func _place_unit_at(unit: TrafficUnit, dist: float, lane_dir: float, slot: int) -> void:
	_spawn_counter += 1
	unit.along = maxf(18.0, dist)
	unit.lane_dir = lane_dir
	unit.base_speed = RoadType.roll_range(_spawn_counter + slot * 7, road_seed, 952, 14.5, 22.5)
	unit.current_speed = unit.base_speed * 0.85
	unit.yield_offset = 0.0
	unit.hit_pause = 0.0
	unit.overtaken = false
	unit.active = true
	var half: float = ChunkType.half_width_at(unit.along, road_seed)
	var lat: float = lane_dir * half * 0.50
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
		bmat.emission_energy_multiplier = 2.6 if braking else 0.9
	if unit.headlight_spot != null:
		unit.headlight_spot.visible = is_night and dist_to_player < 190.0


# ------------------------------------------------------------ сборка машин


func _create_unit(index: int) -> TrafficUnit:
	var unit := TrafficUnit.new()
	var kind: int = index % 3
	var livery: Color = LIVERY_COLORS[index % LIVERY_COLORS.size()]

	var body := AnimatableBody3D.new()
	body.name = "TrafficCar_%d" % index
	body.collision_layer = 2
	body.collision_mask = 0
	body.sync_to_physics = true

	var car_width: float = 1.72
	var car_length: float = 4.05
	var body_height: float = 0.62
	var cabin_height: float = 0.54
	var cabin_len: float = 2.05
	var cabin_z: float = -0.18
	if kind == BodyKind.HATCH:
		car_length = 3.65
		cabin_len = 2.25
		cabin_z = -0.35
	elif kind == BodyKind.VAN:
		car_width = 1.84
		car_length = 4.35
		body_height = 0.85
		cabin_height = 0.72
		cabin_len = 2.95
		cabin_z = -0.32

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = livery
	body_mat.roughness = 0.52
	body_mat.metallic = 0.15

	var lower := MeshInstance3D.new()
	var lower_mesh := BoxMesh.new()
	lower_mesh.size = Vector3(car_width, body_height, car_length)
	lower.mesh = lower_mesh
	lower.material_override = body_mat
	lower.position = Vector3(0.0, 0.34 + body_height * 0.5, 0.0)
	body.add_child(lower)

	var roof := MeshInstance3D.new()
	var roof_mesh := BoxMesh.new()
	roof_mesh.size = Vector3(car_width * 0.86, cabin_height, cabin_len)
	roof.mesh = roof_mesh
	roof.material_override = body_mat if kind == BodyKind.VAN else _glass_mat
	roof.position = Vector3(0.0, 0.34 + body_height + cabin_height * 0.45, cabin_z)
	body.add_child(roof)

	# Лобовое и заднее стекло поверх фургона/кабины.
	if kind == BodyKind.VAN:
		var wind := MeshInstance3D.new()
		var wind_mesh := BoxMesh.new()
		wind_mesh.size = Vector3(car_width * 0.82, cabin_height * 0.65, cabin_len + 0.04)
		wind.mesh = wind_mesh
		wind.material_override = _glass_mat
		wind.position = Vector3(0.0, 0.34 + body_height + cabin_height * 0.42, cabin_z)
		body.add_child(wind)

	# Бамперы (+Z = перед, -Z = зад).
	var bumper_mesh := BoxMesh.new()
	bumper_mesh.size = Vector3(car_width * 1.02, 0.22, 0.16)
	for bz in [car_length * 0.5 + 0.02, -car_length * 0.5 - 0.02]:
		var bmp := MeshInstance3D.new()
		bmp.mesh = bumper_mesh
		bmp.material_override = _bumper_mat
		bmp.position = Vector3(0.0, 0.36, bz)
		body.add_child(bmp)

	# Передние фары (+Z) и прожектор для ночи.
	var lamp_mesh := BoxMesh.new()
	lamp_mesh.size = Vector3(0.32, 0.14, 0.08)
	for lx in [-car_width * 0.34, car_width * 0.34]:
		var hl := MeshInstance3D.new()
		hl.mesh = lamp_mesh
		hl.material_override = _headlight_mat
		hl.position = Vector3(lx, 0.62, car_length * 0.5 + 0.02)
		body.add_child(hl)

	var spot := SpotLight3D.new()
	spot.name = "HeadlightBeam"
	spot.position = Vector3(0.0, 0.68, car_length * 0.5 + 0.08)
	spot.rotation_degrees = Vector3(-8.0, 180.0, 0.0)
	spot.light_color = Color(1.0, 0.92, 0.78, 1.0)
	spot.light_energy = 5.5
	spot.spot_range = 42.0
	spot.spot_angle = 36.0
	spot.shadow_enabled = false
	spot.visible = is_night
	body.add_child(spot)
	unit.headlight_spot = spot

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
		tl.position = Vector3(lx, 0.64, -car_length * 0.5 - 0.02)
		body.add_child(tl)

	# 4 колеса (вращаются вокруг оси X).
	var w_mesh := CylinderMesh.new()
	w_mesh.top_radius = unit.wheel_radius
	w_mesh.bottom_radius = unit.wheel_radius
	w_mesh.height = 0.24
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

	# Коллайдер кузова.
	var col_shape := BoxShape3D.new()
	col_shape.size = Vector3(car_width * 0.96, body_height + cabin_height * 0.8, car_length * 0.96)
	var col := CollisionShape3D.new()
	col.shape = col_shape
	col.position = Vector3(0.0, 0.30 + col_shape.size.y * 0.5, 0.0)
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
