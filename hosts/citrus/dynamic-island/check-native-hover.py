#!/usr/bin/env python3
"""Check native pointer enter/leave against the running island; restore the pointer."""

import json
import subprocess
import time


def command(*args):
    return subprocess.run(args, text=True, capture_output=True, check=True).stdout


def state():
    return json.loads(command("islandctl", "status"))


monitors = json.loads(command("hyprctl", "-j", "monitors"))
monitor = next((m for m in monitors if m.get("focused")), monitors[0])
view = "island-view-" + monitor["name"]


def geometry():
    return json.loads(
        command("qs", "-c", "dynamic-island", "ipc", "call", view, "geometry")
    )


def move(x, y):
    command(
        "hyprctl", "dispatch", f"hl.dsp.cursor.move({{x={round(x)}, y={round(y)}}})"
    )
    # Hyprland's synthetic warp omits wl_pointer.frame under an exclusive layer.
    # A virtual pointer emits a complete motion frame; return to the target pixel.
    command("wlrctl", "pointer", "move", "1", "0")
    command("wlrctl", "pointer", "move", "-1", "0")
    print(
        "Pointer position:", command("hyprctl", "-j", "cursorpos").strip(), flush=True
    )


def wait_for(predicate):
    deadline = time.monotonic() + 3
    while True:
        info = geometry()
        if predicate(info):
            return info
        assert time.monotonic() < deadline, (
            info,
            command("hyprctl", "-j", "cursorpos"),
        )
        time.sleep(0.08)


initial = json.loads(command("hyprctl", "-j", "cursorpos"))
inside = (monitor["x"] + monitor["width"] / monitor["scale"] / 2, monitor["y"] + 30)
outside = (
    inside[0],
    monitor["y"] + min(700, monitor["height"] / monitor["scale"] - 20),
)
moved = False
try:
    move(*outside)
    moved = True
    time.sleep(0.7)
    move(*inside)
    print(
        "Native hover expanded:",
        wait_for(lambda g: g["hovered"] and g["expanded"]),
        flush=True,
    )
    command("islandctl", "controls")
    wait_for(lambda g: g["state"] == "controls")
    move(*outside)
    print(
        "Native leave collapsed controls:",
        wait_for(lambda g: not g["expanded"] and not g["hovered"]),
        flush=True,
    )
    assert state()["page"] == "", state()
finally:
    if moved:
        move(initial["x"], initial["y"])
        print("Original pointer position restored.", flush=True)
