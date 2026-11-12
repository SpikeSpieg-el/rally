"""Проверки «Студии трассы» без движка.

Godot в CI может отсутствовать, поэтому всё, что можно сверить статически,
сверяется здесь: имена полей «пультов», арность вызовов анализа, состав дока,
включённость плагина и предпросмотра у ЛЕС2.

Запуск: python3 -m unittest discover -s tests
"""
import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as handle:
        return handle.read()


def exports(source):
    return set(re.findall(r"^@export[^\n]*var (\w+)", source, re.M))


def code_only(source):
    """Убрать строковые литералы: «studio.gd» в тексте — не обращение к члену."""
    without_strings = re.sub(r'"(?:[^"\\]|\\.)*"', '""', source)
    return re.sub(r"#[^\n]*", "", without_strings)


def members(source):
    found = set(re.findall(r"^var (\w+)", source, re.M))
    found |= set(re.findall(r"^func (\w+)\(", source, re.M))
    found |= set(re.findall(r"^const (\w+)", source, re.M))
    return found


def function_returns(source):
    """Имя функции -> есть ли аннотация возврата (`-> Type`)."""
    result = {}
    for match in re.finditer(r"^func (\w+)\(", source, re.M):
        index = match.end() - 1
        depth = 0
        while index < len(source):
            char = source[index]
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    break
            index += 1
        tail = source[index + 1:index + 80]
        tail = tail.split(":", 1)[0].strip()
        result[match.group(1)] = tail.startswith("->")
    return result


def untyped_inference_risks(source):
    """`var x := studio.метод()` без типа не собирается.

    GDScript выводит тип только у выражений с известным типом. Нетипизированный
    параметр (`studio`) делает и поле, и результат вызова Variant'ом — даже если
    у метода есть `-> Type`: компилятор не знает класс получателя и падает с
    «Cannot infer the type of x variable». Ловим именно это, плюс вызовы
    собственных функций без аннотации возврата.
    """
    returns = function_returns(source)
    risks = []
    for number, line in enumerate(source.split("\n"), 1):
        match = re.search(r"var (\w+) := (.*)$", line)
        if not match:
            continue
        expression = match.group(2)
        if " as " in expression:
            continue  # приведение типа задаёт тип явно
        if re.match(r"(studio|_studio)\.", expression):
            risks.append("%d: %s" % (number, line.strip()))
            continue
        local_call = re.match(r"([A-Za-z_]\w*)\(", expression)
        if local_call and local_call.group(1) in returns and not returns[local_call.group(1)]:
            risks.append("%d: %s" % (number, line.strip()))
    return risks


def static_signatures(source):
    """Имя -> (всего параметров, обязательных)."""
    result = {}
    for match in re.finditer(r"^static func (\w+)\(([^)]*)\)", source, re.M | re.S):
        params = [item.strip() for item in match.group(2).split(",") if item.strip()]
        required = sum(1 for item in params if "=" not in item)
        result[match.group(1)] = (len(params), required)
    return result


def call_args(source, name):
    """Список списков аргументов для вызовов name(...)."""
    results = []
    for match in re.finditer(r"(?<![\w.])" + re.escape(name) + r"\(", source):
        index = match.end()
        depth = 1
        args = 0
        seen = False
        while index < len(source) and depth > 0:
            char = source[index]
            if char in "([{":
                depth += 1
            elif char in ")]}":
                depth -= 1
                if depth == 0:
                    break
            elif char == "," and depth == 1:
                args += 1
            elif not char.isspace() and char != "\n":
                seen = True
            index += 1
        if seen:
            args += 1
        results.append(args)
    return results


class TrackStudioTest(unittest.TestCase):
    def test_settings_fields_used_by_plugin_exist(self):
        settings = exports(read("scripts/data/rally_track_studio_settings.gd"))
        self.assertIn("mode_names", settings)
        self.assertIn("show_hud", settings)
        used = set()
        for rel in ("addons/rally_track_studio/studio.gd",
                    "addons/rally_track_studio/studio_view.gd",
                    "addons/rally_track_studio/dock.gd",
                    "addons/rally_track_studio/plugin.gd"):
            source = code_only(read(rel))
            used |= set(re.findall(r"\b_st\.(\w+)", source))
            used |= set(re.findall(r"\bsettings\.(\w+)", source))
            used |= set(re.findall(r"\b_settings\.(\w+)", source))
        missing = sorted(used - settings)
        self.assertEqual(missing, [], "поля настроек студии: %s" % missing)

    def test_studio_members_used_elsewhere_exist(self):
        known = members(read("addons/rally_track_studio/studio.gd"))
        used = set()
        for rel, prefix in (
            ("addons/rally_track_studio/studio_view.gd", "studio"),
            ("addons/rally_track_studio/dock.gd", "_studio"),
            ("addons/rally_track_studio/plugin.gd", "studio"),
        ):
            used |= set(re.findall(r"\b%s\.(\w+)" % prefix, code_only(read(rel))))
        missing = sorted(used - known)
        self.assertEqual(missing, [], "члены studio.gd: %s" % missing)

    def test_dock_rows_are_real_track_fields(self):
        config = exports(read("scripts/data/rally_track_config.gd"))
        rows = re.findall(r'"property": "(\w+)"', read("addons/rally_track_studio/dock.gd"))
        self.assertGreaterEqual(len(rows), 12, "док должен покрывать дорогу, рельеф, насыпь и свет")
        missing = sorted(set(rows) - config)
        self.assertEqual(missing, [], "поля RallyTrackConfig: %s" % missing)
        self.assertEqual(len(rows), len(set(rows)), "без повторяющихся ползунков")

    def test_analysis_calls_match_signatures(self):
        signatures = static_signatures(read("scripts/track/route_analysis.gd"))
        self.assertIn("find_corners", signatures)
        for rel in ("addons/rally_track_studio/studio.gd",
                    "addons/rally_track_studio/studio_view.gd",
                    "tests/track_studio.gd"):
            source = read(rel)
            for name, (total, required) in signatures.items():
                if name.startswith("_"):
                    continue
                for count in call_args(source, "Analysis." + name):
                    self.assertGreaterEqual(count, required, "%s: мало аргументов %s" % (rel, name))
                    self.assertLessEqual(count, total, "%s: много аргументов %s" % (rel, name))

    def test_plugin_is_enabled_and_forest_has_preview(self):
        self.assertIn("addons/rally_track_studio/plugin.cfg", read("project.godot"))
        config = read("addons/rally_track_studio/plugin.cfg")
        self.assertIn('script="plugin.gd"', config)
        self.assertTrue(os.path.exists(os.path.join(ROOT, "addons/rally_track_studio/plugin.gd")))
        scene = read("scenes/rally_stage2_forest.tscn")
        m = re.search(r'settings\s*=\s*SubResource\("([^"]+)"\)', scene)
        self.assertIsNotNone(m, "в rally_stage2_forest.tscn должен быть ресурс settings")
        sub_header = '[sub_resource type="Resource" id="%s"]' % m.group(1)
        block = scene[scene.index(sub_header):]
        block = block[:block.index("[sub_resource", 10)] if "[sub_resource" in block[10:] else block
        # Поле может не сериализоваться, когда совпадает со значением по умолчанию.
        default = read("scripts/data/rally_stage_settings.gd")
        self.assertNotIn("preview_in_editor = false", block)
        self.assertTrue("preview_in_editor = true" in block or
                        "var preview_in_editor: bool = true" in default)
        self.assertIn("stage_forest_route2.tres", scene)

    def test_no_untyped_inference_in_plugin(self):
        """`var x := studio.метод()` не собирается: тип приходится писать явно."""
        for rel in ("addons/rally_track_studio/studio.gd",
                    "addons/rally_track_studio/studio_view.gd",
                    "addons/rally_track_studio/dock.gd",
                    "addons/rally_track_studio/plugin.gd",
                    "scripts/track/route_analysis.gd",
                    "tests/track_studio.gd"):
            risks = untyped_inference_risks(read(rel))
            self.assertEqual(risks, [], "%s: выведите тип явно: %s" % (rel, risks))

    def test_all_polygons_are_guarded(self):
        """Каждый draw_colored_polygon должен быть защищён от вырожденных данных.

        Иначе Godot сыплет «Invalid polygon data, triangulation failed» на
        каждый кадр — это и был лог на 2740 строк и просадка редактора.
        """
        lines = read("addons/rally_track_studio/studio_view.gd").split("\n")
        calls = 0
        for number, line in enumerate(lines):
            if "draw_colored_polygon" not in line or line.strip().startswith("#"):
                continue
            calls += 1
            window = "\n".join(lines[max(0, number - 12):number + 1])
            guarded = ("_in_picture" in window or "_draw_quad" in window
                       or "_draw_triangle" in window or "_quad_is_convex" in window)
            self.assertTrue(guarded, "полигон без проверки: строка %d" % (number + 1))
        self.assertGreater(calls, 0, "разметка должна что-то заливать")
        # Никаких «одним полигоном на 500 вершин»: у Godot отсечение ушей за
        # O(n^2), а на ровном профиле он ещё и падает с Invalid polygon data.
        # Два вызова в _draw_quad и два в _draw_triangle — и ни одного мимо них.
        self.assertEqual(calls, 4, "заливать можно только через _draw_quad/_draw_triangle")

    def test_quads_are_convex(self):
        """Четырёхугольник-«бабочка» тоже роняет триангуляцию."""
        view = read("addons/rally_track_studio/studio_view.gd")
        self.assertIn("func _quad_is_convex(", view)
        self.assertIn("_quad_is_convex(a, b, c, d)", view)

    def test_profile_fill_is_trapezoids(self):
        """Заливка профиля — столбики из _draw_quad, а не один огромный полигон."""
        view = read("addons/rally_track_studio/studio_view.gd")
        block = view[view.index("func _draw_profile("):]
        block = block[:block.index("\nfunc ")]
        self.assertNotIn("draw_colored_polygon", block)
        self.assertIn("_draw_quad(", block)
        self.assertIn("_st.profile_fill_max_quads", block)
        settings = read("scripts/data/rally_track_studio_settings.gd")
        self.assertIn("var profile_fill_max_quads", settings)

    def test_projections_are_frustum_culled_and_cached(self):
        """unproject_position зовём только для того, что в кадре, и кэшируем."""
        view = read("addons/rally_track_studio/studio_view.gd")
        self.assertIn("func _project_samples(", view)
        self.assertIn("is_position_in_frustum", view)
        self.assertIn("_cache_key", view)
        studio = read("addons/rally_track_studio/studio.gd")
        self.assertIn("route_version", studio)
        hover = studio[studio.index("func _nearest_sample_screen("):]
        hover = hover[:hover.index("\nfunc ")]
        self.assertIn("is_position_in_frustum", hover,
                      "поиск подсказки перебирает всю трассу — без отсечения лагает")
        self.assertIn("func _nearest_sample_screen(camera: Camera3D, screen_pos: Vector2, limit_px: float) -> int",
                      studio)

    def test_hover_redraw_is_gated(self):
        """Перерисовку просим только когда подсказка правда изменилась."""
        studio = read("addons/rally_track_studio/studio.gd")
        self.assertIn("func _update_hover(camera: Camera3D, screen_pos: Vector2) -> bool", studio)
        self.assertIn("if _update_hover(camera, motion.position):", studio)

    def test_cursor_hint_is_off_by_default(self):
        """Подсказка ездит за мышью и тормозит редактор — по умолчанию выключена."""
        settings = read("scripts/data/rally_track_studio_settings.gd")
        self.assertIn("var show_cursor: bool = false", settings)
        self.assertIn("var show_ghost_point: bool = false", settings)
        resource = read("data/editor/track_studio.tres")
        self.assertNotIn("show_cursor", resource, "в .tres не должно быть переопределения")

    def test_forest_scene_has_no_baked_geometry(self):
        """Запечённая земля в .tscn — это десятки мегабайт и медленное сохранение."""
        rel = "scenes/rally_stage2_forest.tscn"
        scene = read(rel)
        self.assertNotIn('[sub_resource type="ArrayMesh"', scene)
        self.assertNotIn('[sub_resource type="ConcavePolygonShape3D"', scene)
        size = os.path.getsize(os.path.join(ROOT, rel))
        self.assertLess(size, 1_000_000, "сцена ЛЕС2 весит %d байт" % size)
        stage = read("scripts/rally_stage.gd")
        self.assertIn("func _ensure_terrain_parts", stage)
        self.assertIn("terrain_mesh.owner = null", stage)
        self.assertIn("terrain_collider.owner = null", stage)

    def test_undo_methods_are_public_and_idempotent_names(self):
        source = read("addons/rally_track_studio/studio.gd")
        for name in ("apply_curve_state", "apply_sections", "apply_section_state",
                     "apply_spawn_state", "_attach_node", "_detach_node",
                     "_after_edit", "_mark_scene_dirty"):
            self.assertIn("func %s(" % name, source, "метод UndoRedo %s" % name)


class TrackStudioEditingRegressionTest(unittest.TestCase):
    def test_editing_does_not_reanalyse_or_rebuild_for_props(self):
        source = read("addons/rally_track_studio/studio.gd")
        def body(name):
            text = source.split("func " + name + "(", 1)[1]
            return re.split(r"\n(?:func |## )", text, maxsplit=1)[0]
        self.assertNotIn("_dirty = true", body("_drag_width"))
        self.assertIn("_road_changed()", body("_drag_width"))
        self.assertNotIn("_after_edit", body("_commit_props_placed"))
        self.assertNotIn("_schedule_rebuild", body("_after_props_edit"))
        self.assertIn('_stroke_nodes.size() >= settings.brush_max_per_stroke', body("_place_brush"))
        self.assertIn("_stroke_has_space", body("_place_brush"))
        self.assertNotIn("Analysis.nearest", body("_direction_at_distance"))
        self.assertNotIn("_ground_y(", body("_ray_ground"))

    def test_runtime_regressions_cover_brush_and_width(self):
        test = read("tests/track_studio_editing.gd")
        self.assertIn("_width_section_for_edit", test)
        self.assertIn("_stroke_nodes.size() == 8", test)
        self.assertIn("StudioProps", test)
        self.assertIn("global_position.y - 12.0", test)

    def test_stage_suspends_background_rebuilds_when_studio_active(self):
        stage = read("scripts/rally_stage.gd")
        self.assertIn("var editor_suspend_auto_rebuild: bool = false", stage)
        self.assertIn("editor_suspend_auto_rebuild", stage[stage.index("func _queue_rebuild("):stage.index("func _queue_rebuild_from_track(")])
        self.assertIn("func rebuild_preview(fast_mode: bool = false)", stage)
        studio = read("addons/rally_track_studio/studio.gd")
        self.assertIn("_set_stage_suspend", studio)
        self.assertIn("rebuild_preview", studio)

    def test_performance_and_convenience_features_wired(self):
        studio = read("addons/rally_track_studio/studio.gd")
        for fn in ("focus_distance", "focus_selected_or_hovered", "snap_route_to_ground",
                   "level_grade_between_points", "reverse_route", "toggle_closed_loop",
                   "remove_section_at", "snap_studio_props_to_ground", "clear_studio_props",
                   "auto_place_checkpoints", "clear_custom_checkpoints"):
            self.assertIn("func %s(" % fn, studio, "нет удобного метода %s" % fn)
        view = read("addons/rally_track_studio/studio_view.gd")
        self.assertIn("draw_multiline_colors", view, "штрихи должны рисоваться одним вызовом")
        self.assertIn("_prof_cache_key", view, "профиль высот должен кэшироваться")
        self.assertIn("mode_chip_rects", view)
        self.assertIn("warning_item_rects", view)
        plugin = read("addons/rally_track_studio/plugin.gd")
        self.assertIn("_last_toolbar_state", plugin, "панель не должна перерисовываться вхолостую")

    def test_forest_brush_avoids_editor_bottlenecks(self):
        studio = read("addons/rally_track_studio/studio.gd")

        def body(name: str) -> str:
            start = studio.index("func %s" % name)
            nxt = studio.find("\nfunc ", start + 1)
            return studio[start:] if nxt < 0 else studio[start:nxt]

        # 1. Луч земли не бьёт в пропсы (collision_mask = 1) и сначала идёт по сетке высот.
        self.assertIn("collision_mask = 1", body("_terrain_ray"))
        self.assertIn("_ray_height_grid", body("_ray_ground"))
        # 2. Во время живого мазка owner не ставится на каждый узел (иначе SceneTreeDock зависает),
        #    а фиксация UndoRedo идёт пачкой (_attach_nodes_batch / _detach_nodes_batch).
        self.assertIn("if host == null:\n\t\tnode.owner = scene_root", body("_instantiate_prop"))
        self.assertIn("_attach_nodes_batch", body("_commit_props_placed"))
        self.assertIn("_detach_nodes_batch", body("_commit_props_placed"))
        self.assertIn("_detach_entries_batch", body("_commit_erased_stroke"))
        self.assertIn("_attach_entries_batch", body("_commit_erased_stroke"))
        # 3. Завершение/отмена мазка кисти не помечает маршрут грязным (_dirty = true).
        self.assertIn("if not was_props_or_road:\n\t\t_dirty = true", body("_end_drag"))
        self.assertIn("if not was_props_or_road:\n\t\t_dirty = true", body("_cancel_drag"))
        # 4. Мазки и ластик троттлятся и проверяют уже стоящие деревья по пространственной сетке.
        self.assertIn("_last_paint_ms", body("_paint_drag"))
        self.assertIn("_last_erase_ms", body("_erase_prop_stroke_step"))
        self.assertIn("_existing_props_grid", body("_stroke_has_space"))
        # 5. Стриминг отдаёт закэшированную высоту тайла без sparse-поиска.
        streamer = read("scripts/world_streamer.gd")
        self.assertIn("func cached_tile_height(", streamer)
        stage = read("scripts/rally_stage.gd")
        eg_start = stage.index("func editor_cached_ground_height(")
        eg_end = stage.find("\nfunc ", eg_start + 1)
        self.assertIn("cached_tile_height", stage[eg_start:eg_end])
        # 6. В режиме «Лес» оверлей пропускает тяжёлые слои (штрихи, стрелки, стенограмму, предупреждения).
        view = read("addons/rally_track_studio/studio_view.gd")
        da_start = view.index("func draw_all(")
        da_end = view.find("\nfunc ", da_start + 1)
        self.assertIn("in_props", view[da_start:da_end])


if __name__ == "__main__":
    unittest.main()
