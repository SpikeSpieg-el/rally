# godot --headless --path . --script res://tests/road_surface.gd
extends SceneTree

const Surface = preload("res://scripts/road_surface.gd")
var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var surface = Surface.new()
	var point := Vector3(0.2, 0.0, 0.2)
	check(surface.surface_kind("Асфальт", false, 0.0) == "asphalt", "асфальт")
	check(surface.surface_kind("Гравий", true, 0.0) == "grass", "обочина")
	check(surface.surface_kind("Асфальт", false, 1.0) == "snow", "снег поверх асфальта")
	check(surface.surface_kind("Грязь", false, 0.0) == "mud", "грязь")
	var fresh: Dictionary = surface.sample(point, "gravel", 0.0)
	check(fresh.depth == 0.0 and fresh.grip == 1.0 and fresh.rolling == 1.0, "нетронутое покрытие")
	for i in range(300):
		surface.imprint(point, "gravel", 1.0, 0.0, 10.0, 0.016)
	var packed: Dictionary = surface.sample(point, "gravel", 0.0)
	check(packed.compaction > 0.0 and packed.grip > 1.0, "накат улучшает сухой гравий")
	var calm_depth: float = packed.depth
	for i in range(300):
		surface.imprint(point, "gravel", 1.0, 1.0, 10.0, 0.016)
	var rut: Dictionary = surface.sample(point, "mud", 1.0)
	check(rut.depth > calm_depth and rut.depth <= 0.065, "пробуксовка углубляет колею")
	check(rut.rolling > packed.rolling and rut.grip < 1.0, "грязная колея тормозит и скользит")
	check(surface.sample(Vector3(10, 0, 10), "mud", 1.0).depth == 0.0, "изменение локально")
	var left: Dictionary = surface.sample(Vector3(0.39999, 0, 0.2), "mud", 1.0)
	var right: Dictionary = surface.sample(Vector3(0.40001, 0, 0.2), "mud", 1.0)
	check(absf(left.depth - right.depth) < 0.0001, "непрерывность на границе ячейки")
	check(surface.sample(point, "asphalt", 1.0).depth == 0.0, "асфальт не деформируется")
	var count: int = surface.cells.size()
	surface.imprint(Vector3(20, 0, 20), "asphalt", 1.0, 1.0, 10.0, 0.016)
	surface.imprint(Vector3(20, 0, 20), "mud", 0.0, 1.0, 10.0, 0.016)
	surface.imprint(Vector3(20, 0, 20), "mud", 1.0, 1.0, 0.0, 0.016)
	check(surface.cells.size() == count, "асфальт, отсутствие нагрузки и остановка не роют грунт")
	var snow: Dictionary = surface.sample(point, "snow", 0.0)
	check(snow.grip < 1.0 and snow.depth > 0.0, "снег уплотняется даже без дождя")
	for i in range(Surface.MAX_CELLS + 10):
		surface.imprint(Vector3(i, 0, 0), "mud", 1.0, 1.0, 10.0, 0.016)
	check(surface.cells.size() <= Surface.MAX_CELLS, "память ограничена")
	check(surface._order.size() <= Surface.MAX_CELLS * 2 + 4, "очередь вытеснения ограничена")
	surface.clear()
	check(surface.cells.is_empty() and surface._order.is_empty(), "сброс состояния")
	if failures == 0:
		print("PASS: накат, колея, снег, локальность, непрерывность и лимит памяти")
	quit(0 if failures == 0 else 1)
