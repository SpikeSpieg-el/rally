## Настройки призрака и живой дельты в меню паузы.
##
## Все тексты, пути и файл сохранения вынесены в инспектор; сами строки
## интерфейса живут прямо в сцене `scenes/ui/rally_hud.tscn` (`PausePanel/Box/GhostOptions`).
extends VBoxContainer

const GhostLookType = preload("res://scripts/effects/rally_ghost_look.gd")
const SETTINGS_PATH := "user://rally_ghost.cfg"

@export var settings_path: String = SETTINGS_PATH
@export_group("Тексты списка ориентиров")
@export var mode_auto_text: String = "АВТО (ПРИЗРАК → ЦЕЛЬ)"
@export var mode_ghost_text: String = "ТОЛЬКО ПРИЗРАК"
@export var mode_target_text: String = "ТОЛЬКО ЦЕЛЕВОЕ ВРЕМЯ"
@export var delete_ready_text: String = "УДАЛИТЬ ПРИЗРАКА"
@export var delete_empty_text: String = "НЕТ ПРИЗРАКА"

var _ghost_look: GhostLookType = null
var _delta_widget: Control = null
var _defaults: Dictionary = {}
var _loading: bool = false

var _ghost_check: CheckBox = null
var _delta_check: CheckBox = null
var _trail_check: CheckBox = null
var _opacity_slider: HSlider = null
var _opacity_label: Label = null
var _mode_option: OptionButton = null
var _reset_btn: Button = null
var _delete_btn: Button = null


func _ready() -> void:
	_cache_nodes()
	_populate_modes()
	_connect_signals()


func _cache_nodes() -> void:
	_ghost_check = get_node_or_null("TogglesRow/GhostEnabled") as CheckBox
	_delta_check = get_node_or_null("TogglesRow/DeltaEnabled") as CheckBox
	_trail_check = get_node_or_null("TogglesRow/TrailEnabled") as CheckBox
	_opacity_slider = get_node_or_null("OpacityRow/Slider") as HSlider
	_opacity_label = get_node_or_null("OpacityRow/Value") as Label
	_mode_option = get_node_or_null("ModeRow/ModeOption") as OptionButton
	_reset_btn = get_node_or_null("ActionsRow/ResetButton") as Button
	_delete_btn = get_node_or_null("ActionsRow/DeleteButton") as Button


func _populate_modes() -> void:
	if _mode_option == null:
		return
	_mode_option.clear()
	_mode_option.add_item(mode_auto_text, 0)
	_mode_option.add_item(mode_ghost_text, 1)
	_mode_option.add_item(mode_target_text, 2)


func _connect_signals() -> void:
	if _ghost_check != null and not _ghost_check.toggled.is_connected(_on_toggled):
		_ghost_check.toggled.connect(_on_toggled)
	if _delta_check != null and not _delta_check.toggled.is_connected(_on_toggled):
		_delta_check.toggled.connect(_on_toggled)
	if _trail_check != null and not _trail_check.toggled.is_connected(_on_toggled):
		_trail_check.toggled.connect(_on_toggled)
	if _opacity_slider != null and not _opacity_slider.value_changed.is_connected(_on_opacity_changed):
		_opacity_slider.value_changed.connect(_on_opacity_changed)
	if _mode_option != null and not _mode_option.item_selected.is_connected(_on_mode_selected):
		_mode_option.item_selected.connect(_on_mode_selected)
	if _reset_btn != null and not _reset_btn.pressed.is_connected(_reset_to_scene_defaults):
		_reset_btn.pressed.connect(_reset_to_scene_defaults)
	if _delete_btn != null and not _delete_btn.pressed.is_connected(_on_delete_pressed):
		_delete_btn.pressed.connect(_on_delete_pressed)


func initialize(target_ghost: GhostLookType, target_delta: Control = null) -> void:
	_cache_nodes()
	_populate_modes()
	_connect_signals()
	if _ghost_look != null and is_instance_valid(_ghost_look):
		if _ghost_look.ghost_state_changed.is_connected(_refresh_delete_button):
			_ghost_look.ghost_state_changed.disconnect(_refresh_delete_button)
	_ghost_look = target_ghost
	_delta_widget = target_delta
	if _ghost_look == null:
		return
	if not _ghost_look.ghost_state_changed.is_connected(_refresh_delete_button):
		_ghost_look.ghost_state_changed.connect(_refresh_delete_button)

	_defaults = {
		"ghost_enabled": _ghost_look.enabled,
		"delta_enabled": _ghost_look.delta_enabled,
		"trail_enabled": _ghost_look.trail_enabled,
		"opacity": _ghost_look.opacity,
		"reference_mode": int(_ghost_look.delta_reference_mode),
	}

	var cfg := ConfigFile.new()
	var err: Error = cfg.load(settings_path)
	var prefs: Dictionary = {}
	_loading = true
	if err == OK and cfg.has_section("ghost"):
		var g_on: bool = bool(cfg.get_value("ghost", "ghost_enabled", _defaults["ghost_enabled"]))
		var d_on: bool = bool(cfg.get_value("ghost", "delta_enabled", _defaults["delta_enabled"]))
		var t_on: bool = bool(cfg.get_value("ghost", "trail_enabled", _defaults["trail_enabled"]))
		var op_val: float = clampf(float(cfg.get_value("ghost", "opacity", _defaults["opacity"])), 0.05, 1.0)
		var r_mode: int = clampi(int(cfg.get_value("ghost", "reference_mode", _defaults["reference_mode"])), 0, 2)
		prefs = {
			"ghost_enabled": g_on,
			"delta_enabled": d_on,
			"trail_enabled": t_on,
			"opacity": op_val,
			"reference_mode": r_mode,
		}
		_apply_ui_values(g_on, d_on, t_on, op_val, r_mode)
		_ghost_look.apply_user_preferences(prefs)
	else:
		_apply_ui_values(
			bool(_defaults["ghost_enabled"]),
			bool(_defaults["delta_enabled"]),
			bool(_defaults["trail_enabled"]),
			float(_defaults["opacity"]),
			int(_defaults["reference_mode"])
		)
		_ghost_look.clear_user_preferences()
	_sync_delta_widget()
	_refresh_delete_button()
	_loading = false


func _apply_ui_values(g_on: bool, d_on: bool, t_on: bool, op_val: float, r_mode: int) -> void:
	if _ghost_check != null:
		_ghost_check.set_pressed_no_signal(g_on)
	if _delta_check != null:
		_delta_check.set_pressed_no_signal(d_on)
	if _trail_check != null:
		_trail_check.set_pressed_no_signal(t_on)
	if _opacity_slider != null:
		_opacity_slider.set_value_no_signal(clampf(op_val, _opacity_slider.min_value, _opacity_slider.max_value))
	if _opacity_label != null:
		_opacity_label.text = "%d%%" % roundi(op_val * 100.0)
	if _mode_option != null:
		_mode_option.select(clampi(r_mode, 0, maxi(0, _mode_option.item_count - 1)))


func _on_toggled(_pressed: bool) -> void:
	if _loading:
		return
	_push_and_save()


func _on_opacity_changed(val: float) -> void:
	if _opacity_label != null:
		_opacity_label.text = "%d%%" % roundi(val * 100.0)
	if _loading:
		return
	_push_and_save()


func _on_mode_selected(_idx: int) -> void:
	if _loading:
		return
	_push_and_save()


func _current_prefs() -> Dictionary:
	return {
		"ghost_enabled": _ghost_check.button_pressed if _ghost_check != null else true,
		"delta_enabled": _delta_check.button_pressed if _delta_check != null else true,
		"trail_enabled": _trail_check.button_pressed if _trail_check != null else true,
		"opacity": _opacity_slider.value if _opacity_slider != null else 0.42,
		"reference_mode": _mode_option.get_selected_id() if _mode_option != null else 0,
	}


func _push_and_save() -> void:
	var prefs: Dictionary = _current_prefs()
	if _ghost_look != null:
		_ghost_look.apply_user_preferences(prefs)
	_sync_delta_widget()
	var cfg := ConfigFile.new()
	for k in prefs.keys():
		cfg.set_value("ghost", str(k), prefs[k])
	var err: Error = cfg.save(settings_path)
	if err != OK:
		push_warning("Не удалось сохранить настройки призрака: %s" % error_string(err))


func _sync_delta_widget() -> void:
	if _delta_widget == null or _ghost_look == null:
		return
	_delta_widget.set("enabled", _ghost_look.effective_delta_enabled())


func _refresh_delete_button() -> void:
	if _delete_btn == null:
		return
	var has_file: bool = _ghost_look != null and _ghost_look.has_loaded_ghost()
	_delete_btn.disabled = not has_file
	_delete_btn.text = delete_ready_text if has_file else delete_empty_text


func _reset_to_scene_defaults() -> void:
	if _defaults.is_empty():
		return
	_loading = true
	_apply_ui_values(
		bool(_defaults["ghost_enabled"]),
		bool(_defaults["delta_enabled"]),
		bool(_defaults["trail_enabled"]),
		float(_defaults["opacity"]),
		int(_defaults["reference_mode"])
	)
	_loading = false
	if _ghost_look != null:
		_ghost_look.clear_user_preferences()
	_sync_delta_widget()
	if FileAccess.file_exists(settings_path):
		DirAccess.remove_absolute(settings_path)


func _on_delete_pressed() -> void:
	if _ghost_look == null:
		return
	_ghost_look.delete_current_ghost()
	_refresh_delete_button()
