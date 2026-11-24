## Графика и экран: режим окна, разрешение, VSync, FPS, MSAA, масштабирование,
## тени, анизотропная фильтрация и ретро-экран PS1.
## Всё сохраняется в user://rally_game.cfg ([video]) и применяется сразу:
## дисплейные параметры — через DisplayServer/Engine/Viewport, ретро —
## через сцену заезда (apply_graphics_settings / apply_ps1_setting).
class_name RallyGameSettings
extends VBoxContainer

const SETTINGS_PATH := "user://rally_game.cfg"

signal ps1_enabled_changed(enabled: bool)
signal graphics_changed

## Пресеты разрешения для оконного режима (индекс — в конфиге).
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]
const RESOLUTION_LABELS: Array[String] = ["1280 × 720", "1920 × 1080", "2560 × 1440", "3840 × 2160"]
## Лимиты FPS: 0 — без ограничения.
const FPS_VALUES: Array[int] = [0, 30, 60, 120, 144, 240]
const FPS_LABELS: Array[String] = ["Без ограничения", "30", "60", "120", "144", "240"]
## MSAA: индекс совпадает с Viewport.MSAA_3D_* (0=выкл, 1=2x, 2=4x, 3=8x).
const MSAA_LABELS: Array[String] = ["Выкл", "2x", "4x", "8x"]
## Масштабирование 3D: совпадает с Viewport.Scaling3DMode (0=билинейная, 1=FSR, 2=FSR2).
const SCALING_LABELS: Array[String] = ["Билинейная", "FSR", "FSR2"]
const SHADOW_LABELS: Array[String] = ["Низкое", "Среднее", "Высокое"]
const SHADOW_SIZES: Array[int] = [1024, 2048, 4096]
const ANISO_LABELS: Array[String] = ["Выкл", "2x", "4x", "8x", "16x"]
## Палитра ретро: -1 — как на трассе, 0 — без ограничения, 5..8 — бит/канал.
const PALETTE_VALUES: Array[int] = [-1, 0, 5, 6, 7, 8]
const PALETTE_LABELS: Array[String] = ["Как на трассе", "Без ограничения", "RGB555 (5 бит)", "6 бит", "7 бит", "8 бит"]

var _loading: bool = false
var _window_mode: OptionButton
var _resolution: OptionButton
var _vsync: CheckButton
var _fps: OptionButton
var _msaa: OptionButton
var _scaling: OptionButton
var _scaling_scale: HSlider
var _scaling_scale_value: Label
var _shadows: OptionButton
var _aniso: OptionButton
var _ps1_toggle: CheckButton
var _retro_strength: HSlider
var _retro_strength_value: Label
var _retro_resolution: HSlider
var _retro_resolution_value: Label
var _retro_snap: HSlider
var _retro_snap_value: Label
var _palette: OptionButton
var _dithering: CheckButton
var _retro_rows: Array[Control] = []


# --- Статическое хранилище -------------------------------------------------

static func _cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	return cfg


static func _read(key: String, fallback: Variant) -> Variant:
	return _cfg().get_value("video", key, fallback)


static func _write(key: String, value: Variant) -> void:
	var cfg := _cfg()
	cfg.set_value("video", key, value)
	cfg.save(SETTINGS_PATH)


static func ps1_enabled() -> bool:
	return bool(_read("ps1_retro_enabled", true))


static func set_ps1_enabled(enabled: bool) -> void:
	_write("ps1_retro_enabled", enabled)


static func retro_strength() -> float:
	return float(_read("retro_strength", 1.0))


static func retro_resolution_height() -> int:
	return int(_read("retro_resolution_height", 270))


static func retro_vertex_snap() -> float:
	return float(_read("retro_vertex_snap", 0.15))


static func retro_color_bits() -> int:
	return int(_read("retro_color_bits", -1))


static func retro_dithering() -> bool:
	return bool(_read("retro_dithering", true))


static func window_mode() -> int:
	return int(_read("window_mode", 0))


static func resolution_index() -> int:
	return clampi(int(_read("resolution_index", 1)), 0, RESOLUTIONS.size() - 1)


static func vsync_enabled() -> bool:
	return bool(_read("vsync_enabled", true))


static func max_fps() -> int:
	return int(_read("max_fps", 0))


static func msaa_index() -> int:
	return clampi(int(_read("msaa_index", 0)), 0, 3)


static func scaling_mode() -> int:
	return clampi(int(_read("scaling_mode", 0)), 0, 2)


static func scaling_scale() -> float:
	return clampf(float(_read("scaling_scale", 1.0)), 0.5, 1.0)


static func shadow_quality() -> int:
	return clampi(int(_read("shadow_quality", 1)), 0, 2)


static func anisotropic_index() -> int:
	return clampi(int(_read("anisotropic_index", 0)), 0, 4)


## В браузере и на мобильной ОС по умолчанию используем более лёгкий рендер:
## WebGL 2 и телефон не должны стартовать с настольными 120 тиками физики.
static func is_low_power_runtime() -> bool:
	return OS.has_feature("web") or OS.has_feature("mobile")


static func apply_platform_defaults(viewport: Viewport = null) -> void:
	if not is_low_power_runtime():
		return
	Engine.max_fps = 60
	Engine.physics_ticks_per_second = 60
	ProjectSettings.set_setting("rendering/scaling_3d/mode", 0)
	ProjectSettings.set_setting("rendering/scaling_3d/scale", 0.72)
	ProjectSettings.set_setting(
		"rendering/lights_and_shadows/directional_shadow/size", SHADOW_SIZES[0]
	)
	if viewport != null:
		viewport.msaa_3d = 0
		viewport.scaling_3d_mode = 0
		viewport.scaling_3d_scale = 0.72


static func disable_low_power_light_shadows(root: Node) -> void:
	if root == null or not is_low_power_runtime():
		return
	for node in root.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if light != null:
			light.shadow_enabled = false


## Применить дисплейные параметры к движку. Вызывать из _ready меню/заезда.
static func apply_display(viewport: Viewport = null) -> void:
	var low_power := is_low_power_runtime()
	var fps_limit := max_fps()
	if low_power:
		fps_limit = 60 if fps_limit <= 0 else mini(fps_limit, 60)
	Engine.max_fps = fps_limit
	if low_power:
		Engine.physics_ticks_per_second = 60
	if DisplayServer.get_name() != "headless" and not OS.has_feature("web"):
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if vsync_enabled() else DisplayServer.VSYNC_DISABLED
		)
		var mode := window_mode()
		if mode == 2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif mode == 1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_size(RESOLUTIONS[resolution_index()])
	var effective_scale: float = minf(scaling_scale(), 0.72) if low_power else scaling_scale()
	var effective_scaling_mode: int = 0 if low_power else scaling_mode()
	var effective_shadow_quality: int = 0 if low_power else shadow_quality()
	ProjectSettings.set_setting("rendering/scaling_3d/mode", effective_scaling_mode)
	ProjectSettings.set_setting("rendering/scaling_3d/scale", effective_scale)
	ProjectSettings.set_setting(
		"rendering/lights_and_shadows/directional_shadow/size", SHADOW_SIZES[effective_shadow_quality]
	)
	ProjectSettings.set_setting("rendering/textures/anisotropic_filtering_level", anisotropic_index())
	if viewport != null:
		viewport.msaa_3d = 0 if low_power else msaa_index()
		viewport.scaling_3d_mode = effective_scaling_mode
		viewport.scaling_3d_scale = effective_scale


# --- UI --------------------------------------------------------------------

func _ready() -> void:
	_loading = true
	add_theme_constant_override("separation", 10)
	_build_display_section()
	_build_performance_section()
	_build_retro_section()
	_sync_all()
	_loading = false


func _section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(1.0, 0.62, 0.12, 1.0))
	add_child(label)
	return label


func _row(caption: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size = Vector2(220, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row


func _option(row: HBoxContainer, labels: Array[String]) -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(220, 0)
	option.focus_mode = Control.FOCUS_ALL
	for text in labels:
		option.add_item(text)
	row.add_child(option)
	return option


func _slider_row(caption: String, minimum: float, maximum: float, step: float) -> Array:
	var row := _row(caption)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_ALL
	row.add_child(slider)
	var value := Label.new()
	value.custom_minimum_size = Vector2(64, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return [slider, value]


func _check(caption: String) -> CheckButton:
	var row := _row(caption)
	var check := CheckButton.new()
	check.focus_mode = Control.FOCUS_ALL
	row.add_child(check)
	return check


func _build_display_section() -> void:
	_section_title("ЭКРАН")
	_window_mode = _option(_row("Режим окна"), ["Оконный", "Без рамки", "Полный экран"])
	_window_mode.item_selected.connect(_on_window_mode_changed)
	_resolution = _option(_row("Разрешение"), RESOLUTION_LABELS)
	_resolution.item_selected.connect(_on_resolution_changed)
	_vsync = _check("Вертикальная синхронизация (VSync)")
	_vsync.toggled.connect(_on_vsync_toggled)
	_fps = _option(_row("Лимит FPS"), FPS_LABELS)
	_fps.item_selected.connect(_on_fps_changed)
	if is_low_power_runtime():
		for index in range(FPS_VALUES.size()):
			if FPS_VALUES[index] == 0 or FPS_VALUES[index] > 60:
				_fps.set_item_disabled(index, true)
		_fps.tooltip_text = "В Web/mobile доступно не более 60 FPS."


func _build_performance_section() -> void:
	_section_title("ПРОИЗВОДИТЕЛЬНОСТЬ")
	_msaa = _option(_row("Сглаживание (MSAA)"), MSAA_LABELS)
	_msaa.item_selected.connect(_on_msaa_changed)
	_scaling = _option(_row("Масштабирование 3D"), SCALING_LABELS)
	_scaling.item_selected.connect(_on_scaling_changed)
	var scale_parts := _slider_row("Масштаб 3D", 0.5, 1.0, 0.05)
	_scaling_scale = scale_parts[0] as HSlider
	_scaling_scale_value = scale_parts[1] as Label
	_scaling_scale.value_changed.connect(_on_scaling_scale_changed)
	_shadows = _option(_row("Качество теней"), SHADOW_LABELS)
	_shadows.item_selected.connect(_on_shadows_changed)
	_aniso = _option(_row("Анизотропная фильтрация"), ANISO_LABELS)
	_aniso.item_selected.connect(_on_aniso_changed)
	if is_low_power_runtime():
		_msaa.disabled = true
		_msaa.tooltip_text = "Отключено в Web/mobile для повышения производительности."
		_scaling.disabled = true
		_scaling.tooltip_text = "Web/mobile использует более быстрый режим масштабирования."
		_scaling_scale.max_value = 0.72
		_scaling_scale.tooltip_text = "Можно дополнительно снизить масштаб 3D до 50%."
		_shadows.disabled = true
		_shadows.tooltip_text = "Тени отключены в Web/mobile для повышения производительности."


func _build_retro_section() -> void:
	_section_title("РЕТРО-ЭКРАН PS1")
	_ps1_toggle = _check("Ретро-экран PS1")
	_ps1_toggle.tooltip_text = "Пикселизация, ограниченная палитра и дрожание вершин."
	_ps1_toggle.toggled.connect(_on_ps1_toggled)
	var strength_parts := _slider_row("Сила эффекта", 0.0, 1.0, 0.05)
	var strength_slider := strength_parts[0] as HSlider
	_retro_strength_value = strength_parts[1] as Label
	_retro_strength = strength_slider
	_retro_strength.value_changed.connect(_on_retro_strength_changed)
	var res_parts := _slider_row("Разрешение (строк)", 180.0, 720.0, 10.0)
	var res_slider := res_parts[0] as HSlider
	_retro_resolution_value = res_parts[1] as Label
	_retro_resolution = res_slider
	_retro_resolution.value_changed.connect(_on_retro_resolution_changed)
	var snap_parts := _slider_row("Дрожание вершин", 0.0, 1.0, 0.05)
	var snap_slider := snap_parts[0] as HSlider
	_retro_snap_value = snap_parts[1] as Label
	_retro_snap = snap_slider
	_retro_snap.value_changed.connect(_on_retro_snap_changed)
	_palette = _option(_row("Палитра"), PALETTE_LABELS)
	_palette.item_selected.connect(_on_palette_changed)
	_dithering = _check("Дизер (сглаживание палитры)")
	_dithering.toggled.connect(_on_dithering_toggled)
	_retro_rows = [
		_retro_strength.get_parent() as Control,
		_retro_resolution.get_parent() as Control,
		_retro_snap.get_parent() as Control,
		_palette.get_parent() as Control,
		_dithering.get_parent() as Control,
	]


func _sync_all() -> void:
	var low_power := is_low_power_runtime()
	var effective_fps := max_fps()
	if low_power:
		effective_fps = 60 if effective_fps <= 0 else mini(effective_fps, 60)
	var effective_scale := minf(scaling_scale(), 0.72) if low_power else scaling_scale()
	_window_mode.select(window_mode())
	_resolution.select(resolution_index())
	_resolution.disabled = window_mode() == 2
	_vsync.set_pressed_no_signal(vsync_enabled())
	_fps.select(maxi(0, FPS_VALUES.find(effective_fps)))
	_msaa.select(0 if low_power else msaa_index())
	_scaling.select(0 if low_power else scaling_mode())
	_scaling_scale.set_value_no_signal(effective_scale)
	_scaling_scale_value.text = "%d%%" % roundi(effective_scale * 100.0)
	_scaling_scale.editable = low_power or scaling_mode() != 0
	_shadows.select(0 if low_power else shadow_quality())
	_aniso.select(anisotropic_index())
	_ps1_toggle.set_pressed_no_signal(ps1_enabled())
	_retro_strength.set_value_no_signal(retro_strength())
	_retro_strength_value.text = "%d%%" % roundi(retro_strength() * 100.0)
	_retro_resolution.set_value_no_signal(float(retro_resolution_height()))
	_retro_resolution_value.text = "%d" % retro_resolution_height()
	_retro_snap.set_value_no_signal(retro_vertex_snap())
	_retro_snap_value.text = "%d%%" % roundi(retro_vertex_snap() * 100.0)
	_palette.select(maxi(0, PALETTE_VALUES.find(retro_color_bits())))
	_dithering.set_pressed_no_signal(retro_dithering())
	_update_retro_rows()


func _update_retro_rows() -> void:
	for row in _retro_rows:
		row.visible = ps1_enabled()


func _apply_live() -> void:
	apply_display(get_viewport())
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("apply_graphics_settings"):
		scene.call("apply_graphics_settings")
	elif scene != null and scene.has_method("apply_ps1_setting"):
		scene.call("apply_ps1_setting", ps1_enabled())
	graphics_changed.emit()


func _on_window_mode_changed(index: int) -> void:
	if _loading:
		return
	_write("window_mode", index)
	_resolution.disabled = index == 2
	_apply_live()


func _on_resolution_changed(index: int) -> void:
	if _loading:
		return
	_write("resolution_index", index)
	_apply_live()


func _on_vsync_toggled(enabled: bool) -> void:
	if _loading:
		return
	_write("vsync_enabled", enabled)
	_apply_live()


func _on_fps_changed(index: int) -> void:
	if _loading:
		return
	_write("max_fps", FPS_VALUES[index])
	_apply_live()


func _on_msaa_changed(index: int) -> void:
	if _loading:
		return
	_write("msaa_index", index)
	_apply_live()


func _on_scaling_changed(index: int) -> void:
	if _loading:
		return
	_write("scaling_mode", index)
	_scaling_scale.editable = index != 0
	_apply_live()


func _on_scaling_scale_changed(value: float) -> void:
	_scaling_scale_value.text = "%d%%" % roundi(value * 100.0)
	if _loading:
		return
	_write("scaling_scale", value)
	_apply_live()


func _on_shadows_changed(index: int) -> void:
	if _loading:
		return
	_write("shadow_quality", index)
	_apply_live()


func _on_aniso_changed(index: int) -> void:
	if _loading:
		return
	_write("anisotropic_index", index)
	_apply_live()


func _on_ps1_toggled(enabled: bool) -> void:
	if _loading:
		return
	set_ps1_enabled(enabled)
	_update_retro_rows()
	_apply_live()
	ps1_enabled_changed.emit(enabled)


func _on_retro_strength_changed(value: float) -> void:
	_retro_strength_value.text = "%d%%" % roundi(value * 100.0)
	if _loading:
		return
	_write("retro_strength", value)
	_apply_live()


func _on_retro_resolution_changed(value: float) -> void:
	_retro_resolution_value.text = "%d" % roundi(value)
	if _loading:
		return
	_write("retro_resolution_height", roundi(value))
	_apply_live()


func _on_retro_snap_changed(value: float) -> void:
	_retro_snap_value.text = "%d%%" % roundi(value * 100.0)
	if _loading:
		return
	_write("retro_vertex_snap", value)
	_apply_live()


func _on_palette_changed(index: int) -> void:
	if _loading:
		return
	_write("retro_color_bits", PALETTE_VALUES[index])
	_apply_live()


func _on_dithering_toggled(enabled: bool) -> void:
	if _loading:
		return
	_write("retro_dithering", enabled)
	_apply_live()
