@tool
## Перемещайте маркеры Start и End в редакторе; камера смотрит на машину
## или на указанный Target. Узел целиком можно дублировать и переставлять.
extends Node3D

@export_range(1.0, 60.0, 0.5, "suffix:s") var duration := 9.0
@export_range(20.0, 100.0, 1.0, "suffix:°") var fov := 46.0
## Если включено, позиции маркеров задают смещение от машины.
@export var follow_car := false
@export var track_car := true
@export var target_height := 1.0
## Смещение точки взгляда влево: машина остаётся справа от меню.
@export_range(-50.0, 50.0, 0.5, "suffix:m") var framing_offset := 15.0
@export var target_path: NodePath

func camera_position(t: float, car: Node3D) -> Vector3:
	var start := get_node_or_null("Start") as Node3D
	var end := get_node_or_null("End") as Node3D
	if start == null or end == null:
		return global_position
	var result := start.global_position.lerp(end.global_position, smoothstep(0.0, 1.0, t))
	return result + car.global_position if follow_car else result

func target_position(car: Node3D) -> Vector3:
	var target: Node3D = get_node_or_null(target_path) as Node3D if not target_path.is_empty() else null
	if not track_car and target != null:
		return target.global_position
	return car.global_position + Vector3.UP * target_height
