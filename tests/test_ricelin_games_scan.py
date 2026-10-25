#!/usr/bin/env python3
"""Compatibility checks for the thin legacy Games-scan wrapper."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
WRAPPER = REPO / "configs/hypr/scripts/ricelin-games-scan"
DISCOVERY = REPO / "configs/hypr/scripts/ricelin-game-discovery"
class LegacyGamesScanTests(unittest.TestCase):
    def test_shared_backend_legacy_index_shape(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp) / "home"; folder = home / "Games/Example Game"
            folder.mkdir(parents=True); (folder / "ExampleGame.exe").touch(); (home / ".config/ricelin").mkdir(parents=True)
            run = subprocess.run([sys.executable, str(DISCOVERY), "--home", str(home), "--root", str(home / "Games"), "--format", "legacy-index"], text=True, capture_output=True, check=True)
            payload = json.loads(run.stdout)
            self.assertEqual(payload["source"], "ricelin-game-discovery"); self.assertEqual(len(payload["games"]), 1)
            self.assertEqual(payload["games"][0]["name"], "Example Game"); self.assertTrue(payload["readOnly"])
    def test_old_script_has_no_duplicate_scanner(self):
        source = WRAPPER.read_text(encoding="utf-8")
        self.assertIn('with_name("ricelin-game-discovery")', source); self.assertNotIn("os.walk", source)
if __name__ == "__main__": unittest.main()
