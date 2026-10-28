extends Node3D

@export_group("Физика самой верёвки")
@export var rope_stiffness: float = 75.0     # Натяжение верёвки
@export var rope_damping: float = 5.5        # Затухание верёвки
@export var g_force_sensitivity: float = 0.8 # Сила реакции на разгон и повороты
@export var accel_smoothing: float = 8.0     # Сглаживание мелких кочек
@export var max_swing_angle: float = 65.0    # Максимальный угол отклонения

@export_group("Эффект гибкости (чтобы не была палкой)")
@export var rope_bendiness: float = 1.6      # Насколько сильно прогибается сама нитка дугой
@export var figure_lag: float = 0.45         # Насколько фигурка "запаздывает" и болтается на конце
@export var twist_amount: float = 0.8        # Закручивание фигурки вокруг нитки в поворотах

@export_group("Инверсия осей (если путает стороны)")
@export var invert_left_right: bool = false
@export var invert_front_back: bool = false

var prev_position: Vector3 = Vector3.ZERO
var prev_velocity: Vector3 = Vector3.ZERO
var smoothed_acceleration: Vector3 = Vector3.ZERO

var rope_vel: Vector3 = Vector3.ZERO
var rope_angle: Vector3 = Vector3.ZERO

var fig_vel: Vector3 = Vector3.ZERO
var fig_angle: Vector3 = Vector3.ZERO

var is_ready_first_frame: bool = true
var local_attach_pos: Vector3 = Vector3.ZERO
var rope_length: float = 0.08
var hook_node: Node3D = null
var saved_hook_basis: Basis = Basis.IDENTITY # Хранит родные пропорции фигурки из редактора!
var rope_segments: Array[MeshInstance3D] = []
const SEG_COUNT: int = 8

func _ready() -> void:
	var parent_node: Node3D = get_parent_node_3d()
	var rope_node: MeshInstance3D = find_child("robe", true, false) as MeshInstance3D
	hook_node = find_child("FigureHook", true, false)

	# 1. Запоминаем точные мировые пропорции и поворот фигурки ДО любых изменений!
	var hook_initial_global: Transform3D
	if hook_node:
		hook_initial_global = hook_node.global_transform
		if parent_node:
			var clean_parent: Basis = parent_node.global_transform.basis.orthonormalized()
			saved_hook_basis = clean_parent.inverse() * hook_initial_global.basis
		else:
			saved_hook_basis = hook_initial_global.basis

	var mat: Material = null
	var radius: float = 0.004

	# 2. Вычисляем длину и толщину верёвки
	if rope_node and rope_node.mesh:
		var rope_aabb: AABB = rope_node.mesh.get_aabb()
		var top_world: Vector3 = rope_node.to_global(Vector3(0.0, rope_aabb.position.y + rope_aabb.size.y, 0.0))
		var bot_world: Vector3 = rope_node.to_global(Vector3(0.0, rope_aabb.position.y, 0.0))

		var side_world: Vector3 = rope_node.to_global(Vector3(rope_aabb.size.x * 0.5, 0.0, 0.0)) - rope_node.global_position
		radius = clampf(side_world.length(), 0.0015, 0.025)
		mat = rope_node.get_active_material(0)

		global_position = top_world
		if hook_node:
			rope_length = top_world.distance_to(hook_initial_global.origin)
		else:
			rope_length = top_world.distance_to(bot_world)

		rope_node.visible = false

	# 3. Переносим FigureHook в CharmPivot и возвращаем ему его идеальные пропорции
	if hook_node:
		if hook_node.get_parent() != self:
			hook_node.get_parent().remove_child(hook_node)
			add_child(hook_node)
		hook_node.global_transform = hook_initial_global

	rope_length = maxf(rope_length, 0.02)

	# 4. Создаём сегменты гибкой верёвки
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = (rope_length / float(SEG_COUNT)) * 1.15
	cyl.radial_segments = 8
	if mat:
		cyl.material = mat

	for i in range(SEG_COUNT):
		var seg := MeshInstance3D.new()
		seg.mesh = cyl
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(seg)
		rope_segments.append(seg)

	if parent_node:
		local_attach_pos = parent_node.to_local(global_position)

func _physics_process(delta: float) -> void:
	if delta <= 0.0001:
		return

	var parent_node: Node3D = get_parent_node_3d()
	if not parent_node:
		return

	global_position = parent_node.to_global(local_attach_pos)

	if is_ready_first_frame:
		prev_position = global_position
		prev_velocity = Vector3.ZERO
		smoothed_acceleration = Vector3.ZERO
		is_ready_first_frame = false
		return

	# 1. Скорость и ускорение
	var current_velocity: Vector3 = (global_position - prev_position) / delta
	var raw_acceleration: Vector3 = (current_velocity - prev_velocity) / delta
	if not raw_acceleration.is_finite():
		raw_acceleration = Vector3.ZERO
	raw_acceleration = raw_acceleration.limit_length(35.0)

	prev_position = global_position
	prev_velocity = current_velocity

	if typeof(smoothed_acceleration) != TYPE_VECTOR3 or not smoothed_acceleration.is_finite():
		smoothed_acceleration = Vector3.ZERO

	var weight: float = clampf(delta * accel_smoothing, 0.0, 1.0)
	smoothed_acceleration += (raw_acceleration - smoothed_acceleration) * weight

	# 2. Чистые оси зеркала без искажений масштаба
	var clean_parent_basis: Basis = parent_node.global_transform.basis.orthonormalized()
	var local_gravity: Vector3 = clean_parent_basis.inverse() * (Vector3.DOWN * 9.8)
	var local_inertia: Vector3 = clean_parent_basis.inverse() * (-smoothed_acceleration * g_force_sensitivity)

	if invert_left_right:
		local_inertia.x = -local_inertia.x
	if invert_front_back:
		local_inertia.z = -local_inertia.z

	var local_dir: Vector3 = (local_gravity + local_inertia).normalized()

	var down_y: float = maxf(-local_dir.y, 0.2)
	var target_x: float = clampf(rad_to_deg(atan2(-local_dir.z, down_y)), -max_swing_angle, max_swing_angle)
	var target_z: float = clampf(rad_to_deg(atan2(local_dir.x, down_y)), -max_swing_angle, max_swing_angle)
	var target_angle := Vector3(target_x, 0.0, target_z)

	# 3. Физика верёвки
	var rope_spring: Vector3 = (target_angle - rope_angle) * rope_stiffness
	var rope_damp: Vector3 = -rope_vel * rope_damping
	rope_vel += (rope_spring + rope_damp) * delta
	rope_angle += rope_vel * delta
	rope_angle.x = clampf(rope_angle.x, -max_swing_angle, max_swing_angle)
	rope_angle.z = clampf(rope_angle.z, -max_swing_angle, max_swing_angle)

	# 4. Физика фигурки на кончике верёвки
	var fig_target := Vector3(
		target_angle.x - rope_vel.x * 0.12 * figure_lag,
		(target_angle.z * 0.6 + rope_vel.z * 0.15) * twist_amount,
		target_angle.z - rope_vel.z * 0.12 * figure_lag
	)
	var fig_spring: Vector3 = (fig_target - fig_angle) * (rope_stiffness * 0.65)
	var fig_damp: Vector3 = -fig_vel * (rope_damping * 0.75)
	fig_vel += (fig_spring + fig_damp) * delta
	fig_angle += fig_vel * delta

	global_transform.basis = clean_parent_basis

	# 5. Выстраиваем дугу верёвки (Кривая Безье)
	var mid_angle: Vector3 = rope_angle.lerp(fig_angle, 0.5) - Vector3(rope_vel.x, 0.0, rope_vel.z) * (0.04 * rope_bendiness)
	var mid_basis := Basis.from_euler(Vector3(deg_to_rad(mid_angle.x), 0.0, deg_to_rad(mid_angle.z)))
	var end_basis := Basis.from_euler(Vector3(deg_to_rad(rope_angle.x), deg_to_rad(fig_angle.y), deg_to_rad(rope_angle.z)))

	var p0 := Vector3.ZERO
	var p1: Vector3 = mid_basis * Vector3(0.0, -rope_length * 0.5, 0.0)
	var p2: Vector3 = (p1 * 0.4) + (end_basis * Vector3(0.0, -rope_length, 0.0) * 0.6)

	for i in range(SEG_COUNT):
		var t0: float = float(i) / float(SEG_COUNT)
		var t1: float = float(i + 1) / float(SEG_COUNT)
		var pos_a: Vector3 = p0.bezier_interpolate(p1, p1, p2, t0)
		var pos_b: Vector3 = p0.bezier_interpolate(p1, p1, p2, t1)
		
		var seg: MeshInstance3D = rope_segments[i]
		seg.position = (pos_a + pos_b) * 0.5
		var dir: Vector3 = (pos_a - pos_b).normalized()
		if dir.length_squared() > 0.001:
			var up_vec: Vector3 = dir
			var right_vec: Vector3 = up_vec.cross(Vector3.FORWARD)
			if right_vec.length_squared() < 0.001:
				right_vec = up_vec.cross(Vector3.RIGHT)
			right_vec = right_vec.normalized()
			var fwd_vec: Vector3 = right_vec.cross(up_vec).normalized()
			seg.transform.basis = Basis(right_vec, up_vec, fwd_vec)

	# 6. Поворачиваем фигурку, СОХРАНЯЯ её родные пропорции (saved_hook_basis)!
	if hook_node:
		hook_node.position = p2
		var hook_tilt := Vector3(
			clampf(fig_angle.x * (1.0 + figure_lag * 0.3), -80.0, 80.0),
			fig_angle.y,
			clampf(fig_angle.z * (1.0 + figure_lag * 0.3), -80.0, 80.0)
		)
		var rot_basis := Basis.from_euler(Vector3(
			deg_to_rad(hook_tilt.x),
			deg_to_rad(hook_tilt.y),
			deg_to_rad(hook_tilt.z)
		))
		# Умножаем поворот на исходную матрицу пропорций:
		hook_node.transform.basis = rot_basis * saved_hook_basis
