from __future__ import annotations
import importlib.util
from importlib.machinery import SourceFileLoader
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "configs/hypr/scripts/ricelin-game-discovery"
loader = SourceFileLoader("ricelin_game_discovery", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
mod = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(mod)

class DiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.home = Path(self.temp.name) / "home"
        self.home.mkdir(); (self.home / "Games").mkdir(); (self.home / ".config/ricelin").mkdir(parents=True)
    def tearDown(self): self.temp.cleanup()
    def prefix(self, path):
        path.mkdir(parents=True, exist_ok=True); (path / "system.reg").write_text("WINE REGISTRY Version 2\n"); (path / "drive_c").mkdir(exist_ok=True)
    def desktop(self, name, body, path=None):
        p = path or self.home / ".local/share/applications" / name
        p.parent.mkdir(parents=True, exist_ok=True); p.write_text(body); return p

    def test_read_only_registry(self):
        game = self.home / "Games/Example Game"; game.mkdir(); (game / "ExampleGame.exe").write_bytes(b"MZ")
        registry = self.home / ".config/ricelin/applications.json"; registry.write_text("[]\n"); before = registry.read_bytes()
        report = mod.discover(self.home)
        self.assertTrue(report["readOnly"]); self.assertEqual(registry.read_bytes(), before)
        self.assertEqual(report["games"][0]["name"], "Example Game")

    def test_steam_appid_only_and_runtime_filter(self):
        apps = self.home / ".local/share/Steam/steamapps"; (apps / "common/Sample Game").mkdir(parents=True)
        (apps / "appmanifest_12345.acf").write_text('"AppState" {\n "appid" "12345"\n "name" "Sample Game"\n "installdir" "Sample Game"\n "StateFlags" "4"\n}')
        (apps / "common/Proton - Experimental").mkdir()
        (apps / "appmanifest_12346.acf").write_text('"AppState" {\n "appid" "12346"\n "name" "Proton - Experimental"\n "installdir" "Proton - Experimental"\n "StateFlags" "4"\n}')
        steam = [g for g in mod.discover(self.home)["games"] if g["source"] == "steam"]
        self.assertEqual([g["steamAppId"] for g in steam], ["12345"]); self.assertFalse(steam[0]["executable"])

    def test_additional_steam_library(self):
        steam = self.home / ".local/share/Steam"; (steam / "steamapps").mkdir(parents=True)
        lib = self.home / "External Library"; (lib / "steamapps/common/Another Game").mkdir(parents=True)
        (steam / "steamapps/libraryfolders.vdf").write_text('"libraryfolders" {\n "0" { "path" "' + str(steam) + '" }\n "1" { "path" "' + str(lib) + '" }\n}')
        (lib / "steamapps/appmanifest_999.acf").write_text('"AppState" {\n "appid" "999"\n "name" "Another Game"\n "installdir" "Another Game"\n "StateFlags" "4"\n}')
        self.assertIn("999", [g["steamAppId"] for g in mod.discover(self.home)["games"]])

    def test_primary_executable_beats_setup_launcher_and_uninstaller(self):
        game = self.home / "Games/Hollow Knight"; (game / "game").mkdir(parents=True)
        exe = game / "game/hollow_knight.exe"; exe.touch()
        (game / "setup.exe").touch(); (game / "unins000.exe").touch(); (game / "launcher.exe").touch()
        item = next(g for g in mod.discover(self.home)["games"] if g["source"] == "local-directory")
        self.assertEqual(item["executable"], str(exe)); self.assertEqual(item["name"], "Hollow Knight")

    def test_duplicate_loose_exe_is_not_repeated(self):
        game = self.home / "Games/OMORI"; game.mkdir(); (game / "OMORI.exe").touch(); (self.home / "Games/OMORI.exe").touch()
        self.assertEqual(len([g for g in mod.discover(self.home)["games"] if g["name"].casefold() == "omori"]), 1)

    def test_prefix_requires_wine_registry_and_drive_c(self):
        game = self.home / "Games/Undertale"; game.mkdir(); (game / "UNDERTALE.exe").touch()
        fake = game / "prefix"; (fake / "drive_c").mkdir(parents=True)
        self.assertIsNone(next(g for g in mod.discover(self.home)["games"] if g["name"] == "Undertale")["prefix"])
        self.prefix(fake)
        self.assertEqual(next(g for g in mod.discover(self.home)["games"] if g["name"] == "Undertale")["prefix"], str(fake.resolve()))

    def test_quoted_wineprefix_desktop_entry(self):
        prefix = self.home / "Games/wineprefix"; self.prefix(prefix)
        payload = prefix / "drive_c/Games/Example"
        payload.mkdir(parents=True)
        (payload / "Example.exe").touch()
        desktop = self.home / ".local/share/applications/wine/Programs/Example/Example.desktop"
        desktop.parent.mkdir(parents=True)
        desktop.write_text("[Desktop Entry]\nType=Application\nName=Example\n" +
            'Exec=env "WINEPREFIX=' + str(prefix) + '" wine "C:\\\\Games\\\\Example.exe"\n' +
            "Path=" + str(prefix / "drive_c/Games/Example") + "\n")
        found = [g for g in mod.discover(self.home)["games"] if g["source"] == "wine-desktop"]
        self.assertEqual(len(found), 1); self.assertEqual(found[0]["runner"], "wine")
        self.assertEqual(found[0]["prefix"], str(prefix.resolve()))

    def test_user_desktop_utility_filtered(self):
        self.desktop("utility.desktop", "[Desktop Entry]\nType=Application\nName=Proteus 8\nExec=proteus\nCategories=Game;\n")
        self.desktop("other.desktop", "[Desktop Entry]\nType=Application\nName=Editor\nExec=editor\nCategories=Utility;\n")
        self.assertEqual(mod.desktop_candidates(self.home, []), [])

    def test_lutris_source_is_read_only(self):
        folder = self.home / "Games/Lutris Game"; folder.mkdir(); exe = folder / "Game.exe"; exe.touch()
        cfg = self.home / ".config/lutris/games/lutris-game.yml"; cfg.parent.mkdir(parents=True)
        cfg.write_text("name: Lutris Game\ngame:\n  exe: " + str(exe) + "\n")
        registry = self.home / ".config/ricelin/applications.json"; registry.write_text("[]\n"); before = registry.read_bytes()
        self.assertEqual(len([g for g in mod.discover(self.home)["games"] if g["source"] == "lutris"]), 1)
        self.assertEqual(registry.read_bytes(), before)

    def test_steam_desktop_deduplicates_manifest_by_appid(self):
        apps = self.home / ".local/share/Steam/steamapps"; (apps / "common/Sample Game").mkdir(parents=True)
        (apps / "appmanifest_123.acf").write_text('"AppState" {\n "appid" "123"\n "name" "Sample Game"\n "installdir" "Sample Game"\n "StateFlags" "4"\n}')
        self.desktop("sample.desktop", "[Desktop Entry]\nType=Application\nName=Sample Game\nExec=steam steam://rungameid/123\nCategories=Game;\n")
        found = [g for g in mod.discover(self.home)["games"] if g.get("steamAppId") == "123"]
        self.assertEqual(len(found), 1); self.assertEqual(found[0]["source"], "steam"); self.assertEqual(found[0]["desktopEntryId"], "sample.desktop")

    def test_malformed_registry_reported(self):
        (self.home / ".config/ricelin/applications.json").write_text("{broken")
        status = mod.discover(self.home)["registry"]
        self.assertTrue(status["exists"]); self.assertTrue(status["error"])

    def test_legacy_index_is_adapter_to_shared_backend(self):
        folder = self.home / "Games/Example"; folder.mkdir(); (folder / "Example.exe").touch()
        result = mod.scan(self.home / "Games")
        self.assertTrue(result["readOnly"]); self.assertEqual(result["source"], "ricelin-game-discovery")
        self.assertEqual(len(result["games"]), 1); self.assertEqual(result["games"][0]["sourcePath"], str(folder.resolve()))

    def test_ids_are_stable(self):
        folder = self.home / "Games/Stable Game"; folder.mkdir(); (folder / "StableGame.exe").touch()
        self.assertEqual([g["id"] for g in mod.discover(self.home)["games"]], [g["id"] for g in mod.discover(self.home)["games"]])

if __name__ == "__main__": unittest.main()
