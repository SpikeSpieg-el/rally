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
