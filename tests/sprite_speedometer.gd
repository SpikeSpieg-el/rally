# godot --headless --path . --script res://tests/sprite_speedometer.gd
extends SceneTree

const HudStyle = preload("res://scripts/data/rally_hud_style.gd")
const AtlasType = preload("res://scripts/ui/hud_sprite_atlas.gd")
const SpeedometerType = preload("res://scripts/ui/sprite_speedometer.gd")
const HudScene = preload("res://scenes/ui/rally_hud.tscn")

var _failures: int = 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: %s" % msg)
		_failures += 1


func _initialize() -> void:
	_test_atlas_sheets()
	_test_speedometer_presets_and_api()
	_test_hud_mode_switching()
	if _failures == 0:
		print("PASS: SpriteSpeedometer, RallyHudSpriteAtlas и переключение режима RallyHUD")
	quit(0 if _failures == 0 else 1)


func _test_atlas_sheets() -> void:
	var sheets := [
		"res://scenes/ui/ui_hud_r1_ru.png",
		"res://scenes/ui/ui спрайты спидометр русс.jpg",
		"res://scenes/ui/ui спрайты спидометр англ.jpg",
	]
	for p in sheets:
		var tex := ResourceLoader.load(p) as Texture2D
		_check(tex != null, "не загружен лист %s" % p)
		if tex == null:
			continue
		var atlas := AtlasType.new()
		var ok := atlas.build(tex, AtlasType.KeyoutMode.AUTO, 2)
		_check(ok and atlas.ready, "атлас не нарезан для %s" % p)
		_check(atlas.big_digits.size() == 10, "%s: ожидалось 10 крупных цифр, получено %d" % [p, atlas.big_digits.size()])
		_check(atlas.small_digits.size() == 10, "%s: ожидалось 10 мелких цифр, получено %d" % [p, atlas.small_digits.size()])
		_check(atlas.gear_items.size() == 5, "%s: ожидалось 5 передач, получено %d" % [p, atlas.gear_items.size()])
		_check(atlas.bar_stepped_segments.size() == 11, "%s: ожидалось 11 сегментов bar1, получено %d" % [p, atlas.bar_stepped_segments.size()])
		_check(atlas.bar_block_segments.size() == 11, "%s: ожидалось 11 сегментов bar2, получено %d" % [p, atlas.bar_block_segments.size()])
		_check(atlas.bar_wide_segments.size() == 4, "%s: ожидалось 4 сегмента bar3, получено %d" % [p, atlas.bar_wide_segments.size()])
		_check(atlas.word_gear.end.x < atlas.unit_kmh.position.x, "%s: word_gear пересекается с unit_kmh" % p)
		_check(atlas.unit_kmh.end.x < atlas.unit_mph.position.x, "%s: unit_kmh пересекается с unit_mph" % p)
		_check(atlas.tint_tex != null, "%s: tint_tex не создан" % p)
		if p.ends_with(".jpg"):
			var img := atlas.tex.get_image()
			_check(img != null and img.get_pixel(0, 0).a < 0.05, "%s: тёмный фон не вырезан в углу (0,0)" % p)


func _test_speedometer_presets_and_api() -> void:
	var sp := SpeedometerType.new()
	sp.custom_minimum_size = Vector2(340, 224)
	sp.size = Vector2(340, 224)
	get_root().add_child(sp)

	sp.apply_preset(SpeedometerType.Preset.COMPACT_MINIMAL)
	_check(sp.preset == SpeedometerType.Preset.COMPACT_MINIMAL, "пресет COMPACT_MINIMAL не применился")
	_check(sp.arc_style == SpeedometerType.ArcRenderStyle.SEGMENTED_BAR_BLOCKS, "COMPACT_MINIMAL должен использовать SEGMENTED_BAR_BLOCKS")

	sp.apply_preset(SpeedometerType.Preset.RETRO_PIXEL)
	_check(sp.draw_backdrop == true and sp.backdrop_corner_radius == 0, "RETRO_PIXEL должен включать пиксельную подложку")

	sp.digit_gap_px = 4.5
	_check(sp.preset == SpeedometerType.Preset.CUSTOM, "ручная правка свойства должна переводить пресет в CUSTOM")

	sp.rpm_smooth_speed = 0.0
	sp.speed_smooth_speed = 0.0
	sp.speed_units = SpeedometerType.SpeedUnits.KMH
	sp.set_telemetry(100.0, 6800.0, 7600.0, "6", true)
	_check(sp.get_display_speed() == 100, "KMH 100 должен давать 100")
	_check(sp.is_redline == true, "redline должен выставляться через set_telemetry")
	sp.speed_units = SpeedometerType.SpeedUnits.MPH
	_check(sp.get_display_speed() == 62, "MPH для 100 км/ч должен давать 62, получено %d" % sp.get_display_speed())

	var st := HudStyle.new()
	st.text_primary_color = Color(0.2, 0.9, 1.0, 1.0)
	sp.set_hud_style(st)
	_check(sp.speed_digit_tint.is_equal_approx(st.text_primary_color), "RallyHudStyle не синхронизировался со SpriteSpeedometer")

	sp.queue_free()


func _test_hud_mode_switching() -> void:
	var hud_node := HudScene.instantiate()
	get_root().add_child(hud_node)
	var mini := hud_node.get_node("MiniMap")
	var throttle := hud_node.get_node("TelemetryPanel/TeleBox/ThrottleBar")
	var timer_lbl := hud_node.get_node("TimerPanel/TimerBox/TimerLabel")
	var timer_spr := hud_node.get_node("TimerPanel/TimerBox/TimerSprite")

	hud_node.call("set_pixel_mode", false)
	_check(mini.get("pixel_mode") == false, "в классическом режиме MiniMap.pixel_mode должен быть false")
	_check(throttle.call("_effective_style") == 0, "в классическом режиме GaugeBar должен оставаться VECTOR")

	var style_res := hud_node.get("hud_style") as HudStyle
	style_res.use_sprite_digits_for_timer = true
	hud_node.call("set_pixel_mode", true)
	_check(mini.get("pixel_mode") == true, "в пиксельном режиме MiniMap.pixel_mode должен стать true")
	_check(throttle.call("_effective_style") == 2, "в пиксельном режиме GaugeBar должен переключиться в PIXEL_SOLID")
	_check(timer_spr.visible == true and timer_lbl.visible == false, "в пиксельном режиме TimerSprite должен заменить TimerLabel")

	hud_node.update_timer_display("01:23.456")
	_check(timer_lbl.text == "01:23.456" and timer_spr.text == "01:23.456", "update_timer_display должен синхронизировать оба таймера")

	hud_node.call("set_pixel_mode", false)
	_check(mini.get("pixel_mode") == false and timer_lbl.visible == true, "возврат в классический режим должен восстанавливать исходные панели")
	hud_node.queue_free()
