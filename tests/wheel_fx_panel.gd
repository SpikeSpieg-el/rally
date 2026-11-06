# godot --headless --path . --script res://tests/wheel_fx_panel.gd
#
# Панель «Колёса, пыль и грязь» не должна быть отдельным списком полей, который
# забывают обновлять. Тест проверяет, что она строится из инспектора профилей,
# показывает все рабочие поля и умеет сбрасываться к заводскому .tres.
extends SceneTree

const FxPanel = preload("res://scripts/ui/wheel_fx_settings.gd")
const FxProfile = preload("res://scripts/data/rally_fx_profile.gd")
const FX_PATH := "res://data/stage/default_fx_profile.tres"

var failures := 0


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fx := ResourceLoader.load(FX_PATH) as FxProfile
	check(fx != null, "профиль эффектов загружается")
	if fx == null:
		quit(1)
		return
	check(fx.fx_intensity > 1.5, "сила эффектов по умолчанию заметно выше прежней")
	check(fx.surface_fx_profiles.size() == 5, "у каждого покрытия свой профиль")
	var panel := FxPanel.new()
	# Не трогаем настоящий user:// в тесте: пишем во временный файл.
	panel.save_path = "user://wheel_fx_panel_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(panel.save_path))
	root.add_child(panel)
	panel.open_with(fx)
	check(panel.visible, "панель открывается по кнопке паузы")
	# Каждое экспортируемое число/цвет/вектор профиля должно попасть на панель.
	var missing: Array[String] = []
	for property in fx.get_property_list():
		if int(property.get("usage", 0)) & PROPERTY_USAGE_EDITOR == 0:
			continue
		var field := String(property["name"])
		if field in FxPanel.HIDDEN_FIELDS or field.begins_with("_") or field == "script":
			continue
		if int(property.get("hint", 0)) == PROPERTY_HINT_ENUM:
			continue
		var shown := false
		for control in panel._controls:
			if String(control["field"]) == field:
				shown = true
				break
		if not shown:
			missing.append(field)
	check(missing.is_empty(), "все поля профиля видны на панели: " + str(missing))
	# Правка слайдера применяется к живому ресурсу без перезапуска заезда.
	panel._commit("fx_intensity", 3.0, func(field: String, value: Variant) -> void:
		fx.set(field, value)
	)
	check(is_equal_approx(fx.fx_intensity, 3.0), "правка сразу меняет живой профиль")
	# Сброс возвращает заводские значения из .tres, а не «нули».
	fx.fx_intensity = 0.5
	fx.surface_fx_profiles[0].amount_scale = 0.2
	panel.reset_to_defaults()
	var fresh := ResourceLoader.load(FX_PATH) as FxProfile
	check(
		is_equal_approx(fx.fx_intensity, fresh.fx_intensity),
		"сброс восстанавливает силу эффектов из заводского ресурса"
	)
	var target_scale: float = fx.surface_fx_profiles[0].amount_scale
	var fresh_scale: float = fresh.surface_fx_profiles[0].amount_scale
	check(
		is_equal_approx(target_scale, fresh_scale),
		"сброс восстанавливает и профили покрытий"
	)
	# Подписи — русские и говорящие, а не голые имена полей.
	check(
		FxPanel._human_name("foam_amount") != "foam_amount",
		"у полей есть понятные подписи"
	)
	check(FxPanel._human_name("body_spread").length() > 3, "новые поля тоже подписаны")
	# Ни одно рабочее поле не должно подписываться «сырым» именем переменной.
	var raw: Array[String] = []
	for property in fx.get_property_list():
		if int(property.get("usage", 0)) & PROPERTY_USAGE_EDITOR == 0:
			continue
		var field := String(property["name"])
		if field in FxPanel.HIDDEN_FIELDS or field.begins_with("_") or field == "script":
			continue
		if int(property.get("type")) not in [
			TYPE_BOOL, TYPE_COLOR, TYPE_FLOAT, TYPE_INT, TYPE_VECTOR3, TYPE_AABB
		]:
			continue
		if int(property.get("hint", 0)) == PROPERTY_HINT_ENUM:
			continue
		if FxPanel._human_name(field) == field:
			raw.append(field)
	check(raw.is_empty(), "у всех полей русские подписи, без «сырых» имён: " + str(raw))
	panel.close()
	check(panel._closing, "закрытие начинается сразу после «Готово»")
	# Окно гаснет плавно: ждём конец анимации, а не проверяем кадр закрытия.
	await create_timer(0.3, true).timeout
	check(not panel.visible, "панель закрывается кнопкой «Готово»")
	# Сохранение/загрузка: правка, перезапуск (новый объект) и чтение из файла.
	var saved_intensity := fx.fx_intensity
	panel._save()
	fx.fx_intensity = 0.25
	FxPanel.apply_saved(fx, panel.save_path)
	check(
		is_equal_approx(fx.fx_intensity, saved_intensity),
		"сохранённые настройки подхватываются при следующем заезде"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(panel.save_path))
	root.remove_child(panel)
	panel.free()
	if failures == 0:
		print("PASS: панель эффектов колёс строится из ресурса и правит живой профиль")
	quit(0 if failures == 0 else 1)
