## Ползунок телеметрии. Направленная шкала: при `centered` заполнение
## растёт от центра влево/вправо (руль, газ-тормоз), иначе от левого края.
## Рисуется StyleBox-ами: тёмный желоб с рамкой и насечками + скруглённая
## цветная заливка. Все цвета правятся экспортами в инспекторе.
class_name GaugeBar
extends Control

@export var bar_color: Color = Color(0.30, 0.90, 0.42, 1.0)
@export var bg_color: Color = Color(0.06, 0.09, 0.12, 1.0)
@export var center_color: Color = Color(0.55, 0.60, 0.66, 1.0)
@export var centered: bool = true
@export var round_corners: bool = true

## Значение: 0..1 (нецентрированная) или -1..1 (центрированная).
var value: float = 0.0


func set_value(new_value: float) -> void:
	value = new_value
	queue_redraw()


func _radius() -> int:
	if not round_corners:
		return 0
	return mini(5, int(size.y * 0.5))


func _trough_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.set_corner_radius_all(_radius())
	style.set_border_width_all(1)
	style.border_color = Color(0.4, 0.5, 0.6, 0.35)
	return style


func _fill_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bar_color
	style.set_corner_radius_all(_radius())
	return style


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_style_box(_trough_style(), rect)

	# Насечки каждые 25 % — шкалу легче читать на скорости.
	var tick_color := Color(1.0, 1.0, 1.0, 0.07)
	for i in range(1, 4):
		var x: float = size.x * 0.25 * float(i)
		draw_line(Vector2(x, 2.0), Vector2(x, size.y - 2.0), tick_color, 1.0)

	if centered:
		# Центральная риска у нулевой отметки.
		draw_line(
			Vector2(size.x * 0.5, 1.0), Vector2(size.x * 0.5, size.y - 1.0),
			Color(center_color, 0.85), 2.0
		)

	var fill := clampf(absf(value), 0.0, 1.0)
	if fill <= 0.001:
		return
	var width: float = size.x * fill
	var fill_rect: Rect2
	if centered:
		if value >= 0.0:
			fill_rect = Rect2(size.x * 0.5, 0.0, width, size.y)
		else:
			fill_rect = Rect2(size.x * 0.5 - width, 0.0, width, size.y)
	else:
		fill_rect = Rect2(0.0, 0.0, width, size.y)
	draw_style_box(_fill_style(), fill_rect)
