## Экран «Колёса и пыль» — настройка эффектов колёс прямо в паузе.
##
## Панель строится по инспектору ресурсов: каждая группа @export_group становится
## вкладкой, каждое поле — строкой с названием, слайдером/переключателем/цветом
## и точным значением. Ничего не «зашито» в код панели, поэтому новые поля
## в RallyFxProfile / RallySurfaceFxProfile появляются здесь автоматически.
##
## Изменения применяются сразу (можно ставить паузу и крутить на ходу) и
## сохраняются в user://rally_wheel_fx.cfg. Кнопка «Сбросить» возвращает
## заводские значения ресурса из data/stage/default_fx_profile.tres.
extends Control

signal closed

const FxProfileType = preload("res://scripts/data/rally_fx_profile.gd")
const UiThemeType = preload("res://scripts/data/rally_ui_theme.gd")
const SAVE_PATH := "user://rally_wheel_fx.cfg"
const DEFAULT_FX_PATH := "res://data/stage/default_fx_profile.tres"
## Скрывать нечего: «детально» значит все группы профиля, включая следы шин
## и физику грунта. Список оставлен для несовместимых полей будущего.
const HIDDEN_GROUPS: Array[String] = []
const HIDDEN_FIELDS: Array[String] = ["surface_fx_enabled", "surface_fx_profiles"]

## Живой ресурс этапа. Пауза передаёт сюда s_fx() — правки сразу видны в заезде.
var fx: RallyFxProfile = null
## Машина текущего заезда: у неё просим применить профиль к живым частицам.
var car: Node = null
## Куда писать пользовательские настройки. Тесты подменяют путь на временный.
var save_path := SAVE_PATH
## Тема панели. Пусто — res://data/ui/default_ui_theme.tres.
var ui_theme: UiThemeType = null

var _tabs: TabContainer
var _surface_picker: OptionButton
var _controls: Array[Dictionary] = []
var _presets: Array[Dictionary] = []
var _status: Label
var _applying := false
var _built := false
## Пока идёт плавное закрытие, окно уже не ловит мышь, но паузу не закрывает.
var _closing := false
var _previous_focus: Control = null
var _overlay_focus: Control = null
var _fade_tween: Tween = null


func theme_cfg() -> UiThemeType:
	if ui_theme == null:
		if ResourceLoader.exists("res://data/ui/default_ui_theme.tres"):
			ui_theme = ResourceLoader.load("res://data/ui/default_ui_theme.tres") as UiThemeType
		if ui_theme == null:
			ui_theme = UiThemeType.new()
	return ui_theme


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	get_viewport().gui_focus_changed.connect(_on_gui_focus_changed)
	_build()
	hide()


## Открыть панель. Ресурс эффектов подставляет вызывающий: пауза этапа.
func open_with(profile: RallyFxProfile, target_car: Node = null) -> void:
	fx = profile
	car = target_car
	if fx != null:
		_load_saved()
	# Если узел ещё не в дереве, _ready() не успел собрать окно.
	_build()
	_kill_fade()
	_closing = false
	_rebuild_rows()
	_previous_focus = get_viewport().gui_get_focus_owner()
	show()
	mouse_filter = Control.MOUSE_FILTER_STOP
	modulate.a = 0.0
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 1.0, 0.15)
	if _tabs != null and _tabs.get_tab_count() > 0:
		_tabs.get_tab_bar().grab_focus()


func close() -> void:
	if not visible or _closing:
		return
	_closing = true
	_kill_fade()
	_save()
	# Окно гаснет плавно, но мышь отпускает сразу: под ним — пауза.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 0.0, 0.14)
	await get_tree().create_timer(0.14, true).timeout
	# За время анимации окно могли открыть снова — тогда не прячем его.
	if not _closing:
		return
	if get_tree() != null:
		hide()
	modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_closing = false
	if is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()
	closed.emit()


func is_open() -> bool:
	return visible


## Навигация геймпадом не должна уходить на кнопки паузы под окном.
func _on_gui_focus_changed(focus: Control) -> void:
	if not visible or _closing:
		return
	if focus != null and is_ancestor_of(focus):
		_overlay_focus = focus
		return
	if is_instance_valid(_overlay_focus) and _overlay_focus.is_visible_in_tree():
		_overlay_focus.grab_focus()
	elif _tabs != null and _tabs.get_tab_count() > 0:
		_tabs.get_tab_bar().grab_focus()


## Esc и «назад» на геймпаде закрывают это окно, не трогая паузу.
func _unhandled_input(event: InputEvent) -> void:
	if not visible or _closing:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _kill_fade() -> void:
	if _fade_tween != null and _fade_tween.is_running():
		_fade_tween.kill()
	_fade_tween = null


## Сброс к заводскому .tres (и к сохранённым значениям по умолчанию).
func reset_to_defaults() -> void:
	if fx == null:
		return
	# CACHE_MODE_IGNORE: живой профиль — это тот же экземпляр из кеша, и без
	# этого «заводские» значения оказались бы текущими правками пользователя.
	var fresh: RallyFxProfile = null
	if ResourceLoader.exists(DEFAULT_FX_PATH):
		fresh = ResourceLoader.load(
			DEFAULT_FX_PATH, "", ResourceLoader.CACHE_MODE_IGNORE
		) as FxProfileType
	if fresh == null:
		fresh = FxProfileType.new()
	_applying = true
	for field in _fx_fields():
		fx.set(field, fresh.get(field))
	for i in range(mini(fx.surface_fx_profiles.size(), fresh.surface_fx_profiles.size())):
		var target := fx.surface_fx_profiles[i]
		var source := fresh.surface_fx_profiles[i]
		for field in exported_names(source):
			target.set(field, source.get(field))
	_applying = false
	_rebuild_rows()
	apply_to_car()
	_save()
	_set_status("Заводские значения восстановлены.")


# ------------------------------------------------------------------ построение


func _build() -> void:
	if _built:
		return
	_built = true
	var theme_cfg_ref := theme_cfg()
	var backdrop := ColorRect.new()
	backdrop.color = theme_cfg_ref.overlay_backdrop
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	# Экран 1280×720 тоже должен вмещать окно: размер тянется к экрану.
	var viewport_size := get_viewport_rect().size
	panel.custom_minimum_size = Vector2(
		minf(980.0, viewport_size.x - 40.0), minf(720.0, viewport_size.y - 40.0)
	)
	var style := StyleBoxFlat.new()
	style.bg_color = theme_cfg_ref.panel_background
	style.border_color = theme_cfg_ref.border_accent
	style.set_border_width_all(2)
	style.border_width_top = 4
	style.set_corner_radius_all(6)
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	panel.add_child(layout)
	var title := Label.new()
	title.text = "КОЛЁСА, ПЫЛЬ И ГРЯЗЬ"
	title.add_theme_color_override("font_color", theme_cfg_ref.accent)
	title.add_theme_font_size_override("font_size", theme_cfg_ref.font_overlay_title)
	layout.add_child(title)
	var hint := Label.new()
	hint.text = (
		"Правки видны сразу и сохраняются. Готовые варианты — сверху, "
		+ "точные числа — во вкладках."
	)
	hint.add_theme_color_override("font_color", theme_cfg_ref.text_secondary)
	hint.add_theme_font_size_override("font_size", theme_cfg_ref.font_caption)
	layout.add_child(hint)
	var presets := HBoxContainer.new()
	presets.name = "Presets"
	presets.add_theme_constant_override("separation", 6)
	layout.add_child(presets)
	_tabs = TabContainer.new()
	_tabs.name = "Tabs"
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.custom_minimum_size = Vector2(0, 470)
	layout.add_child(_tabs)
	_status = Label.new()
	_status.name = "Status"
	_status.add_theme_color_override("font_color", theme_cfg_ref.text_muted)
	_status.add_theme_font_size_override("font_size", theme_cfg_ref.font_caption)
	layout.add_child(_status)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	layout.add_child(footer)
	var reset := Button.new()
	reset.text = "СБРОСИТЬ К ЗАВОДСКИМ"
	reset.pressed.connect(reset_to_defaults)
	footer.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var close_button := Button.new()
	close_button.text = "ГОТОВО"
	close_button.pressed.connect(close)
	footer.add_child(close_button)
	_build_presets(presets)


## Готовые варианты: один клик — и шлейф становится заметным или зрелищным.
func _build_presets(box: HBoxContainer) -> void:
	_presets = [
		{"name": "СПОКОЙНО", "values": {"fx_intensity": 1.0, "foam_alpha": 0.32, "grit_scale_max": 1.9}},
		{"name": "ЗАВОДСКОЙ", "values": {}},
		{"name": "ЗРЕЛИЩНО", "values": {"fx_intensity": 2.0, "foam_alpha": 0.46, "grit_scale_max": 2.6}},
		{
			"name": "КАК В DAKAR",
			"values": {
				"fx_intensity": 3.4, "foam_alpha": 0.62, "foam_growth": 4.2, "grit_scale_max": 3.4
			},
		},
	]
	for preset in _presets:
		var button := Button.new()
		button.text = String(preset["name"])
		button.pressed.connect(_apply_preset.bind(preset))
		box.add_child(button)


func _apply_preset(preset: Dictionary) -> void:
	if fx == null:
		return
	var values: Dictionary = preset["values"]
	if values.is_empty():
		reset_to_defaults()
		return
	_applying = true
	for field in values:
		if field in _fx_fields() or _has_property(fx, String(field)):
			fx.set(field, values[field])
	_applying = false
	_rebuild_rows()
	apply_to_car()
	_save()
	_set_status("Готовый вариант «%s» применён." % preset["name"])


# ------------------------------------------------------------------ строки


func _rebuild_rows() -> void:
	if _tabs == null:
		return
	_controls.clear()
	if fx == null:
		return
	for child in _tabs.get_children():
		child.name = "Stale"
		_tabs.remove_child(child)
		child.queue_free()
	_add_tab_from_resource(fx, "Эффекты и кузов", func(field: String, value: Variant) -> void:
		fx.set(field, value)
	)
	var profiles := fx.surface_fx_profiles
	var surfaces := VBoxContainer.new()
	surfaces.name = "Покрытия"
	surfaces.add_theme_constant_override("separation", 6)
	var picker := OptionButton.new()
	picker.name = "SurfacePicker"
	_surface_picker = picker
	var kind_titles := {
		"gravel": "Гравий",
		"mud": "Грязь",
		"grass": "Трава",
		"snow": "Снег",
		"asphalt": "Асфальт",
	}
	for profile in profiles:
		var kind := String(profile.kind_name())
		picker.add_item(String(kind_titles.get(kind, kind)).capitalize())
	if picker.item_count > 0:
		picker.select(0)
	surfaces.add_child(picker)
	var holder := VBoxContainer.new()
	holder.name = "SurfaceHolder"
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	surfaces.add_child(holder)
	_tabs.add_child(surfaces)
	picker.item_selected.connect(_show_surface.bind(holder))
	if not profiles.is_empty():
		_show_surface(0, holder)


func _show_surface(index: int, holder: VBoxContainer) -> void:
	if fx == null or index < 0 or index >= fx.surface_fx_profiles.size():
		return
	var profile := fx.surface_fx_profiles[index]
	for child in holder.get_children():
		holder.remove_child(child)
		child.queue_free()
	var on_change := func(field: String, value: Variant) -> void:
		profile.set(field, value)
	_add_tab_from_resource(profile, "Покрытие %d" % (index + 1), on_change, holder)


## Пройти по экспортам ресурса и собрать вкладку: группы → строки с полями.
func _add_tab_from_resource(
	resource: Resource,
	tab_title: String,
	on_change: Callable,
	into: VBoxContainer = null
) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = tab_title
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var page := VBoxContainer.new()
	page.name = "Page"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 4)
	scroll.add_child(page)
	var current_group := ""
	for property in resource.get_property_list():
		if not _is_visible_export(property, resource):
			continue
		var group := String(property.get("group", ""))
		if group != current_group:
			current_group = group
			_add_group_header(page, group)
		_add_row(page, resource, property, on_change)
	if into == null:
		_tabs.add_child(scroll)
	else:
		into.add_child(scroll)


func _add_group_header(page: VBoxContainer, title: String) -> void:
	var header := Label.new()
	header.text = (title if not title.is_empty() else "ПРОЧЕЕ").to_upper()
	header.add_theme_color_override("font_color", theme_cfg().accent_soft)
	header.add_theme_font_size_override("font_size", theme_cfg().font_group)
	page.add_child(header)


func _add_row(
	page: VBoxContainer, resource: Resource, property: Dictionary, on_change: Callable
) -> void:
	var field := String(property["name"])
	var type := int(property["type"])
	var value: Variant = resource.get(field)
	_controls.append({"field": field, "resource": resource, "type": type})
	var row := HBoxContainer.new()
	row.name = field
	row.add_theme_constant_override("separation", 8)
	page.add_child(row)
	var label := Label.new()
	label.text = _human_name(field)
	label.custom_minimum_size = Vector2(260, 0)
	label.add_theme_color_override("font_color", theme_cfg().text_primary)
	label.add_theme_font_size_override("font_size", theme_cfg().font_hud_label)
	row.add_child(label)
	if type == TYPE_BOOL:
		var toggle := CheckButton.new()
		toggle.button_pressed = bool(value)
		toggle.toggled.connect(func(pressed: bool) -> void: _commit(field, pressed, on_change))
		row.add_child(toggle)
	elif type == TYPE_COLOR:
		var picker := ColorPickerButton.new()
		picker.color = value
		picker.custom_minimum_size = Vector2(96, 24)
		picker.color_changed.connect(func(color: Color) -> void: _commit(field, color, on_change))
		row.add_child(picker)
	elif type == TYPE_VECTOR3:
		_add_vector3_spins(row, resource, field, value, on_change)
	elif type == TYPE_AABB:
		# AABB — это позиция и размер кулинг-бокса: шесть спинбоксов.
		var box: AABB = value
		_add_aabb_spins(row, resource, field, box, "pos", on_change)
		_add_aabb_spins(row, resource, field, box, "size", on_change)
	elif _is_text_list(field, value):
		var edit := LineEdit.new()
		edit.text = ", ".join(PackedStringArray(value))
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.text_submitted.connect(
			func(text: String) -> void: _commit(field, PackedStringArray(text.split(",")), on_change)
		)
		row.add_child(edit)
	elif type == TYPE_INT or type == TYPE_FLOAT:
		_add_number_row(row, resource, property, on_change)
	else:
		var caption := Label.new()
		caption.text = str(value)
		caption.add_theme_color_override("font_color", theme_cfg().text_muted)
		row.add_child(caption)


## Три спинбокса для Vector3-поля профиля.
func _add_vector3_spins(
	row: HBoxContainer, resource: Resource, field: String, vec: Vector3, on_change: Callable
) -> void:
	for axis in range(3):
		var spin := SpinBox.new()
		spin.min_value = -500.0
		spin.max_value = 500.0
		spin.step = 0.05
		spin.value = vec[axis]
		spin.custom_minimum_size = Vector2(78, 0)
		spin.value_changed.connect(
			func(changed: float) -> void:
				var next: Vector3 = resource.get(field)
				next[axis] = changed
				_commit(field, next, on_change)
		)
		row.add_child(spin)


## Три спинбокса для позиции или размера AABB (кулинг-бокс облака).
func _add_aabb_spins(
	row: HBoxContainer,
	resource: Resource,
	field: String,
	box: AABB,
	half: String,
	on_change: Callable
) -> void:
	var vec: Vector3 = box.position if half == "pos" else box.size
	for axis in range(3):
		var spin := SpinBox.new()
		spin.min_value = -500.0
		spin.max_value = 500.0
		spin.step = 0.05
		spin.value = vec[axis]
		spin.custom_minimum_size = Vector2(78, 0)
		spin.value_changed.connect(
			func(changed: float) -> void:
				var current: AABB = resource.get(field)
				var next: Vector3 = current.position if half == "pos" else current.size
				next[axis] = changed
				var updated := (
					AABB(next, current.size) if half == "pos" else AABB(current.position, next)
				)
				_commit(field, updated, on_change)
		)
		row.add_child(spin)


## Число: ползунок в диапазоне из @export_range или спинбокс без подсказки.
func _add_number_row(
	row: HBoxContainer, resource: Resource, property: Dictionary, on_change: Callable
) -> void:
	var field := String(property["name"])
	var is_int := int(property["type"]) == TYPE_INT
	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var has_range: bool = int(property["hint"]) == PROPERTY_HINT_RANGE
	if has_range:
		var parts := String(property["hint_string"]).split(",")
		slider.min_value = float(parts[0])
		slider.max_value = float(parts[1]) if parts.size() > 1 else 1.0
		slider.step = float(parts[2]) if parts.size() > 2 else (1.0 if is_int else 0.01)
	else:
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 1.0 if is_int else 0.01
	var current := float(resource.get(field))
	slider.min_value = minf(slider.min_value, current)
	slider.max_value = maxf(slider.max_value, current)
	slider.value = current
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(72, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_color_override(
		"font_color", theme_cfg().text_value
	)
	value_label.add_theme_font_size_override("font_size", theme_cfg().font_hud_small)
	value_label.text = _format_value(resource.get(field), is_int)
	slider.value_changed.connect(
		func(changed: float) -> void:
			var next: Variant = roundi(changed) if is_int else changed
			value_label.text = _format_value(next, is_int)
			_commit(field, next, on_change)
	)
	row.add_child(slider)
	row.add_child(value_label)


## Списки имён (какие меши пачкаются) — строкой через запятую, а не слайдером.
static func _is_text_list(field: String, value: Variant) -> bool:
	return value is PackedStringArray or (
		value is Array and ("prefixes" in field or "skip" in field)
	)


func _commit(field: String, value: Variant, on_change: Callable) -> void:
	if _applying:
		return
	on_change.call(field, value)
	apply_to_car()
	_save()
	_set_status("Изменено: %s" % _human_name(field))


## Попросить машину применить профиль к уже работающим частицам и слоям кузова.
func apply_to_car() -> void:
	if car == null or not is_instance_valid(car):
		return
	var effects: Variant = car.get("surface_effects")
	if effects != null and is_instance_valid(effects) and effects.has_method("refresh_profile"):
		effects.call("refresh_profile")
	# Заднее облако собирается по тем же полям: просим машину пересобрать его.
	if car.has_method("refresh_dust_cloud"):
		car.call("refresh_dust_cloud")


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


# ------------------------------------------------------------------ данные


## Экспорты ресурса, которые можно показывать: без внутренних полей и массивов.
## static: вызывается из static exported_names() и из static apply_saved().
static func _is_visible_export(property: Dictionary, _resource: Resource) -> bool:
	if int(property.get("usage", 0)) & PROPERTY_USAGE_EDITOR == 0:
		return false
	if String(property.get("group", "")) in HIDDEN_GROUPS:
		return false
	var field := String(property["name"])
	if field in HIDDEN_FIELDS or field.begins_with("_") or field in ["script", "resource_name"]:
		return false
	var type := int(property["type"])
	if int(property.get("hint", 0)) == PROPERTY_HINT_ENUM:
		return false
	return type in [
		TYPE_BOOL, TYPE_COLOR, TYPE_FLOAT, TYPE_INT, TYPE_VECTOR3, TYPE_AABB,
		TYPE_PACKED_STRING_ARRAY,
	]


func _fx_fields() -> Array[String]:
	return exported_names(fx)


static func exported_names(resource: Resource) -> Array[String]:
	var names: Array[String] = []
	if resource == null:
		return names
	for property in resource.get_property_list():
		if _is_visible_export(property, resource):
			names.append(String(property["name"]))
	return names


static func _has_property(resource: Resource, field: String) -> bool:
	for property in resource.get_property_list():
		if String(property["name"]) == field:
			return true
	return false


## Понятные подписи: имя поля → русская строка с пробелами.
static func _human_name(field: String) -> String:
	var names := {
		"fx_intensity": "Сила эффектов, ×",
		"fx_update_hz": "Частота пересчёта, Гц",
		"fx_physics_fps": "FPS симуляции частиц",
		"fx_sparkle_enabled": "Светящиеся пылинки",
		"fx_sparkle_strength": "Яркость пылинок",
		"fx_sparkle_color": "Цвет пылинок",
		"fx_sparkle_emission": "Свечение пылинок",
		"foam_height": "Высота клубов",
		"foam_lifetime": "Жизнь клуба, с",
		"foam_growth": "Раздувание клуба",
		"foam_size": "Размер клуба",
		"foam_emission_radius": "Пятно рождения клубов",
		"foam_scale_min": "Разброс размера min",
		"foam_scale_max": "Разброс размера max",
		"foam_direction": "Направление клубов",
		"foam_spread": "Разлёт клубов, °",
		"foam_speed_min": "Скорость клубов min",
		"foam_speed_max": "Скорость клубов max",
		"foam_gravity": "Тяжесть клубов",
		"foam_amount": "Клубов на колесо",
		"foam_wet_boost": "Больше на мокром",
		"foam_alpha": "Плотность клубов (0–1)",
		"foam_lit": "Клубы ловят свет",
		"grit_lifetime": "Жизнь комьев, с",
		"grit_spread": "Разлёт комьев, °",
		"grit_speed_min": "Скорость комьев min",
		"grit_speed_max": "Скорость комьев max",
		"grit_gravity": "Тяжесть комьев",
		"grit_scale_min": "Размер комьев min",
		"grit_scale_max": "Размер комьев max",
		"grit_amount": "Комьев на колесо",
		"grit_specular": "Блеск комьев",
		"grit_light_boost": "Подсветка комьев",
		"side_splay": "Разлёт в стороны",
		"inherit_velocity_ratio": "Инерция машины",
		"wind_pull": "Сдувание ветром",
		"steer_boost": "Надбавка за поворот",
		"handbrake_boost": "Надбавка за ручник",
		"dust_enabled": "Облако за кормой",
		"dust_amount": "Плотность облака",
		"dust_lifetime": "Жизнь облака, с",
		"dust_radius": "Размер облака",
		"dust_color": "Цвет облака",
		"dust_speed_max": "Скорость облака",
		"dust_min_speed_kmh": "Мин. скорость, км/ч",
		"dust_slip_threshold": "Порог пробуксовки",
		"dust_growth": "Раздувание облака",
		"dust_flatness": "Сплющенность облака",
		"dust_spin": "Вращение облака, °/с",
		"dust_turbulence_scale": "Масштаб завихрений",
		"dust_turbulence_influence": "Сила завихрений",
		"dust_lifetime_randomness": "Разброс жизни облака",
		"dust_damping_min": "Торможение облака min",
		"dust_damping_max": "Торможение облака max",
		"dust_turbulence": "Завихрения",
		"body_coverage": "Густота грязи, ×",
		"body_alpha": "Непрозрачность слоя (0–1)",
		"body_spread": "Радиус пятна по кузову",
		"foam_emission": "Свечение клубов",
		"foam_flatness": "Сплющенность клубов",
		"foam_spin": "Вращение клубов, °/с",
		"foam_turbulence": "Завихрения клубов",
		"foam_turbulence_scale": "Масштаб завихрений",
		"foam_damping_min": "Торможение клубов min",
		"foam_damping_max": "Торможение клубов max",
		"foam_lifetime_randomness": "Разброс жизни клубов",
		"grit_lifetime_randomness": "Разброс жизни комьев",
		"grit_spin": "Вращение комьев, °/с",
		"body_edge_softness": "Мягкость краёв",
		"body_dirt_buildup": "Сила слоя грязи",
		"body_snow_buildup": "Сила слоя снега",
		"dirt_color": "Цвет грязи",
		"body_snow_color": "Цвет снега",
		"dirt_body_prefixes": "Какие меши пачкаются",
		"dirt_body_skip": "Что не пачкается",
		"dry_color": "Сухой цвет",
		"wet_color": "Мокрый цвет",
		"amount_scale": "Количество",
		"lifetime_scale": "Время жизни",
		"spread_scale": "Разлёт",
		"velocity_scale": "Скорость",
		"particle_scale": "Размер частиц",
		"grain_scale": "Размер комьев",
		"smoke_share": "Доля дыма",
		"grit_share": "Доля комьев",
		"particle_tint": "Плотность цвета",
		"burst_scale": "Сила выброса",
		"speed_weight": "Вклад скорости",
		"slip_weight": "Вклад пробуксовки",
		"wet_weight": "Вклад мокроты",
		"speed_start_kmh": "Скорость: начало",
		"speed_full_kmh": "Скорость: максимум",
		"slip_start": "Пробуксовка: начало",
		"slip_full": "Пробуксовка: максимум",
		"gravity_scale": "Тяжесть",
		"direction": "Направление",
		"level_1_threshold": "Порог 1",
		"level_2_threshold": "Порог 2",
		"level_3_threshold": "Порог 3",
		"level_1_amount_ratio": "Плотность 1",
		"level_2_amount_ratio": "Плотность 2",
		"level_3_amount_ratio": "Плотность 3",
		"level_1_velocity_scale": "Скорость 1",
		"level_2_velocity_scale": "Скорость 2",
		"level_3_velocity_scale": "Скорость 3",
		"enabled": "Включено",
		"kind": "Покрытие",

		"alpha_asphalt_scale": "Прозрачность на асфальте",
		"alpha_cutoff": "Порог отсечения следа",
		"alpha_limit": "Предел прозрачности",
		"alpha_max": "Прозрачность сильного следа",
		"alpha_min": "Прозрачность слабого следа",
		"asphalt_mark_color": "Цвет следа: асфальт",
		"chunk_count": "Кусков в кольце следа",
		"chunk_size": "Точек в куске следа",
		"damp_dry_scale": "Налипание на сухом",
		"damp_wet_scale": "Налипание на мокром",
		"depth_dry_scale": "Глубина на сухом",
		"depth_firm": "Глубина колеи: плотный",
		"depth_grass": "Глубина колеи: трава",
		"depth_soft": "Глубина колеи: мягкий грунт",
		"depth_wet_scale": "Глубина на мокром",
		"dirt_center_spring_scale": "Смещение пятен по подвеске",
		"dirt_min_speed": "Порог скорости для грязи, м/с",
		"dust_aabb": "Зона видимости облака",
		"dust_direction": "Направление облака",
		"dust_emission_extents": "Форма зоны выброса",
		"dust_gravity": "Тяжесть облака",
		"dust_handbrake_slip": "Пробуксовка от ручника",
		"dust_scale_max": "Размер облака max",
		"dust_scale_min": "Размер облака min",
		"dust_speed_min": "Скорость облака min",
		"dust_spread": "Разлёт облака, °",
		"flush_interval": "Частота пересборки следа, с",
		"foam_sparkle": "Пылинки внутри клубов",
		"grass_dirt_rate": "Налипание на траве, ед/с",
		"grass_mark_color": "Цвет следа: трава",
		"gravel_dirt_rate": "Налипание на гравии, ед/с",
		"gravel_mark_color": "Цвет следа: гравий",
		"grip_max": "Сцепление: максимум",
		"grip_min": "Сцепление: минимум",
		"grip_zones_enabled": "Скользкие полосы",
		"imprint_delta_limit": "Отпечаток: предел шага",
		"imprint_load_limit": "Отпечаток: предел нагрузки",
		"imprint_load_scale": "Сила отпечатка",
		"imprint_slip_base": "Отпечаток: база скольжения",
		"imprint_slip_scale": "Отпечаток: вклад скольжения",
		"imprint_speed_limit": "Отпечаток: предел скорости",
		"imprint_speed_scale": "Отпечаток: вклад скорости",
		"max_distance": "Макс. шаг точки следа, м",
		"min_distance": "Мин. шаг точки следа, м",
		"min_looseness": "Порог рыхлости для комочков",
		"min_speed": "Мин. скорость для следа, м/с",
		"mud_dirt_rate": "Налипание на грязи, ед/с",
		"mud_mark_color": "Цвет следа: грязь",
		"packing_grip_gravel": "Накат: сцепление (гравий)",
		"packing_grip_other": "Накат: сцепление (прочее)",
		"packing_rolling_gain": "Накат: сопротивление качению",
		"rain_dry_loss": "Сушка без дождя",
		"rain_wash": "Дождь смывает грязь",
		"rain_wet_gain": "Дождь: скорость намокания",
		"rolling_max": "Качение: максимум",
		"rolling_min": "Качение: минимум",
		"rut_alpha_bonus": "Надбавка за колею",
		"rut_depth_scale": "Глубина колеи для следа",
		"rut_grip_loss_dry": "Колея: потеря сцепления (сухо)",
		"rut_grip_loss_wet": "Колея: потеря сцепления (мокро)",
		"rut_rolling_firm": "Колея: качение (плотный)",
		"rut_rolling_soft": "Колея: качение (мягкий)",
		"rut_width_bonus": "Ширина по колее",
		"snow_gain": "Снегопад: накопление",
		"snow_mark_color": "Цвет следа: снег",
		"snow_melt": "Снег тает сам",
		"snow_rate": "Накопление снега, ед/с",
		"snow_track_threshold": "Порог снежного следа",
		"snow_wash_by_rain": "Дождь убирает снег",
		"soil_height": "Комочек: высота",
		"soil_lighten": "Осветление комочков",
		"soil_offset": "Комочек: подъём над землёй",
		"soil_radius_max": "Комочек: радиус max",
		"soil_radius_min": "Комочек: радиус min",
		"soil_side_max": "Комочек: вынос вбок max",
		"soil_side_min": "Комочек: вынос вбок min",
		"soil_spacing": "Шаг комочков вдоль следа, м",
		"soil_wet_darken": "Затемнение мокрых комочков",
		"spray_direction": "Направление брызг",
		"spray_dry_color": "Цвет брызг: сухой",
		"spray_grain_height": "Высота крупинки, м",
		"spray_grain_radius": "Радиус крупинки, м",
		"spray_grain_segments": "Граней у крупинки",
		"spray_grain_rings": "Колец у крупинки",
		"spray_min_speed": "Порог скорости брызг",
		"spray_slip_threshold": "Порог пробуксовки брызг",
		"spray_snow_color": "Цвет брызг: снег",
		"spray_wet_color": "Цвет брызг: мокрый",
		"spray_wet_threshold": "Порог мокроты для брызг",
		"surface_cell_size": "Ячейка памяти грунта, м",
		"surface_max_cells": "Предел ячеек грунта",
		"surface_offset": "Высота следа над землёй, м",
		"tire_width_max_m": "Ширина шины max, м",
		"tire_width_min_m": "Ширина шины min, м",
		"wet_soil_color": "Цвет мокрого комочка",
		"width_scale": "Ширина следа",
		"zone_dry_lighten": "Сухая полоса: осветление",
		"zone_end_margin": "Полосы: отступ от финиша, м",
		"zone_grip_loss_strong": "Сцепление в сильной луже",
		"zone_grip_loss_weak": "Сцепление в слабой луже",
		"zone_half_width": "Полосы: полуширина, м",
		"zone_lateral_fraction": "Смещение лужи от оси",
		"zone_lateral_limit": "Предел смещения лужи",
		"zone_length": "Полосы: длина лужи, м",
		"zone_period": "Полосы: длина ячейки, м",
		"zone_puddle_mix": "Смешение лужи",
		"zone_puddle_roughness": "Глянец лужи",
		"zone_shader_contrast": "Лужа в шейдере: контраст",
		"zone_shader_fade": "Лужа в шейдере: затухание",
		"zone_shader_half_width": "Лужа в шейдере: полуширина",
		"zone_shader_softness": "Лужа в шейдере: мягкость",
		"zone_start": "Полосы: начало, м",
		"zone_wet_darken": "Мокрая лужа: затемнение",	}
	if names.has(field):
		return String(names[field])
	return field.replace("_", " ")


static func _format_value(value: Variant, is_int: bool) -> String:
	if is_int:
		return str(int(value))
	return "%.2f" % float(value)


# ------------------------------------------------------------------ сохранение


func _save() -> void:
	if fx == null:
		return
	var config := ConfigFile.new()
	for field in _fx_fields():
		var value: Variant = fx.get(field)
		if value is PackedStringArray:
			config.set_value("fx", field, Array(value))
		elif value is Object or value is Array:
			continue
		else:
			config.set_value("fx", field, value)
	for index in range(fx.surface_fx_profiles.size()):
		var profile := fx.surface_fx_profiles[index]
		for field in exported_names(profile):
			var value: Variant = profile.get(field)
			if value is Object or value is Array:
				continue
			config.set_value("surface_%d" % index, field, value)
	config.save(save_path)


func _load_saved() -> void:
	if fx != null:
		apply_saved(fx)


## Применить сохранённые пользователем настройки к профилю (если файл есть).
## Вызывается и при открытии окна, и при старте заезда — правки переживают
## перезапуск игры, не трогая .tres в репозитории.
static func apply_saved(profile: RallyFxProfile, from_path: String = SAVE_PATH) -> void:
	if profile == null:
		return
	var config := ConfigFile.new()
	if config.load(from_path) != OK:
		return
	for field in exported_names(profile):
		if not config.has_section_key("fx", field):
			continue
		var value: Variant = config.get_value("fx", field)
		if value is Array and profile.get(field) is PackedStringArray:
			profile.set(field, PackedStringArray(value))
		else:
			profile.set(field, value)
	for index in range(profile.surface_fx_profiles.size()):
		var surface := profile.surface_fx_profiles[index]
		for field in exported_names(surface):
			if config.has_section_key("surface_%d" % index, field):
				surface.set(field, config.get_value("surface_%d" % index, field))
