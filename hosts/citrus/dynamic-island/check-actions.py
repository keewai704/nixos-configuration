#!/usr/bin/env python3
"""Dependency-free parser and subprocess-boundary checks for actions.py."""

from __future__ import annotations

import io
import json
import tempfile
from contextlib import redirect_stdout
from pathlib import Path

import actions


class Result:
    def __init__(self, stdout=b"", stderr=b"", returncode=0):
        self.stdout = stdout
        self.stderr = stderr
        self.returncode = returncode


def main() -> None:
    displays = actions.parse_ddc_detect(
        """
Display 1
   I2C bus: /dev/i2c-3
   DRM connector: DP-1
   Mfg id: DEL
   Model: AW3926QW
   Serial number: CMYQ7K4
Display 2
   I2C bus: 8
   DRM connector: HDMI-A-1
"""
    )
    assert displays == [
        {
            "display": 1,
            "bus": 3,
            "bus_path": "/dev/i2c-3",
            "connector": "DP-1",
            "manufacturer": "DEL",
            "model": "AW3926QW",
            "serial": "CMYQ7K4",
        },
        {"display": 2, "bus": 8, "bus_path": "/dev/i2c-8", "connector": "HDMI-A-1"},
    ]
    assert actions.parse_ddc_brightness("VCP 10 C 25 100") == (25.0, 100.0)
    assert actions.parse_ddc_brightness("current value = 42, max value = 255") == (
        42.0,
        255.0,
    )
    try:
        actions.parse_ddc_brightness("no brightness")
    except ValueError:
        pass
    else:
        raise AssertionError("invalid DDC output was accepted")

    assert actions.parse_brightnessctl_machine(
        "intel_backlight,backlight,800,1000,80%\n"
    ) == {
        "device": "intel_backlight",
        "class": "backlight",
        "current": 800,
        "max": 1000,
        "percent": 80,
    }
    assert (
        actions.parse_active_connector(
            '[{"name":"DP-1","focused":true,"disabled":false}]'
        )
        == "DP-1"
    )
    assert actions.parse_hyprpaper_active(
        "DP-1 = /tmp/wall.png\nDP-2: /tmp/other.png\n"
    ) == [
        {"monitor": "DP-1", "path": "/tmp/wall.png"},
        {"monitor": "DP-2", "path": "/tmp/other.png"},
    ]
    assert actions.BRIGHTNESSCTL == ("brightnessctl", "--class=backlight")

    clients = actions.parse_hypr_clients(
        json.dumps(
            [
                {
                    "address": "0xabc",
                    "class": "kitty",
                    "title": "Terminal",
                    "workspace": {"id": 2, "name": "2"},
                },
                {"address": "0xno-shell", "class": "bad", "title": "skip"},
            ]
        )
    )
    assert clients == [
        {
            "address": "0xabc",
            "title": "Terminal",
            "app": "kitty",
            "workspace": "2",
            "workspace_id": 2,
            "focused": False,
            "mapped": True,
        }
    ]

    opaque_id = "opaque$(touch should-never-run)"
    items = actions.parse_clipboard_list(f"{opaque_id}\t{'x' * 200}\n")
    assert items[0]["id"] == opaque_id
    assert len(items[0]["text"]) == actions.PREVIEW_LIMIT

    calls = []

    def fake_run(argv, **kwargs):
        calls.append((list(argv), kwargs))
        if argv == ["cliphist", "list"]:
            return Result(f"{opaque_id}\tpreview\n".encode())
        if argv[:2] == ["cliphist", "decode"]:
            assert argv[2] == opaque_id
            return Result(b"clipboard bytes")
        if argv == ["wl-copy"]:
            assert kwargs["input_data"] == b"clipboard bytes"
            return Result()
        raise AssertionError(f"unexpected mock command: {argv}")

    original_run = actions.run_command
    actions.run_command = fake_run
    try:
        copied = actions.dispatch(["clipboard-copy", opaque_id])
    finally:
        actions.run_command = original_run
    assert copied == {
        "ok": True,
        "action": "clipboard-copy",
        "id": opaque_id,
        "bytes": 15,
    }
    assert all(call_kwargs.get("shell") is not True for _, call_kwargs in calls)

    calls = []

    def failing_ddc(argv, **kwargs):
        calls.append(list(argv))
        if argv == ["ddcutil", "detect", "--brief"]:
            return Result(b"Display 1\n I2C bus: 3\n DRM connector: DP-1\n")
        if argv == ["hyprctl", "-j", "monitors"]:
            return Result(b'[{"name":"DP-1","focused":true,"disabled":false}]')
        if argv == ["ddcutil", "--bus", "3", "--terse", "getvcp", "10"]:
            return Result(b"VCP 10 C 50 100")
        if argv == ["ddcutil", "--bus", "3", "setvcp", "10", "80"]:
            return Result(returncode=1, stderr=b"DDC write failed")
        raise AssertionError(f"unexpected DDC mock command: {argv}")

    original_run = actions.run_command
    actions.run_command = failing_ddc
    try:
        try:
            actions._brightness_set(80)
        except actions.ActionError as error:
            assert error.code == "command_failed"
        else:
            raise AssertionError("failed DDC write was accepted")
    finally:
        actions.run_command = original_run
    assert not any(call and call[0] == "brightnessctl" for call in calls)

    calls = []
    original_run = actions.run_command
    actions.run_command = failing_ddc
    try:
        try:
            actions._brightness_set(80, bus_name="i2c-3")
        except actions.ActionError as error:
            assert error.code == "command_failed"
        else:
            raise AssertionError("failed explicit-bus write was accepted")
        try:
            actions._brightness_set(80, bus_name="3; echo invalid")
        except actions.ActionError as error:
            assert error.code == "invalid_bus"
        else:
            raise AssertionError("invalid bus was accepted")
    finally:
        actions.run_command = original_run
    assert calls == [
        ["ddcutil", "--bus", "3", "--terse", "getvcp", "10"],
        ["ddcutil", "--bus", "3", "setvcp", "10", "80"],
    ]

    calls = []

    def fake_wallpaper_output(argv, **kwargs):
        calls.append(list(argv))
        return ""

    with tempfile.TemporaryDirectory() as directory:
        wallpaper = Path(directory) / "wall.png"
        wallpaper.write_bytes(b"PNG")
        original_output = actions._output
        original_write_state = actions._write_state
        actions._output = fake_wallpaper_output
        actions._write_state = lambda name, value: None
        try:
            result = actions.wallpaper_set(str(wallpaper))
        finally:
            actions._output = original_output
            actions._write_state = original_write_state
    assert result["ok"] and calls == [
        ["hyprctl", "hyprpaper", "wallpaper", f",{wallpaper}"]
    ]

    output = io.StringIO()
    with redirect_stdout(output):
        code = actions.main(["unknown-action"])
    assert code != 0
    failure = json.loads(output.getvalue())
    assert failure["ok"] is False and failure["action"] == "unknown-action"
    print("action checks passed")


if __name__ == "__main__":
    main()
