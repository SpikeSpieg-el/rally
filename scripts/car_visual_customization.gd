## Одинаковая внешность для витрины и машины на трассе.
## Материалы копируются на экземпляр: исходная сцена и другие машины не меняются.
extends RefCounted

const ORIGINAL_META := &"rally_original_material"
const CUSTOM_META := &"rally_custom_material"
## Покраска машины без ливрей: копия материала поверхности кузова и её оригинал.
const PAINT_SURFACE_META := &"rally_paint_surface_material"
const PAINT_ORIGINAL_META := &"rally_paint_surface_original"
## Поверхность кузова в меше модели: у всех трёх машин это поверхность 0.
const PAINT_SURFACE := 0
## Нейтральный тон кузова: такой цвет ничего не меняет ни в ливрее, ни в краске.
const DEFAULT_TINT := Color(1, 1, 1, 1)
## Имя узла кузова задаёт модель машины (метаданные car_body_mesh).
## Основной меш помечается группой rally_body_paint в сцене.
const BODY_MESH_META := &"car_body_mesh"


static func _material_for(mesh: MeshInstance3D) -> StandardMaterial3D:
	if not mesh.has_meta(ORIGINAL_META):
		var original: Material = mesh.material_override
		if original == null and mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
			original = mesh.mesh.surface_get_material(0)
		if original == null or not original is StandardMaterial3D:
			original = StandardMaterial3D.new()
		mesh.set_meta(ORIGINAL_META, original)
	var custom: StandardMaterial3D = null
	if mesh.has_meta(CUSTOM_META):
		custom = mesh.get_meta(CUSTOM_META) as StandardMaterial3D
	if custom == null or mesh.material_override != custom:
		# PS1-стилизация может заменить material_override после первой настройки.
		# Сохраняем выбранную ею фильтрацию, не меняя исходный материал модели.
		var current := mesh.material_override as StandardMaterial3D
		var original := mesh.get_meta(ORIGINAL_META) as StandardMaterial3D
		custom = original.duplicate() as StandardMaterial3D
		if current != null:
			custom.texture_filter = current.texture_filter
		mesh.material_override = custom
		mesh.set_meta(CUSTOM_META, custom)
	return custom


## Основной меш покраски; метаданные поддерживаются для старых витрин.
static func body_mesh(model: Node3D) -> MeshInstance3D:
	if model == null:
		return null
	if model is MeshInstance3D and model.is_in_group("rally_body_paint"):
		return model as MeshInstance3D
	for node in model.find_children("*", "MeshInstance3D", true, false):
		if node.is_in_group("rally_body_paint"):
			return node as MeshInstance3D
	var body_name := String(model.get_meta(BODY_MESH_META, ""))
	return model.find_child(body_name, true, false) as MeshInstance3D if not body_name.is_empty() else null


static func ensure_body_material(model: Node3D) -> StandardMaterial3D:
	if model == null:
		return null
	var body := body_mesh(model)
	if body == null:
		return null
	if body.material_override is StandardMaterial3D and (body.has_meta(ORIGINAL_META) or body.has_meta(CUSTOM_META)):
		return body.material_override as StandardMaterial3D
	return _material_for(body)


## Покраска кузова: ливрея (когда у машины есть свои текстуры), тон и тип краски.
## У машины без ливрей (Golf R32) вместо ливреи красится поверхность кузова:
## при нейтральном белом тоне остаётся заводская краска модели, а выбранный цвет
## и «Глянец/Матовый/Металлик» работают так же, как у машин с ливреями.
static func apply_body(model: Node3D, setup: RallyCarSetup, textures: Array = []) -> void:
	if model == null or setup == null:
		return
	var body := body_mesh(model)
	if body == null:
		return
	if textures.is_empty():
		_apply_factory_paint(body, setup)
		return
	# Ливрея заменяет материал одного отмеченного меша целиком.
	var material := _material_for(body)
	var original := body.get_meta(ORIGINAL_META) as StandardMaterial3D
	material.albedo_color = setup.body_color
	var index := setup.livery if setup.livery >= 0 and setup.livery < textures.size() else 0
	var texture := textures[index] as Texture2D
	# Пустую ячейку не подменяем ливреей другой машины.
	material.albedo_texture = texture if texture != null else original.albedo_texture
	_apply_finish(material, original, setup)


## Покраска машины без собственных ливрей (Golf R32).
## Кузовной меш собран из нескольких поверхностей — краска, стекло, фонари, —
## поэтому material_override брать нельзя: он перекрыл бы всё разом, и машина
## осталась бы без стёкол и задних фонарей. Красим только поверхность кузова.
static func _apply_factory_paint(body: MeshInstance3D, setup: RallyCarSetup) -> void:
	var paint := paint_surface_material(body)
	var factory := body.get_meta(PAINT_ORIGINAL_META) as StandardMaterial3D
	if paint == null or factory == null:
		return
	# Белый тон — нейтральное значение по умолчанию: у машин с ливреями он
	# означает «текстуру не подкрашиваем», здесь — «оставить краску модели».
	# Иначе любая машина без ливрей белела бы, включая сцены, которые реестр
	# зарегистрировал сам (их пресеты собраны из BASE_SETUP, где тон белый).
	var tint := setup.body_color
	paint.albedo_color = factory.albedo_color if tint.is_equal_approx(DEFAULT_TINT) else tint
	_apply_finish(paint, factory, setup)


## Копия материала поверхности кузова (поверхность 0) на экземпляре меша.
## Возвращает null, если у меша нет материала поверхности: красить нечего.
static func paint_surface_material(mesh: MeshInstance3D) -> StandardMaterial3D:
	if mesh == null or mesh.mesh == null or mesh.mesh.get_surface_count() < 1:
		return null
	var custom := mesh.get_meta(PAINT_SURFACE_META) as StandardMaterial3D
	if custom != null and mesh.get_surface_override_material(PAINT_SURFACE) == custom:
		return custom
	var original := mesh.mesh.surface_get_material(PAINT_SURFACE) as StandardMaterial3D
	if original == null:
		return null
	custom = original.duplicate() as StandardMaterial3D
	# PS1-стилизация может заменить материал поверхности после первой настройки:
	# сохраняем выбранную ею фильтрацию, не меняя исходный материал модели.
	var current := mesh.get_surface_override_material(PAINT_SURFACE) as StandardMaterial3D
	if current != null:
		custom.texture_filter = current.texture_filter
	mesh.set_surface_override_material(PAINT_SURFACE, custom)
	mesh.set_meta(PAINT_SURFACE_META, custom)
	mesh.set_meta(PAINT_ORIGINAL_META, original)
	return custom


## Покрытие краски: общий ход и для ливреи, и для заводской краски.
static func _apply_finish(material: StandardMaterial3D, original: StandardMaterial3D,
		setup: RallyCarSetup) -> void:
	match setup.paint_finish:
		1: # Глянец
			material.metallic = 0.08
			material.roughness = 0.18
		2: # Матовый
			material.metallic = 0.0
			material.roughness = 0.90
		3: # Металлик
			material.metallic = 0.65
			material.roughness = 0.25
		_:
			material.metallic = original.metallic
			material.roughness = original.roughness


static func apply_wheel(wheel: MeshInstance3D, setup: RallyCarSetup) -> void:
	if wheel == null or setup == null:
		return
	var material := _material_for(wheel)
	var original := wheel.get_meta(ORIGINAL_META) as StandardMaterial3D
	material.albedo_color = original.albedo_color * setup.wheel_color


static func wheel_scale(radius: float, width: float, visual_radius: float = 0.438) -> Vector3:
	# Исходная ось колеса — X. Диаметр и ширина регулируются независимо.
	var diameter_scale := radius / maxf(0.05, visual_radius)
	return Vector3(width / 245.0, diameter_scale, diameter_scale)


static func apply_headlights(car: Node, setup: RallyCarSetup) -> void:
	if car == null or setup == null:
		return
	for node_name in ["HeadlightL", "HeadlightR"]:
		var light := car.get_node_or_null(node_name) as SpotLight3D
		if light == null:
			light = car.find_child(node_name, true, false) as SpotLight3D
		if light != null:
			light.light_color = setup.headlight_color
			light.light_energy = setup.headlight_energy
