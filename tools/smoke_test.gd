## Голосовой smoke-тест трасс: для каждой трассы генерирует сцену,
## ставит простого бота-пилота (результат важен как проверка, не как рекорд)
## и прогоняет заезд. Запуск:
##   godot --headless --path <проект> --script res://tools/smoke_test.gd
##
## На выходе: количество точек маршрута, КПП, длина, сработал ли финиш,
## средняя скорость. Ошибки движка видны в логах (stderr).
extends SceneTree

const StageScene := preload("res://scenes/rally_stage.tscn")

var _stage: Node3D = null
var _frames: int = 0
var _track_index: int = 0
var _max_frames: int = 6000
var _finished: bool = false
var _report: Array = []


var _inited := false


func _init() -> void:
	randomize()
	print("SMOKE: Godot %s | mode=headless-route-smoke" % Engine.get_version_info().get("version"))


func _game() -> Node:
	return root.get_node_or_null("RallyGame")


func _press(keycode: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	event.location = 0
	Input.parse_input_event(event)


func _release(keycode: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = false
	event.location = 0
	Input.parse_input_event(event)


func _load_track(index: int) -> void:
	_track_index = index
	var game: Node = _game()
	if game == null:
		quit(2)
		return
	game.call("select_track", index)
	game.call("prepare_race_seed")
	if _stage != null:
		_stage.free()
		_stage = null
	_stage = StageScene.instantiate()
	root.add_child(_stage)
	_frames = 0
	_finished = false
	_max_frames = int(_stage.track.target_time * 1.3 * 60.0)
	_press(KEY_W)  # throttle
	print("SMOKE: трасса %d загружена: points=%d cps=%d len=%.0f" % [
		index + 1, _stage.route_points.size(), _stage.checkpoints.size(), _stage.track.length
	])
	# Проверка направления спавна: forward·tangent > 0.
	var car = _stage.car
	if car != null:
		var fwd: Vector3 = car.global_transform.basis.z
		var tgt := Vector3(_stage.route_tangents[0].x, 0.0, _stage.route_tangents[0].y)
		print("SMOKE: spawn forward·tangent = %.3f" % fwd.dot(tgt))


func _process(delta: float) -> bool:
	if not _inited:
		_inited = true
		for n in root.get_children():
			printerr("SMOKE: root child: %s (%s)" % [n.name, n.get_class()])
		var game := _game()
		if game == null:
			printerr("SMOKE: автозагрузка RallyGame не найдена")
			quit(2)
			return false
		_load_track(0)
	_frames += 1
	_drive(delta)
	if _stage.stage_finished:
		_finished = true
		_report_track()
		_load_next()
		return false
	if _frames >= _max_frames:
		_report_track()
		_load_next()
		return false
	return false


var _stuck_time: float = 0.0


func _drive(delta: float) -> void:
	var car = _stage.car
	if car == null:
		return
	_respawn_if_needed(car, delta)
	if _frames % 600 == 0:
		var lp: Vector2 = _stage._route_lookup(car.global_position.x, car.global_position.z)
		var dfin: float = Vector2(car.global_position.x - _stage.finish_pos.x, car.global_position.z - _stage.finish_pos.y).length()
		printerr("SMOKE: dist=%.0fm dfin=%.1fm v=%.1fms" % [lp.y, dfin, car.speed_mps])
	# Пилот: смотрит на точку маршрута впереди, тормозит на крутых поворотах.
	var lookup: Vector2 = _stage._route_lookup(car.global_position.x, car.global_position.z)
	var idx: int = clampi(int(lookup.y / 0.5), 0, _stage.route_points.size() - 1)
	var lookahead: int = clampi(int(car.speed_mps * 0.9), 10, 60)
	var target_index: int = mini(_stage.route_points.size() - 1, idx + lookahead)
	var target := Vector3(_stage.route_points[target_index].x, 0.0, _stage.route_points[target_index].y)
	var to_target: Vector3 = target - car.global_position
	to_target.y = 0.0
	if to_target.length() < 0.5:
		return
	var forward: Vector3 = car.global_transform.basis.z
	var angle: float = atan2(forward.x * to_target.z - forward.z * to_target.x, forward.dot(to_target))
	# Сбросить все клавиши — иначе нажатия «залипают» и складываются.
	_release(KEY_W)
	_release(KEY_S)
	_release(KEY_A)
	_release(KEY_D)
	if absf(angle) > 0.45:
		_press(KEY_S)
	else:
		_press(KEY_W)
	if angle > 0.08:
		_press(KEY_A)
	if angle < -0.08:
		_press(KEY_D)


func _respawn_if_needed(car: Node, delta: float) -> void:
	if car.global_transform.basis.y.y < -0.4:
		_respawn_car(car)
		return
	var dt := delta
	if car.speed_mps < 2.0:
		_stuck_time += dt
	else:
		_stuck_time = 0.0
	if _stuck_time > 3.0:
		_respawn_car(car)


func _respawn_car(car: Node) -> void:
	_stuck_time = 0.0
	var lp: Vector2 = _stage._route_lookup(car.global_position.x, car.global_position.z)
	# Цель рестарта: чуть перед следующей непройденной КПП (если она скоро),
	# иначе — на 12 м вперёд по маршруту.
	var next_cp_dist: float = 1.0e30
	for i in range(_stage.checkpoints.size()):
		if not _stage.cp_triggered[i]:
			next_cp_dist = mini(next_cp_dist, float(_stage.checkpoints[i]["idx"]) * 0.5)
	var target_dist: float = mini(next_cp_dist - 10.0, lp.y + 12.0) if next_cp_dist < 1.0e29 else lp.y + 12.0
	var idx: int = clampi(int(target_dist / 0.5), 0, _stage.route_points.size() - 2)
	var pos: Vector2 = _stage.route_points[idx]
	var tang: Vector2 = _stage.route_tangents[idx]
	var yaw := atan2(tang.x, tang.y)
	var t := Transform3D().rotated(Vector3(0.0, 1.0, 0.0), yaw)
	t.origin = Vector3(pos.x, _stage._terrain_height(pos.x, pos.y), pos.y)
	# Полный сброс состояния Vehicle через собственный рестарт машины.
	car.set("spawn_transform", t)
	car.call("reset_to_spawn")
	printerr("SMOKE: рестарт на %.0f м по маршруту" % lp.y)


func _report_track() -> void:
	var car = _stage.car
	var avg_speed: float = 0.0
	if car != null and _stage.stage_time > 0.0:
		avg_speed = float(_stage.route_points.size()) * 0.5 / _stage.stage_time
	print("SMOKE: трасса %d | финиш=%s время=%.1fс ср.скорость=%.1f м/с КПП=%d" % [
		_track_index + 1,
		str(_finished),
		_stage.stage_time,
		avg_speed,
		_stage.checkpoints.size()
	])
	_report.append(_finished)


func _load_next() -> void:
	if _track_index + 1 < 7:
		call_deferred("_load_track", _track_index + 1)
	else:
		var ok: int = 0
		for finished in _report:
			if finished:
				ok += 1
		print("SMOKE: итог — финишировали %d из 7 трасс" % ok)
		print("SMOKE: ГОТОВО")
		quit(0)
