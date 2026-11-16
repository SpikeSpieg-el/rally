"""Статические и архитектурные проверки системы призрака и живой дельты HUD."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


class GhostRacerDeliverablesTest(unittest.TestCase):
    def test_required_files_exist(self):
        expected = [
            "shaders/ghost_car.gdshader",
            "scripts/ghost/ghost_recording.gd",
            "scripts/ghost/ghost_car_rig.gd",
            "scripts/effects/rally_ghost_look.gd",
            "scenes/effects/ghost_racer.tscn",
            "scripts/ui/delta_bar_view.gd",
            "scripts/ui/rally_delta_widget.gd",
            "scenes/ui/delta_panel.tscn",
            "scripts/ui/ghost_settings.gd",
            "tests/ghost_racer.gd",
        ]
        for rel in expected:
            self.assertTrue((ROOT / rel).is_file(), f"Не найден файл: {rel}")

    def test_ghost_shader_uniforms_and_render_mode(self):
        shader = read("shaders/ghost_car.gdshader")
        self.assertIn("shader_type spatial;", shader)
        self.assertIn("blend_mix", shader)
        self.assertIn("depth_draw_always", shader)
        self.assertIn("unshaded", shader)
        for token in (
            "uniform vec4 ghost_color",
            "uniform vec4 rim_color",
            "uniform float opacity",
            "uniform float near_fade_alpha",
            "uniform bool use_texture",
            "uniform float texture_mix",
            "uniform sampler2D albedo_tex",
            "uniform float scanline_strength",
            "uniform float pulse_speed",
            "varying float v_local_y;",
        ):
            self.assertIn(token, shader)
        self.assertNotRegex(shader, r"uniform\s+\w+\s+\w+\[\d+\]\s*=")

    def test_ghost_look_is_tool_data_driven_and_wired_into_visual_effects(self):
        ghost_look = read("scripts/effects/rally_ghost_look.gd")
        self.assertIn("@tool", ghost_look)
        self.assertIn("class_name RallyGhostLook", ghost_look)
        for token in (
            "enum GhostLook",
            "OFF",
            "HOLOGRAM",
            "SILHOUETTE",
            "NEON_PACER",
            "TRANSPARENT_RIVAL",
            "enum DeltaReferenceMode",
            "func _mark_custom(",
            "func begin_session(",
            "func update_runtime(",
            "func record_checkpoint(",
            "func finish_session(",
            "func format_finish_summary(",
            "func delete_current_ghost(",
            "func apply_user_preferences(",
            "func clear_user_preferences(",
            "near_fade_enabled",
            "spawn_target_pacer_3d",
            "trail_enabled",
        ):
            self.assertIn(token, ghost_look)

        # Все поля должны оставаться редактируемыми в инспекторе:
        # _validate_property помечает read-only только description.
        val_block = re.search(
            r"func _validate_property.*?(?=\nfunc |\Z)", ghost_look, re.DOTALL
        )
        self.assertIsNotNone(val_block)
        self.assertIn('"description"', val_block.group(0))
        self.assertNotIn("GhostLook.CUSTOM", val_block.group(0))

        vfx_tscn = read("scenes/effects/visual_effects.tscn")
        self.assertIn("scenes/effects/ghost_racer.tscn", vfx_tscn)
        self.assertIn('[node name="Ghost"', vfx_tscn)

        vfx_gd = read("scripts/effects/rally_visual_effects.gd")
        self.assertIn("ghost_path", vfx_gd)
        self.assertIn("func ghost(", vfx_gd)

    def test_ghost_recording_binary_format_and_math(self):
        rec = read("scripts/ghost/ghost_recording.gd")
        self.assertIn("class_name RallyGhostRecording", rec)
        for token in (
            'const MAGIC := "RGHOST01"',
            "func append_sample(",
            "func sample_at_time(",
            "func time_at_along(",
            "func along_near(",
            "func compute_delta(",
            "func compute_target_delta(",
            "func save_to_file(",
            "func save_for_key(",
            "static func load_from_file(",
            "static func load_for_key(",
            "static func has_saved_ghost(",
            "static func delete_file(",
            "static func delete_ghost(",
            "slerp(",
        ):
            self.assertIn(token, rec)

    def test_ghost_car_rig_clones_cleanly_and_preserves_livery_texture(self):
        rig = read("scripts/ghost/ghost_car_rig.gd")
        self.assertIn("@tool", rig)
        self.assertIn("class_name RallyGhostCarRig", rig)
        for token in (
            "enum RenderMode",
            "HOLOGRAM_SHADER",
            "TRANSPARENT_LIVERY",
            '"base_tex"',
            "preserve_livery_texture",
            "set_near_fade",
            "func build_from_scene_path(",
            "func apply_look_params(",
            "func update_pose_and_fx(",
            "ImmediateMesh",
            "SKIP_NODES",
            '"BodyCollider"',
        ):
            self.assertIn(token, rig)
        # Клонируемая геометрия призрака не должна вшиваться в .tscn как owner = ...
        self.assertNotRegex(rig, r"\.owner\s*=")
        # Коллайдеры и служебные узлы не клонируются в призрака.
        self.assertNotIn("CollisionShape3D.new()", rig)

    def test_delta_hud_mini_map_and_pause_ui_wiring(self):
        hud_tscn = read("scenes/ui/rally_hud.tscn")
        self.assertIn("scenes/ui/delta_panel.tscn", hud_tscn)
        self.assertIn('[node name="DeltaPanel"', hud_tscn)
        self.assertIn('[node name="GhostOptions"', hud_tscn)
        self.assertIn("scripts/ui/ghost_settings.gd", hud_tscn)

        delta_panel_tscn = read("scenes/ui/delta_panel.tscn")
        self.assertIn("scripts/ui/rally_delta_widget.gd", delta_panel_tscn)
        self.assertIn("scripts/ui/delta_bar_view.gd", delta_panel_tscn)

        delta_gd = read("scripts/ui/rally_delta_widget.gd")
        self.assertIn("@tool", delta_gd)
        self.assertIn("class_name RallyDeltaWidget", delta_gd)
        self.assertIn("func set_cockpit_hidden(", delta_gd)
        self.assertIn("func update_live_delta(", delta_gd)
        self.assertIn("func flash_checkpoint(", delta_gd)
        self.assertIn("func set_hud_style(", delta_gd)

        bar_gd = read("scripts/ui/delta_bar_view.gd")
        self.assertIn("@tool", bar_gd)
        self.assertIn("class_name RallyDeltaBarView", bar_gd)

        hud_style = read("scripts/data/rally_hud_style.gd")
        self.assertIn("cockpit_hide_delta_panel", hud_style)
        style_tres = read("data/ui/default_hud_style.tres")
        self.assertIn("cockpit_hide_delta_panel", style_tres)

        hud_gd = read("scripts/ui/rally_hud.gd")
        self.assertIn("delta_panel_path", hud_gd)
        self.assertIn("set_cockpit_hidden", hud_gd)
        self.assertIn("get_delta_panel", hud_gd)

        mini = read("scripts/ui/mini_map.gd")
        for token in ("show_ghost", "ghost_color", "func set_ghost(", "func clear_ghost("):
            self.assertIn(token, mini)

        ghost_opts = read("scripts/ui/ghost_settings.gd")
        self.assertIn("user://rally_ghost.cfg", ghost_opts)
        self.assertIn("apply_user_preferences", ghost_opts)
        self.assertIn("delete_current_ghost", ghost_opts)

    def test_stage_and_arcade_and_menu_integration(self):
        stage = read("scripts/rally_stage.gd")
        for token in (
            'const GhostLookScene = preload("res://scenes/effects/ghost_racer.tscn")',
            "func _resolve_ghost_look(",
            "func _setup_ghost_session(",
            "_ghost_look.begin_session(",
            "_ghost_look.update_runtime(",
            "_ghost_look.record_checkpoint(",
            "_ghost_look.finish_session(",
            'delta_widget.call("update_live_delta"',
            'delta_widget.call("flash_checkpoint"',
            "mini_map.set_ghost(",
            "mini_map.clear_ghost()",
        ):
            self.assertIn(token, stage)

        finish_block = re.search(
            r"func _finish_stage\(\).*?(?=\nfunc |\Z)", stage, re.DOTALL
        )
        self.assertIsNotNone(finish_block)
        fb = finish_block.group(0)
        self.assertLess(fb.index("submit_time"), fb.index("finish_session"))

        arcade = read("scripts/arcade/arcade_stage.gd")
        self.assertIn('"DeltaPanel"', arcade)
        self.assertIn('"PausePanel/Box/GhostOptions"', arcade)

        layout = read("scripts/data/rally_menu_layout.gd")
        self.assertIn("ghost_available_badge", layout)
        menu = read("scripts/main_menu.gd")
        self.assertIn("has_saved_ghost", menu)
        self.assertIn("ghost_available_badge", menu)

    def test_docs_updated(self):
        doc = read("docs/AGENTS_DATA_DRIVEN_RU.md")
        self.assertIn("RallyGhostLook", doc)
        self.assertIn("RallyDeltaWidget", doc)

    def test_godot47_parse_and_runtime_contracts(self):
        rig = read("scripts/ghost/ghost_car_rig.gd")
        self.assertNotIn("CULL_MODE_DISABLED", rig)
        self.assertIn("BaseMaterial3D.CULL_DISABLED", rig)
        self.assertNotIn("FeelConfigType.load_default", rig)
        self.assertIn('res://data/car/default_car_feel.tres', rig)
        self.assertIn('src.get("feel")', rig)
        self.assertIn("ghost_src_mat", rig)
        self.assertIn("245.0", rig)

        ghost_look = read("scripts/effects/rally_ghost_look.gd")
        self.assertIn('setup_res.get("livery")', ghost_look)

        arcade = read("scripts/arcade/arcade_stage.gd")
        self.assertIn(
            'const GameSettings = preload("res://scripts/ui/game_settings.gd")',
            arcade,
        )
        self.assertIn("GameSettings.apply_display(", arcade)

        # Проверяем, что ни один скрипт в scripts/ не вызывает несуществующий static метод
        # или отсутствующий enum через const Alias = preload("res://...gd").
        gd_files = sorted((ROOT / "scripts").rglob("*.gd"))
        static_funcs_by_rel = {}
        enums_by_rel = {}
        for gd in gd_files:
            rel = gd.relative_to(ROOT).as_posix()
            txt = gd.read_text(encoding="utf-8", errors="ignore")
            static_funcs_by_rel[rel] = set(
                re.findall(r"^static\s+func\s+(\w+)\s*\(", txt, re.M)
            )
            enum_map = {}
            for em in re.finditer(r"^enum\s+(\w+)\s*\{([^}]*)\}", txt, re.M | re.S):
                members = set()
                for line in em.group(2).splitlines():
                    line = line.split("#")[0].strip()
                    for tok in line.split(","):
                        tok = tok.strip().split("=")[0].strip()
                        if tok:
                            members.add(tok)
                enum_map[em.group(1)] = members
            enums_by_rel[rel] = enum_map

        for gd in gd_files:
            rel = gd.relative_to(ROOT).as_posix()
            txt = "\n".join(
                line.split("#")[0]
                for line in gd.read_text(encoding="utf-8", errors="ignore").splitlines()
            )
            for am in re.finditer(
                r'^const\s+(\w+)\s*=\s*preload\(\s*"res://([^"]+\.gd)"\s*\)',
                txt,
                re.M,
            ):
                alias, target = am.group(1), am.group(2)
                if target not in static_funcs_by_rel:
                    continue
                for cm in re.finditer(rf"(?<![.\w]){re.escape(alias)}\.(\w+)\s*\(", txt):
                    meth = cm.group(1)
                    if meth == "new":
                        continue
                    self.assertIn(
                        meth,
                        static_funcs_by_rel[target],
                        f"{rel}: {alias}.{meth}() не является static func в {target}",
                    )
                for em in re.finditer(
                    rf"(?<![.\w]){re.escape(alias)}\.(\w+)\.(\w+)\b", txt
                ):
                    en, ev = em.group(1), em.group(2)
                    if en in enums_by_rel[target]:
                        self.assertIn(
                            ev,
                            enums_by_rel[target][en],
                            f"{rel}: {alias}.{en}.{ev} не найден в {target}",
                        )


if __name__ == "__main__":
    unittest.main()
