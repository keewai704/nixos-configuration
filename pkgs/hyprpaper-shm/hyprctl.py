#!@PYTHON@

import os
import socket
import sys


REAL_HYPRCTL = "@REAL_HYPRCTL@"
SOCKET_TIMEOUT = 5.0
LIST_COMMANDS = {"listactive", "listloaded"}


def socket_path():
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    instance = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if instance:
        return os.path.join(runtime, "hypr", instance, ".hyprpaper.sock")
    return os.path.join(runtime, "hypr", ".hyprpaper.sock")


def request(command):
    payload = " ".join(command).encode()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(SOCKET_TIMEOUT)
        client.connect(socket_path())
        client.sendall(payload)
        client.shutdown(socket.SHUT_WR)
        chunks = []
        while chunk := client.recv(65536):
            chunks.append(chunk)
    return b"".join(chunks).decode("utf-8", "replace").rstrip("\x00\r\n")


def run_hyprpaper(command):
    if not command:
        print("hyprctl: hyprpaper requires a command", file=sys.stderr)
        return 2

    if command[0] == "wallpaper":
        command = ["reload", *command[1:]]

    try:
        reply = request(command)
    except (OSError, TimeoutError) as error:
        print(f"hyprctl: hyprpaper IPC failed: {error}", file=sys.stderr)
        return 1

    if command[0] in LIST_COMMANDS:
        if reply.startswith("no wallpapers "):
            print(f"hyprctl: {reply}", file=sys.stderr)
            return 1
        if reply:
            print(reply)
        return 0

    if reply == "ok":
        print(reply)
        return 0

    print(f"hyprctl: {reply or 'hyprpaper returned no response'}", file=sys.stderr)
    return 1


def main(argv):
    if not argv or argv[0] != "hyprpaper":
        try:
            os.execv(REAL_HYPRCTL, [REAL_HYPRCTL, *argv])
        except OSError as error:
            print(f"hyprctl: unable to execute real hyprctl: {error}", file=sys.stderr)
            return 1
    return run_hyprpaper(argv[1:])


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
