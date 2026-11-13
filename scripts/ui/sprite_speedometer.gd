## Спрайтовый спидометр с тахометром-дугой, цифровым спидометром и индикатором передач.
##
## Полностью настраиваемый `@tool`-виджет HUD на базе RallyHudSpriteAtlas:
##   - 5 пресетов (RALLY_CLASSIC, COMPACT_MINIMAL, WIDE_ARCADE, RETRO_PIXEL, CUSTOM);
##   - связь с общим стилем RallyHudStyle и переключение в единую пиксельную тему;
##   - нарезка с автоопределением и вырезом белого/тёмного фона + пользовательские зоны;
##   - настраиваемый шейдер четвертькруглой дуги 0..8 (с пиковым хвостом и переключением на сегментные бары);
##   - сочный отклик (пружина переключения, удержание пика RPM, лёгкая тряска на отсечке, подсветка);
##   - поддержка км/ч и миль/ч, ведущих нулей, передач 1..5 и 6/R/N;
##   - прямое API set_telemetry(), синхронизация со SpeedBox или прямое чтение машины + превью в редакторе.
@tool
class_name SpriteSpeedometer
extends Control

signal telemetry_updated(speed_display: float, rpm_value: float, gear_text: String)
signal redline_changed(redline_active: bool)
signal preset_applied(preset_id: int)
signal atlas_rebuilt(is_ready: bool)

enum Preset {
	CUSTOM = 0,
	RALLY_CLASSIC = 1,
	COMPACT_MINIMAL = 2,
	WIDE_ARCADE = 3,
	RETRO_PIXEL = 4,
}

enum SpeedUnits {
	KMH = 0,
	MPH = 1,
}

enum DataSource {
	AUTO = 0,
	VEHICLE_DIRECT = 1,
	SPEEDBOX_SYNC = 2,
	MANUAL_OVERRIDE = 3,
	EDITOR_PREVIEW = 4,
}

enum ArcRenderStyle {
	ARC_DIAL = 0,
	SEGMENTED_BAR_STEPPED = 1,
	SEGMENTED_BAR_BLOCKS = 2,
}

enum ArcShaderGeometry {
	QUARTER_CIRCLE = 0,
	RADIAL_SWEEP = 1,
}

enum GearRenderMode {
	ACTIVE_BADGE_AUTO = 0,
	FIVE_GEAR_STRIP = 1,
	SMALL_GLYPH_ONLY = 2,
}

const ARC_SHADER_CODE := """shader_type canvas_item;
uniform vec4 arc_uv = vec4(0.0, 0.0, 0.44, 0.42);
uniform float fill_ratio : hint_range(0.0, 1.0) = 0.0;
uniform float peak_ratio : hint_range(0.0, 1.0) = 0.0;
uniform float redline_ratio : hint_range(0.0, 1.0) = 0.86;
uniform float pulse = 0.0;
uniform float shift_flash = 0.0;
uniform float geometry_mode = 0.0;
uniform vec2 quarter_pivot = vec2(0.97, 0.96);
uniform vec4 tint_active : source_color = vec4(1.0, 0.70, 0.14, 1.0);
uniform vec4 tint_mid : source_color = vec4(1.0, 0.26, 0.04, 1.0);
uniform vec4 tint_hot : source_color = vec4(1.0, 0.08, 0.05, 1.0);
uniform vec4 tint_dim : source_color = vec4(0.50, 0.50, 0.50, 1.0);
uniform vec4 tint_peak : source_color = vec4(1.0, 0.65, 0.25, 0.85);
uniform vec2 radial_center = vec2(0.505, 0.535);
uniform float angle_start_deg = 228.0;
uniform float angle_sweep_deg = 256.0;
uniform float tip_glow = 0.72;

void fragment() {
	vec2 sample_uv = arc_uv.xy + UV * arc_uv.zw;
	vec4 tex_col = texture(TEXTURE, sample_uv);
	if (tex_col.a < 0.04) {
		discard;
	}

	float ang = 0.0;
	if (geometry_mode < 0.5) {
		vec2 p = quarter_pivot - UV;
		ang = atan(max(0.0, p.y), max(0.0001, p.x)) / 1.5707963;
		ang = clamp(ang, 0.0, 1.0);
	} else {
		vec2 rp = UV - radial_center;
		float deg = degrees(atan(-rp.y, rp.x));
		float rel = mod(angle_start_deg - deg + 360.0, 360.0);
		ang = clamp(rel / max(angle_sweep_deg, 1.0), 0.0, 1.0);
	}

	float max_c = max(tex_col.r, max(tex_col.g, tex_col.b));
	float min_c = min(tex_col.r, min(tex_col.g, tex_col.b));
	bool is_white_border = max_c > 0.68 && (max_c - min_c) < 0.14;
	bool is_colored_num = (max_c - min_c) >= 0.14;
	bool is_shadow = max_c < 0.24 || tex_col.a < 0.36;
	bool is_grey_track = !is_white_border && !is_colored_num && !is_shadow;

	if (is_grey_track) {
		bool in_redline = ang >= redline_ratio;
		if (ang <= fill_ratio && fill_ratio > 0.002) {
			vec3 active_col = in_redline
				? tint_hot.rgb
				: mix(tint_active.rgb, tint_mid.rgb, smoothstep(0.35, redline_ratio, ang));
			float tip = smoothstep(max(0.0, fill_ratio - 0.055), fill_ratio, ang);
			active_col = mix(active_col, vec3(1.0, 0.96, 0.72), tip * tip_glow);
			active_col = mix(active_col, vec3(1.0, 0.95, 0.75), shift_flash * 0.55);
			if (fill_ratio >= redline_ratio) {
				active_col *= 1.0 + 0.22 * pulse;
			}
			tex_col.rgb = active_col;
			tex_col.a = 0.96;
		} else if (ang <= peak_ratio && peak_ratio > fill_ratio + 0.015) {
			float trail = 1.0 - clamp((ang - fill_ratio) / max(0.01, peak_ratio - fill_ratio), 0.0, 1.0);
			tex_col.rgb = mix(tint_peak.rgb * 0.55, tint_peak.rgb, trail);
			tex_col.a = tint_peak.a;
		} else if (in_redline) {
			tex_col.rgb = tint_hot.rgb * 0.72 * (1.0 + (fill_ratio >= redline_ratio - 0.08 ? 0.25 * pulse : 0.0));
			tex_col.a = 0.80;
		} else {
			tex_col.rgb *= tint_dim.rgb;
			tex_col.a *= tint_dim.a;
		}
	}
	COLOR = tex_col;
}
"""

const KMH_TO_MPH := 0.621371

var _applying_preset := false

@export var preset: Preset = Preset.RALLY_CLASSIC:
	set(v):
		preset = v
		if not _applying_preset and v != Preset.CUSTOM:
			apply_preset(v)

@export var hud_style: RallyHudStyle:
	set(v):
		if hud_style != null and hud_style.changed.is_connected(_on_hud_style_changed):
			hud_style.changed.disconnect(_on_hud_style_changed)
		hud_style = v
		if hud_style != null and not hud_style.changed.is_connected(_on_hud_style_changed):
			hud_style.changed.connect(_on_hud_style_changed)
		_apply_hud_style_sync()
		rebuild_atlas()
		queue_redraw()

@export var sync_from_hud_style: bool = true:
	set(v):
		sync_from_hud_style = v
		_apply_hud_style_sync()
		rebuild_atlas()
		queue_redraw()

@export_group("Telemetry")
@export var data_source: DataSource = DataSource.AUTO:
	set(v):
		data_source = v
		queue_redraw()

@export var vehicle_path: NodePath = NodePath(""):
	set(v):
		vehicle_path = v
		_bound_vehicle = null
		if is_inside_tree():
			_resolve_bound_vehicle()

@export var speed_units: SpeedUnits = SpeedUnits.KMH:
	set(v):
		speed_units = v
		queue_redraw()

@export_range(0.25, 3.0, 0.01) var speed_scale: float = 1.0:
	set(v):
		speed_scale = v
		queue_redraw()

@export var speed_kmh: float = 0.0:
	set(v):
		speed_kmh = maxf(0.0, v)
		if speed_smooth_speed <= 0.0:
			_display_speed_kmh = speed_kmh
		queue_redraw()

@export var rpm: float = 0.0:
	set(v):
		rpm = maxf(0.0, v)
		if rpm_smooth_speed <= 0.0:
			_display_rpm = rpm
		queue_redraw()

@export var max_rpm: float = 7600.0:
	set(v):
		max_rpm = maxf(1000.0, v)
		queue_redraw()

@export var redline_rpm: float = 0.0:
	set(v):
		redline_rpm = maxf(0.0, v)
		queue_redraw()

@export_range(0.5, 0.99, 0.01) var redline_ratio: float = 0.86:
	set(v):
		redline_ratio = clampf(v, 0.5, 0.99)
		queue_redraw()

@export var gear_label: String = "N":
	set(v):
		gear_label = v
		queue_redraw()

@export var transmission_text: String = "":
	set(v):
		transmission_text = v
		queue_redraw()

@export var drivetrain_text: String = "":
	set(v):
		drivetrain_text = v
		queue_redraw()

@export var is_redline: bool = false:
	set(v):
		var prev := is_redline
		is_redline = v
		if prev != is_redline:
			redline_changed.emit(is_redline)
		queue_redraw()

@export_range(0.0, 40.0, 0.5) var rpm_smooth_speed: float = 22.0
@export_range(0.0, 40.0, 0.5) var speed_smooth_speed: float = 0.0

@export var show_rpm_bar: bool = true:
	set(v):
		show_rpm_bar = v
		_mark_custom_if_editing()
		_sync_arc_node()
		queue_redraw()

@export var show_gear_bar: bool = true:
	set(v):
		show_gear_bar = v
		_mark_custom_if_editing()
		queue_redraw()

@export var show_speed_digits: bool = true:
	set(v):
		show_speed_digits = v
		_mark_custom_if_editing()
		queue_redraw()

@export var show_unit_label: bool = true:
	set(v):
		show_unit_label = v
		_mark_custom_if_editing()
		queue_redraw()

@export var show_rpm_underline: bool = true:
	set(v):
		show_rpm_underline = v
		_mark_custom_if_editing()
		queue_redraw()

@export var show_extra_info: bool = false:
	set(v):
		show_extra_info = v
		_mark_custom_if_editing()
		queue_redraw()

@export_group("Feel & Juice")
@export_range(0.0, 2.0, 0.05) var juice_intensity: float = 1.0
@export_range(0.0, 1.5, 0.02) var peak_hold_seconds: float = 0.24
@export_range(1.0, 20.0, 0.5) var peak_fall_speed: float = 5.5
@export var show_underglow: bool = true:
	set(v):
		show_underglow = v
		queue_redraw()
@export var enable_shake: bool = true

@export_group("Preview")
@export var preview_in_editor: bool = true:
	set(v):
		preview_in_editor = v
		queue_redraw()

@export_range(0.0, 320.0, 1.0) var preview_speed_kmh: float = 138.0:
	set(v):
		preview_speed_kmh = v
		queue_redraw()

@export_range(0.0, 12000.0, 50.0) var preview_rpm: float = 5900.0:
	set(v):
		preview_rpm = v
		queue_redraw()

@export var preview_gear: String = "4":
	set(v):
		preview_gear = v
		queue_redraw()

@export var preview_animate: bool = false

@export_group("Sprite Sheet & Slicing")
@export var sprite_sheet: Texture2D:
	set(v):
		sprite_sheet = v
		rebuild_atlas()
		queue_redraw()

@export var bg_keyout: RallyHudSpriteAtlas.KeyoutMode = RallyHudSpriteAtlas.KeyoutMode.AUTO:
	set(v):
		bg_keyout = v
		rebuild_atlas()
		queue_redraw()

@export_range(0, 8, 1) var slice_pad_px: int = 2:
	set(v):
		slice_pad_px = v
		rebuild_atlas()
		queue_redraw()

@export var use_custom_regions: bool = false:
	set(v):
		use_custom_regions = v
		rebuild_atlas()
		queue_redraw()

@export var region_arc_norm: Rect2 = Rect2(0.0, 0.0, 0.44, 0.425):
	set(v):
		region_arc_norm = v
		if use_custom_regions:
			rebuild_atlas()
			queue_redraw()

@export var region_bar_stepped_norm: Rect2 = Rect2(0.45, 0.03, 0.53, 0.125):
	set(v):
		region_bar_stepped_norm = v
		if use_custom_regions:
			rebuild_atlas()
			queue_redraw()

@export var region_bar_blocks_norm: Rect2 = Rect2(0.45, 0.165, 0.53, 0.12):
	set(v):
		region_bar_blocks_norm = v
		if use_custom_regions:
			rebuild_atlas()
			queue_redraw()

@export var region_big_digits_norm: Rect2 = Rect2(0.01, 0.425, 0.98, 0.17):
	set(v):
		region_big_digits_norm = v
		if use_custom_regions:
			rebuild_atlas()
			queue_redraw()

@export var region_small_digits_norm: Rect2 = Rect2(0.01, 0.605, 0.98, 0.105):
	set(v):
		region_small_digits_norm = v
		if use_custom_regions:
			rebuild_atlas()
			queue_redraw()

@export var region_labels_norm: Rect2 = Rect2(0.01, 0.72, 0.98, 0.135):
	set(v):
		region_labels_norm = v
		if use_custom_regions:
			rebuild_atlas()
			queue_redraw()

@export var region_gears_norm: Rect2 = Rect2(0.01, 0.86, 0.98, 0.12):
	set(v):
		region_gears_norm = v
		if use_custom_regions:
			rebuild_atlas()
			queue_redraw()

@export var pixel_filter: bool = true:
	set(v):
		pixel_filter = v
		_mark_custom_if_editing()
		_apply_filter_mode()
		queue_redraw()

@export_group("Visuals & Colors")
@export var speed_digit_tint: Color = Color(1.0, 1.0, 1.0, 1.0):
	set(v):
		speed_digit_tint = v
		queue_redraw()

@export_range(0.0, 1.0, 0.02) var leading_zero_alpha: float = 0.16:
	set(v):
		leading_zero_alpha = v
		_mark_custom_if_editing()
		queue_redraw()

@export var dim_leading_zeros: bool = true:
	set(v):
		dim_leading_zeros = v
		_mark_custom_if_editing()
		queue_redraw()

@export_range(1, 5, 1) var min_speed_digits: int = 3:
	set(v):
		min_speed_digits = clampi(v, 1, 5)
		_mark_custom_if_editing()
		queue_redraw()

@export var speed_use_small_digits: bool = false:
	set(v):
		speed_use_small_digits = v
		_mark_custom_if_editing()
		queue_redraw()

@export var unit_tint: Color = Color(1.0, 0.94, 0.82, 0.98):
	set(v):
		unit_tint = v
		queue_redraw()

@export var gear_active_tint: Color = Color(1.0, 1.0, 1.0, 1.0):
	set(v):
		gear_active_tint = v
		queue_redraw()

@export var gear_inactive_tint: Color = Color(0.55, 0.68, 0.78, 0.24):
	set(v):
		gear_inactive_tint = v
		queue_redraw()

@export var gear_redline_tint: Color = Color(1.0, 0.45, 0.25, 1.0):
	set(v):
		gear_redline_tint = v
		queue_redraw()

@export var gear_render_mode: GearRenderMode = GearRenderMode.ACTIVE_BADGE_AUTO:
	set(v):
		gear_render_mode = v
		_mark_custom_if_editing()
		queue_redraw()

@export var sub_info_tint: Color = Color(0.82, 0.88, 0.95, 0.85):
	set(v):
		sub_info_tint = v
		queue_redraw()

@export_group("RPM Arc & Shader")
@export var arc_style: ArcRenderStyle = ArcRenderStyle.ARC_DIAL:
	set(v):
		arc_style = v
		_mark_custom_if_editing()
		_sync_arc_node()
		queue_redraw()

@export var arc_geometry: ArcShaderGeometry = ArcShaderGeometry.QUARTER_CIRCLE:
	set(v):
		arc_geometry = v
		_sync_arc_node()

@export var arc_active_tint: Color = Color(1.0, 0.70, 0.14, 1.0):
	set(v):
		arc_active_tint = v
		_sync_arc_node()
		queue_redraw()

@export var arc_mid_tint: Color = Color(1.0, 0.26, 0.04, 1.0):
	set(v):
		arc_mid_tint = v
		_sync_arc_node()
		queue_redraw()

@export var arc_hot_tint: Color = Color(1.0, 0.08, 0.05, 1.0):
	set(v):
		arc_hot_tint = v
		_sync_arc_node()
		queue_redraw()

@export var arc_dim_tint: Color = Color(0.50, 0.50, 0.50, 1.0):
	set(v):
		arc_dim_tint = v
		_sync_arc_node()
		queue_redraw()

@export var arc_peak_tint: Color = Color(1.0, 0.65, 0.25, 0.85):
	set(v):
		arc_peak_tint = v
		_sync_arc_node()

@export var arc_quarter_pivot: Vector2 = Vector2(0.97, 0.96):
	set(v):
		arc_quarter_pivot = v
		_sync_arc_node()

@export var arc_radial_center: Vector2 = Vector2(0.505, 0.535):
	set(v):
		arc_radial_center = v
		_sync_arc_node()

@export_range(0.0, 360.0, 1.0) var arc_start_deg: float = 228.0:
	set(v):
		arc_start_deg = v
		_sync_arc_node()

@export_range(60.0, 360.0, 1.0) var arc_sweep_deg: float = 256.0:
	set(v):
		arc_sweep_deg = v
		_sync_arc_node()

@export_range(0.0, 1.0, 0.02) var arc_tip_glow: float = 0.72:
	set(v):
		arc_tip_glow = v
		_sync_arc_node()

@export var segmented_preserve_colors: bool = false:
	set(v):
		segmented_preserve_colors = v
		queue_redraw()

@export_group("Layout & Sizing")
@export_range(0.5, 2.0, 0.02) var content_scale: float = 1.0:
	set(v):
		content_scale = v
		_mark_custom_if_editing()
		queue_redraw()

@export var content_offset: Vector2 = Vector2.ZERO:
	set(v):
		content_offset = v
		queue_redraw()

@export_range(0.45, 1.15, 0.01) var arc_height_ratio: float = 0.90:
	set(v):
		arc_height_ratio = v
		_mark_custom_if_editing()
		_sync_arc_node()
		queue_redraw()

@export var arc_offset: Vector2 = Vector2(2.0, 4.0):
	set(v):
		arc_offset = v
		_sync_arc_node()
		queue_redraw()

@export_range(0.05, 0.60, 0.01) var digit_start_x_ratio: float = 0.31:
	set(v):
		digit_start_x_ratio = v
		_mark_custom_if_editing()
		queue_redraw()

@export_range(0.10, 0.75, 0.01) var digit_y_ratio: float = 0.41:
	set(v):
		digit_y_ratio = v
		_mark_custom_if_editing()
		queue_redraw()

@export_range(0.14, 0.55, 0.01) var digit_height_ratio: float = 0.27:
	set(v):
		digit_height_ratio = v
		_mark_custom_if_editing()
		queue_redraw()

@export_range(0.45, 0.90, 0.01) var digit_slot_aspect: float = 0.66:
	set(v):
		digit_slot_aspect = v
		_mark_custom_if_editing()
		queue_redraw()

@export_range(0.0, 12.0, 0.5) var digit_gap_px: float = 2.0:
	set(v):
		digit_gap_px = v
		_mark_custom_if_editing()
		queue_redraw()

@export var speed_offset: Vector2 = Vector2.ZERO:
	set(v):
		speed_offset = v
		queue_redraw()

@export_range(0.05, 0.24, 0.005) var unit_height_ratio: float = 0.135:
	set(v):
		unit_height_ratio = v
		_mark_custom_if_editing()
		queue_redraw()

@export var unit_offset: Vector2 = Vector2(6.0, 0.0):
	set(v):
		unit_offset = v
		queue_redraw()

@export_range(0.40, 0.95, 0.005) var gear_y_ratio: float = 0.735:
	set(v):
		gear_y_ratio = v
		_mark_custom_if_editing()
		queue_redraw()

@export_range(0.08, 0.30, 0.005) var gear_strip_height_ratio: float = 0.15:
	set(v):
		gear_strip_height_ratio = v
		_mark_custom_if_editing()
		queue_redraw()

@export var gear_offset: Vector2 = Vector2.ZERO:
	set(v):
		gear_offset = v
		queue_redraw()

@export_group("Background & SpeedBox Sync")
@export var draw_backdrop: bool = false:
	set(v):
		draw_backdrop = v
		_mark_custom_if_editing()
		queue_redraw()

@export var backdrop_color: Color = Color(0.03, 0.05, 0.08, 0.84):
	set(v):
		backdrop_color = v
		queue_redraw()

@export var backdrop_border_color: Color = Color(1.0, 0.45, 0.05, 0.92):
	set(v):
		backdrop_border_color = v
		queue_redraw()

@export_range(0, 6, 1) var backdrop_border_width: int = 2:
	set(v):
		backdrop_border_width = v
		_mark_custom_if_editing()
		queue_redraw()

@export_range(0, 16, 1) var backdrop_corner_radius: int = 0:
	set(v):
		backdrop_corner_radius = v
		_mark_custom_if_editing()
		queue_redraw()

@export var sync_speed_box_visibility: bool = true:
	set(v):
		sync_speed_box_visibility = v
		_sync_speed_box_visibility()

@export var speed_box_path: NodePath = NodePath("../SpeedBox")

var _atlas: RallyHudSpriteAtlas = RallyHudSpriteAtlas.new()
var _arc_node: TextureRect = null
var _arc_mat: ShaderMaterial = null
var _bound_vehicle: Node = null
var _has_direct_telemetry: bool = false

var _rpm_bar: ProgressBar = null
var _speed_label: Label = null
var _speed_unit_lbl: Label = null
var _gear_label_node: Label = null
var _drivetrain_lbl: Label = null
var _rpm_caption_lbl: Label = null

var _display_speed_kmh: float = 0.0
var _display_rpm: float = 0.0
var _peak_rpm: float = 0.0
var _peak_hold: float = 0.0
var _pulse_time: float = 0.0
var _first_frame: bool = true
var _last_gear: String = ""
var _last_speed: int = -1
var _gear_pop: float = 0.0
var _widget_punch: float = 0.0
var _speed_pop: float = 0.0
var _shift_flash: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if preset != Preset.CUSTOM:
		apply_preset(preset)
	_apply_filter_mode()
	_apply_hud_style_sync()
	_bind_speed_box_nodes()
	_ensure_arc_node()
	rebuild_atlas()
	if not Engine.is_editor_hint():
		_resolve_bound_vehicle()
	_sync_arc_node()
	_sync_speed_box_visibility()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_VISIBILITY_CHANGED:
		_sync_arc_node()
		_sync_speed_box_visibility()
		queue_redraw()


func _process(delta: float) -> void:
	if not is_atlas_ready():
		return

	if not Engine.is_editor_hint():
		match data_source:
			DataSource.VEHICLE_DIRECT:
				_poll_vehicle_telemetry()
			DataSource.SPEEDBOX_SYNC:
				_poll_speed_box_telemetry()
			DataSource.AUTO:
				if not _has_direct_telemetry:
					if _bound_vehicle != null and is_instance_valid(_bound_vehicle):
						_poll_vehicle_telemetry()
					else:
						_poll_speed_box_telemetry()
			DataSource.MANUAL_OVERRIDE, DataSource.EDITOR_PREVIEW:
				pass

	var target_speed := _target_speed_kmh()
	var target_rpm := _target_rpm_value()
	var max_r := maxf(max_rpm, 1000.0)
	var gear_str := _effective_gear_text()

	if Engine.is_editor_hint() or data_source == DataSource.EDITOR_PREVIEW:
		_display_speed_kmh = target_speed
		_display_rpm = target_rpm
		_peak_rpm = target_rpm
		_shake_offset = Vector2.ZERO
		_gear_pop = 0.0
		_widget_punch = 0.0
		_speed_pop = 0.0
		_shift_flash = 0.0
		if Engine.is_editor_hint() and preview_animate:
			_pulse_time += delta * 1.4
	else:
		if speed_smooth_speed > 0.0:
			_display_speed_kmh = lerpf(_display_speed_kmh, target_speed, clampf(speed_smooth_speed * delta, 0.0, 1.0))
		else:
			_display_speed_kmh = target_speed

		var spd_int := get_display_speed()

		if rpm_smooth_speed > 0.0:
			_display_rpm = lerpf(_display_rpm, target_rpm, clampf(rpm_smooth_speed * delta, 0.0, 1.0))
		else:
			_display_rpm = target_rpm

		if _display_rpm >= _peak_rpm:
			_peak_rpm = _display_rpm
			_peak_hold = peak_hold_seconds
		elif _peak_hold > 0.0:
			_peak_hold -= delta
		else:
			_peak_rpm = lerpf(_peak_rpm, _display_rpm, clampf(delta * peak_fall_speed, 0.0, 1.0))

		_pulse_time += delta * 16.0

		if _first_frame:
			_last_gear = gear_str
			_last_speed = spd_int
			_first_frame = false
		else:
			if gear_str != _last_gear:
				_gear_pop = 1.0
				_widget_punch = 1.0 * juice_intensity
				_shift_flash = 1.0 * juice_intensity
				_last_gear = gear_str
			if spd_int != _last_speed:
				if spd_int > _last_speed:
					_speed_pop = minf(1.0, _speed_pop + 0.55 * juice_intensity)
				_last_speed = spd_int

		_gear_pop = move_toward(_gear_pop, 0.0, delta * 4.5)
		_widget_punch = move_toward(_widget_punch, 0.0, delta * 6.5)
		_speed_pop = move_toward(_speed_pop, 0.0, delta * 8.0)
		_shift_flash = move_toward(_shift_flash, 0.0, delta * 5.0)

		var rpm_norm := clampf(_display_rpm / max_r, 0.0, 1.0)
		var shake_amp := 0.0
		if enable_shake:
			if rpm_norm > redline_ratio:
				shake_amp += ((rpm_norm - redline_ratio) / maxf(0.01, 1.0 - redline_ratio)) * 1.6
			if spd_int > 140:
				shake_amp += clampf(float(spd_int - 140) / 120.0, 0.0, 1.0) * 0.8
		shake_amp *= juice_intensity
		_shake_offset = Vector2(
			sin(_pulse_time * 3.3) * shake_amp,
			cos(_pulse_time * 3.9) * shake_amp
		)

	_sync_arc_node()
	queue_redraw()


func _mark_custom_if_editing() -> void:
	if is_inside_tree() and not _applying_preset and preset != Preset.CUSTOM:
		preset = Preset.CUSTOM


func apply_preset(preset_id: Preset) -> void:
	_applying_preset = true
	preset = preset_id
	match preset_id:
		Preset.RALLY_CLASSIC:
			arc_style = ArcRenderStyle.ARC_DIAL
			gear_render_mode = GearRenderMode.ACTIVE_BADGE_AUTO
			arc_height_ratio = 0.90
			arc_offset = Vector2(2.0, 4.0)
			digit_start_x_ratio = 0.31
			digit_y_ratio = 0.41
			digit_height_ratio = 0.27
			digit_slot_aspect = 0.66
			digit_gap_px = 2.0
			unit_height_ratio = 0.135
			gear_y_ratio = 0.735
			gear_strip_height_ratio = 0.15
			content_scale = 1.0
			leading_zero_alpha = 0.16
			dim_leading_zeros = true
			min_speed_digits = 3
			speed_use_small_digits = false
			show_rpm_bar = true
			show_gear_bar = true
			show_speed_digits = true
			show_unit_label = true
			show_rpm_underline = true
			show_extra_info = false
			pixel_filter = true
			draw_backdrop = false
			backdrop_border_width = 2
			backdrop_corner_radius = 0
		Preset.COMPACT_MINIMAL:
			arc_style = ArcRenderStyle.SEGMENTED_BAR_BLOCKS
			gear_render_mode = GearRenderMode.ACTIVE_BADGE_AUTO
			arc_height_ratio = 0.80
			digit_start_x_ratio = 0.06
			digit_y_ratio = 0.30
			digit_height_ratio = 0.34
			digit_slot_aspect = 0.64
			digit_gap_px = 2.0
			unit_height_ratio = 0.13
			gear_y_ratio = 0.74
			gear_strip_height_ratio = 0.14
			content_scale = 0.96
			leading_zero_alpha = 0.14
			dim_leading_zeros = true
			min_speed_digits = 3
			speed_use_small_digits = false
			show_rpm_bar = true
			show_gear_bar = true
			show_speed_digits = true
			show_unit_label = true
			show_rpm_underline = false
			show_extra_info = false
			pixel_filter = true
			draw_backdrop = false
			backdrop_border_width = 2
			backdrop_corner_radius = 0
		Preset.WIDE_ARCADE:
			arc_style = ArcRenderStyle.ARC_DIAL
			gear_render_mode = GearRenderMode.FIVE_GEAR_STRIP
			arc_height_ratio = 0.92
			arc_offset = Vector2(4.0, 2.0)
			digit_start_x_ratio = 0.33
			digit_y_ratio = 0.35
			digit_height_ratio = 0.30
			digit_slot_aspect = 0.66
			digit_gap_px = 3.0
			unit_height_ratio = 0.13
			gear_y_ratio = 0.75
			gear_strip_height_ratio = 0.15
			content_scale = 1.02
			leading_zero_alpha = 0.20
			dim_leading_zeros = true
			min_speed_digits = 3
			speed_use_small_digits = false
			show_rpm_bar = true
			show_gear_bar = true
			show_speed_digits = true
			show_unit_label = true
			show_rpm_underline = true
			show_extra_info = true
			pixel_filter = true
			draw_backdrop = true
			backdrop_border_width = 2
			backdrop_corner_radius = 2
		Preset.RETRO_PIXEL:
			arc_style = ArcRenderStyle.SEGMENTED_BAR_STEPPED
			gear_render_mode = GearRenderMode.FIVE_GEAR_STRIP
			arc_height_ratio = 0.85
			digit_start_x_ratio = 0.06
			digit_y_ratio = 0.29
			digit_height_ratio = 0.32
			digit_slot_aspect = 0.68
			digit_gap_px = 2.0
			unit_height_ratio = 0.13
			gear_y_ratio = 0.74
			gear_strip_height_ratio = 0.15
			content_scale = 1.0
			leading_zero_alpha = 0.20
			dim_leading_zeros = true
			min_speed_digits = 3
			speed_use_small_digits = false
			show_rpm_bar = true
			show_gear_bar = true
			show_speed_digits = true
			show_unit_label = true
			show_rpm_underline = true
			show_extra_info = true
			pixel_filter = true
			draw_backdrop = true
			backdrop_border_width = 2
			backdrop_corner_radius = 0
	_applying_preset = false
	_apply_filter_mode()
	_sync_arc_node()
	queue_redraw()
	preset_applied.emit(int(preset_id))


func set_hud_style(style_res: RallyHudStyle) -> void:
	hud_style = style_res


func set_telemetry(
	new_speed_kmh: float,
	new_rpm: float,
	new_max_rpm: float,
	new_gear: String,
	new_redline: bool = false
) -> void:
	_has_direct_telemetry = true
	var prev_red := is_redline
	speed_kmh = maxf(0.0, new_speed_kmh)
	rpm = maxf(0.0, new_rpm)
	max_rpm = maxf(1000.0, new_max_rpm)
	gear_label = new_gear
	is_redline = new_redline
	if speed_smooth_speed <= 0.0 or not is_inside_tree():
		_display_speed_kmh = speed_kmh
	if rpm_smooth_speed <= 0.0 or not is_inside_tree():
		_display_rpm = rpm
		_peak_rpm = maxf(_peak_rpm, _display_rpm)
	if prev_red != is_redline:
		redline_changed.emit(is_redline)
	_sync_arc_node()
	queue_redraw()
	telemetry_updated.emit(float(get_display_speed()), rpm, gear_label)


func set_speed_only(new_speed_kmh: float) -> void:
	_has_direct_telemetry = true
	speed_kmh = maxf(0.0, new_speed_kmh)
	if speed_smooth_speed <= 0.0 or not is_inside_tree():
		_display_speed_kmh = speed_kmh
	queue_redraw()


func set_rpm_only(new_rpm: float, new_max_rpm: float = -1.0, new_redline: bool = false) -> void:
	_has_direct_telemetry = true
	rpm = maxf(0.0, new_rpm)
	if new_max_rpm > 0.0:
		max_rpm = maxf(1000.0, new_max_rpm)
	is_redline = new_redline
	if rpm_smooth_speed <= 0.0 or not is_inside_tree():
		_display_rpm = rpm
	_sync_arc_node()
	queue_redraw()


func set_gear_only(new_gear: String) -> void:
	_has_direct_telemetry = true
	gear_label = new_gear
	queue_redraw()


func bind_vehicle(vehicle: Node) -> void:
	_bound_vehicle = vehicle
	if _bound_vehicle != null:
		_poll_vehicle_telemetry()


func get_display_speed() -> int:
	var raw := _target_speed_kmh() if Engine.is_editor_hint() or speed_smooth_speed <= 0.0 else _display_speed_kmh
	var converted := raw * speed_scale
	if speed_units == SpeedUnits.MPH:
		converted *= KMH_TO_MPH
	return int(round(maxf(0.0, converted)))


func get_rpm_ratio() -> float:
	var active_rpm := _target_rpm_value() if Engine.is_editor_hint() or rpm_smooth_speed <= 0.0 else _display_rpm
	var dial_max := maxf(8000.0, maxf(max_rpm, 1000.0)) if arc_style == ArcRenderStyle.ARC_DIAL and arc_geometry == ArcShaderGeometry.QUARTER_CIRCLE else maxf(max_rpm, 1000.0)
	return clampf(active_rpm / dial_max, 0.0, 1.0)


func is_atlas_ready() -> bool:
	return _atlas != null and _atlas.ready


func get_atlas() -> RallyHudSpriteAtlas:
	return _atlas


func rebuild_atlas() -> bool:
	if _atlas == null:
		_atlas = RallyHudSpriteAtlas.new()
	var sheet_to_use: Texture2D = sprite_sheet
	var keyout_to_use: int = int(bg_keyout)
	var pad_to_use: int = slice_pad_px
	if sheet_to_use == null and sync_from_hud_style and hud_style != null:
		sheet_to_use = hud_style.sprite_sheet
		keyout_to_use = int(hud_style.keyout_mode)
		pad_to_use = hud_style.slice_pad_px
	var regions: Dictionary = {}
	if use_custom_regions:
		regions = {
			"arc": region_arc_norm,
			"bar_stepped": region_bar_stepped_norm,
			"bar_blocks": region_bar_blocks_norm,
			"big_digits": region_big_digits_norm,
			"small_digits": region_small_digits_norm,
			"labels": region_labels_norm,
			"gears": region_gears_norm,
		}
	var ok := _atlas.build(sheet_to_use, keyout_to_use, pad_to_use, regions)
	_sync_arc_node()
	_sync_speed_box_visibility()
	atlas_rebuilt.emit(ok)
	return ok


func _on_hud_style_changed() -> void:
	_apply_hud_style_sync()
	rebuild_atlas()
	queue_redraw()


func _apply_hud_style_sync() -> void:
	if not sync_from_hud_style or hud_style == null:
		return
	speed_digit_tint = hud_style.text_primary_color
	leading_zero_alpha = hud_style.dim_zero_alpha
	arc_active_tint = hud_style.accent_warm_color
	arc_mid_tint = hud_style.panel_accent_color
	arc_hot_tint = hud_style.accent_hot_color
	gear_redline_tint = hud_style.accent_hot_color
	backdrop_color = hud_style.panel_bg_color
	backdrop_border_color = hud_style.panel_border_color
	backdrop_border_width = hud_style.border_width
	backdrop_corner_radius = hud_style.corner_radius
	pixel_filter = hud_style.pixel_crisp_filtering


func _apply_filter_mode() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if pixel_filter else CanvasItem.TEXTURE_FILTER_LINEAR
	if _arc_node != null:
		_arc_node.texture_filter = texture_filter


func _bind_speed_box_nodes() -> void:
	if speed_box_path.is_empty():
		return
	var box := get_node_or_null(speed_box_path)
	if box == null:
		return
	_rpm_bar = box.get_node_or_null("RPMBar") as ProgressBar
	_speed_label = box.get_node_or_null("SpeedLabel") as Label
	_speed_unit_lbl = box.get_node_or_null("SpeedUnit") as Label
	_gear_label_node = box.get_node_or_null("GearLabel") as Label
	_drivetrain_lbl = box.get_node_or_null("DrivetrainLabel") as Label
	_rpm_caption_lbl = box.get_node_or_null("RpmCaption") as Label


func _resolve_bound_vehicle() -> void:
	if not vehicle_path.is_empty():
		var explicit_node := get_node_or_null(vehicle_path)
		if explicit_node != null:
			_bound_vehicle = explicit_node
			return
	var stage_nodes := get_tree().get_nodes_in_group("rally_stage")
	for st in stage_nodes:
		var car_prop: Variant = st.get("car")
		if car_prop is Node:
			_bound_vehicle = car_prop as Node
			return
	var car_nodes := get_tree().get_nodes_in_group("rally_car")
	if not car_nodes.is_empty():
		_bound_vehicle = car_nodes[0]


func _poll_vehicle_telemetry() -> void:
	if _bound_vehicle == null or not is_instance_valid(_bound_vehicle):
		_resolve_bound_vehicle()
	if _bound_vehicle == null:
		return
	var v_sp: Variant = _bound_vehicle.get("speed_kmh")
	var v_rpm: Variant = _bound_vehicle.get("current_rpm")
	var v_max: Variant = _bound_vehicle.get("max_rpm")
	var v_red: Variant = _bound_vehicle.get("motor_is_redline")
	if v_sp is float or v_sp is int:
		speed_kmh = maxf(0.0, float(v_sp))
	if v_rpm is float or v_rpm is int:
		rpm = maxf(0.0, float(v_rpm))
	if v_max is float or v_max is int:
		max_rpm = maxf(1000.0, float(v_max))
	if v_red is bool:
		is_redline = bool(v_red)
	if _bound_vehicle.has_method("get_gear_label"):
		gear_label = str(_bound_vehicle.call("get_gear_label"))
	if _bound_vehicle.has_method("get_transmission_label"):
		transmission_text = str(_bound_vehicle.call("get_transmission_label"))
	if _bound_vehicle.has_method("get_drivetrain_label"):
		drivetrain_text = str(_bound_vehicle.call("get_drivetrain_label"))


func _poll_speed_box_telemetry() -> void:
	if _rpm_bar != null:
		rpm = _rpm_bar.value
		max_rpm = maxf(1000.0, _rpm_bar.max_value)
	if _speed_label != null:
		var digits := ""
		for i in range(_speed_label.text.length()):
			var ch := _speed_label.text[i]
			if ch >= "0" and ch <= "9":
				digits += ch
		if not digits.is_empty():
			var raw_val := float(int(digits))
			if speed_units == SpeedUnits.MPH and _speed_unit_lbl != null and _speed_unit_lbl.text.to_lower().contains("мил"):
				speed_kmh = raw_val / KMH_TO_MPH
			else:
				speed_kmh = raw_val
	if _gear_label_node != null:
		gear_label = _gear_label_node.text
	if _drivetrain_lbl != null and _drivetrain_lbl.visible:
		drivetrain_text = _drivetrain_lbl.text


func _target_speed_kmh() -> float:
	if (Engine.is_editor_hint() or data_source == DataSource.EDITOR_PREVIEW) and preview_in_editor:
		if Engine.is_editor_hint() and preview_animate:
			return 40.0 + 180.0 * (0.5 + 0.5 * sin(_pulse_time * 0.9))
		return preview_speed_kmh
	return speed_kmh


func _target_rpm_value() -> float:
	if (Engine.is_editor_hint() or data_source == DataSource.EDITOR_PREVIEW) and preview_in_editor:
		if Engine.is_editor_hint() and preview_animate:
			return max_rpm * (0.25 + 0.75 * (0.5 + 0.5 * sin(_pulse_time * 1.4)))
		return preview_rpm
	return rpm


func _effective_gear_info() -> Dictionary:
	var raw := preview_gear if ((Engine.is_editor_hint() or data_source == DataSource.EDITOR_PREVIEW) and preview_in_editor) else gear_label
	var up := raw.to_upper()
	var mode := transmission_text
	if mode.is_empty():
		if up.ends_with(" A") or up.contains("AUTO") or up.contains("АВТО"):
			mode = "АВТО"
		elif up.ends_with(" M") or up.contains("MAN") or up.contains("РУЧ") or up.contains("МКПП"):
			mode = "МКПП"
	var cleaned := up.replace("КПП", "").replace("GEAR", "").strip_edges()
	var g := "1"
	for i in range(cleaned.length()):
		var ch := cleaned[i]
		if (ch >= "0" and ch <= "9") or ch == "R" or ch == "З" or ch == "N" or ch == "Н":
			g = ch
			break
	return {"gear": g, "mode": mode}


func _effective_gear_text() -> String:
	var info := _effective_gear_info()
	return str(info.get("gear", "N"))


func _is_redline_effective() -> bool:
	if is_redline:
		return true
	var active_rpm := _target_rpm_value() if Engine.is_editor_hint() else _display_rpm
	if redline_rpm > 0.0:
		return active_rpm >= redline_rpm
	return (active_rpm / maxf(max_rpm, 1000.0)) >= redline_ratio


func _sync_speed_box_visibility() -> void:
	if not sync_speed_box_visibility or speed_box_path.is_empty() or not is_inside_tree():
		return
	if not visible:
		return
	var box := get_node_or_null(speed_box_path) as Control
	if box != null:
		box.visible = not is_atlas_ready()


func _ensure_arc_node() -> void:
	if _arc_node != null and is_instance_valid(_arc_node):
		return
	_arc_node = get_node_or_null("ArcRect") as TextureRect
	if _arc_node == null:
		_arc_node = TextureRect.new()
		_arc_node.name = "ArcRect"
		_arc_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_arc_node.stretch_mode = TextureRect.STRETCH_SCALE
		_arc_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_arc_node.show_behind_parent = true
		add_child(_arc_node)
	var sh := Shader.new()
	sh.code = ARC_SHADER_CODE
	_arc_mat = ShaderMaterial.new()
	_arc_mat.shader = sh
	_arc_node.material = _arc_mat
	_arc_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if pixel_filter else CanvasItem.TEXTURE_FILTER_LINEAR


func _sync_arc_node() -> void:
	if _arc_node == null:
		return
	var use_dial := show_rpm_bar and arc_style == ArcRenderStyle.ARC_DIAL and _atlas != null and _atlas.ready and _atlas.tex != null
	if not use_dial:
		_arc_node.visible = false
		return

	_arc_node.visible = true
	_arc_node.texture = _atlas.tex

	var ctrl_h := self.size.y
	var arc_h := ctrl_h * arc_height_ratio * content_scale
	var arc_aspect := _atlas.arc_rect.size.x / maxf(_atlas.arc_rect.size.y, 1.0)
	_arc_node.size = Vector2(arc_h * arc_aspect, arc_h)
	_arc_node.pivot_offset = _arc_node.size * 0.5
	var punch_sc := Vector2.ONE * (1.0 + 0.035 * _widget_punch)
	var total_offset := _shake_offset + Vector2(0.0, 3.0 * _widget_punch)
	_arc_node.scale = punch_sc
	_arc_node.position = arc_offset + content_offset + total_offset

	if _arc_mat != null:
		var max_r := maxf(max_rpm, 1000.0)
		var dial_max := maxf(8000.0, max_r) if arc_geometry == ArcShaderGeometry.QUARTER_CIRCLE else max_r
		var active_rpm := _target_rpm_value() if Engine.is_editor_hint() else _display_rpm
		var fill_r := clampf(active_rpm / dial_max, 0.0, 1.0)
		var peak_r := clampf(_peak_rpm / dial_max, 0.0, 1.0)
		var red_start := clampf(max_r * redline_ratio / dial_max, 0.5, 0.98)
		var pulse_val := 0.0 if Engine.is_editor_hint() else (0.5 + 0.5 * sin(_pulse_time))

		_arc_mat.set_shader_parameter("arc_uv", _atlas.arc_uv_rect())
		_arc_mat.set_shader_parameter("fill_ratio", fill_r)
		_arc_mat.set_shader_parameter("peak_ratio", peak_r)
		_arc_mat.set_shader_parameter("redline_ratio", red_start)
		_arc_mat.set_shader_parameter("pulse", pulse_val)
		_arc_mat.set_shader_parameter("shift_flash", _shift_flash)
		_arc_mat.set_shader_parameter("geometry_mode", 0.0 if arc_geometry == ArcShaderGeometry.QUARTER_CIRCLE else 1.0)
		_arc_mat.set_shader_parameter("quarter_pivot", arc_quarter_pivot)
		_arc_mat.set_shader_parameter("radial_center", arc_radial_center)
		_arc_mat.set_shader_parameter("angle_start_deg", arc_start_deg)
		_arc_mat.set_shader_parameter("angle_sweep_deg", arc_sweep_deg)
		_arc_mat.set_shader_parameter("tip_glow", arc_tip_glow)
		_arc_mat.set_shader_parameter("tint_active", arc_active_tint)
		_arc_mat.set_shader_parameter("tint_mid", arc_mid_tint)
		_arc_mat.set_shader_parameter("tint_hot", arc_hot_tint)
		_arc_mat.set_shader_parameter("tint_dim", arc_dim_tint)
		_arc_mat.set_shader_parameter("tint_peak", arc_peak_tint)


func _draw() -> void:
	var w := self.size.x
	var h := self.size.y
	if w <= 2.0 or h <= 2.0:
		return

	if draw_backdrop:
		_draw_backdrop_plate(Rect2(Vector2.ZERO, Vector2(w, h)))

	if _atlas == null or not _atlas.ready or _atlas.tex == null:
		return

	var max_r := maxf(max_rpm, 1000.0)
	var active_rpm := _target_rpm_value() if Engine.is_editor_hint() else _display_rpm
	var rpm_norm := clampf(active_rpm / max_r, 0.0, 1.0)
	var pulse_val := 0.0 if Engine.is_editor_hint() else (0.5 + 0.5 * sin(_pulse_time))

	var center := Vector2(w, h) * 0.5
	var punch_sc := Vector2.ONE * (1.0 + 0.035 * _widget_punch) * content_scale
	var total_offset := _shake_offset + Vector2(0.0, 3.0 * _widget_punch) + content_offset
	draw_set_transform(center + total_offset - center * punch_sc, 0.0, punch_sc)

	if show_underglow:
		var glow_col := Color(0.15, 0.35, 0.65, 0.04).lerp(Color(arc_active_tint.r, arc_active_tint.g, arc_active_tint.b, 0.13), clampf(rpm_norm * 1.1, 0.0, 1.0))
		if rpm_norm >= redline_ratio:
			glow_col = glow_col.lerp(Color(arc_hot_tint.r, arc_hot_tint.g, arc_hot_tint.b, 0.22 + 0.08 * pulse_val), (rpm_norm - redline_ratio) / maxf(0.01, 1.0 - redline_ratio))
		if _shift_flash > 0.01:
			glow_col = glow_col.lerp(Color(1.0, 0.85, 0.35, 0.24), _shift_flash * 0.6)
		draw_circle(Vector2(w * 0.56, h * 0.54), h * 0.44, glow_col)
		draw_circle(Vector2(w * 0.56, h * 0.54), h * 0.26, Color(glow_col.r, glow_col.g, glow_col.b, glow_col.a * 0.8))

	var start_x := w * digit_start_x_ratio

	if show_rpm_bar and arc_style != ArcRenderStyle.ARC_DIAL:
		var bar_h := clampf(h * 0.16, 12.0, 30.0)
		var bar_kind := RallyHudSpriteAtlas.BarKind.STEPPED if arc_style == ArcRenderStyle.SEGMENTED_BAR_STEPPED else RallyHudSpriteAtlas.BarKind.BLOCKS
		var seg_rect := Rect2(8.0 + arc_offset.x, 8.0 + arc_offset.y, w - 16.0, bar_h)
		_atlas.draw_segmented_bar(
			self,
			seg_rect,
			rpm_norm,
			bar_kind,
			arc_active_tint,
			arc_dim_tint,
			arc_hot_tint,
			redline_ratio,
			segmented_preserve_colors
		)

	var spd_int := get_display_speed()
	var spd_str := str(spd_int).lpad(min_speed_digits, "0")
	var base_digit_h := h * digit_height_ratio
	var digit_y := h * digit_y_ratio + speed_offset.y
	var sp_x := start_x + speed_offset.x
	var speed_end_x := sp_x

	if show_speed_digits:
		var spd_scale := 1.0 + 0.035 * _speed_pop
		var d_h := base_digit_h * spd_scale
		var d_y := digit_y - (d_h - base_digit_h) * 0.5
		var slot_w := d_h * digit_slot_aspect
		var tint_sp := speed_digit_tint
		if _speed_pop > 0.05:
			tint_sp = tint_sp.lerp(Color(1.0, 0.92, 0.72, speed_digit_tint.a), _speed_pop * 0.5)
		var drawn_w := _atlas.draw_digits(
			self,
			spd_str,
			Vector2(sp_x, d_y),
			d_h,
			speed_use_small_digits,
			tint_sp,
			dim_leading_zeros,
			leading_zero_alpha,
			digit_gap_px,
			digit_slot_aspect
		)
		speed_end_x = sp_x + maxf(drawn_w, float(spd_str.length()) * slot_w)

	if show_unit_label:
		var use_mph := speed_units == SpeedUnits.MPH
		var unit_src := _atlas.unit_mph if use_mph else _atlas.unit_kmh
		if unit_src.size.x > 1.0 and unit_src.size.y > 1.0:
			var unit_h := h * unit_height_ratio
			var unit_w := unit_h * (unit_src.size.x / unit_src.size.y)
			var unit_x := speed_end_x + unit_offset.x
			var unit_y := digit_y + base_digit_h - unit_h + unit_offset.y
			var max_unit_w := maxf(w - unit_x - 4.0, 20.0)
			if unit_w > max_unit_w:
				var sc_u := max_unit_w / unit_w
				unit_w *= sc_u
				unit_h *= sc_u
				unit_y = digit_y + base_digit_h - unit_h + unit_offset.y
			draw_texture_rect_region(_atlas.tex, Rect2(unit_x, unit_y, unit_w, unit_h), unit_src, unit_tint)

	if show_rpm_underline:
		var line_w := maxf((w - 14.0) - sp_x, 60.0)
		var line_y := digit_y + base_digit_h + 4.0
		draw_rect(Rect2(sp_x, line_y, line_w, 2.0), Color(1.0, 1.0, 1.0, 0.10))
		var fill_w := line_w * rpm_norm
		if fill_w > 1.0:
			var line_col := arc_active_tint.lerp(arc_hot_tint, smoothstep(0.65, 0.95, rpm_norm))
			if _shift_flash > 0.01:
				line_col = line_col.lerp(Color(1.0, 0.96, 0.7, 1.0), _shift_flash * 0.7)
			draw_rect(Rect2(sp_x, line_y, fill_w, 2.5), line_col)
			draw_circle(Vector2(sp_x + fill_w, line_y + 1.25), 2.5, Color(1.0, 0.95, 0.75, 0.95))

	var g_info := _effective_gear_info()
	var gear_str: String = str(g_info["gear"])
	var gear_mode: String = str(g_info["mode"])

	if show_gear_bar:
		_draw_gear_section(sp_x, w, h, gear_str, rpm_norm, pulse_val)

	if show_extra_info:
		var font := ThemeDB.fallback_font
		var info_parts: Array[String] = []
		if not gear_mode.is_empty():
			info_parts.append(gear_mode)
		if not drivetrain_text.is_empty():
			info_parts.append(drivetrain_text)
		elif _drivetrain_lbl != null and _drivetrain_lbl.visible and not _drivetrain_lbl.text.is_empty():
			info_parts.append(_drivetrain_lbl.text)
		else:
			info_parts.append("%d RPM" % int(round(active_rpm)))
		if not info_parts.is_empty():
			var info_str := " • ".join(info_parts)
			var info_col := sub_info_tint
			if rpm_norm >= redline_ratio:
				info_col = Color(arc_hot_tint.r, arc_hot_tint.g, arc_hot_tint.b, 0.95)
			elif rpm_norm >= 0.65:
				info_col = Color(1.0, 0.78, 0.35, 0.9)
			draw_string(font, Vector2(w - 170.0, h - 4.0), info_str, HORIZONTAL_ALIGNMENT_RIGHT, 166.0, 11, info_col)


func _draw_backdrop_plate(rect: Rect2) -> void:
	if backdrop_corner_radius <= 0:
		draw_rect(rect, backdrop_color, true)
		if backdrop_border_width > 0:
			draw_rect(rect, backdrop_border_color, false, float(backdrop_border_width))
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = backdrop_color
	sb.border_color = backdrop_border_color
	sb.set_border_width_all(backdrop_border_width)
	sb.set_corner_radius_all(backdrop_corner_radius)
	draw_style_box(sb, rect)


func _draw_gear_section(start_x: float, w: float, h: float, gear_str: String, rpm_norm: float, pulse_val: float) -> void:
	var gear_y := h * gear_y_ratio + gear_offset.y
	var gear_h := h * gear_strip_height_ratio
	var red_on := is_redline or rpm_norm >= redline_ratio

	var gear_col := gear_active_tint
	if red_on:
		gear_col = Color(gear_redline_tint.r, clampf(gear_redline_tint.g + 0.35 * pulse_val, 0.0, 1.0), gear_redline_tint.b, 1.0)
	if _gear_pop > 0.01:
		gear_col = gear_col.lerp(Color(1.35, 1.2, 0.65, 1.0), _gear_pop)

	var gp_scale := 1.0 + 0.24 * sin(_gear_pop * PI)
	var gp_lift := -3.0 * _gear_pop
	var gx0 := start_x + gear_offset.x

	if gear_render_mode == GearRenderMode.SMALL_GLYPH_ONLY:
		var wg_h := gear_h * 0.92 * gp_scale
		var wg_w := wg_h * (_atlas.word_gear.size.x / maxf(_atlas.word_gear.size.y, 1.0))
		draw_texture_rect_region(_atlas.tex, Rect2(gx0, gear_y + gp_lift, wg_w, wg_h), _atlas.word_gear, gear_col)
		var sx := gx0 + wg_w + 6.0
		_draw_gear_fallback_char(gear_str, sx, gear_y + gp_lift, wg_h, gear_col)
		return

	if gear_render_mode == GearRenderMode.FIVE_GEAR_STRIP:
		var cx := gx0
		var gap := 4.0
		var g_num := int(gear_str) if gear_str.is_valid_int() else -1
		for i in range(5):
			var g_src := _atlas.gear_items[i]
			var gw := gear_h * (g_src.size.x / maxf(g_src.size.y, 1.0))
			var is_active := (g_num == i + 1)
			var col := gear_col if is_active else gear_inactive_tint
			var sc := gp_scale if is_active else 1.0
			var dst := Rect2(
				cx + gw * (1.0 - sc) * 0.5,
				gear_y + (gp_lift if is_active else 0.0) + gear_h * (1.0 - sc) * 0.5,
				gw * sc,
				gear_h * sc
			)
			draw_texture_rect_region(_atlas.tex, dst, g_src, col)
			cx += gw + gap
		if g_num <= 0 or g_num > 5:
			var bx := cx + 2.0
			var badge_rect := Rect2(bx, gear_y + gp_lift, gear_h * 0.95, gear_h)
			draw_rect(badge_rect, Color(0.06, 0.10, 0.16, 0.92), true)
			draw_rect(badge_rect, gear_col, false, 1.5)
			_draw_gear_fallback_char(gear_str, bx + 4.0, gear_y + gp_lift + gear_h * 0.1, gear_h * 0.8, gear_col)
		return

	# ACTIVE_BADGE_AUTO: крупный бейдж для 1..5, для 6/R/N — слово ПЕРЕДАЧА + символ
	if gear_str >= "1" and gear_str <= "5":
		var g_idx := int(gear_str) - 1
		var g_src := _atlas.gear_items[g_idx]
		var g_w := gear_h * (g_src.size.x / maxf(g_src.size.y, 1.0))
		var g_center := Vector2(gx0 + g_w * 0.5, gear_y + gear_h * 0.5 + gp_lift)
		var dst := Rect2(
			g_center.x - g_w * gp_scale * 0.5,
			g_center.y - gear_h * gp_scale * 0.5,
			g_w * gp_scale,
			gear_h * gp_scale
		)
		draw_texture_rect_region(_atlas.tex, dst, g_src, gear_col)
	else:
		var wg_h := gear_h * 0.92 * gp_scale
		var wg_w := wg_h * (_atlas.word_gear.size.x / maxf(_atlas.word_gear.size.y, 1.0))
		var max_wg_w := maxf(w - gx0 - wg_h - 14.0, 24.0)
		if wg_w > max_wg_w:
			wg_w = max_wg_w
		draw_texture_rect_region(_atlas.tex, Rect2(gx0, gear_y + gp_lift, wg_w, wg_h), _atlas.word_gear, gear_col)
		_draw_gear_fallback_char(gear_str, gx0 + wg_w + 6.0, gear_y + gp_lift, wg_h, gear_col)


func _draw_gear_fallback_char(gear_str: String, x_pos: float, y_pos: float, char_h: float, col: Color) -> void:
	if gear_str.length() == 1 and gear_str >= "0" and gear_str <= "9" and _atlas.small_digits.size() == 10:
		var sd_src := _atlas.small_digits[int(gear_str)]
		var sd_w := char_h * (sd_src.size.x / maxf(sd_src.size.y, 1.0))
		draw_texture_rect_region(_atlas.tex, Rect2(x_pos, y_pos, sd_w, char_h), sd_src, col)
	else:
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(x_pos, y_pos + char_h * 0.85), gear_str, HORIZONTAL_ALIGNMENT_LEFT, -1, int(char_h * 0.9), Color(1.0, 0.35, 0.25, 1.0))
