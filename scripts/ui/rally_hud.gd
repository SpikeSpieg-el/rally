## Корневой контроллер гоночного HUD (`scenes/ui/rally_hud.tscn`).
##
## Связывает общий стиль `RallyHudStyle`, настраиваемый `SpriteSpeedometer`,
## счётчики `SpriteCounter`, `RallyFpsCounter`, `MiniMap`, `RallyRadioCard` и
## шесть шкал телеметрии `GaugeBar` в единую архитектуру.
## Позволяет переключать весь HUD целиком между текущим «стеклянным» видом
## и полным пиксельным стилем спрайт-листа спидометра.
@tool
class_name RallyHUD
extends Control

const LayoutType = preload("res://scripts/ui/rally_screen_layout.gd")

signal hud_style_applied(pixel_active: bool)
signal cockpit_mode_changed(in_cockpit: bool)

enum ThemeMode {
	AUTO_FROM_STYLE = 0,
	KEEP_CLASSIC_PANELS = 1,
	SPEEDOMETER_PIXEL = 2,
}

enum SpeedometerDisplayMode {
	SPRITE_SPEEDOMETER = 0,
	CLASSIC_TEXT_BOX = 1,
	BOTH = 2,
}

enum CockpitHideMode {
	AUTO_FROM_STYLE = 0,
	FORCE_HIDE_REDUNDANT = 1,
	KEEP_ALL_HUD = 2,
}

@export_group("Стиль HUD")
@export var hud_style: RallyHudStyle:
	set(v):
		if hud_style != null and hud_style.changed.is_connected(_on_hud_style_changed):
			hud_style.changed.disconnect(_on_hud_style_changed)
		hud_style = v
		if hud_style != null and not hud_style.changed.is_connected(_on_hud_style_changed):
			hud_style.changed.connect(_on_hud_style_changed)
		if is_inside_tree():
			apply_hud_style()

@export var theme_mode: ThemeMode = ThemeMode.AUTO_FROM_STYLE:
	set(v):
		theme_mode = v
		if is_inside_tree():
			apply_hud_style()

@export var speedometer_display: SpeedometerDisplayMode = SpeedometerDisplayMode.SPRITE_SPEEDOMETER:
	set(v):
		speedometer_display = v
		if is_inside_tree():
			_sync_speedometer_mode()

@export var auto_apply_on_ready: bool = true

@export_group("Вид из кабины (1-е лицо)")
@export var cockpit_hide_mode: CockpitHideMode = CockpitHideMode.AUTO_FROM_STYLE:
	set(v):
		cockpit_hide_mode = v
		if is_inside_tree():
			_apply_cockpit_visibility()
@export var sync_cockpit_camera_from_vehicle: bool = true

@export_group("Портретная раскладка")
## Высота нижней полосы HUD, отданной спидометру в портрете, px канвы
## (1920-базовая шкала; на экране масштабируется вместе с остальным UI).
@export_range(120.0, 400.0, 4.0) var portrait_speed_height: float = 210.0
## Ширина мини-карты в портрете, px канвы.
@export_range(120.0, 600.0, 8.0) var portrait_minimap_width: float = 300.0
## Зазор между панелями и краем экрана в портрете, px канвы.
@export_range(0.0, 80.0, 2.0) var portrait_margin: float = 20.0

@export_group("Пути виджетов")
@export var stage_panel_path: NodePath = NodePath("StagePanel")
@export var radio_card_path: NodePath = NodePath("RadioCard")
@export var timer_panel_path: NodePath = NodePath("TimerPanel")
@export var timer_label_path: NodePath = NodePath("TimerPanel/TimerBox/TimerLabel")
@export var timer_sprite_path: NodePath = NodePath("TimerPanel/TimerBox/TimerSprite")
@export var split_label_path: NodePath = NodePath("TimerPanel/TimerBox/SplitLabel")
@export var delta_panel_path: NodePath = NodePath("DeltaPanel")
@export var mini_map_path: NodePath = NodePath("MiniMap")
@export var fps_label_path: NodePath = NodePath("FPSLabel")
@export var speed_panel_path: NodePath = NodePath("SpeedPanel")
@export var speedometer_path: NodePath = NodePath("SpeedPanel/SpriteSpeedometer")
@export var speed_box_path: NodePath = NodePath("SpeedPanel/SpeedBox")
@export var telemetry_panel_path: NodePath = NodePath("TelemetryPanel")
@export var telemetry_box_path: NodePath = NodePath("TelemetryPanel/TeleBox")
@export var hint_label_path: NodePath = NodePath("Hint")
@export var clutch_notice_path: NodePath = NodePath("ClutchNotice")
@export var pause_panel_path: NodePath = NodePath("PausePanel")
@export var results_panel_path: NodePath = NodePath("ResultsPanel")
@export var touch_controls_path: NodePath = NodePath("TouchControls")

var _saved_panel_styles: Dictionary = {}
var _saved_label_styles: Dictionary = {}
var _saved_button_styles: Dictionary = {}
var _saved_text_colors: Dictionary = {}
var _classic_captured: bool = false
var _current_camera_mode: int = 0
var _cockpit_hidden_nodes: Dictionary = {}
var _bound_vehicle: Node = null
## Раскладка, которую HUD применил последней: "" (сцена), "portrait" или
## "landscape". Пересобираем только при смене — размеры пересчитываются при
## каждом изменении канвы, но не каждый кадр.
var _applied_layout: String = ""
## Канва, под которую посчитаны прямоугольники портрета: поворот телефона и
## изменение окна пересчитывают их, даже если ориентация осталась портретной.
var _applied_canvas: Vector2 = Vector2.ZERO
## Верх сенсорных кнопок, под который посчитана нижняя полоса портрета:
## кнопки пересобираются отложенно (после первого layout), и без этого
## сравнения спидометр остался бы там, где посчитался по догадке 0.62.
var _applied_controls_top: float = -1.0
## Базовые размеры шрифтов и высоты кнопок из сцены — см. `_scale_font_size()`.
var _base_font_sizes: Dictionary = {}
var _base_min_heights: Dictionary = {}
## Смещения панелей из .tscn: к ним возвращаемся в альбоме после портрета.
var _scene_offsets: Dictionary = {}


func _ready() -> void:
	if hud_style == null:
		hud_style = RallyHudStyle.load_default() as RallyHudStyle
	_capture_classic_styles()
	if auto_apply_on_ready:
		apply_hud_style()
	if sync_cockpit_camera_from_vehicle and not Engine.is_editor_hint():
		_try_bind_scene_vehicle()
	_apply_cockpit_visibility()
	if not Engine.is_editor_hint():
		_apply_ui_scale()
		_cache_scene_offsets()
		_apply_orientation()
		var viewport := get_viewport()
		if viewport != null:
			if not viewport.size_changed.is_connected(_apply_orientation):
				viewport.size_changed.connect(_apply_orientation)
			if not viewport.size_changed.is_connected(_on_viewport_resized):
				viewport.size_changed.connect(_on_viewport_resized)
		var controls := get_node_or_null(touch_controls_path)
		if controls != null and controls.has_signal("layout_changed"):
			if not controls.is_connected("layout_changed", Callable(self, "_apply_orientation")):
				controls.connect("layout_changed", Callable(self, "_apply_orientation"))


## Крупность шрифтов HUD и модалок для телефона/браузера.
##
## В сцене все размеры нарисованы под 1080 px короткой стороны ПК. На
## телефоне та же канва растянута на 6", и 12–15 px — это 2 мм текста.
## Множитель берётся из `RallyScreenLayout`: ландшафт +15 %, портрет +5 %.
## Это шрифты, а не `scale`: панели остаются на местах, буквы крупнее.
func _apply_ui_scale() -> void:
	if not is_inside_tree():
		return
	var amount: float = LayoutType.ui_scale()
	for container in [self, get_node_or_null(pause_panel_path), get_node_or_null(results_panel_path),
			get_node_or_null(stage_panel_path), get_node_or_null(radio_card_path),
			get_node_or_null(timer_panel_path), get_node_or_null(delta_panel_path)]:
		if container == null:
			continue
		for node in container.find_children("*", "Label", true, false):
			var label := node as Label
			if label == null:
				continue
			_scale_font_size(label, amount)
		for node in container.find_children("*", "Button", true, false):
			var button := node as Button
			if button == null:
				continue
			_scale_font_size(button, amount)
			# Палец толще курсора: на телефоне кнопки ещё и выше.
			var key := button.get_instance_id()
			if not _base_min_heights.has(key):
				_base_min_heights[key] = button.custom_minimum_size.y
			var base_min: float = float(_base_min_heights[key])
			if amount > 1.0 and base_min > 0.0 and base_min < 44.0:
				button.custom_minimum_size = Vector2(button.custom_minimum_size.x, 44.0)
			elif base_min > 0.0:
				button.custom_minimum_size = Vector2(button.custom_minimum_size.x, base_min)


## Базовый (из сцены) размер шрифта помним по узлу: поворот телефона меняет
## множитель, а не копит его. Без кэша каждый поворот умножал бы уже
## увеличенный размер, и после двух альбомов текст уезжал за экран.
func _scale_font_size(ctrl: Control, amount: float) -> void:
	var key := ctrl.get_instance_id()
	if not _base_font_sizes.has(key):
		var scene_size: int = ctrl.get_theme_font_size("font_size")
		if scene_size <= 0:
			return
		_base_font_sizes[key] = scene_size
	var base_size: int = int(_base_font_sizes[key])
	if base_size <= 0:
		return
	# Не `remove_theme_font_size_override()`: в .tscn размер приходит именно
	# оверрайдом узла, и снятие сбросило бы его на дефолт темы — на ПК, где
	# множитель 1.0, HUD перестал бы совпадать со сценой. При 1.0 записываем
	# базовое значение обратно, визуально это no-op.
	ctrl.add_theme_font_size_override("font_size", maxi(8, roundi(float(base_size) * amount)))


## Поворот/ресайз: крупность могла смениться (альбом 1.15 ↔ портрет 1.05),
## а вместе с ней и раскладка. `_apply_orientation()` сам решает, нужно ли
## переставлять панели, поэтому вызываем оба всегда — это дешёвые итерации
## по десятку узлов только на событии размера, не в кадре.
func _on_viewport_resized() -> void:
	if Engine.is_editor_hint():
		return
	_apply_ui_scale()
	_apply_orientation()


## Кэш смещений/якорей из сцены: в портрете панели получают новые, а в
## альбоме возвращаются ровно к тем, что нарисованы в редакторе.
func _cache_scene_offsets() -> void:
	for path in [
		stage_panel_path, radio_card_path, timer_panel_path, delta_panel_path,
		mini_map_path, speed_panel_path, fps_label_path, clutch_notice_path,
		pause_panel_path, results_panel_path,
	]:
		var ctrl := get_node_or_null(path) as Control
		if ctrl == null or _scene_offsets.has(path):
			continue
		_scene_offsets[path] = {
			"anchors": [ctrl.anchor_left, ctrl.anchor_top, ctrl.anchor_right, ctrl.anchor_bottom],
			"offsets": [ctrl.offset_left, ctrl.offset_top, ctrl.offset_right, ctrl.offset_bottom],
		}


## Портрет: HUD перестраивается под высокий экран.
##
## В альбоме панели стоят по краям 16:9-канвы и не мешают друг другу. В
## портрете та же раскладка превращается в кашу: панель этапа и радио
## занимают всю ширину, таймер и дельта лежат друг на друге, спидометр
## закрывает кнопки газа. Здесь разводим их по полосам:
##
##   верх   — этап, радио, FPS;
##   центр  — таймер, дельта, уведомление о сцеплении;
##   низ    — мини-карта слева, спидометр справа, пальцы по центру-низу.
func _apply_orientation() -> void:
	if Engine.is_editor_hint() or _scene_offsets.is_empty():
		return
	var canvas: Vector2 = _canvas_size()
	var portrait: bool = LayoutType.is_portrait(canvas)
	var wanted: String = "portrait" if portrait else "landscape"
	var same_canvas: bool = canvas.distance_squared_to(_applied_canvas) < 1.0
	var controls_top: float = _controls_top(canvas)
	var same_band: bool = absf(controls_top - _applied_controls_top) < 1.0
	if wanted == _applied_layout and (not portrait or (same_canvas and same_band)):
		return
	_applied_layout = wanted
	_applied_canvas = canvas
	_applied_controls_top = controls_top
	if portrait:
		_apply_portrait_layout(canvas)
	else:
		_restore_scene_layout()


func _restore_scene_layout() -> void:
	for path in _scene_offsets.keys():
		var ctrl := get_node_or_null(path) as Control
		if ctrl == null:
			continue
		var saved: Dictionary = _scene_offsets[path]
		var anchors: Array = saved["anchors"]
		var offsets: Array = saved["offsets"]
		ctrl.anchor_left = float(anchors[0])
		ctrl.anchor_top = float(anchors[1])
		ctrl.anchor_right = float(anchors[2])
		ctrl.anchor_bottom = float(anchors[3])
		ctrl.offset_left = float(offsets[0])
		ctrl.offset_top = float(offsets[1])
		ctrl.offset_right = float(offsets[2])
		ctrl.offset_bottom = float(offsets[3])


## Поставить панель прямоугольником в координатах канвы.
func _place(ctrl: Control, rect: Rect2) -> void:
	if ctrl == null:
		return
	ctrl.anchor_left = 0.0
	ctrl.anchor_top = 0.0
	ctrl.anchor_right = 0.0
	ctrl.anchor_bottom = 0.0
	ctrl.offset_left = rect.position.x
	ctrl.offset_top = rect.position.y
	ctrl.offset_right = rect.position.x + rect.size.x
	ctrl.offset_bottom = rect.position.y + rect.size.y


func _apply_portrait_layout(canvas: Vector2 = Vector2.ZERO) -> void:
	if canvas.x <= 0.0 or canvas.y <= 0.0:
		canvas = _canvas_size()
	var margin: float = maxf(8.0, portrait_margin)
	var width: float = maxf(320.0, canvas.x)
	var height: float = maxf(480.0, canvas.y)
	var available: float = maxf(200.0, width - margin * 2.0)
	# Верхний ряд выше ландшафтной панели радио (100 px), иначе карточка
	# радио обрезается по высоте: она рассчитана на две строки текста.
	var top_height: float = clampf(width * 0.10, 96.0, 220.0)
	var fps_height: float = 46.0
	var gap: float = 8.0

	# --- Верх: этап и радио в две колонки ---
	# Обе панели — PanelContainer: их минимум (две строки текста) тоже
	# уважаем, иначе содержимое обрезается или панель растёт поверх FPS.
	# Сначала отдаём место радио (ему нужен минимум под текст песни), остаток
	# — этапу; на очень узкой канве этап ужимается первым.
	var stage_panel := get_node_or_null(stage_panel_path) as Control
	var radio_card := get_node_or_null(radio_card_path) as Control
	var radio_width: float = clampf(available * 0.42, 260.0, 460.0)
	if radio_card != null:
		var radio_min := radio_card.get_combined_minimum_size()
		radio_width = maxf(radio_width, radio_min.x)
		top_height = maxf(top_height, radio_min.y)
	radio_width = minf(radio_width, maxf(120.0, available - gap - 80.0))
	var stage_width: float = maxf(80.0, available - radio_width - gap)
	if stage_panel != null:
		var stage_min := stage_panel.get_combined_minimum_size()
		stage_width = maxf(stage_width, minf(stage_min.x, available - radio_width - gap))
		top_height = maxf(top_height, stage_min.y)
	_place(stage_panel, Rect2(Vector2(margin, margin), Vector2(stage_width, top_height)))
	_place(radio_card, Rect2(Vector2(margin + stage_width + gap, margin),
		Vector2(radio_width, top_height)))

	# --- FPS: своя короткая строка под верхним рядом, у правого края ---
	var fps_top: float = margin + top_height + gap
	var fps := get_node_or_null(fps_label_path) as Control
	if fps != null:
		_place(fps, Rect2(Vector2(width - margin - 190.0, fps_top), Vector2(190.0, fps_height)))

	# --- Центр: таймер и дельта во всю ширину под FPS ---
	var timer_top: float = fps_top + fps_height + gap
	# Таймер — тоже PanelContainer (подпись, спрайт времени и отсечка): его
	# минимум выше «на глаз», и без max() панель вырастала на дельту.
	var timer_panel := get_node_or_null(timer_panel_path) as Control
	var timer_height: float = maxf(72.0, top_height * 0.82)
	if timer_panel != null:
		timer_height = maxf(timer_height, timer_panel.get_combined_minimum_size().y)
	_place(timer_panel, Rect2(Vector2(margin, timer_top), Vector2(available, timer_height)))
	var delta_top: float = timer_top + timer_height + gap
	var delta_panel := get_node_or_null(delta_panel_path) as Control
	var delta_height: float = maxf(52.0, top_height * 0.6)
	if delta_panel != null:
		delta_height = maxf(delta_height, delta_panel.get_combined_minimum_size().y)
	_place(delta_panel, Rect2(Vector2(margin, delta_top), Vector2(available, delta_height)))
	var clutch := get_node_or_null(clutch_notice_path) as Control
	if clutch != null:
		_place(clutch, Rect2(Vector2(margin, delta_top + delta_height + gap),
			Vector2(available, maxf(40.0, top_height * 0.5))))

	# --- Низ: мини-карта и спидометр в полосе НАД кнопками ---
	# Панель спидометра — PanelContainer с восемью строками телеметрии: её
	# минимальный размер больше назначенного вручную, и Godot вырастил бы её
	# вниз, снова на кнопки. Берём максимум из желаемого и минимального и
	# только потом прижимаем к верху полосы кнопок.
	var speed_panel := get_node_or_null(speed_panel_path) as Control
	var speed_min := Vector2.ZERO
	if speed_panel != null:
		speed_min = speed_panel.get_combined_minimum_size()
	var controls_top: float = _controls_top(canvas)
	var bottom_limit: float = clampf(controls_top - margin, height * 0.35, height - margin)
	var band_height: float = maxf(120.0, bottom_limit - timer_top)
	var speed_height: float = clampf(maxf(portrait_speed_height, speed_min.y), 120.0, band_height)
	var speed_width: float = minf(available * 0.52, maxf(maxf(260.0, speed_min.x), speed_height * 1.5))
	speed_width = minf(speed_width, available)
	var speed_rect := Rect2(
		Vector2(width - margin - speed_width, bottom_limit - speed_height),
		Vector2(speed_width, speed_height)
	)
	_place(speed_panel, speed_rect)
	var map_width: float = minf(available - speed_width - gap, maxf(160.0, portrait_minimap_width))
	_place(get_node_or_null(mini_map_path) as Control,
		Rect2(Vector2(margin, speed_rect.position.y), Vector2(maxf(140.0, map_width), speed_rect.size.y)))

	# --- Модалки: на высоком экране им тесно в 620×970 по центру ---
	_place_modal(get_node_or_null(pause_panel_path) as Control, canvas, margin, 0.62)
	_place_modal(get_node_or_null(results_panel_path) as Control, canvas, margin, 0.45)


## Верх сенсорных кнопок в координатах HUD. `content_top()` отдаёт
## фактический прямоугольник нарисованных кнопок; если TouchControls ещё не
## посчитал зоны (или его нет, как в тестовой сцене), берём долю экрана,
## которую кнопки занимают по умолчанию.
func _controls_top(canvas: Vector2) -> float:
	var controls := get_node_or_null(touch_controls_path)
	if controls != null and controls.has_method("content_top"):
		var top := float(controls.call("content_top"))
		if top > 0.0:
			return top
	return canvas.y * 0.62


## Размер канвы (не Control.size: при stretch=canvas_items это одно и то же,
## но viewport успевает обновиться раньше, чем пройдёт layout детей).
func _canvas_size() -> Vector2:
	var viewport := get_viewport()
	if viewport != null:
		var visible_size: Vector2 = viewport.get_visible_rect().size
		if visible_size.x > 0.0 and visible_size.y > 0.0:
			return visible_size
	return LayoutType.screen_size()


## Модальная панель: ширина канвы минус поля, высота — доля экрана. Так
## настройки паузы (слайдеры и вкладки) остаются в экране и прокручиваются,
## а не уезжают за нижний край. В портрете канва выше, чем широкий 16:9
## макет паузы: 620 px ширины — это треть экрана, поэтому панель тянется на
## всю доступную ширину.
func _place_modal(ctrl: Control, canvas: Vector2, margin: float, height_ratio: float) -> void:
	if ctrl == null:
		return
	var modal_height: float = clampf(canvas.y * height_ratio, 320.0, canvas.y - margin * 2.0)
	_place(ctrl, Rect2(
		Vector2(margin, (canvas.y - modal_height) * 0.5),
		Vector2(maxf(320.0, canvas.x - margin * 2.0), modal_height)
	))


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or not sync_cockpit_camera_from_vehicle:
		return
	if _bound_vehicle == null or not is_instance_valid(_bound_vehicle):
		_try_bind_scene_vehicle()
	if _bound_vehicle != null and "camera_mode" in _bound_vehicle:
		var v_mode: int = int(_bound_vehicle.get("camera_mode"))
		if v_mode != _current_camera_mode:
			set_camera_mode(v_mode)


func bind_vehicle(vehicle: Node) -> void:
	if _bound_vehicle != null and is_instance_valid(_bound_vehicle):
		if _bound_vehicle.has_signal("camera_mode_changed"):
			var prev_cb := Callable(self, "_on_vehicle_camera_mode_changed")
			if _bound_vehicle.is_connected("camera_mode_changed", prev_cb):
				_bound_vehicle.disconnect("camera_mode_changed", prev_cb)
	_bound_vehicle = vehicle
	if _bound_vehicle != null and is_instance_valid(_bound_vehicle):
		if _bound_vehicle.has_signal("camera_mode_changed"):
			var cb := Callable(self, "_on_vehicle_camera_mode_changed")
			if not _bound_vehicle.is_connected("camera_mode_changed", cb):
				_bound_vehicle.connect("camera_mode_changed", cb)
		if "camera_mode" in _bound_vehicle:
			set_camera_mode(int(_bound_vehicle.get("camera_mode")))
	var speedo := get_speedometer()
	if speedo != null and _bound_vehicle != null:
		speedo.bind_vehicle(_bound_vehicle)


func _try_bind_scene_vehicle() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	var cars := tree.get_nodes_in_group("rally_car")
	if not cars.is_empty():
		bind_vehicle(cars[0])


func _on_vehicle_camera_mode_changed(new_mode: int) -> void:
	set_camera_mode(new_mode)


func set_camera_mode(mode: int) -> void:
	var clamped: int = clampi(mode, 0, 2)
	var prev_cockpit: bool = is_cockpit_view()
	_current_camera_mode = clamped
	_apply_cockpit_visibility()
	var now_cockpit: bool = is_cockpit_view()
	if prev_cockpit != now_cockpit:
		cockpit_mode_changed.emit(now_cockpit)


func is_cockpit_view() -> bool:
	return _current_camera_mode == 2


func _should_hide_in_cockpit() -> Dictionary:
	var result := {
		"speed": false,
		"radio": false,
		"telemetry": false,
		"stage": false,
		"timer": false,
		"delta": false,
		"mini_map": false,
		"fps": false,
		"hint": false,
	}
	if not is_cockpit_view():
		return result
	if cockpit_hide_mode == CockpitHideMode.KEEP_ALL_HUD:
		return result
	if cockpit_hide_mode == CockpitHideMode.FORCE_HIDE_REDUNDANT:
		result["speed"] = true
		result["radio"] = true
		return result
	if hud_style == null:
		result["speed"] = true
		result["radio"] = true
		return result
	if not hud_style.cockpit_hide_redundant_hud:
		return result
	result["speed"] = hud_style.cockpit_hide_speed_panel
	result["radio"] = hud_style.cockpit_hide_radio_card
	result["telemetry"] = hud_style.cockpit_hide_telemetry_panel
	result["stage"] = hud_style.cockpit_hide_stage_panel
	result["timer"] = hud_style.cockpit_hide_timer_panel
	result["delta"] = hud_style.cockpit_hide_delta_panel
	result["mini_map"] = hud_style.cockpit_hide_mini_map
	result["fps"] = hud_style.cockpit_hide_fps
	result["hint"] = hud_style.cockpit_hide_hint
	return result


func _apply_cockpit_visibility() -> void:
	var flags: Dictionary = _should_hide_in_cockpit()
	var delta_node := get_delta_panel()
	if delta_node != null and delta_node.has_method("set_cockpit_hidden"):
		delta_node.call("set_cockpit_hidden", bool(flags["delta"]))
	var mapping := [
		[speed_panel_path, bool(flags["speed"])],
		[radio_card_path, bool(flags["radio"])],
		[telemetry_panel_path, bool(flags["telemetry"])],
		[stage_panel_path, bool(flags["stage"])],
		[timer_panel_path, bool(flags["timer"])],
		[mini_map_path, bool(flags["mini_map"])],
		[fps_label_path, bool(flags["fps"])],
		[hint_label_path, bool(flags["hint"])],
	]
	for entry in mapping:
		var ctrl_path: NodePath = entry[0]
		var should_hide: bool = bool(entry[1])
		var ctrl_node := get_node_or_null(ctrl_path) as Control
		if ctrl_node == null:
			continue
		if should_hide:
			if not _cockpit_hidden_nodes.has(ctrl_path):
				_cockpit_hidden_nodes[ctrl_path] = ctrl_node.visible
			ctrl_node.visible = false
		elif _cockpit_hidden_nodes.has(ctrl_path):
			var prev_vis: bool = bool(_cockpit_hidden_nodes[ctrl_path])
			_cockpit_hidden_nodes.erase(ctrl_path)
			ctrl_node.visible = prev_vis


func set_hud_style(style_res: RallyHudStyle) -> void:
	hud_style = style_res


func set_pixel_mode(enabled: bool) -> void:
	theme_mode = ThemeMode.SPEEDOMETER_PIXEL if enabled else ThemeMode.KEEP_CLASSIC_PANELS


func is_pixel_mode() -> bool:
	match theme_mode:
		ThemeMode.SPEEDOMETER_PIXEL:
			return true
		ThemeMode.KEEP_CLASSIC_PANELS:
			return false
	return hud_style != null and hud_style.is_pixel_mode()


func get_speedometer() -> SpriteSpeedometer:
	return get_node_or_null(speedometer_path) as SpriteSpeedometer


func get_delta_panel() -> Control:
	return get_node_or_null(delta_panel_path) as Control


func _on_hud_style_changed() -> void:
	if is_inside_tree():
		apply_hud_style()


func apply_hud_style() -> void:
	if hud_style == null:
		hud_style = RallyHudStyle.load_default() as RallyHudStyle
	if not _classic_captured:
		_capture_classic_styles()

	var pixel_active := is_pixel_mode()
	var effective_style: RallyHudStyle = _effective_style_copy(pixel_active)

	var speedo := get_speedometer()
	if speedo != null:
		speedo.set_hud_style(effective_style)

	var mini := get_node_or_null(mini_map_path)
	if mini != null and mini.has_method("set_hud_style"):
		mini.call("set_hud_style", effective_style)

	var fps := get_node_or_null(fps_label_path)
	if fps != null and fps.has_method("set_hud_style"):
		fps.call("set_hud_style", effective_style)

	var delta_p := get_delta_panel()
	if delta_p != null and delta_p.has_method("set_hud_style"):
		delta_p.call("set_hud_style", effective_style)

	var radio := get_node_or_null(radio_card_path)
	# rally_radio_card.gd — не @tool: в редакторе это placeholder-инстанс и
	# вызов apply_hud_style даёт ошибку. В рантайме карточка сама применит
	# стиль в _ready().
	if radio != null and not Engine.is_editor_hint() and radio.has_method("apply_hud_style"):
		radio.call("apply_hud_style", effective_style)

	var tele_box := get_node_or_null(telemetry_box_path)
	if tele_box != null:
		for child in tele_box.get_children():
			if child.has_method("set_hud_style"):
				child.call("set_hud_style", effective_style)

	_apply_panel_theming(pixel_active, effective_style)
	_sync_timer_sprite(pixel_active, effective_style)
	_sync_speedometer_mode()
	_apply_cockpit_visibility()
	hud_style_applied.emit(pixel_active)


func _effective_style_copy(pixel_active: bool) -> RallyHudStyle:
	if hud_style == null:
		return RallyHudStyle.new()
	if pixel_active == hud_style.is_pixel_mode():
		return hud_style
	var copy := hud_style.duplicate() as RallyHudStyle
	if copy == null:
		return hud_style
	copy.hud_mode = RallyHudStyle.HudMode.SPEEDOMETER_PIXEL if pixel_active else RallyHudStyle.HudMode.CLASSIC_GLASS
	return copy


func _sync_speedometer_mode() -> void:
	var speedo := get_speedometer()
	var speed_box := get_node_or_null(speed_box_path) as Control
	if speedo != null:
		match speedometer_display:
			SpeedometerDisplayMode.SPRITE_SPEEDOMETER:
				speedo.visible = true
				speedo.sync_speed_box_visibility = true
				if speed_box != null:
					speed_box.visible = not speedo.is_atlas_ready()
			SpeedometerDisplayMode.CLASSIC_TEXT_BOX:
				speedo.visible = false
				if speed_box != null:
					speed_box.visible = true
			SpeedometerDisplayMode.BOTH:
				speedo.sync_speed_box_visibility = false
				speedo.visible = true
				if speed_box != null:
					speed_box.visible = true
	elif speed_box != null:
		speed_box.visible = true
	_apply_cockpit_visibility()


func _sync_timer_sprite(pixel_active: bool, effective_style: RallyHudStyle) -> void:
	var t_lbl := get_node_or_null(timer_label_path) as Label
	var t_spr := get_node_or_null(timer_sprite_path) as SpriteCounter
	var use_spr := pixel_active and effective_style.use_sprite_digits_for_timer and t_spr != null
	if t_spr != null:
		t_spr.set_hud_style(effective_style)
		t_spr.digit_height_px = effective_style.timer_digit_height
		if t_lbl != null:
			t_spr.set_value_text(t_lbl.text)
		use_spr = use_spr and t_spr.is_atlas_ready()
		t_spr.visible = use_spr
	if t_lbl != null:
		t_lbl.visible = not use_spr


func update_timer_display(time_text: String, split_text: String = "", split_col: Color = Color(-1.0, 0.0, 0.0, 0.0)) -> void:
	var t_lbl := get_node_or_null(timer_label_path) as Label
	if t_lbl != null:
		t_lbl.text = time_text
	var t_spr := get_node_or_null(timer_sprite_path) as SpriteCounter
	if t_spr != null:
		t_spr.set_value_text(time_text)
	if not split_text.is_empty():
		var s_lbl := get_node_or_null(split_label_path) as Label
		if s_lbl != null:
			s_lbl.text = split_text
			if split_col.r >= 0.0:
				s_lbl.add_theme_color_override("font_color", split_col)


func update_speed_telemetry(
	new_speed_kmh: float,
	new_rpm: float,
	new_max_rpm: float,
	new_gear: String,
	new_redline: bool = false,
	trans_text: String = "",
	drive_text: String = ""
) -> void:
	var speedo := get_speedometer()
	if speedo != null:
		if not trans_text.is_empty():
			speedo.transmission_text = trans_text
		if not drive_text.is_empty():
			speedo.drivetrain_text = drive_text
		speedo.set_telemetry(new_speed_kmh, new_rpm, new_max_rpm, new_gear, new_redline)


func _capture_classic_styles() -> void:
	_classic_captured = true
	for p in [stage_panel_path, timer_panel_path, telemetry_panel_path, pause_panel_path, results_panel_path]:
		var ctrl := get_node_or_null(p) as Control
		if ctrl != null and ctrl.has_theme_stylebox_override("panel"):
			_saved_panel_styles[p] = ctrl.get_theme_stylebox("panel")
	for lp in [hint_label_path, clutch_notice_path]:
		var lbl := get_node_or_null(lp) as Label
		if lbl != null and lbl.has_theme_stylebox_override("normal"):
			_saved_label_styles[lp] = lbl.get_theme_stylebox("normal")
	_capture_buttons_under(get_node_or_null(pause_panel_path))
	_capture_buttons_under(get_node_or_null(results_panel_path))


func _capture_buttons_under(root_node: Node) -> void:
	if root_node == null:
		return
	for child in root_node.get_children():
		if child is Button:
			var btn := child as Button
			var key := str(btn.get_path())
			var map := {}
			for st in ["normal", "hover", "pressed", "focus"]:
				if btn.has_theme_stylebox_override(st):
					map[st] = btn.get_theme_stylebox(st)
			if not map.is_empty():
				_saved_button_styles[key] = map
		_capture_buttons_under(child)


func _apply_panel_theming(pixel_active: bool, style_res: RallyHudStyle) -> void:
	if not pixel_active:
		for p in _saved_panel_styles.keys():
			var ctrl := get_node_or_null(p) as Control
			if ctrl != null:
				ctrl.add_theme_stylebox_override("panel", _saved_panel_styles[p])
		for lp in _saved_label_styles.keys():
			var lbl := get_node_or_null(lp) as Label
			if lbl != null:
				lbl.add_theme_stylebox_override("normal", _saved_label_styles[lp])
		_restore_buttons_under(get_node_or_null(pause_panel_path))
		_restore_buttons_under(get_node_or_null(results_panel_path))
		return

	var stage_p := get_node_or_null(stage_panel_path) as Control
	if stage_p != null:
		stage_p.add_theme_stylebox_override("panel", style_res.make_panel_style(true, false))
	var timer_p := get_node_or_null(timer_panel_path) as Control
	if timer_p != null:
		timer_p.add_theme_stylebox_override("panel", style_res.make_panel_style(false, true))
	var tele_p := get_node_or_null(telemetry_panel_path) as Control
	if tele_p != null:
		tele_p.add_theme_stylebox_override("panel", style_res.make_panel_style(true, false))
	var pause_p := get_node_or_null(pause_panel_path) as Control
	if pause_p != null:
		pause_p.add_theme_stylebox_override("panel", style_res.make_panel_style(false, true))
	var res_p := get_node_or_null(results_panel_path) as Control
	if res_p != null:
		res_p.add_theme_stylebox_override("panel", style_res.make_panel_style(false, true))

	var hint_s := style_res.make_hint_style()
	for lp in [hint_label_path, clutch_notice_path]:
		var lbl := get_node_or_null(lp) as Label
		if lbl != null:
			lbl.add_theme_stylebox_override("normal", hint_s)

	_apply_buttons_under(get_node_or_null(pause_panel_path), style_res)
	_apply_buttons_under(get_node_or_null(results_panel_path), style_res)


func _apply_buttons_under(root_node: Node, style_res: RallyHudStyle) -> void:
	if root_node == null:
		return
	for child in root_node.get_children():
		if child is Button:
			var btn := child as Button
			for st in ["normal", "hover", "pressed", "focus"]:
				btn.add_theme_stylebox_override(st, style_res.make_button_style(st))
		_apply_buttons_under(child, style_res)


func _restore_buttons_under(root_node: Node) -> void:
	if root_node == null:
		return
	for child in root_node.get_children():
		if child is Button:
			var btn := child as Button
			var key := str(btn.get_path())
			if _saved_button_styles.has(key):
				var map: Dictionary = _saved_button_styles[key]
				for st in map.keys():
					btn.add_theme_stylebox_override(str(st), map[st])
		_restore_buttons_under(child)
