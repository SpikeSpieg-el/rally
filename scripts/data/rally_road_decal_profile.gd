## Набор пятен для одного вида полотна: что именно выпадает на гравии, грязи,
## асфальте и снегу. RoadDecals читает профили и раскладывает пятна по трассе.
##
## Это данные, а не код: каждый вид покрытия — свой ресурс
## data/stage/road_decals/{gravel,mud,asphalt,snow,grass}.tres. Откройте нужный
## в инспекторе и правьте: сколько пятен на 100 м, где они лежат по ширине
## полотна, какие именно пятна выпадают (цвет ядра и края, шум, форма маски,
## размер, шероховатость, вес). Код только раскладывает готовые пятна.
@tool
class_name RallyRoadDecalProfile
extends Resource

enum RoadKind { GRAVEL, MUD, ASPHALT, SNOW, GRASS }

## Где лежат профили по видам покрытия и как называются их файлы.
const PROFILE_DIR := "res://data/stage/road_decals"
const PROFILE_NAMES := ["gravel", "mud", "asphalt", "snow", "grass"]

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


## Все профили с диска (data/stage/road_decals/*.tres). Пустые и битые файлы
## пропускаются: генератор потом доберёт недостающие виды заводскими.
static func load_files() -> Array:
	var result: Array = []
	for file_name in PROFILE_NAMES:
		var path := "%s/%s.tres" % [PROFILE_DIR, file_name]
		if not ResourceLoader.exists(path):
			continue
		var loaded: Variant = ResourceLoader.load(path)
		if loaded is RallyRoadDecalProfile:
			result.append(loaded)
	return result


## Заводской набор на случай, если файлов профилей нет вовсе. Значения простые:
## по одному мокрому пятну и одной грязи на покрытие, без изысков — всё
## настраиваемое живёт в .tres, а не здесь.
static func defaults() -> Array:
	var from_files := load_files()
	if not from_files.is_empty():
		return from_files
	return [
		_fallback(RoadKind.GRAVEL, 8.0, Color(0.22, 0.18, 0.13), Color(0.12, 0.10, 0.08), 0.5),
		_fallback(RoadKind.MUD, 9.0, Color(0.24, 0.18, 0.10), Color(0.15, 0.11, 0.06), 0.7),
		_fallback(RoadKind.ASPHALT, 4.5, Color(0.16, 0.16, 0.17), Color(0.08, 0.08, 0.09), 0.3),
		_fallback(RoadKind.SNOW, 9.0, Color(0.82, 0.85, 0.90), Color(0.93, 0.96, 1.0), 0.8),
		_fallback(RoadKind.GRASS, 2.0, Color(0.20, 0.18, 0.10), Color(0.20, 0.16, 0.09), 0.9),
	]


static func _fallback(
	kind: int,
	density: float,
	edge: Color,
	core: Color,
	roughness: float
) -> RallyRoadDecalProfile:
	var wet := RallyRoadDecalSpec.new()
	wet.display_name = "Мокрое пятно"
	wet.kind = RallyRoadDecalSpec.Kind.WET
	wet.weight = 1.0
	wet.edge_color = Color(edge.r, edge.g, edge.b, 0.0)
	wet.core_color = Color(core.r, core.g, core.b, 0.85)
	wet.roughness = roughness * 0.4
	var loose := RallyRoadDecalSpec.new()
	loose.display_name = "Рыхлое пятно"
	loose.kind = RallyRoadDecalSpec.Kind.LOOSE
	loose.weight = 1.0
	loose.edge_color = Color(edge.r, edge.g, edge.b, 0.0)
	loose.core_color = Color(core.r, core.g, core.b, 0.75)
	loose.roughness = roughness
	loose.blob_count = 4
	var specs: Array[RallyRoadDecalSpec] = [wet, loose]
	var profile := RallyRoadDecalProfile.new()
	profile.road_kind = kind
	profile.density = density
	profile.decals = specs
	return profile
