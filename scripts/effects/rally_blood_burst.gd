## Редактируемый всплеск крови: капли и туман — обычные GPUParticles3D в сцене
## `scenes/effects/blood_burst.tscn`. Откройте сцену, нажмите F6, крутите
## amount / lifetime / gravity / цвет в инспекторе. Код только целится по удару
## и перезапускает уже настроенные частицы.
@tool
class_name RallyBloodBurst
extends Node3D

const PREWARM_META := "blood_prewarm"
const BASE_VELOCITY_META := "blood_burst_base_velocity"

@export_group("Что играет")
@export var droplets_path: NodePath = ^"Droplets"
@export var mist_path: NodePath = ^"Mist"
## Через сколько секунд узел удаляется после удара. 0 — не удалять (для лаборатории).
@export_range(0.0, 8.0, 0.05, "suffix:с") var free_after: float = 1.6
## Нацелить выброс вдоль скорости машины.
@export var aim_with_car: bool = true
## Небольшая добавка к скорости капель от скорости машины.
@export_range(0.0, 1.0, 0.01) var extra_speed_from_car: float = 0.02
## Доля скорости машины, которую капли забирают с собой — достаточно, чтобы
## всплеск следовал за машиной, но не превращался в длинное облако.
@export_range(0.0, 1.0, 0.01) var inherit_velocity_ratio: float = 0.62
@export_range(0.0, 2.0, 0.05) var droplet_lift: float = 0.35
@export_range(0.0, 2.0, 0.05) var mist_lift: float = 0.2
@export_multiline var description: String = "Короткий направленный всплеск крови. Править GPUParticles3D Droplets и Mist."


func play(world_velocity: Vector3 = Vector3(0.0, 3.0, 8.0), away_from: Vector3 = Vector3.ZERO) -> void:
	var heading: Vector3 = away_from
	if heading.length() < 0.2:
		heading = world_velocity
	if heading.length() < 0.2:
		heading = Vector3(0.0, 1.0, 0.0)
	heading.y = maxf(heading.y, 0.35)
	heading = heading.normalized()
	if world_velocity.length() > 0.4:
		# Учитываем поток воздуха: мелкие брызги слегка уносит навстречу движению.
		heading = (heading - world_velocity.normalized() * 0.28).normalized()
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
	if process_mat != null:
		process_mat.inherit_velocity_ratio = inherit_velocity_ratio
		process_mat.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
		var base_min: float = process_mat.initial_velocity_min
		var base_max: float = process_mat.initial_velocity_max
		if process_mat.has_meta(BASE_VELOCITY_META):
			var base_velocity: Vector2 = process_mat.get_meta(BASE_VELOCITY_META)
			base_min = base_velocity.x
			base_max = base_velocity.y
		elif not has_meta(PREWARM_META):
			process_mat.set_meta(BASE_VELOCITY_META, Vector2(base_min, base_max))
		if not has_meta(PREWARM_META):
			var bonus: float = speed * extra_speed_from_car
			process_mat.initial_velocity_min = maxf(0.1, base_min + bonus * 0.45)
			process_mat.initial_velocity_max = maxf(
				process_mat.initial_velocity_min, base_max + bonus
			)
		if aim_with_car:
			process_mat.direction = heading + Vector3(0.0, lift, 0.0)
	particles.restart()
