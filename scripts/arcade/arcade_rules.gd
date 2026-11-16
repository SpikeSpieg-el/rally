## Правила аркадного заезда: очки, множитель чистой езды, строгий урон HP
## и таблица рекордов по пройденной дистанции (`user://arcade_records.cfg`).
class_name RallyArcadeRules
extends RefCounted

const ArcadeSettingsType = preload("res://scripts/data/rally_arcade_settings.gd")

const MAX_HP: float = 100.0
const RECORDS_PATH := "user://arcade_records.cfg"
const MAX_LEADERBOARD: int = 5

var cfg: ArcadeSettingsType = null
var max_hp: float = MAX_HP
var hp: float = MAX_HP
var score: int = 0
var multiplier: float = 1.0
var clean_streak_sec: float = 0.0
var overtakes: int = 0
var near_misses: int = 0
var ped_hits: int = 0
var crashes: int = 0
var run_ended: bool = false

var _score_frac: float = 0.0
var _damage_cooldown: float = 0.0
var _next_milestone_m: float = 500.0


func configure(p_cfg: ArcadeSettingsType) -> void:
	cfg = p_cfg
	reset()


func reset() -> void:
	max_hp = cfg.max_hp if cfg != null else MAX_HP
	hp = max_hp
	score = 0
	multiplier = 1.0
	clean_streak_sec = 0.0
	overtakes = 0
	near_misses = 0
	ped_hits = 0
	crashes = 0
	run_ended = false
	_score_frac = 0.0
	_damage_cooldown = 0.0
	_next_milestone_m = cfg.milestone_distance_m if cfg != null else 500.0


func tick(
	delta: float, speed_mps: float, on_road: bool, max_along: float, dv_horiz: float
) -> Array[Dictionary]:
	var alerts: Array[Dictionary] = []
	if run_ended:
		return alerts

	if _damage_cooldown > 0.0:
		_damage_cooldown = maxf(0.0, _damage_cooldown - delta)

	var spd_thresh: float = cfg.speed_score_threshold_mps if cfg != null else 13.5
	var spd_rate: float = cfg.speed_score_rate if cfg != null else 2.8
	var mult_step: float = cfg.multiplier_step_seconds if cfg != null else 15.0
	var mult_max: float = cfg.multiplier_max if cfg != null else 3.0

	# Очки за высокую скорость и чистую езду по полотну.
	if on_road and speed_mps > spd_thresh:
		clean_streak_sec += delta
		multiplier = clampf(1.0 + floorf(clean_streak_sec / maxf(mult_step, 1.0)) * 0.5, 1.0, mult_max)
		_score_frac += (speed_mps - 10.0) * spd_rate * multiplier * delta
		if _score_frac >= 1.0:
			var whole: int = int(floor(_score_frac))
			score += whole
			_score_frac -= float(whole)
	elif not on_road and speed_mps > 12.0:
		clean_streak_sec = maxf(0.0, clean_streak_sec - delta * 2.0)
		multiplier = clampf(1.0 + floorf(clean_streak_sec / maxf(mult_step, 1.0)) * 0.5, 1.0, mult_max)

	# Бонусы за дистанцию.
	if max_along >= _next_milestone_m:
		var bonus: int = cfg.milestone_bonus_points if cfg != null else 300
		score += bonus
		alerts.append({
			"text": "РУБЕЖ %.0f М  •  +%d ОЧК." % [_next_milestone_m, bonus],
			"color": Color(0.35, 0.96, 0.62, 1.0),
		})
		var step_m: float = cfg.milestone_distance_m if cfg != null else 500.0
		_next_milestone_m += maxf(50.0, step_m)

	# Строгий урон от столкновений с отбойниками, деревьями и рельефом.
	var crash_dv: float = cfg.crash_min_dv_mps if cfg != null else 4.6
	if dv_horiz > crash_dv and _damage_cooldown <= 0.0:
		var c_scale: float = cfg.crash_damage_scale if cfg != null else 2.35
		var c_min: float = cfg.crash_damage_min if cfg != null else 6.0
		var c_max: float = cfg.crash_damage_max if cfg != null else 42.0
		var dmg: float = clampf((dv_horiz - (crash_dv - 0.6)) * c_scale, c_min, c_max)
		_apply_damage(dmg)
		crashes += 1
		alerts.append({
			"text": "СТОЛКНОВЕНИЕ  -%d HP" % roundi(dmg),
			"color": Color(1.0, 0.32, 0.22, 1.0),
		})

	return alerts


func on_traffic_event(ev: Dictionary) -> Dictionary:
	if run_ended:
		return {}
	var kind: String = String(ev.get("kind", ""))
	if kind == "overtake":
		overtakes += 1
		var base_ov: int = cfg.overtake_points if cfg != null else 250
		var pts: int = roundi(float(base_ov) * multiplier)
		score += pts
		return {
			"text": "ОБГОН +%d  (×%.1f)" % [pts, multiplier],
			"color": Color(0.32, 0.98, 0.60, 1.0),
		}
	elif kind == "near_miss":
		near_misses += 1
		var base_nm: int = cfg.near_miss_points if cfg != null else 150
		var pts_nm: int = roundi(float(base_nm) * multiplier)
		score += pts_nm
		return {
			"text": "ОПАСНЫЙ РАЗЪЕЗД +%d" % pts_nm,
			"color": Color(1.0, 0.80, 0.22, 1.0),
		}
	elif kind == "impact":
		if _damage_cooldown <= 0.0:
			var rel_spd: float = float(ev.get("rel_speed", 12.0))
			var t_scale: float = cfg.traffic_impact_scale if cfg != null else 1.45
			var t_min: float = cfg.traffic_impact_min if cfg != null else 8.0
			var t_max: float = cfg.traffic_impact_max if cfg != null else 46.0
			var dmg: float = clampf((rel_spd - 3.0) * t_scale, t_min, t_max)
			_apply_damage(dmg)
			crashes += 1
			return {
				"text": "УДАР О ТРАФИК  -%d HP" % roundi(dmg),
				"color": Color(1.0, 0.25, 0.18, 1.0),
			}
	return {}


func on_pedestrian_event(ev: Dictionary) -> Dictionary:
	if run_ended:
		return {}
	var kind: String = String(ev.get("kind", ""))
	if kind == "pedestrian_hit":
		ped_hits += 1
		var dmg: float = cfg.pedestrian_hit_damage if cfg != null else 35.0
		var pen: int = cfg.pedestrian_hit_penalty if cfg != null else 500
		_apply_damage(dmg)
		score = maxi(0, score - pen)
		return {
			"text": "СБИТ ПЕШЕХОД!  -%d HP  •  -%d ОЧК." % [roundi(dmg), pen],
			"color": Color(1.0, 0.16, 0.16, 1.0),
		}
	elif kind == "crosswalk_ahead":
		return {
			"text": "ВПЕРЕДИ ПЕШЕХОДНЫЙ ПЕРЕХОД",
			"color": Color(1.0, 0.78, 0.22, 1.0),
		}
	elif kind == "crosswalk_courtesy":
		var base_cw: int = cfg.crosswalk_courtesy_points if cfg != null else 150
		var pts: int = roundi(float(base_cw) * multiplier)
		score += pts
		return {
			"text": "ЧИСТЫЙ ПЕРЕХОД +%d" % pts,
			"color": Color(0.40, 0.94, 0.96, 1.0),
		}
	return {}


func on_rescue() -> Dictionary:
	if run_ended:
		return {}
	var dmg: float = cfg.rescue_damage if cfg != null else 12.0
	_apply_damage(dmg)
	return {
		"text": "ВОЗВРАТ НА ТРАССУ  -%d HP" % roundi(dmg),
		"color": Color(1.0, 0.56, 0.18, 1.0),
	}


func _apply_damage(amount: float) -> void:
	hp = maxf(0.0, hp - amount)
	clean_streak_sec = 0.0
	multiplier = 1.0
	_damage_cooldown = cfg.damage_cooldown_sec if cfg != null else 0.65
	if hp <= 0.0:
		hp = 0.0
		run_ended = true


# ------------------------------------------------ таблица рекордов по дистанции


static func _resolve_records_path(p_cfg: ArcadeSettingsType) -> String:
	if p_cfg != null and not p_cfg.records_path.is_empty():
		return p_cfg.records_path
	return RECORDS_PATH


static func load_leaderboard(p_cfg: ArcadeSettingsType = null) -> Array:
	var cfg_file := ConfigFile.new()
	if cfg_file.load(_resolve_records_path(p_cfg)) != OK:
		return []
	var raw: Variant = cfg_file.get_value("arcade", "leaderboard", [])
	if raw is Array:
		return (raw as Array).duplicate(true)
	return []


static func best_distance(p_cfg: ArcadeSettingsType = null) -> float:
	var entries: Array = load_leaderboard(p_cfg)
	if entries.is_empty():
		return 0.0
	return float((entries[0] as Dictionary).get("distance_m", 0.0))


static func record_run(entry: Dictionary, p_cfg: ArcadeSettingsType = null) -> Dictionary:
	var entries: Array = load_leaderboard(p_cfg)
	var limit: int = maxi(1, p_cfg.leaderboard_size) if p_cfg != null else MAX_LEADERBOARD
	var token: int = int(Time.get_ticks_usec())
	var tagged: Dictionary = entry.duplicate(true)
	tagged["_token"] = token
	entries.append(tagged)
	entries.sort_custom(func(a: Variant, b: Variant) -> bool:
		var da: float = float((a as Dictionary).get("distance_m", 0.0))
		var db: float = float((b as Dictionary).get("distance_m", 0.0))
		if absf(da - db) > 0.5:
			return da > db
		return int((a as Dictionary).get("score", 0)) > int((b as Dictionary).get("score", 0))
	)
	if entries.size() > limit:
		entries.resize(limit)
	var rank: int = -1
	for i in range(entries.size()):
		if int((entries[i] as Dictionary).get("_token", -1)) == token:
			rank = i + 1
			(entries[i] as Dictionary).erase("_token")
	var path: String = _resolve_records_path(p_cfg)
	var cfg_file := ConfigFile.new()
	cfg_file.load(path)
	cfg_file.set_value("arcade", "leaderboard", entries)
	cfg_file.save(path)
	return {
		"rank": rank,
		"is_record": rank == 1,
		"entries": entries,
	}
