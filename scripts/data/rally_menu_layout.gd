## Тексты и поведение главного меню и гаража: подписи, подсказки, превью.
##
## Всё, что раньше было строкой в коде меню, теперь поле этого ресурса.
## Файл: res://data/ui/default_menu_layout.tres. Меню можно переопределить
## полем `menu_layout` у корня MainMenu / GarageMenu.
@tool
class_name RallyMenuLayout
extends Resource

@export_group("Главное меню")
## Заголовки берутся из RallyGameConfig, а тут — только подписи блоков.
@export var tracks_heading: String = "ВЫБОР ТРАССЫ"
@export var setups_heading: String = "МАШИНА"
@export var seed_heading: String = "ЖИВАЯ ЛЕНТА · СИД ГЕНЕРАЦИИ"
@export var weather_heading: String = "ПОГОДА"
@export var profile_heading: String = "ХАРАКТЕР ТРАССЫ"
@export var time_heading: String = "ВРЕМЯ СУТОК"
## Подписи вариантов времени суток: как на трассе, день, ночь (порядок — как в GameState).
@export var time_labels: PackedStringArray = PackedStringArray(["КАК НА ТРАССЕ", "ДЕНЬ", "НОЧЬ"])
@export var time_tips: PackedStringArray = PackedStringArray([
	"Время суток задаёт трасса: ночные лесные этапы — ночью, остальные — днём.",
	"Дневной свет и небо, даже если трасса ночная.",
	"Ночное небо, слабое солнце и тёмное окружение, даже если трасса дневная.",
])
@export var seed_hint: String = "Сид сохраняется в user://rally_conditions.cfg"
@export var apply_button: String = "ПРИМЕНИТЬ"
@export var reroll_button: String = "ПЕРЕГЕНЕРИРОВАТЬ"
@export var copy_button: String = "КОПИЯ"
@export var seed_apply_tip: String = "Собрать трассу по введённому сиду"
@export var seed_reroll_tip: String = "Новая случайная трасса. Сид сохраняется — карту всегда можно вернуть."
@export var seed_copy_tip: String = "Скопировать сид в буфер обмена"
@export var seed_field_tip: String = "Введите сид и нажмите «ПРИМЕНИТЬ» — трасса соберётся ровно по нему."
## Подписи кнопок в главном меню (тексты берутся из сцены, если поле пустое).
@export var start_button_text: String = "НА СТАРТ"
@export var controls_button_text: String = "УПРАВЛЕНИЕ"
@export var quit_button_text: String = "ВЫХОД"
## Горячие клавиши быстрого выбора и текст подсказки внизу.
@export var track_hotkey_count: int = 5
@export var footer_keyboard: String = "F1-F5 — трасса  •  F6 — погода  •  F7 — характер трассы  •  F8 — новый сид «Живой ленты»  •  F9 — время суток  •  N — трек  •  M — радио.  Выбор сохраняется между заездами."
@export var footer_gamepad: String = "Геймпад: [%s/%s] трасса  •  [%s] гараж  •  [%s] выход  •  радио — кнопки карточки  •  погода и сид — мышью"
@export var hotkey_weather: Key = KEY_F6
@export var hotkey_profile: Key = KEY_F7
@export var hotkey_reroll: Key = KEY_F8
@export var hotkey_time: Key = KEY_F9
## Формат строки кнопки трассы: F-клавиша и название.
@export var track_button_format: String = "F%d   %s"
## Сообщения о сиде (форматы — как в GDScript, «%d» подставит число).
@export var seed_status_new: String = "Новый сид %d сохранён — трасса переплетается"
@export var seed_status_invalid: String = "Сид — целое число от 1 до 999 999 999"
@export var seed_status_same: String = "Этот сид уже активен"
@export var seed_status_applied: String = "Сид %d сохранён — эта трасса соберётся заново"
@export var seed_status_copied: String = "Сид %d скопирован"
@export var seed_min_value: int = 1
@export var seed_max_value: int = 999999999
## Подпись лучшего времени на кнопке трассы.
@export var best_time_label: String = "ЛУЧШЕЕ ВРЕМЯ%s:  %s"
@export var best_time_empty: String = "ЛУЧШЕЕ ВРЕМЯ:  —"

@export_group("Гараж")
@export var garage_turntable_speed: float = 0.16
@export var garage_status_saved: String = "Все открытые пресеты сохранены."
@export var garage_status_unsaved: String = "Есть несохранённые изменения. При смене пресета они будут отменены."
@export var garage_status_ready: String = "Сохраните изменения или нажмите «На старт»."
@export var garage_status_reset: String = "Пресет сброшен. Сохраните изменения или начните заезд."
@export var garage_status_save_failed: String = "Не удалось сохранить. Проверьте доступ к файлу настроек."
@export var garage_status_storage_missing: String = "Не удалось сохранить: хранилище недоступно."
@export var garage_preset_prefix: String = "БАЗОВЫЙ ПРЕСЕТ: "
## Радиус колеса эталонной модели (для масштаба колёс в витрине), м.
@export var garage_reference_tire_radius: float = 0.438
@export var garage_retro_shrink: int = 3
@export_range(180, 720, 1) var garage_retro_resolution_y: int = 270
@export_range(0.0, 1.0, 0.01) var garage_retro_strength: float = 1.0
@export_range(0.0, 0.02, 0.001) var garage_mouse_rotate_speed: float = 0.008
@export_range(10.0, 90.0, 1.0) var garage_preview_fov_min: float = 24.0
@export_range(10.0, 90.0, 1.0) var garage_preview_fov_max: float = 60.0
@export_range(1.0, 30.0, 0.5) var garage_preview_fov_step: float = 2.0
