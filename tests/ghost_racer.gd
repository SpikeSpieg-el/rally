# godot --headless --path . --script res://tests/ghost_racer.gd
## Контракты системы призрака и живой дельты HUD:
## сериализация RGHOST01, интерполяция, вдоль-трассовая дельта, клон каждой машины реестра,
## переключение голограмма/ливрея, скрытие в кабине и настройки паузы.
extends SceneTree

const GhostRecording = preload("res://scripts/ghost/ghost_recording.gd")
const GhostCarRig = preload("res://scripts/ghost/ghost_car_rig.gd")
const GhostLookScene = preload("res://scenes/effects/ghost_racer.tscn")
const GhostLookScript = preload("res://scripts/effects/rally_ghost_look.gd")
const HudScene = preload("res://scenes/ui/rally_hud.tscn")
const HudStyle = preload("res://scripts/data/rally_hud_style.gd")
const CarModels = preload("res://scripts/car_models.gd")

var _failures: int = 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: %s" % msg)
		_failures += 1


func _initialize() -> void:
	_run_section("запись и математика дельты", _test_recording_math_and_io)
	_run_section("пресеты внешности и настройки", _test_ghost_look_presets_and_preferences)
	_run_section("клонирование машин и ливрея", _test_ghost_car_rig_cloning_and_livery_toggle)
	_run_section("дельта-панель и пиксельный стиль", _test_delta_panel_cockpit_and_pixel_style)
	_run_section("сохранение настроек призрака", _test_ghost_settings_persistence)
	if _failures == 0:
		print("PASS: система призрака, клонирование машин, живая дельта HUD и настройки паузы")
	else:
		printerr("[ghost-racer] всего провалов: %d" % _failures)
	quit(0 if _failures == 0 else 1)


## Печатает число провалов до и после раздела: когда полный лог не прочесть,
## по этим строкам сразу видно, какой раздел сыплется.
func _run_section(title: String, body: Callable) -> void:
	var before := _failures
	body.call()
	print("[ghost-racer] %s: провалов +%d (всего %d)" % [title, _failures - before, _failures])


func _test_recording_math_and_io() -> void:
	var rec := GhostRecording.new()
	rec.record_key = "test_ghost_unit_key"
	rec.vehicle_id = "evo"
	rec.total_length = 200.0
	for i in range(11):
		var t: float = float(i) * 0.5
		var s: float = float(i) * 20.0
		var pos := Vector3(0.0, 0.0, s)
		var q := Quaternion(Vector3.UP, 0.0)
		rec.append_sample(t, s, pos, q, 25.0 + float(i), 0.1, 0.0, 0.1, 0.1, 0.1, 0.1)
	rec.finish_time = 5.0
	rec.set_checkpoint_time(0, 2.5)

	var mid: Dictionary = rec.sample_at_time(2.25)
	_check(bool(mid.get("valid", false)), "sample_at_time должен быть валиден в середине записи")
	_check(absf(Vector3(mid["pos"]).z - 90.0) < 1.5, "Catmull-Rom интерполяция позиции около 90 м")
	var at_100: Dictionary = rec.time_at_along(100.0)
	_check(bool(at_100.get("valid", false)) and absf(float(at_100["time"]) - 2.5) < 0.05, "time_at_along(100) == 2.5 с")

	# Отрицательная дельта = игрок БЫСТРЕЕ призрака.
	var fast_delta: Dictionary = rec.compute_delta(2.1, 100.0, 28.0)
	_check(bool(fast_delta.get("valid", false)), "compute_delta должен быть валиден")
	_check(float(fast_delta["delta_sec"]) < -0.35, "если игрок прошёл 100 м быстрее 2.5 с — delta < 0")
	_check(float(fast_delta["gap_meters"]) > 0.0, "если игрок быстрее — gap_meters > 0 (впереди)")

	# Положительная дельта = игрок МЕДЛЕННЕЕ призрака.
	var slow_delta: Dictionary = rec.compute_delta(3.0, 100.0, 22.0)
	_check(float(slow_delta["delta_sec"]) > 0.45, "если игрок медленнее — delta > 0")
	_check(float(slow_delta["gap_meters"]) < 0.0, "если игрок медленнее — gap_meters < 0 (позади)")

	# Проверка записи/чтения и удаления с диска.
	_check(rec.save_for_key(rec.record_key, rec.vehicle_id, true) == OK, "сохранение RGHOST01 в user://ghosts должно пройти")
	_check(GhostRecording.has_saved_ghost(rec.record_key, rec.vehicle_id, true), "has_saved_ghost должен видеть файл")
	var loaded := GhostRecording.load_for_key(rec.record_key, rec.vehicle_id, true)
	_check(loaded != null and loaded.sample_count() == 11, "загрузка RGHOST01 должна вернуть 11 кадров")
	_check(is_equal_approx(loaded.finish_time, 5.0), "finish_time сохраняется точно")
	_check(loaded.cp_times.size() == 1 and is_equal_approx(loaded.get_checkpoint_time(0), 2.5), "cp_times сохраняются")
	_check(GhostRecording.delete_ghost(rec.record_key, rec.vehicle_id, true), "удаление файла призрака должно пройти")
	_check(not GhostRecording.has_saved_ghost(rec.record_key, rec.vehicle_id, true), "после удаления has_saved_ghost == false")

	# Проверка target-pacer дельты.
	var tgt: Dictionary = GhostRecording.compute_target_delta(20.0, 100.0, 28.0, 0.0, 200.0, 50.0)
	_check(bool(tgt.get("valid", false)), "compute_target_delta должен работать на середине трассы")
	_check(float(tgt["delta_sec"]) < -4.5, "целевое время на 50% = 25 с, при 20 с дельта = -5 с")


func _test_ghost_look_presets_and_preferences() -> void:
	var g := GhostLookScene.instantiate() as GhostLookScript
	_check(g != null, "scenes/effects/ghost_racer.tscn должен инстанцироваться как RallyGhostLook")
	g.look = GhostLookScript.GhostLook.NEON_PACER
	_check(g.ghost_color.r > 0.8 and g.ghost_color.b < 0.4, "пресет NEON_PACER задаёт янтарно-неоновый цвет")
	g.look = GhostLookScript.GhostLook.TRANSPARENT_RIVAL
	_check(g.preserve_livery_texture and g.livery_tint_strength > 0.05, "пресет TRANSPARENT_RIVAL сохраняет текстуру ливреи")
	g.opacity = 0.61
	_check(g.look == GhostLookScript.GhostLook.CUSTOM, "ручная правка поля переводит look в CUSTOM")
	g.apply_user_preferences({"ghost_enabled": false, "delta_enabled": false, "opacity": 0.25, "reference_mode": 2})
	_check(not g.effective_enabled() and not g.effective_delta_enabled(), "user prefs отключают рендер призрака/дельту")
	_check(is_equal_approx(g.effective_opacity(), 0.25), "user prefs переопределяют прозрачность без порчи scene export")
	_check(is_equal_approx(g.opacity, 0.61), "scene @export opacity не мутирует от pause-настроек")
	g.clear_user_preferences()
	_check(is_equal_approx(g.effective_opacity(), 0.61), "clear_user_preferences возвращает экспорт сцены")
	g.free()


func _test_ghost_car_rig_cloning_and_livery_toggle() -> void:
	var g := GhostLookScene.instantiate() as GhostLookScript
	var stage_stub := Node3D.new()
	# Каждая машина реестра, включая ту, у которой нет ливрей: призрак обязан
	# собраться и покраситься в любом случае.
	root.add_child(stage_stub)
	for scene_path in CarModels.car_scene_paths():
		var rig := GhostCarRig.new()
		_check(rig.build_from_scene_path(scene_path), "GhostCarRig должен собраться из %s" % scene_path)
		_check(rig.get_child_count() > 0, "GhostCarRig должен склонировать кузов/колёса из %s" % scene_path)
		var has_collision: bool = false
		for node in rig.find_children("*", "", true, false):
			if node is CollisionObject3D or node is CollisionShape3D:
				has_collision = true
				_check(node.owner == null, "склонированные узлы призрака должны иметь owner == null")
		_check(not has_collision, "в призраке не должно быть коллизий")

		g.look = GhostLookScript.GhostLook.HOLOGRAM
		rig.apply_look_params(g._build_params_dict())
		g.look = GhostLookScript.GhostLook.TRANSPARENT_RIVAL
		rig.apply_look_params(g._build_params_dict())
		# Обновление позы читает global_transform: вне дерева оно возвращает
		# нулевую матрицу и печатает ошибку скрипта, поэтому риг на время
		# обновления висит на дереве, как в настоящем заезде.
		stage_stub.add_child(rig)
		rig.update_pose_and_fx(
			0.016,
			{"valid": true, "pos": Vector3.ZERO, "quat": Quaternion.IDENTITY, "speed_mps": 20.0, "steer": 0.15, "brake": 0.8},
			stage_stub,
			g._build_params_dict(),
			true
		)
		stage_stub.remove_child(rig)
		rig.free()
	root.remove_child(stage_stub)
	stage_stub.free()
	g.free()


func _test_delta_panel_cockpit_and_pixel_style() -> void:
	var hud := HudScene.instantiate()
	var delta_p := hud.get_node_or_null("DeltaPanel")
	_check(delta_p != null, "в RallyHUD должен присутствовать DeltaPanel")
	var style := HudStyle.load_default().duplicate() as HudStyle
	style.cockpit_hide_redundant_hud = true
	style.cockpit_hide_delta_panel = true
	hud.set_hud_style(style)
	hud.set_camera_mode(2)
	delta_p.call("update_live_delta", {"delta_active": true, "delta_sec": -0.75, "speed_delta_kmh": 8.0, "gap_meters": 12.0, "is_target": false})
	_check(delta_p.visible == false, "в 1-м лице при cockpit_hide_delta_panel=true DeltaPanel остаётся скрыт даже при живом обновлении")
	hud.set_camera_mode(0)
	delta_p.call("update_live_delta", {"delta_active": true, "delta_sec": -0.75, "speed_delta_kmh": 8.0, "gap_meters": 12.0, "is_target": false})
	_check(delta_p.visible == true, "в 3-м лице DeltaPanel снова становится видим")
	delta_p.call("flash_checkpoint", 0, -0.45)

	var mini := hud.get_node_or_null("MiniMap")
	_check(mini != null and mini.has_method("set_ghost"), "MiniMap должен поддерживать set_ghost()")
	mini.call("set_ghost", Vector2(10.0, 20.0), 0.3, true)
	mini.call("clear_ghost")
	hud.free()


func _test_ghost_settings_persistence() -> void:
	var hud := HudScene.instantiate()
	var opts := hud.get_node_or_null("PausePanel/Box/GhostOptions")
	_check(opts != null, "в RallyHUD должен быть PausePanel/Box/GhostOptions")
	var cfg_path := "user://test_rally_ghost_unit.cfg"
	opts.set("settings_path", cfg_path)
	var g := GhostLookScene.instantiate() as GhostLookScript
	var delta_p := hud.get_node_or_null("DeltaPanel")
	opts.call("initialize", g, delta_p)
	opts.get_node("TogglesRow/GhostEnabled").button_pressed = false
	_check(not g.effective_enabled(), "переключатель в паузе сразу обновляет RallyGhostLook")
	_check(FileAccess.file_exists(cfg_path), "настройки призрака сохраняются на диск")
	opts.call("_reset_to_scene_defaults")
	_check(g.effective_enabled(), "сброс восстанавливает дефолт сцены")
	if FileAccess.file_exists(cfg_path):
		DirAccess.remove_absolute(cfg_path)
	g.free()
	hud.free()
