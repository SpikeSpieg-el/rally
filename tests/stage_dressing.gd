# godot --headless --path . --script res://tests/stage_dressing.gd
extends SceneTree

const Dressing = preload("res://scripts/track/stage_dressing.gd")

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func _initialize() -> void:
	# Кластеризация: детерминирована, даёт и поляны (0), и заросли (>1.2),
	# а среднее по длинной трассе не взрывает бюджет объектов.
	var low: float = 10.0
	var high: float = 0.0
	var total: float = 0.0
	var samples: int = 0
	var d: float = 0.0
	while d < 6000.0:
		var a: float = Dressing.cluster_factor(d, 777)
		var b: float = Dressing.cluster_factor(d, 777)
		check(a == b, "cluster_factor должен быть детерминированным")
		low = minf(low, a)
		high = maxf(high, a)
		total += a
		samples += 1
		d += 7.0
	check(low <= 0.01, "на трассе должны быть пустые поляны")
	check(high >= 1.2, "на трассе должны быть плотные заросли")
	check(total / float(samples) < 1.1, "средняя плотность не должна раздувать бюджет")

	# Тормозные таблички: 150/100/50 перед поворотом, у старта отсекаются.
	var markers: PackedFloat32Array = Dressing.braking_marker_distances(800.0, 3700.0)
	check(markers.size() == 3 and markers[0] == 650.0 and markers[2] == 750.0, "таблички 150/100/50")
	check(Dressing.braking_marker_distances(120.0, 3700.0).is_empty(), "таблички не ставятся до старта")

	# Зрители: только крутые повороты, с минимальным интервалом и потолком.
	var corners: Array = []
	for i in range(10):
		corners.append({"distance": 300.0 + float(i) * 200.0, "severity": 2, "direction": 1})
	corners.append({"distance": 2500.0, "severity": 6, "direction": -1})
	var spots: Array = Dressing.select_spectator_corners(corners, 420.0, 3)
	check(spots.size() == 3, "потолок зрительских точек")
	check(float(spots[1].get("distance", 0.0)) - float(spots[0].get("distance", 0.0)) >= 420.0, "интервал между лагерями")

	# ЛЭП: участки внутри трассы, упорядочены, стороны чередуются.
	var ranges: Array = Dressing.powerline_ranges(3700.0, 42)
	check(not ranges.is_empty(), "ЛЭП должна существовать на длинной трассе")
	for line_range in ranges:
		check(float(line_range.get("start", -1.0)) >= 0.0, "ЛЭП не раньше старта")
		check(float(line_range.get("end", 0.0)) <= 3700.0 - 140.0, "ЛЭП не у финиша")
		check(float(line_range.get("end", 0.0)) > float(line_range.get("start", 0.0)), "ЛЭП упорядочена")
	if ranges.size() == 2:
		check(float(ranges[0].get("side", 0.0)) == -float(ranges[1].get("side", 1.0)), "участки ЛЭП по разные стороны")

	# Туман: только настоящие низины и не чаще заданного интервала.
	var points := PackedVector3Array()
	var distances := PackedFloat32Array()
	for i in range(200):
		var x: float = float(i) * 10.0
		points.append(Vector3(x, 20.0 - 12.0 * exp(-pow((x - 600.0) / 90.0, 2.0)) - 10.0 * exp(-pow((x - 1500.0) / 80.0, 2.0)), 0.0))
		distances.append(x)
	var fog: PackedFloat32Array = Dressing.fog_distances(points, distances, 420.0, 6)
	check(fog.size() == 2, "две низины — два пятна тумана")
	if fog.size() == 2:
		check(fog[1] - fog[0] >= 420.0, "туман не чаще интервала")

	# Сюжетные точки внутри заданных долей длины.
	var house: float = Dressing.landmark_distance(3700.0, 5, 21, 0.52, 0.62)
	check(house >= 3700.0 * 0.52 and house <= 3700.0 * 0.62, "домик лесника во второй половине")

	if failures.is_empty():
		print("STAGE_DRESSING_OK")
		quit(0)
	else:
		printerr("STAGE_DRESSING_FAILURES: %d" % failures.size())
		quit(1)
