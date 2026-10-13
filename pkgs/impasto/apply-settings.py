#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
import tempfile


OLD_EFFECTS = "Island · Open the wallpaper effects"
EFFECTS = "Shell · Open the wallpaper effects"


def read_object(path):
    try:
        value = json.loads(path.read_text())
        if not isinstance(value, dict):
            raise ValueError("expected a JSON object")
        return value
    except FileNotFoundError:
        return {}
    except (OSError, ValueError) as error:
        print(f"impasto: leaving {path} unchanged: {error}", file=sys.stderr)
        return None


def write_changed(path, text):
    if path.exists() and path.read_text() == text:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as output:
        temporary = Path(output.name)
        try:
            output.write(text)
            output.flush()
            os.fsync(output.fileno())
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


def migrate_keys(settings):
    if not isinstance(settings, dict):
        return
    keys = settings.get("keys")
    if isinstance(keys, dict) and OLD_EFFECTS in keys:
        keys.setdefault(EFFECTS, keys.pop(OLD_EFFECTS))


def write_json(path, value):
    write_changed(path, json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def apply(declared, state):
    state = Path(state)
    settings_path = state / "settings.json"
    settings = read_object(settings_path)
    if settings is not None:
        migrate_keys(settings)
        settings.update(declared)
        write_json(settings_path, settings)

    profiles_path = state / "profiles.json"
    if profiles_path.exists():
        profiles = read_object(profiles_path)
        if profiles is not None:
            entries = profiles.get("profiles", [])
            if isinstance(entries, list):
                for entry in entries:
                    if isinstance(entry, dict):
                        migrate_keys(entry.get("settings"))
            write_json(profiles_path, profiles)

    keys_path = state / "keys.tsv"
    if keys_path.exists():
        lines = keys_path.read_text().splitlines(keepends=True)
        has_effects = any(line.startswith(EFFECTS + "\t") for line in lines)
        migrated = []
        for line in lines:
            if line.startswith(OLD_EFFECTS + "\t"):
                if has_effects:
                    continue
                line = EFFECTS + line[len(OLD_EFFECTS):]
            migrated.append(line)
        write_changed(keys_path, "".join(migrated))


if __name__ == "__main__":
    declared = read_object(Path(sys.argv[1]))
    if declared is not None:
        apply(declared, sys.argv[2])
