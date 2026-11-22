@tool
class_name RallySponsorBanner
extends Node3D

## ЖК-экран спонсора на трассе.
##
## Щит показывает баннеры из атласа (по умолчанию textures/4XSponsorBanners.png,
## сетка 2×2) и каждые `cycle_time` секунд плавно растворяет текущий в
## следующем; поверх — рябь строк, мерцание и блик стекла.
##
## Само переключение делает шейдер shaders/sponsor_banner.gdshader по времени:
## щиты из библиотеки пропсов запекаются в MultiMesh, где скрипты не работают.
## Этот скрипт только переносит настройки из инспектора в материал экранов
## (узлы `Mesh_screen*`) — в редакторе изменения видны сразу.

const SCREEN_PREFIX := "Mesh_screen"

@export_group("Баннеры")
## Атлас баннеров: картинки одинакового размера, уложенные сеткой.
@export var banner_atlas: Texture2D = null:
	set(value):
		banner_atlas = value
		_apply()
## Сетка атласа: колонки и строки.
@export var atlas_grid: Vector2i = Vector2i(2, 2):
	set(value):
		atlas_grid = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		_apply()
## Сколько ячеек атласа занято баннерами (слева направо, сверху вниз).
@export_range(1, 16) var banner_count: int = 4:
	set(value):
		banner_count = value
		_apply()
## Сколько секунд показывается один баннер, включая переход.
@export_range(0.5, 60.0, 0.1, "suffix:с") var cycle_time: float = 3.0:
	set(value):
		cycle_time = value
		_apply()
## Длительность плавного перехода к следующему баннеру.
@export_range(0.0, 5.0, 0.05, "suffix:с") var crossfade_time: float = 0.6:
	set(value):
		crossfade_time = value
		_apply()
## Разносить щиты по времени, чтобы соседние не переключались хором.
@export var random_phase: bool = true:
	set(value):
		random_phase = value
		_apply()

@export_group("Стиль ЖК-экрана")
## Яркость свечения (больше 1 — экран подсвечивает glow окружения).
@export_range(0.0, 4.0, 0.05) var brightness: float = 1.15:
	set(value):
		brightness = value
		_apply()
## Рябь горизонтальных строк (0 — выключена).
@export_range(0.0, 1.0, 0.01) var scanline_strength: float = 0.3:
	set(value):
		scanline_strength = value
		_apply()
## Число строк по высоте экрана.
@export_range(3.0, 400.0, 1.0) var scanline_frequency: float = 140.0:
	set(value):
		scanline_frequency = value
		_apply()
## Лёгкое мерцание яркости.
@export_range(0.0, 0.4, 0.01) var flicker_strength: float = 0.04:
	set(value):
		flicker_strength = value
		_apply()
## Яркость блика стекла у верхнего края.
@export_range(0.0, 1.0, 0.01) var gloss_strength: float = 0.35:
	set(value):
		gloss_strength = value
		_apply()
## Ширина блика относительно высоты экрана.
@export_range(0.01, 0.35, 0.01) var gloss_width: float = 0.08:
	set(value):
		gloss_width = value
		_apply()


func _ready() -> void:
	_apply()


## Материалы экранов щита (без повторов: лицевой и задний экран делят один).
func screen_materials() -> Array[ShaderMaterial]:
	var result: Array[ShaderMaterial] = []
	for child in get_children():
		var screen := child as MeshInstance3D
		if screen == null or not String(screen.name).begins_with(SCREEN_PREFIX):
			continue
		var material := screen.material_override as ShaderMaterial
		if material != null and not result.has(material):
			result.append(material)
	return result


## Номер баннера, который сейчас на экране (по тем же правилам, что в шейдере).
func current_banner(time_sec: float, phase: float = 0.0) -> int:
	var count := maxi(banner_count, 1)
	var step := floorf(time_sec / maxf(cycle_time, 0.1) + phase * float(count))
	return posmod(int(step), count)


func _apply() -> void:
	if not is_inside_tree():
		return
	for material in screen_materials():
		if banner_atlas != null:
			material.set_shader_parameter("banner_atlas", banner_atlas)
		material.set_shader_parameter("atlas_grid", atlas_grid)
		material.set_shader_parameter("banner_count", banner_count)
		material.set_shader_parameter("cycle_time", cycle_time)
		material.set_shader_parameter("crossfade_time", crossfade_time)
		material.set_shader_parameter("random_phase", random_phase)
		material.set_shader_parameter("brightness", brightness)
		material.set_shader_parameter("scanline_strength", scanline_strength)
		material.set_shader_parameter("scanline_frequency", scanline_frequency)
		material.set_shader_parameter("flicker_strength", flicker_strength)
		material.set_shader_parameter("gloss_strength", gloss_strength)
		material.set_shader_parameter("gloss_width", gloss_width)
