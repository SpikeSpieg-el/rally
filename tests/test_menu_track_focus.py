"""Меню трасс не должно терять фокус при пересборке списка.

Списки кнопок пересобираются на каждое изменение выбора (`selection_changed`),
а старые кнопки уходят в `queue_free` до конца кадра. Пока фокус не
переносили на новую кнопку, клавиатура и геймпад «замирали» после первого же
переключения трассы. Поведение проверяет `tests/menu_track_focus.gd`.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def function(source: str, header: str) -> str:
    body = source.split(header, 1)[1]
    return body.split("\nfunc ", 1)[0]


class MenuTrackFocusTest(unittest.TestCase):
    def test_rebuild_restores_focus_by_index(self):
        menu = read("scripts/main_menu.gd")
        build = function(menu, "func _build_buttons() -> void:")
        self.assertIn("_focused_index(track_buttons)", build)
        self.assertIn("_focused_index(setup_buttons)", build)
        self.assertIn("track_buttons[focused_track].grab_focus()", build)
        self.assertIn("setup_buttons[focused_setup].grab_focus()", build)

    def test_focus_index_uses_live_focus(self):
        menu = read("scripts/main_menu.gd")
        helper = function(menu, "func _focused_index(buttons: Array[Button]) -> int:")
        self.assertIn(".has_focus()", helper)

    def test_engine_check_is_wired_into_ci(self):
        workflow = read(".github/workflows/pages.yml")
        self.assertIn("tests/menu_track_focus.gd", workflow)
        self.assertIn("tests.test_menu_track_focus", workflow)

    def test_engine_test_compares_buttons_not_names(self):
        # Godot переименовывает новую кнопку в @Button@N, пока старая с тем же
        # именем ещё ждёт queue_free, поэтому сверять фокус по имени нельзя.
        engine = read("tests/menu_track_focus.gd")
        self.assertIn("gui_get_focus_owner() == menu.track_buttons[", engine)
        self.assertNotIn('_focus_name() == "TrackButton_', engine)


if __name__ == "__main__":
    unittest.main()
