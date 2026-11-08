## Лаборатория болельщиков и крови. Откройте сцену и нажмите F6.
## Слева — живой человек (инспектор сцены человека), справа — всплеск частиц.
@tool
extends Node3D

@export var autoplay_burst: bool = true
@export var burst_velocity: Vector3 = Vector3(2.0, 4.0, 10.0)


func _ready() -> void:
	if not autoplay_burst:
		return
	var burst := get_node_or_null("BloodBurst")
	if burst != null and burst.has_method("play"):
		burst.call("play", burst_velocity)
