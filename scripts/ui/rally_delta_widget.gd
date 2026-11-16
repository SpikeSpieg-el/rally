## Виджет живой дельты времени (`scenes/ui/delta_panel.tscn`).
##
## Показывает опережение/отставание в реальном времени относительно сохранённого
## призрака (или целевого времени трассы), разницу скорости, разрыв в метрах,
## центральную полосу-индикатор и вспышку на контрольных пунктах.
@tool
class_name RallyDeltaWidget
extends PanelContainer

const DeltaBarType = preload("res://scripts/ui/delta_bar_view.gd")

enum DisplayMode {
	COMPACT_TIME = 0,
	TIME_AND_BAR = 1,
	FULL_TELEMETRY = 2,
}

@export_group("Режим и предпросмотр")
## Включить панель живой дельты.
@export var enabled: bool = true:
	set(value):
		enabled = value
		_refresh_view()
## Показывать тестовые данные в 2D-редакторе для удобной настройки цветов и шрифтов.
@export var preview_in_editor: bool = true:
	set(value):
		preview_in_editor = value
		_refresh_view()
@export_range(-30.0, 30.0, 0.05, "suffix:с") var preview_delta_seconds: float = -1.24:
	set(value):
		preview_delta_seconds = value
		_refresh_view()
@export_range(-100.0, 100.0, 1.0, "suffix:км/ч") var preview_speed_delta_kmh: float = 8.0:
	set(value):
		preview_speed_delta_kmh = value
		_refresh_view()
@export_range(-200.0, 200.0, 1.0, "suffix:м") var preview_gap_meters: float = 16.0:
	set(value):
		preview_gap_meters = value
		_refresh_view()
@export var preview_is_target: bool = false:
	set(value):
		preview_is_target = value
		_refresh_view()

@export_group("Отображаемые блоки")
@export var display_mode: DisplayMode = DisplayMode.FULL_TELEMETRY:
	set(value):
		display_mode = value
		_refresh_layout()
		_refresh_view()
@export var show_reference_badge: bool = true:
	set(value):
		show_reference_badge = value
		_refresh_layout()
@export var show_delta_bar: bool = true:
	set(value):
		show_delta_bar = value
		_refresh_layout()
@export var show_speed_delta: bool = true:
	set(value):
		show_speed_delta = value
		_refresh_view()
@export var show_distance_gap: bool = true:
	set(value):
		show_distance_gap = value
		_refresh_view()
@export var show_plus_minus_sign: bool = true:
	set(value):
		show_plus_minus_sign = value
		_refresh_view()
@export var show_direction_arrow: bool = true:
	set(value):
		show_direction_arrow = value
		_refresh_view()
@export var show_minutes_over_60s: bool = true:
	set(value):
		show_minutes_over_60s = value
		_refresh_view()
@export var hide_when_no_reference: bool = true:
	set(value):
		hide_when_no_reference = value
		_refresh_visibility()
@export_range(1, 3, 1) var decimal_places: int = 2:
	set(value):
		decimal_places = clampi(value, 1, 3)
		_refresh_view()

@export_group("Тексты и единицы")
@export var ghost_badge_text: String = "ПРИЗРАК":
	set(value):
		ghost_badge_text = value
		_refresh_view()
@export var target_badge_text: String = "ЦЕЛЬ":
	set(value):
		target_badge_text = value
		_refresh_view()
@export var ahead_arrow: String = "▲":
	set(value):
		ahead_arrow = value
		_refresh_view()
@export var behind_arrow: String = "▼":
	set(value):
		behind_arrow = value
		_refresh_view()
@export var neutral_arrow: String = "●":
	set(value):
		neutral_arrow = value
		_refresh_view()
@export var speed_unit: String = "км/ч":
	set(value):
		speed_unit = value
		_refresh_view()
@export var distance_unit: String = "м":
	set(value):
		distance_unit = value
		_refresh_view()
@export var checkpoint_prefix: String = "КПП":
	set(value):
		checkpoint_prefix = value
		_refresh_view()

@export_group("Цвета и пороги")
@export var ahead_color: Color = Color(0.24, 0.96, 0.56, 1.0):
	set(value):
		ahead_color = value
		_refresh_view()
@export var behind_color: Color = Color(1.0, 0.30, 0.22, 1.0):
	set(value):
		behind_color = value
		_refresh_view()
@export var neutral_color: Color = Color(0.92, 0.95, 1.0, 1.0):
	set(value):
		neutral_color = value
		_refresh_view()
@export var badge_ghost_color: Color = Color(0.32, 0.90, 1.0, 1.0):
	set(value):
		badge_ghost_color = value
		_refresh_view()
@export var badge_target_color: Color = Color(1.0, 0.72, 0.24, 1.0):
	set(value):
		badge_target_color = value
		_refresh_view()
@export var bar_track_color: Color = Color(0.10, 0.13, 0.18, 0.90):
	set(value):
		bar_track_color = value
		_refresh_bar_style()
@export var bar_border_color: Color = Color(1.0, 1.0, 1.0, 0.18):
	set(value):
		bar_border_color = value
		_refresh_bar_style()
@export var bar_center_tick_color: Color = Color(1.0, 1.0, 1.0, 0.72):
	set(value):
		bar_center_tick_color = value
		_refresh_bar_style()
@export_range(0.0, 0.5, 0.01, "suffix:с") var neutral_threshold_sec: float = 0.05:
	set(value):
		neutral_threshold_sec = value
		_refresh_view()

@export_group("Шкала и оформление")
@export_range(0.5, 30.0, 0.5, "suffix:с") var bar_max_seconds: float = 5.0:
	set(value):
		bar_max_seconds = value
		_refresh_bar_style()
@export_range(120.0, 480.0, 2.0, "suffix:px") var bar_width: float = 264.0:
	set(value):
		bar_width = value
		_refresh_layout()
@export_range(4.0, 24.0, 1.0, "suffix:px") var bar_height: float = 8.0:
	set(value):
		bar_height = value
		_refresh_layout()
@export var bar_segmented: bool = true:
	set(value):
		bar_segmented = value
		_refresh_bar_style()
@export_range(3, 24, 1) var bar_segments_per_side: int = 10:
	set(value):
		bar_segments_per_side = value
		_refresh_bar_style()
@export_range(0.0, 8.0, 0.5, "suffix:px") var bar_segment_gap: float = 2.0:
	set(value):
		bar_segment_gap = value
		_refresh_bar_style()
## Зелёная полоса выигрыша растёт вправо от центра (или влево — к минусу).
@export var ahead_fills_right: bool = true:
	set(value):
		ahead_fills_right = value
		_refresh_bar_style()
@export_range(14, 42, 1) var delta_font_size: int = 23:
	set(value):
		delta_font_size = value
		_refresh_layout()
@export_range(9, 24, 1) var meta_font_size: int = 12:
	set(value):
		meta_font_size = value
		_refresh_layout()
@export_range(8, 22, 1) var badge_font_size: int = 11:
	set(value):
		badge_font_size = value
		_refresh_layout()

@export_group("КПП и тема HUD")
@export var checkpoint_flash_enabled: bool = true
@export_range(0.5, 8.0, 0.1, "suffix:с") var checkpoint_hold_seconds: float = 2.6
@export_range(1.0, 1.25, 0.01) var flash_pulse_scale: float = 1.06
@export var hud_style: RallyHudStyle = null:
	set(value):
		if hud_style != null and hud_style.changed.is_connected(_on_style_changed):
			hud_style.changed.disconnect(_on_style_changed)
		hud_style = value
		if hud_style != null and not hud_style.changed.is_connected(_on_style_changed):
			hud_style.changed.connect(_on_style_changed)
		if is_inside_tree():
			_sync_hud_style()
@export var sync_with_hud_style: bool = true:
	set(value):
		sync_with_hud_style = value
		if is_inside_tree():
			_sync_hud_style()

var _badge_label: Label = null
var _delta_label: Label = null
var _meta_label: Label = null
var _bar_view: DeltaBarType = null

var _classic_panel_style: StyleBox = null
var _classic_captured: bool = false
var _pixel_mode: bool = false
var _hidden_by_cockpit: bool = false
var _runtime_has_data: bool = false
var _desired_visible: bool = true

var _live_delta_sec: float = 0.0
var _live_speed_kmh: float = 0.0
var _live_gap_m: float = 0.0
var _live_is_target: bool = false

var _cp_flash_timer: float = 0.0
var _cp_flash_label: String = ""
var _cp_flash_delta: float = 0.0


func _ready() -> void:
	_badge_label = get_node_or_null("Box/TopRow/BadgeLabel") as Label
	_delta_label = get_node_or_null("Box/TopRow/DeltaLabel") as Label
	_meta_label = get_node_or_null("Box/TopRow/MetaLabel") as Label
	_bar_view = get_node_or_null("Box/DeltaBar") as DeltaBarType
	if not _classic_captured:
		_classic_panel_style = get_theme_stylebox("panel")
		_classic_captured = true
	if hud_style == null:
		hud_style = RallyHudStyle.load_default() as RallyHudStyle
	_sync_hud_style()
	_refresh_layout()
	_refresh_bar_style()
	_refresh_view()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _cp_flash_timer > 0.0:
		_cp_flash_timer = maxf(0.0, _cp_flash_timer - delta)
		if _cp_flash_timer <= 0.0:
			self.scale = Vector2.ONE
		else:
			var t_pulse: float = clampf(_cp_flash_timer / maxf(0.1, checkpoint_hold_seconds), 0.0, 1.0)
			var boost: float = lerpf(1.0, flash_pulse_scale, sin(t_pulse * PI) * 0.65)
			self.pivot_offset = self.size * 0.5
			self.scale = Vector2(boost, boost)
		_refresh_view()


func set_hud_style(style_res: RallyHudStyle) -> void:
	hud_style = style_res


func _on_style_changed() -> void:
	if is_inside_tree():
		_sync_hud_style()


func _sync_hud_style() -> void:
	if not is_inside_tree():
		return
	if not sync_with_hud_style or hud_style == null:
		_pixel_mode = false
		if _classic_panel_style != null:
			add_theme_stylebox_override("panel", _classic_panel_style)
	else:
		_pixel_mode = hud_style.is_pixel_mode()
		if _pixel_mode:
			add_theme_stylebox_override("panel", hud_style.make_panel_style(false, true))
		elif _classic_panel_style != null:
			add_theme_stylebox_override("panel", _classic_panel_style)
	_refresh_bar_style()


func set_cockpit_hidden(hidden_flag: bool) -> void:
	_hidden_by_cockpit = hidden_flag
	_refresh_visibility()


func update_live_delta(info: Dictionary) -> void:
	var active: bool = bool(info.get("delta_active", false))
	_runtime_has_data = active
	if active:
		_live_delta_sec = float(info.get("delta_sec", 0.0))
		_live_speed_kmh = float(info.get("speed_delta_kmh", 0.0))
		_live_gap_m = float(info.get("gap_meters", 0.0))
		_live_is_target = bool(info.get("is_target", false))
	_refresh_view()


func flash_checkpoint(cp_index: int, cp_delta_sec: float) -> void:
	if not checkpoint_flash_enabled:
		return
	_cp_flash_timer = checkpoint_hold_seconds
	_cp_flash_label = "%s %d" % [checkpoint_prefix, cp_index + 1]
	_cp_flash_delta = cp_delta_sec
	_refresh_view()


func clear_runtime() -> void:
	_runtime_has_data = false
	_cp_flash_timer = 0.0
	self.scale = Vector2.ONE
	_refresh_view()


func _refresh_layout() -> void:
	if _badge_label != null:
		_badge_label.visible = show_reference_badge
		_badge_label.add_theme_font_size_override("font_size", badge_font_size)
	if _delta_label != null:
		_delta_label.add_theme_font_size_override("font_size", delta_font_size)
	if _meta_label != null:
		_meta_label.visible = display_mode == DisplayMode.FULL_TELEMETRY and (show_speed_delta or show_distance_gap)
		_meta_label.add_theme_font_size_override("font_size", meta_font_size)
	if _bar_view != null:
		_bar_view.visible = show_delta_bar and display_mode != DisplayMode.COMPACT_TIME
		_bar_view.custom_minimum_size = Vector2(bar_width, bar_height)


func _refresh_bar_style() -> void:
	if _bar_view == null:
		return
	_bar_view.max_seconds = bar_max_seconds
	_bar_view.neutral_threshold = neutral_threshold_sec
	_bar_view.ahead_fills_right = ahead_fills_right
	_bar_view.segmented = bar_segmented or _pixel_mode
	_bar_view.segments_per_side = bar_segments_per_side
	_bar_view.segment_gap = bar_segment_gap
	_bar_view.pixel_mode = _pixel_mode
	_bar_view.track_color = bar_track_color
	_bar_view.border_color = hud_style.panel_border_color if (_pixel_mode and hud_style != null) else bar_border_color
	_bar_view.center_tick_color = bar_center_tick_color
	_bar_view.ahead_color = ahead_color
	_bar_view.behind_color = behind_color
	_bar_view.neutral_color = neutral_color


func _refresh_view() -> void:
	if not is_inside_tree():
		return
	var is_editor: bool = Engine.is_editor_hint()
	var active_source: bool = (preview_in_editor if is_editor else _runtime_has_data)
	_desired_visible = enabled and (active_source or not hide_when_no_reference)
	_refresh_visibility()
	if not _desired_visible:
		return

	var d_sec: float = preview_delta_seconds if is_editor else (_cp_flash_delta if _cp_flash_timer > 0.0 else _live_delta_sec)
	var spd_d: float = preview_speed_delta_kmh if is_editor else _live_speed_kmh
	var gap_d: float = preview_gap_meters if is_editor else _live_gap_m
	var is_tgt: bool = preview_is_target if is_editor else _live_is_target

	var is_neutral: bool = absf(d_sec) <= neutral_threshold_sec
	var is_ahead: bool = d_sec < 0.0
	var state_col: Color = neutral_color if is_neutral else (ahead_color if is_ahead else behind_color)

	if _badge_label != null:
		_badge_label.visible = show_reference_badge
		if _cp_flash_timer > 0.0 and not is_editor:
			_badge_label.text = _cp_flash_label
			_badge_label.add_theme_color_override("font_color", state_col)
		else:
			_badge_label.text = target_badge_text if is_tgt else ghost_badge_text
			_badge_label.add_theme_color_override("font_color", badge_target_color if is_tgt else badge_ghost_color)

	if _delta_label != null:
		var arrow: String = ""
		if show_direction_arrow:
			arrow = (neutral_arrow if is_neutral else (ahead_arrow if is_ahead else behind_arrow)) + " "
		_delta_label.text = "%s%s" % [arrow, format_delta(d_sec)]
		_delta_label.add_theme_color_override("font_color", state_col)

	if _meta_label != null:
		var parts: Array[String] = []
		if display_mode == DisplayMode.FULL_TELEMETRY and active_source:
			if show_speed_delta:
				var s_sign: String = "+" if roundi(spd_d) > 0 else ""
				parts.append("%s%d %s" % [s_sign, roundi(spd_d), speed_unit])
			if show_distance_gap:
				var g_sign: String = "+" if roundi(gap_d) > 0 else ""
				parts.append("%s%d %s" % [g_sign, roundi(gap_d), distance_unit])
		_meta_label.visible = not parts.is_empty()
		_meta_label.text = " · ".join(parts)
		_meta_label.add_theme_color_override("font_color", state_col.lightened(0.25))

	if _bar_view != null:
		_bar_view.visible = show_delta_bar and display_mode != DisplayMode.COMPACT_TIME
		_bar_view.delta_seconds = d_sec if active_source else 0.0


func _refresh_visibility() -> void:
	self.visible = _desired_visible and not _hidden_by_cockpit


func format_delta(sec: float) -> String:
	var sign_str: String = ""
	if show_plus_minus_sign:
		if absf(sec) <= 0.0005:
			sign_str = "+"
		else:
			sign_str = "-" if sec < 0.0 else "+"
	var mag: float = absf(sec)
	if show_minutes_over_60s and mag >= 60.0:
		var mins: int = floori(mag / 60.0)
		var rem: float = fmod(mag, 60.0)
		if decimal_places == 3:
			return "%s%d:%06.3f" % [sign_str, mins, rem]
		if decimal_places == 1:
			return "%s%d:%04.1f" % [sign_str, mins, rem]
		return "%s%d:%05.2f" % [sign_str, mins, rem]
	if decimal_places == 3:
		return "%s%.3f" % [sign_str, mag]
	if decimal_places == 1:
		return "%s%.1f" % [sign_str, mag]
	return "%s%.2f" % [sign_str, mag]
