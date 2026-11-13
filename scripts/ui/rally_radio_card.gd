## Карточка «обложка + имя» для меню и гоночного HUD. Один и тот же контрол
## используется в scenes/main_menu.tscn и scenes/ui/rally_hud.tscn, поэтому
## тема и поведение не расходятся между экранами.
##
## Карточка subscribes к автозагрузке RallyRadio: при смене трека обложка
## перетекает в новую, а подписи появляются мягко, без резкого мигания.
extends PanelContainer

@export var compact: bool = false
@export var show_controls: bool = true
@export var station_override: String = ""
@export var hud_style: RallyHudStyle = null

var _radio: Node = null
var _panel_style: StyleBoxFlat = null
var _cover_a: TextureRect = null
var _cover_b: TextureRect = null
var _cover_front: int = 0
var _info: VBoxContainer = null
var _eyebrow: Label = null
var _title: Label = null
var _artist: Label = null
var _time: Label = null
var _progress: ProgressBar = null
var _progress_bg: StyleBoxFlat = null
var _progress_fill: StyleBoxFlat = null
var _accent_bar: ColorRect = null
var _mute_button: Button = null
var _next_button: Button = null
var _meta_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build()
	if hud_style != null:
		apply_hud_style(hud_style)
	call_deferred("_connect_radio")


func _build() -> void:
	var cover_size := 66.0 if compact else 76.0
	var title_size := 16 if compact else 18
	var artist_size := 12 if compact else 13
	var eyebrow_size := 10 if compact else 11
	custom_minimum_size = Vector2(0.0, 94.0 if compact else 108.0)

	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = Color(0.025, 0.040, 0.057, 0.88)
	_panel_style.border_color = Color(1.0, 0.48, 0.08, 0.85)
	_panel_style.set_border_width_all(1)
	_panel_style.border_width_left = 3
	_panel_style.set_corner_radius_all(10)
	_panel_style.content_margin_left = 10.0
	_panel_style.content_margin_right = 10.0
	_panel_style.content_margin_top = 9.0
	_panel_style.content_margin_bottom = 9.0
	_panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
	_panel_style.shadow_size = 8
	add_theme_stylebox_override("panel", _panel_style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(row)

	_accent_bar = ColorRect.new()
	_accent_bar.custom_minimum_size = Vector2(3.0, 0.0)
	_accent_bar.color = Color(1.0, 0.48, 0.08, 1.0)
	_accent_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_accent_bar)

	var cover_holder := Control.new()
	cover_holder.custom_minimum_size = Vector2(cover_size, cover_size)
	cover_holder.clip_contents = true
	cover_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cover_bg := ColorRect.new()
	cover_bg.color = Color(0.04, 0.07, 0.10, 1.0)
	cover_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover_holder.add_child(cover_bg)
	_cover_a = _make_cover()
	_cover_b = _make_cover()
	cover_holder.add_child(_cover_a)
	cover_holder.add_child(_cover_b)
	row.add_child(cover_holder)

	_info = VBoxContainer.new()
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.add_theme_constant_override("separation", 2)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_info)

	_eyebrow = _make_label("RALLY FM  •  СЕЙЧАС В ЭФИРЕ", eyebrow_size,
		Color(1.0, 0.62, 0.16, 1.0))
	_info.add_child(_eyebrow)
	_title = _make_label("ЗАГРУЗКА ЭФИРА…", title_size, Color(0.96, 0.98, 1.0, 1.0))
	_info.add_child(_title)
	_artist = _make_label("НОН-СТОП МИКС", artist_size, Color(0.62, 0.76, 0.86, 1.0))
	_info.add_child(_artist)

	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0.0, 5.0)
	_progress.min_value = 0.0
	_progress.max_value = 1.0
	_progress.step = 0.001
	_progress.show_percentage = false
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_bg = StyleBoxFlat.new()
	_progress_bg.bg_color = Color(1.0, 1.0, 1.0, 0.12)
	_progress_bg.set_corner_radius_all(3)
	_progress_fill = StyleBoxFlat.new()
	_progress_fill.bg_color = Color(1.0, 0.48, 0.08, 1.0)
	_progress_fill.set_corner_radius_all(3)
	_progress.add_theme_stylebox_override("background", _progress_bg)
	_progress.add_theme_stylebox_override("fill", _progress_fill)
	_info.add_child(_progress)

	_time = _make_label("--:-- / --:--", 10, Color(0.52, 0.64, 0.74, 1.0))
	_info.add_child(_time)

	if show_controls:
		var controls := VBoxContainer.new()
		controls.add_theme_constant_override("separation", 4)
		controls.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(controls)
		_next_button = _make_button("N  NEXT")
		_next_button.pressed.connect(_on_next_pressed)
		controls.add_child(_next_button)
		_mute_button = _make_button("M  MUTE")
		_mute_button.pressed.connect(_on_mute_pressed)
		controls.add_child(_mute_button)


func apply_hud_style(style_res: RallyHudStyle) -> void:
	hud_style = style_res
	if style_res == null or _panel_style == null:
		return
	var is_pix := style_res.is_pixel_mode()
	_panel_style.bg_color = style_res.panel_bg_color
	_panel_style.border_color = style_res.panel_accent_color
	_panel_style.set_border_width_all(style_res.border_width)
	_panel_style.border_width_left = maxi(3, style_res.accent_border_width)
	_panel_style.set_corner_radius_all(style_res.corner_radius if is_pix else 10)
	_panel_style.skew = style_res.panel_skew if is_pix else Vector2(0.06, 0.0)
	_panel_style.shadow_size = style_res.shadow_size if is_pix else 8
	add_theme_stylebox_override("panel", _panel_style)
	if _progress_bg != null:
		_progress_bg.set_corner_radius_all(style_res.corner_radius if is_pix else 3)
	if _progress_fill != null:
		_progress_fill.set_corner_radius_all(style_res.corner_radius if is_pix else 3)
	var filt := CanvasItem.TEXTURE_FILTER_NEAREST if (is_pix and style_res.pixel_crisp_filtering) else CanvasItem.TEXTURE_FILTER_LINEAR
	if _cover_a != null:
		_cover_a.texture_filter = filt
	if _cover_b != null:
		_cover_b.texture_filter = filt


func _make_cover() -> TextureRect:
	var rect := TextureRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate.a = 0.0
	return rect


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_CLICK
	button.custom_minimum_size = Vector2(80.0, 26.0)
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_color_override("font_color", Color(0.88, 0.93, 0.98, 1.0))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.11, 0.15, 0.90)
	style.border_color = Color(1.0, 1.0, 1.0, 0.14)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, style)
	return button


func _connect_radio() -> void:
	_radio = get_node_or_null("/root/RallyRadio")
	_refresh_station()
	if _radio == null:
		return
	if _radio.has_signal("track_changed"):
		var on_track := Callable(self, "_on_track_changed")
		if not _radio.is_connected("track_changed", on_track):
			_radio.connect("track_changed", on_track)
	if _radio.has_signal("state_changed"):
		var on_state := Callable(self, "_on_state_changed")
		if not _radio.is_connected("state_changed", on_state):
			_radio.connect("state_changed", on_state)
	var track = _radio.get("current_track")
	if track is Dictionary:
		_apply_track(track, false)
	_refresh_state()


func _refresh_station() -> void:
	var station := station_override
	if station.is_empty() and _radio != null and _radio.has_method("station_name"):
		station = String(_radio.call("station_name"))
	if station.is_empty():
		station = "RALLY FM"
	_eyebrow.text = "%s  •  СЕЙЧАС В ЭФИРЕ" % station


func _on_track_changed(track: Dictionary) -> void:
	_apply_track(track, true)


func _apply_track(track: Dictionary, animated: bool) -> void:
	var accent = track.get("accent", Color(1.0, 0.48, 0.08, 1.0))
	if accent is Color:
		_set_accent(accent)
	_title.text = _short(String(track.get("title", "БЕЗ НАЗВАНИЯ")), 30)
	_artist.text = _short(String(track.get("artist", "RALLY FM")), 34)
	tooltip_text = String(track.get("display_name", _title.text))
	var incoming := _cover_b if _cover_front == 0 else _cover_a
	var outgoing := _cover_a if _cover_front == 0 else _cover_b
	incoming.texture = _load_cover(String(track.get("cover_path", "")))
	_cover_front = 1 - _cover_front
	if not animated:
		incoming.modulate.a = 1.0
		outgoing.modulate.a = 0.0
		_info.modulate.a = 1.0
		return
	if _meta_tween != null and _meta_tween.is_running():
		_meta_tween.kill()
	incoming.modulate.a = 0.0
	_info.modulate.a = 0.0
	_meta_tween = create_tween().set_parallel(true)
	_meta_tween.tween_property(incoming, "modulate:a", 1.0, 0.55)
	_meta_tween.tween_property(outgoing, "modulate:a", 0.0, 0.55)
	_meta_tween.tween_property(_info, "modulate:a", 1.0, 0.38)


func _load_cover(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as Texture2D


func _set_accent(color: Color) -> void:
	_accent_bar.color = color
	_eyebrow.add_theme_color_override("font_color", color)
	if _progress_fill != null:
		_progress_fill.bg_color = color


func _on_state_changed(_playing: bool, muted: bool) -> void:
	_refresh_state(muted)


func _refresh_state(muted: bool = false) -> void:
	if _radio != null:
		muted = bool(_radio.get("is_muted"))
	if _mute_button != null:
		_mute_button.text = "M  UNMUTE" if muted else "M  MUTE"
	modulate.a = 0.72 if muted else 1.0


func _process(_delta: float) -> void:
	if _radio == null:
		return
	var length := float(_radio.call("current_length"))
	var played := float(_radio.call("current_position"))
	if length > 0.0:
		_progress.value = clampf(played / length, 0.0, 1.0)
		_time.text = "%s / %s" % [_format_time(played), _format_time(length)]
	else:
		_progress.value = 0.0
		_time.text = "--:-- / --:--"


func _format_time(seconds: float) -> String:
	var total := maxi(0, int(seconds))
	return "%02d:%02d" % [int(total / 60.0), total % 60]


func _short(text: String, limit: int) -> String:
	if text.length() <= limit:
		return text
	return text.substr(0, maxi(1, limit - 1)) + "…"


func _on_next_pressed() -> void:
	if _radio != null and _radio.has_method("skip_track"):
		_radio.call("skip_track")


func _on_mute_pressed() -> void:
	if _radio != null and _radio.has_method("toggle_mute"):
		_radio.call("toggle_mute")
