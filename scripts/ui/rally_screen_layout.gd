## Ориентация и «крупность» интерфейса — одно место для всех экранов.
##
## Проект рисуется в 1920×1080 (`window/stretch/mode="canvas_items"`,
## `aspect="expand"`). На телефоне это значит две очень разные раскладки:
##
##  * альбом (ландшафт) — высота 1080, ширина 1920 и больше. UI нарисован в
##    тех же px, что и на ПК, но физически кнопка 17 px на экране 6" занимает
##    ~2 мм: «всё мелкое». Поэтому альбом на сенсорном устройстве получает
##    `PORTRAIT...`-независимый множитель UI_SCALE_LANDSCAPE;
##  * портрет — ширина падает до ~1080, высота растёт до ~2000. Горизонтальный
##    HUD (панель этапа слева, таймер сверху, спидометр справа снизу) в такую
##    раскладку не влезает: панели наезжают друг на друга и на кнопки.
##
## Здесь только измерения и числа — без создания узлов. HUD
## (`rally_hud.gd`), меню (`main_menu.gd`, `garage_menu.gd`, титульный экран) и
## тема (`RallyUiTheme`) спрашивают отсюда, и правка масштаба остаётся в одном
## файле.
##
## ВАЖНО: масштаб UI — это размеры шрифтов и отступов, а НЕ `scale` узлов и не
## уменьшение canvas. Растянутая канва размывает текст; крупные шрифты
## остаются чёткими при любом разрешении.
class_name RallyScreenLayout
extends RefCounted

## Альбом на телефоне/в браузере: меню и HUD крупнее на ~15 %. Значение
## подобрано так, чтобы самый длинный пункт («КОНФИГУРАЦИЯ LANCER EVO») ещё
## помещался в свою колонку при 1920 px ширины.
const UI_SCALE_LANDSCAPE := 1.15
## Портрет: шрифты HUD крупнее, потому что экран ближе к лицу, а колонки узкие.
const UI_SCALE_PORTRAIT := 1.05
## Портрет — это высота больше ширины. Порог с запасом: квадратные окна ПК и
## планшеты в альбоме остаются в «альбомной» ветке.
const PORTRAIT_MAX_ASPECT := 1.0

## Сенсорное устройство (телефон/планшет) или браузер. ПК с мышью сюда не
## попадает: там прежние размеры и никаких «крупных» меню.
static func is_touch_runtime() -> bool:
	return (
		OS.has_feature("web")
		or OS.has_feature("mobile")
		or DisplayServer.is_touchscreen_available()
	)


## Размер канвы, в которой живут контролы (1920×1080 на ПК, 1080×2000 в
## портрете телефона). Экран может передать свой размер явно — так тесты
## проверяют обе раскладки без окна.
static func screen_size(fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if fallback.x > 0.0 and fallback.y > 0.0:
		return fallback
	var viewport := Engine.get_main_loop() as SceneTree
	if viewport == null:
		return Vector2(1920.0, 1080.0)
	var root := viewport.root
	if root == null:
		return Vector2(1920.0, 1080.0)
	var visible := root.get_visible_rect().size
	if visible.x <= 0.0 or visible.y <= 0.0:
		return Vector2(1920.0, 1080.0)
	return visible


## Портретная ориентация. Считаем по реальному размеру канвы, а не по
## «mobile»: телефон в альбоме должен остаться альбомным.
static func is_portrait(viewport_size: Vector2 = Vector2.ZERO) -> bool:
	var measured := screen_size(viewport_size)
	if measured.x <= 0.0 or measured.y <= 0.0:
		return false
	return measured.y > measured.x * PORTRAIT_MAX_ASPECT


## Множитель шрифтов/отступов для меню и HUD.
##  * ПК — 1.0 (ничего не меняется);
##  * телефон/браузер в альбоме — UI_SCALE_LANDSCAPE;
##  * портрет — UI_SCALE_PORTRAIT (крупнее + пересобранная раскладка).
static func ui_scale(viewport_size: Vector2 = Vector2.ZERO) -> float:
	if not is_touch_runtime():
		return 1.0
	if is_portrait(viewport_size):
		return UI_SCALE_PORTRAIT
	return UI_SCALE_LANDSCAPE


## Размер шрифта с учётом крупности UI. Минимум 8 px — как у Range в теме.
static func font_size(base_size: int) -> int:
	var scaled := roundi(float(base_size) * ui_scale())
	return maxi(8, scaled)


## Пиксельный размер элемента (высота кнопки, отступ) с учётом крупности.
static func px(base_value: float) -> float:
	return maxf(0.0, base_value * ui_scale())


## Прямоугольник панели HUD в портретной раскладке.
##
## `anchor_x`/`anchor_y` — 0.0 (левый/верхний край), 0.5 (центр) или
## 1.0 (правый/нижний край); `x` — сдвиг от якоря в px. Панель получает
## ширину `width` и высоту `height`. Всё считается от фактической канвы, так
## что та же формула работает и на 1080×2000, и на 1200×1920.
static func portrait_rect(
	viewport_size: Vector2,
	anchor_x: float,
	anchor_y: float,
	x: float,
	y: float,
	width: float,
	height: float
) -> Rect2:
	var measured := screen_size(viewport_size)
	var left: float = measured.x * anchor_x + x
	var top: float = measured.y * anchor_y + y
	# Панель не должна вылезать за край: на узком экране сдвиг от правого
	# якоря может утащить её наружу — прижимаем.
	left = clampf(left, 0.0, maxf(0.0, measured.x - width))
	top = clampf(top, 0.0, maxf(0.0, measured.y - height))
	return Rect2(Vector2(left, top), Vector2(width, height))
