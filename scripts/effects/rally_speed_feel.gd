## Эффект скорости как отдельный объект сцены.
## Выбирайте готовый характер, а не угадывайтедробные uniform'ы.
## Точные значения открываются только в режиме «Свой характер».
@tool
class_name RallySpeedFeel
extends Node

signal settings_changed

enum Feel { CUSTOM, OFF, COMFORT, EXPRESSIVE, ARCADE }

const PRESETS := {
	Feel.OFF: [false, 65.0, 180.0, 1.0, 0.0, 0.0],
	Feel.COMFORT: [true, 90.0, 210.0, 0.6, 0.6, 6.0],
	Feel.EXPRESSIVE: [true, 65.0, 180.0, 1.0, 1.2, 12.0],
	Feel.ARCADE: [true, 45.0, 160.0, 1.4, 2.0, 20.0],
}

@export_group("Характер эффекта")
## Готовый вариант. «Свой характер» открывает точные настройки ниже.
@export var feel: Feel = Feel.EXPRESSIVE:
	set(value):
		var changed := value != feel
		feel = value
		if changed and value != Feel.CUSTOM and not _applying_preset:
			_apply_preset()
		_refresh()
## Главный выключатель. Не влияет на PS1-пиксели и палитру.
@export var enabled: bool = true:
	set(value):
		enabled = value
		_mark_custom()
		_refresh()
@export_multiline var description: String = ""

@export_group("Точные значения (только для «Свой характер»)")
@export_range(0.0, 300.0, 1.0, "suffix:км/ч") var start_kmh: float = 65.0:
	set(value):
		start_kmh = value
		_mark_custom()
		_refresh()
@export_range(20.0, 400.0, 1.0, "suffix:км/ч") var full_kmh: float = 180.0:
	set(value):
		if is_equal_approx(full_kmh, value):
			return
		full_kmh = value
		_mark_custom()
		_refresh()
@export_range(0.0, 2.0, 0.05) var strength: float = 1.0:
	set(value):
		strength = value
		_mark_custom()
		_refresh()
## Размытие только по краям кадра; центр дороги остаётся читаемым.
@export_range(0.0, 5.0, 0.1, "suffix:% экрана") var edge_blur_percent: float = 1.2:
	set(value):
		edge_blur_percent = value
		_mark_custom()
		_refresh()
@export_range(0.0, 100.0, 1.0, "suffix:%") var vignette_percent: float = 12.0:
	set(value):
		vignette_percent = value
		_mark_custom()
		_refresh()

var _applying_preset := false


func _ready() -> void:
	_refresh()


func _validate_property(property: Dictionary) -> void:
	if property.name == "description":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
	if property.name in ["start_kmh", "full_kmh", "strength", "edge_blur_percent", "vignette_percent"] and feel != Feel.CUSTOM:
		property.usage = PROPERTY_USAGE_STORAGE


func _mark_custom() -> void:
	if not _applying_preset and feel != Feel.CUSTOM:
		feel = Feel.CUSTOM


func _apply_preset() -> void:
	if not PRESETS.has(feel):
		return
	_applying_preset = true
	var p: Array = PRESETS[feel]
	enabled = p[0]
	start_kmh = p[1]
	full_kmh = p[2]
	strength = p[3]
	edge_blur_percent = p[4]
	vignette_percent = p[5]
	_applying_preset = false


func _refresh() -> void:
	if feel == Feel.CUSTOM and full_kmh <= start_kmh:
		full_kmh = start_kmh + 1.0
		return
	description = "Меняет только ощущение скорости: края кадра размываются и темнеют.\n"
	description += "PS1-пиксели, палитра, дождь и снег не изменяются.\n"
	if not enabled:
		description += "Сейчас: выключено."
	else:
		description += "Сейчас: начало %.0f км/ч, полный эффект %.0f км/ч." % [start_kmh, full_kmh]
	notify_property_list_changed()
	settings_changed.emit()


## Совместимость с ресурсом этапа: узел сцены — источник истины.
func write_settings(cfg: Resource) -> void:
	if cfg == null:
		return
	cfg.set("speed_fx_enabled", enabled)
	cfg.set("speed_fx_start_kmh", start_kmh)
	cfg.set("speed_fx_full_kmh", full_kmh)
	cfg.set("speed_effect_strength", strength)
	cfg.set("speed_blur_strength", edge_blur_percent / 100.0)
	cfg.set("vignette_strength", vignette_percent / 100.0)


func adopt_settings(cfg: Resource) -> void:
	if cfg == null:
		return
	_applying_preset = true
	feel = Feel.CUSTOM
	enabled = bool(cfg.get("speed_fx_enabled"))
	start_kmh = float(cfg.get("speed_fx_start_kmh"))
	full_kmh = float(cfg.get("speed_fx_full_kmh"))
	strength = float(cfg.get("speed_effect_strength"))
	edge_blur_percent = float(cfg.get("speed_blur_strength")) * 100.0
	vignette_percent = float(cfg.get("vignette_strength")) * 100.0
	_applying_preset = false
	_refresh()


func intensity_for(speed_kmh: float, track_allows: bool) -> float:
	if not enabled or not track_allows:
		return 0.0
	var span := maxf(1.0, full_kmh - start_kmh)
	return clampf((speed_kmh - start_kmh) / span * strength, 0.0, 1.0)
