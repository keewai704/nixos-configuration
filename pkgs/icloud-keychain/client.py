import argparse
import getpass
import json
import os
import re
import resource
import select
import ssl
import stat
import struct
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlsplit

from websockets.exceptions import WebSocketException
from websockets.protocol import State
from websockets.sync.client import connect

DEFAULT_SERVER_URL = "@serverUrl@"
CONFIG_DIRECTORY = "icloud-keychain-client"
MAX_MESSAGE = 1024 * 1024
HEADER = struct.Struct("=I")
TOKEN_LENGTH = 43
TOKEN_PATTERN = re.compile(r"[A-Za-z0-9_-]{43}\Z", re.ASCII)
OPEN_TIMEOUT = 10
RECEIVE_TIMEOUT = 30
CLOSE_TIMEOUT = 5
PING_INTERVAL = 20
PING_TIMEOUT = 20
CANONICAL_PATH = "/icloud-keychain/"


def config_directory():
    root = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(root) / CONFIG_DIRECTORY


def token_path():
    return config_directory() / "token"


def valid_token(value):
    return isinstance(value, str) and TOKEN_PATTERN.fullmatch(value) is not None


def prepare_config_directory(directory):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    if not stat.S_ISDIR(directory.lstat().st_mode):
        raise OSError("Token directory is not a directory")
    directory.chmod(0o700)
    return directory


def save_token(value, path=None):
    if not valid_token(value):
        raise ValueError("Invalid bearer token")
    path = token_path() if path is None else Path(path)
    directory = prepare_config_directory(path.parent)
    descriptor, temporary = tempfile.mkstemp(prefix=".token-", dir=directory)
    open_descriptor = descriptor
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            open_descriptor = None
            stream.write(value.encode("ascii"))
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if open_descriptor is not None:
            os.close(open_descriptor)
        Path(temporary).unlink(missing_ok=True)


def load_token(path=None):
    path = token_path() if path is None else Path(path)
    try:
        info = path.lstat()
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_mode & 0o077
            or info.st_size != TOKEN_LENGTH
        ):
            return None
        value = path.read_bytes().decode("ascii")
    except (OSError, UnicodeError):
        return None
    return value if valid_token(value) else None


def configure():
    if not sys.stdin.isatty():
        print("Token configuration requires a TTY.", file=sys.stderr)
        return 1
    try:
        value = getpass.getpass("Bearer token: ")
    except (EOFError, KeyboardInterrupt):
        print("Token configuration failed.", file=sys.stderr)
        return 1
    if not valid_token(value):
        print("Invalid bearer token.", file=sys.stderr)
        return 1
    try:
        save_token(value)
    except (OSError, ValueError):
        print("Token configuration failed.", file=sys.stderr)
        return 1
    print("configured")
    return 0


def status():
    print("configured" if load_token() is not None else "missing")
    return 0


def validate_server_url(value):
    if (
        not isinstance(value, str)
        or not value
        or any(ch.isspace() or ord(ch) < 0x20 for ch in value)
        or "\\" in value
        or "?" in value
        or "#" in value
    ):
        raise ValueError("Invalid WebSocket URL")
    try:
        parsed = urlsplit(value)
        host = parsed.hostname
        if (
            parsed.scheme != "wss"
            or not host
            or parsed.username is not None
            or parsed.password is not None
            or parsed.port not in (None, 443)
            or parsed.path != CANONICAL_PATH
            or parsed.query
            or parsed.fragment
            or "%" in host
        ):
            raise ValueError()
        host.encode("idna")
    except (AttributeError, UnicodeError, ValueError):
        raise ValueError("Invalid WebSocket URL") from None
    return value


def _reject_constant(value):
    raise ValueError("Non-standard JSON constant")


def parse_dictionary(value):
    if not isinstance(value, str):
        raise TypeError("Expected a text JSON message")
    try:
        result = json.loads(value, parse_constant=_reject_constant)
    except (TypeError, ValueError, RecursionError):
        raise ValueError("Invalid JSON message") from None
    if not isinstance(result, dict):
        raise TypeError("Expected a JSON dictionary")
    return result


def read_exact(stream, length):
    result = bytearray()
    while len(result) < length:
        part = stream.read(length - len(result))
        if not isinstance(part, (bytes, bytearray, memoryview)) or not part:
            raise ValueError("Truncated native message")
        if len(part) > length - len(result):
            raise ValueError("Invalid native message stream")
        result.extend(part)
    return bytes(result)


def read_frame(stream):
    first = stream.read(1)
    if first == b"":
        return None
    if not isinstance(first, bytes) or len(first) != 1:
        raise TypeError("Invalid native message header")
    length = HEADER.unpack(first + read_exact(stream, HEADER.size - 1))[0]
    if not 0 < length <= MAX_MESSAGE:
        raise ValueError("Invalid native message size")
    value = read_exact(stream, length).decode("utf-8")
    parse_dictionary(value)
    return value


def response_frame(value):
    if not isinstance(value, str):
        raise TypeError("Expected a text server response")
    payload = value.encode("utf-8")
    if not 0 < len(payload) <= MAX_MESSAGE:
        raise ValueError("Invalid server response size")
    parse_dictionary(value)
    return HEADER.pack(len(payload)) + payload


class NativeInput:
    def __init__(self, stream, connection):
        self.stream = stream
        self.connection = connection
        try:
            self.fd = stream.fileno()
        except (AttributeError, OSError):
            self.fd = None

    def read(self, length):
        if self.fd is None:
            return self.stream.read(length)
        while self.connection.state is State.OPEN:
            if select.select([self.fd], [], [], 0.25)[0]:
                return os.read(self.fd, length)
        return b""


def relay(instream, outstream, token):
    if not valid_token(token):
        raise ValueError("Invalid bearer token")
    url = validate_server_url(DEFAULT_SERVER_URL)
    with connect(
        url,
        ssl=ssl.create_default_context(),
        additional_headers={"Authorization": f"Bearer {token}"},
        proxy=None,
        open_timeout=OPEN_TIMEOUT,
        close_timeout=CLOSE_TIMEOUT,
        ping_interval=PING_INTERVAL,
        ping_timeout=PING_TIMEOUT,
        max_size=MAX_MESSAGE,
        max_queue=4,
    ) as socket:
        socket.socket.settimeout(RECEIVE_TIMEOUT)
        source = NativeInput(instream, socket)
        while True:
            request = read_frame(source)
            if request is None:
                return 0
            socket.send(request)
            response = socket.recv(timeout=RECEIVE_TIMEOUT)
            outstream.write(response_frame(response))
            outstream.flush()


def native_host(instream=None, outstream=None):
    try:
        token = load_token()
        if token is None:
            raise ValueError("Bearer token is not configured")
        if instream is None:
            instream = getattr(sys.stdin, "buffer", sys.stdin)
        if outstream is None:
            outstream = getattr(sys.stdout, "buffer", sys.stdout)
        return relay(instream, outstream, token)
    except KeyboardInterrupt:
        return 130
    except (
        AttributeError,
        LookupError,
        OSError,
        RuntimeError,
        TypeError,
        ValueError,
        WebSocketException,
    ):
        print(
            "Native messaging relay failed; no automatic retry was made.",
            file=sys.stderr,
        )
        return 1


def main(argv=None):
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    arguments = list(sys.argv[1:] if argv is None else argv)
    if arguments and arguments[0] == "native-host":
        return native_host()
    parser = argparse.ArgumentParser(prog="icloud-keychain-client")
    parser.add_argument("command", choices=("configure", "status"))
    args = parser.parse_args(arguments)
    return configure() if args.command == "configure" else status()


if __name__ == "__main__":
    raise SystemExit(main())
