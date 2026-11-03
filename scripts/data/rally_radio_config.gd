## Настройки радиостанции: плейлист собирается из папки OGG, а здесь лежат
## оформление и параметры сведения. Файл: res://data/radio/default_radio.tres.
## Меняйте числа в инспекторе — код подхватит их при следующем запуске.
@tool
class_name RallyRadioConfig
extends Resource

const DEFAULT_MUSIC_DIR := "res://audio/music"

@export_group("Станция")
@export var station_name: String = "RALLY FM"
@export var station_tagline: String = "СПЕЦУЧАСТОК · НОН-СТОП МИКС"
## Папка с музыкой. Сканируется один раз при запуске: 100 OGG не грузятся
## в память сразу, поток читается по одному файлу.
@export var music_dir: String = DEFAULT_MUSIC_DIR
@export var cover_paths: Array[String] = [
	"res://textures/radio/night_stage.png",
	"res://textures/radio/gravel_ghost.png",
	"res://textures/radio/red_mist.png",
	"res://textures/radio/snow_line.png",
]

@export_group("Сведение")
## Длительность наложения двух треков. Фактическое значение немного
## варьируется случайно, чтобы переходы не звучали по шаблону.
@export_range(1.0, 12.0, 0.1) var crossfade_seconds: float = 6.0
## Громкость плеера: треки уже нормализованы до −14 LUFS, поэтому минус
## оставляет место двигателю и не дёргает ограничитель на Master.
@export_range(-24.0, 0.0, 0.5) var music_volume_db: float = -7.0
@export_range(-12.0, 0.0, 0.5) var music_bus_db: float = -1.0
@export_range(-12.0, 0.0, 0.5) var vehicle_bus_db: float = -1.0
## Сколько декодированных потоков держать в кэше. Два плеера + запас на
## следующий трек: вся библиотека в память не попадает.
@export_range(2, 8, 1) var stream_cache_size: int = 4
