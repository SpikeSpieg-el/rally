## «Характер трассы»: пресет покрытия и геометрии полотна.
##
## Трасса задаёт конкретную осевую линию, а этот ресурс — каким будет
## полотно: узкая разбитая колея, широкий гладкий асфальт или снежная
## целина. Пресет накладывается на копию конфига трассы (сам .tres не
## меняется), поэтому один и тот же спецучасток можно проехать по-разному.
##
## Редактируется в инспекторе: res://data/profiles/*.tres.
@tool
class_name RallyTrackProfile
extends Resource

@export_group("Описание")
@export var id: String = "gravel"
@export var display_name: String = "ГРАВИЙ · КЛАССИКА"
@export_multiline var description: String = "Стандартный гравийный спецучасток."
## Подпись покрытия для HUD и карточки меню. Пусто — оставить у трассы.
@export var surface_name: String = "Гравий"

@export_group("Полотно")
## Ширина проезжей части относительно трассы.
@export_range(0.6, 1.6, 0.01) var road_width_scale: float = 1.0
@export_range(0.4, 2.0, 0.01) var shoulder_scale: float = 1.0
## Амплитуда кочек и «стиральной доски» относительно трассы.
@export_range(0.0, 3.0, 0.01) var bumps_scale: float = 1.0
@export_range(0.0, 3.0, 0.05) var camber_scale: float = 1.0

@export_group("Сцепление")
@export_range(0.2, 1.6, 0.01) var grip_scale: float = 1.0
@export_range(0.2, 2.0, 0.01) var rolling_resistance_scale: float = 1.0
@export_range(0.2, 1.5, 0.01) var offroad_grip_scale: float = 1.0

@export_group("Цвета полотна")
## Перекрасить дорогу и обочину (например, асфальт вместо гравия).
@export var override_road_colors: bool = false
@export var road_color: Color = Color(0.34, 0.28, 0.19, 1.0)
@export var road_color_2: Color = Color(0.45, 0.37, 0.26, 1.0)
@export var shoulder_color: Color = Color(0.31, 0.25, 0.17, 1.0)

@export_group("Рельеф вокруг")
## Высота холмов и гребней относительно трассы.
@export_range(0.0, 2.0, 0.01) var hills_scale: float = 1.0


## Накладывает пресет на конфиг трассы. Вызывать только на КОПИИ ресурса:
## исходный .tres в репозитории должен оставаться нетронутым.
func apply_to(track: RallyTrackConfig) -> void:
	if track == null:
		return
	track.road_half_width = clampf(track.road_half_width * road_width_scale, 2.0, 10.0)
	track.road_shoulder = clampf(track.road_shoulder * shoulder_scale, 0.0, 5.0)
	track.bumps_amplitude = clampf(track.bumps_amplitude * bumps_scale, 0.0, 0.6)
	track.bumps_roughness = clampf(track.bumps_roughness * bumps_scale, 0.0, 0.4)
	track.road_camber = clampf(track.road_camber * camber_scale, 0.0, 0.4)
	track.grip_scale = clampf(track.grip_scale * grip_scale, 0.2, 2.0)
	track.rolling_resistance_scale = clampf(
		track.rolling_resistance_scale * rolling_resistance_scale, 0.2, 4.0
	)
	track.offroad_grip = clampf(track.offroad_grip * offroad_grip_scale, 0.05, 1.0)
	track.hills_height = clampf(track.hills_height * hills_scale, 0.0, 80.0)
	track.ridge_height = clampf(track.ridge_height * hills_scale, 0.0, 80.0)
	if override_road_colors:
		track.road_color = road_color
		track.road_color_2 = road_color_2
		track.shoulder_color = shoulder_color
	if not surface_name.is_empty():
		track.surface_name = surface_name
