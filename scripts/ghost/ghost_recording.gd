## Запись, хранение, интерполяция и расчёт живой дельты призрака.
##
## Формат файла — компактный бинарный `.rghost` (`user://ghosts/<ключ>.rghost`):
## загрузка и сохранение даже длинного 20-минутного спецучастка занимают
## миллисекунды, без раздувания `.tres`.
class_name RallyGhostRecording
extends RefCounted

const MAGIC := "RGHOST01"
const FORMAT_VERSION: int = 1
const MAX_SAMPLE_COUNT: int = 2000000
const DEFAULT_DIR := "user://ghosts"

var version: int = FORMAT_VERSION
var record_key: String = ""
var vehicle_id: String = ""
var setup_id: String = ""
var livery_index: int = 0
var paint_color: Color = Color(1.0, 1.0, 1.0, 1.0)
var finish_time: float = 0.0
var total_length: float = 0.0
var cp_times: PackedFloat32Array = PackedFloat32Array()

var times: PackedFloat32Array = PackedFloat32Array()
var alongs: PackedFloat32Array = PackedFloat32Array()
var positions: PackedVector3Array = PackedVector3Array()
var rot_xyzw: PackedFloat32Array = PackedFloat32Array()
var speeds: PackedFloat32Array = PackedFloat32Array()
var steers: PackedFloat32Array = PackedFloat32Array()
var brakes: PackedFloat32Array = PackedFloat32Array()
var wheel_ys: PackedFloat32Array = PackedFloat32Array()


func clear_samples() -> void:
	finish_time = 0.0
	cp_times.clear()
	times.clear()
	alongs.clear()
	positions.clear()
	rot_xyzw.clear()
	speeds.clear()
	steers.clear()
	brakes.clear()
	wheel_ys.clear()


func sample_count() -> int:
	return times.size()


func is_valid() -> bool:
	var n: int = times.size()
	if n < 2 or finish_time <= 0.0:
		return false
	return (
		alongs.size() == n
		and positions.size() == n
		and rot_xyzw.size() == n * 4
		and speeds.size() == n
		and steers.size() == n
		and brakes.size() == n
		and wheel_ys.size() == n * 4
	)


func start_along() -> float:
	return alongs[0] if not alongs.is_empty() else 0.0


func end_along() -> float:
	return alongs[alongs.size() - 1] if not alongs.is_empty() else 0.0


func append_sample(
	t: float,
	along_val: float,
	sample_pos: Vector3,
	sample_quat: Quaternion,
	speed_mps: float,
	steer_rad: float,
	brake_val: float,
	wy_fl: float = 0.0,
	wy_fr: float = 0.0,
	wy_rl: float = 0.0,
	wy_rr: float = 0.0
) -> void:
	var n: int = times.size()
	var safe_t: float = maxf(0.0, t)
	var safe_along: float = along_val
	if n > 0:
		var prev_t: float = times[n - 1]
		if safe_t < prev_t:
			safe_t = prev_t
		# Монотонность километража гарантирует O(log N) бинарный поиск для дельты.
		if safe_along < alongs[n - 1]:
			safe_along = alongs[n - 1]
		# Если время вообще не сдвинулось — обновляем последний кадр вместо дубля.
		if is_equal_approx(safe_t, prev_t):
			var last_idx: int = n - 1
			alongs[last_idx] = safe_along
			positions[last_idx] = sample_pos
			var qn := sample_quat.normalized()
			var rbase: int = last_idx * 4
			rot_xyzw[rbase] = qn.x
			rot_xyzw[rbase + 1] = qn.y
			rot_xyzw[rbase + 2] = qn.z
			rot_xyzw[rbase + 3] = qn.w
			speeds[last_idx] = speed_mps
			steers[last_idx] = steer_rad
			brakes[last_idx] = clampf(brake_val, 0.0, 1.0)
			wheel_ys[rbase] = wy_fl
			wheel_ys[rbase + 1] = wy_fr
			wheel_ys[rbase + 2] = wy_rl
			wheel_ys[rbase + 3] = wy_rr
			return
	var q_norm := sample_quat.normalized()
	times.append(safe_t)
	alongs.append(safe_along)
	positions.append(sample_pos)
	rot_xyzw.append(q_norm.x)
	rot_xyzw.append(q_norm.y)
	rot_xyzw.append(q_norm.z)
	rot_xyzw.append(q_norm.w)
	speeds.append(speed_mps)
	steers.append(steer_rad)
	brakes.append(clampf(brake_val, 0.0, 1.0))
	wheel_ys.append(wy_fl)
	wheel_ys.append(wy_fr)
	wheel_ys.append(wy_rl)
	wheel_ys.append(wy_rr)


func set_checkpoint_time(cp_index: int, cp_time: float) -> void:
	if cp_index < 0:
		return
	if cp_times.size() <= cp_index:
		var old_size: int = cp_times.size()
		cp_times.resize(cp_index + 1)
		for k in range(old_size, cp_times.size()):
			cp_times[k] = 0.0
	cp_times[cp_index] = maxf(0.0, cp_time)


func get_checkpoint_time(cp_index: int) -> float:
	if cp_index < 0 or cp_index >= cp_times.size():
		return 0.0
	return cp_times[cp_index]


func quat_at(index: int) -> Quaternion:
	var base: int = clampi(index, 0, maxi(0, times.size() - 1)) * 4
	if base + 3 >= rot_xyzw.size():
		return Quaternion.IDENTITY
	return Quaternion(
		rot_xyzw[base],
		rot_xyzw[base + 1],
		rot_xyzw[base + 2],
		rot_xyzw[base + 3]
	).normalized()


## Интерполяция позы, колёс и тормозов призрака на момент времени `t`.
func sample_at_time(t: float, smooth: bool = true) -> Dictionary:
	var n: int = times.size()
	if n == 0 or positions.size() != n:
		return {"valid": false}
	if n == 1 or t <= times[0]:
		return {
			"valid": true,
			"pos": positions[0],
			"quat": quat_at(0),
			"along": alongs[0],
			"speed_mps": speeds[0],
			"steer": steers[0],
			"brake": brakes[0],
			"wy_fl": wheel_ys[0],
			"wy_fr": wheel_ys[1],
			"wy_rl": wheel_ys[2],
			"wy_rr": wheel_ys[3],
			"finished": false,
		}
	var last: int = n - 1
	if t >= times[last]:
		var b_last: int = last * 4
		var is_done: bool = finish_time > 0.0 and t >= finish_time
		return {
			"valid": true,
			"pos": positions[last],
			"quat": quat_at(last),
			"along": alongs[last],
			"speed_mps": speeds[last],
			"steer": steers[last],
			"brake": brakes[last],
			"wy_fl": wheel_ys[b_last],
			"wy_fr": wheel_ys[b_last + 1],
			"wy_rl": wheel_ys[b_last + 2],
			"wy_rr": wheel_ys[b_last + 3],
			"finished": is_done,
		}

	var idx: int = _upper_bracket(times, t)
	var span: float = maxf(0.00001, times[idx + 1] - times[idx])
	var u: float = clampf((t - times[idx]) / span, 0.0, 1.0)

	var p1: Vector3 = positions[idx]
	var p2: Vector3 = positions[idx + 1]
	var out_pos: Vector3
	# При респавне (> 30 м скачок) Catmull-Rom не натягиваем, чтобы призрак не нырял под землю.
	if smooth and n >= 4 and p1.distance_squared_to(p2) < 900.0:
		var p0: Vector3 = positions[maxi(0, idx - 1)]
		var p3: Vector3 = positions[mini(last, idx + 2)]
		if p0.distance_squared_to(p1) < 900.0 and p2.distance_squared_to(p3) < 900.0:
			var u2: float = u * u
			var u3: float = u2 * u
			out_pos = 0.5 * (
				(2.0 * p1)
				+ (-p0 + p2) * u
				+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3
			)
		else:
			out_pos = p1.lerp(p2, u)
	else:
		out_pos = p1.lerp(p2, u)

	var q1: Quaternion = quat_at(idx)
	var q2: Quaternion = quat_at(idx + 1)
	if q1.dot(q2) < 0.0:
		q2 = -q2
	var out_quat: Quaternion = q1.slerp(q2, u).normalized()

	var b0: int = idx * 4
	var b1: int = (idx + 1) * 4
	return {
		"valid": true,
		"pos": out_pos,
		"quat": out_quat,
		"along": lerpf(alongs[idx], alongs[idx + 1], u),
		"speed_mps": lerpf(speeds[idx], speeds[idx + 1], u),
		"steer": lerpf(steers[idx], steers[idx + 1], u),
		"brake": lerpf(brakes[idx], brakes[idx + 1], u),
		"wy_fl": lerpf(wheel_ys[b0], wheel_ys[b1], u),
		"wy_fr": lerpf(wheel_ys[b0 + 1], wheel_ys[b1 + 1], u),
		"wy_rl": lerpf(wheel_ys[b0 + 2], wheel_ys[b1 + 2], u),
		"wy_rr": lerpf(wheel_ys[b0 + 3], wheel_ys[b1 + 3], u),
		"finished": false,
	}


## Время и скорость призрака в заданном километраже трассы.
func time_at_along(query_along: float) -> Dictionary:
	var n: int = alongs.size()
	if n < 2 or times.size() != n:
		return {"valid": false}
	if query_along <= alongs[0]:
		return {
			"valid": true,
			"time": times[0],
			"speed_mps": speeds[0],
			"beyond_end": false,
		}
	var last: int = n - 1
	if query_along >= alongs[last]:
		var end_t: float = finish_time if finish_time > 0.0 else times[last]
		return {
			"valid": true,
			"time": end_t,
			"speed_mps": speeds[last],
			"beyond_end": true,
		}
	var idx: int = _upper_bracket(alongs, query_along)
	var a0: float = alongs[idx]
	var a1: float = alongs[idx + 1]
	var span: float = a1 - a0
	var u: float = clampf((query_along - a0) / span, 0.0, 1.0) if span > 0.0001 else 0.0
	return {
		"valid": true,
		"time": lerpf(times[idx], times[idx + 1], u),
		"speed_mps": lerpf(speeds[idx], speeds[idx + 1], u),
		"beyond_end": false,
	}


func along_at_time(t: float) -> float:
	var n: int = times.size()
	if n == 0 or alongs.size() != n:
		return 0.0
	if n == 1 or t <= times[0]:
		return alongs[0]
	var last: int = n - 1
	if t >= times[last]:
		return alongs[last]
	var idx: int = _upper_bracket(times, t)
	var span: float = maxf(0.00001, times[idx + 1] - times[idx])
	var u: float = clampf((t - times[idx]) / span, 0.0, 1.0)
	return lerpf(alongs[idx], alongs[idx + 1], u)


## Живая дельта игрока относительно этой записи призрака.
## delta_sec < 0 означает «игрок быстрее ориентира»; > 0 — «отстаёт».
func compute_delta(stage_time: float, player_along: float, player_speed_mps: float) -> Dictionary:
	var lookup: Dictionary = time_at_along(player_along)
	if not bool(lookup.get("valid", false)):
		return {"valid": false}
	var ref_time: float = float(lookup["time"])
	var ref_speed_mps: float = float(lookup["speed_mps"])
	var g_along: float = along_at_time(stage_time)
	return {
		"valid": true,
		"is_target": false,
		"delta_sec": stage_time - ref_time,
		"ref_time": ref_time,
		"gap_meters": player_along - g_along,
		"speed_delta_kmh": (player_speed_mps - ref_speed_mps) * 3.6,
		"ref_speed_kmh": ref_speed_mps * 3.6,
		"ghost_along": g_along,
	}


## Живая дельта относительно целевого времени трассы (когда призрака ещё нет
## или выбран режим «Только цель»).
static func compute_target_delta(
	stage_time: float,
	player_along: float,
	player_speed_mps: float,
	start_d: float,
	finish_d: float,
	target_time: float
) -> Dictionary:
	if target_time <= 0.05:
		return {"valid": false}
	var span: float = maxf(1.0, finish_d - start_d)
	var frac: float = clampf((player_along - start_d) / span, 0.0, 1.0)
	var ref_time: float = frac * target_time
	var target_speed_mps: float = span / target_time
	var pacer_along: float = clampf(start_d + target_speed_mps * stage_time, start_d, finish_d)
	return {
		"valid": true,
		"is_target": true,
		"delta_sec": stage_time - ref_time,
		"ref_time": ref_time,
		"gap_meters": player_along - pacer_along,
		"speed_delta_kmh": (player_speed_mps - target_speed_mps) * 3.6,
		"ref_speed_kmh": target_speed_mps * 3.6,
		"ghost_along": pacer_along,
	}


## Устойчивый к шпилькам и петлям километраж: ищет ближайший отрезок в локальном
## окне вокруг предыдущего `prev_along` и переходит к глобальному поиску только
## при большом улёте/сбросе машины.
static func along_near(
	network: RoadNetwork,
	x: float,
	z: float,
	prev_along: float,
	window_m: float = 55.0,
	fallback_dist_m: float = 35.0
) -> float:
	if network == null or network.samples.size() < 2:
		return 0.0
	if prev_along < 0.0:
		return network.along_road(x, z)
	var count: int = network.samples.size()
	var step: float = maxf(0.1, network.total_length / float(maxi(1, count - 1)))
	var center_idx: int = clampi(roundi(prev_along / step), 0, count - 2)
	var half_segs: int = maxi(8, ceili(window_m / step))
	var lo: int = maxi(0, center_idx - half_segs)
	var hi: int = mini(count - 2, center_idx + half_segs)
	var best_sq: float = INF
	var best_along: float = prev_along
	for i in range(lo, hi + 1):
		var a: Vector3 = network.samples[i]
		var b: Vector3 = network.samples[i + 1]
		var sx: float = b.x - a.x
		var sz: float = b.z - a.z
		var len_sq: float = sx * sx + sz * sz
		var t: float = clampf(((x - a.x) * sx + (z - a.z) * sz) / len_sq, 0.0, 1.0) if len_sq > 0.000001 else 0.0
		var dx: float = x - (a.x + sx * t)
		var dz: float = z - (a.z + sz * t)
		var sq: float = dx * dx + dz * dz
		if sq < best_sq:
			best_sq = sq
			best_along = lerpf(network.sample_dists[i], network.sample_dists[i + 1], t)
	if best_sq <= fallback_dist_m * fallback_dist_m:
		return best_along
	return network.along_road(x, z)


static func storage_path_for(
	key: String,
	veh_id: String = "",
	separate_by_vehicle: bool = false,
	dir_path: String = DEFAULT_DIR
) -> String:
	var full_key: String = key
	if separate_by_vehicle and not veh_id.is_empty():
		full_key = "%s@%s" % [key, veh_id]
	var clean_dir: String = dir_path if not dir_path.is_empty() else DEFAULT_DIR
	var slug := _safe_slug(full_key)
	var hash_hex: String = full_key.sha256_text().substr(0, 16)
	return clean_dir.path_join("%s_%s.rghost" % [slug, hash_hex])


static func _safe_slug(raw: String) -> String:
	var out := ""
	for i in range(raw.length()):
		var ch: String = raw.substr(i, 1)
		var code: int = ch.unicode_at(0)
		var ok: bool = (
			(code >= 48 and code <= 57)
			or (code >= 65 and code <= 90)
			or (code >= 97 and code <= 122)
			or code == 95
			or code == 45
		)
		out += ch if ok else "_"
		if out.length() >= 36:
			break
	if out.is_empty():
		return "stage"
	return out


func save_to_file(file_path: String) -> Error:
	if not is_valid():
		return ERR_INVALID_DATA
	var base_dir: String = file_path.get_base_dir()
	if not base_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(base_dir)
	var file_handle := FileAccess.open(file_path, FileAccess.WRITE)
	if file_handle == null:
		return FileAccess.get_open_error()

	var cp_arr: Array[float] = []
	for v in cp_times:
		cp_arr.append(float(v))
	var meta := {
		"record_key": record_key,
		"vehicle_id": vehicle_id,
		"setup_id": setup_id,
		"livery_index": livery_index,
		"paint": [paint_color.r, paint_color.g, paint_color.b, paint_color.a],
		"finish_time": finish_time,
		"total_length": total_length,
		"cp_times": cp_arr,
	}
	var meta_bytes: PackedByteArray = JSON.stringify(meta).to_utf8_buffer()
	var n: int = times.size()
	var pos_xyz: PackedFloat32Array = _pack_vec3(positions)

	file_handle.store_buffer(MAGIC.to_ascii_buffer())
	file_handle.store_32(FORMAT_VERSION)
	file_handle.store_32(meta_bytes.size())
	file_handle.store_buffer(meta_bytes)
	file_handle.store_32(n)
	file_handle.store_buffer(times.to_byte_array())
	file_handle.store_buffer(alongs.to_byte_array())
	file_handle.store_buffer(pos_xyz.to_byte_array())
	file_handle.store_buffer(rot_xyzw.to_byte_array())
	file_handle.store_buffer(speeds.to_byte_array())
	file_handle.store_buffer(steers.to_byte_array())
	file_handle.store_buffer(brakes.to_byte_array())
	file_handle.store_buffer(wheel_ys.to_byte_array())
	file_handle.flush()
	return OK


static func load_from_file(file_path: String) -> RallyGhostRecording:
	if file_path.is_empty() or not FileAccess.file_exists(file_path):
		return null
	var file_handle := FileAccess.open(file_path, FileAccess.READ)
	if file_handle == null:
		return null
	if file_handle.get_length() < 24:
		return null
	var magic_buf: PackedByteArray = file_handle.get_buffer(MAGIC.length())
	if magic_buf.get_string_from_ascii() != MAGIC:
		return null
	var fmt_ver: int = file_handle.get_32()
	if fmt_ver != FORMAT_VERSION:
		return null
	var meta_len: int = file_handle.get_32()
	if meta_len <= 0 or meta_len > 1048576:
		return null
	var meta_buf: PackedByteArray = file_handle.get_buffer(meta_len)
	if meta_buf.size() != meta_len:
		return null
	var parsed: Variant = JSON.parse_string(meta_buf.get_string_from_utf8())
	if not (parsed is Dictionary):
		return null
	var meta: Dictionary = parsed as Dictionary
	var n: int = file_handle.get_32()
	if n < 2 or n > MAX_SAMPLE_COUNT:
		return null

	var bytes_1: int = n * 4
	var bytes_3: int = n * 12
	var bytes_4: int = n * 16
	var b_times: PackedByteArray = file_handle.get_buffer(bytes_1)
	var b_alongs: PackedByteArray = file_handle.get_buffer(bytes_1)
	var b_pos: PackedByteArray = file_handle.get_buffer(bytes_3)
	var b_rot: PackedByteArray = file_handle.get_buffer(bytes_4)
	var b_speeds: PackedByteArray = file_handle.get_buffer(bytes_1)
	var b_steers: PackedByteArray = file_handle.get_buffer(bytes_1)
	var b_brakes: PackedByteArray = file_handle.get_buffer(bytes_1)
	var b_wys: PackedByteArray = file_handle.get_buffer(bytes_4)
	if (
		b_times.size() != bytes_1
		or b_alongs.size() != bytes_1
		or b_pos.size() != bytes_3
		or b_rot.size() != bytes_4
		or b_speeds.size() != bytes_1
		or b_steers.size() != bytes_1
		or b_brakes.size() != bytes_1
		or b_wys.size() != bytes_4
	):
		return null

	var rec := RallyGhostRecording.new()
	rec.version = fmt_ver
	rec.record_key = String(meta.get("record_key", ""))
	rec.vehicle_id = String(meta.get("vehicle_id", ""))
	rec.setup_id = String(meta.get("setup_id", ""))
	rec.livery_index = int(meta.get("livery_index", 0))
	var paint_arr: Variant = meta.get("paint", [])
	if paint_arr is Array and (paint_arr as Array).size() >= 4:
		var pa: Array = paint_arr as Array
		rec.paint_color = Color(float(pa[0]), float(pa[1]), float(pa[2]), float(pa[3]))
	rec.finish_time = float(meta.get("finish_time", 0.0))
	rec.total_length = float(meta.get("total_length", 0.0))
	var raw_cps: Variant = meta.get("cp_times", [])
	if raw_cps is Array:
		for cp_val in (raw_cps as Array):
			rec.cp_times.append(float(cp_val))
	rec.times = b_times.to_float32_array()
	rec.alongs = b_alongs.to_float32_array()
	rec.positions = _unpack_vec3(b_pos.to_float32_array())
	rec.rot_xyzw = b_rot.to_float32_array()
	rec.speeds = b_speeds.to_float32_array()
	rec.steers = b_steers.to_float32_array()
	rec.brakes = b_brakes.to_float32_array()
	rec.wheel_ys = b_wys.to_float32_array()
	if not rec.is_valid():
		return null
	return rec


static func delete_file(file_path: String) -> bool:
	if file_path.is_empty() or not FileAccess.file_exists(file_path):
		return false
	return DirAccess.remove_absolute(file_path) == OK


static func has_saved_ghost(
	key: String,
	veh_id: String = "",
	separate_by_vehicle: bool = false,
	dir_path: String = DEFAULT_DIR
) -> bool:
	var file_path: String = storage_path_for(key, veh_id, separate_by_vehicle, dir_path)
	return not file_path.is_empty() and FileAccess.file_exists(file_path)


func save_for_key(
	key: String,
	veh_id: String = "",
	separate_by_vehicle: bool = false,
	dir_path: String = DEFAULT_DIR
) -> Error:
	return save_to_file(storage_path_for(key, veh_id, separate_by_vehicle, dir_path))


static func load_for_key(
	key: String,
	veh_id: String = "",
	separate_by_vehicle: bool = false,
	dir_path: String = DEFAULT_DIR
) -> RallyGhostRecording:
	return load_from_file(storage_path_for(key, veh_id, separate_by_vehicle, dir_path))


static func delete_ghost(
	key: String,
	veh_id: String = "",
	separate_by_vehicle: bool = false,
	dir_path: String = DEFAULT_DIR
) -> bool:
	return delete_file(storage_path_for(key, veh_id, separate_by_vehicle, dir_path))


static func _upper_bracket(arr: PackedFloat32Array, value: float) -> int:
	var lo: int = 0
	var hi: int = arr.size() - 2
	while lo < hi:
		var mid: int = (lo + hi + 1) >> 1
		if arr[mid] <= value:
			lo = mid
		else:
			hi = mid - 1
	return lo


static func _pack_vec3(arr: PackedVector3Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(arr.size() * 3)
	for i in range(arr.size()):
		var v: Vector3 = arr[i]
		var base: int = i * 3
		out[base] = v.x
		out[base + 1] = v.y
		out[base + 2] = v.z
	return out


static func _unpack_vec3(floats: PackedFloat32Array) -> PackedVector3Array:
	@warning_ignore("integer_division")
	var count: int = floats.size() / 3
	var out := PackedVector3Array()
	out.resize(count)
	for i in range(count):
		var base: int = i * 3
		out[i] = Vector3(floats[base], floats[base + 1], floats[base + 2])
	return out
