## Дождь или снег как редактируемый GPUParticles3D в сцене.
## Сначала выберите понятную интенсивность; числа нужны только для своего варианта.
## Частицы мировые: область рождения следует за машиной, уже выпавшие капли — нет.
@tool
class_name RallyPrecipitationEffect
extends GPUParticles3D

signal settings_changed

enum Kind { RAIN, SNOW }
enum Preset { CUSTOM, LIGHT, STEADY, HEAVY }

const RAIN_PRESETS := {
	Preset.LIGHT: [350, 900, 1.0, 18.0, 24.0, 2.0, Vector2(0.015, 0.30)],
	Preset.STEADY: [700, 2400, 1.15, 21.0, 29.0, 3.0, Vector2(0.02, 0.40)],
	Preset.HEAVY: [1600, 4200, 1.3, 27.0, 36.0, 5.0, Vector2(0.025, 0.55)],
}
const SNOW_PRESETS := {
	Preset.LIGHT: [250, 800, 4.5, 0.8, 2.0, 18.0, Vector2(0.05, 0.05)],
	Preset.STEADY: [500, 1800, 4.0, 1.2, 3.0, 25.0, Vector2(0.07, 0.07)],
	Preset.HEAVY: [1200, 3600, 5.0, 2.0, 4.5, 40.0, Vector2(0.09, 0.09)],
}
const ADVANCED := [
	"density", "amount_min", "amount_max", "lifetime_seconds", "speed_min", "speed_max",
	"spread_degrees", "particle_size", "scale_min", "scale_max", "gravity", "wind_tilt",
	"color", "box_extents", "visible_bounds",
]

@export_group("Что идёт и насколько сильно")
@export var kind: Kind = Kind.RAIN:
	set(value):
		kind = value
		if not _applying and preset != Preset.CUSTOM:
			_apply_preset()
		_refresh()
## Слабые / обычные / сильные осадки. «Свой вариант» открывает точные поля.
@export var preset: Preset = Preset.STEADY:
	set(value):
		var changed := value != preset
		preset = value
		if changed and value != Preset.CUSTOM and not _applying:
			_apply_preset()
		_refresh()
## Выключает частицы, но не меняет мокрость дороги и настройки погоды.
@export var enabled: bool = true:
	set(value):
		enabled = value
		_refresh()
@export_multiline var description: String = ""

@export_group("Точные значения (только для «Свой вариант»)")
@export_range(0.1, 2.0, 0.1) var density: float = 1.0:
	set(value):
		density = value
		_mark_custom()
		_refresh()
@export_range(1, 20000, 10) var amount_min: int = 700:
	set(value):
		amount_min = value
		_mark_custom()
		_refresh()
@export_range(1, 20000, 10) var amount_max: int = 2400:
	set(value):
		amount_max = value
		_mark_custom()
		_refresh()
@export_range(0.2, 12.0, 0.05, "suffix:с") var lifetime_seconds: float = 1.15:
	set(value):
		lifetime_seconds = value
		_mark_custom()
		_refresh()
@export_range(0.0, 80.0, 0.5, "suffix:м/с") var speed_min: float = 21.0:
	set(value):
		speed_min = value
		_mark_custom()
		_refresh()
@export_range(0.0, 80.0, 0.5, "suffix:м/с") var speed_max: float = 29.0:
	set(value):
		speed_max = value
		_mark_custom()
		_refresh()
@export_range(0.0, 90.0, 1.0, "suffix:°") var spread_degrees: float = 3.0:
	set(value):
		spread_degrees = value
		_mark_custom()
		_refresh()
## Для дождя X — толщина штриха, Y — длина; для снега — размер снежинки.
@export var particle_size: Vector2 = Vector2(0.02, 0.4):
	set(value):
		particle_size = value
		_mark_custom()
		_refresh()
@export_range(0.1, 4.0, 0.05) var scale_min: float = 0.7:
	set(value):
		scale_min = value
		_mark_custom()
		_refresh()
@export_range(0.1, 4.0, 0.05) var scale_max: float = 1.25:
	set(value):
		scale_max = value
		_mark_custom()
		_refresh()
@export var gravity: Vector3 = Vector3(0.0, -12.0, 0.0):
	set(value):
		gravity = value
		_mark_custom()
		_refresh()
@export_range(0.0, 1.0, 0.001) var wind_tilt: float = 0.008:
	set(value):
		wind_tilt = value
		_mark_custom()
		_refresh()
@export var color: Color = Color(0.70, 0.79, 0.90, 0.38):
	set(value):
		color = value
		_mark_custom()
		_refresh()
@export var box_extents: Vector3 = Vector3(32.0, 9.0, 32.0):
	set(value):
		box_extents = value
		_mark_custom()
		_refresh()
@export var visible_bounds: AABB = AABB(Vector3(-90, -65, -90), Vector3(180, 115, 180)):
	set(value):
		visible_bounds = value
		_mark_custom()
		_refresh()

var _applying := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	local_coords = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_refresh_description()


func _validate_property(property: Dictionary) -> void:
	if property.name == "description":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
	if property.name in ADVANCED and preset != Preset.CUSTOM:
		property.usage = PROPERTY_USAGE_STORAGE


func _mark_custom() -> void:
	if not _applying and preset != Preset.CUSTOM:
		preset = Preset.CUSTOM


func _apply_preset() -> void:
	var table := RAIN_PRESETS if kind == Kind.RAIN else SNOW_PRESETS
	if not table.has(preset):
		return
	_applying = true
	var p: Array = table[preset]
	amount_min = p[0]
	amount_max = p[1]
	lifetime_seconds = p[2]
	speed_min = p[3]
	speed_max = p[4]
	spread_degrees = p[5]
	particle_size = p[6]
	if kind == Kind.RAIN:
		gravity = Vector3(0, -12, 0)
		wind_tilt = 0.008
		scale_min = 0.7
		scale_max = 1.25
		color = Color(0.70, 0.79, 0.90, 0.38)
		box_extents = Vector3(32, 9, 32)
	else:
		gravity = Vector3(0, -1.6, 0)
		wind_tilt = 0.025
		scale_min = 0.6
		scale_max = 1.6
		color = Color(0.94, 0.97, 1.0, 0.72)
		box_extents = Vector3(28, 7, 28)
	_applying = false


func _refresh() -> void:
	_apply_visuals()
	_refresh_description()
	settings_changed.emit()


func _refresh_description() -> void:
	description = "Мировые частицы вокруг машины. На паузе останавливаются.\n"
	description += "Мокрость дороги и сцепление задаются погодой отдельно.\n"
	description += "Сейчас: %s, %s." % [
		"дождь" if kind == Kind.RAIN else "снег",
		["свой вариант", "слабые", "обычные", "сильные"][preset],
	]
	notify_property_list_changed()


## Настроить нативные частицы по полям узла. Вызывается при правке и перед заездом.
func _apply_visuals() -> void:
	var pm := process_material as ParticleProcessMaterial
	if pm == null:
		pm = ParticleProcessMaterial.new()
		process_material = pm
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box_extents
	pm.direction = Vector3.DOWN
	pm.spread = spread_degrees
	pm.initial_velocity_min = speed_min
	pm.initial_velocity_max = maxf(speed_min, speed_max)
	pm.gravity = gravity
	pm.scale_min = scale_min
	pm.scale_max = maxf(scale_min, scale_max)
	var quad := draw_pass_1 as QuadMesh
	if quad == null:
		quad = QuadMesh.new()
		draw_pass_1 = quad
	quad.size = particle_size
	var mat := quad.material as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		quad.material = mat
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_keep_scale = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if kind == Kind.RAIN else BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = color
	lifetime = maxf(0.2, lifetime_seconds)
	preprocess = minf(lifetime, 2.0)
	visibility_aabb = visible_bounds
	amount = maxi(1, amount_max)


## Применить интенсивность и ветер выбранной погоды к копии сцены.
func configure(intensity: float, wind_speed: float) -> void:
	_apply_visuals()
	var t := clampf(intensity, 0.0, 1.0)
	amount = maxi(1, int(lerpf(float(amount_min), float(amount_max), t) * density))
	var wind := Vector3(wind_speed, 0.0, wind_speed * 0.35)
	var pm := process_material as ParticleProcessMaterial
	pm.direction = (Vector3.DOWN + wind * wind_tilt).normalized()
	if kind == Kind.SNOW:
		pm.gravity = gravity + Vector3(wind.x * 0.10, 0.0, wind.z * 0.10)
	emitting = false
	name = "WeatherParticles"


func write_settings(cfg: Resource) -> void:
	if cfg == null:
		return
	var prefix := "rain" if kind == Kind.RAIN else "snow"
	cfg.set("precipitation_enabled", enabled)
	cfg.set("precipitation_density", density)
	cfg.set(prefix + "_amount_min", amount_min)
	cfg.set(prefix + "_amount_max", amount_max)
	cfg.set(prefix + "_lifetime", lifetime_seconds)
	cfg.set(prefix + "_speed_min", speed_min)
	cfg.set(prefix + "_speed_max", speed_max)
	cfg.set(prefix + "_spread", spread_degrees)
	cfg.set(prefix + "_streak_size" if kind == Kind.RAIN else prefix + "_flake_size", particle_size)
	cfg.set(prefix + "_scale_min", scale_min)
	cfg.set(prefix + "_scale_max", scale_max)
	cfg.set(prefix + "_gravity", gravity)
	cfg.set(prefix + "_wind_tilt", wind_tilt)
	cfg.set(prefix + "_color", color)
	cfg.set(prefix + "_box_extents", box_extents)
	cfg.set("precipitation_aabb", visible_bounds)


func adopt_settings(cfg: Resource) -> void:
	if cfg == null:
		return
	_applying = true
	preset = Preset.CUSTOM
	var prefix := "rain" if kind == Kind.RAIN else "snow"
	enabled = bool(cfg.get("precipitation_enabled"))
	density = float(cfg.get("precipitation_density"))
	amount_min = int(cfg.get(prefix + "_amount_min"))
	amount_max = int(cfg.get(prefix + "_amount_max"))
	lifetime_seconds = float(cfg.get(prefix + "_lifetime"))
	speed_min = float(cfg.get(prefix + "_speed_min"))
	speed_max = float(cfg.get(prefix + "_speed_max"))
	spread_degrees = float(cfg.get(prefix + "_spread"))
	particle_size = cfg.get(prefix + "_streak_size" if kind == Kind.RAIN else prefix + "_flake_size")
	scale_min = float(cfg.get(prefix + "_scale_min"))
	scale_max = float(cfg.get(prefix + "_scale_max"))
	gravity = cfg.get(prefix + "_gravity")
	wind_tilt = float(cfg.get(prefix + "_wind_tilt"))
	color = cfg.get(prefix + "_color")
	box_extents = cfg.get(prefix + "_box_extents")
	visible_bounds = cfg.get("precipitation_aabb")
	_applying = false
	_refresh()
