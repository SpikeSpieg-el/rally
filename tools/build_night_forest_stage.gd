## Сборка карты «НОЧНОЙ ЛЕС» (rally_stage.tscn + stage_forest_route.tres).
## Запуск: godot --headless --script res://tools/build_night_forest_stage.gd
##
## Делает две вещи:
##   1. Рисует новую плавную трассу (~3 км) в stage_forest_route.tres
##      (файл и его uid сохраняются, ссылки из stage_forest.tres живы).
##   2. Очищает узел Props сцены rally_stage.tscn и расставляет лес заново:
##      сосны/ели с обеих сторон полотна, кусты и валуны у обочин.
##      Высота каждого объекта берётся из той же функции высоты, что и рельеф
##      (RallyStage.height_at), поэтому деревья стоят ровно на земле.
extends SceneTree

const ROUTE_PATH := "res://data/tracks/stage_forest_route.tres"
const STAGE_PATH := "res://scenes/rally_stage.tscn"
const TRACK_PATH := "res://data/tracks/stage_forest.tres"

const RallyStageScript = preload("res://scripts/rally_stage.gd")
const RoadNetworkScript = preload("res://scripts/road_network.gd")

const SEED := 47111977
const CORNER_DEG := 70.0
const STEP := 2.0  # шаг полилинии, м


func _initialize() -> void:
	var curve := _build_route()
	_check_curve(curve)
	ResourceSaver.save(curve, ROUTE_PATH)
	print("Трасса сохранена: длина %.0f м, точек %d" % [curve.get_baked_length(), curve.point_count])
	_dress_stage(curve)
	quit(0)


# ------------------------------------------------------------------- трасса


## Сегменты маршрута: [длина_прямой_м, радиус_поворота].
## У прямой радиус 0; у поворота длина 0 — она считается как радиус * 70°.
## Радиус со знаком: + поворот влево, - вправо.
func _segments() -> Array:
	return [
		[140.0, 0.0], [0.0, 110.0], [70.0, 0.0],
		[0.0, -70.0], [80.0, 0.0], [0.0, 55.0], [40.0, 0.0],
		[0.0, -90.0], [90.0, 0.0], [130.0, 0.0],
		[0.0, 65.0], [70.0, 0.0], [0.0, -45.0], [100.0, 0.0],
		[0.0, 80.0], [50.0, 0.0], [0.0, -60.0], [110.0, 0.0],
		[0.0, 95.0], [60.0, 0.0], [0.0, -75.0], [150.0, 0.0],
		[0.0, 50.0], [90.0, 0.0], [0.0, -110.0], [120.0, 0.0],
		[0.0, 85.0], [70.0, 0.0], [0.0, -65.0], [100.0, 0.0],
		[0.0, 120.0], [80.0, 0.0],
	]


func _segment_run(segment: Array) -> float:
	var length: float = segment[0]
	var radius: float = segment[1]
	if length < 0.001:
		return absf(radius) * deg_to_rad(CORNER_DEG)
	return length


## Плавная высота осевой линии: два наложенных синуса, уклон <= ~6%.
func _elevation(s: float) -> float:
	return 5.0 * sin(TAU * s / 750.0) + 3.0 * sin(TAU * s / 1100.0 + 1.0)


func _build_route() -> Curve3D:
	var curve: Curve3D
	if ResourceLoader.exists(ROUTE_PATH):
		curve = load(ROUTE_PATH) as Curve3D
	if curve == null:
		curve = Curve3D.new()
	curve.bake_interval = 0.5
	curve.clear_points()

	# Полилиния осевой линии: идём по кривизне, высота — из _elevation.
	var polyline := PackedVector3Array()
	var heading := 0.0
	var pos := Vector3.ZERO
	var total := 0.0
	for segment in _segments():
		var run := _segment_run(segment)
		var radius: float = segment[1]
		var curvature := 0.0 if absf(radius) < 0.001 else (1.0 / radius)
		var gone := 0.0
		while gone < run:
			var ds: float = minf(STEP, run - gone)
			heading += curvature * ds
			pos += Vector3(cos(heading), 0.0, -sin(heading)) * ds
			total += ds
			polyline.append(Vector3(pos.x, _elevation(total), pos.z))
			gone += ds

	# Контрольные точки кривой: каждые ~40 м, но на поворотах чаще —
	# каждые ~15° накопленного поворота (и не реже чем через 12 м).
	var samples := PackedInt32Array()
	var last_emit := 0
	var heading_acc := 0.0
	var prev_dir := Vector2.ZERO
	for i in range(1, polyline.size()):
		var a := polyline[i - 1]
		var b := polyline[i]
		var dir := Vector2(b.x - a.x, b.z - a.z).normalized()
		if prev_dir != Vector2.ZERO:
			heading_acc += absf(dir.angle_to(prev_dir))
		prev_dir = dir
		var dist_m: float = float(i - last_emit) * STEP
		if (dist_m >= 40.0 or heading_acc >= deg_to_rad(15.0)) and dist_m >= 12.0:
			samples.append(i)
			last_emit = i
			heading_acc = 0.0
			prev_dir = Vector2.ZERO
	samples.append(polyline.size() - 1)

	var points := PackedVector3Array()
	for index in samples:
		points.append(polyline[index])

	# Ручки Безье: касательная Катмулла-Рома, длина = 1/3 расстояния между
	# соседями (как в редакторе Godot).
	for i in range(points.size()):
		var p := points[i]
		var prev := points[maxi(i - 1, 0)]
		var next := points[mini(i + 1, points.size() - 1)]
		var tangent := (next - prev) / 3.0
		if i == 0:
			tangent = (next - p) / 3.0
		elif i == points.size() - 1:
			tangent = (p - prev) / 3.0
		curve.add_point(p, -tangent, tangent)

	return curve


## Диагностика: минимальное расстояние между несоседними участками осевой
## (полотно 5 м + обочины 2 м: между осями нужно >= 14 м) и макс. уклон.
func _check_curve(curve: Curve3D) -> void:
	var pts := curve.get_baked_points()
	var stride := 10  # каждая 10-я точка запекания (шаг 5 м)
	var min_clear := INF
	var count := pts.size()
	for i in range(0, count, stride):
		for j in range(i + 320, count, stride):  # пропускаем 160 м вдоль трассы
			var d: float = Vector2(pts[i].x, pts[i].z).distance_to(Vector2(pts[j].x, pts[j].z))
			if d < min_clear:
				min_clear = d
	var max_grade := 0.0
	for i in range(count - 1):
		max_grade = maxf(max_grade, absf(pts[i + 1].y - pts[i].y) / 0.5)
	print("Проверка трассы: зазор осей %.1f м (нужно >= 14), макс. уклон %.1f%%" % [
		min_clear, max_grade * 100.0
	])


# -------------------------------------------------------------------- пропсы


func _dress_stage(curve: Curve3D) -> void:
	var packed: PackedScene = load(STAGE_PATH) as PackedScene
	if packed == null:
		push_error("Не открыть " + STAGE_PATH)
		quit(1)
		return
	var root := packed.instantiate() as Node3D
	var props := root.get_node_or_null("Props") as Node3D
	if props == null:
		props = Node3D.new()
		props.name = "Props"
		root.add_child(props)
	for child in props.get_children():
		props.remove_child(child)
		child.free()
	# Старые деревья «Студии трассы» от прежней кривой — прочь.
	var studio := root.get_node_or_null("StudioProps")
	if studio != null:
		root.remove_child(studio)
		studio.free()

	var track := load(TRACK_PATH)
	var stage := RallyStageScript.new()
	stage.track = track
	stage.network = RoadNetworkScript.build(curve, _terrain_rect(curve, track), track.terrain_cell)
	stage._setup_noise()

	var rng := RandomNumberGenerator.new()
	rng.seed = SEED

	var pine_scene: PackedScene = load("res://scenes/props/pine_tree.tscn")
	var fir_scene: PackedScene = load("res://scenes/props/fir_tree.tscn")
	var bush_scene: PackedScene = load("res://scenes/props/bush.tscn")
	var boulder_scene: PackedScene = load("res://scenes/props/boulder.tscn")

	var length := curve.get_baked_length()
	var counts := {"Pine": 0, "Fir": 0, "Bush": 0, "Boulder": 0}

	# Деревья с обеих сторон полотна каждые ~7.5 м; гуще у дороги, реже вглубь.
	var i := int(45.0 / 0.5)
	while i * 0.5 < length - 45.0:
		var s: float = i * 0.5
		var side := _road_side(curve, s)
		var center := curve.sample_baked(s)
		for mirror: float in [1.0, -1.0]:
			if rng.randf() < 0.1:
				continue  # прогалина в лесу
			var offset: float = 9.0 + rng.randf() * rng.randf() * 22.0
			var p := center + side * mirror * offset
			var roll := rng.randf()
			var scene: PackedScene = pine_scene if roll < 0.6 else fir_scene
			var kind: String = "Pine" if roll < 0.6 else "Fir"
			_plant(props, scene, kind, p, stage, rng, 0.9, 1.4, counts)
		i += int(7.5 / 0.5)

	# Кусты: у обочин, каждые ~19 м.
	i = int(30.0 / 0.5)
	while i * 0.5 < length - 40.0:
		var s2: float = i * 0.5
		if rng.randf() < 0.55:
			var mirror2: float = 1.0 if rng.randf() < 0.5 else -1.0
			var p2: Vector3 = curve.sample_baked(s2) + _road_side(curve, s2) * mirror2 * (8.0 + rng.randf() * 6.0)
			_plant(props, bush_scene, "Bush", p2, stage, rng, 0.8, 1.3, counts)
		i += int(19.0 / 0.5)

	# Валуны: у полотна, каждые ~33 м.
	i = int(50.0 / 0.5)
	while i * 0.5 < length - 40.0:
		var s3: float = i * 0.5
		if rng.randf() < 0.5:
			var mirror3: float = 1.0 if rng.randf() < 0.5 else -1.0
			var p3: Vector3 = curve.sample_baked(s3) + _road_side(curve, s3) * mirror3 * (8.0 + rng.randf() * 9.0)
			_plant(props, boulder_scene, "Boulder", p3, stage, rng, 0.7, 1.5, counts)
		i += int(33.0 / 0.5)

	stage.free()

	for child in root.get_children():
		child.owner = root
	packed.pack(root)
	ResourceSaver.save(packed, STAGE_PATH)
	var total: int = counts["Pine"] + counts["Fir"] + counts["Bush"] + counts["Boulder"]
	print("Пропсы расставлены: %d (сосны %d, ели %d, кусты %d, валуны %d)" % [
		total, counts["Pine"], counts["Fir"], counts["Bush"], counts["Boulder"]
	])


func _road_side(curve: Curve3D, s: float) -> Vector3:
	var dir := (curve.sample_baked(s + 2.0) - curve.sample_baked(s - 2.0)).normalized()
	return Vector3(-dir.z, 0.0, dir.x)


func _plant(props: Node3D, scene: PackedScene, kind: String, p: Vector3, stage, rng: RandomNumberGenerator, min_scale: float, max_scale: float, counts: Dictionary) -> void:
	if scene == null:
		return
	var node := scene.instantiate() as Node3D
	if node == null:
		return
	counts[kind] = int(counts[kind]) + 1
	node.name = "%s_%03d" % [kind, int(counts[kind])]
	node.add_to_group("Props")
	var h: float = stage.height_at(p.x, p.z)
	var basis := Basis(Vector3.UP, rng.randf() * TAU)
	basis = basis.scaled(Vector3.ONE * rng.randf_range(min_scale, max_scale))
	node.transform = Transform3D(basis, Vector3(p.x, h, p.z))
	props.add_child(node)
	node.owner = props.owner if props.owner != null else props


func _terrain_rect(curve: Curve3D, track) -> Rect2:
	var pts := curve.get_baked_points()
	var min_x := INF
	var min_z := INF
	var max_x := -INF
	var max_z := -INF
	for p in pts:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	var margin: float = maxf(40.0, track.terrain_margin)
	return Rect2(
		Vector2(min_x - margin, min_z - margin),
		Vector2(max_x - min_x + margin * 2.0, max_z - min_z + margin * 2.0)
	)
