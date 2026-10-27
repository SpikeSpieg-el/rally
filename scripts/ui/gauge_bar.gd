## Ползунок телеметрии. Направленная шкала: при `centered` заполнение
## растёт от центра влево/вправо (руль, газ-тормоз), иначе от левого края.
class_name GaugeBar
extends Control

@export var bar_color: Color = Color(0.30, 0.90, 0.42, 1.0)
@export var bg_color: Color = Color(0.10, 0.14, 0.18, 1.0)
@export var center_color: Color = Color(0.55, 0.60, 0.66, 1.0)
@export var centered: bool = true
@export var round_corners: bool = true

## Значение: 0..1 (нецентрированная) или -1..1 (центрированная).
var value: float = 0.0


func set_value(new_value: float) -> void:
	value = new_value
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if round_corners:
		draw_rect(rect, bg_color, true, 4.0)
	else:
		draw_rect(rect, bg_color, true)

	if centered:
		draw_line(Vector2(size.x * 0.5, 2.0), Vector2(size.x * 0.5, size.y - 2.0), center_color, 1.0)

	var fill := clampf(absf(value), 0.0, 1.0)
	var width: float = size.x * fill
	if centered:
		if value >= 0.0:
			if round_corners:
				draw_rect(Rect2(size.x * 0.5, 0.0, width, size.y), bar_color, true, 4.0)
			else:
				draw_rect(Rect2(size.x * 0.5, 0.0, width, size.y), bar_color, true)
		else:
			if round_corners:
				draw_rect(Rect2(size.x * 0.5 - width, 0.0, width, size.y), bar_color, true, 4.0)
			else:
				draw_rect(Rect2(size.x * 0.5 - width, 0.0, width, size.y), bar_color, true)
	else:
		if round_corners:
			draw_rect(Rect2(0.0, 0.0, width, size.y), bar_color, true, 4.0)
		else:
			draw_rect(Rect2(0.0, 0.0, width, size.y), bar_color, true)
