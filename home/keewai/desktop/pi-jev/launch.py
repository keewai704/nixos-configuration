import json
import os
import subprocess
import sys
import time
import uuid
from pathlib import Path


class StartupError(Exception):
    def __init__(self, reason):
        self.reason = reason


def browser_running(profile):
    try:
        pid = int(os.readlink(profile / "SingletonLock").rsplit("-", 1)[1])
        if pid <= 0:
            return False
        os.kill(pid, 0)
        return True
    except (OSError, ValueError, IndexError):
        return False


def main():
    systemd_run, executable, runner, workspace = sys.argv[1:]
    profile = (
        Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
        / "BraveSoftware"
        / "Brave-Origin"
    )
    for key in tuple(os.environ):
        if key.startswith(("BU_", "BH_", "BROWSER_HARNESS_", "BROWSER_USE_")):
            del os.environ[key]
    os.environ.update(
        BH_HOME=str(Path(workspace) / "harness"),
        BU_NAME="pi-jev",
        BH_TELEMETRY="0",
        BH_UPDATE_CHECK="0",
        BH_TAB_MARKER="0",
    )
    if not browser_running(profile):
        if not (os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY")):
            raise StartupError("desktop_session_required")
        subprocess.run(
            [
                systemd_run,
                "--user",
                "--quiet",
                "--collect",
                "--service-type=exec",
                f"--unit=app-pi-jev-brave-{uuid.uuid4()}",
                executable,
            ],
            check=True,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=10,
        )
    deadline = time.monotonic() + 15
    port_file = profile / "DevToolsActivePort"
    while time.monotonic() < deadline:
        if browser_running(profile):
            try:
                port_line, socket_path = port_file.read_text().splitlines()[:2]
                port = int(port_line)
            except (FileNotFoundError, ValueError):
                time.sleep(0.1)
                continue
            if not 1 <= port <= 65535 or not socket_path.startswith(
                "/devtools/browser/"
            ):
                raise StartupError("invalid_browser_endpoint")
            os.environ["BU_CDP_WS"] = f"ws://127.0.0.1:{port}{socket_path}"
            os.execv(sys.executable, [sys.executable, "-B", runner])
        time.sleep(0.1)
    raise StartupError(
        "browser_setup_required"
        if browser_running(profile)
        else "browser_startup_failed"
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(
            json.dumps(
                {
                    "event": "result",
                    "stop_reason": error.reason
                    if isinstance(error, StartupError)
                    else "browser_startup_failed",
                    "error_type": type(error).__name__,
                    "evidence": None,
                    "hint": "Brave uses its normal profile with no added browser flags. If remote debugging is disabled, enable it yourself at brave://inspect/#remote-debugging and approve the connection when prompted. The launcher never changes browser preferences.",
                }
            ),
            flush=True,
        )
