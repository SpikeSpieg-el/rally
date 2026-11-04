## Условия участка по километражу. Ширина плавно меняется на входе.
@tool
class_name RallyRouteSection
extends Resource

@export var start_distance: float = 0.0
@export var title: String = ""
@export var surface_name: String = "Гравий"
@export_range(2.0, 10.0, 0.1) var half_width: float = 4.2
@export var road_color: Color = Color(0.34, 0.28, 0.19)
@export_range(0.2, 2.0, 0.01) var grip: float = 1.0
@export_range(0.2, 4.0, 0.01) var rolling: float = 1.0
@export_range(20.0, 500.0, 1.0) var transition_length: float = 180.0
@export var weather: RallyWeatherConfig = null
