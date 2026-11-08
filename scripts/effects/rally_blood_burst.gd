## Редактируемый всплеск крови: капли и туман — обычные GPUParticles3D в сцене
## `scenes/effects/blood_burst.tscn`. Откройте сцену, нажмите F6, крутите
## amount / lifetime / gravity / цвет в инспекторе. Код только целится по удару
## и перезапускает уже настроенные частицы.
@tool
class_name RallyBloodBurst
extends Node3D

@export_group("Что играет")
@export var droplets_path: NodePath = ^"Droplets"
@export var mist_path: NodePath = ^"Mist"
## Через сколько секунд узел удаляется после удара. 0 — не удалять (для лаборатории).
@export_range(0.0, 8.0, 0.05, "suffix:с") var free_after: float = 2.4
## Нацелить выброс вдоль скорости машины.
@export var aim_with_car: bool = true
## Добавка к скорости частиц от скорости машины, 0 — как настроено в сцене.
@export_range(0.0, 1.0, 0.01) var extra_speed_from_car: float = 0.12
@export_range(0.0, 2.0, 0.05) var droplet_lift: float = 0.55
@export_range(0.0, 2.0, 0.05) var mist_lift: float = 0.35
@export_multiline var description: String = "Капли и туман после удара. Править GPUParticles3D Droplets и Mist."


func play(world_velocity: Vector3 = Vector3(0.0, 3.0, 8.0)) -> void:
	var heading: Vector3 = world_velocity
	if heading.length() < 0.4:
		heading = Vector3(0.0, 1.0, 0.0)
	heading = heading.normalized()
	var speed: float = clampf(world_velocity.length(), 0.0, 55.0)
	_restart(_particles(droplets_path), heading, speed, droplet_lift)
	_restart(_particles(mist_path), heading, speed, mist_lift)
	if free_after > 0.001 and not Engine.is_editor_hint() and is_inside_tree():
		var timer := get_tree().create_timer(free_after)
		timer.timeout.connect(queue_free)


func _particles(path: NodePath) -> GPUParticles3D:
	if path.is_empty():
		return null
	return get_node_or_null(path) as GPUParticles3D


func _restart(particles: GPUParticles3D, heading: Vector3, speed: float, lift: float) -> void:
	if particles == null:
		return
	var process_mat := particles.process_material as ParticleProcessMaterial
	if process_mat != null and aim_with_car:
		process_mat.direction = heading + Vector3(0.0, lift, 0.0)
		if extra_speed_from_car > 0.001:
			var bonus: float = speed * extra_speed_from_car
			process_mat.initial_velocity_min = maxf(0.1, process_mat.initial_velocity_min + bonus * 0.45)
			process_mat.initial_velocity_max = maxf(
				process_mat.initial_velocity_min, process_mat.initial_velocity_max + bonus
			)
	particles.restart()
