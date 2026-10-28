## Ползунок телеметрии. При `centered` заполнение растёт от центра влево/вправо,
## иначе от левого края.
class_name GaugeBar
extends Control

@export var bar_color: Color = Color(0.30, 0.90, 0.42, 1.0)
@export var bg_color: Color = Color(1.0, 1.0, 1.0, 0.08)
@export var center_color: Color = Color(1.0, 1.0, 1.0, 0.4)
@export var centered: bool = true
@export var round_corners: bool = true

var value: float = 0.0


func set_value(new_value: float) -> void:
	value = new_value
	queue_redraw()


func _radius() -> int:
	if not round_corners:
		return 0
	return mini(4, int(size.y * 0.5))


func _trough_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.set_corner_radius_all(_radius())
	return style


func _fill_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bar_color
	style.set_corner_radius_all(_radius())
	return style


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_style_box(_trough_style(), rect)

	var fill := clampf(absf(value), 0.0, 1.0)
	if fill > 0.005:
		var fill_rect: Rect2
		if centered:
			var half_w: float = size.x * 0.5
			var w: float = half_w * fill
			if value >= 0.0:
				fill_rect = Rect2(half_w, 0.0, w, size.y)
			else:
				fill_rect = Rect2(half_w - w, 0.0, w, size.y)
		else:
			fill_rect = Rect2(0.0, 0.0, size.x * fill, size.y)
		draw_style_box(_fill_style(), fill_rect)

	if centered:
		draw_line(
			Vector2(size.x * 0.5, 0.0),
			Vector2(size.x * 0.5, size.y),
			center_color, 1.5
		)
