## Выноски-инфографика гаража: от частей машины на 3D-витрине идут линии к
## карточкам с главными цифрами. Мотор — от капота, подвеска — от верха стойки
## переднего колеса, колёса и тормоза — от боковины заднего колеса, привод —
## от заднего моста, внешность — от двери. Колесо и дверь берутся с той
## стороны, что смотрит в камеру; карточки сами расходятся влево и вправо от
## машины и плавно переезжают, когда она поворачивается.
##
## Узел %Callouts сцены гаража; поля ниже правятся в инспекторе.
class_name GarageCallouts
extends Control

## Нажали на карточку части (id группы из car_customization.gd).
signal part_pressed(id: String)

## Части машины: id группы настроек → подпись карточки. Порядок — обход с
## клавиатуры.
const PART_ORDER := ["engine", "suspension", "tires", "drivetrain", "appearance"]
const PART_CAPTIONS := {
	"engine": "МОТОР",
	"suspension": "ПОДВЕСКА",
	"tires": "КОЛЁСА И ТОРМОЗА",
	"drivetrain": "ПРИВОД И МАССА",
	"appearance": "ВНЕШНОСТЬ",
}
## Метка модели: габариты кузова для точек выносок (считаются один раз).
const ANCHOR_META := "garage_anchor_data"

## Ширина карточки, пиксели.
@export_range(160.0, 480.0, 1.0) var card_width: float = 250.0
## Отступ карточек от края экрана, пиксели.
@export_range(0.0, 400.0, 1.0) var card_margin: float = 48.0
## Свободная полоса сверху и снизу под меню, доля высоты экрана.
@export_range(0.0, 0.45, 0.01) var free_top: float = 0.24
@export_range(0.0, 0.45, 0.01) var free_bottom: float = 0.16
## Длина горизонтального участка линии у карточки, пиксели.
@export_range(0.0, 200.0, 1.0) var elbow_length: float = 40.0
## Цвета: акцент (точки, подсветка) и спокойная линия.
@export var accent: Color = Color(1.0, 0.58, 0.08, 1.0)
@export var line_color: Color = Color(0.86, 0.9, 0.94, 0.55)

## Камера и вьюпорт витрины, модель и её колёса — задаёт гараж.
var camera: Camera3D = null
var viewport: SubViewport = null
var model: Node3D = null
var wheels: Array[Dictionary] = []
## Открытая часть: остальные карточки прячутся, линия идёт к панели.
var active_part := ""
## Куда тянуть линию открытой части (глобальная точка у панели настроек).
var focus_point := Vector2.ZERO

var _cards: Dictionary = {}
var _parts: Dictionary = {}
var _pos: Dictionary = {}
var _side: Dictionary = {}
var _screen: Dictionary = {}
var _placed := false
var _hover := ""
var _styles: Array[StyleBoxFlat] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_styles = [_card_style(false), _card_style(true)]
	for id: String in PART_ORDER:
		_build_card(id)


## Карточки встанут на места сразу, без переезда (смена машины, вход).
func reset_layout() -> void:
	_placed = false


func card(id: String) -> Control:
	return _cards.get(id) as Control


## Экранные точки выносок, видимые в последнем кадре: id → Vector2.
func anchor_points() -> Dictionary:
	return _screen.duplicate()


func _build_card(id: String) -> void:
	var panel := PanelContainer.new()
	panel.name = "Callout" + id.to_pascal_case()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.focus_mode = Control.FOCUS_ALL
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.custom_minimum_size = Vector2(card_width, 0.0)
	panel.tooltip_text = "Настроить: " + String(PART_CAPTIONS[id]).to_lower()
	panel.add_theme_stylebox_override("panel", _styles[0])
	add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	var title := _label(String(PART_CAPTIONS[id]), 13, accent)
	box.add_child(title)
	var value := _label("", 18, Color(0.96, 0.97, 0.98))
	box.add_child(value)
	var sub := _label("", 13, Color(0.6, 0.69, 0.76))
	box.add_child(sub)
	var bar := ProgressBar.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.step = 0.0
	bar.custom_minimum_size = Vector2(0.0, 4.0)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(1, 1, 1, 0.1)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = accent
	bar.add_theme_stylebox_override("background", bar_bg)
	bar.add_theme_stylebox_override("fill", bar_fill)
	box.add_child(bar)
	var swatch := ColorRect.new()
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.custom_minimum_size = Vector2(0.0, 4.0)
	swatch.visible = false
	box.add_child(swatch)
	_cards[id] = panel
	_parts[id] = {"value": value, "sub": sub, "bar": bar, "swatch": swatch}
	_side[id] = -1
	panel.gui_input.connect(_on_card_input.bind(id))
	panel.mouse_entered.connect(_set_hover.bind(id, true))
	panel.mouse_exited.connect(_set_hover.bind(id, false))
	panel.focus_entered.connect(_set_hover.bind(id, true))
	panel.focus_exited.connect(_set_hover.bind(id, false))


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _card_style(hot: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.045, 0.06, 0.88 if hot else 0.7)
	style.border_color = accent if hot else Color(accent, 0.55)
	style.border_width_left = 3
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 8.0
	return style


func _set_hover(id: String, hot: bool) -> void:
	if hot:
		_hover = id
	elif _hover == id:
		_hover = ""


func _on_card_input(event: InputEvent, id: String) -> void:
	var click := event is InputEventMouseButton and event.pressed
	if click and (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	if click or event.is_action_pressed("ui_accept"):
		(_cards[id] as Control).accept_event()
		part_pressed.emit(id)


# ---------------------------------------------------------------------------
# Цифры на карточках
# ---------------------------------------------------------------------------


## Главное из каждой группы настроек. livery_labels — подписи ливрей машины.
func refresh(setup: RallyCarSetup, livery_labels: Array[String], finishes: Array) -> void:
	if setup == null or _parts.is_empty():
		return
	set_card(
		"engine",
		"%d Н·м  ·  %d об/мин" % [roundi(setup.max_torque), roundi(setup.max_rpm)],
		"%s  ·  %d передач" % ["Турбо" if setup.turbo else "Атмо", setup.gear_ratios.size()],
		inverse_lerp(100.0, 900.0, setup.max_torque)
	)
	var split := setup.awd_front_torque
	if setup.drivetrain == RallyCarSetup.Drivetrain.RWD:
		split = 0.0
	elif setup.drivetrain == RallyCarSetup.Drivetrain.FWD:
		split = 1.0
	set_card(
		"drivetrain",
		"%s  ·  %d кг" % [setup.get_drivetrain_name(), roundi(setup.vehicle_mass)],
		(
			"тяга вперёд %d%%  ·  вес на перёд %d%%"
			% [roundi(split * 100.0), roundi(setup.front_weight_distribution * 100.0)]
		),
		split
	)
	set_card(
		"suspension",
		"ход %.2f / %.2f м" % [setup.front_spring_length, setup.rear_spring_length],
		(
			"аморт. %.2f / %.2f  ·  стаб. %.2f / %.2f"
			% [
				setup.front_damping_ratio,
				setup.rear_damping_ratio,
				setup.front_arb_ratio,
				setup.rear_arb_ratio,
			]
		),
		inverse_lerp(0.1, 1.2, (setup.front_damping_ratio + setup.rear_damping_ratio) * 0.5)
	)
	set_card(
		"tires",
		"R %.2f м  ·  %d мм" % [setup.tire_radius, roundi(setup.tire_width)],
		(
			"сцепление %.2f×  ·  тормоза %d%% вперёд"
			% [setup.grip_scale, roundi(setup.front_brake_bias * 100.0)]
		),
		inverse_lerp(0.3, 2.5, setup.grip_scale)
	)
	var livery := ""
	if not livery_labels.is_empty():
		livery = livery_labels[clampi(setup.livery, 0, livery_labels.size() - 1)]
	var finish := ""
	if not finishes.is_empty():
		finish = String(finishes[clampi(setup.paint_finish, 0, finishes.size() - 1)]) + "  ·  "
	set_card("appearance", livery, finish + "#" + setup.body_color.to_html(false).to_upper(), -1.0)
	var swatch := _parts["appearance"]["swatch"] as ColorRect
	swatch.visible = true
	swatch.color = setup.body_color


## Текст карточки; amount 0..1 — полоска, меньше нуля — без полоски.
func set_card(id: String, value: String, sub: String, amount: float) -> void:
	var parts: Dictionary = _parts[id]
	(parts["value"] as Label).text = value
	(parts["sub"] as Label).text = sub
	var bar := parts["bar"] as ProgressBar
	bar.visible = amount >= 0.0
	bar.value = clampf(amount, 0.0, 1.0)


func card_text(id: String) -> String:
	var parts: Dictionary = _parts[id]
	return (parts["value"] as Label).text + "\n" + (parts["sub"] as Label).text


# ---------------------------------------------------------------------------
# Точки на машине
# ---------------------------------------------------------------------------


## Габариты кузова без колёс в координатах модели и точка на капоте.
func anchor_data(target: Node3D) -> Dictionary:
	if target.has_meta(ANCHOR_META):
		return target.get_meta(ANCHOR_META)
	var wheel_nodes: Array[Node] = []
	for entry: Dictionary in wheels:
		var node := entry.get("node") as Node
		if node != null and is_instance_valid(node):
			wheel_nodes.append(node)
	var to_model := target.global_transform.affine_inverse()
	var points := PackedVector3Array()
	for node in target.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null or _is_wheel_part(mesh_node, wheel_nodes):
			continue
		var xform := to_model * mesh_node.global_transform
		for v in mesh_node.mesh.get_faces():
			points.append(xform * v)
	var box := AABB(Vector3(-0.9, 0.0, -2.1), Vector3(1.8, 1.4, 4.2))
	if not points.is_empty():
		box = AABB(points[0], Vector3.ZERO)
		for p in points:
			box = box.expand(p)
	# Капот: самая высокая точка передней четверти кузова у оси машины
	# (перед модели — +Z).
	var length := box.size.z
	var front := box.end.z
	var hood_y := box.position.y + box.size.y * 0.7
	var found := false
	for p in points:
		var in_front := p.z > front - length * 0.32 and p.z < front - length * 0.12
		if in_front and absf(p.x - box.get_center().x) < box.size.x * 0.3:
			hood_y = p.y if not found else maxf(hood_y, p.y)
			found = true
	var data := {"box": box, "hood": Vector3(box.get_center().x, hood_y, front - length * 0.22)}
	target.set_meta(ANCHOR_META, data)
	return data


func _is_wheel_part(node: Node, wheel_nodes: Array[Node]) -> bool:
	for wheel in wheel_nodes:
		if node == wheel or wheel.is_ancestor_of(node):
			return true
	return false


## Центр и радиус колеса в мире: по габаритам меша, а не по началу
## координат узла (у части моделей оно не в центре колеса).
static func wheel_info(wheel: Node3D) -> Dictionary:
	var mesh := wheel as MeshInstance3D
	if mesh == null:
		var children := wheel.find_children("*", "MeshInstance3D", true, false)
		if not children.is_empty():
			mesh = children[0] as MeshInstance3D
	if mesh == null:
		return {"center": wheel.global_position, "radius": 0.33}
	var box := mesh.get_aabb()
	var scale_y := mesh.global_transform.basis.get_scale().y
	return {
		"center": mesh.global_transform * box.get_center(),
		"radius": maxf(box.size.y, box.size.z) * 0.5 * scale_y,
	}


## Точки выносок в мировых координатах витрины: id → Vector3.
func part_anchors() -> Dictionary:
	var out := {}
	if model == null or not is_instance_valid(model) or camera == null:
		return out
	var data := anchor_data(model)
	var box: AABB = data["box"]
	var xf := model.global_transform
	var to_local := xf.affine_inverse()
	var local_cam := to_local * camera.global_position
	var side := 1.0 if local_cam.x >= box.get_center().x else -1.0
	var mid := box.get_center()
	out["engine"] = xf * (data["hood"] as Vector3)
	out["appearance"] = (
		xf
		* Vector3(
			mid.x + side * box.size.x * 0.5,
			box.position.y + box.size.y * 0.5,
			mid.z - box.size.z * 0.05
		)
	)
	var found: Array[Dictionary] = []
	for entry: Dictionary in wheels:
		var node := entry.get("node") as Node3D
		if node != null and is_instance_valid(node) and node.is_visible_in_tree():
			var info := wheel_info(node)
			found.append(
				{"local": to_local * (info["center"] as Vector3), "radius": info["radius"]}
			)
	if found.size() < 2:
		out["suspension"] = (
			xf
			* Vector3(
				mid.x + side * box.size.x * 0.45, box.size.y * 0.55, box.end.z - box.size.z * 0.2
			)
		)
		out["tires"] = (
			xf
			* Vector3(
				mid.x + side * box.size.x * 0.5,
				box.size.y * 0.22,
				box.position.z + box.size.z * 0.2
			)
		)
		out["drivetrain"] = (
			xf * Vector3(mid.x, box.size.y * 0.25, box.position.z + box.size.z * 0.2)
		)
		return out
	found.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (a["local"] as Vector3).z > (b["local"] as Vector3).z
	)
	var half := found.size() / 2
	var front_wheel: Vector3 = found[0]["local"]
	var rear_wheel: Vector3 = found[found.size() - 1]["local"]
	var rear_sum := Vector3.ZERO
	for i in range(found.size()):
		var local: Vector3 = found[i]["local"]
		var on_side := signf(local.x - mid.x) == side
		if i < half and on_side:
			front_wheel = local
		elif i >= half:
			rear_sum += local
			if on_side:
				rear_wheel = local
	var rear_axle := rear_sum / float(found.size() - half)
	var radius := clampf(float(found[0]["radius"]), 0.15, 0.8)
	# Подвеска — верх стойки над передним колесом, шины — боковина заднего,
	# привод — задний мост (у переднеприводных — передний).
	out["suspension"] = xf * (front_wheel + Vector3(0.0, radius * 1.2, 0.0))
	out["tires"] = xf * (rear_wheel + Vector3(side * 0.1, 0.0, 0.0))
	out["drivetrain"] = xf * Vector3(mid.x, rear_axle.y, rear_axle.z)
	return out


# ---------------------------------------------------------------------------
# Раскладка и рисование
# ---------------------------------------------------------------------------


func tick(delta: float) -> void:
	_screen.clear()
	if camera == null or viewport == null:
		return
	var view := Vector2(viewport.size)
	if view.x <= 0.0 or view.y <= 0.0 or size.x <= 0.0:
		return
	var to_layer := size / view
	var anchors := part_anchors()
	for id: String in anchors:
		var world: Vector3 = anchors[id]
		if not camera.is_position_behind(world):
			_screen[id] = camera.unproject_position(world) * to_layer
	var center_x := size.x * 0.5
	if model != null and is_instance_valid(model):
		var box: AABB = anchor_data(model)["box"]
		var mid := model.global_transform * box.get_center()
		if not camera.is_position_behind(mid):
			center_x = (camera.unproject_position(mid) * to_layer).x
	_layout_cards(center_x, delta)
	queue_redraw()


func _layout_cards(center_x: float, delta: float) -> void:
	# Сторона карточки — по положению точки относительно середины машины, с
	# запасом, чтобы карточки не перескакивали при покачивании.
	var columns := {-1: [], 1: []}
	for id: String in PART_ORDER:
		if not _screen.has(id):
			continue
		var point: Vector2 = _screen[id]
		var side: int = _side[id]
		if not _placed:
			side = -1 if point.x < center_x else 1
		elif side < 0 and point.x > center_x + 40.0:
			side = 1
		elif side > 0 and point.x < center_x - 40.0:
			side = -1
		_side[id] = side
		columns[side].append(id)
	var top := size.y * free_top
	var bottom := size.y * (1.0 - free_bottom)
	var k := 1.0 if not _placed else 1.0 - exp(-delta * 7.0)
	for side: int in columns:
		var ids: Array = columns[side]
		if ids.is_empty():
			continue
		ids.sort_custom(
			func(a: String, b: String) -> bool:
				return (_screen[a] as Vector2).y < (_screen[b] as Vector2).y
		)
		var heights := 0.0
		for id: String in ids:
			heights += (_cards[id] as Control).size.y
		var count := ids.size()
		var gap := clampf((bottom - top - heights) / float(count), 12.0, 70.0)
		var y := (top + bottom - heights - gap * float(count - 1)) * 0.5
		for id: String in ids:
			var panel := _cards[id] as Control
			var x := card_margin if side < 0 else size.x - card_margin - panel.size.x
			var target := Vector2(x, y)
			var current: Vector2 = _pos.get(id, target)
			current = current.lerp(target, k)
			_pos[id] = current
			panel.position = current
			y += panel.size.y + gap
	_placed = true
	for id: String in _cards:
		var panel := _cards[id] as Control
		panel.visible = _screen.has(id) and active_part.is_empty()
		var style := _styles[1 if id == _hover else 0]
		if panel.get_theme_stylebox("panel") != style:
			panel.add_theme_stylebox_override("panel", style)


func _draw() -> void:
	for id: String in _screen:
		var point: Vector2 = _screen[id]
		if not active_part.is_empty():
			if id == active_part:
				var join := get_global_transform().affine_inverse() * focus_point
				_draw_leader(point, join, join + Vector2(-elbow_length, 0.0), true)
			continue
		var panel := _cards[id] as Control
		if not panel.visible:
			continue
		var side: int = _side[id]
		var join := Vector2(
			panel.position.x + panel.size.x if side < 0 else panel.position.x,
			panel.position.y + 14.0
		)
		var elbow := join + Vector2(elbow_length if side < 0 else -elbow_length, 0.0)
		_draw_leader(point, join, elbow, id == _hover)


## Линия выноски: точка на детали → излом → карточка.
func _draw_leader(point: Vector2, join: Vector2, elbow: Vector2, hot: bool) -> void:
	var color := accent if hot else line_color
	draw_polyline(PackedVector2Array([point, elbow, join]), color, 2.0 if hot else 1.4, true)
	draw_circle(join, 2.5, color)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004)
	draw_arc(
		point, 7.0 + pulse * 3.0, 0.0, TAU, 24, Color(accent, 0.35 + 0.3 * (1.0 - pulse)), 1.5, true
	)
	draw_circle(point, 3.5, accent if hot else Color(1, 1, 1, 0.95))
