#!/usr/bin/env python3
"""Bounded native desktop actions for the Dynamic Island shell."""

from __future__ import annotations

import fcntl
import json
import math
import os
import re
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager, suppress
from pathlib import Path

COMMAND_TIMEOUT = 5.0
DDC_TIMEOUT = 4.0
LOCK_TIMEOUT = 4.0
SCREENSHOT_TIMEOUT = 120.0
PREVIEW_LIMIT = 160
IMAGE_SUFFIXES = {".avif", ".bmp", ".gif", ".jpeg", ".jpg", ".png", ".svg", ".webp"}
ADDRESS_RE = re.compile(r"0x[0-9a-fA-F]{1,16}\Z")
PROFILE_RE = re.compile(r"[A-Za-z0-9_.-]{1,64}\Z")
BUS_RE = re.compile(r"(?:/dev/)?i2c-(\d+)\Z", re.IGNORECASE)
BRIGHTNESSCTL = ("brightnessctl", "--class=backlight")
COMMANDS = (
    "brightness-status",
    "brightness-set PERCENT",
    "brightness-up",
    "brightness-down",
    "wallpaper-list",
    "wallpaper-set PATH",
    "wallpaper-status",
    "wallpaper-restore",
    "clipboard-list",
    "clipboard-copy ID",
    "clipboard-decode ID",
    "clipboard-delete ID",
    "clipboard-clear",
    "windows-list",
    "window-focus ADDRESS",
    "screenshot-region",
    "screenshot-all",
    "screenshot-active",
    "lock",
    "network",
    "bluetooth",
    "audio",
    "nightlight-status",
    "nightlight-toggle",
    "power-status",
    "power-set PROFILE",
)


class ActionError(Exception):
    def __init__(self, code: str, message: str, details=None):
        super().__init__(message)
        self.code, self.message, self.details = code, message, details


def _short(value, limit=500):
    text = (
        value.decode("utf-8", "replace")
        if isinstance(value, bytes)
        else str(value or "")
    )
    return text.strip()[:limit]


def _ok(action, **data):
    return {"ok": True, "action": action, **data}


def _error(action, error):
    payload = {"code": error.code, "message": error.message}
    if error.details is not None:
        payload["details"] = error.details
    return {"ok": False, "action": action, "error": payload}


def run_command(argv, *, timeout=COMMAND_TIMEOUT, input_data=None, text=True):
    if not argv or any(not isinstance(arg, str) or "\x00" in arg for arg in argv):
        raise ActionError(
            "invalid_command", "The desktop command arguments are invalid"
        )
    try:
        return subprocess.run(
            list(argv),
            input=input_data,
            capture_output=True,
            check=False,
            shell=False,
            text=text,
            timeout=timeout,
        )
    except FileNotFoundError as exc:
        raise ActionError(
            "command_missing", f"Required command is unavailable: {argv[0]}"
        ) from exc
    except subprocess.TimeoutExpired as exc:
        raise ActionError("timeout", f"Command timed out: {argv[0]}") from exc
    except OSError as exc:
        raise ActionError(
            "command_error", f"Could not run {argv[0]}", _short(exc)
        ) from exc


def _output(argv, *, timeout=COMMAND_TIMEOUT, input_data=None, text=True):
    result = run_command(argv, timeout=timeout, input_data=input_data, text=text)
    if result.returncode:
        details = {"returncode": result.returncode}
        if _short(result.stderr):
            details["stderr"] = _short(result.stderr)
        if _short(result.stdout):
            details["stdout"] = _short(result.stdout)
        raise ActionError("command_failed", f"{argv[0]} failed", details)
    return result.stdout or (b"" if not text else "")


def _text(value):
    return (
        value.decode("utf-8", "replace") if isinstance(value, bytes) else (value or "")
    )


def _state_root():
    configured = os.environ.get("XDG_STATE_HOME", "")
    root = (
        Path(configured).expanduser()
        if configured
        else Path.home() / ".local" / "state"
    )
    return (
        root if root.is_absolute() else Path.home() / ".local" / "state"
    ) / "dynamic-island"


def _ensure_state_root():
    root = _state_root()
    try:
        root.mkdir(mode=0o700, parents=True, exist_ok=True)
        root.chmod(0o700)
    except OSError as exc:
        raise ActionError(
            "state_error", "Could not create Dynamic Island state", _short(exc)
        ) from exc
    return root


def _read_state(name):
    try:
        return (_state_root() / name).read_text(encoding="utf-8").strip() or None
    except FileNotFoundError:
        return None
    except OSError as exc:
        raise ActionError(
            "state_error", f"Could not read state: {name}", _short(exc)
        ) from exc


def _write_state(name, value):
    root = _ensure_state_root()
    descriptor, temporary = tempfile.mkstemp(prefix=f".{name}.", dir=root, text=True)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(value + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, root / name)
    except OSError as exc:
        with suppress(OSError):
            os.unlink(temporary)
        raise ActionError(
            "state_error", f"Could not write state: {name}", _short(exc)
        ) from exc


@contextmanager
def _ddc_lock(timeout=LOCK_TIMEOUT):
    try:
        descriptor = os.open(
            _ensure_state_root() / "ddcutil.lock", os.O_RDWR | os.O_CREAT, 0o600
        )
    except OSError as exc:
        raise ActionError(
            "lock_error", "Could not open the DDC lock", _short(exc)
        ) from exc
    deadline = time.monotonic() + timeout
    try:
        while True:
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise ActionError(
                        "lock_timeout", "Timed out waiting for the DDC lock"
                    )
                time.sleep(0.05)
        yield
    finally:
        with suppress(OSError):
            fcntl.flock(descriptor, fcntl.LOCK_UN)
        with suppress(OSError):
            os.close(descriptor)


def _number(value):
    return int(value) if float(value).is_integer() else round(float(value), 2)


def _percent(value):
    return _number(max(0.0, min(100.0, float(value))))


def parse_ddc_detect(output):
    displays, current = [], None
    for line in output.splitlines():
        stripped = line.strip()
        match = re.match(r"(?:Display|Monitor)\s+(\d+)\b", stripped, re.IGNORECASE)
        if match:
            if current and "bus" in current:
                displays.append(current)
            current = {"display": int(match.group(1))}
            continue
        if current is None:
            continue
        lowered = stripped.lower()
        if lowered.startswith("i2c bus:"):
            value = stripped.split(":", 1)[1].strip()
            match = re.search(r"(?:/dev/)?i2c-(\d+)|\b(\d+)\b", value, re.IGNORECASE)
            if match:
                bus = int(match.group(1) or match.group(2))
                current.update(bus=bus, bus_path=f"/dev/i2c-{bus}")
        elif lowered.startswith("drm connector:"):
            current["connector"] = stripped.split(":", 1)[1].strip()
        elif lowered.startswith("mfg id:"):
            current["manufacturer"] = stripped.split(":", 1)[1].strip()
        elif lowered.startswith("model:"):
            current["model"] = stripped.split(":", 1)[1].strip()
        elif lowered.startswith("serial number:"):
            current["serial"] = stripped.split(":", 1)[1].strip()
    if current and "bus" in current:
        displays.append(current)
    unique, seen = [], set()
    for display in displays:
        key = (display["display"], display["bus"])
        if key not in seen:
            seen.add(key)
            unique.append(display)
    return unique


def parse_ddc_brightness(output):
    patterns = (
        r"current\s+value\s*=\s*([0-9]+(?:\.[0-9]+)?)\D+max(?:imum)?\s+value\s*=\s*([0-9]+(?:\.[0-9]+)?)",
        r"\bVCP\s+(?:0x)?10\s+C\s+([0-9]+(?:\.[0-9]+)?)\s+(?:M\s+)?([0-9]+(?:\.[0-9]+)?)\b",
    )
    for pattern in patterns:
        match = re.search(pattern, output, re.IGNORECASE)
        if match:
            current, maximum = map(float, match.groups())
            if 0 <= current <= maximum and maximum > 0:
                return current, maximum
    raise ValueError("No valid VCP 0x10 current/max values found")


def parse_brightnessctl_machine(output):
    for line in output.splitlines():
        fields = line.strip().split(",")
        if len(fields) < 5:
            continue
        try:
            current = int(fields[2])
            if "%" in fields[3]:
                percent = float(
                    re.search(r"([0-9]+(?:\.[0-9]+)?)%", fields[3]).group(1)
                )
                maximum = int(fields[4])
            else:
                maximum = int(fields[3])
                percent = float(
                    re.search(r"([0-9]+(?:\.[0-9]+)?)%", fields[4]).group(1)
                )
        except (AttributeError, ValueError):
            continue
        if maximum > 0 and 0 <= current <= maximum and 0 <= percent <= 100:
            return {
                "device": fields[0],
                "class": fields[1],
                "current": current,
                "max": maximum,
                "percent": _percent(percent),
            }
    return None


def parse_active_connector(output):
    try:
        monitors = json.loads(output)
    except json.JSONDecodeError:
        return None
    monitors = monitors.get("monitors", []) if isinstance(monitors, dict) else monitors
    if not isinstance(monitors, list):
        return None
    for monitor in monitors:
        if (
            isinstance(monitor, dict)
            and monitor.get("focused")
            and not monitor.get("disabled")
            and isinstance(monitor.get("name"), str)
            and monitor["name"]
        ):
            return monitor["name"]
    return None


def parse_hyprpaper_active(output):
    active = []
    for line in output.splitlines():
        line = line.strip()
        if not line:
            continue
        match = re.match(r"(.+?)\s*(?:=|->|:)\s*(.+)\Z", line)
        if match:
            active.append(
                {"monitor": match.group(1).strip(), "path": match.group(2).strip()}
            )
        elif Path(line).is_absolute():
            active.append({"monitor": "", "path": line})
    return active


def parse_hypr_clients(output):
    try:
        clients = json.loads(output)
    except json.JSONDecodeError as exc:
        raise ActionError(
            "invalid_json", "Hyprland returned invalid window data", _short(exc)
        ) from exc
    clients = clients.get("clients", []) if isinstance(clients, dict) else clients
    if not isinstance(clients, list):
        raise ActionError("invalid_json", "Hyprland returned an unexpected window list")
    windows = []
    for client in clients:
        if not isinstance(client, dict) or not ADDRESS_RE.fullmatch(
            str(client.get("address", ""))
        ):
            continue
        workspace = client.get("workspace", {})
        if isinstance(workspace, dict):
            workspace_id, workspace_name = (
                workspace.get("id"),
                workspace.get("name") or workspace.get("id"),
            )
        else:
            workspace_id, workspace_name = None, workspace
        windows.append(
            {
                "address": client["address"],
                "title": str(client.get("title") or client.get("initialTitle") or ""),
                "app": str(client.get("class") or client.get("initialClass") or ""),
                "workspace": str(workspace_name or ""),
                "workspace_id": workspace_id,
                "focused": bool(client.get("focused")),
                "mapped": bool(client.get("mapped", True)),
            }
        )
    return windows


def parse_clipboard_list(output):
    items = []
    for line in output.splitlines():
        line = line.rstrip("\r")
        if not line:
            continue
        parts = line.split("\t", 1) if "\t" in line else line.split(" ", 1)
        item_id, preview = parts[0], parts[1] if len(parts) > 1 else ""
        if item_id:
            items.append({"id": item_id, "text": preview[:PREVIEW_LIMIT]})
    return items


def parse_power_profiles(output):
    profiles = []
    for line in output.splitlines():
        match = re.match(r"\s*\*?\s*([A-Za-z][A-Za-z0-9_.-]*)\s*:?[ \t]*\Z", line)
        if match and match.group(1) not in profiles:
            profiles.append(match.group(1))
    return profiles


def _active_connector():
    try:
        return parse_active_connector(_text(_output(["hyprctl", "-j", "monitors"])))
    except ActionError:
        return None


def _connector_matches(ddc, active):
    if not ddc or not active:
        return False
    ddc, active = ddc.casefold(), active.casefold()
    return ddc == active or ddc.endswith("-" + active) or active.endswith("-" + ddc)


def _select_display(displays, display_name=None, bus_name=None, active=None):
    if display_name is not None:
        matches = [
            d
            for d in displays
            if str(d.get("display")) == display_name
            or str(d.get("connector", "")).casefold() == display_name.casefold()
        ]
        if len(matches) != 1:
            raise ActionError(
                "display_not_found" if not matches else "display_ambiguous",
                f"DDC display target is not unique: {display_name}",
            )
        return matches[0]
    if bus_name is not None:
        match = BUS_RE.fullmatch(bus_name) or re.fullmatch(r"(\d+)", bus_name)
        if not match:
            raise ActionError("invalid_bus", f"Invalid I2C bus target: {bus_name}")
        matches = [d for d in displays if d.get("bus") == int(match.group(1))]
        if len(matches) != 1:
            raise ActionError(
                "bus_not_found" if not matches else "bus_ambiguous",
                f"DDC bus target is not unique: {bus_name}",
            )
        return matches[0]
    for display in displays:
        if _connector_matches(display.get("connector"), active):
            return display
    return displays[0] if displays else None


def _ddc_query(display):
    output = _output(
        ["ddcutil", "--bus", str(display["bus"]), "--terse", "getvcp", "10"],
        timeout=DDC_TIMEOUT,
    )
    try:
        current, maximum = parse_ddc_brightness(_text(output))
    except ValueError as exc:
        raise ActionError(
            "invalid_ddc", "ddcutil returned no usable brightness value", _short(exc)
        ) from exc
    result = dict(display)
    result.update(
        current=_number(current),
        max=_number(maximum),
        percent=_percent(current * 100 / maximum),
    )
    return result


def _ddc_set(display, percent):
    raw = round(float(display["max"]) * percent / 100)
    _output(
        ["ddcutil", "--bus", str(display["bus"]), "setvcp", "10", str(raw)],
        timeout=DDC_TIMEOUT,
    )
    return _ddc_query(display)


def _ddc_snapshot(display_name=None, bus_name=None):
    try:
        with _ddc_lock():
            displays = parse_ddc_detect(
                _text(_output(["ddcutil", "detect", "--brief"], timeout=DDC_TIMEOUT))
            )
            if not displays:
                raise ActionError("no_ddc_display", "No DDC/CI display was detected")
            selected = _select_display(
                displays, display_name, bus_name, _active_connector()
            )
            queried, errors = [], []
            for display in displays:
                try:
                    queried.append(_ddc_query(display))
                except ActionError as exc:
                    failed = dict(display)
                    failed["error"] = exc.message
                    queried.append(failed)
                    errors.append(exc.message)
            selected = next(
                (
                    d
                    for d in queried
                    if d.get("display") == selected.get("display") and "current" in d
                ),
                None,
            )
            if selected is None:
                raise ActionError(
                    "ddc_unavailable", "The selected DDC display could not be read"
                )
            warning = (
                ActionError(
                    "ddc_unavailable",
                    "One or more DDC displays could not be read",
                    errors,
                )
                if errors
                else None
            )
            return queried, selected, warning
    except ActionError as exc:
        return [], None, exc


def _backlight_snapshot():
    try:
        info = parse_brightnessctl_machine(_text(_output([*BRIGHTNESSCTL, "-m"])))
        return (
            (info, None)
            if info
            else (
                None,
                ActionError(
                    "invalid_backlight",
                    "brightnessctl returned no usable backlight value",
                ),
            )
        )
    except ActionError as exc:
        return None, exc


def _brightness_data(display_name=None, bus_name=None):
    displays, selected, ddc_error = _ddc_snapshot(display_name, bus_name)
    backlight, backlight_error = _backlight_snapshot()
    if display_name is not None or bus_name is not None:
        backlight = None
    source = selected or backlight
    data = {
        "available": source is not None,
        "percent": source.get("percent") if source else None,
        "current": source.get("current") if source else None,
        "max": source.get("max") if source else None,
        "backend": "ddc" if selected else ("backlight" if backlight else None),
        "display": selected.get("connector") if selected else None,
        "bus": selected.get("bus") if selected else None,
        "displays": displays,
        "backlight": backlight,
    }
    warnings = [error.message for error in (ddc_error, backlight_error) if error]
    if warnings:
        data["warnings"] = warnings
    if not data["available"]:
        data["error"] = "; ".join(warnings) or "No brightness backend is available"
    return data


def _brightness_result(info, backend, action):
    return _ok(
        action,
        available=True,
        percent=info.get("percent"),
        current=info.get("current"),
        max=info.get("max"),
        backend=backend,
        display=info.get("connector") if backend == "ddc" else None,
        bus=info.get("bus") if backend == "ddc" else None,
    )


def _brightness_set(percent, display_name=None, bus_name=None):
    explicit = display_name is not None or bus_name is not None
    if explicit:
        with _ddc_lock():
            displays = parse_ddc_detect(
                _text(_output(["ddcutil", "detect", "--brief"], timeout=DDC_TIMEOUT))
            )
            selected = _select_display(displays, display_name, bus_name)
            if selected is None:
                raise ActionError(
                    "ddc_unavailable", "The requested DDC display is not available"
                )
            return _ddc_set(_ddc_query(selected), percent), "ddc"

    with _ddc_lock():
        try:
            displays = parse_ddc_detect(
                _text(_output(["ddcutil", "detect", "--brief"], timeout=DDC_TIMEOUT))
            )
            selected = _select_display(displays, active=_active_connector())
        except ActionError:
            selected = None
        if selected:
            try:
                current = _ddc_query(selected)
            except ActionError:
                pass
            else:
                return _ddc_set(current, percent), "ddc"
    _output([*BRIGHTNESSCTL, "set", f"{_number(percent)}%"])
    info, error = _backlight_snapshot()
    if not info:
        raise error or ActionError(
            "backlight_unavailable", "The backlight could not be read after setting it"
        )
    return info, "backlight"


def _brightness_change(delta, display_name=None, bus_name=None):
    explicit = display_name is not None or bus_name is not None
    with _ddc_lock():
        try:
            displays = parse_ddc_detect(
                _text(_output(["ddcutil", "detect", "--brief"], timeout=DDC_TIMEOUT))
            )
            selected = _select_display(
                displays, display_name, bus_name, _active_connector()
            )
        except ActionError:
            if explicit:
                raise
            selected = None
        if selected:
            try:
                current = _ddc_query(selected)
            except ActionError:
                if explicit:
                    raise
            else:
                target = max(0.0, min(100.0, float(current["percent"]) + delta))
                return _ddc_set(current, target), "ddc"
    if explicit:
        raise ActionError(
            "ddc_unavailable", "The requested DDC display is not available"
        )
    info, error = _backlight_snapshot()
    if not info:
        raise error or ActionError(
            "brightness_unavailable", "No brightness backend is available"
        )
    target = max(0.0, min(100.0, float(info["percent"]) + delta))
    _output([*BRIGHTNESSCTL, "set", f"{_number(target)}%"])
    info, error = _backlight_snapshot()
    if not info:
        raise error or ActionError(
            "backlight_unavailable", "The backlight could not be read after setting it"
        )
    return info, "backlight"


def _parse_brightness_options(args, required=False):
    value = display = bus = None
    step = 5.0
    index = 0
    while index < len(args):
        arg = args[index]
        if arg in {"--display", "--bus", "--step"}:
            if index + 1 >= len(args):
                raise ActionError("usage", f"{arg} requires a value")
            option, value_arg = arg, args[index + 1]
            index += 2
        else:
            match = re.fullmatch(r"(--display|--bus|--step)=(.*)", arg)
            if match:
                option, value_arg = match.groups()
                index += 1
            elif arg.startswith("-"):
                raise ActionError("usage", f"Unknown brightness option: {arg}")
            elif value is None:
                value, index = arg, index + 1
                continue
            else:
                raise ActionError("usage", "Brightness accepts one value")
        if option == "--display":
            display = value_arg
        elif option == "--bus":
            bus = value_arg
        else:
            step = _parse_percent(value_arg, "step")
    if display and bus:
        raise ActionError("usage", "Choose either --display or --bus")
    if required and value is None:
        raise ActionError("usage", "Brightness set requires PERCENT")
    return value, display, bus, step


def _parse_percent(value, label="percent"):
    try:
        parsed = float(value)
    except (TypeError, ValueError) as exc:
        raise ActionError("invalid_value", f"Invalid {label}: {value}") from exc
    if not math.isfinite(parsed) or not 0 <= parsed <= 100:
        raise ActionError(
            "invalid_value", f"{label.capitalize()} must be between 0 and 100"
        )
    return parsed


def brightness_action(action, args):
    value, display, bus, step = _parse_brightness_options(
        args, action == "brightness-set"
    )
    if action == "brightness-status":
        return _ok(action, **_brightness_data(display, bus))
    if action == "brightness-set":
        info, backend = _brightness_set(_parse_percent(value), display, bus)
    else:
        info, backend = _brightness_change(
            step if action == "brightness-up" else -step, display, bus
        )
    return _brightness_result(info, backend, action)


def _valid_image(value):
    if not value or any(char in value for char in "\x00,\r\n"):
        raise ActionError("invalid_path", "Wallpaper path is invalid")
    try:
        path = Path(value).expanduser().resolve(strict=True)
    except OSError as exc:
        raise ActionError(
            "invalid_path", "Wallpaper path could not be resolved", _short(exc)
        ) from exc
    if not path.is_file() or path.suffix.lower() not in IMAGE_SUFFIXES:
        raise ActionError("invalid_path", "Wallpaper must be a supported image file")
    return path


def _default_wallpaper():
    value = os.environ.get("ISLAND_DEFAULT_WALLPAPER")
    if not value:
        return None
    try:
        return _valid_image(value)
    except ActionError:
        return None


def wallpaper_list():
    paths = {}
    if default := _default_wallpaper():
        paths[str(default)] = default
    directory = Path.home() / "Pictures" / "Wallpapers"
    try:
        candidates = directory.iterdir() if directory.is_dir() else ()
        for candidate in candidates:
            try:
                image = _valid_image(str(candidate))
            except ActionError:
                continue
            paths[str(image)] = image
    except OSError:
        pass
    return [
        {"name": path.name, "path": str(path)}
        for path in sorted(paths.values(), key=lambda p: (p.name.casefold(), str(p)))
    ]


def wallpaper_set(value):
    path = _valid_image(value)
    _output(["hyprctl", "hyprpaper", "wallpaper", f",{path}"])
    _write_state("wallpaper", str(path))
    return _ok("wallpaper-set", path=str(path))


def wallpaper_status():
    saved = _read_state("wallpaper")
    if saved:
        try:
            saved = str(_valid_image(saved))
        except ActionError:
            saved = None
        else:
            return _ok("wallpaper-status", path=saved, available=True)
    try:
        active = parse_hyprpaper_active(
            _text(_output(["hyprctl", "hyprpaper", "listactive"]))
        )
    except ActionError:
        active = []
    for current in active:
        try:
            path = str(_valid_image(current["path"]))
        except (ActionError, KeyError):
            continue
        return _ok(
            "wallpaper-status",
            path=path,
            monitor=current.get("monitor", ""),
            available=True,
        )
    if default := _default_wallpaper():
        return _ok("wallpaper-status", path=str(default), available=True, default=True)
    raise ActionError(
        "wallpaper_unavailable", "No current or default wallpaper is known"
    )


def wallpaper_action(action, args):
    if action == "wallpaper-list":
        if args:
            raise ActionError("usage", "wallpaper-list takes no arguments")
        return _ok(action, wallpapers=wallpaper_list())
    if action == "wallpaper-status":
        if args:
            raise ActionError("usage", "wallpaper-status takes no arguments")
        result = wallpaper_status()
        result["action"] = action
        return result
    if action == "wallpaper-restore":
        if args:
            raise ActionError("usage", "wallpaper-restore takes no arguments")
        saved = _read_state("wallpaper")
        if saved:
            try:
                saved = str(_valid_image(saved))
            except ActionError:
                saved = None
        if not saved and (default := _default_wallpaper()):
            saved = str(default)
        if not saved:
            raise ActionError(
                "wallpaper_unavailable", "No wallpaper is available to restore"
            )
        result = wallpaper_set(saved)
        result["action"] = action
        return result
    if len(args) != 1:
        raise ActionError("usage", "wallpaper-set requires PATH")
    return wallpaper_set(args[0])


def _clipboard_items():
    return parse_clipboard_list(_text(_output(["cliphist", "list"], text=False)))


def _clipboard_id(items, value):
    if not value or any(char in value for char in "\x00\n\r"):
        raise ActionError("invalid_clipboard_id", "Clipboard item ID is invalid")
    if not any(item["id"] == value for item in items):
        raise ActionError("clipboard_not_found", "Clipboard item was not found")
    return value


def clipboard_action(action, args):
    if action == "clipboard-list":
        if args:
            raise ActionError("usage", "clipboard-list takes no arguments")
        return _ok(action, items=_clipboard_items())
    if action in {"clipboard-copy", "clipboard-decode"}:
        if len(args) != 1:
            raise ActionError("usage", f"{action} requires ID")
        item_id = _clipboard_id(_clipboard_items(), args[0])
        decoded = _output(["cliphist", "decode", item_id], text=False)
        payload = decoded if isinstance(decoded, bytes) else str(decoded).encode()
        _output(["wl-copy"], input_data=payload, text=False)
        return _ok(action, id=item_id, bytes=len(payload))
    if action == "clipboard-delete":
        if len(args) != 1:
            raise ActionError("usage", "clipboard-delete requires ID")
        item_id = _clipboard_id(_clipboard_items(), args[0])
        _output(["cliphist", "delete", item_id])
        return _ok(action, id=item_id)
    if args:
        raise ActionError("usage", "clipboard-clear takes no arguments")
    _output(["cliphist", "wipe"])
    return _ok(action, cleared=True)


def windows_list():
    return parse_hypr_clients(_text(_output(["hyprctl", "-j", "clients"])))


def windows_action(action, args):
    if action == "windows-list":
        if args:
            raise ActionError("usage", "windows-list takes no arguments")
        return _ok(action, windows=windows_list())
    if len(args) != 1 or not ADDRESS_RE.fullmatch(args[0]):
        raise ActionError(
            "invalid_address", "Window address must be 0x followed by 1-16 hex digits"
        )
    address = args[0]
    if not any(
        window["address"].casefold() == address.casefold() for window in windows_list()
    ):
        raise ActionError("window_not_found", "Window address was not found")
    _output(["hyprctl", "dispatch", "focuswindow", f"address:{address}"])
    return _ok(action, address=address)


def screenshot_action(action, args):
    if args:
        raise ActionError("usage", f"{action} takes no arguments")
    target = {
        "screenshot-region": "area",
        "screenshot-all": "screen",
        "screenshot-active": "active",
    }[action]
    time.sleep(0.45)
    _output(["grimblast", "--notify", "copysave", target], timeout=SCREENSHOT_TIMEOUT)
    return _ok(action, target=target)


def _launch(action, command):
    environment = os.environ.copy()
    environment.update(LANG="en_US.UTF-8", LC_ALL="en_US.UTF-8", LANGUAGE="en_US:en")
    try:
        process = subprocess.Popen(
            [command],
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            close_fds=True,
            start_new_session=True,
            shell=False,
        )
    except FileNotFoundError as exc:
        raise ActionError(
            "command_missing", f"Required command is unavailable: {command}"
        ) from exc
    except OSError as exc:
        raise ActionError(
            "command_error", f"Could not start {command}", _short(exc)
        ) from exc
    return _ok(action, launched=True, pid=process.pid)


def nightlight_status():
    output = _text(_output(["hyprctl", "hyprsunset", "temperature"]))
    match = re.search(r"\b(\d{4,5})\b", output)
    if not match:
        raise ActionError("invalid_nightlight", "hyprsunset returned no temperature")
    temperature = int(match.group(1))
    return _ok(
        "nightlight-status", enabled=temperature == 3000, temperature=temperature
    )


def nightlight_action(action, args):
    if args:
        raise ActionError("usage", f"{action} takes no arguments")
    if action == "nightlight-status":
        return nightlight_status()
    state = nightlight_status()
    if state["enabled"]:
        _output(["hyprctl", "hyprsunset", "temperature", "6500"])
        _output(["hyprctl", "hyprsunset", "identity"])
    else:
        _output(["hyprctl", "hyprsunset", "temperature", "3000"])
    result = nightlight_status()
    result["action"] = action
    return result


def power_status():
    output = _text(_output(["powerprofilesctl", "get"]))
    profile = output.strip().splitlines()[0] if output.strip() else ""
    if not PROFILE_RE.fullmatch(profile):
        raise ActionError(
            "invalid_profile", "powerprofilesctl returned no usable profile"
        )
    try:
        profiles = parse_power_profiles(_text(_output(["powerprofilesctl", "list"])))
    except ActionError:
        profiles = []
    if profile not in profiles:
        profiles.insert(0, profile)
    return _ok("power-status", available=True, profile=profile, profiles=profiles)


def power_action(action, args):
    if action == "power-status":
        if args:
            raise ActionError("usage", "power-status takes no arguments")
        return power_status()
    if len(args) != 1 or not PROFILE_RE.fullmatch(args[0]):
        raise ActionError(
            "invalid_profile", "Power profile contains unsupported characters"
        )
    _output(["powerprofilesctl", "set", args[0]])
    result = power_status()
    result["action"] = action
    return result


def dispatch(argv):
    if not argv or argv[0] in {"help", "--help", "-h"}:
        if len(argv) > 1:
            raise ActionError("usage", "help takes no arguments")
        return _ok("help", commands=list(COMMANDS))
    action, args = argv[0], list(argv[1:])
    if action.startswith("brightness-"):
        if action not in {
            "brightness-status",
            "brightness-set",
            "brightness-up",
            "brightness-down",
        }:
            raise ActionError("usage", f"Unknown action: {action}")
        return brightness_action(action, args)
    if action.startswith("wallpaper-"):
        if action not in {
            "wallpaper-list",
            "wallpaper-set",
            "wallpaper-status",
            "wallpaper-restore",
        }:
            raise ActionError("usage", f"Unknown action: {action}")
        return wallpaper_action(action, args)
    if action.startswith("clipboard-"):
        if action not in {
            "clipboard-list",
            "clipboard-copy",
            "clipboard-decode",
            "clipboard-delete",
            "clipboard-clear",
        }:
            raise ActionError("usage", f"Unknown action: {action}")
        return clipboard_action(action, args)
    if action in {"windows-list", "window-focus"}:
        return windows_action(action, args)
    if action in {"screenshot-region", "screenshot-all", "screenshot-active"}:
        return screenshot_action(action, args)
    if action in {"lock", "network", "bluetooth", "audio"}:
        if args:
            raise ActionError("usage", f"{action} takes no arguments")
        return _launch(
            action,
            {
                "lock": "hyprlock",
                "network": "nm-connection-editor",
                "bluetooth": "blueman-manager",
                "audio": "pavucontrol",
            }[action],
        )
    if action.startswith("nightlight-"):
        if action not in {"nightlight-status", "nightlight-toggle"}:
            raise ActionError("usage", f"Unknown action: {action}")
        return nightlight_action(action, args)
    if action.startswith("power-"):
        if action not in {"power-status", "power-set"}:
            raise ActionError("usage", f"Unknown action: {action}")
        return power_action(action, args)
    raise ActionError("unknown_action", f"Unknown desktop action: {action}")


def main(argv=None):
    arguments = list(sys.argv[1:] if argv is None else argv)
    action = arguments[0] if arguments else "help"
    try:
        result, exit_code = dispatch(arguments), 0
    except ActionError as error:
        result, exit_code = _error(action, error), 1
    except KeyboardInterrupt:
        result, exit_code = (
            _error(action, ActionError("interrupted", "Action interrupted")),
            130,
        )
    except Exception as error:  # noqa: BLE001 - Preserve the JSON error contract at the CLI boundary.
        result, exit_code = (
            _error(
                action,
                ActionError(
                    "internal", "Unexpected desktop action failure", _short(error)
                ),
            ),
            1,
        )
    try:
        print(json.dumps(result, ensure_ascii=False, separators=(",", ":")), flush=True)
    except BrokenPipeError:
        return 1
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
