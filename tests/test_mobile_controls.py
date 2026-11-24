"""Mobile input and low-power Web configuration checks without Godot runtime."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


class MobileControlsTest(unittest.TestCase):
    def test_touch_controls_are_in_the_shared_hud(self):
        scene = read("scenes/ui/rally_hud.tscn")
        self.assertIn('path="res://scripts/ui/touch_controls.gd" id="13_touch_controls"', scene)
        self.assertIn('[node name="TouchControls" type="Control" parent="."]', scene)
        self.assertIn('script = ExtResource("13_touch_controls")', scene)

    def test_controls_support_multitouch_drag_and_existing_actions(self):
        controls = read("scripts/ui/touch_controls.gd")
        for token in (
            "signal pause_requested",
            "InputEventScreenTouch",
            "InputEventScreenDrag",
            "_touch_actions",
            "_action_holds",
            "Input.action_press(action, 1.0)",
            "Input.action_release(action)",
            '"steer_left"',
            '"steer_right"',
            '"throttle"',
            '"brake"',
            '"handbrake"',
            '"pause"',
            "NOTIFICATION_APPLICATION_FOCUS_OUT",
        ):
            self.assertIn(token, controls)

    def test_controls_hide_for_pause_results_and_input_settings(self):
        controls = read("scripts/ui/touch_controls.gd")
        for panel in ('"PausePanel"', '"ResultsPanel"', '"InputSettings"'):
            self.assertIn(panel, controls)
        self.assertIn("get_tree().paused", controls)
        self.assertIn("_release_all()", controls)

    def test_both_modes_connect_touch_pause(self):
        for rel in ("scripts/rally_stage.gd", "scripts/arcade/arcade_stage.gd"):
            stage = read(rel)
            self.assertIn("TouchControls", stage)
            self.assertIn('has_signal("pause_requested")', stage)
            self.assertIn('Callable(self, "_on_touch_pause_requested")', stage)
            self.assertIn("func _on_touch_pause_requested()", stage)

    def test_web_and_mobile_use_reduced_rendering_cost(self):
        settings = read("scripts/ui/game_settings.gd")
        self.assertIn('OS.has_feature("web") or OS.has_feature("mobile")', settings)
        self.assertIn("Engine.physics_ticks_per_second = 60", settings)
        self.assertIn("viewport.scaling_3d_scale = WEB_DEFAULT_SCALE", settings)
        self.assertIn("const WEB_DEFAULT_SCALE := 0.72", settings)
        self.assertIn("disable_low_power_light_shadows", settings)

        for rel in ("scripts/rally_stage.gd", "scripts/arcade/arcade_stage.gd"):
            stage = read(rel)
            self.assertIn("env.glow_enabled = not low_power_render", stage)
            self.assertIn("and not low_power_render", stage)
            self.assertIn("volumetric and not low_power_render", stage)

        shader = read("shaders/speed_fx.gdshader")
        self.assertIn("uniform bool low_power_mode = false", shader)
        self.assertIn("if (!low_power_mode && mask > 0.001)", shader)

    def test_touch_buttons_are_larger_and_hit_wider_than_they_look(self):
        controls = read("scripts/ui/touch_controls.gd")
        self.assertIn("const MAIN_SIDE_RATIO := 0.24", controls)
        self.assertIn("const MAIN_SIDE_MIN := 64.0", controls)
        # Прежняя доля 0.18 давала кнопки около 65 px на телефоне: слишком мало.
        self.assertNotIn("short_side * 0.18", controls)
        self.assertIn('"hit": rect.grow(pad)', controls)
        self.assertIn('var hit: Rect2 = zone["hit"]', controls)

    def test_touch_reverse_and_gears_exist_without_keyboard(self):
        controls = read("scripts/ui/touch_controls.gd")
        # Задний ход в автомате включается только через shift_down (клавиша Q).
        # На телефоне без кнопки сюда не попасть — поэтому R и D есть на экране.
        self.assertIn('"shift_down", "R" if automatic else ""', controls)
        self.assertIn('"shift_up", "D" if automatic else ""', controls)
        self.assertIn('Input.action_press(action, 1.0)', controls)
        self.assertIn("TRANSMISSION_MANUAL_CLUTCH", controls)
        self.assertIn('"clutch", "СЦЕП"', controls)

    def test_touch_layout_rebuilds_when_transmission_changes(self):
        controls = read("scripts/ui/touch_controls.gd")
        self.assertIn('get_node_or_null("/root/RallyGame")', controls)
        self.assertIn('_game.get("transmission_index")', controls)
        self.assertIn("if key != _layout_key:", controls)

    def test_touch_icons_do_not_depend_on_font_glyphs(self):
        controls = read("scripts/ui/touch_controls.gd")
        self.assertIn("func _draw_icon(", controls)
        self.assertIn("draw_colored_polygon", controls)
        self.assertNotIn('"◀"', controls)
        self.assertNotIn('"▶"', controls)

    def test_web_graphics_settings_apply_at_startup_and_work(self):
        settings = read("scripts/ui/game_settings.gd")
        # Раньше apply_display вызывался только при правке в меню, и после
        # перезагрузки страницы сохранённые настройки не действовали.
        platform = settings.split("static func apply_platform_defaults", 1)[1].split("static func disable_low_power_light_shadows", 1)[0]
        self.assertIn("apply_display(viewport)", platform)
        self.assertIn("viewport.msaa_3d = msaa_index()", settings)
        self.assertNotIn("viewport.msaa_3d = 0 if low_power", settings)
        self.assertNotIn("minf(scaling_scale(), 0.72)", settings)
        self.assertNotIn("_msaa.disabled = true", settings)
        self.assertNotIn("_shadows.disabled = true", settings)
        self.assertNotIn("_scaling.disabled = true", settings)
        # Строки, которыми управляет браузер, прячем, а не оставляем серыми.
        for row in ("_window_mode.get_parent().visible = false",
                    "_resolution.get_parent().visible = false",
                    "_vsync.get_parent().visible = false",
                    "_scaling.get_parent().visible = false",
                    "_shadows.get_parent().visible = false"):
            self.assertIn(row, settings)

    def test_web_render_governor_lowers_scale_only_on_low_power_runtime(self):
        governor = read("scripts/ui/web_render_governor.gd")
        self.assertIn("set_process(GameSettingsType.is_low_power_runtime())", governor)
        self.assertIn("viewport.scaling_3d_scale = target", governor)
        self.assertIn("GameSettingsType.WEB_MIN_SCALE", governor)
        self.assertIn("const LOW_FPS: float = 30.0", governor)
        self.assertIn("const HIGH_FPS: float = 50.0", governor)
        game_state = read("scripts/game_state.gd")
        self.assertIn('governor.name = "WebRenderGovernor"', game_state)
        start = game_state.index('func _ready() -> void:')
        block = game_state[start:game_state.index("load_config()", start)]
        self.assertIn("if GameSettingsType.is_low_power_runtime():", block)

    def test_web_scenery_density_is_reduced_only_in_browser(self):
        stage = read("scripts/rally_stage.gd")
        self.assertIn("const WEB_SCENERY_DENSITY_SCALE := 0.6", stage)
        self.assertIn("density *= WEB_SCENERY_DENSITY_SCALE", stage)
        guard = stage.index("density *= WEB_SCENERY_DENSITY_SCALE")
        self.assertIn("if GameSettings.is_low_power_runtime():", stage[guard - 80:guard])

    def test_emulated_touch_mouse_never_turns_the_camera(self):
        # Godot шлёт касания как мышь с device == DEVICE_ID_EMULATION.
        # Без этой проверки палец на кнопке крутил камеру (жалоба на телефоне).
        car = read("scripts/rally_car.gd")
        start = car.index("func _unhandled_input(event: InputEvent) -> void:")
        body = car[start:car.index("\n\n\nfunc ", start)]
        self.assertIn("event.device == InputEvent.DEVICE_ID_EMULATION", body)
        self.assertLess(
            body.index("DEVICE_ID_EMULATION"),
            body.index("InputEventMouseMotion"),
        )

    def test_web_buttons_have_no_small_upper_clamp(self):
        controls = read("scripts/ui/touch_controls.gd")
        self.assertIn("const WEB_MAIN_SIDE_RATIO := 0.26", controls)
        self.assertIn("const WEB_MAIN_SIDE_MIN := 200.0", controls)
        self.assertIn("const WEB_MAIN_SIDE_MAX := 340.0", controls)
        self.assertIn("func _main_side(short_side: float, portrait: bool = false) -> float:", controls)
        self.assertIn("if GameSettings.is_low_power_runtime():", controls)
        # На ПК размеры прежние: отдельная ветка с MAIN_SIDE_MAX.
        self.assertIn("return clampf(short_side * MAIN_SIDE_RATIO, MAIN_SIDE_MIN, MAIN_SIDE_MAX)", controls)

    def test_portrait_buttons_fit_four_in_a_row(self):
        # Раньше вычитались зазоры только двух соседей, хотя в нижнем ряду
        # четыре кнопки — «руль вправо» наезжал на «тормоз» в портрете.
        controls = read("scripts/ui/touch_controls.gd")
        self.assertIn("const PORTRAIT_SIDE_RATIO := 0.235", controls)
        self.assertIn("(size.x - 2.0 * margin - 3.0 * gap) * 0.25", controls)
        self.assertIn("func content_top() -> float:", controls)
        # Поворот телефона пересобирает зоны под новую ширину.
        self.assertIn("viewport.size_changed.connect(_rebuild_zones)", controls)

    def test_portrait_layout_and_theme_scale_exist(self):
        layout = read("scripts/ui/rally_screen_layout.gd")
        for token in (
            "static func is_portrait(",
            "static func ui_scale(",
            "const UI_SCALE_LANDSCAPE := 1.15",
            "const UI_SCALE_PORTRAIT := 1.05",
        ):
            self.assertIn(token, layout)
        # Масштаб — это числа шрифтов/отступов, а не Control.scale.
        theme = read("scripts/data/rally_ui_theme.gd")
        self.assertIn("var ui_scale: float = 1.0", theme)
        self.assertIn("func scaled_font(base_size: int) -> int:", theme)
        self.assertNotIn("scale = Vector2(", theme)
        hud = read("scripts/ui/rally_hud.gd")
        self.assertIn("func _apply_portrait_layout(", hud)
        self.assertIn("func _apply_orientation() -> void:", hud)
        self.assertIn("_restore_scene_layout()", hud)

    def test_camera_widens_in_portrait(self):
        car = read("scripts/rally_car.gd")
        self.assertIn("func _portrait_fov_bonus() -> float:", car)
        self.assertIn("var portrait_fov_bonus: float = 12.0", car)
        self.assertIn("+ _portrait_fov_bonus()", car)
        self.assertIn("func _portrait_distance_scale() -> float:", car)

    def test_web_cover_density_is_halved_only_in_browser(self):
        stage = read("scripts/rally_stage.gd")
        self.assertIn("const WEB_COVER_DENSITY_SCALE := 0.5", stage)
        self.assertIn("cover_density *= WEB_COVER_DENSITY_SCALE", stage)
        self.assertIn("if cover_pass == 0 and GameSettings.is_low_power_runtime():", stage)

    def test_fps_counter_shows_draw_calls_only_in_browser(self):
        fps = read("scripts/ui/fps_label.gd")
        self.assertIn("show_render_stats = GameSettingsType.is_low_power_runtime()", fps)
        self.assertIn("RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME", fps)
        self.assertIn('"%d FPS · %d dc · %d%%"', fps)

    def test_web_hidpi_is_off_only_for_the_browser(self):
        project = read("project.godot")
        self.assertIn("window/dpi/allow_hidpi.web=false", project)
        # Базовое значение не трогаем: ПК остаётся с HiDPI.
        self.assertNotIn("window/dpi/allow_hidpi=false", project)

    def test_web_hides_anisotropy_row_that_has_no_effect(self):
        settings = read("scripts/ui/game_settings.gd")
        self.assertIn("_aniso.get_parent().visible = false", settings)

    def test_fps_counter_shows_current_3d_scale(self):
        fps = read("scripts/ui/fps_label.gd")
        self.assertIn("get_viewport().scaling_3d_scale", fps)

    def test_normal_rally_hud_updates_at_a_bounded_rate(self):
        stage = read("scripts/rally_stage.gd")
        self.assertIn("const HUD_REFRESH: float = 0.08", stage)
        self.assertIn("if _hud_clock >= HUD_REFRESH:", stage)
        self.assertIn("_update_hud()", stage)

    def test_portrait_hud_reserves_room_for_the_thumb_row(self):
        # Спидометр 210 px и кнопки газа делили низ экрана: панель ложилась
        # под пальцы. Нижняя полоса считается от `content_top()`, а не от
        # доли экрана «на глаз».
        hud = read("scripts/ui/rally_hud.gd")
        self.assertIn("func _controls_top(canvas: Vector2) -> float:", hud)
        self.assertIn('controls.has_method("content_top")', hud)
        self.assertIn("controls_top - margin", hud)
        self.assertIn("var speed_height: float = clampf(maxf(portrait_speed_height, speed_min.y), 120.0, band_height)", hud)
        # Панель-контейнер уважает свой минимум, иначе Godot вырастит её на пальцы.
        self.assertIn("speed_panel.get_combined_minimum_size()", hud)
        self.assertIn("@export var touch_controls_path: NodePath = NodePath(\"TouchControls\")", hud)
        controls = read("scripts/ui/touch_controls.gd")
        self.assertIn("signal layout_changed", controls)
        self.assertIn("layout_changed.emit()", controls)
        self.assertIn('controls.connect("layout_changed", Callable(self, "_apply_orientation"))', hud)

    def test_portrait_layout_reacts_to_a_new_band_without_a_rotate(self):
        # Зоны кнопок собираются отложенно; HUD должен переставиться, даже
        # если ориентация и канва не менялись.
        hud = read("scripts/ui/rally_hud.gd")
        self.assertIn("var _applied_controls_top: float = -1.0", hud)
        self.assertIn("var same_band: bool = absf(controls_top - _applied_controls_top) < 1.0", hud)

    def test_ui_scale_does_not_compound_across_rotations(self):
        # Поворот альбом→портрет→альбом раньше умножал уже увеличенный шрифт.
        hud = read("scripts/ui/rally_hud.gd")
        self.assertIn("var _base_font_sizes: Dictionary = {}", hud)
        self.assertIn("func _scale_font_size(ctrl: Control, amount: float) -> void:", hud)
        # Снимать оверрайд нельзя: размер из .tscn хранится в нём же.
        self.assertNotIn('ctrl.remove_theme_font_size_override("font_size")', hud)
        self.assertIn('ctrl.add_theme_font_size_override("font_size", maxi(8, roundi(float(base_size) * amount)))', hud)
        self.assertIn("viewport.size_changed.connect(_on_viewport_resized)", hud)

    def test_portrait_modals_fit_the_tall_canvas(self):
        hud = read("scripts/ui/rally_hud.gd")
        self.assertIn("func _place_modal(ctrl: Control, canvas: Vector2, margin: float, height_ratio: float) -> void:", hud)
        self.assertIn("_place_modal(get_node_or_null(pause_panel_path) as Control, canvas, margin, 0.62)", hud)
        self.assertIn("_place_modal(get_node_or_null(results_panel_path) as Control, canvas, margin, 0.45)", hud)
        # Модалка портрета тянется по ширине: 620 px — это треть узкой канвы.
        self.assertIn("maxf(320.0, canvas.x - margin * 2.0)", hud)

    def test_low_power_render_trims_are_wired(self):
        car = read("scripts/rally_car.gd")
        self.assertIn("const LOW_POWER_FX_AMOUNT_SCALE := 0.35", car)
        self.assertIn("func _sync_interior_visibility() -> void:", car)
        self.assertIn("const INTERIOR_LOW_POWER := true", car)
        stage = read("scripts/rally_stage.gd")
        self.assertIn("const WEB_SCENERY_RANGE_SCALE := 0.72", stage)
        self.assertIn("const WEB_SCENERY_RANGE_SMALL_SCALE := 0.75", stage)
        self.assertIn("func _scenery_range(", stage)
        streamer = read("scripts/world_streamer.gd")
        self.assertIn("const MOBILE_REPLAN_DISTANCE := 48.0", streamer)
        self.assertIn("const MOBILE_REPLAN_SECONDS := 1.25", streamer)
        hud_speed = read("scripts/ui/sprite_speedometer.gd")
        self.assertIn("LOW_POWER_REDRAW_HZ", hud_speed)
        self.assertIn("func _low_power_redraw_enabled() -> bool:", hud_speed)
        radio = read("scripts/ui/rally_radio_card.gd")
        self.assertIn("LOW_POWER_POLL_INTERVAL", radio)
        governor = read("scripts/ui/web_render_governor.gd")
        self.assertIn("CRITICAL_FPS", governor)
        self.assertIn("func _trim_expensive_extras() -> void:", governor)
        self.assertIn("Engine.physics_ticks_per_second = 45", governor)
        title = read("scripts/title_screen.gd")
        self.assertIn("LOW_POWER_PREVIEW_FPS", title)
        self.assertIn("OS.has_feature(\"web\")", title)

    def test_expensive_draw_caches_are_reused(self):
        minimap = read("scripts/ui/mini_map.gd")
        self.assertIn("func _panel_box() -> StyleBoxFlat:", minimap)
        self.assertIn("_passed_index", minimap)
        surface = read("scripts/surface_effects.gd")
        self.assertIn("const LOW_POWER_AMOUNT_SCALE := 0.4", surface)


if __name__ == "__main__":
    unittest.main()
