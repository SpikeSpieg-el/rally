## Один параметр шейдера, который можно задать прямо в инспекторе — без кода.
##
## Как пользоваться:
##   1. Откройте data/stage/default_stage_settings.tres (или свой ресурс);
##   2. В массивах `ground_shader_overrides` / `road_shader_overrides` /
##      `screen_shader_overrides` нажмите «Добавить элемент»;
##   3. В поле `param_name` впишите имя uniform из .gdshader, выберите kind
##      и значение.
## Код применит параметр поверх заводских значений каждый раз при сборке мира.
## Так можно докрутить ЛЮБОЙ uniform (включая добавленные позже) только в
## инспекторе, ничего не переписывая в скриптах.
@tool
class_name RallyShaderParameter
extends Resource

@export_group("Что менять")
## Имя uniform из .gdshader — ровно как в файле шейдера.
@export var param_name: String = ""
## Тип значения. Выбирается из списка, лишние поля не используются.
@export_enum("float", "color", "vector2", "vector3", "bool", "texture") var kind: String = "float"

@export_group("Значение")
@export var float_value: float = 0.0
@export var color_value: Color = Color.WHITE
@export var vector2_value: Vector2 = Vector2.ZERO
@export var vector3_value: Vector3 = Vector3.ZERO
@export var bool_value: bool = true
@export var texture: Texture2D = null


## Записать значение в материал. Неизвестное имя игнорируется молча:
## в шейдере может не быть этого uniform, и это не ошибка сборки.
func apply_to(material: ShaderMaterial) -> void:
	if material == null or material.shader == null or param_name.is_empty():
		return
	match kind:
		"color":
			material.set_shader_parameter(param_name, color_value)
		"vector2":
			material.set_shader_parameter(param_name, vector2_value)
		"vector3":
			material.set_shader_parameter(param_name, vector3_value)
		"bool":
			material.set_shader_parameter(param_name, bool_value)
		"texture":
			material.set_shader_parameter(param_name, texture)
		_:
			material.set_shader_parameter(param_name, float_value)


## Применить список параметров (null-safe, порядок сохраняется).
static func apply_all(target: ShaderMaterial, parameters: Array) -> void:
	if target == null:
		return
	for entry in parameters:
		var parameter := entry as RallyShaderParameter
		if parameter != null:
			parameter.apply_to(target)
