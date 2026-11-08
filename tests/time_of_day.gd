# Выбор времени суток в меню: «как на трассе», «день», «ночь».
# godot --headless --path . --script res://tests/time_of_day.gd
#
# Проверяет чистую логику выбора (без мира и GPU): явный выбор главнее поля
# погоды, а «как на трассе» оставляет решение за погодой и трассой.
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
		WeatherType.resolve_night_choice(0, null, true),
		"«как на трассе» без погоды оставляет ночную трассу ночной"
	)
	check(
		not WeatherType.resolve_night_choice(0, null, false),
		"«как на трассе» без погоды оставляет дневную трассу днём"
	)
	check(
		not WeatherType.resolve_night_choice(1, null, true),
		"«день» делает ночную трассу дневной"
	)
	check(
		WeatherType.resolve_night_choice(2, null, false),
		"«ночь» делает дневную трассу ночной"
	)
	var weather := WeatherType.new()
	weather.time_of_day = WeatherType.TimeOfDay.DAY
	check(
		not WeatherType.resolve_night_choice(0, weather, true),
		"поле времени в погоде работает, когда в меню выбрано «как на трассе»"
	)
	check(
		WeatherType.resolve_night_choice(2, weather, false),
		"явный выбор «ночь» главнее поля времени в погоде"
	)
	if failures == 0:
		print("PASS: время суток — как на трассе, день, ночь")
	quit(0 if failures == 0 else 1)
