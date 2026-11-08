## Эффект скорости как отдельный объект сцены.
## Выбирайте готовый характер, а не угадывайтедробные uniform'ы.
## Точные значения открываются только в режиме «Свой характер».
##
## Единственный источник истины для эффекта скорости — этот узел.
## Шаблон `scenes/effects/speed_effect.tscn` используют все заезды, поэтому
## правка здесь меняет эффект везде. Uniform'ы материала экрана и старый
## `RallyStageSettings` — не настройки, а зеркало/миграция.
@tool
class_name RallySpeedFeel
extends Node

signal settings_changed

enum Feel { CUSTOM, OFF, COMFORT, EXPRESSIVE, ARCADE }

## enabled, start_kmh, full_kmh, strength, edge_blur%, vignette%, blur_gain,
## cockpit_scale, edge_stretch%.
const PRESETS := {
	Feel.OFF: [false, 65.0, 180.0, 1.0, 0.0, 0.0, 1.0, 0.8, 0.0],
	Feel.COMFORT: [true, 90.0, 210.0, 0.6, 0.4, 6.0, 1.2, 0.7, 0.6],
	Feel.EXPRESSIVE: [true, 65.0, 180.0, 1.0, 1.0, 12.0, 2.0, 0.8, 2.0],
	Feel.ARCADE: [true, 45.0, 160.0, 1.2, 1.6, 18.0, 2.6, 0.9, 3.2],
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
## Во сколько раз усиливается периферийное размытие сзади/в кабине.
## 1 — прежняя сила; капот всегда использует 1.
@export_range(1.0, 4.0, 0.1) var blur_gain: float = 2.4:
	set(value):
		blur_gain = value
		_mark_custom()
		_refresh()
## Насколько сильно кабина получает усиленное размытие относительно вида сзади.
@export_range(0.0, 1.0, 0.05) var cockpit_scale: float = 0.8:
	set(value):
		cockpit_scale = value
		_mark_custom()
		_refresh()
## Растяжение картинки от центра к краям, % экрана. Это тот самый «поток»,
## который читается как скорость, но не трясёт кадр: центр остаётся резким.
@export_range(0.0, 6.0, 0.1, "suffix:% экрана") var edge_stretch_percent: float = 2.0:
	set(value):
		edge_stretch_percent = value
		_mark_custom()
		_refresh()

var _applying_preset := false


func _ready() -> void:
	# Пресет — это выбор пользователя, а точные числа — только его следствие.
	# В .tscn числа пресета тоже сохраняются (иначе их нечем было бы читать
	# старому коду), и при загрузке они приходили бы ПОСЛЕ `feel`, превращая
	# выбранный характер в «Свой характер». Поэтому пресет применяется заново
	# уже после того, как все свойства сцены прочитаны.
	if feel != Feel.CUSTOM:
		_apply_preset()
	_refresh()


func _validate_property(property: Dictionary) -> void:
	if property.name == "description":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
	if property.name in ["start_kmh", "full_kmh", "strength", "edge_blur_percent", "vignette_percent", "blur_gain", "cockpit_scale", "edge_stretch_percent"] and feel != Feel.CUSTOM:
		property.usage = PROPERTY_USAGE_STORAGE


## Ручная правка числа переводит эффект в «Свой характер» — но только когда
## узел уже живёт в сцене. Пока сцена загружается, сеттеры получают значения
## пресета, и переключать из-за них режим нельзя.
func _mark_custom() -> void:
	if _applying_preset or not is_inside_tree():
		return
	if feel == Feel.CUSTOM:
		return
	feel = Feel.CUSTOM
	# Точные значения спрятаны у пресетов. Без этого вызова они остаются
	# невидимыми в инспекторе до перезапуска редактора — и кажется, что
	# настройка «не сохранилась».
	notify_property_list_changed()


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
	blur_gain = p[6]
	cockpit_scale = p[7]
	edge_stretch_percent = p[8] if p.size() > 8 else 0.0
	_applying_preset = false


func _refresh() -> void:
	if full_kmh <= start_kmh:
		# Порог полного эффекта всегда выше порога начала, иначе скорость
		# делится на ноль и эффект молча пропадает.
		full_kmh = start_kmh + 1.0
		return
	description = "Меняет только ощущение скорости: края кадра мягко размываются, темнеют и тянутся от центра.\n"
	description += "Центр (дорога и прицел) остаётся резким; капот сохраняет прежний спокойный вариант.\n"
	description += "Кадр не трясётся: скорость дают ускорение, поток в мире и ветер, а не дрожь камеры.\n"
	description += "PS1-пиксели, палитра, дождь и снег не изменяются.\n"
	if not enabled:
		description += "Сейчас: выключено."
	else:
		description += "Сейчас: начало %.0f км/ч, полный эффект %.0f км/ч." % [start_kmh, full_kmh]
	notify_property_list_changed()
	settings_changed.emit()


## Разовая миграция старого RallyStageSettings в узел (кнопка «Перенести
## старый ресурс в эффекты сцены» у корня этапа). Обратной записи нет: этот
## узел — единственное место, где живут числа эффекта скорости.
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
	blur_gain = float(cfg.get("speed_blur_gain"))
	cockpit_scale = float(cfg.get("speed_cockpit_scale"))
	var stored_stretch: Variant = cfg.get("speed_edge_stretch")
	edge_stretch_percent = float(stored_stretch if stored_stretch != null else 0.02) * 100.0
	_applying_preset = false
	_refresh()


func intensity_for(speed_kmh: float, track_allows: bool) -> float:
	if not enabled or not track_allows:
		return 0.0
	var span := maxf(1.0, full_kmh - start_kmh)
	return clampf((speed_kmh - start_kmh) / span * strength, 0.0, 1.0)


## Почему эффект сейчас молчит. Пустая строка — всё работает.
## Нужен этапу, чтобы в консоли было видно причину, а не тихий ноль.
func inactive_reason(speed_kmh: float) -> String:
	if not enabled:
		return "узел VisualEffects/Speed выключен (характер «Выключено» или enabled = false)"
	if strength <= 0.0:
		return "сила эффекта скорости равна 0"
	if full_kmh <= start_kmh:
		return "порог полного эффекта не выше порога начала (%.0f км/ч)" % start_kmh
	if speed_kmh < start_kmh:
		return "скорость %.0f км/ч ниже порога %.0f км/ч" % [speed_kmh, start_kmh]
	return ""
