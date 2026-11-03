## Экранный ретро-вид. Живёт настоящим ColorRect под HUD, а не создаётся
## невидимым кодом. Материал принадлежит сцене и сохраняется вместе с ней.
@tool
class_name RallyScreenLook
extends ColorRect

const SpeedFeelType = preload("res://scripts/effects/rally_speed_feel.gd")
const ShaderParam = preload("res://scripts/data/rally_shader_parameter.gd")

signal settings_changed

enum Look { CUSTOM, CLEAN, SOFT_PS1, CLASSIC_PS1 }

## Именованные варианты; exact values remain editable in CUSTOM mode.
const PRESETS := {
	Look.CLEAN: [0.0, 360, 0, 0.0, false],
	Look.SOFT_PS1: [0.65, 360, 6, 0.05, true],
	Look.CLASSIC_PS1: [1.0, 270, 5, 0.15, true],
}

@export_group("Готовый вид")
## Понятный стартовый вариант. Для точной правки выберите «Свой вид».
@export var look: Look = Look.CLASSIC_PS1:
	set(value):
		var changed := value != look
		look = value
		if changed and value != Look.CUSTOM and not _applying_preset:
			_apply_preset()
		_refresh()
## Выключает только экранный ретро-фильтр. Эффект скорости живёт отдельно.
@export var enabled: bool = true:
	set(value):
		enabled = value
		_refresh()
@export_multiline var description: String = ""

@export_group("Точные значения (только для «Свой вид»)")
@export_range(0.0, 1.0, 0.05) var strength: float = 1.0:
	set(value):
		strength = value
		_mark_custom()
		_refresh()
## Меньше строк — крупнее пиксель. Это стилизация, не ускорение рендера.
@export_range(180, 720, 1, "suffix:строк") var pixel_height: int = 270:
	set(value):
		pixel_height = value
		_mark_custom()
		_refresh()
## 0 — без ограничения палитры; 5 — классический RGB555.
@export_range(0, 8, 1, "suffix:бит/канал") var palette_bits: int = 5:
	set(value):
		palette_bits = value
		_mark_custom()
		_refresh()
## Дрожание вершин дороги и земли. Коллизии и физика не меняются.
@export_range(0.0, 1.0, 0.05) var vertex_snap: float = 0.15:
	set(value):
		vertex_snap = value
		_mark_custom()
		_refresh()
## Упорядоченный дизер сглаживает переходы ограниченной палитры.
@export var dithering: bool = true:
	set(value):
		dithering = value
		_mark_custom()
		_refresh()
## Дополнительные uniform'ы поверх выбранного вида. Имя должно совпадать с shader.
@export var custom_uniforms: Array[ShaderParam] = []

var speed_feel: SpeedFeelType = null
var _applying_preset := false
var _track_ps1 := true
var _track_bits := 5
var _track_dither := true
var _track_allows_speed := true
var _speed_kmh := 0.0
var _compare_original := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if material == null or not material is ShaderMaterial:
		material = ShaderMaterial.new()
	if (material as ShaderMaterial).shader == null:
		(material as ShaderMaterial).shader = preload("res://shaders/speed_fx.gdshader")
	_apply_material()
	_refresh()


func _validate_property(property: Dictionary) -> void:
	if property.name == "description":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
	if property.name in ["strength", "pixel_height", "palette_bits", "vertex_snap", "dithering", "custom_uniforms"] and look != Look.CUSTOM:
		property.usage = PROPERTY_USAGE_STORAGE


func _mark_custom() -> void:
	if not _applying_preset and look != Look.CUSTOM:
		look = Look.CUSTOM


func _apply_preset() -> void:
	if not PRESETS.has(look):
		return
	_applying_preset = true
	var p: Array = PRESETS[look]
	strength = p[0]
	pixel_height = p[1]
	palette_bits = p[2]
	vertex_snap = p[3]
	dithering = p[4]
	_applying_preset = false


func _refresh() -> void:
	description = "Обрабатывает картинку мира до HUD: пиксельная сетка, палитра и дизер.\n"
	description += "Материалы дороги/земли получают ту же сетку вершин; физика не меняется.\n"
	match look:
		Look.CLEAN:
			description += "Сейчас: чистая картинка без ретро-фильтра."
		Look.SOFT_PS1:
			description += "Сейчас: мягкий ретро — мелкий пиксель, спокойная палитра."
		Look.CLASSIC_PS1:
			description += "Сейчас: классический PS1 — 270 строк, RGB555, лёгкое дрожание вершин."
		_:
			description += "Сейчас: свой вид — значения ниже задают точный результат."
	_apply_material()
	notify_property_list_changed()
	settings_changed.emit()


func bind_speed(node: SpeedFeelType) -> void:
	speed_feel = node
	_apply_material()


func configure_for_track(track: Resource) -> void:
	_track_ps1 = track != null and bool(track.get("ps1_style"))
	_track_bits = int(track.get("color_banding")) if track != null else 5
	_track_dither = track != null and bool(track.get("dither_fog"))
	_track_allows_speed = track == null or bool(track.get("enable_speed_fx"))
	_apply_material()


func set_preview_speed(speed_kmh: float) -> void:
	_speed_kmh = speed_kmh
	_apply_material()


func set_compare_original(value: bool) -> void:
	_compare_original = value
	_apply_material()


func _apply_material() -> void:
	var mat := material as ShaderMaterial
	if mat == null:
		return
	var retro_on := enabled and _track_ps1 and not _compare_original
	var bits := palette_bits if look == Look.CUSTOM else int(PRESETS.get(look, PRESETS[Look.CLASSIC_PS1])[2])
	var levels := (1 << clampi(bits, 0, 8)) - 1 if retro_on and bits > 0 else 0
	mat.set_shader_parameter("retro_strength", clampf(strength, 0.0, 1.0) if retro_on else 0.0)
	mat.set_shader_parameter("resolution_y", float(pixel_height))
	mat.set_shader_parameter("color_levels", float(levels))
	mat.set_shader_parameter("dither_strength", 1.0 if retro_on and dithering and _track_dither else 0.0)
	var blur := 0.012
	var vignette := 0.12
	var intensity := 0.0
	if speed_feel != null and not _compare_original:
		blur = speed_feel.edge_blur_percent / 100.0
		vignette = speed_feel.vignette_percent / 100.0
		intensity = speed_feel.intensity_for(_speed_kmh, _track_allows_speed)
	mat.set_shader_parameter("blur_strength", blur)
	mat.set_shader_parameter("vignette_strength", vignette)
	mat.set_shader_parameter("speed_intensity", intensity)
	ShaderParam.apply_all(mat, custom_uniforms)


## Совместимость: после загрузки сцены ресурс этапа становится зеркалом узлов.
func write_settings(cfg: Resource) -> void:
	if cfg == null:
		return
	cfg.set("ps1_enabled", enabled)
	cfg.set("retro_style_strength", strength)
	cfg.set("retro_resolution_height", pixel_height)
	cfg.set("retro_vertex_snap", vertex_snap)
	cfg.set("retro_color_bits_override", palette_bits)
	cfg.set("screen_shader_overrides", custom_uniforms)


func adopt_settings(cfg: Resource) -> void:
	if cfg == null:
		return
	_applying_preset = true
	look = Look.CUSTOM
	enabled = bool(cfg.get("ps1_enabled"))
	strength = float(cfg.get("retro_style_strength"))
	pixel_height = int(cfg.get("retro_resolution_height"))
	vertex_snap = float(cfg.get("retro_vertex_snap"))
	var bits := int(cfg.get("retro_color_bits_override"))
	palette_bits = bits if bits >= 0 else 5
	dithering = true
	var overrides: Array = cfg.get("screen_shader_overrides")
	custom_uniforms.assign(overrides)
	_applying_preset = false
	_refresh()
