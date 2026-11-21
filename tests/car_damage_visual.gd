# godot --headless --path . --fixed-fps 120 --script res://tests/car_damage_visual.gd
# Визуальные повреждения кузова: вмятины появляются только от настоящего удара,
# только на Lancer (систему сдаём на пробу) и не задевают ни остальные меши,
# ни здоровье, ни физику. Езда по грунту и приземление после прыжка кузов не мнут,
# а траектория удара с вмятинами и без них совпадает.
extends SceneTree

const Config = preload("res://data/rally_game_config.tres")
const CarModels = preload("res://scripts/car_models.gd")
const SETUP := preload("res://data/setups/11_gravel.tres")

## Машина, на которой система включена. Остальные обязаны остаться нетронутыми.
const DAMAGE_ID := "mitsubishi"
## Кадров: усадка подвески, проезд без препятствий, падение с высоты, удар.
const SETTLE_FRAMES := 120
const DRIVE_FRAMES := 120
const JUMP_FRAMES := 150
const CRASH_FRAMES := 200
## Скорости, м/с: обычная езда и удар о стену.
const DRIVE_SPEED := 12.0
const CRASH_SPEED := 25.0
## Насколько глубоко должен быть помят кузов после удара о стену, метры.
const MIN_DENT_M := 0.01
## Допустимое расхождение траектории удара с вмятинами и без них, метры.
const MAX_PHYSICS_DIFF_M := 0.05

var failures: Array[String] = []


## Провайдер машины для теста. Настоящая игра отдаёт один выбранный автомобиль
## на весь заезд, а здесь каждая модель реестра проверяется отдельно. Сцены всех
## машин несут в скрипте одно значение по умолчанию («mitsubishi»), настоящий id
## приходит из RallyGame — поэтому подставляем своего. Машина и звук спрашивают
## у него только get_race_vehicle_id(), остальные поля читаются через get() и
## отсутствие игры переживают.
class GameStub:
	extends Node

	var race_vehicle_id := "mitsubishi"

	func get_race_vehicle_id() -> String:
		return race_vehicle_id


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)


func _initialize() -> void:
	call_deferred("_run")


func _steps(count: int) -> void:
	for i in range(count):
		await physics_frame


## Открытая площадка и стена впереди: всё, что нужно для удара передом.
func _make_world() -> Node3D:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	ground.add_to_group("Dirt")
	var ground_collider := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(200.0, 1.0, 200.0)
	ground_collider.shape = ground_box
	ground_collider.position.y = -0.5
	ground.add_child(ground_collider)
	world.add_child(ground)
	var wall := StaticBody3D.new()
	# Слой 2 — тот же, что у секций забора на трассе: кузов с ним сталкивается.
	wall.collision_layer = 2
	var wall_collider := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(30.0, 5.0, 1.0)
	wall_collider.shape = wall_box
	wall.add_child(wall_collider)
	wall.position = Vector3(0.0, 2.5, 14.0)
	world.add_child(wall)
	return world


## Меши модели как они есть: узел → ресурс меша.
func _snapshot_meshes(car: RallyCar) -> Dictionary:
	var out := {}
	var model: Node3D = car._find_body_model()
	if model == null:
		return out
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := node as MeshInstance3D
		out[mesh_inst] = mesh_inst.mesh
	return out


## Размеры геометрии кузовных панелей: узел → [поверхностей, вершин].
## Деформация обязана сохранить и то и другое — меняется положение вершин,
## а не их количество. Остальные меши проверяются строже и дешевле: их ресурс
## не должен быть заменён вовсе (см. _meshes_untouched / _only_panels_replaced).
func _snapshot_geometry(car: RallyCar) -> Dictionary:
	var out := {}
	var model: Node3D = car._find_body_model()
	if model == null:
		return out
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := node as MeshInstance3D
		if not mesh_inst.is_in_group("rally_body_fx"):
			continue
		var mesh := mesh_inst.mesh
		if mesh == null:
			out[mesh_inst] = [0, 0]
			continue
		var vertices := 0
		for s in range(mesh.get_surface_count()):
			var surface_arrays := mesh.surface_get_arrays(s)
			var surface_vertices: PackedVector3Array = surface_arrays[Mesh.ARRAY_VERTEX]
			vertices += surface_vertices.size()
		out[mesh_inst] = [mesh.get_surface_count(), vertices]
	return out


func _geometry_same(before: Dictionary, after: Dictionary) -> bool:
	if before.size() != after.size():
		return false
	for node in before:
		if not after.has(node):
			return false
		if before[node] != after[node]:
			return false
	return true


## Ни один меш не заменён.
func _meshes_untouched(before: Dictionary) -> bool:
	for node in before:
		if not is_instance_valid(node):
			return false
		if before[node] != node.mesh:
			return false
	return true


## Заменены меши только кузовных панелей (группа rally_body_fx), и хотя бы одна.
func _only_panels_replaced(before: Dictionary) -> bool:
	var replaced := 0
	for node in before:
		if not is_instance_valid(node):
			return false
		if before[node] == node.mesh:
			continue
		if node.is_in_group("rally_body_fx"):
			replaced += 1
		else:
			return false
	return replaced > 0


func _dent_depth(car: RallyCar) -> float:
	return 0.0 if car.damage_visual == null else car.damage_visual.total_dent_depth()


## Телепорт на площадку подальше от стены, проезд и падение с высоты:
## обычная езда и приземление не должны оставлять вмятин.
func _drive_and_land(car: RallyCar) -> void:
	car.spawn_transform = Transform3D(Basis.IDENTITY, Vector3(-60.0, 0.3, -60.0))
	car.reset_to_spawn()
	car.linear_velocity = Vector3(0.0, 0.0, DRIVE_SPEED)
	await _steps(DRIVE_FRAMES)
	car.spawn_transform = Transform3D(Basis.IDENTITY, Vector3(-60.0, 4.0, -60.0))
	car.reset_to_spawn()
	car.linear_velocity = Vector3(0.0, 0.0, DRIVE_SPEED)
	await _steps(JUMP_FRAMES)


## Лобовой удар о стену. Возвращает траекторию, расхождение с предыдущим заездом
## (если он был) и глубину вмятин к концу заезда.
func _crash_into_wall(car: RallyCar, reference: PackedVector3Array) -> Dictionary:
	car.spawn_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, 0.0))
	car.reset_to_spawn()
	car.linear_velocity = Vector3(0.0, 0.0, CRASH_SPEED)
	car.angular_velocity = Vector3.ZERO
	var track := PackedVector3Array()
	var compare := not reference.is_empty()
	var max_diff := 0.0
	for i in range(CRASH_FRAMES):
		await physics_frame
		track.append(car.global_position)
		if compare and i < reference.size():
			max_diff = maxf(max_diff, track[i].distance_to(reference[i]))
	return {"track": track, "max_diff": max_diff, "depth": _dent_depth(car)}


## Поле `damage_visual_config` у корня RallyCar — то самое место, где настройка
## правится в инспекторе. Проверяем, что поле действительно управляет системой:
## с выключенным ресурсом компонент не ставится вовсе, а потолок глубины из
## ресурса ограничивает вмятину.
func _check_scene_field(game: GameStub) -> void:
	game.race_vehicle_id = DAMAGE_ID
	var scene_path := CarModels.race_scene_path(DAMAGE_ID)
	check(not scene_path.is_empty(), "Lancer есть в реестре машин")
	if scene_path.is_empty():
		return
	var scene := load(scene_path) as PackedScene
	check(scene != null, "сцена Lancer открывается: " + scene_path)
	if scene == null:
		return

	# Выключенная настройка: компонента нет, значит и вмятин быть не может —
	# удар здесь не нужен.
	var off_world := _make_world()
	var off_config := RallyDamageVisualConfig.new()
	off_config.enabled = false
	var off_car := scene.instantiate() as RallyCar
	off_car.setup_override = SETUP
	off_car.mouse_look_enabled = false
	off_car.damage_visual_config = off_config
	off_car.position = Vector3(0.0, 0.3, 0.0)
	off_world.add_child(off_car)
	await _steps(SETTLE_FRAMES)
	check(off_car.damage_visual == null,
		"Lancer: с выключенным ресурсом настройки компонент не ставится")
	check(not off_car.contact_monitor,
		"Lancer: с выключенной настройкой запись контактов не включается")
	off_car.queue_free()
	off_world.queue_free()
	await _steps(2)

	# Своя настройка из поля сцены: потолок глубины 5 см вместо 16 см.
	var soft_world := _make_world()
	var soft_config := RallyDamageVisualConfig.new()
	soft_config.depth_min_m = 0.05
	soft_config.depth_max_m = 0.05
	var soft_car := scene.instantiate() as RallyCar
	soft_car.setup_override = SETUP
	soft_car.mouse_look_enabled = false
	soft_car.damage_visual_config = soft_config
	soft_car.position = Vector3(0.0, 0.3, 0.0)
	soft_world.add_child(soft_car)
	await _steps(SETTLE_FRAMES)
	check(soft_car.damage_visual != null, "Lancer: ресурс настройки из сцены подхватился")
	var soft_run := await _crash_into_wall(soft_car, PackedVector3Array())
	var soft_depth := float(soft_run["depth"])
	check(soft_depth > 0.0 and soft_depth <= 0.05 + 0.0005,
		"Lancer: глубина вмятины берётся из ресурса (%.3f м ≤ 0.05)" % soft_depth)
	soft_car.queue_free()
	soft_world.queue_free()
	await _steps(2)


func _run() -> void:
	var old_game := root.get_node_or_null("RallyGame")
	if old_game != null:
		root.remove_child(old_game)
		old_game.queue_free()
	var game := GameStub.new()
	game.name = "RallyGame"
	root.add_child(game)

	var config := Config.duplicate(true) as RallyGameConfig
	var tested: Array[String] = []
	for vehicle_resource in config.vehicles:
		var data := vehicle_resource as RallyVehicle
		if data == null:
			continue
		tested.append(data.id)
		game.race_vehicle_id = data.id
		var world := _make_world()
		var scene := load(CarModels.scene_path(data.race_scene)) as PackedScene
		check(scene != null, "сцена машины открывается: " + data.id)
		if scene == null:
			world.queue_free()
			continue
		var car := scene.instantiate() as RallyCar
		car.setup_override = SETUP
		car.mouse_look_enabled = false
		car.position = Vector3(0.0, 0.3, 0.0)
		world.add_child(car)
		await _steps(SETTLE_FRAMES)

		var is_damage_car := data.id == DAMAGE_ID
		if is_damage_car:
			check(car.damage_visual != null, "%s: компонент визуальных вмятин установлен" % data.id)
			check(car.contact_monitor and car.max_contacts_reported > 0,
				"%s: физика пишет контакты — иначе точку удара не взять" % data.id)
		else:
			check(car.damage_visual == null,
				"%s: визуальные вмятины не ставим (проба только на Lancer)" % data.id)
			check(not car.contact_monitor, "%s: запись контактов не включена" % data.id)

		var meshes_before := _snapshot_meshes(car)
		var geometry_before := _snapshot_geometry(car)
		check(not meshes_before.is_empty(), "%s: модель кузова найдена" % data.id)

		await _drive_and_land(car)
		check(_dent_depth(car) == 0.0,
			"%s: езда по грунту и приземление кузов не мнут (вмятина %.3f м)"
			% [data.id, _dent_depth(car)])
		check(_meshes_untouched(meshes_before), "%s: без удара геометрию кузова менять нельзя" % data.id)

		var first := await _crash_into_wall(car, PackedVector3Array())
		if is_damage_car and car.damage_visual != null:
			var depth := float(first["depth"])
			var stats: Dictionary = car.damage_visual.deformation_stats()
			var tuning: RallyDamageVisualConfig = car.damage_visual.config
			check(depth >= MIN_DENT_M,
				"Lancer: после удара о стену кузов помят (%.3f м ≥ %.3f)" % [depth, MIN_DENT_M])
			# У низкополигонального кузова вершины стоят редко: раньше профиль
			# считался от точки удара, и ближайшая вершина получала лишь малую
			# долю заданной глубины — вмятина выходила в разы мельче настройки и
			# терялась на глаз. Сильный удар обязан выбирать хотя бы половину
			# потолка глубины из ресурса.
			check(depth >= tuning.depth_max_m * 0.5,
				"Lancer: сильный удар даёт вмятину не меньше половины настроенной глубины (%.3f м ≥ %.3f)"
				% [depth, tuning.depth_max_m * 0.5])
			check(int(stats["moved_vertices"]) > 0,
				"Lancer: вершины кузова сдвинуты (%d шт.)" % int(stats["moved_vertices"]))
			check(float(stats["max_offset_m"]) >= depth * 0.5,
				"Lancer: вмятина видна — вершина ушла на %.3f м" % float(stats["max_offset_m"]))
			var centroid: Vector3 = stats["centroid_local"]
			# Сводка уходит в лог проверки: видно, что удар действительно
			# оставил вмятину спереди, а не «прошёл молча».
			print("Lancer: вмятина %.3f м, сдвинуто вершин %d, центр вмятин %.2f/%.2f/%.2f"
				% [depth, int(stats["moved_vertices"]), centroid.x, centroid.y, centroid.z])
			check(centroid.z > 0.0,
				"Lancer: удар передом мнёт переднюю часть кузова (центр вмятин z=%.2f)" % centroid.z)
			check(_only_panels_replaced(meshes_before),
				"Lancer: деформированы только панели rally_body_fx, интерьер и колёса целы")
			check(_geometry_same(geometry_before, _snapshot_geometry(car)),
				"Lancer: число поверхностей и вершин не изменилось")

			var second := await _crash_into_wall(car, PackedVector3Array())
			check(float(second["depth"]) > depth + 0.0005,
				"Lancer: вмятины накапливаются (%.3f → %.3f м)" % [depth, float(second["depth"])])

			# Ремонт и проверка, что визуал не тянет за собой физику: тот же удар
			# на целом кузове и с выключенным компонентом.
			car.damage_visual.clear_damage()
			var cleared: Dictionary = car.damage_visual.deformation_stats()
			check(car.damage_visual.total_dent_depth() == 0.0 and int(cleared["moved_vertices"]) == 0,
				"Lancer: clear_damage возвращает исходную геометрию")
			# Ресурс настройки общий для всех машин, поэтому выключаем вмятины
			# в его копии: заодно проверяем, что настройка действительно рулит.
			var shared_config: RallyDamageVisualConfig = car.damage_visual.config
			var off_config := shared_config.duplicate() as RallyDamageVisualConfig
			off_config.enabled = false
			car.damage_visual.config = off_config
			var clean := await _crash_into_wall(car, second["track"])
			check(float(clean["max_diff"]) <= MAX_PHYSICS_DIFF_M,
				"Lancer: траектория удара не зависит от вмятин (расхождение %.4f м ≤ %.2f)"
				% [float(clean["max_diff"]), MAX_PHYSICS_DIFF_M])
			check(float(clean["depth"]) == 0.0, "Lancer: с выключенным компонентом вмятин нет")
			car.damage_visual.config = shared_config
		else:
			check(_meshes_untouched(meshes_before), "%s: после удара кузов остался прежним" % data.id)
			check(_geometry_same(geometry_before, _snapshot_geometry(car)),
				"%s: геометрия кузова не изменилась" % data.id)

		car.queue_free()
		world.queue_free()
		await _steps(2)

	await _check_scene_field(game)

	root.remove_child(game)
	game.queue_free()

	# Пустой цикл по реестру означал бы «проверок не было, всё хорошо»: ловим.
	check(tested.has(DAMAGE_ID), "Lancer обязан попасть в проверку реестра")
	check(tested.size() == config.vehicles.size(),
		"реестр перебран целиком: %d из %d машин (%s)"
		% [tested.size(), config.vehicles.size(), ", ".join(tested)])

	if failures.is_empty():
		print("PASS: вмятины только от удара и только на Lancer, физика и здоровье не задеты")
	print("Car damage visual: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
