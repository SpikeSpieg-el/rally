## Корень визуальных настроек этапа. В дереве сцены лежат отдельные эффекты:
## Speed, Rain, Snow, Surfaces; экранный ретро-фильтр — ColorRect под HUD.
## Этот скрипт только связывает их, здесь нет «простыни» ползунков.
@tool
class_name RallyVisualEffects
extends Node

const WeatherType = preload("res://scripts/data/rally_weather_config.gd")
const ScreenLook = preload("res://scripts/effects/rally_screen_look.gd")
const SpeedFeel = preload("res://scripts/effects/rally_speed_feel.gd")
const Precip = preload("res://scripts/effects/rally_precipitation_effect.gd")
const Surfaces = preload("res://scripts/effects/rally_surface_looks.gd")

@export_group("Где живут эффекты в сцене")
## Обычно это HUD/SpeedShaderRect: настоящий материал экранного фильтра.
@export var screen_path: NodePath = ^"../HUD/SpeedShaderRect"
@export var speed_path: NodePath = ^"Speed"
@export var rain_path: NodePath = ^"Rain"
@export var snow_path: NodePath = ^"Snow"
@export var surfaces_path: NodePath = ^"Surfaces"

@export_group("Область осадков вокруг машины")
## Новые капли рождаются в этой сетке; уже выпавшие остаются в мире.
@export_range(0.5, 40.0, 0.5, "suffix:м") var anchor_grid: float = 8.0
@export_range(0.0, 60.0, 0.5, "suffix:м") var anchor_height: float = 11.0
@export_range(0.0, 2.0, 0.01) var anchor_velocity_lead: float = 0.35
@export_range(0.0, 200.0, 1.0, "suffix:м/с") var anchor_velocity_limit: float = 50.0


func screen() -> ScreenLook:
	return get_node_or_null(screen_path) as ScreenLook


func speed() -> SpeedFeel:
	return get_node_or_null(speed_path) as SpeedFeel


func rain() -> Precip:
	return get_node_or_null(rain_path) as Precip


func snow() -> Precip:
	return get_node_or_null(snow_path) as Precip


func surfaces() -> Surfaces:
	return get_node_or_null(surfaces_path) as Surfaces


func configure_screen(track: Resource) -> void:
	var rect := screen()
	if rect != null:
		rect.bind_speed(speed())
		rect.configure_for_track(track)


## Каждый кадр заезда: экранный фильтр скорости получает текущую скорость.
## Трасса осталась в подписи ради совместимости со старыми вызовами, но
## фильтру она не нужна — параметр с подчёркиванием, чтобы не было предупреждения.
func update_speed(speed_kmh: float, _track: Resource = null) -> void:
	var rect := screen()
	if rect != null:
		rect.set_preview_speed(speed_kmh)


## Копия сцены осадков для заезда: правки шаблона в редакторе не изменяются.
func make_weather_particles(weather: Resource) -> Precip:
	if weather == null or not weather.has_precipitation():
		return null
	var template: Precip = rain() if weather.precipitation == WeatherType.Precipitation.RAIN else snow()
	if template == null or not template.enabled:
		return null
	var particles := template.duplicate() as Precip
	if particles.process_material != null:
		particles.process_material = particles.process_material.duplicate()
	var quad := particles.draw_pass_1 as QuadMesh
	if quad != null:
		quad = quad.duplicate() as QuadMesh
		if quad.material != null:
			quad.material = quad.material.duplicate()
		particles.draw_pass_1 = quad
	particles.configure(float(weather.precipitation_intensity), float(weather.wind_speed))
	return particles


func anchor_for(position: Vector3, velocity: Vector3) -> Vector3:
	var lead := Vector3(velocity.x, 0.0, velocity.z).limit_length(anchor_velocity_limit) * anchor_velocity_lead
	var center := position + lead
	var grid := maxf(0.5, anchor_grid)
	return Vector3(roundf(center.x / grid) * grid, position.y + anchor_height, roundf(center.z / grid) * grid)


## Предпросмотр в лаборатории: показать нужные осадки, остальные выключить.
func preview_weather(weather: Resource) -> void:
	for node in [rain(), snow()]:
		if node == null:
			continue
		var active: bool = weather != null and weather.has_precipitation()
		active = active and ((node.kind == Precip.Kind.RAIN and weather.precipitation == WeatherType.Precipitation.RAIN) or (node.kind == Precip.Kind.SNOW and weather.precipitation == WeatherType.Precipitation.SNOW))
		if active and node.enabled:
			node.configure(float(weather.precipitation_intensity), float(weather.wind_speed))
			node.emitting = true
		else:
			node.emitting = false


func stop_preview() -> void:
	for node in [rain(), snow()]:
		if node != null:
			node.emitting = false


## Старый ресурс этапа остаётся совместимым зеркалом, а не главным пультом.
func sync_to_settings(cfg: Resource) -> void:
	if cfg == null:
		return
	if screen() != null:
		screen().write_settings(cfg)
	if speed() != null:
		speed().write_settings(cfg)
	if rain() != null:
		rain().write_settings(cfg)
	if snow() != null:
		snow().write_settings(cfg)
	cfg.set("precipitation_enabled", (rain() != null and rain().enabled) or (snow() != null and snow().enabled))
	if surfaces() != null:
		surfaces().write_settings(cfg)
	cfg.set("anchor_grid", anchor_grid)
	cfg.set("anchor_height", anchor_height)
	cfg.set("anchor_velocity_lead", anchor_velocity_lead)
	cfg.set("anchor_velocity_limit", anchor_velocity_limit)


func adopt_from_settings(cfg: Resource) -> void:
	if cfg == null:
		return
	if screen() != null:
		screen().adopt_settings(cfg)
	if speed() != null:
		speed().adopt_settings(cfg)
	if rain() != null:
		rain().adopt_settings(cfg)
	if snow() != null:
		snow().adopt_settings(cfg)
	if surfaces() != null:
		surfaces().adopt_settings(cfg)
	anchor_grid = float(cfg.get("anchor_grid"))
	anchor_height = float(cfg.get("anchor_height"))
	anchor_velocity_lead = float(cfg.get("anchor_velocity_lead"))
	anchor_velocity_limit = float(cfg.get("anchor_velocity_limit"))
