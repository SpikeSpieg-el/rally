@tool
class_name RallySponsorBanner
extends Node3D

## ЛСД-экран спонсора на трассе.
##
## SponsorBanner — светящаяся «жидкокристаллическая» панель (LSD-экран), а не просто
## картинка: показывает текущий баннер спонсора и каждые `banner_cycle_time` секунд
## плавно растворяет его в следующем, а поверх рисует рябь из полосок и блестящую полосу
## блика — так, будто это работающий рекламный дисплей. Всё настраивается здесь в инспекторе:
## массив картинок-баннеров, время переключения, длительность перехода и стиль экрана.
##
## Шейдер и текстуры живут у этого скрипта (а не записываются вручную в .tscn): он создаёт
## ShaderMaterial поверх узла `Mesh_board` и обновляет uniform'ы каждый кадр. Картинки пока
## цветные заглушки — реальные баннеры кладут в inspector-массив `sponsor_images`.

signal banner_changed(index: int)   # Сработал при старте экрана и каждом смене баннера (с индексом нового).

const SponsorBannerShader = preload("res://shaders/sponsor_banner.gdshader")


@export_group("Баннеры спонсора")
## Реальные логотипы-баннеры. Если массив пуст — рисуем цветные плитки-заглушки «SPONSOR 1…» из hue wheel.
## Заглушки хранятся во внутреннем (неэкспортируемом) списке, чтобы не засорять .tscn.
@export var sponsor_images: Array[Texture2D] = []

## Каждые сколько секунд менять баннер (по умолчанию каждые 3 секунды).
@export_range(0.1, 30.0) @export var banner_cycle_time: float = 3.0
## На сколько времени в конце каждого цикла плавно растворяется один баннер в следующий.
@export_range(0.1, 2.5) @export var banner_crossfade: float = 0.6


@export_group("Стиль ЖК-экрана")
## Рябь из горизонтальных «строк» экрана (признак живого дисплея).
@export var screen_scanlines: bool = true
## Яркость ряби полосок (0 — выключено, 1 — максимум).
@export_range(0.0, 1.0) @export var screen_scanline_strength: float = 0.30
## Количество полосок по высоте экрана.
@export_range(3.0, 80.0) @export var screen_scanline_frequency: float = 26.0

## Блестящая горизонтальная полоса-блик у верхнего края панели (как на стекле LCD).
@export var screen_gloss_band: bool = true
## Ширина блестящей полосы относительно высоты экрана.
@export_range(0.01, 0.35) @export var screen_gloss_width: float = 0.08

## Лёгкое мерцание светимости — чтобы экран «дышал».
@export_range(0.0, 0.4) @export var screen_flicker_strength: float = 0.06


# Узел с отображением панели (обычно MeshInstance3D под именем «Mesh_board»).
var _board: MeshInstance3D = null
var _material: ShaderMaterial = null

## Разрешённый список баннеров, который реально показываем. Инициализируется из inspector-массива,
## либо — из цветных заглушек (внутренний список, не экспортится в .tscn).
var _banners := Array()

# Индекс текущего баннера и сколько времени уже прошло в текущем цикле переключения.
var _banner_index: int = 0
var _elapsed_time: float = 0.0


func _ready() -> void:
	_ensure_board()
	_resolve_banners()
	if not is_instance_valid(_material):
		_build_material()   # с первого раза подставим материал (и вышлем начальный баннер)


func _ensure_board() -> void:
	if is_instance_valid(_board):
		return
	var board := _find_board() as MeshInstance3D
	if is_instance_valid(board):
		_board = board


## Ход по потомкам дерева: собираем все узлы под SponsorBanner (чтобы найти `Mesh_board`).
func _collect_meshes() -> Array:
	var out := Array()
	var stack := Array(get_children())
	while not stack.is_empty():
		var node := stack.pop_back()
		for child in node.get_children():
			stack.push_front(child)
		out.append(node)
	return out


func _find_board() -> MeshInstance3D:
	if is_instance_valid(_board):
		return _board
	# Имя целевого узла — «Mesh_board» (рекламная панель на щите).
	for mesh in _collect_meshes():
		if mesh.name == "Mesh_board":
			return mesh as MeshInstance3D
	# Если имя узла не совпало — берём любой потомок MeshInstance3D.
	for mesh in _collect_meshes():
		if mesh is MeshInstance3D:
			return mesh
	return null


## Рисует цветную плитку-заглушку из hue wheel (чтобы разные баннеры были различимы) и возвращает
## текстуру, либо надёжный вариант прямо через Image, если иконка не отрисовалась.
func make_placeholder(index: int) -> Texture2D:
	var rect := ColorRect.new()
	rect.size = Vector2(512.0, 256.0)   # чёткий размер — иначе иконка будет пустой
	rect.color = _palette_color(index)

	var icon := rect.get_icon() as Texture2D
	if is_instance_valid(icon):
		return icon

	# Запасной надёжный путь: рисуем плитку сразу из Image (не зависит от узла в дереве).
	var image := Image.create(512, 256, false)   # alpha=false — непрозрачная плитка
	image.fill(_palette_color(index))
	return ImageTexture.create_from_image(image) as Texture2D


func _palette_color(index: int) -> Color:
	var hue := float(index % 8) / 8.0
	return Color.from_hsv(hue, 0.85, 1.0, 1.0)


## Заполняем внутренний список баннеров один раз (из inspector или заглушками). Идиомпотентно:
## если массив уже определён — не трогаем его.
func _resolve_banners() -> void:
	if not _banners.is_empty():
		return
	_banners = sponsor_images.duplicate()   # копия списка реальных текстур из инспектора (если есть)
	if _banners.size() == 0 or not is_instance_valid(_banners[0]):
		# Заглушки живём во внутреннем списке, а не в экспортном @export — чтобы .tscn остался чистым.
		_banners = [make_placeholder(i) for i in range(6)]


func _normalize_banner_index(index: int) -> int:
	var size := max(_banners.size(), 1)
	return ((index % size) + size) % size   # нормализуем и отрицательные индексы в [0, size)


func banner_texture(index: int) -> Texture2D:
	if not _banners.is_empty():
		index = _normalize_banner_index(index)
		var image := _banners[index]
		return image if is_instance_valid(image) else make_placeholder(index)
	# Список баннеров не определён или повреждён — рисуем цветную заглушку по индексу.
	return make_placeholder(((index % 6) + 6) % 6)


func _apply_style(shader: ShaderMaterial) -> void:
	shader.set_shader_parameter("lsd_scanlines", screen_scanlines)
	shader.set_shader_parameter("scanline_strength", clampf(screen_scanline_strength, 0.0, 1.0))
	shader.set_shader_parameter("scanline_frequency", screen_scanline_frequency)
	shader.set_shader_parameter("lsd_gloss_band", screen_gloss_band)
	shader.set_shader_parameter("gloss_width", screen_gloss_width)
	shader.set_shader_parameter("flicker_strength", screen_flicker_strength)


func _build_material() -> void:
	if not is_instance_valid(_board):
		return   # без узла-приёмника материала не подставим

	var shader := ShaderMaterial.new()
	shader.shader = SponsorBannerShader      # наш preload'd шейдер
	_apply_style(shader)

	# Не пересоздаём материал, если он уже подставлен (например, _ready сработал дважды).
	if (_board.material_override as SurfaceMaterial) != null:
		return

	_material = shader
	_board.material_override = shader   # теперь Mesh_board рисует наш LSD-экран
	banner_changed.emit(_banner_index)  # первый баннер объявлен


func _set_banner(a_index: int, b_index: int, crossfade_amount: float) -> void:
	if not (is_instance_valid(_material) and is_instance_valid(_board)):
		return
	_material.set_shader_parameter("banner_a", banner_texture(a_index))
	_material.set_shader_parameter("banner_b", banner_texture(b_index))
	_material.set_shader_parameter("crossfade", clampf(crossfade_amount, 0.0, 1.0))


func _process(delta: float) -> void:
	if not is_inside_tree() or _board == null:
		return

	var shader := _material
	if not is_instance_valid(shader):
		return

	_elapsed_time += delta
	var cycle_time := clampf(banner_cycle_time, 0.1, 30.0)
	var crossfade_seconds := clampf(banner_crossfade, 0.1, max(cycle_time * 0.98, 0.1))
	if crossfade_seconds >= cycle_time:
		crossfade_seconds = cycle_time * 0.5

	var next_index := (_banner_index + 1) % max(_banners.size(), 1)

	if _elapsed_time <= (cycle_time - crossfade_seconds):
		# Большая часть цикла — держим текущий баннер без переходов.
		_set_banner(_banner_index, next_index, 0.0)
	elif _elapsed_time < cycle_time:
		# В конце цикла плавно растворяем в следующий баннер (ease-in-out по альфе).
		var progress := clampf((_elapsed_time - (cycle_time - crossfade_seconds)) / crossfade_seconds, 0.0, 1.0)
		_set_banner(_banner_index, next_index, ease_in_out(progress))
	else:
		# Цикл завершён — переходим к следующему баннеру и начинаем заново (беззубой петля).
		_banner_index = next_index
		banner_changed.emit(_banner_index)   # объявляем новый активный баннер
		_elapsed_time = 0.0


func ease_in_out(t: float) -> float:
	return 0.5 * (1.0 - cos(t * PI))
