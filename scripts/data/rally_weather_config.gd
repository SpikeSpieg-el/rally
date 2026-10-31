## Погодный пресет заездa. Выбирается в меню и накладывается поверх
## «родного» неба трассы: не заменяет его целиком, а подмешивает цвет,
## плотность тумана, силу солнца, влажность полотна и сцепление.
##
## Так один и тот же спецучасток можно проехать в сухую жару, под дождём,
## в молочном тумане или по снегу — небо ночного леса при этом остаётся
## ночным, а пресет только сгущает или подсвечивает его.
##
## Редактируется в инспекторе: res://data/weather/*.tres.
@tool
class_name RallyWeatherConfig
extends Resource

enum Precipitation { NONE, RAIN, SNOW }
enum TimeOfDay { KEEP, DAY, NIGHT }

@export_group("Описание")
@export var id: String = "default"
@export var display_name: String = "КАК НА ТРАССЕ"
## Короткая подпись для HUD и карточки меню.
@export var short_name: String = "ШТИЛЬ"
@export_multiline var description: String = "Погода из конфига трассы, без изменений."

@export_group("Осадки")
@export_enum("Нет", "Дождь", "Снег") var precipitation: int = Precipitation.NONE
@export_range(0.0, 1.0, 0.01) var precipitation_intensity: float = 0.0
## Ветер сносит осадки в сторону, м/с. Он же наклоняет «штрихи» дождя.
@export_range(0.0, 30.0, 0.5) var wind_speed: float = 0.0

@export_group("Небо и свет")
@export_enum("Как на трассе", "День", "Ночь") var time_of_day: int = TimeOfDay.KEEP
## 0 — небо трассы не трогаем, 1 — полностью красим в sky_tint.
@export_range(0.0, 1.0, 0.01) var sky_tint_strength: float = 0.0
@export var sky_tint: Color = Color(0.62, 0.68, 0.74, 1.0)
## Обесцвечивание неба: 0.5 — «серое» небо на половину.
@export_range(0.0, 1.0, 0.01) var sky_desaturation: float = 0.0
@export_range(0.2, 2.0, 0.01) var sun_energy_scale: float = 1.0
@export var sun_tint: Color = Color(1.0, 1.0, 1.0, 1.0)
@export_range(0.0, 1.0, 0.01) var sun_tint_strength: float = 0.0
@export_range(0.2, 2.5, 0.01) var ambient_energy_scale: float = 1.0
@export_range(0.4, 1.8, 0.01) var exposure_scale: float = 1.0

@export_group("Туман и видимость")
@export var fog_color: Color = Color(0.72, 0.79, 0.88, 1.0)
## 0 — цвет тумана трассы, 1 — полностью fog_color.
@export_range(0.0, 1.0, 0.01) var fog_color_strength: float = 0.0
@export_range(0.0, 6.0, 0.05) var fog_density_scale: float = 1.0
@export_range(0.0, 0.04, 0.0001) var fog_density_add: float = 0.0
## Насколько сжать «дальность» дизер-тумана в шейдере земли (0.3 — густой).
@export_range(0.2, 1.0, 0.01) var visibility_scale: float = 1.0
## Включить объёмный туман (лучи фар, дымка), даже если у трассы он выключен.
@export var volumetric_fog: bool = false

@export_group("Полотно и земля")
## Мокрое покрытие: темнее, глянцевее, меньше сцепления на гравии.
@export_range(0.0, 1.0, 0.01) var wetness: float = 0.0
## Снежный покров на земле и полотне.
@export_range(0.0, 1.0, 0.01) var snow_cover: float = 0.0

@export_group("Сцепление")
@export_range(0.2, 1.5, 0.01) var grip_scale: float = 1.0
@export_range(0.2, 2.0, 0.01) var rolling_resistance_scale: float = 1.0
@export_range(0.2, 1.5, 0.01) var offroad_grip_scale: float = 1.0


func has_precipitation() -> bool:
	return precipitation != Precipitation.NONE and precipitation_intensity > 0.01


func precipitation_name() -> String:
	match precipitation:
		Precipitation.RAIN:
			return "ДОЖДЬ"
		Precipitation.SNOW:
			return "СНЕГ"
		_:
			return ""


## Короткая строка условий для HUD: «ДОЖДЬ · ВЕТЕР 8 М/С».
func get_summary() -> String:
	var parts := PackedStringArray()
	if not short_name.is_empty():
		parts.append(short_name)
	var precipitation_label: String = precipitation_name()
	if has_precipitation() and not precipitation_label.is_empty() and precipitation_label != short_name:
		parts.append(precipitation_label)
	if wind_speed >= 6.0:
		parts.append("ВЕТЕР %d М/С" % int(round(wind_speed)))
	if parts.is_empty():
		return display_name
	return "  •  ".join(parts)


## Ночной ли заезд с этой погодой. KEEP оставляет решение за трассой.
func resolve_night(track_night: bool) -> bool:
	match time_of_day:
		TimeOfDay.DAY:
			return false
		TimeOfDay.NIGHT:
			return true
		_:
			return track_night
