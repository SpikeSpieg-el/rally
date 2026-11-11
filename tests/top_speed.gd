# godot --headless --path . --fixed-fps 120 --script res://tests/top_speed.gd
# Максимальная скорость. У RigidBody3D в Godot по умолчанию включено линейное
# демпфирование (physics/3d/default_linear_damp = 0.1): каждый шаг физики
# скорость кузова умножается на (1 − 0.1·dt), то есть на машину действует
# скрытая сила «0.1 · масса · скорость», которой нет ни в одной формуле игры.
# На 140 км/ч это около 4.8 кН — на порядок больше сопротивления воздуха,
# поэтому стоковая машина упиралась в ~140 км/ч при любой главной паре.
# Тест следит, чтобы на кузове это демпфирование оставалось выключенным, а
# предел скорости задавали мотор, передачи и аэродинамика из сетапа.
extends SceneTree

const CarScene = preload("res://scenes/rally_car.tscn")
const StockSetup = preload("res://data/setups/engine_stock.tres")
## Обе сцены с корнем RallyCar: тело из первой едет в игре, вторая — кузов Subaru.
const CAR_SCENES: Array[String] = ["res://scenes/rally_car.tscn", "res://scenes/rally_car2.tscn"]
## Сток обеих машин и скорость, которую он обязан набрать за RUN_SECONDS с места.
## Со скрытым демпфированием их потолок был 141 и 115 км/ч на любой дистанции.
const RUNS: Array[Dictionary] = [
	{"setup": "res://data/setups/engine_stock.tres", "min_kmh": 180.0},
	{"setup": "res://data/setups/subaru/subaru_sti.tres", "min_kmh": 150.0},
]
const PHYSICS_FPS := 120
const SETTLE_STEPS := 240
const RUN_SECONDS := 20.0
## Допуск на «нулевое» демпфирование кузова, 1/с.
const DAMP_EPSILON := 0.001
## Во сколько раз третий заезд увеличивает Cx·S и сколько км/ч он обязан потерять.
const DRAG_FACTOR := 3.0
const DRAG_MIN_LOSS_KMH := 15.0

var failures: Array[String] = []


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)


func _initialize() -> void:
	call_deferred("_run")


func _steps(count: int) -> void:
	for i in range(count):
		await physics_frame


func _make_world() -> Node3D:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	ground.add_to_group("Dirt")
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Прямая вдоль +Z с запасом: за 20 секунд машина проезжает меньше километра.
	box.size = Vector3(200.0, 1.0, 4000.0)
	collider.shape = box
	collider.position = Vector3(0.0, -0.5, 1900.0)
	ground.add_child(collider)
	world.add_child(ground)
	return world


func _spawn(world: Node3D, scene: PackedScene, setup: RallyCarSetup) -> RallyCar:
	var car := scene.instantiate() as RallyCar
	car.setup_override = setup
	car.mouse_look_enabled = false
	car.position.y = 0.3
	world.add_child(car)
	return car


## Демпфирование, которое движок реально применяет к телу: вместе с проектным
## значением по умолчанию и зонами Area3D, а не только свойство узла.
func _total_linear_damp(scene_path: String) -> float:
	var world := _make_world()
	var car := _spawn(world, load(scene_path) as PackedScene, StockSetup.duplicate(true) as RallyCarSetup)
	await _steps(SETTLE_STEPS)
	var state := PhysicsServer3D.body_get_direct_state(car.get_rid())
	var damp: float = state.total_linear_damp if state != null else INF
	world.free()
	await _steps(2)
	return damp


## Полный газ с места по прямой на автомате.
func _full_throttle(setup: RallyCarSetup) -> Dictionary:
	var world := _make_world()
	var car := _spawn(world, CarScene, setup)
	await _steps(SETTLE_STEPS)
	var result := {
		"cda": car.coefficient_of_drag * car.frontal_area,
		"to_100": -1.0,
		"peak": 0.0,
		"gear": 0,
		"drift": 0.0,
	}
	Input.action_press("throttle")
	for i in range(int(RUN_SECONDS * PHYSICS_FPS)):
		await physics_frame
		result["peak"] = maxf(result["peak"], car.speed_kmh)
		result["drift"] = maxf(result["drift"], absf(car.global_position.x))
		if result["to_100"] < 0.0 and car.speed_kmh >= 100.0:
			result["to_100"] = float(i + 1) / PHYSICS_FPS
	Input.action_release("throttle")
	result["gear"] = car.current_gear
	world.free()
	await _steps(2)
	return result


func _run() -> void:
	# Коробку выбирает игрок в меню (RallyGame), а не пресет: тесту нужен автомат.
	var game := root.get_node_or_null("RallyGame")
	if game != null:
		game.set("transmission_index", RallyCarSetup.Transmission.AUTOMATIC)

	for scene_path in CAR_SCENES:
		var damp: float = await _total_linear_damp(scene_path)
		check(damp < DAMP_EPSILON, "%s: движок не должен тормозить кузов демпфированием (сейчас %.3f 1/с)" % [scene_path.get_file(), damp])

	var stock_peak := 0.0
	for run in RUNS:
		var setup := (load(run["setup"]) as RallyCarSetup).duplicate(true) as RallyCarSetup
		var result: Dictionary = await _full_throttle(setup)
		if run["setup"] == StockSetup.resource_path:
			stock_peak = result["peak"]
		check(is_equal_approx(result["cda"], setup.coefficient_of_drag * setup.frontal_area), "%s: аэродинамика кузова берётся из сетапа" % setup.id)
		check(result["peak"] >= run["min_kmh"], "%s: за %.0f с набирает %.0f км/ч, нужно не меньше %.0f" % [setup.id, RUN_SECONDS, result["peak"], run["min_kmh"]])
		print("%s: 0–100 за %.2f с, за %.0f с — %.1f км/ч на %d-й передаче, Cx·S %.2f м², увод с прямой %.1f м" % [
			setup.id, result["to_100"], RUN_SECONDS, result["peak"], result["gear"], result["cda"], result["drift"],
		])

	# Тот же сток с увеличенным Cx·S: скорость ограничивает именно воздух.
	var draggy := StockSetup.duplicate(true) as RallyCarSetup
	draggy.coefficient_of_drag *= DRAG_FACTOR
	var slow: Dictionary = await _full_throttle(draggy)
	check(stock_peak > 0.0, "в RUNS должен быть стоковый сетап — с ним сравнивается заезд с большим Cx")
	check(slow["peak"] <= stock_peak - DRAG_MIN_LOSS_KMH, "Cx ×%.0f должен отнимать не меньше %.0f км/ч: %.1f против %.1f" % [DRAG_FACTOR, DRAG_MIN_LOSS_KMH, slow["peak"], stock_peak])
	print("Сток с Cx ×%.0f (Cx·S %.2f м²): за %.0f с — %.1f км/ч" % [DRAG_FACTOR, slow["cda"], RUN_SECONDS, slow["peak"]])

	print("Top speed: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
