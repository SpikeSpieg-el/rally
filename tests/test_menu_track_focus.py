"""Выбор трассы на 3D-доске гаража не должен терять подсветку и выбор.

Доска пересобирается при каждом открытии гаража: подсветка стартует с выбранной
трассы, стрелки и наведение её двигают, а подтверждённый выбор пишется в RallyGame.
Поведение проверяет `tests/menu_track_focus.gd`.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def function(source: str, header: str) -> str:
    body = source.split(header, 1)[1]
    return body.split("\nfunc ", 1)[0]


class TrackBoardFocusTest(unittest.TestCase):
    def test_board_clamps_focus_and_wraps_steps(self):
        board = read("scripts/garage_track_board.gd")
        set_focus = function(board, "func set_focus(index: int) -> void:")
        self.assertIn("clampi(index", set_focus)
        step = function(board, "func step_focus(step: int) -> void:")
        self.assertIn("posmod(focus_index + step", step)

    def test_garage_builds_board_from_selected_track(self):
        garage = read("scripts/garage_menu.gd")
        enter = function(garage, "func _enter_track_phase() -> void:")
        self.assertIn("_track_board.build(names, _track_panel.selected_track)", enter)

    def test_hover_previews_and_only_choice_records(self):
        garage = read("scripts/garage_menu.gd")
        self.assertIn("_track_board.focus_changed.connect(_on_track_focus_changed)", garage)
        self.assertIn("_track_board.track_chosen.connect(_choose_track)", garage)
        choose = function(garage, "func _choose_track(index: int) -> void:")
        self.assertIn("_track_panel.select_track(index)", choose)
        panel = read("scripts/garage_track_panel.gd")
        preview = function(panel, "func preview_track(index: int) -> void:")
        self.assertNotIn("_sync_track", preview)
        self.assertNotIn("select_track", preview)

    def test_pick_projects_pads_to_screen(self):
        board = read("scripts/garage_track_board.gd")
        pick = function(board, "func pick(camera: Camera3D, viewport_point: Vector2) -> int:")
        self.assertIn("unproject_position", pick)
        self.assertIn("is_position_behind", pick)

    def test_engine_check_is_wired_into_ci(self):
        workflow = read(".github/workflows/pages.yml")
        self.assertIn("tests/menu_track_focus.gd", workflow)
        self.assertIn("tests.test_menu_track_focus", workflow)

    def test_engine_test_drives_the_track_board(self):
        engine = read("tests/menu_track_focus.gd")
        self.assertIn("garage._track_board", engine)
        self.assertIn("focus_index", engine)
        self.assertNotIn("track_buttons", engine)


if __name__ == "__main__":
    unittest.main()
