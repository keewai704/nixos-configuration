import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest


source = os.environ.get("IMPASTO_APPLY_SETTINGS", Path(__file__).with_name("apply-settings.py"))
spec = importlib.util.spec_from_file_location("apply_settings", source)
settings = importlib.util.module_from_spec(spec)
spec.loader.exec_module(settings)


class SettingsMigrationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.state = Path(self.directory.name)

    def save(self, name, value):
        (self.state / name).write_text(json.dumps(value))

    def load(self, name):
        return json.loads((self.state / name).read_text())

    def test_merge_preserves_palette_and_unmanaged_settings(self):
        self.save("settings.json", {
            "palette": "tokyo_night", "language": "es", "barHeight": 40,
            "keys": {settings.OLD_EFFECTS: "", "Open terminal": "SUPER + T"},
        })
        settings.apply({"barHeight": 32}, self.state)
        actual = self.load("settings.json")
        self.assertEqual(actual["palette"], "tokyo_night")
        self.assertEqual(actual["language"], "es")
        self.assertEqual(actual["barHeight"], 32)
        self.assertEqual(actual["keys"], {settings.EFFECTS: "", "Open terminal": "SUPER + T"})

    def test_profiles_and_tsv_keep_overrides_and_are_idempotent(self):
        self.save("profiles.json", {
            "active": "custom", "offered": ["painting"],
            "profiles": [
                {"id": "custom", "wallpaper": "/my/wallpaper", "settings": {
                    "keys": {settings.OLD_EFFECTS: "SUPER + W"}}},
                {"id": "other", "settings": {"keys": {
                    settings.OLD_EFFECTS: "SUPER + W", settings.EFFECTS: ""}}},
            ],
        })
        (self.state / "keys.tsv").write_text(
            f"{settings.OLD_EFFECTS}\tSUPER + W\nOpen terminal\tSUPER + Return\n")
        settings.apply({}, self.state)
        profiles = self.load("profiles.json")
        self.assertEqual(profiles["active"], "custom")
        self.assertEqual(profiles["offered"], ["painting"])
        self.assertEqual(profiles["profiles"][0]["wallpaper"], "/my/wallpaper")
        self.assertEqual(profiles["profiles"][0]["settings"]["keys"], {settings.EFFECTS: "SUPER + W"})
        self.assertEqual(profiles["profiles"][1]["settings"]["keys"], {settings.EFFECTS: ""})
        self.assertEqual((self.state / "keys.tsv").read_text(),
                         f"{settings.EFFECTS}\tSUPER + W\nOpen terminal\tSUPER + Return\n")
        modified = {path.name: path.stat().st_mtime_ns for path in self.state.iterdir()}
        settings.apply({}, self.state)
        self.assertEqual(modified, {path.name: path.stat().st_mtime_ns for path in self.state.iterdir()})

    def test_tsv_keeps_existing_new_description(self):
        path = self.state / "keys.tsv"
        path.write_text(f"{settings.OLD_EFFECTS}\tSUPER + W\n{settings.EFFECTS}\t\n")
        settings.apply({}, self.state)
        self.assertEqual(path.read_text(), f"{settings.EFFECTS}\t\n")

    def test_invalid_existing_json_is_not_replaced(self):
        for value in ("{broken", "[]", "null"):
            with self.subTest(value=value):
                for name in ("settings.json", "profiles.json"):
                    (self.state / name).write_text(value)
                with contextlib.redirect_stderr(io.StringIO()):
                    settings.apply({"barHeight": 32}, self.state)
                for name in ("settings.json", "profiles.json"):
                    self.assertEqual((self.state / name).read_text(), value)

    def test_first_start_creates_only_settings(self):
        state = self.state / "quickshell"
        settings.apply({"idleLock": 0}, state)
        self.assertEqual(json.loads((state / "settings.json").read_text()), {"idleLock": 0})
        self.assertFalse((state / "profiles.json").exists())
        self.assertFalse((state / "keys.tsv").exists())


if __name__ == "__main__":
    unittest.main()
