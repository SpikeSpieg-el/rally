## Лаборатория деформации кузова (Deformation Lab)
## Открывает выбранный автомобиль и наносит удары в карьерную систему
## деформации кузова (CarDamageVisual), чтобы можно было наглядно проверять
## и подбирать параметры вмятин прямо в инспекторе Godot.
##
## Левый клик по кузову — удар в точку клика. Кнопка "Пуск" (или Enter) —
## удар по координатам из инспектора. R — сбросить машину и кузов,
## Esc — скрыть/показать подсказку и статус.
@tool
extends Node3D

class_name DeformationLab

const CarModels = preload("res://scripts/car_models.gd")

## Подсказка по управлению (также отображается в 3D-viewport как Label3D).
@export_group("Подсказка")
@export var show_overlay: bool = true

## Автомобиль из каталога CarModels (res://data/vehicles/*.tres).
@export_group("Автомобиль")
@export var car_id: String = "mitsubishi"
@export var spawn_distance: float = 6.0
@export var spawn_height: float = 1.4
@export var spawn_rotation_deg: float = 0.0

## Параметры камеры-обозревателя.
@export_group("Камера")
@export var camera_orbit_pitch_deg: float = -14.0
@export var camera_orbit_min_zoom: float = 2.0
@export var camera_orbit_max_zoom: float = 22.0

## Параметры удара, применимого кнопкой Пуск / горячей клавишей.
## Координаты задаются в локальных координатах кузова (пространство,
## в котором CarDamageVisual принимает точки удара).
@export_group("Удар (для кнопки Пуск)")
@export var impact_point_local: Vector3 = Vector3(0.9, 0.8, 0.6)
@export var impact_push_dir: Vector3 = Vector3(-1.0, 0.0, 0.0)
@export var impact_speed_mps: float = 12.0

## Если задать > 0, удары наносятся автоматически с таким интервалом в мс.
@export var auto_punch_interval_ms: int = 0

## Ресурс с настройками деформации (тот же, что использует RallyCar).
## Если не задан — берётся res://data/car/default_damage_visual.tres.
@export var damage_config: RallyDamageVisualConfig = null

var car_root: Node3D = null
var damage_visual: CarDamageVisual = null
var cam_orbit: Camera3D = null
var body_meshes: Array[MeshInstance3D] = []
var body_geometries: Array[Geometry3D] = []
var auto_punch_accum_ms: int = 0

func _ready() -> void:
	add_to_group("rally_editor_tool")
	_setup_environment()
	cam_orbit = get_node_or_null("CameraOrbit") as Camera3D
	_configure_orbit()
	_configure_hint()
	reload_car()

func _process(_delta: float) -> void:
	if cam_orbit is null:
		return
	if Input.mouse_wheel > 0.0:
		cam_orbit.zoom = Vector2(
			clampf(cam_orbit.zoom.x - 0.5, camera_orbit_min_zoom, camera_orbit_max_zoom),
			clampf(cam_orbit.zoom.y - 0.5, camera_orbit_min_zoom, camera_orbit_max_zoom))
	elif Input.mouse_wheel < 0.0:
		cam_orbit.zoom = Vector2(
			clampf(cam_orbit.zoom.x + 0.5, camera_orbit_min_zoom, camera_orbit_max_zoom),
			clampf(cam_orbit.zoom.y + 0.5, camera_orbit_min_zoom, camera_orbit_max_zoom))
	if Input.is_action_just_pressed("ui_accept"):
		punch_impact()
	if Input.is_action_just_pressed("reset_car"):
		_reset_car()
		show_overlay = false
		_configure_hint()
		return
	if Input.is_action_just_pressed("ui_cancel"):
		show_overlay = not show_overlay
		_configure_hint()
		return
	_update_overlay()
	_update_auto_punch()

func _unhandled_input(event: InputEvent) -> void:
	if car_root is null or cam_orbit is null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var mouse: Vector2 = get_viewport().get_mouse_position()
		var from: Vector3 = cam_orbit.project_ray_origin(mouse)
		var direction := cam_orbit.project_ray_normal(mouse)
		var hit := _raycast_body(from, direction)
		if hit.get("hit", false):
			_set_impact_from_world(hit["position"])
			punch_impact()

## Перезагружает автомобиль в сцену и подключает систему деформации.
func reload_car() -> void:
	if car_root is not null:
		car_root.queue_free()
		car_root = null
	damage_visual = null
	body_meshes.clear()
	body_geometries.clear()

	if not CarModels.has_method("make_model"):
		push_warning("DeformationLab: автокаталог CarModels недоступен.")
		_update_overlay()
		return

	car_root = CarModels.make_model(car_id)
	if car_root is null:
		push_warning("DeformationLab: модель для '%s' не найдена." % car_id)
		_update_overlay()
		return

	var container: Node3D = get_node_or_null("CarContainer")
	if container is not null:
		container.add_child(car_root)
	else:
		add_child(car_root)
	car_root.position = Vector3(0.0, spawn_height, -spawn_distance)
	car_root.rotation_degrees.y = spawn_rotation_deg

	for node in car_root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh != null and mesh.is_in_group("rally_body_fx") and mesh.mesh != null:
			body_meshes.append(mesh)
			body_geometries.append(mesh.mesh.create_mesh_surface_geometry())

	var cfg: RallyDamageVisualConfig = damage_config
	if cfg is null:
		cfg = load("res://data/car/default_damage_visual.tres") as RallyDamageVisualConfig
	if cfg is null:
		push_warning("DeformationLab: ресурс настроек деформации не найден.")
		_update_overlay()
		return

	damage_visual = CarDamageVisual.new()
	damage_visual.set_name("DeformationVisual")
	add_child(damage_visual)
	# Пространство удара — корень превью: точки приходят в его локальных
	# координатах, как в игре (точка контакта машины).
	damage_visual.setup(car_root, car_root, cfg)
	_update_overlay()

## Удар в точку, заданную в инспекторе (локальные координаты кузова).
func punch_impact() -> void:
	if damage_visual is null:
		return
	var push: Vector3 = impact_push_dir
	if push.length_squared() < 1e-8:
		push = Vector3(-1.0, 0.0, 0.0)
	damage_visual.apply_impact(impact_point_local, push.normalized(), impact_speed_mps)

## Задаёт точку удара по клику: мировая координата преобразуется в
## локальные координаты кузова.
func _set_impact_from_world(world_point: Vector3) -> void:
	if car_root is null or not car_root.is_inside_tree():
		return
	impact_point_local = car_root.global_transform.affine_inverse() * world_point
	impact_push_dir = Vector3(-1.0, 0.0, 0.0)

## Сброс положения машины и очистка вмятин.
func _reset_car() -> void:
	if car_root is not null:
		car_root.position = Vector3(0.0, spawn_height, -spawn_distance)
		car_root.rotation_degrees.y = spawn_rotation_deg
	if damage_visual is not null:
		damage_visual.clear_damage()

## Лучами по кузову: превью не имеет физических коллизий, поэтому
## производим луч по тёмным граням мешей напрямую.
func _raycast_body(from: Vector3, dir: Vector3) -> Dictionary:
	var closest := Dictionary()
	var best_t: float = 20.0
	for i in body_meshes.size():
		var geometry: Geometry3D = body_geometries[i]
		if geometry is null:
			continue
		var hit := geometry.ray_cast(body_meshes[i].global_transform, 0, from, from + dir * best_t)
		if hit.get("hit", false) and hit.get("distance", INF) < best_t:
			best_t = hit["distance"]
			closest = hit
	if closest.is_empty():
		return {}
	return closest

func _configure_orbit() -> void:
	if cam_orbit is null:
		return
	cam_orbit.rotation_degrees.x = camera_orbit_pitch_deg
	var base_zoom := clampf(spawn_distance, camera_orbit_min_zoom, camera_orbit_max_zoom)
	cam_orbit.zoom = Vector2(base_zoom, base_zoom)

func _configure_hint() -> void:
	var hint := get_node_or_null("Hint") as Label3D
	if hint is null:
		return
	hint.visible = show_overlay

func _update_overlay() -> void:
	var hint := get_node_or_null("Hint") as Label3D
	if hint is null:
		return
	var status := "Модель: %s | ударов: %d | панелей: %d" % [
			car_id,
			str(damage_visual.impact_count() if damage_visual != null else 0),
			str(damage_visual.panel_count() if damage_visual != null else 0),
		]
	hint.text = "Лаборатория деформации кузова. Пуск — удар, клик по кузову — удар в точку клика, R — сброс, Esc — скрыть текст, прокрутка — дистанция | %s" % status

func _setup_environment() -> void:
	var env := get_node_or_null("Environment") as WorldEnvironment
	if env is null:
		return
	if env.environment is null:
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.23, 0.25, 0.27)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		e.ambient_light_energy = 0.55
		e.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.environment = e

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if car_root is not null and car_root.is_inside_tree():
			car_root.queue_free()
