"""Статические и пиксельные контракты управляемого SpriteSpeedometer и RallyHudStyle."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


class HudSpriteArchitectureTest(unittest.TestCase):
    def test_required_files_and_uids_exist(self):
        required = [
            "scripts/data/rally_hud_style.gd",
            "scripts/data/rally_hud_style.gd.uid",
            "data/ui/default_hud_style.tres",
            "scripts/ui/hud_sprite_atlas.gd",
            "scripts/ui/hud_sprite_atlas.gd.uid",
            "scripts/ui/sprite_speedometer.gd",
            "scripts/ui/sprite_speedometer.gd.uid",
            "scripts/ui/sprite_counter.gd",
            "scripts/ui/sprite_counter.gd.uid",
            "scripts/ui/fps_label.gd",
            "scripts/ui/fps_label.gd.uid",
            "scripts/ui/rally_hud.gd",
            "scripts/ui/rally_hud.gd.uid",
            "tests/sprite_speedometer.gd",
            "tests/sprite_speedometer.gd.uid",
        ]
        for rel in required:
            self.assertTrue((ROOT / rel).is_file(), f"отсутствует обязательный файл {rel}")

    def test_rally_hud_scene_uses_external_scripts_not_inline_gdscript(self):
        tscn = read("scenes/ui/rally_hud.tscn")
        self.assertNotIn('id="GDScript_fps"', tscn)
        self.assertNotIn('id="GDScript_speedometer"', tscn)
        self.assertIn("res://scripts/ui/rally_hud.gd", tscn)
        self.assertIn("res://scripts/ui/sprite_speedometer.gd", tscn)
        self.assertIn("res://scripts/ui/fps_label.gd", tscn)
        self.assertIn("res://scripts/ui/sprite_counter.gd", tscn)
        self.assertIn("res://data/ui/default_hud_style.tres", tscn)
        self.assertIn('[node name="TimerSprite"', tscn)

    def test_sprite_speedometer_exports_and_api(self):
        code = read("scripts/ui/sprite_speedometer.gd")
        self.assertIn("@tool", code)
        self.assertIn("class_name SpriteSpeedometer", code)
        for enum_name in ("Preset", "SpeedUnits", "DataSource", "ArcRenderStyle", "ArcShaderGeometry", "GearRenderMode"):
            self.assertIn(f"enum {enum_name}", code)
        for group in (
            '@export_group("Telemetry")',
            '@export_group("Feel & Juice")',
            '@export_group("Preview")',
            '@export_group("Sprite Sheet & Slicing")',
            '@export_group("Visuals & Colors")',
            '@export_group("RPM Arc & Shader")',
            '@export_group("Layout & Sizing")',
            '@export_group("Background & SpeedBox Sync")',
        ):
            self.assertIn(group, code)
        for sig in ("telemetry_updated", "redline_changed", "preset_applied", "atlas_rebuilt"):
            self.assertIn(f"signal {sig}", code)
        for method in (
            "func apply_preset(",
            "func set_hud_style(",
            "func set_telemetry(",
            "func set_speed_only(",
            "func set_rpm_only(",
            "func set_gear_only(",
            "func bind_vehicle(",
            "func get_display_speed(",
            "func get_rpm_ratio(",
            "func rebuild_atlas(",
        ):
            self.assertIn(method, code)

    def test_hud_widgets_and_stage_wiring(self):
        hud_style = read("scripts/data/rally_hud_style.gd")
        self.assertIn("class_name RallyHudStyle", hud_style)
        self.assertIn("func is_pixel_mode(", hud_style)
        self.assertIn("func make_panel_style(", hud_style)
        self.assertIn("func make_button_style(", hud_style)

        hud_ctrl = read("scripts/ui/rally_hud.gd")
        self.assertIn("class_name RallyHUD", hud_ctrl)
        self.assertIn("func apply_hud_style(", hud_ctrl)
        self.assertIn("func set_pixel_mode(", hud_ctrl)
        self.assertIn("func update_timer_display(", hud_ctrl)

        gauge = read("scripts/ui/gauge_bar.gd")
        self.assertIn("func set_hud_style(", gauge)
        self.assertIn("draw_segmented_bar(", gauge)

        mini = read("scripts/ui/mini_map.gd")
        self.assertIn("var pixel_mode: bool", mini)
        self.assertIn("func set_hud_style(", mini)

        radio = read("scripts/ui/rally_radio_card.gd")
        self.assertIn("func apply_hud_style(", radio)

        stage = read("scripts/rally_stage.gd")
        self.assertIn("var hud_controller: RallyHudType", stage)
        self.assertIn("var sprite_speedometer: SpriteSpeedometerType", stage)
        self.assertIn("sprite_speedometer.set_telemetry(", stage)
        # Сохранение старых контрактов SpeedBox для tests/speed_ui.gd.
        self.assertIn("speed_label.text =", stage)
        self.assertIn("gear_label.text =", stage)
        self.assertIn("rpm_bar.value =", stage)

    def test_agents_docs_updated(self):
        doc = read("docs/AGENTS_DATA_DRIVEN_RU.md")
        self.assertIn("RallyHudStyle", doc)
        self.assertIn("data/ui/default_hud_style.tres", doc)


class SpriteSheetSlicingGeometryTest(unittest.TestCase):
    """Проверка реальной нарезки всех 3 спрайт-листов без запуска Godot."""

    @staticmethod
    def _find_runs(active_cols, x0: int, max_gap: int):
        runs = []
        in_run = False
        run_start = 0
        gap = 0
        for i, val in enumerate(active_cols):
            if val:
                if not in_run:
                    in_run = True
                    run_start = x0 + i
                gap = 0
            elif in_run:
                gap += 1
                if gap > max_gap:
                    runs.append((run_start, x0 + i - gap))
                    in_run = False
        if in_run:
            runs.append((run_start, x0 + len(active_cols) - 1))
        return runs

    @unittest.skipUnless(shutil.which("convert"), "ImageMagick convert не установлен")
    def test_all_three_sprite_sheets_slice_cleanly(self):
        sheets = [
            "scenes/ui/ui_hud_r1_ru.png",
            "scenes/ui/ui спрайты спидометр русс.jpg",
            "scenes/ui/ui спрайты спидометр англ.jpg",
        ]
        for rel in sheets:
            path = ROOT / rel
            self.assertTrue(path.is_file(), f"не найден лист {rel}")
            raw = subprocess.check_output(["convert", str(path), "-depth", "8", "rgba:-"])
            w, h = 1200, 896
            self.assertEqual(len(raw), w * h * 4, f"неожиданный размер {rel}")

            # Определяем цвет тёмного фона JPG для имитации _flood_remove_dark_bg.
            r0, g0, b0, a0 = raw[0], raw[1], raw[2], raw[3]
            is_dark_jpg = a0 >= 216 and max(r0, g0, b0) <= 56 and max(r0, g0, b0) >= 8

            def is_solid(x: int, y: int) -> bool:
                idx = (y * w + x) * 4
                r, g, b, a = raw[idx], raw[idx + 1], raw[idx + 2], raw[idx + 3]
                if a <= 76:
                    return False
                if is_dark_jpg:
                    mx = max(r, g, b)
                    if mx >= 11 and abs(r - r0) <= 15 and abs(g - g0) <= 15 and abs(b - b0) <= 15:
                        return False
                return True

            def is_bright_solid(x: int, y: int) -> bool:
                if not is_solid(x, y):
                    return False
                idx = (y * w + x) * 4
                return max(raw[idx], raw[idx + 1], raw[idx + 2]) > 64

            def scan_zone(rx: float, ry: float, rw: float, rh: float, max_gap: int, bright: bool = False):
                x0, y0 = int(rx * w), int(ry * h)
                x1, y1 = int((rx + rw) * w), int((ry + rh) * h)
                cols = []
                fn = is_bright_solid if bright else is_solid
                for x in range(x0, x1):
                    cols.append(any(fn(x, y) for y in range(y0, y1)))
                return self._find_runs(cols, x0, max_gap)

            big_digits = scan_zone(0.01, 0.425, 0.98, 0.17, max(1, int(w * 0.006)))
            small_digits = scan_zone(0.01, 0.605, 0.98, 0.105, max(1, int(w * 0.006)))
            labels = scan_zone(0.01, 0.72, 0.98, 0.135, max(8, int(w * 0.018)))
            gears = scan_zone(0.01, 0.86, 0.98, 0.12, max(6, int(w * 0.016)))
            bar1 = scan_zone(0.45, 0.03, 0.53, 0.125, max(1, int(w * 0.0025)), bright=True)
            bar2 = scan_zone(0.45, 0.165, 0.53, 0.12, max(1, int(w * 0.0025)), bright=True)
            bar3 = scan_zone(0.45, 0.29, 0.53, 0.125, max(1, int(w * 0.0025)), bright=True)

            self.assertEqual(len(big_digits), 10, f"{rel}: big_digits={len(big_digits)}")
            self.assertEqual(len(small_digits), 10, f"{rel}: small_digits={len(small_digits)}")
            self.assertGreaterEqual(len(labels), 3, f"{rel}: labels={len(labels)}")
            self.assertEqual(len(gears), 5, f"{rel}: gears={len(gears)}")
            self.assertEqual(len(bar1), 11, f"{rel}: bar1={len(bar1)}")
            self.assertEqual(len(bar2), 11, f"{rel}: bar2={len(bar2)}")
            self.assertEqual(len(bar3), 4, f"{rel}: bar3={len(bar3)}")


if __name__ == "__main__":
    unittest.main()
