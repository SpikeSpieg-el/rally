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
        block = scene[scene.index('[sub_resource type="Resource" id="Resource_sodgx"]'):]
        block = block[:block.index("[sub_resource", 10)] if "[sub_resource" in block[10:] else block
        self.assertIn("preview_in_editor = true", block)
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
            window = "\n".join(lines[max(0, number - 6):number + 1])
            guarded = ("_in_picture" in window or "_polygon_area" in window
                       or "_draw_quad" in window or "_draw_triangle" in window)
            self.assertTrue(guarded, "полигон без проверки: строка %d" % (number + 1))
        self.assertGreater(calls, 0, "разметка должна что-то заливать")

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


if __name__ == "__main__":
    unittest.main()
