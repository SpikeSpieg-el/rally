## Материалы земли и дороги — ресурсы прямо на узле сцены.
## Код меняет только то, что зависит от трассы/погоды/ретро-сетки;
## художественные uniform'ы (зерно, колеи, блики) остаются вашими.
@tool
class_name RallySurfaceLooks
extends Node

const ShaderParam = preload("res://scripts/data/rally_shader_parameter.gd")

signal settings_changed

enum Look { CUSTOM, FACTORY, SOFT, CONTRAST }

@export_group("Вид поверхностей")
## Готовая отправная точка. «Свой вид» ничего не перезаписывает.
@export var look: Look = Look.FACTORY:
	set(value):
		var changed := value != look
		look = value
		if changed and value != Look.CUSTOM:
			_apply_preset()
		_refresh()
@export_multiline var description: String = ""

@export_group("Материалы сцены")
## Откройте материал: Shader Parameters видны прямо в инспекторе.
@export var ground_material: ShaderMaterial = null:
	set(value):
		ground_material = value
		_refresh()
@export var road_material: ShaderMaterial = null:
	set(value):
		road_material = value
		_refresh()

@export_group("Дополнительные uniform'ы (необязательно)")
@export var ground_uniforms: Array[ShaderParam] = []
@export var road_uniforms: Array[ShaderParam] = []


func _ready() -> void:
	_refresh()


func _validate_property(property: Dictionary) -> void:
	if property.name == "description":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY


func _apply_preset() -> void:
	if ground_material == null or road_material == null:
		return
	match look:
		Look.FACTORY:
			ground_material.set_shader_parameter("grain_scale", 2.4)
			ground_material.set_shader_parameter("surface_roughness", 0.97)
			road_material.set_shader_parameter("road_roughness", 0.92)
			road_material.set_shader_parameter("detail_strength", 0.16)
			road_material.set_shader_parameter("track_strength", 0.12)
			road_material.set_shader_parameter("loose_relief", 1.0)
		Look.SOFT:
			ground_material.set_shader_parameter("grain_scale", 1.4)
			ground_material.set_shader_parameter("surface_roughness", 0.99)
			road_material.set_shader_parameter("road_roughness", 0.96)
			road_material.set_shader_parameter("detail_strength", 0.08)
			road_material.set_shader_parameter("track_strength", 0.06)
			road_material.set_shader_parameter("loose_relief", 0.5)
		Look.CONTRAST:
			ground_material.set_shader_parameter("grain_scale", 3.2)
			ground_material.set_shader_parameter("surface_roughness", 0.9)
			road_material.set_shader_parameter("road_roughness", 0.86)
			road_material.set_shader_parameter("detail_strength", 0.28)
			road_material.set_shader_parameter("track_strength", 0.22)
			road_material.set_shader_parameter("loose_relief", 1.3)


func _refresh() -> void:
	description = "Здесь лежат настоящие материалы земли и дороги.\n"
	description += "Погода, цвета трассы и PS1-сетка применяются при заезде.\n"
	description += "Зерно, колеи и блики правятся в Shader Parameters материала."
	notify_property_list_changed()
	settings_changed.emit()


func write_settings(cfg: Resource) -> void:
	if cfg == null:
		return
	cfg.set("ground_material", ground_material)
	cfg.set("road_material", road_material)
	cfg.set("ground_shader_overrides", ground_uniforms)
	cfg.set("road_shader_overrides", road_uniforms)
	if ground_material != null:
		cfg.set("ground_grain_scale", float(ground_material.get_shader_parameter("grain_scale")))
		cfg.set("ground_surface_roughness", float(ground_material.get_shader_parameter("surface_roughness")))
	if road_material != null:
		cfg.set("road_roughness", float(road_material.get_shader_parameter("road_roughness")))
		cfg.set("road_detail_strength", float(road_material.get_shader_parameter("detail_strength")))
		cfg.set("road_track_strength", float(road_material.get_shader_parameter("track_strength")))
		cfg.set("road_loose_relief", float(road_material.get_shader_parameter("loose_relief")))


func adopt_settings(cfg: Resource) -> void:
	if cfg == null:
		return
	look = Look.CUSTOM
	if cfg.get("ground_material") != null:
		ground_material = cfg.get("ground_material")
	if cfg.get("road_material") != null:
		road_material = cfg.get("road_material")
	ground_uniforms.assign(cfg.get("ground_shader_overrides"))
	road_uniforms.assign(cfg.get("road_shader_overrides"))
	if ground_material != null:
		ground_material.set_shader_parameter("grain_scale", cfg.get("ground_grain_scale"))
		ground_material.set_shader_parameter("surface_roughness", cfg.get("ground_surface_roughness"))
	if road_material != null:
		road_material.set_shader_parameter("road_roughness", cfg.get("road_roughness"))
		road_material.set_shader_parameter("detail_strength", cfg.get("road_detail_strength"))
		road_material.set_shader_parameter("track_strength", cfg.get("road_track_strength"))
		road_material.set_shader_parameter("loose_relief", cfg.get("road_loose_relief"))
	_refresh()
