import base64
import fcntl
import hashlib
import json
import os
import plistlib
import secrets
import ssl
import stat
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit

import requests
from websockets.sync.client import connect

from .. import paths
from ..errors import AppleError

DEFAULT_ANISETTE_URL = "https://ani.sidestore.io"
APPLE_CA = "@appleCa@"
LOOKUP = "https://gsa.apple.com/grandslam/GsService2/lookup"
CLIENT_INFO = "<MacBookPro13,2> <macOS;13.1;22C65> <com.apple.AuthKit/1 (com.apple.dt.Xcode/3594.4.19)>"
LIMIT = 2 * 1024 * 1024


class AnisetteError(AppleError):
    pass


def endpoint(value, *, apple=False):
    try:
        parsed = urlsplit(value)
        host = parsed.hostname or ""
        if (
            not isinstance(value, str)
            or any(ch.isspace() for ch in value)
            or parsed.scheme != "https"
            or not host
            or parsed.username is not None
            or parsed.password is not None
            or parsed.query
            or parsed.fragment
            or "\\" in value
            or "%" in host
            or (parsed.port is not None and parsed.port != 443)
            or (apple and host != "apple.com" and not host.endswith(".apple.com"))
        ):
            raise ValueError()
    except (ValueError, TypeError, AttributeError):
        raise AnisetteError(
            "Expected an HTTPS endpoint without credentials, query or fragment"
        ) from None
    return value.rstrip("/")


def b64(value):
    return base64.b64encode(value).decode("ascii")


def blob(value, *, size=None):
    if not isinstance(value, str) or not value or len(value) > LIMIT // 2:
        raise AnisetteError("Invalid anisette provisioning data")
    try:
        data = base64.b64decode(value, validate=True)
    except ValueError:
        raise AnisetteError("Invalid anisette provisioning data") from None
    if not data or b64(data) != value or (size is not None and len(data) != size):
        raise AnisetteError("Invalid anisette provisioning data")
    return value


def plist_blob(value):
    return blob(b64(value) if isinstance(value, bytes) else value)


def request(method, url, *, apple=False, **kwargs):
    endpoint(url, apple=apple)
    try:
        with requests.Session() as http:
            http.trust_env = False
            with http.request(
                method,
                url,
                timeout=(5, 20),
                allow_redirects=False,
                verify=APPLE_CA if apple else True,
                stream=True,
                **kwargs,
            ) as response:
                if not 200 <= response.status_code < 300:
                    raise AnisetteError(
                        f"Anisette/provisioning HTTP {response.status_code}; no retry made"
                    )
                body = bytearray()
                for chunk in response.iter_content(65536):
                    body.extend(chunk)
                    if len(body) > LIMIT:
                        raise AnisetteError(
                            "Anisette/provisioning response is too large"
                        )
                return bytes(body)
    except requests.RequestException:
        raise AnisetteError(
            "Anisette/provisioning HTTPS request failed; no retry made"
        ) from None


def save(path, value):
    fd, name = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


class Anisette:
    def __init__(self, url=None):
        self.url = endpoint(
            url or os.environ.get("ICP_ANISETTE_URL") or DEFAULT_ANISETTE_URL
        )

    def headers(self):
        try:
            directory = paths.config_dir()
            fd = os.open(directory / "anisette-v3.guard", os.O_CREAT | os.O_RDWR, 0o600)
            with os.fdopen(fd, "rb") as guard:
                try:
                    fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    raise AnisetteError(
                        "Another anisette operation is running"
                    ) from None
                path = directory / "anisette-v3.json"
                if path.exists():
                    info = path.lstat()
                    if (
                        not stat.S_ISREG(info.st_mode)
                        or info.st_mode & 0o077
                        or info.st_size > LIMIT
                    ):
                        raise AnisetteError(
                            "Anisette state must be a private regular file"
                        )
                    state = json.loads(path.read_text())
                    if state.get("url") != self.url:
                        raise AnisetteError(
                            "Anisette state belongs to another server; it was not transmitted"
                        )
                    blob(state.get("identifier"), size=16)
                    if not state.get("adi_pb"):
                        raise AnisetteError(
                            "Provisioning was interrupted; inspect or move anisette-v3.json before retrying explicitly"
                        )
                    blob(state["adi_pb"])
                else:
                    state = {
                        "url": self.url,
                        "identifier": b64(secrets.token_bytes(16)),
                        "adi_pb": None,
                    }
                    save(path, state)
                    state["adi_pb"] = self.provision(state["identifier"])
                    save(path, state)
                response = json.loads(
                    request(
                        "POST",
                        self.url + "/v3/get_headers",
                        json={
                            "identifier": state["identifier"],
                            "adi_pb": state["adi_pb"],
                        },
                    )
                )
                result = {
                    name: blob(response.get(name))
                    for name in ("X-Apple-I-MD", "X-Apple-I-MD-M")
                }
                rinfo = str(response.get("X-Apple-I-MD-RINFO", "17106176"))
                if not rinfo.isascii() or not rinfo.isdigit() or len(rinfo) > 20:
                    raise AnisetteError("Invalid anisette routing information")
                identifier = base64.b64decode(state["identifier"])
                result.update(
                    {
                        "X-Apple-I-MD-RINFO": rinfo,
                        "X-Mme-Device-Id": str(uuid.UUID(bytes=identifier)).upper(),
                        "X-Apple-I-MD-LU": hashlib.sha256(identifier)
                        .hexdigest()
                        .upper(),
                    }
                )
                return result
        except AnisetteError:
            raise
        except Exception:
            raise AnisetteError(
                "Anisette operation failed; state was preserved and no retry made"
            ) from None

    def provision(self, identifier):
        headers = {
            "X-Mme-Client-Info": CLIENT_INFO,
            "User-Agent": "akd/1.0 CFNetwork/808.1.4",
            "X-Mme-Device-Id": str(
                uuid.UUID(bytes=base64.b64decode(identifier))
            ).upper(),
            "X-Apple-I-MD-LU": hashlib.sha256(base64.b64decode(identifier))
            .hexdigest()
            .upper(),
            "X-Apple-I-Client-Time": datetime.now(timezone.utc)
            .replace(microsecond=0)
            .isoformat()
            .replace("+00:00", "Z"),
            "Content-Type": "text/x-xml-plist",
        }
        bag = plistlib.loads(request("GET", LOOKUP, apple=True, headers=headers))[
            "urls"
        ]
        start = endpoint(bag["midStartProvisioning"], apple=True)
        finish = endpoint(bag["midFinishProvisioning"], apple=True)
        with connect(
            "wss://" + self.url.removeprefix("https://") + "/v3/provisioning_session",
            ssl=ssl.create_default_context(),
            proxy=None,
            open_timeout=15,
            close_timeout=5,
            max_size=LIMIT,
            ping_interval=None,
        ) as socket:
            self.expect(socket, "GiveIdentifier")
            socket.send(json.dumps({"identifier": identifier}))
            self.expect(socket, "GiveStartProvisioningData")
            response = self.apple_provision(start, {}, headers)
            socket.send(json.dumps({"spim": plist_blob(response["spim"])}))
            end = self.expect(socket, "GiveEndProvisioningData")
            response = self.apple_provision(
                finish, {"cpim": blob(end.get("cpim"))}, headers
            )
            socket.send(
                json.dumps(
                    {
                        "ptm": plist_blob(response["ptm"]),
                        "tk": plist_blob(response["tk"]),
                    }
                )
            )
            return blob(self.expect(socket, "ProvisioningSuccess").get("adi_pb"))

    @staticmethod
    def apple_provision(url, payload, headers):
        body = plistlib.dumps({"Header": {}, "Request": payload})
        return plistlib.loads(
            request("POST", url, apple=True, headers=headers, data=body)
        )["Response"]

    @staticmethod
    def expect(socket, expected):
        message = socket.recv(timeout=20)
        if not isinstance(message, str) or len(message) > LIMIT:
            raise AnisetteError("Invalid anisette provisioning message")
        result = json.loads(message)
        if not isinstance(result, dict) or result.get("result") != expected:
            raise AnisetteError("Unexpected anisette provisioning state; no retry made")
        return result
