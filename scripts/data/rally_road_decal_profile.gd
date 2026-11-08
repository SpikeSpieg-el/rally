## Набор пятен для одного вида полотна: что именно выпадает на гравии, грязи,
## асфальте и снегу. RoadDecals читает профили и раскладывает пятна по трассе.
##
## Встроенные наборы (defaults()) — это и есть «генерация для каждого вида
## дороги»: у гравия мокрые и рыхлые пятна с грязью, у грязи — глубокая грязь и
## лужи, у асфальта — трещины, мокрые пятна и натасканный гравий, у снега —
## накат, лёд и слякоть. Хотите свой набор — создайте ресурс этого типа и
## положите его в RoadDecals.profiles: встроенные тогда не используются.
@tool
class_name RallyRoadDecalProfile
extends Resource

enum RoadKind { GRAVEL, MUD, ASPHALT, SNOW, GRASS }

@export_group("Покрытие")
@export_enum("Гравий", "Грязь", "Асфальт", "Снег", "Трава") var road_kind: int = RoadKind.GRAVEL
## Сколько пятен на 100 м полотна (плотность именно этого вида покрытия).
@export_range(0.0, 40.0, 0.1) var density: float = 7.0
## Какая доля полуширины полотна занята пятнами: 1 — от обочины до обочины.
@export_range(0.05, 1.0, 0.01) var spread: float = 0.85

@export_group("Пятна")
## Чем больше weight у пятна, тем чаще оно выпадает.
@export var decals: Array[RallyRoadDecalSpec] = []


## Ключ профиля: те же имена, что возвращает RoadSurface.surface_kind().
func kind_name() -> String:
	match road_kind:
		RoadKind.MUD:
			return "mud"
		RoadKind.ASPHALT:
			return "asphalt"
		RoadKind.SNOW:
			return "snow"
		RoadKind.GRASS:
			return "grass"
		_:
			return "gravel"


## Сумма весов всех пятен профиля (0 — на этом покрытии пятен нет).
func total_weight() -> float:
	var total := 0.0
	for spec in decals:
		if spec != null:
			total += maxf(0.0, spec.weight)
	return total


## Встроенные наборы пятен по видам полотна. Возвращаются новые ресурсы, так
## что правка одного профиля в инспекторе не меняет остальные и не портит
## значения по умолчанию.
static func defaults() -> Array[RallyRoadDecalProfile]:
	return [
		_gravel_profile(),
		_mud_profile(),
		_asphalt_profile(),
		_snow_profile(),
		_grass_profile(),
	]


static func _spec(
	label: String,
	spec_kind: int,
	weight: float,
	edge: Color,
	core: Color,
	roughness: float,
	size_min: Vector2,
	size_max: Vector2
) -> RallyRoadDecalSpec:
	var spec := RallyRoadDecalSpec.new()
	spec.display_name = label
	spec.kind = spec_kind
	spec.weight = weight
	spec.edge_color = edge
	spec.core_color = core
	spec.roughness = roughness
	spec.size_min = size_min
	spec.size_max = size_max
	return spec


static func _profile(kind: int, density: float, specs: Array) -> RallyRoadDecalProfile:
	var profile := RallyRoadDecalProfile.new()
	profile.road_kind = kind
	profile.density = density
	for spec in specs:
		if spec is RallyRoadDecalSpec:
			profile.decals.append(spec)
	return profile


## Гравий: мокрые тёмные пятна, светлый разрыхлённый гравий, натасканная грязь
## и редкие лужи после дождя.
static func _gravel_profile() -> RallyRoadDecalProfile:
	var wet := _spec(
		"Мокрый гравий",
		RallyRoadDecalSpec.Kind.WET,
		1.6,
		Color(0.24, 0.20, 0.15, 0.0),
		Color(0.13, 0.11, 0.09, 0.85),
		0.42,
		Vector2(1.6, 2.2),
		Vector2(3.2, 4.6)
	)
	var loose := _spec(
		"Рыхлый гравий",
		RallyRoadDecalSpec.Kind.LOOSE,
		1.4,
		Color(0.52, 0.45, 0.33, 0.0),
		Color(0.58, 0.50, 0.37, 0.8),
		0.95,
		Vector2(1.2, 1.6),
		Vector2(2.6, 3.6)
	)
	var mud := _spec(
		"Натасканная грязь",
		RallyRoadDecalSpec.Kind.MUD,
		1.0,
		Color(0.26, 0.19, 0.11, 0.0),
		Color(0.17, 0.12, 0.07, 0.88),
		0.78,
		Vector2(1.4, 2.0),
		Vector2(2.8, 4.2)
	)
	var puddle := _spec(
		"Лужа",
		RallyRoadDecalSpec.Kind.PUDDLE,
		0.6,
		Color(0.12, 0.14, 0.16, 0.0),
		Color(0.06, 0.07, 0.08, 0.82),
		0.06,
		Vector2(1.4, 1.8),
		Vector2(3.0, 4.4)
	)
	puddle.noise_type = 1
	puddle.normal_strength = 0.0
	return _profile(RoadKind.GRAVEL, 8.0, [wet, loose, mud, puddle])


## Грязь: глубокая колея, сухие корки, лужи и размазанная жижа.
static func _mud_profile() -> RallyRoadDecalProfile:
	var mud := _spec(
		"Грязь",
		RallyRoadDecalSpec.Kind.MUD,
		2.0,
		Color(0.22, 0.16, 0.09, 0.0),
		Color(0.14, 0.10, 0.06, 0.92),
		0.72,
		Vector2(1.8, 2.6),
		Vector2(3.6, 5.4)
	)
	mud.normal_strength = 9.0
	var wet := _spec(
		"Жижа",
		RallyRoadDecalSpec.Kind.WET,
		1.2,
		Color(0.18, 0.14, 0.09, 0.0),
		Color(0.09, 0.07, 0.05, 0.9),
		0.22,
		Vector2(1.6, 2.2),
		Vector2(3.4, 4.8)
	)
	var crack := _spec(
		"Сухая корка",
		RallyRoadDecalSpec.Kind.CRACK,
		0.7,
		Color(0.36, 0.30, 0.21, 0.0),
		Color(0.42, 0.35, 0.24, 0.7),
		0.98,
		Vector2(1.2, 1.8),
		Vector2(2.6, 3.8)
	)
	crack.noise_frequency = 0.08
	var puddle := _spec(
		"Лужа",
		RallyRoadDecalSpec.Kind.PUDDLE,
		0.8,
		Color(0.12, 0.13, 0.14, 0.0),
		Color(0.07, 0.08, 0.09, 0.85),
		0.05,
		Vector2(1.6, 2.0),
		Vector2(3.4, 4.8)
	)
	puddle.normal_strength = 0.0
	return _profile(RoadKind.MUD, 9.0, [mud, wet, crack, puddle])


## Асфальт: мокрые пятна, лужи, трещины/латки и гравий, натасканный с обочины.
static func _asphalt_profile() -> RallyRoadDecalProfile:
	var wet := _spec(
		"Мокрое пятно",
		RallyRoadDecalSpec.Kind.WET,
		1.5,
		Color(0.16, 0.16, 0.17, 0.0),
		Color(0.07, 0.07, 0.08, 0.8),
		0.16,
		Vector2(1.8, 2.4),
		Vector2(3.6, 5.0)
	)
	var puddle := _spec(
		"Лужа",
		RallyRoadDecalSpec.Kind.PUDDLE,
		1.1,
		Color(0.12, 0.13, 0.15, 0.0),
		Color(0.05, 0.06, 0.07, 0.85),
		0.04,
		Vector2(1.6, 2.0),
		Vector2(3.4, 4.8)
	)
	puddle.normal_strength = 0.0
	var crack := _spec(
		"Трещина и латка",
		RallyRoadDecalSpec.Kind.CRACK,
		0.9,
		Color(0.10, 0.10, 0.11, 0.0),
		Color(0.035, 0.035, 0.04, 0.75),
		0.85,
		Vector2(1.0, 1.6),
		Vector2(2.2, 3.4)
	)
	crack.noise_frequency = 0.11
	crack.rim = 0.30
	var loose := _spec(
		"Гравий с обочины",
		RallyRoadDecalSpec.Kind.LOOSE,
		0.8,
		Color(0.50, 0.44, 0.33, 0.0),
		Color(0.44, 0.38, 0.28, 0.75),
		0.92,
		Vector2(1.0, 1.2),
		Vector2(2.2, 3.0)
	)
	return _profile(RoadKind.ASPHALT, 4.5, [wet, puddle, crack, loose])


## Снег: укатанный накат, лёд, слякоть и мокрый снег. Зимой полотно получает
## именно этот набор, даже если летом это был гравий.
static func _snow_profile() -> RallyRoadDecalProfile:
	var pack := _spec(
		"Укатанный снег",
		RallyRoadDecalSpec.Kind.LOOSE,
		2.0,
		Color(0.80, 0.83, 0.88, 0.0),
		Color(0.92, 0.95, 0.99, 0.85),
		0.85,
		Vector2(1.8, 2.6),
		Vector2(3.8, 5.6)
	)
	pack.noise_type = 1
	var ice := _spec(
		"Лёд",
		RallyRoadDecalSpec.Kind.ICE,
		1.0,
		Color(0.56, 0.62, 0.70, 0.0),
		Color(0.70, 0.78, 0.88, 0.7),
		0.05,
		Vector2(1.4, 1.8),
		Vector2(3.2, 4.4)
	)
	ice.normal_strength = 1.5
	var slush := _spec(
		"Слякоть",
		RallyRoadDecalSpec.Kind.WET,
		1.2,
		Color(0.30, 0.32, 0.35, 0.0),
		Color(0.36, 0.39, 0.43, 0.8),
		0.25,
		Vector2(1.6, 2.2),
		Vector2(3.4, 4.8)
	)
	var drift := _spec(
		"Сугроб",
		RallyRoadDecalSpec.Kind.LOOSE,
		1.1,
		Color(0.84, 0.87, 0.92, 0.0),
		Color(0.95, 0.97, 1.0, 0.9),
		0.8,
		Vector2(1.6, 2.4),
		Vector2(3.6, 5.2)
	)
	drift.noise_frequency = 0.026
	return _profile(RoadKind.SNOW, 9.0, [pack, ice, slush, drift])


## Трава — редкие проплешины, если пятно всё же попало за кромку полотна.
static func _grass_profile() -> RallyRoadDecalProfile:
	var bare := _spec(
		"Проплешина",
		RallyRoadDecalSpec.Kind.MUD,
		1.0,
		Color(0.20, 0.18, 0.10, 0.0),
		Color(0.20, 0.16, 0.09, 0.7),
		0.95,
		Vector2(1.0, 1.4),
		Vector2(2.2, 3.2)
	)
	return _profile(RoadKind.GRASS, 2.0, [bare])
