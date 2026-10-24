import fcntl
import hashlib
import json
import os
import stat
import subprocess
import sys
import time
from pathlib import Path

OUTPUT = "SUNSHINE"


def write_atomic(path, contents):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(contents))
    temporary.replace(path)


def identity(output):
    return {
        key: output.get(key)
        for key in ("name", "description", "make", "model", "serial", "config_name")
    }


def workspace_selector(workspace):
    return f"{workspace['index']}/{workspace['output']}"


def logical_workspace(workspace):
    return {key: workspace[key] for key in ("name", "named", "index")}


def same_workspace(saved, current):
    return saved["named"] == current["named"] and (
        saved["name"] == current["name"]
        if saved["named"]
        else saved["index"] == current["index"]
    )


def find_workspace(saved, output_name, workspaces):
    matches = [
        workspace
        for workspace in workspaces
        if workspace["output"] == output_name and same_workspace(saved, workspace)
    ]
    return matches[0] if len(matches) == 1 else None


class DisplayController:
    def __init__(self):
        runtime = Path(os.environ["XDG_RUNTIME_DIR"])
        self.socket = Path(
            os.environ.get("UMBRIEL_SOCKET")
            or runtime / f"umbriel-{os.environ['WAYLAND_DISPLAY']}.sock"
        ).absolute()
        self.session = self.socket_identity()
        self.environment = dict(os.environ, UMBRIEL_SOCKET=str(self.socket))
        session_name = hashlib.sha256(
            json.dumps(self.session, sort_keys=True).encode()
        ).hexdigest()
        self.runtime = runtime / "sunshine-display" / session_name
        self.runtime.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.owner_file = self.runtime / "owner.json"
        self.state_file = self.runtime / "state.json"

    def socket_identity(self):
        metadata = self.socket.stat()
        if not stat.S_ISSOCK(metadata.st_mode) or metadata.st_uid != os.getuid():
            raise RuntimeError("Umbriel IPC must be a socket owned by the current user")
        return {
            "socket": str(self.socket),
            "device": metadata.st_dev,
            "inode": metadata.st_ino,
            "created": metadata.st_ctime_ns,
        }

    def run(self, *args):
        if self.socket_identity() != self.session:
            raise RuntimeError(
                "Umbriel session changed; refusing stale display recovery"
            )
        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=10,
            env=self.environment,
        )
        if result.returncode:
            raise RuntimeError(
                f"{args[0]} failed: {result.stderr.strip() or result.stdout.strip()}"
            )
        return result.stdout.strip()

    def ipc(self, *args):
        return json.loads(self.run("umbriel", *args, "--json"))

    def query(self, command):
        result = self.ipc(command)
        if not isinstance(result, list):
            raise RuntimeError(f"Invalid Umbriel {command} response")
        return result

    def action(self, command, argument):
        self.ipc("msg", f"{command}:{argument}")

    def wait_for(self, predicate, command="outputs"):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            entries = self.query(command)
            if predicate(entries):
                return entries
            time.sleep(0.1)
        raise RuntimeError(f"Umbriel did not apply the requested {command} state")

    def owned_output(self):
        output = next(
            (
                output
                for output in self.query("outputs")
                if output["name"].casefold() == OUTPUT.casefold()
            ),
            None,
        )
        if output is not None:
            owner = (
                json.loads(self.owner_file.read_text())
                if self.owner_file.exists()
                else None
            )
            if owner != {"session": self.session, "output": identity(output)}:
                raise RuntimeError(
                    "An output named SUNSHINE is not owned by this service"
                )
        return output

    def ensure_output(self, width=1920, height=1080, fps=60):
        if self.owned_output() is not None:
            return
        self.owner_file.unlink(missing_ok=True)
        created = self.ipc("output-create", OUTPUT, f"{width}x{height}@{fps}")
        if created != OUTPUT:
            raise RuntimeError("Umbriel did not create the requested SUNSHINE output")
        output = next(
            (output for output in self.query("outputs") if output["name"] == OUTPUT),
            None,
        )
        if output is None:
            raise RuntimeError("The newly created SUNSHINE output is missing")
        write_atomic(
            self.owner_file, {"session": self.session, "output": identity(output)}
        )

    def physical_output(self, previous, outputs):
        matches = [
            output
            for output in outputs
            if output["name"] != OUTPUT
            and (
                output.get("config_name") == previous["config_name"]
                if previous.get("config_name")
                else identity(output) == identity(previous)
            )
        ]
        if len(matches) != 1:
            raise RuntimeError(
                f"Cannot safely identify saved output {previous['name']}"
            )
        return matches[0]

    def restore_outputs(self, state):
        failures = []
        for previous in state["outputs"]:
            try:
                current = self.physical_output(previous, self.query("outputs"))
                if current["enabled"] != previous["enabled"]:
                    self.action(
                        "output-enable" if previous["enabled"] else "output-disable",
                        current["name"],
                    )
                if previous["enabled"]:
                    current = self.physical_output(previous, self.query("outputs"))
                    if any(
                        current[key] != previous[key]
                        for key in ("position", "scale", "transform")
                    ):
                        position = previous["position"]
                        self.run(
                            "wlr-randr",
                            "--output",
                            current["name"],
                            "--pos",
                            f"{position['x']},{position['y']}",
                            "--scale",
                            str(previous["scale"]),
                            "--transform",
                            previous["transform"],
                        )
            except (RuntimeError, OSError, subprocess.SubprocessError) as error:
                failures.append(str(error))
        if failures:
            raise RuntimeError("; ".join(failures))
        self.wait_for(
            lambda outputs: all(
                all(
                    self.physical_output(previous, outputs)[key] == previous[key]
                    for key in (
                        ("enabled", "position", "scale", "transform")
                        if previous["enabled"]
                        else ("enabled",)
                    )
                )
                for previous in state["outputs"]
            )
        )

    def recovered_workspaces(self, state, outputs, verify_focus=False):
        workspaces = self.query("workspaces")
        current_workspaces = {workspace["id"]: workspace for workspace in workspaces}
        windows = {window["id"]: window for window in self.query("windows")}
        restored_outputs = {
            previous["name"]: self.physical_output(previous, outputs)
            for previous in state["outputs"]
            if previous["enabled"]
        }
        for saved in state["windows"]:
            output = restored_outputs.get(saved["output"])
            current = windows.get(saved["id"])
            if output is None or current is None:
                continue
            if current["output"] != output["name"]:
                return False
            if saved["workspace"] is not None:
                workspace = current_workspaces.get(current["workspace"])
                if (
                    workspace is None
                    or workspace["output"] != output["name"]
                    or not same_workspace(saved["workspace"], workspace)
                ):
                    return False
        for saved in state["workspaces"]:
            output = restored_outputs.get(saved["output"])
            if output is None or not saved["active"]:
                continue
            focused_window = windows.get(saved["focused_window"])
            workspace = find_workspace(saved, output["name"], workspaces)
            if saved["active"] or focused_window is not None:
                if workspace is None:
                    return False
                if focused_window is not None:
                    if (
                        focused_window["output"] != output["name"]
                        or focused_window["workspace"] != workspace["id"]
                    ):
                        return False
                    if (
                        verify_focus
                        and workspace["focused_window"] != focused_window["id"]
                    ):
                        return False
                if verify_focus and saved["active"]:
                    if not workspace["active"]:
                        return False
                    if output["focused"]:
                        active = windows.get(workspace["focused_window"])
                        if active is not None:
                            if not active["active"]:
                                return False
                        elif any(window["active"] for window in windows.values()):
                            return False
        if verify_focus:
            for previous in state["outputs"]:
                if previous["enabled"]:
                    if (
                        restored_outputs[previous["name"]]["focused"]
                        != previous["focused"]
                    ):
                        return False
        return True

    def focus_output(self, name, force=False):
        for _attempt in range(len(self.query("outputs")) + 1):
            output = next(
                (output for output in self.query("outputs") if output["name"] == name),
                None,
            )
            if output is None or not output["enabled"]:
                raise RuntimeError(f"Cannot focus restored output {name}")
            if output["focused"]:
                if force:
                    self.ipc("msg", "output-focus-next")
                    force = False
                    continue
                return
            self.ipc("msg", "output-focus-next")
        raise RuntimeError(f"Umbriel did not focus restored output {name}")

    def focus_surviving_window(self, window_id):
        if not any(window["id"] == window_id for window in self.query("windows")):
            return
        try:
            self.action("window-focus", window_id)
        except (RuntimeError, subprocess.SubprocessError):
            if any(window["id"] == window_id for window in self.query("windows")):
                raise

    def restore_workspaces(self, state):
        self.wait_for(lambda outputs: self.recovered_workspaces(state, outputs))
        previous_outputs = {
            previous["name"]: previous
            for previous in state["outputs"]
            if previous["enabled"]
        }
        for previous in previous_outputs.values():
            saved = [
                workspace
                for workspace in state["workspaces"]
                if workspace["output"] == previous["name"] and workspace["active"]
            ]
            if len(saved) != 1:
                raise RuntimeError(
                    f"Saved active workspace on {previous['name']} is ambiguous"
                )
            output = self.physical_output(previous, self.query("outputs"))
            workspace = find_workspace(
                saved[0], output["name"], self.query("workspaces")
            )
            if workspace is None:
                raise RuntimeError(
                    f"Saved logical workspace on {previous['name']} is missing"
                )
            if not workspace["active"]:
                self.action("workspace-switch", workspace_selector(workspace))
            if workspace["focused_window"] != saved[0]["focused_window"]:
                self.focus_surviving_window(saved[0]["focused_window"])
        for previous in previous_outputs.values():
            if previous["focused"]:
                output = self.physical_output(previous, self.query("outputs"))
                saved = next(
                    workspace
                    for workspace in state["workspaces"]
                    if workspace["output"] == previous["name"] and workspace["active"]
                )
                workspace = find_workspace(
                    saved, output["name"], self.query("workspaces")
                )
                if workspace is None:
                    raise RuntimeError(
                        f"Saved logical workspace on {previous['name']} is missing"
                    )
                self.focus_surviving_window(workspace["focused_window"])
                self.focus_output(output["name"], force=not workspace["focused_window"])
        self.wait_for(
            lambda outputs: self.recovered_workspaces(state, outputs, verify_focus=True)
        )

    def evacuate_stream(self, state):
        original_windows = {window["id"] for window in state["windows"]}
        deadline = time.monotonic() + 10
        while True:
            windows = [
                window for window in self.query("windows") if window["output"] == OUTPUT
            ]
            displaced = [
                window for window in windows if window["id"] in original_windows
            ]
            if not displaced:
                break
            if time.monotonic() >= deadline:
                raise RuntimeError(
                    "Physical workspace windows have not returned from SUNSHINE"
                )
            time.sleep(0.1)
        if not windows:
            return
        enabled = {
            self.physical_output(previous, self.query("outputs"))["name"]
            for previous in state["outputs"]
            if previous["enabled"]
        }
        targets = [
            workspace
            for workspace in self.query("workspaces")
            if workspace["output"] in enabled and workspace["active"]
        ]
        targets.sort(key=lambda workspace: not workspace["focused"])
        if not targets:
            raise RuntimeError(
                "No restored physical workspace can receive stream windows"
            )
        selector = workspace_selector(targets[0])
        for window in windows:
            self.action("window-focus", window["id"])
            active = next(
                (
                    entry
                    for entry in self.query("windows")
                    if entry["id"] == window["id"]
                ),
                None,
            )
            if active is None:
                continue
            if not active["active"] or active["output"] != OUTPUT:
                raise RuntimeError("Cannot safely focus a stream window for evacuation")
            self.action("window-move-to-workspace-silent", selector)
        if any(window["output"] == OUTPUT for window in self.query("windows")):
            raise RuntimeError("Stream windows remain on SUNSHINE")

    def restore_power(self, state):
        for previous in state["outputs"]:
            if previous["enabled"]:
                current = self.physical_output(previous, self.query("outputs"))
                self.action(
                    "dpms-on" if previous["powered"] else "dpms-off", current["name"]
                )
        self.wait_for(
            lambda outputs: all(
                all(
                    self.physical_output(previous, outputs)[key] == previous[key]
                    for key in ("enabled", "powered")
                )
                for previous in state["outputs"]
            )
        )

    def destroy_output(self):
        if self.owned_output() is None:
            self.owner_file.unlink(missing_ok=True)
            return
        if any(window["output"] == OUTPUT for window in self.query("windows")):
            raise RuntimeError(
                "Refusing to destroy SUNSHINE while it still contains windows"
            )
        self.ipc("output-destroy", OUTPUT)
        self.wait_for(
            lambda outputs: all(output["name"] != OUTPUT for output in outputs)
        )
        self.owner_file.unlink(missing_ok=True)

    def restore(self):
        if not self.state_file.exists():
            return
        state = json.loads(self.state_file.read_text())
        if state["session"] != self.session:
            raise RuntimeError(
                "Saved recovery state belongs to a different Umbriel session"
            )
        if state.get("version") != 2:
            raise RuntimeError(
                "Saved recovery state lacks safe logical workspace snapshots"
            )
        try:
            self.owned_output()
            self.restore_outputs(state)
            self.wait_for(lambda outputs: self.recovered_workspaces(state, outputs))
            self.evacuate_stream(state)
            self.restore_workspaces(state)
            self.restore_power(state)
            if self.owned_output() is not None:
                self.action("output-disable", OUTPUT)
                self.wait_for(
                    lambda outputs: all(
                        not output["enabled"]
                        for output in outputs
                        if output["name"] == OUTPUT
                    )
                )
            self.restore_power(state)
            self.wait_for(
                lambda outputs: self.recovered_workspaces(
                    state, outputs, verify_focus=True
                )
            )
        except (RuntimeError, OSError, subprocess.SubprocessError) as error:
            raise RuntimeError(
                "Display recovery is incomplete; retaining saved state and any virtual display. "
                "Restart sunshine to retry: " + str(error)
            ) from error
        self.state_file.unlink()

    def prepare(self, mode):
        width = int(os.environ.get("SUNSHINE_CLIENT_WIDTH", "1920"))
        height = int(os.environ.get("SUNSHINE_CLIENT_HEIGHT", "1080"))
        fps = int(os.environ.get("SUNSHINE_CLIENT_FPS", "60"))
        if not (320 <= width <= 7680 and 200 <= height <= 4320 and 10 <= fps <= 240):
            raise ValueError("Unsupported client resolution or refresh rate")
        if width % 2 or height % 2:
            raise ValueError("The stream resolution must have even dimensions")
        self.restore()
        self.owned_output()
        outputs = [
            output for output in self.query("outputs") if output["name"] != OUTPUT
        ]
        workspaces = self.query("workspaces")
        workspace_by_id = {workspace["id"]: workspace for workspace in workspaces}
        windows = self.query("windows")
        enabled_names = {output["name"] for output in outputs if output["enabled"]}
        for window in windows:
            if window["output"] in enabled_names and window["workspace"]:
                workspace = workspace_by_id.get(window["workspace"])
                if workspace is None or workspace["output"] != window["output"]:
                    raise RuntimeError(
                        "Workspace inventory changed while snapshotting; retry preparation"
                    )
        state = {
            "version": 2,
            "session": self.session,
            "outputs": [
                {
                    key: value
                    for key, value in output.items()
                    if key != "active_workspace"
                }
                for output in outputs
            ],
            "workspaces": [
                {key: value for key, value in workspace.items() if key != "id"}
                for workspace in workspaces
                if workspace["output"] != OUTPUT
            ],
            "windows": [
                {
                    "id": window["id"],
                    "output": window["output"],
                    "workspace": (
                        logical_workspace(workspace_by_id[window["workspace"]])
                        if window["workspace"] in workspace_by_id
                        else None
                    ),
                }
                for window in windows
                if window["output"] != OUTPUT
            ],
        }
        write_atomic(self.state_file, state)
        try:
            self.ensure_output(width, height, fps)
            enabled = [output for output in outputs if output["enabled"]]
            right = max(
                (
                    output["position"]["x"] + output["logical_size"]["width"]
                    for output in enabled
                ),
                default=0,
            )
            top = min((output["position"]["y"] for output in enabled), default=0)
            self.run(
                "wlr-randr",
                "--output",
                OUTPUT,
                "--on",
                "--custom-mode",
                f"{width}x{height}@{fps}Hz",
                "--pos",
                f"{right},{top}",
                "--scale",
                "1",
                "--transform",
                "normal",
                "--adaptive-sync",
                "disabled",
            )
            self.action("dpms-on", OUTPUT)
            self.wait_for(
                lambda outputs: any(
                    output["name"] == OUTPUT
                    and output["enabled"]
                    and output["powered"]
                    and output["scale"] == 1
                    and output["transform"] == "normal"
                    and output["adaptive_sync"] is not True
                    and output["position"] == {"x": right, "y": top}
                    and output["logical_size"] == {"width": width, "height": height}
                    and any(
                        mode["current"]
                        and mode["width"] == width
                        and mode["height"] == height
                        and abs(mode["refresh_mhz"] - fps * 1000) < 1000
                        for mode in output["modes"]
                    )
                    for output in outputs
                )
            )
            if mode == "client-only":
                for output in enabled:
                    self.action("output-disable", output["name"])
                self.wait_for(
                    lambda outputs: {
                        output["name"] for output in outputs if output["enabled"]
                    }
                    == {OUTPUT}
                )
            else:
                self.restore_power(state)
            workspace = next(
                workspace
                for workspace in self.query("workspaces")
                if workspace["output"] == OUTPUT and workspace["active"]
            )
            self.action("workspace-switch", workspace_selector(workspace))
        except BaseException:
            self.restore()
            raise

    def main(self, action):
        with (self.runtime / "lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            if action == "init":
                self.restore()
                self.ensure_output()
                if any(window["output"] == OUTPUT for window in self.query("windows")):
                    raise RuntimeError(
                        "Refusing to hide SUNSHINE while it contains windows"
                    )
                self.action("output-disable", OUTPUT)
                self.wait_for(
                    lambda outputs: all(
                        not output["enabled"]
                        for output in outputs
                        if output["name"] == OUTPUT
                    )
                )
            elif action in ("extend", "client-only"):
                self.prepare(action)
            elif action == "restore":
                self.restore()
            elif action == "stop":
                self.restore()
                self.destroy_output()
            else:
                raise ValueError(f"Unknown action: {action}")


if __name__ == "__main__":
    try:
        os.umask(0o077)
        if len(sys.argv) != 2:
            raise ValueError("Expected init, stop, restore, extend, or client-only")
        DisplayController().main(sys.argv[1])
    except (
        KeyError,
        ValueError,
        RuntimeError,
        OSError,
        StopIteration,
        subprocess.SubprocessError,
    ) as error:
        print(f"sunshine-display: {error}", file=sys.stderr)
        sys.exit(1)
