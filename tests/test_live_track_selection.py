"""«Живая лента» не должна подменяться ночным лесом.

У процедурной трассы нет своей сцены: она едет на общей `rally_stage.tscn`,
у которой `track_override = stage_forest.tres`. Раньше этап безусловно
навязывал трассу из сцены, и выбор «ЖИВОЙ ЛЕНТЫ» в меню приводил в ночной
лес. Само поведение проверяет `tests/live_track_selection.gd`; здесь держим
развилку «меню / прямой запуск» и проводку обеих проверок в CI.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def function(source: str, header: str) -> str:
    body = source.split(header, 1)[1]
    return body.split("\nfunc ", 1)[0]


class LiveTrackSelectionTest(unittest.TestCase):
    def test_menu_race_does_not_take_scene_track(self):
        stage = read("scripts/rally_stage.gd")
        enter = function(stage, "func _enter_tree() -> void:")
        self.assertIn(
            "if track_override != null and not _game_starts_from_menu(game):",
            enter,
            "вход в этап не должен навязывать track_override заезду из меню",
        )
        resolve = function(stage, "func _resolve_track() -> void:")
        self.assertIn(
            "if track_override != null and not _game_starts_from_menu(game):",
            resolve,
            "этап не должен собирать сценическую трассу вместо выбранной",
        )
        helper = function(stage, "func _game_starts_from_menu(game: Node) -> bool:")
        self.assertIn('game.call("is_menu_race")', helper)

    def test_game_exposes_menu_race_flag(self):
        game = read("scripts/game_state.gd")
        fn = function(game, "func is_menu_race() -> bool:")
        self.assertIn("return _race_uses_selected_setup", fn)

    def test_start_race_raises_menu_race_flag(self):
        # Развилка в этапе работает только если start_race() поднимает флаг
        # до смены сцены; иначе «Живая лента» снова станет ночным лесом.
        game = read("scripts/game_state.gd")
        fn = function(game, "func start_race() -> void:")
        self.assertIn("_race_uses_selected_setup = true", fn)

    def test_live_track_really_shares_the_forest_scene(self):
        # Если это когда-нибудь перестанет быть правдой, проверка выше станет
        # бессмысленной — пусть тест скажет об этом прямо.
        scene = read("scenes/rally_stage.tscn")
        self.assertIn('path="res://data/tracks/stage_forest.tres"', scene)
        self.assertIn("track_override = ExtResource", scene)
        dynamic = read("data/tracks/stage_dynamic.tres")
        self.assertIn('display_name = "ЖИВАЯ ЛЕНТА"', dynamic)
        self.assertIn("procedural = true", dynamic)
        self.assertNotIn("stage_scene =", dynamic)

    def test_engine_check_is_wired_into_ci(self):
        workflow = read(".github/workflows/pages.yml")
        self.assertIn("tests/live_track_selection.gd", workflow)
        self.assertIn("tests.test_live_track_selection", workflow)


if __name__ == "__main__":
    unittest.main()
