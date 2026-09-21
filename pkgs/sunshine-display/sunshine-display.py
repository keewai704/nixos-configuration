import fcntl
import json
import math
import os
import subprocess
import sys
import time
from pathlib import Path

OUTPUT = "SUNSHINE"


def ipc(*args):
    result = subprocess.run(
        ["hyprctl", *args], capture_output=True, text=True, check=True, timeout=10
    ).stdout.strip()
    if args[0] in ("eval", "output") and result != "ok":
        raise RuntimeError(result)
    return result


def query(command):
    return json.loads(ipc("-j", command))


def lua(value):
    if isinstance(value, str):
        return '"' + "".join(f"\\{byte:03d}" for byte in value.encode()) + '"'
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def rule(**fields):
    return "hl.monitor({" + ",".join(f"{k}={lua(v)}" for k, v in fields.items()) + "})"


def write_atomic(path, contents):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(contents)
    temporary.replace(path)


def wait_for(predicate):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        monitors = query("monitors")
        if predicate(monitors):
            return monitors
        time.sleep(0.1)
    raise RuntimeError("Hyprland did not apply the requested output configuration")


def owned_output(runtime):
    owner_file = runtime / "owner.json"
    owner = json.loads(owner_file.read_text()) if owner_file.exists() else None
    output = next(
        (m for m in json.loads(ipc("-j", "monitors", "all")) if m["name"] == OUTPUT),
        None,
    )
    if output and owner not in (
        {"instance": os.environ["HYPRLAND_INSTANCE_SIGNATURE"], "id": output["id"]},
        {"instance": os.environ["HYPRLAND_INSTANCE_SIGNATURE"], "id": None},
    ):
        raise RuntimeError(
            "An output named SUNSHINE already exists and is not owned by this service"
        )
    if output and output["hardwareDetails"]["backend"] != "headless":
        raise RuntimeError("SUNSHINE must be a headless output")
    return output


def ensure_output(runtime):
    if not owned_output(runtime):
        write_atomic(
            runtime / "owner.json",
            json.dumps(
                {"instance": os.environ["HYPRLAND_INSTANCE_SIGNATURE"], "id": None}
            ),
        )
        ipc(
            "eval",
            rule(
                output=OUTPUT,
                mode="1920x1080@60",
                position="auto",
                scale=1,
                bitdepth=8,
                vrr=0,
            ),
        )
        ipc("output", "create", "headless", OUTPUT)
        wait_for(lambda monitors: any(m["name"] == OUTPUT for m in monitors))
    elif not any(m["name"] == OUTPUT for m in query("monitors")):
        ipc("eval", rule(output=OUTPUT, disabled=False))
        wait_for(lambda monitors: any(m["name"] == OUTPUT for m in monitors))
    output = owned_output(runtime)
    if output:
        write_atomic(
            runtime / "owner.json",
            json.dumps(
                {
                    "instance": os.environ["HYPRLAND_INSTANCE_SIGNATURE"],
                    "id": output["id"],
                }
            ),
        )


def focus(name):
    ipc("eval", f"hl.dispatch(hl.dsp.focus({{monitor={lua(name)}}}))")


def workspace_name(workspace):
    return (
        workspace["name"]
        if workspace["name"].startswith("special:")
        else (
            f"name:{workspace['name']}"
            if workspace.get("type") == "named" or workspace.get("id", 0) < 0
            else workspace["name"]
        )
    )


def restore_layout(state_file):
    layout = state_file.with_name("layout.lua")
    previous = layout.read_text() if layout.exists() else None
    layout.unlink(missing_ok=True)
    try:
        ipc("reload")
        time.sleep(0.2)
        errors = ipc("configerrors")
        if errors:
            raise RuntimeError("Hyprland configuration reload failed: " + errors)
    except BaseException:
        if previous is not None:
            write_atomic(layout, previous)
        raise


def restore(state_file):
    if not state_file.exists():
        if state_file.with_name("layout.lua").exists():
            restore_layout(state_file)
        return
    state = json.loads(state_file.read_text())
    if state["instance"] != os.environ["HYPRLAND_INSTANCE_SIGNATURE"]:
        state_file.with_name("layout.lua").unlink(missing_ok=True)
        state_file.unlink()
        return
    owned_output(state_file.parent)
    failures = []

    def attempt(action, *args, **kwargs):
        try:
            action(*args, **kwargs)
        except (RuntimeError, subprocess.SubprocessError) as error:
            failures.append(str(error))

    restore_layout(state_file)
    names = {m["name"] for m in query("monitors")}
    missing = {m["name"] for m in state["monitors"]} - names
    if missing:
        print(
            "sunshine-display: disconnected outputs will use their configured layout on reconnect: "
            + ", ".join(sorted(missing)),
            file=sys.stderr,
        )
    for workspace in state["workspaces"]:
        if workspace["monitor"] in names:
            attempt(
                ipc,
                "eval",
                "hl.dispatch(hl.dsp.workspace.move({"
                f"monitor={lua(workspace['monitor'])},workspace={lua(workspace_name(workspace))}"
                + "}))",
            )
    for monitor in state["monitors"]:
        if monitor["name"] not in names:
            continue
        active = monitor["activeWorkspace"]
        attempt(
            ipc,
            "eval",
            f"hl.get_monitor({lua(monitor['name'])}):set_workspace({lua(workspace_name(active))})",
        )
        action = "on" if monitor["dpmsStatus"] else "off"
        if action == "off":
            attempt(
                ipc,
                "eval",
                f"hl.dispatch(hl.dsp.dpms({{action='on',monitor={lua(monitor['name'])}}}))",
            )
        attempt(
            ipc,
            "eval",
            f"hl.dispatch(hl.dsp.dpms({{action={lua(action)},monitor={lua(monitor['name'])}}}))",
        )
    focused = next((m["name"] for m in state["monitors"] if m["focused"]), None)
    if focused in names:
        attempt(focus, focused)
    attempt(
        wait_for,
        lambda outputs: all(
            m["dpmsStatus"] == previous["dpmsStatus"]
            for previous in state["monitors"]
            for m in outputs
            if m["name"] == previous["name"]
        ),
    )
    if failures:
        raise RuntimeError(
            "Display recovery is incomplete; keeping the virtual display and saved state. "
            "Restart sunshine to retry: " + "; ".join(failures)
        )
    state_file.unlink()


def prepare(mode, state_file):
    width = int(os.environ.get("SUNSHINE_CLIENT_WIDTH", "1920"))
    height = int(os.environ.get("SUNSHINE_CLIENT_HEIGHT", "1080"))
    fps = int(os.environ.get("SUNSHINE_CLIENT_FPS", "60"))
    if not (320 <= width <= 7680 and 200 <= height <= 4320 and 10 <= fps <= 240):
        raise ValueError("Unsupported client resolution or refresh rate")
    if width % 2 or height % 2:
        raise ValueError("The stream resolution must have even dimensions")
    restore(state_file)
    ensure_output(state_file.parent)
    monitors = query("monitors")
    others = [m for m in monitors if m["name"] != OUTPUT]
    state = {
        "instance": os.environ["HYPRLAND_INSTANCE_SIGNATURE"],
        "monitors": monitors,
        "workspaces": query("workspaces"),
    }
    write_atomic(state_file, json.dumps(state))
    try:
        right = max(
            (
                m["x"]
                + math.ceil(
                    (m["height"] if m["transform"] % 2 else m["width"]) / m["scale"]
                )
                for m in others
            ),
            default=0,
        )
        top = min((m["y"] for m in others), default=0)
        layout = rule(
            output=OUTPUT,
            mode=f"{width}x{height}@{fps}",
            position=f"{right}x{top}",
            scale=1,
            transform=0,
            bitdepth=8,
            vrr=0,
        )
        if mode == "client-only":
            layout += "\n" + "\n".join(
                rule(output=m["name"], disabled=True) for m in others
            )
        layout_file = state_file.with_name("layout.lua")
        write_atomic(layout_file, layout)
        ipc("eval", f"dofile({lua(str(layout_file))})")
        wait_for(
            lambda outputs: any(
                m["name"] == OUTPUT
                and m["width"] == width
                and m["height"] == height
                and abs(m["refreshRate"] - fps) < 1
                for m in outputs
            )
        )
        if mode == "client-only":
            wait_for(lambda outputs: {m["name"] for m in outputs} == {OUTPUT})
        ipc("eval", f"hl.dispatch(hl.dsp.dpms({{action='on',monitor={lua(OUTPUT)}}}))")
        focus(OUTPUT)
    except BaseException:
        restore(state_file)
        raise


def main():
    os.umask(0o077)
    runtime = (
        Path(os.environ["XDG_RUNTIME_DIR"])
        / "sunshine-display"
        / os.environ["HYPRLAND_INSTANCE_SIGNATURE"]
    )
    runtime.mkdir(mode=0o700, parents=True, exist_ok=True)
    state = runtime / "state.json"
    with (runtime / "lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        action = sys.argv[1]
        if action == "init":
            restore(state)
            ensure_output(runtime)
        elif action in ("extend", "client-only"):
            prepare(action, state)
        elif action == "restore":
            restore(state)
        elif action == "stop":
            restore(state)
            if owned_output(runtime):
                ensure_output(runtime)
                ipc("output", "remove", OUTPUT)
            (runtime / "owner.json").unlink(missing_ok=True)
        else:
            raise ValueError(f"Unknown action: {action}")


if __name__ == "__main__":
    try:
        main()
    except (
        KeyError,
        ValueError,
        RuntimeError,
        OSError,
        subprocess.SubprocessError,
    ) as error:
        print(f"sunshine-display: {error}", file=sys.stderr)
        sys.exit(1)
