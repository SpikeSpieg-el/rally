"""The static checks in tools/check_project.py must catch real GDScript errors
the engine reports, without flagging legal code.

History: a duplicated ``var spin`` inside one function made surface_effects.gd
impossible to preload, which cascaded into rally_car.gd and rally_stage.gd.
Neither gdparse nor gdlint notices that, so the project check owns it now.
"""
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _load_checker():
    spec = importlib.util.spec_from_file_location(
        "check_project", ROOT / "tools/check_project.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


CHECK = _load_checker()


class ShaderArrayTest(unittest.TestCase):
    """Godot 4 не принимает значения по умолчанию у uniform-массивов.

    Такой шейдер не компилируется целиком, и слой грязи на кузове молча
    исчезает: в консоли только «Shader compilation failed».
    """

    def test_wheels_array_without_default_is_accepted(self):
        self.assertEqual(CHECK.check_shader_arrays(), [])

    def test_default_on_uniform_array_is_reported(self):
        import tempfile

        original = CHECK.SHADERS_DIR
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "shaders"
            path.mkdir()
            (path / "bad.gdshader").write_text(
                "shader_type spatial;\nuniform vec3 w[4] = vec3[4](vec3(0.0));\n",
                encoding="utf-8",
            )
            CHECK.SHADERS_DIR = str(path)
            try:
                errors = CHECK.check_shader_arrays()
            finally:
                CHECK.SHADERS_DIR = original
        self.assertEqual(len(errors), 1)
        self.assertIn("uniform-массива", errors[0])


class MaterialPropertyTest(unittest.TestCase):
    """`specular` — имя из Godot 3.x; в 4.x это metallic_specular."""

    def test_repository_uses_godot4_names(self):
        self.assertEqual(CHECK.check_material_props(), [])


class ShadowedNameTest(unittest.TestCase):
    """Имена параметров не должны затенять члены базовых классов."""

    def test_repository_has_no_shadowed_names(self):
        self.assertEqual(CHECK.check_shadowed_names(), [])


class PuffSizeTest(unittest.TestCase):
    """Клуб пыли не должен вырастать крупнее машины.

    При foam_size 0.26 / scale_max 1.85 / growth 3.4 клуб на пике был 5.6 м —
    длиннее кузова, и пыль рисовалась «сквозь» железо.
    """

    def test_repository_puffs_fit_the_car(self):
        self.assertEqual(CHECK.check_puff_size(), [])

    def test_oversized_puff_is_reported(self):
        original = CHECK.ROOT
        import shutil
        import tempfile

        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "data/stage").mkdir(parents=True)
            (root / "scripts/data").mkdir(parents=True)
            shutil.copy(
                Path(original) / "scripts/data/rally_fx_profile.gd",
                root / "scripts/data/rally_fx_profile.gd",
            )
            (root / "data/stage/default_fx_profile.tres").write_text(
                "particle_scale = 1.7\nfoam_size = 0.26\nfoam_growth = 3.4\nfoam_scale_max = 1.85\n",
                encoding="utf-8",
            )
            CHECK.ROOT = str(root)
            try:
                errors = CHECK.check_puff_size()
            finally:
                CHECK.ROOT = original
        self.assertEqual(len(errors), 1)
        self.assertIn("крупнее машины", errors[0])


class EnumAssignmentTest(unittest.TestCase):
    """Значение enum'а нельзя брать прямо из Array: нужен типизированный local."""

    def test_repository_is_clean(self):
        self.assertEqual(CHECK.check_enum_assignments(), [])


def _dups(source: str):
    return CHECK._duplicate_locals("sample.gd", source.strip("\n").split("\n"))


class DuplicateLocalTest(unittest.TestCase):
    def test_duplicate_in_same_block_is_reported(self):
        hits = _dups(
            """
func f():
	var spin := 1.0
	spin = 2.0
	var spin := 3.0
"""
        )
        self.assertEqual(len(hits), 1)
        self.assertIn("spin", hits[0])

    def test_sibling_if_branches_may_reuse_a_name(self):
        hits = _dups(
            """
func f():
	if a:
		var spin := 1.0
		print(spin)
	else:
		var spin := 2.0
		print(spin)
"""
        )
        self.assertEqual(hits, [])

    def test_sibling_loops_may_reuse_a_name(self):
        hits = _dups(
            """
func f():
	for i in range(3):
		var p := i
		print(p)
	for j in range(3):
		var p := j
		print(p)
"""
        )
        self.assertEqual(hits, [])

    def test_duplicate_in_nested_scope_is_reported(self):
        hits = _dups(
            """
func f():
	if a:
		var p := 1
		if b:
			var p := 2
"""
        )
        self.assertEqual(len(hits), 1)

    def test_name_reused_after_block_closes_is_fine(self):
        hits = _dups(
            """
func f():
	if a:
		var p := 1
		print(p)
	var p := 2
"""
        )
        self.assertEqual(hits, [])

    def test_separate_functions_may_reuse_a_name(self):
        hits = _dups(
            """
func f():
	var p := 1

func g():
	var p := 2
"""
        )
        self.assertEqual(hits, [])

    def test_real_repository_is_clean(self):
        bad = []
        for path in sorted((ROOT / "scripts").rglob("*.gd")):
            lines = path.read_text(encoding="utf-8").split("\n")
            bad.extend(CHECK._duplicate_locals(str(path.relative_to(ROOT)), lines))
        for path in sorted((ROOT / "tests").glob("*.gd")):
            lines = path.read_text(encoding="utf-8").split("\n")
            bad.extend(CHECK._duplicate_locals(str(path.relative_to(ROOT)), lines))
        self.assertEqual(bad, [])


class InferFromVariantTest(unittest.TestCase):
    def test_null_else_branch_with_untyped_call_is_reported(self):
        hits = CHECK._infer_from_variant(
            "sample.gd",
            ["\tvar profile := profile_for_kind(kind) if not kind.is_empty() else null"],
        )
        self.assertEqual(len(hits), 1)

    def test_null_inside_comparison_is_not_a_ternary(self):
        hits = CHECK._infer_from_variant(
            "sample.gd",
            [
                "\tvar visible := profile != null",
                "\tvar label := host.get_label() if host != null else \"\"",
            ],
        )
        self.assertEqual(hits, [])


if __name__ == "__main__":
    unittest.main()
