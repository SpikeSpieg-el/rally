## Экранный ретро-вид. Живёт настоящим ColorRect под HUD, а не создаётся
## невидимым кодом. Материал принадлежит сцене и сохраняется вместе с ней.
##
## Uniform'ы материала — это зеркало настроек: ретро-часть берётся из этого
## узла, скорость — из `VisualEffects/Speed`. Руками параметры материала
## править не нужно: код пересчитывает их из узлов.
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
var _camera_mode := 0
var _compare_original := false
## Дополнительные uniform'ы нужно применить заново после правки настроек.
var _params_dirty := true
var _warned_no_speed := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if material == null or not material is ShaderMaterial:
		material = ShaderMaterial.new()
	if (material as ShaderMaterial).shader == null:
		(material as ShaderMaterial).shader = preload("res://shaders/speed_fx.gdshader")
	# Как и у эффекта скорости: выбранный вид должен пережить перезапуск
	# сцены. Сохранённые числа пресета не имеют права превращать его в
	# «Свой вид» при каждой загрузке .tscn.
	if look != Look.CUSTOM:
		_apply_preset()
	_params_dirty = true
	_refresh()


func _validate_property(property: Dictionary) -> void:
	if property.name == "description":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
	if property.name in ["strength", "pixel_height", "palette_bits", "vertex_snap", "dithering", "custom_uniforms"] and look != Look.CUSTOM:
		property.usage = PROPERTY_USAGE_STORAGE


## См. комментарий у RallySpeedFeel._mark_custom(): ручная правка числа
## включает «Свой вид» только у узла, который уже стоит в сцене.
func _mark_custom() -> void:
	if _applying_preset or not is_inside_tree():
		return
	if look == Look.CUSTOM:
		return
	look = Look.CUSTOM
	notify_property_list_changed()


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
	_params_dirty = true
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
	_params_dirty = true
	_apply_material()


## Страховка: если этап не успел связать экран с узлом скорости, находим его
## сами по стандартному пути. Без этого экран молча оставался на числах
## материала, и эффект выглядел как «ничего не происходит».
func _bind_missing_speed() -> void:
	if speed_feel != null or not is_inside_tree():
		return
	var node := get_node_or_null("../../VisualEffects/Speed") as SpeedFeelType
	if node != null:
		bind_speed(node)


## `null` значит «трассы ещё нет», а не «выключить пиксели». Иначе загрузка
## сцены без ресурса трассы гасила ретро-фильтр и сохраняла нули в .tscn.
func configure_for_track(track: Resource) -> void:
	if track == null:
		_apply_material()
		return
	_track_ps1 = bool(track.get("ps1_style"))
	var bits: Variant = track.get("color_banding")
	_track_bits = int(bits) if bits != null else 5
	var dither: Variant = track.get("dither_fog")
	_track_dither = bool(dither) if dither != null else true
	var allows: Variant = track.get("enable_speed_fx")
	_track_allows_speed = bool(allows) if allows != null else true
	_params_dirty = true
	_apply_material()


func set_preview_speed(speed_kmh: float, camera_mode: int = -1) -> void:
	_speed_kmh = speed_kmh
	if camera_mode >= 0:
		_camera_mode = clampi(camera_mode, 0, 2)
	_apply_material()


func set_compare_original(value: bool) -> void:
	_compare_original = value
	_params_dirty = true
	_apply_material()


## Почему эффект скорости сейчас не виден. Пустая строка — всё работает.
func speed_blocked_reason() -> String:
	if _compare_original:
		return "включено сравнение «Показать оригинал»"
	if speed_feel == null:
		return "экран не связан с узлом VisualEffects/Speed"
	if not _track_allows_speed:
		return "трасса запрещает эффект: enable_speed_fx = false"
	return speed_feel.inactive_reason(_speed_kmh)


func _apply_material() -> void:
	var mat := material as ShaderMaterial
	if mat == null:
		return
	var retro_on := enabled and _track_ps1 and not _compare_original
	var bits := palette_bits if look == Look.CUSTOM else int(PRESETS.get(look, PRESETS[Look.CLASSIC_PS1])[2])
	var levels := (1 << clampi(bits, 0, 8)) - 1 if retro_on and bits > 0 else 0
	_set_param(mat, "retro_strength", clampf(strength, 0.0, 1.0) if retro_on else 0.0)
	_set_param(mat, "resolution_y", float(pixel_height))
	_set_param(mat, "color_levels", float(levels))
	_set_param(mat, "dither_strength", 1.0 if retro_on and dithering and _track_dither else 0.0)
	# Скорость приходит только от узла Speed. Без него материал остаётся
	# таким, каким его сохранили в сцене: молчаливые нули ломали эффект.
	if speed_feel == null:
		_bind_missing_speed()
	if speed_feel != null:
		_set_param(mat, "blur_strength", speed_feel.edge_blur_percent / 100.0)
		_set_param(mat, "vignette_strength", speed_feel.vignette_percent / 100.0)
		var intensity := 0.0 if _compare_original else speed_feel.intensity_for(
			_speed_kmh, _track_allows_speed
		)
		_set_param(mat, "speed_intensity", intensity)
		_set_param(mat, "camera_mode", _camera_mode)
		_set_param(mat, "blur_gain", speed_feel.blur_gain)
		_set_param(mat, "cockpit_scale", speed_feel.cockpit_scale)
		_set_param(mat, "speed_stretch", speed_feel.edge_stretch_percent / 100.0)
	elif not _warned_no_speed and not Engine.is_editor_hint():
		_warned_no_speed = true
		push_warning(
			"RallyScreenLook: нет узла Speed — экранный эффект скорости остаётся на значениях материала."
		)
	if _params_dirty:
		ShaderParam.apply_all(mat, custom_uniforms)
	_params_dirty = false


## Пишем uniform только когда значение реально изменилось: иначе материал
## помечается изменённым каждый кадр, а в редакторе сцена сразу становится
## «несохранённой» при открытии. Сравниваем с тем, что уже стоит в материале.
func _set_param(mat: ShaderMaterial, param: String, value: Variant) -> void:
	var current: Variant = mat.get_shader_parameter(param)
	if current != null and current == value:
		return
	mat.set_shader_parameter(param, value)


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
	_params_dirty = true
	_refresh()
