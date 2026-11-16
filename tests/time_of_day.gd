# Выбор времени суток в меню: «как на трассе», «утро», «день», «вечер», «ночь».
# godot --headless --path . --script res://tests/time_of_day.gd
#
# Проверяет чистую логику выбора (без мира и GPU): явный выбор главнее поля
# погоды, «как на трассе» оставляет решение за погодой и трассой, а вечер и
# ночь включают тёмное небо и фары (утро и день — дневное небо).
extends SceneTree

const WeatherType = preload("res://scripts/data/rally_weather_config.gd")

var failures := 0


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	check(
		WeatherType.resolve_night_choice(WeatherType.TimeOfDay.KEEP, null, true),
		"«как на трассе» без погоды оставляет ночную трассу ночной"
	)
	check(
		not WeatherType.resolve_night_choice(WeatherType.TimeOfDay.KEEP, null, false),
		"«как на трассе» без погоды оставляет дневную трассу днём"
	)
	check(
		not WeatherType.resolve_night_choice(WeatherType.TimeOfDay.MORNING, null, true),
		"«утро» переводит ночную трассу на дневное/рассветное небо"
	)
	check(
		not WeatherType.resolve_night_choice(WeatherType.TimeOfDay.DAY, null, true),
		"«день» делает ночную трассу дневной"
	)
	check(
		WeatherType.resolve_night_choice(WeatherType.TimeOfDay.EVENING, null, false),
		"«вечер» включает сумеречное небо и фары на дневной трассе"
	)
	check(
		WeatherType.resolve_night_choice(WeatherType.TimeOfDay.NIGHT, null, false),
		"«ночь» делает дневную трассу ночной"
	)
	check(
		WeatherType.resolve_time_choice(WeatherType.TimeOfDay.MORNING, null, true) == WeatherType.TimeOfDay.MORNING,
		"«утро» сохраняет режим MORNING"
	)
	check(
		WeatherType.resolve_time_choice(WeatherType.TimeOfDay.EVENING, null, false) == WeatherType.TimeOfDay.EVENING,
		"«вечер» сохраняет режим EVENING"
	)
	check(
		WeatherType.explicit_time_choice(WeatherType.TimeOfDay.KEEP, null) == WeatherType.TimeOfDay.KEEP,
		"«как на трассе» без погоды не задаёт явный пресет"
	)
	var weather := WeatherType.new()
	weather.time_of_day = WeatherType.TimeOfDay.DAY
	check(
		not WeatherType.resolve_night_choice(WeatherType.TimeOfDay.KEEP, weather, true),
		"поле времени в погоде работает, когда в меню выбрано «как на трассе»"
	)
	check(
		WeatherType.explicit_time_choice(WeatherType.TimeOfDay.KEEP, weather) == WeatherType.TimeOfDay.DAY,
		"явное время из погоды пробрасывается при «как на трассе»"
	)
	check(
		WeatherType.resolve_night_choice(WeatherType.TimeOfDay.NIGHT, weather, false),
		"явный выбор «ночь» главнее поля времени в погоде"
	)
	check(
		WeatherType.explicit_time_choice(WeatherType.TimeOfDay.EVENING, weather) == WeatherType.TimeOfDay.EVENING,
		"явный выбор «вечер» главнее поля времени в погоде"
	)
	if failures == 0:
		print("PASS: время суток — как на трассе, утро, день, вечер, ночь")
	quit(0 if failures == 0 else 1)
