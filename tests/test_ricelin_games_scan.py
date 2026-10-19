#!/usr/bin/env python3
"""Unit tests for the read-only Ricelin Games directory scanner."""
from __future__ import annotations

import runpy
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

REPO = Path(__file__).resolve().parents[1]
SCANNER_PATH = REPO / "configs" / "hypr" / "scripts" / "ricelin-games-scan"
# run_path defines the functions without running the CLI because __name__ is
# not "__main__"; the scanner filename intentionally has no .py suffix.
_NAMESPACE = runpy.run_path(str(SCANNER_PATH))
SCANNER = SimpleNamespace(scan=_NAMESPACE["scan"])


class GamesScannerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "Games"
        self.root.mkdir()

    def write(self, relative, content="not executed"):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return path

    def by_name(self, result, name):
        return next(game for game in result["games"] if game["name"] == name)

    def test_single_executable_is_discovered_without_execution(self):
        marker = Path(self.temp.name) / "should-not-exist"
        game = self.root / "Example Game"
        game.mkdir()
        exe = game / "example-game.exe"
        exe.write_text(f"#!/bin/sh\ntouch {marker}\n", encoding="utf-8")
        exe.chmod(0o755)

        result = SCANNER.scan(self.root)
        found = self.by_name(result, "Example Game")

        self.assertEqual(found["executable"], str(exe))
        self.assertFalse(found["needsSetup"])
        self.assertEqual(found["workingDirectory"], str(game))
        self.assertFalse(marker.exists(), "discovery must never execute a candidate")

    def test_strong_game_name_match_wins_over_launcher(self):
        game = self.root / "Cyberpunk 2077"
        (game / "bin" / "x64").mkdir(parents=True)
        expected = game / "bin" / "x64" / "Cyberpunk2077.exe"
        expected.write_text("game")
        (game / "launcher.exe").write_text("launcher")
        (game / "setup.exe").write_text("installer")
        (game / "unins000.exe").write_text("uninstaller")

        found = self.by_name(SCANNER.scan(self.root), "Cyberpunk 2077")

        self.assertEqual(found["executable"], str(expected))
        paths = {item["path"] for item in found["candidateExecutables"]}
        self.assertNotIn(str(game / "setup.exe"), paths)
        self.assertNotIn(str(game / "unins000.exe"), paths)

    def test_ambiguous_targets_are_not_guessed(self):
        game = self.root / "Mystery Game"
        game.mkdir()
        (game / "client.exe").write_text("client")
        (game / "game-win64.exe").write_text("game")

        found = self.by_name(SCANNER.scan(self.root), "Mystery Game")

        self.assertEqual(found["executable"], "")
        self.assertTrue(found["needsSetup"])
        self.assertEqual(len(found["candidateExecutables"]), 2)

    def test_prefix_and_redistributable_files_are_not_game_targets(self):
        game = self.root / "Imported Game"
        game.mkdir()
        (game / "setup.exe").write_text("installer")
        (game / "prefix" / "drive_c").mkdir(parents=True)
        (game / "prefix" / "drive_c" / "game.exe").write_text("prefix content")
        (game / "CommonRedist" / "dxsetup.exe").parent.mkdir(parents=True)
        (game / "CommonRedist" / "dxsetup.exe").write_text("redistributable")

        found = self.by_name(SCANNER.scan(self.root), "Imported Game")

        self.assertEqual(found["executable"], "")
        self.assertTrue(found["needsSetup"])
        self.assertEqual(found["candidateExecutables"], [])

    def test_root_level_appimage_is_a_game_entry(self):
        game = self.write("portable-game.AppImage")
        game.chmod(0o755)

        found = self.by_name(SCANNER.scan(self.root), "portable-game")

        self.assertEqual(found["executable"], str(game))
        self.assertFalse(found["needsSetup"])
        self.assertEqual(found["candidateExecutables"][0]["kind"], "native")

    def test_symlinked_game_directory_and_root_prefix_folder_are_ignored(self):
        target = self.root / "Real Game"
        target.mkdir()
        (target / "real-game.exe").write_text("game")
        (self.root / "prefix").mkdir()
        (self.root / "prefix" / "prefix-only.exe").write_text("not a game")
        (self.root / "Linked Game").symlink_to(target, target_is_directory=True)

        names = {game["name"] for game in SCANNER.scan(self.root)["games"]}

        self.assertEqual(names, {"Real Game"})


if __name__ == "__main__":
    unittest.main(verbosity=2)
