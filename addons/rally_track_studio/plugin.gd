## «Студия трассы» — редактор спецучастка прямо в 3D-вьюпорте Godot.
##
## Зачем: родной Path3D показывает только точки и ручки. Приходилось тыкать
## точки вслепую, каждый раз жать «Пересобрать трассу» и ждать несколько
## секунд, а ширина, покрытие, лес и зоны вообще жили в других файлах.
##
## Что делает плагин:
##   * режим «Трасса» — рисование кликом по земле, вставка точки на линии,
##     перетаскивание, высота по Shift, удаление ПКМ, сглаживание;
##   * режим «Полотно» — ширина и покрытие участков мышиными ручками;
##   * режим «Лес» — кисть обстановки: ставит и убирает сцены из библиотеки;
##   * режим «Зоны» — старт/финиш/арки КПП перетаскиванием;
##   * живая разметка (полотно, километраж, повороты Л4/П2, предупреждения,
##     профиль высот) рисуется 2D-слоем поверх вьюпорта — сразу, без сборки;
##   * док «Мир трассы» — холмы, насыпь, кювет, сцепление, туман и экспозиция
##     ползунками с одной записью в Ctrl+Z на каждое движение;
##   * Ctrl+R — собрать мир, «Сохранить» — записать сцены и .tres на диск.
##
## Плагин — тонкая оболочка: кнопки, ввод и отрисовка. Вся логика в studio.gd.
@tool
extends EditorPlugin

const StudioType = preload("res://addons/rally_track_studio/studio.gd")
const SettingsType = preload("res://scripts/data/rally_track_studio_settings.gd")
const DockType = preload("res://addons/rally_track_studio/dock.gd")
const DEFAULT_SETTINGS := "res://data/editor/track_studio.tres"
const TICK_SECONDS := 0.05

var studio: StudioType = null
var _settings: SettingsType = null
var _dock: DockType = null
var _bar: HBoxContainer = null
var _toggle: Button = null
var _mode_box: HBoxContainer = null
var _mode_buttons: Array = []
var _rebuild_button: Button = null
var _auto_button: Button = null
var _hud_button: Button = null
var _save_button: Button = null
var _timer: Timer = null


func _enter_tree() -> void:
	_settings = _load_settings()
	studio = StudioType.new()
	studio.setup(self, _settings)
	set_input_event_forwarding_always_enabled()
	_build_toolbar()
	_build_dock()
	_timer = Timer.new()
	_timer.name = "RallyTrackStudioTick"
	_timer.wait_time = TICK_SECONDS
	_timer.autostart = true
	_timer.one_shot = false
	_timer.timeout.connect(_on_tick)
	add_child(_timer)
	scene_changed.connect(_on_scene_changed)
	studio.sync_scene()
	_sync_toolbar()


func _exit_tree() -> void:
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)
	if _timer != null:
		_timer.stop()
		_timer.queue_free()
		_timer = null
	if _bar != null:
		remove_control_from_container(CONTAINER_TOOLBAR, _bar)
		_bar.queue_free()
		_bar = null
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	if studio != null:
		studio.shutdown()
		studio = null


func _load_settings() -> SettingsType:
	var loaded := load(DEFAULT_SETTINGS)
	if loaded is RallyTrackStudioSettings:
		return loaded
	var made := SettingsType.new()
	made.resource_name = "RallyTrackStudioSettings (встроенные значения)"
	return made


func _build_toolbar() -> void:
	_bar = HBoxContainer.new()
	_bar.name = "RallyTrackStudio"
	_bar.add_theme_constant_override("separation", 4)

	_toggle = Button.new()
	_toggle.text = "Ралли"
	_toggle.toggle_mode = true
	_toggle.tooltip_text = "Студия трассы: рисование и разметка прямо в 3D-вьюпорте"
	_toggle.toggled.connect(_on_toggle)
	_bar.add_child(_toggle)

	_mode_box = HBoxContainer.new()
	_mode_box.add_theme_constant_override("separation", 2)
	_bar.add_child(_mode_box)
	var group := ButtonGroup.new()
	for i in range(_settings.mode_names.size()):
		var button := Button.new()
		button.text = _settings.mode_names[i]
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = "Режим «%s» (клавиша %d)" % [_settings.mode_names[i], i + 1]
		button.toggled.connect(_on_mode_toggled.bind(i))
		_mode_box.add_child(button)
		_mode_buttons.append(button)

	_rebuild_button = Button.new()
	_rebuild_button.text = "Собрать"
	_rebuild_button.tooltip_text = "Пересобрать мир по текущей осевой (Ctrl+R)"
	_rebuild_button.focus_mode = Control.FOCUS_NONE
	_rebuild_button.pressed.connect(_on_rebuild)
	_bar.add_child(_rebuild_button)

	_auto_button = Button.new()
	_auto_button.text = "Авто"
	_auto_button.toggle_mode = true
	_auto_button.tooltip_text = "Автоматически пересобирать мир после правок"
	_auto_button.focus_mode = Control.FOCUS_NONE
	_auto_button.toggled.connect(_on_auto_toggled)
	_bar.add_child(_auto_button)

	_hud_button = Button.new()
	_hud_button.text = "HUD"
	_hud_button.toggle_mode = true
	_hud_button.tooltip_text = "Панель, профиль и подписи (H)"
	_hud_button.focus_mode = Control.FOCUS_NONE
	_hud_button.toggled.connect(_on_hud_toggled)
	_bar.add_child(_hud_button)

	_save_button = Button.new()
	_save_button.text = "Сохранить"
	_save_button.tooltip_text = "Записать все открытые сцены и ресурсы на диск"
	_save_button.focus_mode = Control.FOCUS_NONE
	_save_button.pressed.connect(_on_save)
	_bar.add_child(_save_button)

	add_control_to_container(CONTAINER_TOOLBAR, _bar)
	_update_visibility()


func _build_dock() -> void:
	_dock = DockType.new()
	_dock.setup(studio)
	add_control_to_dock(DOCK_SLOT_RIGHT_BR, _dock)


func _on_tick() -> void:
	if studio == null:
		return
	studio.tick(TICK_SECONDS)
	if _dock != null:
		_dock.refresh()
	_sync_toolbar()


func _sync_toolbar() -> void:
	if studio == null or _toggle == null:
		return
	_toggle.set_pressed_no_signal(studio.active)
	for i in range(_mode_buttons.size()):
		var button: Button = _mode_buttons[i]
		button.set_pressed_no_signal(i == studio.mode)
	if _auto_button != null and _auto_button.button_pressed != _settings.auto_rebuild:
		_auto_button.set_pressed_no_signal(_settings.auto_rebuild)
	if _hud_button != null and _hud_button.button_pressed != _settings.show_hud:
		_hud_button.set_pressed_no_signal(_settings.show_hud)
	_update_visibility()


func _update_visibility() -> void:
	if _bar == null or studio == null:
		return
	var ready_now: bool = studio.active and studio.stage != null
	_mode_box.visible = ready_now
	_rebuild_button.visible = ready_now
	_auto_button.visible = ready_now
	_hud_button.visible = ready_now
	_save_button.visible = ready_now


func _on_toggle(pressed: bool) -> void:
	if studio == null:
		return
	studio.set_active(pressed)


func _on_mode_toggled(pressed: bool, index: int) -> void:
	if studio == null or not pressed:
		return
	studio.set_mode(index)


func _on_rebuild() -> void:
	if studio != null:
		studio.rebuild_stage()


func _on_auto_toggled(pressed: bool) -> void:
	if _settings != null:
		_settings.auto_rebuild = pressed


func _on_hud_toggled(pressed: bool) -> void:
	if _settings == null:
		return
	_settings.show_hud = pressed
	if studio != null:
		studio.request_redraw()


func _on_save() -> void:
	get_editor_interface().save_all_scenes()
	if studio != null:
		studio.save_now()
		studio.toast("Сцены и ресурсы сохранены")


func _on_scene_changed(_scene_root: Node) -> void:
	if studio == null:
		return
	studio.sync_scene()
	_sync_toolbar()


func _handles(object: Object) -> bool:
	if studio == null or not studio.active:
		return false
	var node := object as Node
	if node == null:
		return false
	var edited := get_editor_interface().get_edited_scene_root()
	if edited == null:
		return false
	return node == edited or edited.is_ancestor_of(node)


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if studio == null:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	return studio.forward_input(camera, event)


func _forward_3d_draw_over_viewport(overlay: Control) -> void:
	if studio != null:
		studio.draw_overlay(overlay)
