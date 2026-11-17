"""Тесты автогенерации верхних PNG-планов трасс в `docs/previews/`."""
import importlib.util
import struct
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import plot_stage_plan as PLOT


def _load_checker():
    spec = importlib.util.spec_from_file_location("check_project", ROOT / "tools/check_project.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _load_gdtype():
    spec = importlib.util.spec_from_file_location("gdtype_check", ROOT / "tests/gdtype_check.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


EXPECTED_PREVIEWS = {
    "stage_england.tres": "england_stage_plan.png",
    "stage_forest.tres": "forest_stage_plan.png",
    "stage_forest2.tres": "forest2_stage_plan.png",
    "stage_mountain_100.tres": "mountain_100_stage_plan.png",
    "stage_north_arc.tres": "north_arc_stage_plan.png",
    "stage_testpad.tres": "testpad_stage_plan.png",
}
EXCLUDED_TRACKS = ("stage_arcade.tres", "stage_dynamic.tres")


def _png_size(path: Path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        return None
    w, h = struct.unpack(">II", data[16:24])
    return (w, h)


class StagePlanPreviewRepoTest(unittest.TestCase):
    """Готовые превью в репозитории, папка docs/previews/ и отсутствие мусора."""

    def test_previews_folder_has_gdignore_and_no_import_files(self):
        previews = ROOT / "docs" / "previews"
        self.assertTrue(previews.is_dir(), "нет каталога docs/previews/")
        self.assertTrue((previews / ".gdignore").is_file(), "в docs/previews/ нужен .gdignore")
        imports = list(previews.glob("*.import"))
        self.assertEqual(imports, [], "в docs/previews/ не должно быть .import-файлов")

    def test_expected_curve_track_pngs_exist_and_are_valid(self):
        previews = ROOT / "docs" / "previews"
        actual_pngs = sorted(p.name for p in previews.glob("*.png"))
        expected_pngs = sorted(EXPECTED_PREVIEWS.values())
        self.assertEqual(actual_pngs, expected_pngs)
        for name in expected_pngs:
            dims = _png_size(previews / name)
            self.assertIsNotNone(dims, f"{name}: невалидный PNG")
            self.assertGreaterEqual(dims[0], 560, f"{name}: слишком узкий {dims}")
            self.assertGreaterEqual(dims[1], 360, f"{name}: слишком низкий {dims}")

    def test_legacy_england_plan_moved_and_docs_updated(self):
        self.assertFalse((ROOT / "docs" / "england_stage_plan.png").exists())
        self.assertFalse((ROOT / "docs" / "england_stage_plan.png.import").exists())
        doc = (ROOT / "docs" / "ENGLAND_STAGE_RU.md").read_text(encoding="utf-8")
        self.assertIn("previews/england_stage_plan.png", doc)
        self.assertNotIn("(england_stage_plan.png)", doc)


class StagePlanPlotToolTest(unittest.TestCase):
    """Парсер и генератор `tools/plot_stage_plan.py`."""

    def test_output_naming_matches_convention(self):
        for src, dst in EXPECTED_PREVIEWS.items():
            out = PLOT.default_output_path(ROOT / "data/tracks" / src)
            self.assertEqual(out.name, dst)
        self.assertEqual(
            PLOT.default_output_path("custom_rally.tres").name,
            "custom_rally_stage_plan.png",
        )
        self.assertEqual(
            PLOT.default_output_path("my_stage.tres").name,
            "my_stage_plan.png",
        )

    def test_iter_curve_tracks_matches_only_ready_road_curve_tracks(self):
        found = {p.name for p in PLOT.iter_curve_tracks()}
        self.assertEqual(found, set(EXPECTED_PREVIEWS))
        for excluded in EXCLUDED_TRACKS:
            info = PLOT.read_track(ROOT / "data/tracks" / excluded)
            self.assertIsNone(info["road"], f"{excluded}: не должно быть road_curve")

    def test_read_track_resolves_various_ext_ids_river_and_default_prop_bridges(self):
        england = PLOT.read_track(ROOT / "data/tracks/stage_england.tres")
        self.assertEqual(england["road"], ROOT / "data/tracks/stage_england_route.tres")
        self.assertEqual(england["river"], ROOT / "data/tracks/stage_england_river.tres")
        # В stage_england.tres второй мост опускает prop_id (дефолт RallyBridgePlacement),
        # поэтому оба моста должны читаться корректно.
        self.assertEqual(len(england["bridges"]), 2)
        self.assertAlmostEqual(england["bridges"][0]["distance"], 185.8, places=1)
        self.assertAlmostEqual(england["bridges"][1]["distance"], 3378.2, places=1)

        for track_name, expected_route in (
            ("stage_forest.tres", "stage_forest_route.tres"),
            ("stage_forest2.tres", "stage_forest_route2.tres"),
            ("stage_north_arc.tres", "stage_north_arc_route.tres"),
            ("stage_testpad.tres", "stage_testpad_route.tres"),
        ):
            info = PLOT.read_track(ROOT / "data/tracks" / track_name)
            self.assertEqual(info["road"], ROOT / "data/tracks" / expected_route)

    def test_build_single_tracks_into_temp_dir(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = Path(tmp)
            # Речная с мостами, широкая и плоская кольцевая трассы.
            for track_file in ("stage_england.tres", "stage_north_arc.tres", "stage_testpad.tres"):
                out = PLOT.build_stage_plan(
                    ROOT / "data/tracks" / track_file,
                    out_path=tmp_dir / EXPECTED_PREVIEWS[track_file],
                )
                self.assertIsNotNone(out)
                dims = _png_size(out)
                self.assertIsNotNone(dims)
                self.assertGreaterEqual(dims[0], 560)
                self.assertGreaterEqual(dims[1], 360)

    def test_pure_python_fallback_produces_valid_png(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "fallback.png"
            canvas = PLOT._PurePyCanvas(560, 360, (243, 241, 236))
            canvas.rect(20, 20, 120, 34, (56, 96, 190))
            canvas.line(30, 80, 400, 220, (222, 74, 62), width=3)
            canvas.circle(200, 150, 9, (255, 255, 255), outline_color=(28, 28, 28), outline_width=2)
            canvas.text(40, 50, "СТАРТ ФИНИШ 500 м", (32, 122, 52), size=14, bold=True)
            canvas.save(out)
            self.assertEqual(_png_size(out), (560, 360))

    def test_authoring_scripts_trigger_plan_rebuild(self):
        for rel in (
            "tools/author_england_stage.py",
            "tools/author_route.py",
            "tools/author_mountain_100.py",
            "tools/author_testpad.py",
            "tools/make_routes.py",
        ):
            code = (ROOT / rel).read_text(encoding="utf-8")
            self.assertIn("plot_stage_plan", code, f"{rel} не обновляет превью-план")
            self.assertIn("build_stage_plan(", code, f"{rel} не вызывает build_stage_plan")


class GodotPlanAutomationWiringTest(unittest.TestCase):
    """Статическая проверка Godot-интеграции: настройки, триггеры, типизация."""

    def test_new_gdscripts_pass_strict_and_type_checks(self):
        checker = _load_checker()
        gdtype = _load_gdtype()
        strict_errors = [
            err for err in checker.check_gdscript_strict()
            if any(name in err for name in (
                "stage_plan_preview.gd", "build_stage_previews.gd",
                "rally_stage.gd", "studio.gd", "track_studio.gd",
            ))
        ]
        self.assertEqual(strict_errors, [])
        shadow_errors = [
            err for err in checker.check_shadowed_names()
            if any(name in err for name in (
                "stage_plan_preview.gd", "build_stage_previews.gd",
                "rally_stage.gd", "studio.gd", "track_studio.gd",
            ))
        ]
        self.assertEqual(shadow_errors, [])
        for rel in (
            "scripts/track/stage_plan_preview.gd",
            "tools/build_stage_previews.gd",
            "scripts/rally_stage.gd",
            "scripts/data/rally_stage_settings.gd",
            "scripts/data/rally_track_studio_settings.gd",
            "addons/rally_track_studio/studio.gd",
            "tests/track_studio.gd",
        ):
            self.assertEqual(gdtype.check_file((ROOT / rel).read_text(encoding="utf-8")), [], rel)

    def test_settings_and_hooks_are_wired(self):
        for rel in (
            "scripts/data/rally_stage_settings.gd",
            "scripts/data/rally_track_studio_settings.gd",
        ):
            text = (ROOT / rel).read_text(encoding="utf-8")
            self.assertIn("auto_export_plan_png: bool = true", text, rel)
            self.assertIn('plan_preview_dir: String = "res://docs/previews"', text, rel)
            self.assertIn("plan_preview_width: int = 1100", text, rel)

        studio = (ROOT / "addons/rally_track_studio/studio.gd").read_text(encoding="utf-8")
        save_block = studio.split("func save_now()", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("export_plan_preview()", save_block)
        self.assertIn("settings.auto_export_plan_png", save_block)

        stage = (ROOT / "scripts/rally_stage.gd").read_text(encoding="utf-8")
        rebuild_block = stage.split("func rebuild_preview(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("_maybe_export_plan_preview()", rebuild_block)
        self.assertIn('export_tool_button("Обновить план PNG")', stage)


if __name__ == "__main__":
    unittest.main()
