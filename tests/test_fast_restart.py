"""Контракты быстрого рестарта заезда без холодной перезагрузки сцены.

Запуск: python3 -m unittest tests.test_fast_restart
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def function(source: str, header: str) -> str:
    body = source.split(header, 1)[1]
    return body.split("\nfunc ", 1)[0]


class GameStateRestartRoutingTest(unittest.TestCase):
    def test_restart_race_prefers_in_place_restart(self):
        gs = read("scripts/game_state.gd")
        block = function(gs, "func restart_race() -> void:")
        self.assertIn('scene.has_method("can_restart_in_place")', block)
        self.assertIn('scene.call("can_restart_in_place")', block)
        self.assertIn('scene.call("restart_in_place")', block)
        self.assertIn("race_started.emit()", block)
        self.assertIn("last_time = 0.0", block)
        self.assertIn("is_new_record = false", block)
        self.assertIn("start_race()", block)

    def test_marathon_next_stage_still_uses_start_race(self):
        gs = read("scripts/game_state.gd")
        block = function(gs, "func next_marathon_stage() -> bool:")
        self.assertIn("start_race()", block)


class RallyStageInstantRestartTest(unittest.TestCase):
    def test_stage_has_in_place_restart_and_live_seed_guard(self):
        stage = read("scripts/rally_stage.gd")
        can_fn = function(stage, "func can_restart_in_place() -> bool:")
        self.assertIn("track.procedural and track.reroll_seed_each_visit and not marathon_running", can_fn)

        restart_fn = function(stage, "func restart_in_place() -> void:")
        self.assertIn("world_streamer.is_area_ready(spawn_local)", restart_fn)
        self.assertIn("_restart_streamed_async(spawn_xform, spawn_local)", restart_fn)
        self.assertIn("_apply_instant_restart(spawn_xform)", restart_fn)

    def test_stage_instant_restart_resets_race_weather_ghost_and_spectators(self):
        stage = read("scripts/rally_stage.gd")
        apply_fn = function(stage, "func _apply_instant_restart(spawn_xform: Transform3D) -> void:")
        for required in (
            "stage_time = 0.0",
            "timer_running = false",
            "stage_finished = false",
            "is_new_record = false",
            "last_cp_index = -1",
            "surface_state.clear()",
            "track.route_sections.is_empty()",
            "_setup_precipitation()",
            "car.restart_at_spawn()",
            "rally_spectator_crowds",
            "rally_spectators",
            "_setup_ghost_session()",
            "_update_hud()",
        ):
            self.assertIn(required, apply_fn, f"_apply_instant_restart не сбрасывает {required}")

    def test_stage_restart_button_keeps_marathon_next_contract(self):
        stage = read("scripts/rally_stage.gd")
        btn_fn = function(stage, "func _on_restart_pressed() -> void:")
        self.assertIn('game.call("next_marathon_stage")', btn_fn)
        self.assertIn('game.call("restart_race")', btn_fn)
        self.assertIn("restart_in_place()", btn_fn)


class ArcadeStageInstantRestartTest(unittest.TestCase):
    def test_arcade_stage_resets_car_traffic_pedestrians_rules_and_streamers(self):
        arcade = read("scripts/arcade/arcade_stage.gd")
        self.assertIn("func can_restart_in_place() -> bool:", arcade)
        fn = function(arcade, "func restart_in_place() -> void:")
        for required in (
            "_elapsed_time = 0.0",
            "_max_along = 0.0",
            "_surface.clear()",
            "_terrain.prime(spawn_xform.origin)",
            "_streamer.prime(behind, StreamerType.LOOKAHEAD)",
            "_rules.reset()",
            "_traffic.reset(spawn_d)",
            "_pedestrians.reset(spawn_d)",
            "car.process_mode = Node.PROCESS_MODE_PAUSABLE",
            "car.restart_at_spawn()",
            "_update_hud()",
        ):
            self.assertIn(required, fn, f"arcade restart_in_place не сбрасывает {required}")


class CarAndSubsystemResetHelpersTest(unittest.TestCase):
    def test_car_restart_at_spawn_bypasses_rescue_provider_and_clears_fx(self):
        car = read("scripts/rally_car.gd")
        fn = function(car, "func restart_at_spawn() -> void:")
        for required in (
            "reset_provider = Callable()",
            "reset_to_spawn()",
            "reset_provider = saved_provider",
            "driving_feedback_active = true",
            'surface_effects.call("clear_body_dirt")',
            'blood_fx.call("clear_all")',
            'wipers.call("reset_wipers")',
            'tire_marks.call("clear_marks")',
            'audio.call("reset_state")',
        ):
            self.assertIn(required, fn, f"restart_at_spawn не содержит {required}")

    def test_subsystem_reset_helpers_and_streamer_fixes_exist(self):
        self.assertIn("func clear_marks() -> void:", read("scripts/tire_marks.gd"))
        self.assertIn("func clear_body_dirt() -> void:", read("scripts/surface_effects.gd"))
        self.assertIn("func clear_all() -> void:", read("scripts/effects/rally_blood_fx.gd"))
        self.assertIn("func reset_wipers() -> void:", read("scripts/effects/windshield_wipers.gd"))
        self.assertIn("func reset_state() -> void:", read("scripts/engine_sound.gd"))
        self.assertIn("func reset_person() -> void:", read("scripts/track/spectator_person.gd"))
        self.assertIn("func reset_crowd() -> void:", read("scripts/track/spectator_crowd.gd"))
        self.assertIn("remove_child(_rig)", read("scripts/effects/rally_ghost_look.gd"))
        self.assertIn("func is_area_ready(centre_pos: Vector3) -> bool:", read("scripts/world_streamer.gd"))
        self.assertIn("func prepare_for_restart(start_pos_local: Vector3) -> void:", read("scripts/world_streamer.gd"))
        self.assertIn("_ready_queue.is_empty()", function(read("scripts/arcade/arcade_terrain.gd"), "func prime(center_pos: Vector3) -> void:"))
        self.assertIn("_refresh_wanted(center)", function(read("scripts/arcade/arcade_streamer.gd"), "func prime(behind: float, ahead_chunks: int) -> void:"))


if __name__ == "__main__":
    unittest.main()
