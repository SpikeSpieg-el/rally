"""Статические контракты ощущения скорости без запуска Godot.

Главное правило: ощущение скорости не строится на тряске камеры.
Высокочастотная дрожь (10–20 Гц) укачивает и читается как баг — вместо неё
медленный занос в повороте, мягкая инерция дистанции, придорожный поток
частиц, ветер и лёгкое растяжение картинки от центра к краям.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


class NoCameraShakeTest(unittest.TestCase):
    """Тряски в отдаче камеры быть не должно ни в коде, ни в конфиге."""

    def test_no_high_frequency_noise_in_car(self):
        car = read("scripts/rally_car.gd")
        for forbidden in (
            "camera_trauma",
            "_juice_noise",
            "_juice_shake_offset",
            "_juice_shake_rotation",
            "road_shake_",
            "shake_frequency_spread",
            "shake_phase_offset",
            "trauma_amplitude",
            "trauma_decay",
        ):
            self.assertNotIn(forbidden, car, f"в камере остался блок тряски: {forbidden}")

    def test_feel_config_has_no_shake_knobs(self):
        feel = read("scripts/data/rally_car_feel_config.gd")
        for forbidden in (
            "road_shake_start_kmh",
            "road_shake_amplitude",
            "road_shake_frequency",
            "trauma_decay",
            "trauma_amplitude",
            "trauma_frequency",
            "trauma_rotation_deg",
            "shift_trauma",
            "shift_fov_kick",
            "impact_trauma_per_mps2",
            "suspension_impact_trauma",
            "landing_trauma_per_mps",
        ):
            self.assertNotIn(forbidden, feel, f"в конфиге остался ползунок тряски: {forbidden}")

    def test_shift_does_not_kick_the_camera(self):
        car = read("scripts/rally_car.gd")
        self.assertNotIn("shift_pitch_deg", car)
        self.assertNotIn("_juice_shift_kick", car)


class SpeedFeelDesignTest(unittest.TestCase):
    """Новая отдача: медленный занос, крен, инерция и «дыхание» ниже 1 Гц."""

    def test_feel_tuning_is_data_driven(self):
        feel = read("scripts/data/rally_car_feel_config.gd")
        for field in (
            "speed_feel_strength",
            "chase_feel_scale",
            "cockpit_feel_scale",
            "corner_lean_start_kmh",
            "corner_lean_full_kmh",
            "corner_lean_max_deg",
            "corner_lean_rate_share",
            "corner_lean_response",
            "corner_roll_max_deg",
            "corner_roll_response",
            "corner_lean_invert",
            "speed_pull_gain",
            "speed_pull_limit",
            "speed_pull_response",
            "speed_accel_limit",
            "speed_accel_response",
            "high_speed_bob_amplitude",
            "high_speed_bob_hz",
            "vertical_inertia_gain",
            "vertical_inertia_limit",
            "fov_speed_ease",
        ):
            self.assertIn(f"var {field}:", feel, f"нет поля успокоенной отдачи: {field}")

    def test_bob_is_slow_wave_not_shake(self):
        feel = read("scripts/data/rally_car_feel_config.gd")
        # Частота «дыхания» физически не может быть дрожью: это доли герца.
        self.assertIn('"suffix:Гц") var high_speed_bob_hz: float = 0.7', feel)
        car = read("scripts/rally_car.gd")
        self.assertIn("Sway.float_bob(", car)
        # Поток и занос идут через чистую математику, а не через шум.
        sway = read("scripts/effects/rally_speed_sway.gd")
        self.assertIn("static func corner_lean(", sway)
        self.assertIn("static func lean_angle(", sway)
        self.assertIn("static func float_bob(", sway)
        self.assertIn("static func vertical_inertia(", sway)
        self.assertIn("static func speed_fov_factor(", sway)
        self.assertIn("static func speed_weight(", sway)

    def test_lean_and_roll_are_applied_without_randomness(self):
        car = read("scripts/rally_car.gd")
        self.assertIn("func _update_speed_feel(delta: float) -> void:", car)
        self.assertIn("func _apply_chase_feel(active: bool = true) -> void:", car)
        self.assertIn("func _reset_camera_feel() -> void:", car)
        self.assertIn("func _chase_feel_scale() -> float:", car)
        self.assertIn("func _cockpit_feel_scale() -> float:", car)
        self.assertIn("active_camera.rotate_object_local(Vector3.UP, _feel_lean * feel)", car)
        self.assertIn("active_camera.rotate_object_local(Vector3.FORWARD, _feel_roll * feel)", car)
        # Кабина получает ту же отдачу, но с собственной силой.
        self.assertIn("active_camera.rotate_object_local(Vector3.UP, _feel_lean * cockpit_feel)", car)
        self.assertIn("active_camera.rotate_object_local(Vector3.FORWARD, _feel_roll * cockpit_feel)", car)
        # Ни одной выборки шума/случайности в отдаче.
        self.assertNotIn("randf", car.split("func _update_speed_feel", 1)[1].split("func base_camera_distance", 1)[0])

    def test_hood_stays_calm(self):
        car = read("scripts/rally_car.gd")
        update_block = car.split("func _update_cameras(delta: float) -> void:", 1)[1].split("func _update_action_camera", 1)[0]
        hood_block = update_block.split("CameraMode.HOOD:", 1)[1].split("CameraMode.COCKPIT_1ST:", 1)[0]
        self.assertIn("active_camera.global_transform = cam_hood.global_transform", hood_block)
        for forbidden in ("_feel_", "g_force_offset", "_speed_bob_pitch"):
            self.assertNotIn(forbidden, hood_block)

    def test_reset_clears_feel_state(self):
        car = read("scripts/rally_car.gd")
        reset = car.split("func _reset_camera_feel() -> void:", 1)[1].split("\nfunc ", 1)[0]
        for field in ("_feel_local_accel", "_feel_yaw_rate_deg", "_feel_lean", "_feel_roll", "_feel_pull", "_feel_time"):
            self.assertIn(f"{field} =", reset)

    def test_fov_curve_is_eased(self):
        car = read("scripts/rally_car.gd")
        self.assertIn("func chase_fov_factor() -> float:", car)
        self.assertIn("func inside_fov_factor() -> float:", car)
        self.assertIn("Sway.speed_fov_factor(speed_kmh, f().speed_reference_kmh, f().fov_speed_ease)", car)
        self.assertIn("fov_speed_ease", read("scripts/data/rally_car_feel_config.gd"))


class SpeedMotesTest(unittest.TestCase):
    """Придорожный поток — мировой эффект: он не трясёт кадр и виден только сзади."""

    def test_motes_are_data_driven_and_chase_only(self):
        feel = read("scripts/data/rally_car_feel_config.gd")
        for field in (
            "speed_motes_enabled",
            "speed_motes_amount",
            "speed_motes_length",
            "speed_motes_width",
            "speed_motes_height",
            "speed_motes_size",
            "speed_motes_start_kmh",
            "speed_motes_full_kmh",
            "speed_motes_color",
            "speed_motes_lifetime",
            "speed_motes_velocity_stretch",
        ):
            self.assertIn(f"var {field}:", feel)
        car = read("scripts/rally_car.gd")
        self.assertIn("func _setup_speed_motes() -> void:", car)
        self.assertIn("func _update_speed_motes(amount: float) -> void:", car)
        self.assertIn("amount if camera_mode == CameraMode.CHASE_3RD else 0.0", car)


class SpeedFeelShaderTest(unittest.TestCase):
    def test_no_procedural_speed_lines(self):
        shader = read("shaders/speed_fx.gdshader")
        for forbidden in ("streak_strength", "speed_phase", "view_streak", "sectors", "dash"):
            self.assertNotIn(forbidden, shader)

    def test_funnel_stretch_keeps_the_center_sharp(self):
        shader = read("shaders/speed_fx.gdshader")
        self.assertIn("uniform float speed_stretch", shader)
        self.assertIn("uniform float speed_stretch_gain", shader)
        # Растяжение привязано к маске краёв: в центре маска равна нулю.
        self.assertIn("float stretch = speed_stretch * speed_stretch_gain * mask * intensity;", shader)
        # Один проход вместо двух: разлёт = размытие + растяжение.
        self.assertIn("float spread = stretch + blur_strength * view_blur_gain * mask;", shader)

    def test_keeps_camera_aware_peripheral_blur(self):
        shader = read("shaders/speed_fx.gdshader")
        for uniform in ("uniform int camera_mode", "uniform float blur_gain", "uniform float cockpit_scale"):
            self.assertIn(uniform, shader)
        self.assertIn("if (camera_mode != 1)", shader)


class SpeedFeelWiringTest(unittest.TestCase):
    def test_screen_receives_stretch(self):
        screen = read("scripts/effects/rally_screen_look.gd")
        self.assertIn('_set_param(mat, "speed_stretch", speed_feel.edge_stretch_percent / 100.0)', screen)
        feel = read("scripts/effects/rally_speed_feel.gd")
        self.assertIn("var edge_stretch_percent:", feel)
        self.assertIn('cfg.set("speed_edge_stretch", edge_stretch_percent / 100.0)', feel)
        settings = read("scripts/data/rally_stage_settings.gd")
        self.assertIn("var speed_edge_stretch:", settings)

    def test_stage_fallback_pushes_stretch(self):
        stage = read("scripts/rally_stage.gd")
        self.assertIn('speed_fx_material.set_shader_parameter("speed_stretch", cfg.speed_edge_stretch)', stage)

    def test_scenes_store_new_uniform(self):
        for rel in (
            "scenes/effects/retro_screen.tscn",
            "scenes/rally_stage.tscn",
            "scenes/rally_stage2_forest.tscn",
            "scenes/editor/visual_effects_lab.tscn",
        ):
            scene = read(rel)
            self.assertIn("shader_parameter/speed_stretch", scene, rel)
            self.assertNotIn("shader_parameter/streak_strength", scene, rel)

    def test_pause_panel_has_speed_feel_slider(self):
        hud = read("scenes/ui/rally_hud.tscn")
        self.assertIn('name="SpeedFeel"', hud)
        settings = read("scripts/ui/camera_settings.gd")
        self.assertIn('"SpeedFeel"', settings)
        self.assertIn("car.camera_feel_strength = value", settings)

    def test_wind_is_a_speed_cue(self):
        sound = read("scripts/engine_sound.gd")
        self.assertIn("var wind_full_kmh:", sound)
        self.assertIn("var chase_wind_boost_db:", sound)
        self.assertIn("var chase_road_boost_db:", sound)


class SettingsConflictTest(unittest.TestCase):
    """Одна настройка — один пульт.

    Раньше эффект скорости жил в трёх местах сразу: узел Speed, uniform'ы
    материала экрана и старый RallyStageSettings. Правки в инспекторе не
    доживали до заезда (материал перезаписывался), выбранный пресет
    превращался в «Свой характер» после перезапуска сцены, а без узла Speed
    скорость молча получала ноль.
    """

    def test_preset_survives_scene_reload(self):
        cases = (
            ("scripts/effects/rally_speed_feel.gd", "if feel != Feel.CUSTOM:\n\t\t_apply_preset()"),
            ("scripts/effects/rally_screen_look.gd", "if look != Look.CUSTOM:\n\t\t_apply_preset()"),
            ("scripts/effects/rally_precipitation_effect.gd", "if preset != Preset.CUSTOM:\n\t\t_apply_preset()"),
        )
        for rel, ready_line in cases:
            src = read(rel)
            # Пока сцена загружается, сеттеры чисел получают значения пресета.
            self.assertIn("not is_inside_tree()", src, rel)
            # Поэтому пресет ещё раз применяется после чтения всех свойств.
            self.assertIn(ready_line, src, rel)

    def test_manual_edit_reveals_exact_values(self):
        for rel in ("scripts/effects/rally_speed_feel.gd", "scripts/effects/rally_screen_look.gd"):
            src = read(rel)
            block = src.split("func _mark_custom", 1)[1].split("\nfunc ", 1)[0]
            self.assertIn("notify_property_list_changed()", block, rel)

    def test_screen_keeps_material_when_no_speed_node(self):
        screen = read("scripts/effects/rally_screen_look.gd")
        apply = screen.split("func _apply_material", 1)[1].split("func _set_param", 1)[0]
        self.assertIn("if speed_feel != null:", apply)
        # Без узла скорости материал остаётся как в сцене: молчаливые нули
        # и были причиной «эффект не применяется».
        no_node = apply.split("if speed_feel != null:", 1)[1].split("elif", 1)[1]
        self.assertNotIn("speed_intensity", no_node)

    def test_null_track_does_not_disable_retro(self):
        screen = read("scripts/effects/rally_screen_look.gd")
        block = screen.split("func configure_for_track", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("if track == null:", block)
        self.assertIn("return", block)
        # Флаг трассы «нет поля» = «не запрещено», а не «выключено».
        self.assertIn("allows != null", block)
        settings = read("scripts/data/rally_stage_settings.gd")
        self.assertIn("var allowed: Variant = track.get(\"enable_speed_fx\")", settings)

    def test_material_is_not_rewritten_every_frame(self):
        screen = read("scripts/effects/rally_screen_look.gd")
        self.assertIn("func _set_param(mat: ShaderMaterial, param: String, value: Variant) -> void:", screen)
        # set_shader_parameter вызывается только из помощника, который
        # сравнивает новое значение с текущим в материале.
        self.assertEqual(screen.count("mat.set_shader_parameter("), 1)

    def test_stage_falls_back_and_explains_itself(self):
        stage = read("scripts/rally_stage.gd")
        self.assertIn("fx_nodes.speed() != null and speed_rect != null", stage)
        self.assertIn("func _report_speed_fx(speed: float, from_node: bool) -> void:", stage)
        self.assertIn("push_warning(\"Эффект скорости не работает на %.0f км/ч: %s\"", stage)
        speed = read("scripts/effects/rally_speed_feel.gd")
        self.assertIn("func inactive_reason(speed_kmh: float) -> String:", speed)
        screen = read("scripts/effects/rally_screen_look.gd")
        self.assertIn("func speed_blocked_reason() -> String:", screen)

    def test_editor_preview_uses_the_same_source(self):
        effects = read("scripts/effects/rally_visual_effects.gd")
        self.assertIn("func _ready() -> void:\n\tbind_effects()", effects)
        self.assertIn("func bind_effects() -> void:", effects)
        self.assertIn("rect.bind_speed(feel)", effects.split("func configure_screen", 1)[1].split("\nfunc ", 1)[0])

    def test_stage_scene_material_is_not_zeroed(self):
        for rel in ("scenes/rally_stage.tscn", "scenes/rally_stage2_forest.tscn"):
            scene = read(rel)
            self.assertIn("shader_parameter/retro_strength = 1.0", scene, rel)
            self.assertIn("shader_parameter/color_levels = 31.0", scene, rel)
            self.assertIn("shader_parameter/dither_strength = 1.0", scene, rel)
            # Материал хранит те же числа, что посчитает узел Speed,
            # иначе редактор «грязнит» сцену при каждом открытии.
            self.assertIn("shader_parameter/blur_strength = 0.012", scene, rel)
            self.assertIn("shader_parameter/vignette_strength = 0.12", scene, rel)
            self.assertIn("shader_parameter/blur_gain = 2.4", scene, rel)
            self.assertIn("shader_parameter/speed_stretch = 0.02", scene, rel)


if __name__ == "__main__":
    unittest.main()
