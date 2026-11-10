## Одно пятно на полотне: лужа, грязь, рыхлый гравий, снежный накат, лёд или
## трещина. Не рисуется кодом «поверх» дороги — это настоящий Decal, а его
## текстуры собираются из шума (NoiseTexture2D + FastNoiseLite + Gradient):
## по цветам ниже, карте нормалей и ORM (шероховатость/металл).
##
## Набор таких пятен на вид полотна задаёт RallyRoadDecalProfile, а сам узор
## раскладывает по трассе RoadDecals. Правьте числа в инспекторе своего
## профиля, код трогать не нужно.
@tool
class_name RallyRoadDecalSpec
extends Resource

enum Kind { WET, LOOSE, MUD, PUDDLE, ICE, CRACK }

@export_group("Что это")
## Имя для инспектора и отладки.
@export var display_name: String = "Пятно"
@export_enum("Мокрое", "Рыхлое", "Грязь", "Лужа", "Лёд", "Трещина") var kind: int = Kind.WET
## Как часто выпадает среди пятен этого вида полотна (0 — не выпадает вовсе).
@export_range(0.0, 10.0, 0.05) var weight: float = 1.0

@export_group("Текстура и шум")
## Цвет по краю пятна: его альфа задаёт мягкую границу с полотном.
@export var edge_color: Color = Color(0.30, 0.24, 0.16, 0.0)
## Цвет ядра пятна.
@export var core_color: Color = Color(0.16, 0.12, 0.08, 0.85)
## Тип шума, из которого собирается форма пятна.
@export_enum("Значение", "Перлин", "Симплекс", "Симплекс+", "Ячейки") var noise_type: int = 2
## Частота шума: меньше — крупные пятна, больше — мелкая рябь.
@export_range(0.002, 0.25, 0.001) var noise_frequency: float = 0.035
@export_range(1, 6, 1) var noise_octaves: int = 3
@export_range(1.0, 4.0, 0.05) var noise_lacunarity: float = 2.0
@export_range(0.1, 0.95, 0.01) var noise_gain: float = 0.5
## Сдвиг сида шума: два пятна одного вида не выглядят близнецами.
@export var noise_seed: int = 0

@export_group("Форма пятна (маска)")
## Сколько «капель» в одной текстуре: 1 — цельное пятно, 3–5 — россыпь.
## Альфа маски уходит в ноль к краю, поэтому пятно никогда не прямоугольник.
@export_range(1, 6, 1) var blob_count: int = 1
## Насколько мягкий край: 0.05 — почти обрез, 0.9 — пятно тает задолго до края.
@export_range(0.05, 0.95, 0.01) var edge_feather: float = 0.55
## Сколько маски съедает шум: 0 — сплошная капля, 0.35 — рваная каша.
@export_range(0.0, 0.85, 0.01) var mask_threshold: float = 0.18
## Контраст маски: 1 — как есть, больше — плотнее ядро и тоньше края.
@export_range(0.2, 4.0, 0.05) var mask_gain: float = 1.0
## Форма капли: (1, 1) — круглое пятно, (3, 0.5) — вытянутая полоса или трещина.
@export var blob_stretch: Vector2 = Vector2(1.0, 1.0)

@export_group("Вид на полотне")
## Размер пятна поперёк и вдоль дороги, м: минимум и максимум.
@export var size_min: Vector2 = Vector2(1.4, 2.0)
@export var size_max: Vector2 = Vector2(3.0, 4.5)
## Насколько пятно перекрывает цвет полотна (0 — только нормали и шероховатость).
@export_range(0.0, 1.0, 0.01) var albedo_mix: float = 0.9
## Прозрачность пятна целиком.
@export_range(0.0, 1.0, 0.01) var opacity: float = 0.85
## Шероховатость пятна: 0.9 — сухая грязь, 0.08 — зеркальная лужа или лёд.
@export_range(0.0, 1.0, 0.01) var roughness: float = 0.9
@export_range(0.0, 1.0, 0.01) var metallic: float = 0.0
## Сила рельефа в карте нормалей (0 — пятно плоское).
@export_range(0.0, 30.0, 0.5) var normal_strength: float = 6.0
## Во сколько раз рельеф мельче формы пятна.
@export_range(0.1, 6.0, 0.05) var normal_scale: float = 2.0


## Имя вида пятна для отладки и тестов.
func kind_name() -> String:
	match kind:
		Kind.LOOSE:
			return "loose"
		Kind.MUD:
			return "mud"
		Kind.PUDDLE:
			return "puddle"
		Kind.ICE:
			return "ice"
		Kind.CRACK:
			return "crack"
		_:
			return "wet"
