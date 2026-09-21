import contextlib
import fcntl
import hashlib
import hmac
import http
import json
import logging
import os
import re
import secrets
import stat
import threading
from urllib.parse import urlsplit

from websockets.exceptions import ConnectionClosed
from websockets.sync.server import serve

from . import paths
from .keepassxc import MAX_MESSAGE, Denied, Protocol, private_write


def load_clients():
    path = paths.config_dir() / "clients.json"
    if not path.exists():
        return {}
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_mode & 0o077 or info.st_size > 65536:
        raise Denied(6, "Client authorization state must be a private regular file")
    clients = json.loads(path.read_text())
    if (
        not isinstance(clients, dict)
        or len(clients) > 64
        or any(
            not isinstance(name, str)
            or not isinstance(digest, str)
            or re.fullmatch(r"[A-Za-z0-9_-]{1,64}", name) is None
            or re.fullmatch(r"[0-9a-f]{64}", digest) is None
            for name, digest in clients.items()
        )
    ):
        raise Denied(6, "Client authorization state is invalid")
    return clients


@contextlib.contextmanager
def client_state():
    fd = os.open(paths.config_dir() / "clients.guard", os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(fd, "rb") as guard:
        fcntl.flock(guard, fcntl.LOCK_EX)
        clients = load_clients()
        yield clients
        private_write(paths.config_dir() / "clients.json", json.dumps(clients).encode())


def manage_client(action, name=None):
    if action == "client-list":
        for name in sorted(load_clients()):
            print(name)
        return 0
    if not isinstance(name, str) or re.fullmatch(r"[A-Za-z0-9_-]{1,64}", name) is None:
        raise Denied(
            6,
            "Use 1-64 ASCII letters, digits, hyphens or underscores for the client name",
        )
    with client_state() as clients:
        if action == "client-add":
            if name in clients or len(clients) >= 64:
                raise Denied(
                    6,
                    "Client already exists or limit reached; revoke it explicitly first",
                )
            token = secrets.token_urlsafe(32)
            clients[name] = hashlib.sha256(token.encode()).hexdigest()
        elif action == "client-revoke":
            if name not in clients:
                raise Denied(6, "Unknown client")
            del clients[name]
        else:
            raise Denied(6, "Unsupported client management action")
    if action == "client-add":
        print(token)
    return 0


def authorized(digest):
    try:
        return any(
            hmac.compare_digest(digest, expected)
            for expected in load_clients().values()
        )
    except Exception:
        return False


class Server:
    def __init__(self, public_url):
        url = urlsplit(public_url)
        if (
            url.scheme != "https"
            or not url.hostname
            or url.port not in (None, 443)
            or url.username is not None
            or url.password is not None
            or url.query
            or url.fragment
            or url.path != "/icloud-keychain/"
            or "\\" in public_url
            or any(ch.isspace() for ch in public_url)
        ):
            raise ValueError("Expected the canonical HTTPS iCloud Keychain URL")
        self.host = url.hostname
        self.path = url.path
        self.slots = threading.BoundedSemaphore(8)

    def process_request(self, connection, request):
        try:
            if request.path != self.path or request.headers.get("Host") != self.host:
                return connection.respond(http.HTTPStatus.NOT_FOUND, "Not found\n")
            if request.headers.get("Origin") is not None:
                return connection.respond(
                    http.HTTPStatus.FORBIDDEN, "Browser origins are not permitted\n"
                )
            authorization = request.headers.get("Authorization", "")
            if re.fullmatch(r"Bearer [A-Za-z0-9_-]{43}", authorization) is None:
                raise ValueError()
            digest = hashlib.sha256(authorization[7:].encode()).hexdigest()
            if not authorized(digest):
                raise ValueError()
            connection.icloud_digest = digest
            return None
        except Exception:
            return connection.respond(
                http.HTTPStatus.UNAUTHORIZED, "Client authorization required\n"
            )

    def handle(self, connection):
        if not self.slots.acquire(blocking=False):
            connection.close(1013, "Connection limit reached")
            return
        try:
            connection.socket.settimeout(30)
            digest = getattr(connection, "icloud_digest", "")
            protocol = Protocol(approve_association=lambda key: authorized(digest))
            for message in connection:
                if not authorized(digest):
                    connection.close(1008, "Client authorization revoked")
                    return
                if not isinstance(message, str) or len(message.encode()) > MAX_MESSAGE:
                    connection.close(1009, "Invalid message size")
                    return
                payload = json.loads(message)
                if not isinstance(payload, dict):
                    raise ValueError()
                response = protocol.handle(payload)
                encoded = json.dumps(response)
                if len(encoded.encode()) > MAX_MESSAGE:
                    encoded = json.dumps(
                        {
                            "action": response["action"],
                            "errorCode": 6,
                            "error": "Response exceeds native messaging limit",
                        }
                    )
                if not authorized(digest):
                    connection.close(1008, "Client authorization revoked")
                    return
                connection.send(encoded)
        except ConnectionClosed:
            pass
        except Exception:
            connection.close(1002, "Invalid protocol message")
        finally:
            self.slots.release()


def run_server(public_url, port):
    if not 1 <= port <= 65535:
        raise ValueError("Invalid loopback port")
    server = Server(public_url)
    logger = logging.getLogger("icp.websocket")
    logger.addHandler(logging.NullHandler())
    logger.propagate = False
    with serve(
        server.handle,
        "127.0.0.1",
        port,
        process_request=server.process_request,
        origins=[None],
        max_size=MAX_MESSAGE,
        max_queue=4,
        open_timeout=10,
        ping_interval=20,
        ping_timeout=20,
        close_timeout=5,
        logger=logger,
    ) as listener:
        listener.serve_forever()
    return 0
