## Одинаковая внешность для витрины и машины на трассе.
## Материалы копируются на экземпляр: исходная сцена и другие машины не меняются.
extends RefCounted

const LIVERIES := [
	preload("res://textures/иташа2.jpg"),
	preload("res://textures/иташа.jpg"),
	preload("res://textures/иташа3.jpg"),
]
const ORIGINAL_META := &"rally_original_material"
const CUSTOM_META := &"rally_custom_material"


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


static func apply_body(model: Node3D, setup: RallyCarSetup) -> void:
	if model == null or setup == null:
		return
	# Только корпус с общей текстурой. Body_002 и Body_003 — зеркала с
	# несколькими поверхностями, заменять их материал нельзя.
	var body := model.get_node_or_null("Mitsubishi_Body") as MeshInstance3D
	if body == null:
		return
	var material := _material_for(body)
	var original := body.get_meta(ORIGINAL_META) as StandardMaterial3D
	material.albedo_color = setup.body_color
	material.albedo_texture = LIVERIES[clampi(setup.livery, 0, LIVERIES.size() - 1)]
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
		if light != null:
			light.light_color = setup.headlight_color
			light.light_energy = setup.headlight_energy
