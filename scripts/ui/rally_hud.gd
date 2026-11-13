## Корневой контроллер гоночного HUD (`scenes/ui/rally_hud.tscn`).
##
## Связывает общий стиль `RallyHudStyle`, настраиваемый `SpriteSpeedometer`,
## счётчики `SpriteCounter`, `RallyFpsCounter`, `MiniMap`, `RallyRadioCard` и
## шесть шкал телеметрии `GaugeBar` в единую архитектуру.
## Позволяет переключать весь HUD целиком между текущим «стеклянным» видом
## и полным пиксельным стилем спрайт-листа спидометра.
@tool
class_name RallyHUD
extends Control

signal hud_style_applied(pixel_active: bool)

enum ThemeMode {
	AUTO_FROM_STYLE = 0,
	KEEP_CLASSIC_PANELS = 1,
	SPEEDOMETER_PIXEL = 2,
}

enum SpeedometerDisplayMode {
	SPRITE_SPEEDOMETER = 0,
	CLASSIC_TEXT_BOX = 1,
	BOTH = 2,
}

@export_group("Стиль HUD")
@export var hud_style: RallyHudStyle:
	set(v):
		if hud_style != null and hud_style.changed.is_connected(_on_hud_style_changed):
			hud_style.changed.disconnect(_on_hud_style_changed)
		hud_style = v
		if hud_style != null and not hud_style.changed.is_connected(_on_hud_style_changed):
			hud_style.changed.connect(_on_hud_style_changed)
		if is_inside_tree():
			apply_hud_style()

@export var theme_mode: ThemeMode = ThemeMode.AUTO_FROM_STYLE:
	set(v):
		theme_mode = v
		if is_inside_tree():
			apply_hud_style()

@export var speedometer_display: SpeedometerDisplayMode = SpeedometerDisplayMode.SPRITE_SPEEDOMETER:
	set(v):
		speedometer_display = v
		if is_inside_tree():
			_sync_speedometer_mode()

@export var auto_apply_on_ready: bool = true

@export_group("Пути виджетов")
@export var stage_panel_path: NodePath = NodePath("StagePanel")
@export var radio_card_path: NodePath = NodePath("RadioCard")
@export var timer_panel_path: NodePath = NodePath("TimerPanel")
@export var timer_label_path: NodePath = NodePath("TimerPanel/TimerBox/TimerLabel")
@export var timer_sprite_path: NodePath = NodePath("TimerPanel/TimerBox/TimerSprite")
@export var split_label_path: NodePath = NodePath("TimerPanel/TimerBox/SplitLabel")
@export var mini_map_path: NodePath = NodePath("MiniMap")
@export var fps_label_path: NodePath = NodePath("FPSLabel")
@export var speed_panel_path: NodePath = NodePath("SpeedPanel")
@export var speedometer_path: NodePath = NodePath("SpeedPanel/SpriteSpeedometer")
@export var speed_box_path: NodePath = NodePath("SpeedPanel/SpeedBox")
@export var telemetry_panel_path: NodePath = NodePath("TelemetryPanel")
@export var telemetry_box_path: NodePath = NodePath("TelemetryPanel/TeleBox")
@export var hint_label_path: NodePath = NodePath("Hint")
@export var clutch_notice_path: NodePath = NodePath("ClutchNotice")
@export var pause_panel_path: NodePath = NodePath("PausePanel")
@export var results_panel_path: NodePath = NodePath("ResultsPanel")

var _saved_panel_styles: Dictionary = {}
var _saved_label_styles: Dictionary = {}
var _saved_button_styles: Dictionary = {}
var _saved_text_colors: Dictionary = {}
var _classic_captured: bool = false


func _ready() -> void:
	if hud_style == null:
		hud_style = RallyHudStyle.load_default() as RallyHudStyle
	_capture_classic_styles()
	if auto_apply_on_ready:
		apply_hud_style()


func set_hud_style(style_res: RallyHudStyle) -> void:
	hud_style = style_res


func set_pixel_mode(enabled: bool) -> void:
	theme_mode = ThemeMode.SPEEDOMETER_PIXEL if enabled else ThemeMode.KEEP_CLASSIC_PANELS


func is_pixel_mode() -> bool:
	match theme_mode:
		ThemeMode.SPEEDOMETER_PIXEL:
			return true
		ThemeMode.KEEP_CLASSIC_PANELS:
			return false
	return hud_style != null and hud_style.is_pixel_mode()


func get_speedometer() -> SpriteSpeedometer:
	return get_node_or_null(speedometer_path) as SpriteSpeedometer


func _on_hud_style_changed() -> void:
	if is_inside_tree():
		apply_hud_style()


func apply_hud_style() -> void:
	if hud_style == null:
		hud_style = RallyHudStyle.load_default() as RallyHudStyle
	if not _classic_captured:
		_capture_classic_styles()

	var pixel_active := is_pixel_mode()
	var effective_style: RallyHudStyle = _effective_style_copy(pixel_active)

	var speedo := get_speedometer()
	if speedo != null:
		speedo.set_hud_style(effective_style)

	var mini := get_node_or_null(mini_map_path)
	if mini != null and mini.has_method("set_hud_style"):
		mini.call("set_hud_style", effective_style)

	var fps := get_node_or_null(fps_label_path)
	if fps != null and fps.has_method("set_hud_style"):
		fps.call("set_hud_style", effective_style)

	var radio := get_node_or_null(radio_card_path)
	if radio != null and radio.has_method("apply_hud_style"):
		radio.call("apply_hud_style", effective_style)

	var tele_box := get_node_or_null(telemetry_box_path)
	if tele_box != null:
		for child in tele_box.get_children():
			if child.has_method("set_hud_style"):
				child.call("set_hud_style", effective_style)

	_apply_panel_theming(pixel_active, effective_style)
	_sync_timer_sprite(pixel_active, effective_style)
	_sync_speedometer_mode()
	hud_style_applied.emit(pixel_active)


func _effective_style_copy(pixel_active: bool) -> RallyHudStyle:
	if hud_style == null:
		return RallyHudStyle.new()
	if pixel_active == hud_style.is_pixel_mode():
		return hud_style
	var copy := hud_style.duplicate() as RallyHudStyle
	if copy == null:
		return hud_style
	copy.hud_mode = RallyHudStyle.HudMode.SPEEDOMETER_PIXEL if pixel_active else RallyHudStyle.HudMode.CLASSIC_GLASS
	return copy


func _sync_speedometer_mode() -> void:
	var speedo := get_speedometer()
	var speed_box := get_node_or_null(speed_box_path) as Control
	if speedo != null:
		match speedometer_display:
			SpeedometerDisplayMode.SPRITE_SPEEDOMETER:
				speedo.visible = true
				speedo.sync_speed_box_visibility = true
				if speed_box != null:
					speed_box.visible = not speedo.is_atlas_ready()
			SpeedometerDisplayMode.CLASSIC_TEXT_BOX:
				speedo.visible = false
				if speed_box != null:
					speed_box.visible = true
			SpeedometerDisplayMode.BOTH:
				speedo.sync_speed_box_visibility = false
				speedo.visible = true
				if speed_box != null:
					speed_box.visible = true
	elif speed_box != null:
		speed_box.visible = true


func _sync_timer_sprite(pixel_active: bool, effective_style: RallyHudStyle) -> void:
	var t_lbl := get_node_or_null(timer_label_path) as Label
	var t_spr := get_node_or_null(timer_sprite_path) as SpriteCounter
	var use_spr := pixel_active and effective_style.use_sprite_digits_for_timer and t_spr != null
	if t_spr != null:
		t_spr.set_hud_style(effective_style)
		t_spr.digit_height_px = effective_style.timer_digit_height
		if t_lbl != null:
			t_spr.set_value_text(t_lbl.text)
		use_spr = use_spr and t_spr.is_atlas_ready()
		t_spr.visible = use_spr
	if t_lbl != null:
		t_lbl.visible = not use_spr


func update_timer_display(time_text: String, split_text: String = "", split_col: Color = Color(-1.0, 0.0, 0.0, 0.0)) -> void:
	var t_lbl := get_node_or_null(timer_label_path) as Label
	if t_lbl != null:
		t_lbl.text = time_text
	var t_spr := get_node_or_null(timer_sprite_path) as SpriteCounter
	if t_spr != null:
		t_spr.set_value_text(time_text)
	if not split_text.is_empty():
		var s_lbl := get_node_or_null(split_label_path) as Label
		if s_lbl != null:
			s_lbl.text = split_text
			if split_col.r >= 0.0:
				s_lbl.add_theme_color_override("font_color", split_col)


func update_speed_telemetry(
	new_speed_kmh: float,
	new_rpm: float,
	new_max_rpm: float,
	new_gear: String,
	new_redline: bool = false,
	trans_text: String = "",
	drive_text: String = ""
) -> void:
	var speedo := get_speedometer()
	if speedo != null:
		if not trans_text.is_empty():
			speedo.transmission_text = trans_text
		if not drive_text.is_empty():
			speedo.drivetrain_text = drive_text
		speedo.set_telemetry(new_speed_kmh, new_rpm, new_max_rpm, new_gear, new_redline)


func _capture_classic_styles() -> void:
	_classic_captured = true
	for p in [stage_panel_path, timer_panel_path, telemetry_panel_path, pause_panel_path, results_panel_path]:
		var ctrl := get_node_or_null(p) as Control
		if ctrl != null and ctrl.has_theme_stylebox_override("panel"):
			_saved_panel_styles[p] = ctrl.get_theme_stylebox("panel")
	for lp in [hint_label_path, clutch_notice_path]:
		var lbl := get_node_or_null(lp) as Label
		if lbl != null and lbl.has_theme_stylebox_override("normal"):
			_saved_label_styles[lp] = lbl.get_theme_stylebox("normal")
	_capture_buttons_under(get_node_or_null(pause_panel_path))
	_capture_buttons_under(get_node_or_null(results_panel_path))


func _capture_buttons_under(root_node: Node) -> void:
	if root_node == null:
		return
	for child in root_node.get_children():
		if child is Button:
			var btn := child as Button
			var key := str(btn.get_path())
			var map := {}
			for st in ["normal", "hover", "pressed", "focus"]:
				if btn.has_theme_stylebox_override(st):
					map[st] = btn.get_theme_stylebox(st)
			if not map.is_empty():
				_saved_button_styles[key] = map
		_capture_buttons_under(child)


func _apply_panel_theming(pixel_active: bool, style_res: RallyHudStyle) -> void:
	if not pixel_active:
		for p in _saved_panel_styles.keys():
			var ctrl := get_node_or_null(p) as Control
			if ctrl != null:
				ctrl.add_theme_stylebox_override("panel", _saved_panel_styles[p])
		for lp in _saved_label_styles.keys():
			var lbl := get_node_or_null(lp) as Label
			if lbl != null:
				lbl.add_theme_stylebox_override("normal", _saved_label_styles[lp])
		_restore_buttons_under(get_node_or_null(pause_panel_path))
		_restore_buttons_under(get_node_or_null(results_panel_path))
		return

	var stage_p := get_node_or_null(stage_panel_path) as Control
	if stage_p != null:
		stage_p.add_theme_stylebox_override("panel", style_res.make_panel_style(true, false))
	var timer_p := get_node_or_null(timer_panel_path) as Control
	if timer_p != null:
		timer_p.add_theme_stylebox_override("panel", style_res.make_panel_style(false, true))
	var tele_p := get_node_or_null(telemetry_panel_path) as Control
	if tele_p != null:
		tele_p.add_theme_stylebox_override("panel", style_res.make_panel_style(true, false))
	var pause_p := get_node_or_null(pause_panel_path) as Control
	if pause_p != null:
		pause_p.add_theme_stylebox_override("panel", style_res.make_panel_style(false, true))
	var res_p := get_node_or_null(results_panel_path) as Control
	if res_p != null:
		res_p.add_theme_stylebox_override("panel", style_res.make_panel_style(false, true))

	var hint_s := style_res.make_hint_style()
	for lp in [hint_label_path, clutch_notice_path]:
		var lbl := get_node_or_null(lp) as Label
		if lbl != null:
			lbl.add_theme_stylebox_override("normal", hint_s)

	_apply_buttons_under(get_node_or_null(pause_panel_path), style_res)
	_apply_buttons_under(get_node_or_null(results_panel_path), style_res)


func _apply_buttons_under(root_node: Node, style_res: RallyHudStyle) -> void:
	if root_node == null:
		return
	for child in root_node.get_children():
		if child is Button:
			var btn := child as Button
			for st in ["normal", "hover", "pressed", "focus"]:
				btn.add_theme_stylebox_override(st, style_res.make_button_style(st))
		_apply_buttons_under(child, style_res)


func _restore_buttons_under(root_node: Node) -> void:
	if root_node == null:
		return
	for child in root_node.get_children():
		if child is Button:
			var btn := child as Button
			var key := str(btn.get_path())
			if _saved_button_styles.has(key):
				var map: Dictionary = _saved_button_styles[key]
				for st in map.keys():
					btn.add_theme_stylebox_override(str(st), map[st])
		_restore_buttons_under(child)
