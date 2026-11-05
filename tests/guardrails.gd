# godot --headless --path . --script res://tests/guardrails.gd
extends SceneTree

const Placement = preload("res://scripts/data/rally_guardrail_placement.gd")
const Network = preload("res://scripts/road_network.gd")
const Track = preload("res://scripts/data/rally_track_config.gd")
const Layout = preload("res://scripts/data/rally_spawn_layout.gd")
const Stage = preload("res://scripts/rally_stage.gd")

var failures: Array[String] = []


# Слабый левый изгиб непосредственно перед более сильным правым.
class SCurve:
	extends RefCounted
	var total_length := 80.0

	func direction_at(distance: float) -> Vector3:
		var angle := 0.0
		if distance >= 60.0:
			angle = 160.0
		elif distance >= 30.0:
			angle = -20.0 + 6.0 * (distance - 30.0)
		elif distance >= 20.0:
			angle = -2.0 * (distance - 20.0)
		return Vector3(sin(deg_to_rad(angle)), 0, cos(deg_to_rad(angle)))


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)


func _initialize() -> void:
	call_deferred("_run")


func arc(radius: float, sign_value: float, angle: float = PI) -> Curve3D:
	var curve := Curve3D.new()
	for i in range(181):
		var t: float = angle * float(i) / 180.0
		curve.add_point(
			Vector3(sign_value * radius * (1.0 - cos(t)), radius * t * 0.04, radius * sin(t))
		)
	return curve


func snapshot(parent: Node3D) -> Dictionary:
	var result := {}
	var container: Node3D = parent.get_node_or_null("Guardrails")
	if container == null:
		return result
	var visual: MultiMeshInstance3D = container.get_node("Sections")
	var ids: PackedInt32Array = container.get_meta("segment_ids")
	for i in range(ids.size()):
		result[ids[i]] = container.transform * visual.multimesh.get_instance_transform(i)
	return result


func _run() -> void:
	var cfg := Layout.new()
	check(is_equal_approx(cfg.guardrail_offset, 3.0), "отступ по умолчанию 3 м от полотна")
	var track := Track.new()
	var straight := Curve3D.new()
	straight.add_point(Vector3.ZERO)
	straight.add_point(Vector3(0, 0, 160))
	var straight_net = Network.build_sparse(straight)
	check(
		is_zero_approx(Placement.outer_side(straight_net, 80, 40, 65)),
		"на прямой отбойник не нужен"
	)
	var gentle = Network.build_sparse(arc(160, 1.0))
	check(
		is_zero_approx(Placement.outer_side(gentle, gentle.total_length * 0.5, 40, 65)),
		"плавные повороты пропускаются"
	)
	for turn_sign in [-1.0, 1.0]:
		var net = Network.build_sparse(arc(20, turn_sign))
		var distance: float = net.total_length * 0.5
		var side: float = Placement.outer_side(net, distance, 40, 65)
		check(side == -turn_sign, "выбрана внешняя сторона левого/правого поворота")
		var point: Vector3 = Placement.offset_point(net, track, distance, side, 3.0)
		var center := Vector2(turn_sign * 20, 0)
		check(
			Vector2(point.x, point.z).distance_to(center) > 20 + track.road_half_width,
			"ограждение снаружи, а не внутри дуги"
		)
		var road: Vector3 = net.point_at(distance)
		check(
			(
				absf(
					(
						Vector2(point.x - road.x, point.z - road.z).length()
						- track.half_width_at(distance)
						- 3.0
					)
				)
				< 0.01
			),
			"отступ считается от края полотна"
		)

	var long_arc = Network.build_sparse(arc(10, 1.0, PI * 1.5))
	check(
		Placement.outer_side(long_arc, long_arc.total_length * 0.5, 40, 65) == -1.0,
		"шпилька более 180° не меняет внешнюю сторону"
	)
	var s_curve := SCurve.new()
	check(
		is_zero_approx(Placement.outer_side(s_curve, 25, 40, 65)),
		"соседний поворот не ставит ограждение внутри S-дуги"
	)
	check(
		Placement.outer_side(s_curve, 45, 40, 65) == -1.0,
		"сильная часть S-поворота ограждается снаружи"
	)
	var a := Vector3(1, 4, 2)
	var b := Vector3(4, 6, 3)
	var span: Transform3D = Placement.span_transform(a, b)
	check(
		(span * Vector3(-1.5, 0, 0)).distance_to(a) < 0.001,
		"начало секции совпадает с первой точкой грунта"
	)
	check(
		(span * Vector3(1.5, 0, 0)).distance_to(b) < 0.001,
		"конец секции совпадает со следующей точкой"
	)
	check(span.basis.y == Vector3.UP, "стойки вертикальны даже на уклоне")
	var collision: Transform3D = Placement.collision_transform(a, b)
	check(
		collision.basis.is_equal_approx(collision.basis.orthonormalized()),
		"коллизия без неравномерного масштаба и сдвига"
	)

	var full: Array = Placement.segment_ids(850, 3, 12, 0, -1)
	var split: Array = []
	for window in [Vector2(0, 200), Vector2(200, 400), Vector2(400, 850)]:
		split.append_array(Placement.segment_ids(850, 3, 12, window.x, window.y))
	check(full == split, "одни и те же секции при полной сборке и разбиении на чанки")

	var stage = Stage.new()
	stage.track = track
	stage.track.procedural_scenery = false
	stage.track.scenery_density = 0.0
	stage.spawn_layout = cfg
	stage.terrain_rect = Rect2(-120, -120, 240, 240)
	stage.network = Network.build(arc(20, 1.0), stage.terrain_rect, 2.0)
	stage._setup_noise()
	stage.generated = Node3D.new()
	stage.add_child(stage.generated)
	var prop = stage.s_props().by_id("metal_guardrail")
	check(
		prop != null and prop.scene != null and prop.weight == 0.0,
		"модуль зарегистрирован, но не разбрасывается случайно"
	)
	await stage._spawn_guardrails()
	var whole := snapshot(stage.generated)
	check(not whole.is_empty(), "отбойник работает даже при выключенной обстановке")
	var body: Node = stage.generated.get_node("Guardrails/Collision")
	check(body.get_child_count() == whole.size(), "каждая секция имеет коллизию")
	for id in whole:
		var transform: Transform3D = whole[id]
		for endpoint in [-1.5, 0.0, 1.5]:
			var point: Vector3 = transform * Vector3(endpoint, 0, 0)
			check(
				(
					stage.network.distance_to_road(point.x, point.z)
					> track.road_half_width + track.road_shoulder
				),
				"секция не режет полотно"
			)
	stage.generated.get_node("Guardrails").free()
	var partial := {}
	for window in [Vector2(0, 31), Vector2(31, 200)]:
		var chunk := Node3D.new()
		stage.generated.add_child(chunk)
		await stage._spawn_guardrails(window.x, window.y, chunk)
		var values := snapshot(chunk)
		for id in values:
			check(not partial.has(id), "на границе чанков нет дублирующихся секций")
			partial[id] = values[id]
	check(whole.size() == partial.size(), "разбиение на чанки не теряет секции")
	for id in whole:
		check(
			partial.has(id) and (whole[id] as Transform3D).is_equal_approx(partial[id]),
			"позиции совпадают после разбиения"
		)
	cfg.guardrail_collisions = false
	await stage._spawn_guardrails()
	check(
		stage.generated.get_node("Guardrails").get_node_or_null("Collision") == null,
		"коллизии отключаются отдельно"
	)
	stage.generated.get_node("Guardrails").free()
	cfg.guardrails = false
	await stage._spawn_guardrails()
	check(
		stage.generated.get_node_or_null("Guardrails") == null, "генерация отключается в инспекторе"
	)
	cfg.guardrails = true
	stage.network = straight_net
	await stage._spawn_guardrails()
	check(
		stage.generated.get_node_or_null("Guardrails") == null,
		"на прямой не остаются пустые контейнеры"
	)
	stage.free()
	print("Guardrails: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
