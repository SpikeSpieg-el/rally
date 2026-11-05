"""Guard Godot text resources against accidentally committed merge markers."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
GODOT_SUFFIXES = {".gd", ".gdshader", ".tres", ".tscn", ".godot"}
CONFLICT_MARKER = re.compile(r"^(?:<<<<<<<(?:\s|$)|=======$|>>>>>>>(?:\s|$))", re.MULTILINE)


class ResourceIntegrityTest(unittest.TestCase):
    def test_no_merge_markers_in_godot_files(self):
        bad = []
        for path in ROOT.rglob("*"):
            if not path.is_file() or path.suffix not in GODOT_SUFFIXES:
                continue
            if any(part in {".git", ".godot", "export"} for part in path.relative_to(ROOT).parts):
                continue
            match = CONFLICT_MARKER.search(path.read_text(encoding="utf-8"))
            if match:
                bad.append(str(path.relative_to(ROOT)))
        self.assertEqual(bad, [], "Unresolved merge markers in Godot files")

    def test_default_scenery_preserves_both_density_settings(self):
        text = (ROOT / "data/stage/default_scenery.tres").read_text(encoding="utf-8")
        for name in ("ground_cover_density", "extra_grass_density"):
            assignments = re.findall(rf"^{name}\s*=\s*(.+)$", text, re.MULTILINE)
            self.assertEqual(assignments, ["2.5"], name)


if __name__ == "__main__":
    unittest.main()
