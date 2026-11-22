## Разрушаемые пропсы: дощатый забор, щиты, конусы, таблички — всё, у чего в
## библиотеке пропсов (RallyProp) стоит `breakable = true`.
##
## Такой пропс не прикован к земле: пока его не задели, это обычный MultiMesh
## без твёрдой коллизии — только лёгкая зона-датчик. Машина въезжает в датчик —
## секция в тот же кадр рассыпается на настоящие физические обломки (доски,
## стойки, щит), машина теряет немного скорости по закону сохранения импульса,
## летят щепки, звучит треск, камера вздрагивает.
##
## Ресурс res://data/stage/default_breakables.tres — правится в инспекторе:
## у корня сцены этапа (поле `breakables`, группа «Удары и разрушения (гонка)»)
## или прямо в файле. Масса и деление на части — у самого пропса в библиотеке.
@tool
class_name RallyBreakableConfig
extends Resource

@export_group("Включение")
## Главный выключатель. Выключено — разрушаемые пропсы стоят как обычные
## твёрдые препятствия (коллизия по форме из библиотеки).
@export var enabled: bool = true
## Запас датчика вокруг пропса, м: секция рассыпается чуть раньше касания,
## чтобы обломки не рождались внутри кузова.
@export_range(0.0, 2.0, 0.05, "suffix:м") var detect_margin_m: float = 0.35
## Возвращать снесённые пропсы на место при рестарте заезда.
@export var restore_on_restart: bool = true

@export_group("Обломки")
## Сколько физических обломков может жить одновременно на всю сцену. Лишние —
## самые старые — убираются первыми.
@export_range(4, 400, 1) var max_pieces: int = 90
## Сколько секунд обломок лежит на земле, прежде чем исчезнуть.
@export_range(0.5, 120.0, 0.5, "suffix:с") var piece_lifetime_sec: float = 9.0
## Время, за которое обломок уменьшается до нуля в конце жизни.
@export_range(0.0, 5.0, 0.05, "suffix:с") var piece_fade_sec: float = 0.6
## Детали длиннее этого делятся пополам (доска ломается), м. 0 — не делить.
@export_range(0.0, 10.0, 0.05, "suffix:м") var split_longer_than_m: float = 1.6
## Доля скорости машины, с которой обломки улетают вперёд.
@export_range(0.0, 3.0, 0.05) var velocity_transfer: float = 1.1
## Наименьший толчок обломков, м/с: даже при касании секция валится.
@export_range(0.0, 10.0, 0.1, "suffix:м/с") var min_kick_mps: float = 1.6
## Разлёт в стороны от точки удара, м/с.
@export_range(0.0, 20.0, 0.1, "suffix:м/с") var scatter_mps: float = 2.6
## Подброс вверх на полной скорости, м/с.
@export_range(0.0, 20.0, 0.1, "suffix:м/с") var lift_mps: float = 3.2
## Скорость машины, при которой подброс, щепки и встряска выходят на максимум, м/с.
@export_range(2.0, 80.0, 0.5, "suffix:м/с") var full_speed_mps: float = 26.0
## Наибольшая скорость вращения обломков, рад/с.
@export_range(0.0, 40.0, 0.5, "suffix:рад/с") var spin_rad_s: float = 9.0
## Трение обломков о грунт.
@export_range(0.0, 2.0, 0.05) var piece_friction: float = 0.8
## Упругость обломков.
@export_range(0.0, 1.0, 0.05) var piece_bounce: float = 0.15
## Обломки по умолчанию не толкают машину и не попадают под колёса (слой 3):
## на них не подпрыгивают и в них не застревают. Включите — обломки станут
## твёрдыми для кузова.
@export var pieces_hit_car: bool = false

@export_group("Машина")
## Доля импульса, которую машина отдаёт пропсу (1 — честный обмен импульсом:
## машина теряет скорость в пропорции масс).
@export_range(0.0, 4.0, 0.05) var momentum_transfer: float = 1.0
## Потолок потери скорости машиной за одну снесённую секцию, м/с.
@export_range(0.0, 20.0, 0.1, "suffix:м/с") var max_car_speed_loss_mps: float = 2.2
## Царапина и небольшая вмятина на кузове в месте удара: эквивалент потери
## скорости на каждый м/с скорости машины. 0 — кузов не трогать.
@export_range(0.0, 1.0, 0.01) var car_dent_per_mps: float = 0.12
## Потолок этой вмятины, м/с эквивалента.
@export_range(0.0, 30.0, 0.5, "suffix:м/с") var car_dent_max_dv: float = 4.5

@export_group("Камера и вибрация")
## Встряска камеры на полной скорости (0..1, как у эффектов удара машины).
@export_range(0.0, 1.0, 0.01) var shake: float = 0.32
## Рывок камеры на полной скорости (доля kick_m из эффектов удара машины).
@export_range(0.0, 2.0, 0.05) var kick: float = 0.45
## Вибрация геймпада на полной скорости (0..1).
@export_range(0.0, 1.0, 0.05) var rumble: float = 0.45
## Длительность вибрации, с.
@export_range(0.02, 1.0, 0.01, "suffix:с") var rumble_duration: float = 0.16

@export_group("Щепки")
@export var splinters_enabled: bool = true
## Щепок за один удар на полной скорости.
@export_range(1, 256, 1) var splinter_amount: int = 36
## Размер щепки, м (наименьший и наибольший).
@export var splinter_size_m: Vector2 = Vector2(0.025, 0.09)
@export_range(0.1, 5.0, 0.05, "suffix:с") var splinter_lifetime: float = 1.2
@export_range(0.0, 30.0, 0.5, "suffix:м/с") var splinter_speed_min: float = 2.5
@export_range(0.0, 40.0, 0.5, "suffix:м/с") var splinter_speed_max: float = 9.0
## Цвет щепок (у металлических щитов и конусов — переопределяется цветом пропса).
@export var splinter_color: Color = Color(0.62, 0.46, 0.3, 1)
## Облачко пыли там, где стоял пропс.
@export var dust_enabled: bool = true
@export_range(1, 64, 1) var dust_amount: int = 8
@export var dust_color: Color = Color(0.6, 0.56, 0.5, 0.5)

@export_group("Звук")
@export var sound_enabled: bool = true
## Свои звуки треска. Пусто — синтезированный треск дерева.
@export var break_sounds: Array[AudioStream] = []
## Громкость при касании и на полной скорости, дБ.
@export_range(-40.0, 12.0, 0.5, "suffix:дБ") var volume_min_db: float = -14.0
@export_range(-40.0, 12.0, 0.5, "suffix:дБ") var volume_max_db: float = 0.0
@export_range(0.0, 0.5, 0.01) var pitch_jitter: float = 0.15
@export_range(1.0, 50.0, 0.5) var sound_unit_size: float = 9.0


## Сила удара 0..1 по скорости машины.
func strength(speed: float) -> float:
	return clampf(speed / maxf(full_speed_mps, 0.1), 0.0, 1.0)
