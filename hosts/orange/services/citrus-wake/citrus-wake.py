import http.client
import os
import socket
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ["CITRUS_WAKE_PORT"])
MAC = bytes.fromhex(os.environ["CITRUS_MAC"].replace(":", ""))
BROADCAST = os.environ["CITRUS_LAN_BROADCAST"]
UPSTREAM = os.environ["CITRUS_MACHINE_LEARNING_URL"].rstrip("/")
ALIVE_URL = os.environ["CITRUS_ALIVE_URL"]
ALIVE_TIMEOUT = 3
PREDICT_TIMEOUT = 280
FAILURES = (OSError, http.client.HTTPException)


def send_magic_packet():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.sendto(b"\xff" * 6 + MAC * 16, (BROADCAST, 9))


def reachable():
    try:
        with urllib.request.urlopen(ALIVE_URL, timeout=ALIVE_TIMEOUT) as response:
            return response.status == 204
    except FAILURES:
        return False


def predict(body, content_type):
    request = urllib.request.Request(f"{UPSTREAM}/predict", body, {"Content-Type": content_type})
    try:
        with urllib.request.urlopen(request, timeout=PREDICT_TIMEOUT) as response:
            return response.status, response.headers.get("Content-Type", "application/json"), response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.headers.get("Content-Type", "text/plain"), error.read()
    except FAILURES:
        return None


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def respond(self, status, content_type, body):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def wake(self):
        send_magic_packet()
        self.respond(202, "text/plain", b"Wake-on-LAN packet sent to citrus\n")

    def do_GET(self):
        if self.path == "/wake":
            self.wake()
        else:
            self.respond(404, "text/plain", b"not found\n")

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.path == "/wake":
            self.wake()
            return
        if self.path != "/predict":
            self.respond(404, "text/plain", b"not found\n")
            return
        content_type = self.headers.get("Content-Type", "application/octet-stream")
        if not reachable():
            self.respond(503, "text/plain", b"citrus is not awake\n")
            return
        result = predict(body, content_type)
        if result is None:
            self.respond(502, "text/plain", b"citrus did not answer\n")
        else:
            self.respond(*result)


ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
