import json
import os
import subprocess
import sys
import time
from pathlib import Path


def main():
    executable, runner, workspace = sys.argv[1:]
    workspace = Path(workspace)
    profile = workspace / "profile"
    for key in tuple(os.environ):
        if key.startswith(("BU_", "BH_", "BROWSER_HARNESS_", "BROWSER_USE_")):
            del os.environ[key]
    os.environ.update(
        BH_HOME=str(workspace / "harness"),
        BU_NAME="pi-jev",
        BH_TELEMETRY="0",
        BH_UPDATE_CHECK="0",
        BH_TAB_MARKER="0",
    )
    browser_environment = {
        key: value
        for key, value in os.environ.items()
        if not key.startswith(("TYPESAFE_", "TEXT_MODEL_"))
    }
    arguments = [
        executable,
        f"--user-data-dir={profile}",
        "--remote-debugging-address=127.0.0.1",
        "--remote-debugging-port=0",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-background-networking",
        "--disable-component-update",
        "--password-store=basic",
    ]
    if not (os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY")):
        arguments.append("--headless=new")
    browser = subprocess.Popen(
        [*arguments, "about:blank"],
        env=browser_environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    deadline = time.monotonic() + 15
    port_file = profile / "DevToolsActivePort"
    while time.monotonic() < deadline:
        if browser.poll() is not None:
            raise RuntimeError("browser_exited")
        try:
            port = int(port_file.read_text().splitlines()[0])
        except (FileNotFoundError, IndexError, ValueError):
            time.sleep(0.05)
            continue
        if not 1 <= port <= 65535:
            raise ValueError("invalid_port")
        os.environ["BU_CDP_URL"] = f"http://127.0.0.1:{port}"
        os.execv(sys.executable, [sys.executable, "-B", runner])
    raise TimeoutError("browser_startup_timeout")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(
            json.dumps(
                {
                    "event": "result",
                    "stop_reason": "browser_startup_failed",
                    "error_type": type(error).__name__,
                    "evidence": None,
                }
            ),
            flush=True,
        )
