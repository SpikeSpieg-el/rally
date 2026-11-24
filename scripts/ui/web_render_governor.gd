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
## Выше этого среднего FPS масштаб возвращаем к потолку настроек.
const HIGH_FPS: float = 50.0
## Шаг изменения масштаба за одно окно измерения.
const STEP: float = 0.05

var _elapsed: float = 0.0
var _frames: int = 0


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
	if average_fps < LOW_FPS:
		target = maxf(GameSettingsType.WEB_MIN_SCALE, current - STEP)
	elif average_fps > HIGH_FPS:
		target = minf(ceiling, current + STEP)
	if not is_equal_approx(target, current):
		viewport.scaling_3d_scale = target
