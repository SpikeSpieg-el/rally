## Настройки и контроллер 3D-призрака и живой дельты времени.
##
## Живёт на узле `VisualEffects/Ghost` (`scenes/effects/ghost_racer.tscn`),
## поэтому инспектор и редактор сразу показывают все параметры вида, огней,
## затухания, светового следа, записи и расчёта дельты — без скрытых констант.
@tool
class_name RallyGhostLook
extends Node3D

signal settings_changed
signal ghost_state_changed

const GhostRecording = preload("res://scripts/ghost/ghost_recording.gd")
const GhostCarRig = preload("res://scripts/ghost/ghost_car_rig.gd")

enum GhostLook {
	CUSTOM = 0,
	OFF = 1,
	HOLOGRAM = 2,
	SILHOUETTE = 3,
	NEON_PACER = 4,
	TRANSPARENT_RIVAL = 5,
}

enum DeltaReferenceMode {
	AUTO_GHOST_OR_TARGET = 0,
	GHOST_ONLY = 1,
	TARGET_TIME_ONLY = 2,
}

@export_group("Профиль и предпросмотр")
## Готовый пресет внешнего вида призрака. Все ручки ниже остаются открытыми.
@export var look: GhostLook = GhostLook.HOLOGRAM:
	set(value):
		var changed: bool = value != look
		look = value
		if changed and value != GhostLook.CUSTOM and not _applying_preset:
			_apply_preset(value)
		_refresh()
## Главный выключатель 3D-призрака (не отключает запись и живую дельту, если те включены).
@export var enabled: bool = true:
	set(value):
		enabled = value
		_mark_custom()
		_refresh()
## Показать временную модель призрака прямо в 3D-вьюпорте редактора для подбора шейдера.
@export var preview_in_editor: bool = false:
	set(value):
		preview_in_editor = value
		_sync_editor_preview()
## Какую машину показывать в режиме предпросмотра редактора.
@export var preview_vehicle_id: String = "mitsubishi_evo":
	set(value):
		preview_vehicle_id = value
		if preview_in_editor:
			_sync_editor_preview(true)
@export_multiline var description: String = ""

@export_group("Запись и ориентир")
## Записывать заезд для сохранения призрака лучшего проезда.
@export var record_enabled: bool = true:
	set(value):
		record_enabled = value
		_refresh()
## Частота сэмплов траектории призрака (выше — точнее на кочках и в прыжках).
@export_range(5.0, 60.0, 1.0, "suffix:Гц") var record_hz: float = 20.0
## Перезаписывать файл призрака при побитии рекорда времени этапа.
@export var save_on_new_record: bool = true
## Если рекорд времени уже существовал без файла призрака, сохранить первый завершённый заезд.
@export var save_first_finish_if_missing: bool = true
## Хранить отдельного призрака для каждой модели машины вместо общего рекорда трассы.
@export var separate_by_vehicle: bool = false
## Строить 3D-призрака из модели и ливреи, на которой был поставлен рекорд.
@export var match_recorded_vehicle_model: bool = true
## Папка хранения файлов призраков (`.rghost`).
@export var ghost_directory: String = "user://ghosts"
## Кубическая Catmull-Rom интерполяция позы между сэмплами.
@export var smooth_interpolation: bool = true
## Прятать призрака на линии старта до нажатия газа.
@export var hide_before_start: bool = false
## Прятать призрака после того, как он пересёк финиш.
@export var hide_after_finish: bool = true
## Включить расчёт живой дельты времени.
@export var delta_enabled: bool = true
## Что брать ориентиром для живой дельты: призрак (с откатом на цель), только призрак или только цель.
@export var delta_reference_mode: DeltaReferenceMode = DeltaReferenceMode.AUTO_GHOST_OR_TARGET
## Если призрака ещё нет (или выбран режим цели), выпускать по осевой 3D-пейсера под целевое время.
@export var spawn_target_pacer_3d: bool = false
## Сглаживание скачков живой дельты, секунд (0 — без сглаживания).
@export_range(0.0, 0.5, 0.01, "suffix:с") var delta_smoothing_sec: float = 0.08
## Окно локального поиска километража вокруг прошлой позиции (защита от прыжка на шпильках).
@export_range(15.0, 150.0, 1.0, "suffix:м") var along_window_m: float = 55.0
## Порог отклонения, после которого включается глобальный поиск километража (например, после сброса по R).
@export_range(10.0, 100.0, 1.0, "suffix:м") var along_fallback_dist_m: float = 35.0

@export_group("Внешний вид призрака")
## Шейдер голограммы с Френелем/сканлайнами или полупрозрачная окраска реальной ливреи.
@export var render_mode: GhostCarRig.RenderMode = GhostCarRig.RenderMode.HOLOGRAM_SHADER:
	set(value):
		render_mode = value
		_mark_custom()
		_refresh()
## Основной цвет кузова и колёс призрака.
@export var ghost_color: Color = Color(0.22, 0.86, 1.0, 1.0):
	set(value):
		ghost_color = value
		_mark_custom()
		_refresh()
## Цвет контурного свечения Френеля по краям кузова.
@export var rim_color: Color = Color(0.70, 0.97, 1.0, 1.0):
	set(value):
		rim_color = value
		_mark_custom()
		_refresh()
## Общая непрозрачность призрака.
@export_range(0.05, 1.0, 0.01) var opacity: float = 0.42:
	set(value):
		opacity = value
		_mark_custom()
		_refresh()
## Множитель непрозрачности колёс относительно кузова.
@export_range(0.1, 1.5, 0.05) var wheel_opacity_scale: float = 0.85:
	set(value):
		wheel_opacity_scale = value
		_mark_custom()
		_refresh()
@export_range(0.5, 8.0, 0.1) var fresnel_power: float = 2.6:
	set(value):
		fresnel_power = value
		_mark_custom()
		_refresh()
@export_range(0.0, 4.0, 0.05) var rim_intensity: float = 1.65:
	set(value):
		rim_intensity = value
		_mark_custom()
		_refresh()
@export_range(0.0, 4.0, 0.05) var emission_strength: float = 1.15:
	set(value):
		emission_strength = value
		_mark_custom()
		_refresh()
@export_range(0.0, 1.0, 0.02) var scanline_strength: float = 0.18:
	set(value):
		scanline_strength = value
		_mark_custom()
		_refresh()
@export_range(4.0, 140.0, 1.0) var scanline_density: float = 42.0:
	set(value):
		scanline_density = value
		_mark_custom()
		_refresh()
@export_range(-15.0, 15.0, 0.5) var scanline_speed: float = 2.5:
	set(value):
		scanline_speed = value
		_mark_custom()
		_refresh()
@export_range(0.0, 8.0, 0.1) var pulse_speed: float = 2.0:
	set(value):
		pulse_speed = value
		_mark_custom()
		_refresh()
@export_range(0.0, 0.4, 0.01) var pulse_amount: float = 0.08:
	set(value):
		pulse_amount = value
		_mark_custom()
		_refresh()
@export_range(0.0, 1.0, 0.05) var shading_contrast: float = 0.45:
	set(value):
		shading_contrast = value
		_mark_custom()
		_refresh()
## Сохранять рисунок раллийной ливреи на кузове призрака.
@export var preserve_livery_texture: bool = true:
	set(value):
		preserve_livery_texture = value
		_mark_custom()
		_refresh()
@export_range(0.0, 1.0, 0.05) var livery_tint_strength: float = 0.45:
	set(value):
		livery_tint_strength = value
		_mark_custom()
		_refresh()
@export var show_wheels: bool = true:
	set(value):
		show_wheels = value
		_mark_custom()
		_refresh()
@export var animate_wheels: bool = true:
	set(value):
		animate_wheels = value
		_mark_custom()
		_refresh()

@export_group("Огни призрака")
@export var show_brake_lights: bool = true
@export var brake_light_color: Color = Color(1.0, 0.14, 0.08, 1.0)
@export_range(0.0, 4.0, 0.05) var brake_light_idle_energy: float = 0.35
@export_range(0.0, 8.0, 0.1) var brake_light_active_energy: float = 2.8
@export var show_headlights: bool = true
@export var headlights_night_only: bool = true
@export var headlight_color: Color = Color(0.70, 0.92, 1.0, 1.0)
@export_range(0.0, 10.0, 0.1) var headlight_energy: float = 2.6

@export_group("Затухание у машины игрока")
## Плавно приглушать призрака вплотную к игроку или камере, чтобы не перекрывать дорогу.
@export var near_fade_enabled: bool = true
@export_range(1.0, 25.0, 0.5, "suffix:м") var near_fade_start_m: float = 8.5
@export_range(0.2, 15.0, 0.2, "suffix:м") var near_fade_end_m: float = 2.2
@export_range(0.0, 1.0, 0.02) var near_min_opacity: float = 0.05
## Коэффициент дистанции затухания для видов с капота и из кабины.
@export_range(0.5, 3.0, 0.05) var cockpit_near_fade_scale: float = 1.35

@export_group("Световой след (Трейл)")
@export var trail_enabled: bool = true:
	set(value):
		trail_enabled = value
		_mark_custom()
		_refresh()
## Две полосы от задних фонарей вместо одной центральной.
@export var trail_dual_ribbons: bool = true:
	set(value):
		trail_dual_ribbons = value
		_mark_custom()
		_refresh()
@export_range(2.0, 60.0, 1.0, "suffix:м") var trail_length_m: float = 18.0:
	set(value):
		trail_length_m = value
		_mark_custom()
		_refresh()
@export_range(0.03, 1.5, 0.01, "suffix:м") var trail_ribbon_width: float = 0.14:
	set(value):
		trail_ribbon_width = value
		_mark_custom()
		_refresh()
@export_range(0.1, 1.5, 0.02, "suffix:м") var trail_dual_offset_x: float = 0.72:
	set(value):
		trail_dual_offset_x = value
		_mark_custom()
		_refresh()
@export_range(0.05, 1.8, 0.02, "suffix:м") var trail_height_offset: float = 0.48:
	set(value):
		trail_height_offset = value
		_mark_custom()
		_refresh()
@export var trail_color: Color = Color(0.24, 0.88, 1.0, 1.0):
	set(value):
		trail_color = value
		_mark_custom()
		_refresh()
@export_range(0.05, 1.0, 0.02) var trail_opacity: float = 0.55:
	set(value):
		trail_opacity = value
		_mark_custom()
		_refresh()
@export_range(0.0, 80.0, 1.0, "suffix:км/ч") var trail_min_speed_kmh: float = 20.0

@export_group("Тексты результатов и сплитов")
@export var result_delta_prefix: String = "ДЕЛЬТА К ПРИЗРАКУ  "
@export var result_ghost_saved_text: String = "ПРИЗРАК ЛУЧШЕГО ПРОЕЗДА ОБНОВЛЁН"
@export var result_sectors_format: String = "СЕКТОРА В ПЛЮСЕ: %d / %d"

var _applying_preset: bool = false
var _rig: GhostCarRig = null

var _stage_root: Node3D = null
var _network: RoadNetwork = null
var _car: Node3D = null
var _record_key: String = ""
var _vehicle_id: String = ""
var _start_along: float = 0.0
var _finish_along: float = 0.0
var _target_time: float = 0.0
var _is_night: bool = false
var _session_active: bool = false

var _loaded_ghost: GhostRecording = null
var _current_recording: GhostRecording = null
var _ghost_path: String = ""
var _player_along: float = 0.0
var _record_accum: float = 0.0
var _has_sample_zero: bool = false
var _smoothed_delta: float = 0.0
var _has_smoothed_delta: bool = false
var _user_prefs: Dictionary = {}


func _ready() -> void:
	if Engine.is_editor_hint():
		if preview_in_editor:
			_sync_editor_preview()
	_refresh()


func _validate_property(property: Dictionary) -> void:
	if property.name == "description":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY


func _mark_custom() -> void:
	if _applying_preset or not is_inside_tree():
		return
	if look == GhostLook.CUSTOM:
		return
	look = GhostLook.CUSTOM
	notify_property_list_changed()


func _apply_preset(preset_id: GhostLook) -> void:
	_applying_preset = true
	match preset_id:
		GhostLook.OFF:
			enabled = false
		GhostLook.HOLOGRAM:
			enabled = true
			render_mode = GhostCarRig.RenderMode.HOLOGRAM_SHADER
			ghost_color = Color(0.22, 0.86, 1.0, 1.0)
			rim_color = Color(0.70, 0.97, 1.0, 1.0)
			opacity = 0.42
			wheel_opacity_scale = 0.85
			fresnel_power = 2.6
			rim_intensity = 1.65
			emission_strength = 1.15
			scanline_strength = 0.18
			scanline_density = 42.0
			scanline_speed = 2.5
			pulse_speed = 2.0
			pulse_amount = 0.08
			shading_contrast = 0.45
			preserve_livery_texture = true
			livery_tint_strength = 0.35
			trail_enabled = true
			trail_dual_ribbons = true
			trail_color = Color(0.24, 0.88, 1.0, 1.0)
			trail_opacity = 0.55
		GhostLook.SILHOUETTE:
			enabled = true
			render_mode = GhostCarRig.RenderMode.HOLOGRAM_SHADER
			ghost_color = Color(0.86, 0.94, 1.0, 1.0)
			rim_color = Color(1.0, 1.0, 1.0, 1.0)
			opacity = 0.28
			wheel_opacity_scale = 0.75
			fresnel_power = 3.2
			rim_intensity = 1.15
			emission_strength = 0.65
			scanline_strength = 0.0
			pulse_speed = 0.0
			pulse_amount = 0.0
			shading_contrast = 0.55
			preserve_livery_texture = false
			trail_enabled = false
		GhostLook.NEON_PACER:
			enabled = true
			render_mode = GhostCarRig.RenderMode.HOLOGRAM_SHADER
			ghost_color = Color(0.18, 1.0, 0.58, 1.0)
			rim_color = Color(0.72, 1.0, 0.84, 1.0)
			opacity = 0.52
			wheel_opacity_scale = 0.95
			fresnel_power = 2.1
			rim_intensity = 2.2
			emission_strength = 1.65
			scanline_strength = 0.25
			scanline_density = 56.0
			scanline_speed = 4.0
			pulse_speed = 3.2
			pulse_amount = 0.12
			shading_contrast = 0.35
			preserve_livery_texture = false
			trail_enabled = true
			trail_dual_ribbons = true
			trail_color = Color(0.22, 1.0, 0.60, 1.0)
			trail_opacity = 0.72
		GhostLook.TRANSPARENT_RIVAL:
			enabled = true
			render_mode = GhostCarRig.RenderMode.TRANSPARENT_LIVERY
			ghost_color = Color(0.85, 0.94, 1.0, 1.0)
			rim_color = Color(1.0, 1.0, 1.0, 1.0)
			opacity = 0.58
			wheel_opacity_scale = 1.0
			emission_strength = 0.25
			preserve_livery_texture = true
			livery_tint_strength = 0.18
			trail_enabled = true
			trail_dual_ribbons = true
			trail_color = Color(1.0, 0.45, 0.12, 1.0)
			trail_opacity = 0.38
	_applying_preset = false


func _refresh() -> void:
	description = "Призрак лучшего проезда и живая дельта времени.\n"
	description += "Режим: %s • Запись: %.0f Гц • Прозрачность: %d%% • След: %s." % [
		"Голограмма" if render_mode == GhostCarRig.RenderMode.HOLOGRAM_SHADER else "Ливрея",
		record_hz,
		roundi(effective_opacity() * 100.0),
		"вкл" if effective_trail_enabled() else "выкл",
	]
	if _rig != null and is_instance_valid(_rig):
		_rig.apply_look_params(_build_params_dict())
	settings_changed.emit()


func _sync_editor_preview(force_rebuild: bool = false) -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if not preview_in_editor:
		if _rig != null and is_instance_valid(_rig):
			_rig.queue_free()
			_rig = null
		return
	if _rig == null or not is_instance_valid(_rig) or force_rebuild:
		if _rig != null and is_instance_valid(_rig):
			_rig.queue_free()
		_rig = GhostCarRig.new()
		_rig.name = "EditorPreviewGhost"
		add_child(_rig)
		# owner остаётся null, чтобы превью-меши не вшивались в .tscn при сохранении.
		_rig.build_for_vehicle(preview_vehicle_id, "res://scenes/rally_car.tscn")
	_rig.apply_look_params(_build_params_dict())
	_rig.set_near_fade(1.0)


func effective_enabled() -> bool:
	if _user_prefs.has("ghost_enabled"):
		return bool(_user_prefs["ghost_enabled"])
	return enabled


func effective_delta_enabled() -> bool:
	if _user_prefs.has("delta_enabled"):
		return bool(_user_prefs["delta_enabled"])
	return delta_enabled


func effective_trail_enabled() -> bool:
	if _user_prefs.has("trail_enabled"):
		return bool(_user_prefs["trail_enabled"])
	return trail_enabled


func effective_opacity() -> float:
	if _user_prefs.has("opacity"):
		return clampf(float(_user_prefs["opacity"]), 0.05, 1.0)
	return opacity


func effective_reference_mode() -> int:
	if _user_prefs.has("reference_mode"):
		return clampi(int(_user_prefs["reference_mode"]), 0, 2)
	return int(delta_reference_mode)


func apply_user_preferences(prefs: Dictionary) -> void:
	_user_prefs = prefs.duplicate()
	if _rig != null and is_instance_valid(_rig):
		_rig.apply_look_params(_build_params_dict())
		if not effective_enabled():
			_rig.visible = false
			_rig.reset_trail()
	settings_changed.emit()
	ghost_state_changed.emit()


func clear_user_preferences() -> void:
	_user_prefs.clear()
	apply_user_preferences({})


func has_loaded_ghost() -> bool:
	return _loaded_ghost != null and _loaded_ghost.is_valid()


func loaded_ghost_time() -> float:
	return _loaded_ghost.finish_time if has_loaded_ghost() else 0.0


func current_ghost_path() -> String:
	return _ghost_path


## Запустить сессию призрака для заезда RallyStage.
func begin_session(
	stage_root: Node3D,
	road_net: RoadNetwork,
	rec_key: String,
	car_node: Node3D,
	veh_id: String,
	start_d: float,
	finish_d: float,
	stage_target_time: float,
	night_flag: bool
) -> void:
	end_session()
	_stage_root = stage_root
	_network = road_net
	_car = car_node
	_record_key = rec_key
	_vehicle_id = veh_id
	_start_along = start_d
	_finish_along = maxf(start_d + 1.0, finish_d)
	_target_time = stage_target_time
	_is_night = night_flag
	_player_along = start_d
	_record_accum = 0.0
	_has_sample_zero = false
	_smoothed_delta = 0.0
	_has_smoothed_delta = false
	_session_active = true

	_ghost_path = GhostRecording.storage_path_for(
		_record_key, _vehicle_id, separate_by_vehicle, ghost_directory
	)
	_loaded_ghost = GhostRecording.load_from_file(_ghost_path)

	_current_recording = GhostRecording.new()
	_current_recording.record_key = _record_key
	_current_recording.vehicle_id = _vehicle_id
	_current_recording.total_length = _network.total_length if _network != null else 0.0
	_fill_car_setup_meta(_current_recording, car_node)

	_rebuild_runtime_rig()
	ghost_state_changed.emit()


func end_session() -> void:
	_session_active = false
	if _rig != null and is_instance_valid(_rig):
		if _rig.get_parent() == self:
			remove_child(_rig)
		_rig.queue_free()
		_rig = null
	_loaded_ghost = null
	_current_recording = null


func delete_current_ghost() -> bool:
	var deleted: bool = GhostRecording.delete_file(_ghost_path)
	_loaded_ghost = null
	_has_smoothed_delta = false
	if _rig != null and is_instance_valid(_rig):
		_rig.reset_trail()
		_rig.visible = false
	_rebuild_runtime_rig()
	ghost_state_changed.emit()
	return deleted


func _rebuild_runtime_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		if _rig.get_parent() == self:
			remove_child(_rig)
		_rig.queue_free()
		_rig = null
	if Engine.is_editor_hint():
		return
	var use_ghost: bool = has_loaded_ghost() and effective_reference_mode() != DeltaReferenceMode.TARGET_TIME_ONLY
	var use_pacer: bool = not use_ghost and spawn_target_pacer_3d and _target_time > 0.05 and _network != null
	if not use_ghost and not use_pacer:
		return

	_rig = GhostCarRig.new()
	_rig.name = "GhostCarRig"
	add_child(_rig)

	var fallback_scene: String = _car.scene_file_path if _car != null else "res://scenes/rally_car.tscn"
	var rig_vehicle: String = _vehicle_id
	var rig_livery: int = 0
	var rig_paint := Color(1.0, 1.0, 1.0, 1.0)
	if use_ghost and match_recorded_vehicle_model and _loaded_ghost != null:
		if not _loaded_ghost.vehicle_id.is_empty():
			rig_vehicle = _loaded_ghost.vehicle_id
		rig_livery = _loaded_ghost.livery_index
		rig_paint = _loaded_ghost.paint_color
	_rig.build_for_vehicle(rig_vehicle, fallback_scene, rig_livery, rig_paint)
	_rig.apply_look_params(_build_params_dict())
	_rig.visible = false


func _fill_car_setup_meta(rec: GhostRecording, car_node: Node3D) -> void:
	if car_node == null:
		return
	var setup_var: Variant = car_node.get("active_setup")
	if setup_var is Resource:
		var setup_res: Resource = setup_var as Resource
		var sid: Variant = setup_res.get("id")
		if sid != null:
			rec.setup_id = String(sid)
		var liv: Variant = setup_res.get("livery")
		if liv == null:
			liv = setup_res.get("livery_index")
		if liv != null:
			rec.livery_index = int(liv)
		var p_col: Variant = setup_res.get("body_color")
		if p_col is Color:
			rec.paint_color = p_col as Color


func update_runtime(delta: float, stage_time: float, timer_running: bool, stage_finished: bool) -> Dictionary:
	var result: Dictionary = {
		"delta_active": false,
		"delta_sec": 0.0,
		"raw_delta_sec": 0.0,
		"gap_meters": 0.0,
		"speed_delta_kmh": 0.0,
		"is_target": false,
		"ghost_map_active": false,
		"ghost_pos_xz": Vector2.ZERO,
		"ghost_heading": 0.0,
	}
	if not _session_active or _stage_root == null or _car == null:
		return result

	var local_car_pos: Vector3 = _stage_root.to_local(_car.global_position)
	if _network != null:
		_player_along = GhostRecording.along_near(
			_network,
			local_car_pos.x,
			local_car_pos.z,
			_player_along,
			along_window_m,
			along_fallback_dist_m
		)

	# 1. Запись текущего заезда.
	if record_enabled and timer_running and not stage_finished and _current_recording != null:
		if not _has_sample_zero:
			_has_sample_zero = true
			_record_car_sample(0.0)
			_record_accum = 0.0
		_record_accum += delta
		var interval: float = 1.0 / clampf(record_hz, 5.0, 60.0)
		if _record_accum >= interval:
			_record_accum = fmod(_record_accum, interval)
			_record_car_sample(stage_time)

	# 2. Обновление 3D-призрака (или целевого 3D-пейсера).
	var ref_mode: int = effective_reference_mode()
	var ghost_ready: bool = has_loaded_ghost() and ref_mode != DeltaReferenceMode.TARGET_TIME_ONLY
	var use_target_pacer: bool = not ghost_ready and ref_mode != DeltaReferenceMode.GHOST_ONLY and spawn_target_pacer_3d and _target_time > 0.05 and _network != null
	var rig_shown: bool = false

	if _rig != null and is_instance_valid(_rig):
		if not effective_enabled() or (hide_before_start and not timer_running and not stage_finished):
			_rig.visible = false
			_rig.reset_trail()
		elif ghost_ready:
			var sample: Dictionary = _loaded_ghost.sample_at_time(stage_time, smooth_interpolation)
			var is_done: bool = bool(sample.get("finished", false))
			if hide_after_finish and is_done:
				_rig.visible = false
				_rig.reset_trail()
			elif bool(sample.get("valid", false)):
				_rig.visible = true
				_update_rig_near_fade(sample["pos"] as Vector3)
				_rig.update_pose_and_fx(delta, sample, _stage_root, _build_params_dict(), _is_night)
				rig_shown = _rig.visible
				var fwd: Vector3 = _rig.global_transform.basis.z
				result["ghost_map_active"] = true
				result["ghost_pos_xz"] = Vector2(_rig.global_position.x, _rig.global_position.z)
				result["ghost_heading"] = atan2(-fwd.x, -fwd.z)
		elif use_target_pacer:
			var pacer_sample: Dictionary = _build_target_pacer_sample(stage_time)
			var pacer_done: bool = bool(pacer_sample.get("finished", false))
			if hide_after_finish and pacer_done:
				_rig.visible = false
				_rig.reset_trail()
			elif bool(pacer_sample.get("valid", false)):
				_rig.visible = true
				_update_rig_near_fade(pacer_sample["pos"] as Vector3)
				_rig.update_pose_and_fx(delta, pacer_sample, _stage_root, _build_params_dict(), _is_night)
				rig_shown = _rig.visible
				var pfwd: Vector3 = _rig.global_transform.basis.z
				result["ghost_map_active"] = true
				result["ghost_pos_xz"] = Vector2(_rig.global_position.x, _rig.global_position.z)
				result["ghost_heading"] = atan2(-pfwd.x, -pfwd.z)
		else:
			_rig.visible = false
			_rig.reset_trail()

	# Если 3D-призрак выключен пользователем, карта всё равно может показать точку.
	if not rig_shown and ghost_ready and _loaded_ghost != null and (timer_running or not hide_before_start):
		var map_s: Dictionary = _loaded_ghost.sample_at_time(stage_time, false)
		if bool(map_s.get("valid", false)) and not (hide_after_finish and bool(map_s.get("finished", false))):
			var world_p: Vector3 = _stage_root.to_global(map_s["pos"] as Vector3)
			var q: Quaternion = map_s["quat"] as Quaternion
			var fwd_m: Vector3 = (_stage_root.global_transform.basis * Basis(q)).z
			result["ghost_map_active"] = true
			result["ghost_pos_xz"] = Vector2(world_p.x, world_p.z)
			result["ghost_heading"] = atan2(-fwd_m.x, -fwd_m.z)

	# 3. Расчёт живой дельты времени.
	if effective_delta_enabled() and _network != null:
		var player_spd_mps: float = float(_car.get("speed_mps")) if _car.get("speed_mps") != null else 0.0
		var delta_info: Dictionary = {"valid": false}
		if ghost_ready and ref_mode != DeltaReferenceMode.TARGET_TIME_ONLY:
			delta_info = _loaded_ghost.compute_delta(stage_time, _player_along, player_spd_mps)
		elif ref_mode != DeltaReferenceMode.GHOST_ONLY and _target_time > 0.05:
			delta_info = GhostRecording.compute_target_delta(
				stage_time, _player_along, player_spd_mps, _start_along, _finish_along, _target_time
			)

		if bool(delta_info.get("valid", false)):
			var raw_d: float = float(delta_info["delta_sec"])
			if not timer_running and not stage_finished:
				raw_d = 0.0
				_smoothed_delta = 0.0
				_has_smoothed_delta = true
			elif delta_smoothing_sec > 0.001 and _has_smoothed_delta:
				var w: float = 1.0 - exp(-delta / delta_smoothing_sec)
				_smoothed_delta = lerpf(_smoothed_delta, raw_d, w)
			else:
				_smoothed_delta = raw_d
				_has_smoothed_delta = true
			result["delta_active"] = true
			result["delta_sec"] = _smoothed_delta
			result["raw_delta_sec"] = raw_d
			result["gap_meters"] = float(delta_info["gap_meters"])
			result["speed_delta_kmh"] = float(delta_info["speed_delta_kmh"])
			result["is_target"] = bool(delta_info["is_target"])

	return result


func _record_car_sample(t: float) -> void:
	if _current_recording == null or _car == null or _stage_root == null:
		return
	var rel_xform: Transform3D = _stage_root.global_transform.affine_inverse() * _car.global_transform
	var speed_mps: float = float(_car.get("speed_mps")) if _car.get("speed_mps") != null else 0.0
	var steer_rad: float = 0.0
	var fl := _car.get_node_or_null("Wheel_FL") as Node3D
	if fl != null:
		steer_rad = fl.rotation.y
	var br_amt: float = float(_car.get("brake_amount")) if _car.get("brake_amount") != null else 0.0
	var hb_amt: float = float(_car.get("handbrake_input")) if _car.get("handbrake_input") != null else 0.0
	var brake_val: float = maxf(br_amt, hb_amt)
	var wy_fl: float = _wheel_visual_y("Wheel_FL")
	var wy_fr: float = _wheel_visual_y("Wheel_FR")
	var wy_rl: float = _wheel_visual_y("Wheel_RL")
	var wy_rr: float = _wheel_visual_y("Wheel_RR")
	_current_recording.append_sample(
		t,
		_player_along,
		rel_xform.origin,
		rel_xform.basis.orthonormalized().get_rotation_quaternion(),
		speed_mps,
		steer_rad,
		brake_val,
		wy_fl,
		wy_fr,
		wy_rl,
		wy_rr
	)


func _wheel_visual_y(wheel_name: String) -> float:
	if _car == null:
		return 0.0
	var w := _car.get_node_or_null(wheel_name)
	if w == null:
		return 0.0
	var vis := w.get_node_or_null("WheelVisual") as Node3D
	return vis.position.y if vis != null else 0.0


func _update_rig_near_fade(sample_local_pos: Vector3) -> void:
	if _rig == null or _stage_root == null or _car == null:
		return
	if not near_fade_enabled:
		_rig.set_near_fade(1.0)
		return
	var ghost_world: Vector3 = _stage_root.to_global(sample_local_pos)
	var dist: float = ghost_world.distance_to(_car.global_position)
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam != null:
		dist = minf(dist, ghost_world.distance_to(cam.global_position))
	var cam_mode: int = int(_car.get("camera_mode")) if _car.get("camera_mode") != null else 0
	var scale_mult: float = cockpit_near_fade_scale if cam_mode >= 1 else 1.0
	var fade_start: float = near_fade_start_m * scale_mult
	var fade_end: float = near_fade_end_m * scale_mult
	if fade_start <= fade_end:
		fade_start = fade_end + 0.5
	var frac: float = clampf((dist - fade_end) / (fade_start - fade_end), 0.0, 1.0)
	var alpha_mult: float = lerpf(near_min_opacity, 1.0, smoothstep(0.0, 1.0, frac))
	_rig.set_near_fade(alpha_mult)
	if alpha_mult <= 0.004:
		_rig.visible = false


func _build_target_pacer_sample(stage_time: float) -> Dictionary:
	if _network == null or _target_time <= 0.05:
		return {"valid": false}
	var frac: float = clampf(stage_time / _target_time, 0.0, 1.0)
	var along_d: float = lerpf(_start_along, _finish_along, frac)
	var pt: Vector3 = _network.point_at(along_d)
	var dir: Vector3 = _network.direction_at(along_d)
	var car_h: float = 0.0
	if _car != null and _car.has_method("get_spawn_height_offset"):
		car_h = float(_car.call("get_spawn_height_offset"))
	var ground_y: float = pt.y
	if _stage_root != null and _stage_root.has_method("height_at"):
		ground_y = float(_stage_root.call("height_at", pt.x, pt.z))
	var p_pos := Vector3(pt.x, ground_y + car_h, pt.z)
	var p_quat := Basis(Vector3.UP, atan2(dir.x, dir.z)).get_rotation_quaternion()
	var spd: float = maxf(0.0, (_finish_along - _start_along) / _target_time)
	return {
		"valid": true,
		"pos": p_pos,
		"quat": p_quat,
		"along": along_d,
		"speed_mps": spd,
		"steer": 0.0,
		"brake": 0.0,
		"wy_fl": 0.0,
		"wy_fr": 0.0,
		"wy_rl": 0.0,
		"wy_rr": 0.0,
		"finished": stage_time >= _target_time,
	}


func record_checkpoint(cp_index: int, cp_time: float) -> Dictionary:
	if _current_recording != null:
		_current_recording.set_checkpoint_time(cp_index, cp_time)
	var out: Dictionary = {"has_delta": false, "delta_sec": 0.0, "ref_cp_time": 0.0}
	if has_loaded_ghost() and effective_reference_mode() != DeltaReferenceMode.TARGET_TIME_ONLY:
		var g_cp: float = _loaded_ghost.get_checkpoint_time(cp_index)
		if g_cp > 0.0:
			out["has_delta"] = true
			out["ref_cp_time"] = g_cp
			out["delta_sec"] = cp_time - g_cp
	return out


func finish_session(final_time: float, is_new_record: bool) -> Dictionary:
	var summary: Dictionary = {
		"ghost_saved": false,
		"has_prev_ghost": has_loaded_ghost(),
		"prev_ghost_time": loaded_ghost_time(),
		"delta_vs_ghost": 0.0,
		"sectors_ahead": 0,
		"sectors_total": 0,
	}
	if not _session_active:
		return summary
	if has_loaded_ghost():
		summary["delta_vs_ghost"] = final_time - _loaded_ghost.finish_time
		if _current_recording != null:
			var cp_total: int = mini(_current_recording.cp_times.size(), _loaded_ghost.cp_times.size())
			var ahead_cnt: int = 0
			var valid_cps: int = 0
			for i in range(cp_total):
				var cur_cp: float = _current_recording.cp_times[i]
				var ref_cp: float = _loaded_ghost.cp_times[i]
				if cur_cp > 0.0 and ref_cp > 0.0:
					valid_cps += 1
					if cur_cp < ref_cp:
						ahead_cnt += 1
			summary["sectors_ahead"] = ahead_cnt
			summary["sectors_total"] = valid_cps

	if record_enabled and _current_recording != null and final_time > 0.0:
		_record_car_sample(final_time)
		_current_recording.finish_time = final_time
		var should_save: bool = false
		if not has_loaded_ghost() and save_first_finish_if_missing:
			should_save = true
		elif save_on_new_record:
			if not has_loaded_ghost() or final_time < _loaded_ghost.finish_time or is_new_record:
				should_save = true
		if should_save and _current_recording.is_valid():
			if _current_recording.save_to_file(_ghost_path) == OK:
				summary["ghost_saved"] = true
				_loaded_ghost = _current_recording
				ghost_state_changed.emit()

	summary["summary_line"] = format_finish_summary(summary)
	return summary


func format_finish_summary(summary: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	if bool(summary.get("has_prev_ghost", false)):
		var d_val: float = float(summary.get("delta_vs_ghost", 0.0))
		var sign_txt: String = "+" if d_val > 0.0005 else ("-" if d_val < -0.0005 else "±")
		lines.append("%s%s%.3f с" % [result_delta_prefix, sign_txt, absf(d_val)])
	var sec_total: int = int(summary.get("sectors_total", 0))
	if sec_total > 0:
		lines.append(result_sectors_format % [int(summary.get("sectors_ahead", 0)), sec_total])
	if bool(summary.get("ghost_saved", false)) and not result_ghost_saved_text.is_empty():
		lines.append(result_ghost_saved_text)
	return "\n".join(lines)


func _build_params_dict() -> Dictionary:
	return {
		"render_mode": int(render_mode),
		"ghost_color": ghost_color,
		"rim_color": rim_color,
		"opacity": effective_opacity(),
		"wheel_opacity_scale": wheel_opacity_scale,
		"fresnel_power": fresnel_power,
		"rim_intensity": rim_intensity,
		"emission_strength": emission_strength,
		"scanline_strength": scanline_strength,
		"scanline_density": scanline_density,
		"scanline_speed": scanline_speed,
		"pulse_speed": pulse_speed,
		"pulse_amount": pulse_amount,
		"shading_contrast": shading_contrast,
		"preserve_livery_texture": preserve_livery_texture,
		"livery_tint_strength": livery_tint_strength,
		"show_wheels": show_wheels,
		"animate_wheels": animate_wheels,
		"show_brake_lights": show_brake_lights,
		"brake_light_color": brake_light_color,
		"brake_light_idle_energy": brake_light_idle_energy,
		"brake_light_active_energy": brake_light_active_energy,
		"show_headlights": show_headlights,
		"headlights_night_only": headlights_night_only,
		"headlight_color": headlight_color,
		"headlight_energy": headlight_energy,
		"trail_enabled": effective_trail_enabled(),
		"trail_dual_ribbons": trail_dual_ribbons,
		"trail_length_m": trail_length_m,
		"trail_ribbon_width": trail_ribbon_width,
		"trail_dual_offset_x": trail_dual_offset_x,
		"trail_height_offset": trail_height_offset,
		"trail_color": trail_color,
		"trail_opacity": trail_opacity,
		"trail_min_speed_kmh": trail_min_speed_kmh,
	}
