## Настройки редакторской студии трассы.
##
## Это «пульт» инструмента, который живёт в 3D-вьюпорте Godot:
## `addons/rally_track_studio/`. Здесь нет ни одного параметра геймплея —
## только внешний вид разметки, пороги предупреждений, шаг выборки и
## поведение кисти. Файл по умолчанию — `data/editor/track_studio.tres`.
##
## Правило проекта соблюдается: ни одного магического числа в коде плагина,
## все ползунки — здесь, в инспекторе Godot, с комментариями.
@tool
class_name RallyTrackStudioSettings
extends Resource

@export_group("Инструмент")
## Включать студию сразу при открытии сцены этапа.
@export var enabled_on_open: bool = true
## Рисовать разметку поверх 3D-вьюпорта (иначе инструмент только правит данные).
@export var show_overlay: bool = true
## Показывать информационную панель и профиль высот внизу вьюпорта.
@export var show_hud: bool = true
## Заливка полотна вдоль осевой линии.
@export var show_ribbon: bool = true
## Пунктирная осевая линия полотна.
@export var show_dashes: bool = true
## Километровые отметки и подписи.
@export var show_km: bool = true
## Подписи поворотов в раллийном стиле (Л4, П2, …).
@export var show_pace_notes: bool = true
## Предупреждения: узкий радиус, крутой уклон, близкие витки.
@export var show_warnings: bool = true
## Полоса профиля высот внизу вьюпорта.
@export var show_profile: bool = true
## Строка подсказок по горячим клавишам в панели.
@export var show_hints: bool = true
## Стрелки направления движения вдоль трассы.
@export var show_direction: bool = true
## Шаг стрелок направления, м.
@export_range(10.0, 300.0, 5.0) var direction_step: float = 60.0
## Подсказка с километражем/радиусом/шириной под курсором. По умолчанию
## выключена: она ездит за мышью и требует перерисовки на каждом движении.
@export var show_cursor: bool = false
## «Призрак» новой точки на земле под курсором (в режиме «Трасса»). Стоит
## лишнего луча по рельефу на каждое движение мыши, поэтому по умолчанию нет.
@export var show_ghost_point: bool = false
## Заметный режим экономии редактора: отключает заливку полотна, пунктир,
## стрелки и снижает частоту проверок мыши для максимального FPS в Godot.
@export var eco_mode: bool = false
## Ускоренная черновая сборка мира (без декалей, леса и декора, грубее сетка)
## для быстрых примерок геометрии.
@export var fast_rebuild: bool = false
## Расстояние до точки при телепортации камеры (F или двойной клик), м.
@export_range(10.0, 300.0, 5.0) var camera_focus_distance: float = 48.0
## Высота камеры над точкой при телепортации, м.
@export_range(5.0, 200.0, 5.0) var camera_focus_height: float = 28.0
## Шаг расстановки равномерных КПП при авто-разметке зон, м.
@export_range(100.0, 2000.0, 50.0) var auto_checkpoint_step: float = 500.0

@export_group("Точность и отклик")
## Шаг выборки осевой линии для разметки, м.
@export_range(0.5, 20.0, 0.5) var sample_step: float = 2.0
## Потолок выборок на всю трассу: на 100-км марафоне шаг увеличится сам.
@export_range(500, 20000, 250) var max_samples: int = 4000
## Радиус захвата точки маршрута, px.
@export_range(6.0, 40.0, 1.0) var handle_radius_px: float = 13.0
## Радиус захвата самой линии дороги для вставки точки, px.
@export_range(8.0, 60.0, 1.0) var insert_radius_px: float = 20.0
## Частота обновления подсказки под курсором, Гц.
@export_range(5.0, 60.0, 1.0) var hover_hz: float = 24.0
## Шаг сетки для новых точек, м. 0 — без привязки.
@export_range(0.0, 10.0, 0.1) var snap_step: float = 0.5
## Насколько поднять новую точку над землёй, м.
@export_range(-2.0, 2.0, 0.05) var point_height_offset: float = 0.0
## Доля расстояния до соседа для автоматической касательной (1/3 — Catmull-Rom).
@export_range(0.05, 0.5, 0.01) var handle_length_ratio: float = 0.33
## Шаг изменения высоты при Shift-перетаскивании, м на метр экрана.
@export_range(0.005, 1.0, 0.001) var vertical_drag_scale: float = 0.35

@export_group("Анализ трассы")
## Окно сглаживания кривизны, м.
@export_range(6.0, 60.0, 1.0) var corner_window: float = 22.0
## С какого угла начинается поворот для подписи, градусы.
@export_range(10.0, 170.0, 1.0) var corner_threshold_deg: float = 28.0
## Угол, которому соответствует самый пологий поворот (6), градусы.
@export_range(10.0, 90.0, 1.0) var pace_note_min_angle: float = 30.0
## Угол, которому соответствует самый крутой поворот (1), градусы.
@export_range(90.0, 179.0, 1.0) var pace_note_max_angle: float = 165.0
## Минимальный радиус, ниже которого HUD предупреждает, м.
@export_range(5.0, 100.0, 1.0) var min_radius_warning: float = 14.0
## Максимальный уклон, выше которого HUD предупреждает, %.
@export_range(2.0, 40.0, 0.5) var max_grade_warning: float = 14.0
## Минимальный зазор между далёкими витками трассы, м.
@export_range(5.0, 80.0, 1.0) var min_gap_warning: float = 18.0
## Дальше какого километража витки считаются «далёкими» при поиске зазора, м.
@export_range(10.0, 300.0, 5.0) var gap_along_margin: float = 60.0
## Ориентир средней скорости для оценки времени, км/ч.
@export_range(20.0, 160.0, 1.0) var estimate_speed_kmh: float = 78.0

@export_group("Полотно и участки")
## Длина плавного перехода ширины у нового участка, м.
@export_range(20.0, 500.0, 5.0) var section_transition: float = 140.0
## Шаг изменения полуширины краем полотна, м.
@export_range(0.05, 2.0, 0.05) var width_step: float = 0.2
## Границы полуширины в редакторе, м.
@export_range(2.0, 6.0, 0.1) var min_half_width: float = 2.5
@export_range(5.0, 12.0, 0.1) var max_half_width: float = 9.0
## Полуширина по умолчанию, если у сцены нет ресурса трассы, м.
@export_range(2.0, 10.0, 0.1) var fallback_half_width: float = 4.5
## Насколько близко к началу участка нужно тянуть край, чтобы править его,
## а не создавать новый, м.
@export_range(5.0, 200.0, 5.0) var section_grab_distance: float = 40.0
## Расстояние между ручками ширины вдоль трассы, м.
@export_range(5.0, 200.0, 5.0) var width_handle_step: float = 40.0
## Названия покрытий по порядку; переключаются клавишей X.
@export var surface_names: PackedStringArray = PackedStringArray([
	"Гравий", "Асфальт", "Грязь", "Снег", "Трава",
])
## Цвета покрытий для полосы профиля и разметки (порядок как выше).
@export var surface_colors: PackedColorArray = PackedColorArray([
	Color(0.62, 0.50, 0.32, 1.0),
	Color(0.36, 0.38, 0.42, 1.0),
	Color(0.42, 0.29, 0.19, 1.0),
	Color(0.86, 0.90, 0.95, 1.0),
	Color(0.33, 0.45, 0.22, 1.0),
])

@export_group("Кисть обстановки")
## Радиус кисти, м.
@export_range(1.0, 40.0, 0.5) var brush_radius: float = 7.0
## Минимальное расстояние между объектами в одном мазке, м.
@export_range(0.5, 20.0, 0.5) var brush_spacing: float = 3.0
## Шанс поставить объект в каждой точке мазка.
@export_range(0.05, 1.0, 0.01) var brush_chance: float = 0.55
## Не ставить объекты на полотно и обочину.
@export var brush_avoid_road: bool = true
## Запас от кромки полотна, м.
@export_range(0.0, 20.0, 0.5) var brush_road_margin: float = 2.5
## Дополнительный масштаб кисти поверх размера пропса.
@export_range(0.05, 5.0, 0.05) var brush_scale: float = 1.0
## Потолок объектов за один мазок.
@export_range(1, 200, 1) var brush_max_per_stroke: int = 40
## Ограничить набор id (пусто — все сцены из библиотеки пропсов).
@export var brush_prop_ids: PackedStringArray = PackedStringArray()

@export_group("Зоны и сервис")
## Радиус захвата маркеров старта, финиша и КПП, px.
@export_range(6.0, 30.0, 1.0) var zone_radius_px: float = 14.0
## Минимальное расстояние между контрольными точками, м.
@export_range(50.0, 2000.0, 10.0) var checkpoint_spacing_min: float = 150.0
## Пересобирать мир после правок автоматически (тяжело для больших карт).
@export var auto_rebuild: bool = false
## Задержка автосборки после последней правки, сек.
@export_range(0.5, 10.0, 0.1) var auto_rebuild_delay: float = 2.0
## Сколько секунд HUD показывает «собираю мир» после запуска сборки, сек.
@export_range(0.5, 10.0, 0.1) var build_feedback_seconds: float = 2.5
## Сохранять .tres трассы и расстановки на диск сразу после правки.
@export var save_resources_on_commit: bool = true

@export_group("Оформление HUD")
## Отступ панелей от края вьюпорта, px.
@export_range(4.0, 60.0, 1.0) var panel_margin: float = 14.0
## Ширина левой панели, px.
@export_range(160.0, 640.0, 10.0) var panel_width: float = 276.0
## Высота полосы профиля, px.
@export_range(60.0, 320.0, 1.0) var profile_height: float = 104.0
## Кегль основного текста.
@export_range(8, 32, 1) var font_size: int = 14
## Кегль подписей на карте и мелких строк.
@export_range(8, 26, 1) var small_font_size: int = 11
## Толщина линий разметки, px.
@export_range(1.0, 6.0, 0.5) var line_width: float = 1.6
## Минимальная площадь полигона разметки, px². Мельче — не рисуем: такие
## полигоны Godot не может триангулировать и печатает ошибки на каждый кадр.
@export_range(0.0, 8.0, 0.1) var min_polygon_area: float = 0.6
## Сколько столбиков-трапеций максимум в заливке профиля. Один полигон на
## 500 вершин Godot триангулирует за O(n²) в каждом кадре — это и тормозило.
@export_range(16, 512, 1) var profile_fill_max_quads: int = 200
## Толщина кромки полотна, px.
@export_range(1.0, 6.0, 0.5) var edge_width: float = 2.2
## Радиус точки маршрута, px.
@export_range(2.0, 14.0, 0.5) var handle_dot_radius: float = 4.5
## Радиус кружка с раллийным номером поворота, px.
@export_range(6.0, 22.0, 0.5) var corner_badge_radius: float = 11.0
## Размер значка предупреждения на трассе, px.
@export_range(4.0, 20.0, 0.5) var warning_icon_radius: float = 7.0
## Высота «флажка» старта/финиша/КПП, px.
@export_range(6.0, 40.0, 1.0) var zone_flag_height: float = 14.0
## Насколько створ зоны толще обычной линии в режиме «Зоны», px.
@export_range(0.0, 4.0, 0.2) var zone_extra_width: float = 1.6
## Прозрачность заливки полотна (0 — только контур).
@export_range(0.0, 1.0, 0.02) var ribbon_alpha: float = 0.30
## Дальность, после которой разметка бледнеет, м.
@export_range(100.0, 3000.0, 50.0) var fade_distance: float = 900.0
## Шаг километровых насечек, м.
@export_range(10.0, 500.0, 10.0) var km_tick_interval: float = 100.0
## Шаг подписанных километровых отметок, м.
@export_range(50.0, 5000.0, 50.0) var km_label_interval: float = 500.0
## Период пунктира осевой линии, м.
@export_range(4.0, 100.0, 1.0) var dash_period: float = 14.0
## Длина штриха пунктира, м.
@export_range(1.0, 100.0, 1.0) var dash_length: float = 6.0
## Насколько створ старта/финиша/КПП шире полотна в каждую сторону, м.
@export_range(0.0, 20.0, 0.5) var zone_half_width_extra: float = 3.0
## Минимальное расстояние между подписями поворотов на экране, px.
@export_range(10.0, 200.0, 1.0) var corner_label_gap_px: float = 54.0
## Скорость затухания прозрачности — насколько дальняя разметка бледнее.
@export_range(0.0, 1.0, 0.02) var far_alpha_floor: float = 0.25
@export var panel_bg: Color = Color(0.055, 0.075, 0.105, 0.90)
@export var panel_border: Color = Color(0.99, 0.72, 0.24, 0.80)
@export var text_color: Color = Color(0.94, 0.95, 0.96, 1.0)
@export var muted_color: Color = Color(0.63, 0.69, 0.75, 1.0)
@export var accent_color: Color = Color(1.0, 0.66, 0.15, 1.0)
@export var danger_color: Color = Color(1.0, 0.35, 0.28, 1.0)
@export var warning_color: Color = Color(1.0, 0.76, 0.22, 1.0)
@export var ok_color: Color = Color(0.46, 0.86, 0.52, 1.0)
@export var start_color: Color = Color(0.25, 0.72, 1.0, 1.0)
@export var finish_color: Color = Color(1.0, 0.52, 0.18, 1.0)
@export var checkpoint_color: Color = Color(0.98, 0.84, 0.22, 1.0)
@export var road_edge_color: Color = Color(0.99, 0.86, 0.44, 0.95)
@export var center_line_color: Color = Color(1.0, 1.0, 1.0, 0.55)
@export var selection_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var hover_color: Color = Color(0.45, 0.95, 1.0, 1.0)
@export var shadow_color: Color = Color(0.0, 0.0, 0.0, 0.55)

@export_group("Тексты")
## Заголовок панели.
@export var title_text: String = "РЕДАКТОР ТРАССЫ"
## Названия режимов в порядке кнопок панели инструментов.
@export var mode_names: PackedStringArray = PackedStringArray([
	"ТРАССА", "ПОЛОТНО", "ЛЕС", "ЗОНЫ",
])
## Подсказки режима «Трасса».
@export var hints_route: PackedStringArray = PackedStringArray([
	"ЛКМ — тянуть точку, клик по линии — вставить",
	"Shift+тянуть — высота, ПКМ — удалить точку",
	"G — по земле, L — выровнять уклон, I — реверс",
	"S — сгладить, F — камера к точке, Ctrl+R — мир",
])
## Подсказки режима «Полотно».
@export var hints_road: PackedStringArray = PackedStringArray([
	"тяните край полотна — ширина участка",
	"маркер — граница, ПКМ по маркеру — удалить",
	"X / Shift+X — сменить покрытие участка",
	"F — камера к месту, двойной клик по профилю",
])
## Подсказки режима «Лес».
@export var hints_props: PackedStringArray = PackedStringArray([
	"ЛКМ/протяжка — ставить, ПКМ/протяжка — ластик",
	"V/B — вид пропса, [ ] или Ctrl+колесо — радиус",
	"G — посадить на землю все StudioProps",
])
## Подсказки режима «Зоны».
@export var hints_zones: PackedStringArray = PackedStringArray([
	"тяните старт, финиш и арки КПП",
	"клик — добавить КПП, ПКМ по арке — удалить",
	"Shift+клик — старт, Ctrl+клик — финиш, A — авто-КПП",
])
## Строка «мир собран».
@export var text_built: String = "мир собран"
## Строка «есть несобранные правки».
@export var text_dirty: String = "есть правки — Ctrl+R"
## Строка «сборка идёт».
@export var text_building: String = "собираю мир…"
## Строка, когда сцена не распознана как этап.
@export var text_no_stage: String = "откройте сцену этапа RallyStage"
## Строка «трасса не задана».
@export var text_no_route: String = "у трассы нет осевой линии"
