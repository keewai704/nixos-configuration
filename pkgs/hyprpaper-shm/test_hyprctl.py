import os
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("hyprctl.py")


def run_with_socket(args, reply):
    with tempfile.TemporaryDirectory() as directory:
        socket_path = Path(directory) / "hypr" / "instance" / ".hyprpaper.sock"
        socket_path.parent.mkdir(parents=True)
        received = []
        failures = []

        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(str(socket_path))
        server.settimeout(3)
        server.listen(1)

        def serve():
            try:
                connection, _ = server.accept()
                with connection:
                    chunks = []
                    while chunk := connection.recv(65536):
                        chunks.append(chunk)
                    received.append(b"".join(chunks).decode())
                    connection.sendall(reply.encode())
            except BaseException as error:
                failures.append(error)

        thread = threading.Thread(target=serve)
        thread.daemon = True
        thread.start()
        environment = os.environ.copy()
        environment.update(
            XDG_RUNTIME_DIR=directory,
            HYPRLAND_INSTANCE_SIGNATURE="instance",
        )
        result = subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            env=environment,
            capture_output=True,
            text=True,
            check=False,
            timeout=3,
        )
        thread.join(timeout=2)
        server.close()

        if thread.is_alive():
            raise AssertionError("legacy IPC server did not finish")
        if failures:
            raise failures[0]
        return result, received[0]


class HyprctlShimTest(unittest.TestCase):
    def test_wallpaper_mapping_listing_and_error_reply(self):
        result, request = run_with_socket(
            ["hyprpaper", "wallpaper", ",/tmp/selected.png"], "ok"
        )
        self.assertEqual(request, "reload ,/tmp/selected.png")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "ok\n")

        result, request = run_with_socket(
            ["hyprpaper", "listactive"], "Virtual-1 = /tmp/selected.png"
        )
        self.assertEqual(request, "listactive")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "Virtual-1 = /tmp/selected.png\n")

        result, _ = run_with_socket(
            ["hyprpaper", "wallpaper", ",/tmp/missing.png"],
            "wallpaper failed (not preloaded)",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not preloaded", result.stderr)


if __name__ == "__main__":
    unittest.main()
