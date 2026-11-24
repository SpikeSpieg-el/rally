## Только Web/mobile: если браузер не успевает за кадром, плавно снижает масштаб 3D
## (меньше пикселей — быстрее кадр), а когда запас появляется — возвращает его.
## Потолок — значение из настроек графики (GameSettings.scaling_scale), поэтому
## ручная настройка по-прежнему главная. На ПК узел отключён и ничего не меняет.
extends Node

const GameSettingsType = preload("res://scripts/ui/game_settings.gd")

## Окно усреднения FPS, секунд: быстро реагирует, но не дёргается на одном кадре.
const WINDOW_SECONDS: float = 1.5
## Ниже этого среднего FPS масштаб уменьшаем.
const LOW_FPS: float = 30.0
## Совсем плохо: сначала режем то, что не мылит картинку (тени, частая
## физика, частицы у колёс), и только потом трогаем масштаб 3D ещё раз.
## Масштаб — последний рычаг: он размывает кадр, а густота теней и шаг
## физики — нет.
const CRITICAL_FPS: float = 24.0
## Выше этого среднего FPS масштаб возвращаем к потолку настроек.
const HIGH_FPS: float = 50.0
## Шаг изменения масштаба за одно окно измерения.
const STEP: float = 0.05

var _elapsed: float = 0.0
var _frames: int = 0
## Что уже срезано в «критическом» режиме, чтобы не делать это каждый кадр.
var _trimmed_shadows: bool = false
var _trimmed_physics: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(GameSettingsType.is_low_power_runtime())


func _process(delta: float) -> void:
	_elapsed += delta
	_frames += 1
	if _elapsed < WINDOW_SECONDS:
		return
	var average_fps: float = float(_frames) / maxf(_elapsed, 0.001)
	_elapsed = 0.0
	_frames = 0
	adjust(average_fps)


## Один шаг регулировки. Вынесено отдельно, чтобы логику можно было проверить
## без браузера: достаточно передать средний FPS.
func adjust(average_fps: float) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var ceiling: float = GameSettingsType.scaling_scale()
	var current: float = viewport.scaling_3d_scale
	var target: float = current
	if average_fps < CRITICAL_FPS:
		_trim_expensive_extras()
	if average_fps < LOW_FPS:
		target = maxf(GameSettingsType.WEB_MIN_SCALE, current - STEP)
	elif average_fps > HIGH_FPS:
		target = minf(ceiling, current + STEP)
		if _trimmed_shadows:
			# FPS в порядке — вернуть тени и частоту физики раньше, чем масштаб.
			_restore_expensive_extras()
			return
	if not is_equal_approx(target, current):
		viewport.scaling_3d_scale = target


## Срезать «дорогое и незаметное» до того, как трогать разрешение.
## Оба шага обратимы: при восстановлении FPS настройки возвращаются.
func _trim_expensive_extras() -> void:
	if not _trimmed_shadows:
		_trimmed_shadows = true
		ProjectSettings.set_setting(
			"rendering/lights_and_shadows/directional_shadow/size",
			GameSettingsType.SHADOW_SIZES[0]
		)
	if not _trimmed_physics:
		_trimmed_physics = true
		# 45 Гц вместо 60: шаг физики больше, кадров в секунду — больше.
		# Машина на 45 Гц остаётся управляемой, это стандартный шаг для
		# мобильных гонок.
		Engine.physics_ticks_per_second = 45


func _restore_expensive_extras() -> void:
	if _trimmed_physics:
		_trimmed_physics = false
		Engine.physics_ticks_per_second = 60
	if _trimmed_shadows:
		_trimmed_shadows = false
		ProjectSettings.set_setting(
			"rendering/lights_and_shadows/directional_shadow/size",
			GameSettingsType.SHADOW_SIZES[GameSettingsType.shadow_quality()]
		)
