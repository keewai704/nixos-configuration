import argparse
import base64
import binascii
import contextlib
import fcntl
import hashlib
import hmac
import json
import os
import resource
import secrets
import struct
import subprocess
import sys
import tempfile
from pathlib import Path
from types import SimpleNamespace
from urllib.parse import urlsplit

import nacl.exceptions
import nacl.public
import nacl.secret
import secretstorage

from . import paths, totp
from .auth import session

VERSION = "2.6.1"
MAX_MESSAGE = 1024 * 1024
ATTRIBUTES = {"application": "icp", "type": "master-key"}


class Denied(Exception):
    def __init__(self, code, message):
        self.code = code
        super().__init__(message)


def decode(value, length=None):
    if not isinstance(value, str):
        raise ValueError("Expected base64 string")
    result = base64.b64decode(value, validate=True)
    if length is not None and len(result) != length:
        raise ValueError("Invalid key or nonce length")
    return result


def encode(value):
    return base64.b64encode(value).decode("ascii")


def private_write(path, data):
    fd, temporary = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def master_key(*, interactive=False):
    try:
        connection = secretstorage.dbus_init()
        collection = secretstorage.get_default_collection(connection)
        if collection.is_locked() and (
            not interactive or collection.unlock() or collection.is_locked()
        ):
            raise Denied(1, "Login keyring is locked")
        for item in collection.search_items(ATTRIBUTES):
            key = session._decode_key(item.get_secret())
            if key is None:
                raise Denied(1, "Invalid keyring key; existing data was not changed")
            return key
        encrypted = ("session.enc", "vault.enc", "aliases.enc")
        if not interactive or any(
            (paths.config_dir() / name).exists() for name in encrypted
        ):
            raise Denied(1, "Keyring key missing; existing data was not changed")
        key = secrets.token_bytes(nacl.secret.SecretBox.KEY_SIZE)
        collection.create_item(
            "iCloud Keychain master key",
            ATTRIBUTES,
            encode(key).encode("ascii"),
            replace=False,
        )
        return key
    except Denied:
        raise
    except Exception:
        raise Denied(
            1, "Secret Service unavailable; no plaintext key fallback is permitted"
        ) from None


def lock_path():
    return paths.config_dir() / "keepassxc.locked"


def load_credentials(*, check_browser_lock=True):
    if (
        (check_browser_lock and lock_path().exists())
        or not paths.session_file().exists()
        or not paths.vault_file().exists()
    ):
        raise Denied(
            1, "Vault is locked or not synced; use icloud-keychain login/sync/unlock"
        )
    try:
        box = nacl.secret.SecretBox(master_key())
        data = json.loads(box.decrypt(paths.vault_file().read_bytes()))
        entries = data["credentials"]
        if not isinstance(entries, list) or not all(
            isinstance(entry, dict) for entry in entries
        ):
            raise ValueError()
        return entries
    except Denied:
        raise
    except Exception:
        raise Denied(
            1, "Vault could not be read; existing data was not changed"
        ) from None


@contextlib.contextmanager
def associations():
    path = paths.config_dir() / "keepassxc.json"
    fd = os.open(paths.config_dir() / "keepassxc.guard", os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(fd, "rb") as guard:
        fcntl.flock(guard, fcntl.LOCK_EX)
        state = (
            json.loads(path.read_text())
            if path.exists()
            else {"hash": secrets.token_hex(32), "keys": {}}
        )
        if not isinstance(state.get("hash"), str) or not isinstance(
            state.get("keys"), dict
        ):
            raise ValueError("Invalid association state")
        yield state
        private_write(path, json.dumps(state).encode())


def origin(value, *, stored=False):
    if not isinstance(value, str) or not value or any(ch.isspace() for ch in value):
        raise ValueError("Invalid URL")
    if stored and "://" not in value:
        value = "https://" + value
    parsed = urlsplit(value)
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
    ):
        raise ValueError("Only HTTPS origins without userinfo are supported")
    host = parsed.hostname.encode("idna").decode("ascii").lower()
    if not host or "\\" in host or "%" in host:
        raise ValueError("Invalid hostname")
    return host, parsed.port if parsed.port is not None else 443


def entry_id(entry):
    return hashlib.sha256(
        json.dumps(
            [
                entry.get("domain", ""),
                entry.get("username", ""),
                entry.get("title", ""),
            ],
            ensure_ascii=True,
        ).encode()
    ).hexdigest()[:32]


def approve(key):
    fingerprint = hashlib.sha256(decode(key, 32)).hexdigest()
    try:
        result = subprocess.run(
            [
                "@zenity@",
                "--question",
                "--default-cancel",
                "--timeout=60",
                "--title=iCloud Keychain browser association",
                (
                    "--text=Allow the KeePassXC-Browser connection you just requested?\n"
                    "This grants access to matching website passwords and TOTP codes.\n"
                    f"Identification key SHA-256:\n{fingerprint}"
                ),
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=65,
            check=False,
        )
        return result.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


class Protocol:
    def __init__(self):
        self.box = None
        self.client_id = None
        self.client_key = None
        self.used_nonces = set()
        self.authorized = None
        self.granted = set()

    def handle(self, request):
        action = request.get("action", "") if isinstance(request, dict) else ""
        if not isinstance(action, str) or len(action) > 64:
            action = ""
        try:
            if not isinstance(request, dict):
                raise ValueError()
            client_id = request.get("clientID")
            decode(client_id, 24)
            nonce = decode(request.get("nonce"), 24)
            reply_nonce = ((int.from_bytes(nonce, "little") + 1) % (1 << 192)).to_bytes(
                24, "little"
            )
            if action == "change-public-keys":
                client_key = decode(request.get("publicKey"), 32)
                secret_key = nacl.public.PrivateKey.generate()
                box = nacl.public.Box(secret_key, nacl.public.PublicKey(client_key))
                self.box, self.client_id, self.client_key = box, client_id, client_key
                self.used_nonces = set()
                self.authorized = None
                self.granted.clear()
                return {
                    "action": action,
                    "success": "true",
                    "version": VERSION,
                    "nonce": encode(reply_nonce),
                    "publicKey": encode(bytes(secret_key.public_key)),
                }
            if self.box is None or client_id != self.client_id:
                raise Denied(3, "Public key exchange required")
            if (
                nonce in self.used_nonces
                or reply_nonce in self.used_nonces
                or len(self.used_nonces) >= 65536
            ):
                raise Denied(
                    4, "Repeated nonce or session limit; reconnect the browser"
                )
            payload = json.loads(
                self.box.decrypt(decode(request.get("message")), nonce)
            )
            self.used_nonces.update((nonce, reply_nonce))
            if not isinstance(payload, dict) or payload.get("action") != action:
                raise ValueError()
            result = self.dispatch(action, payload)
            result.update(success="true", version=VERSION, nonce=encode(reply_nonce))
            message = self.box.encrypt(
                json.dumps(result).encode(), reply_nonce
            ).ciphertext
            return {
                "action": action,
                "nonce": encode(reply_nonce),
                "message": encode(message),
            }
        except Denied as error:
            return {"action": action, "errorCode": error.code, "error": str(error)}
        except (
            ValueError,
            TypeError,
            KeyError,
            binascii.Error,
            nacl.exceptions.CryptoError,
        ):
            return {
                "action": action,
                "errorCode": 4,
                "error": "Invalid encrypted request or local state",
            }
        except Exception:
            return {
                "action": action,
                "errorCode": 1,
                "error": "Vault unavailable; no data was returned",
            }

    def dispatch(self, action, payload):
        entries = load_credentials()
        with associations() as state:
            if action == "get-databasehash":
                return {"hash": state["hash"]}
            if action == "associate":
                if not hmac.compare_digest(
                    decode(payload.get("key"), 32), self.client_key
                ):
                    raise Denied(8, "Association key mismatch")
                key = payload.get("idKey")
                decode(key, 32)
                if not approve(key):
                    raise Denied(6, "Browser association denied")
                identifier = secrets.token_hex(16)
                state["keys"][identifier] = key
                self.authorized = (identifier, key)
                return {"id": identifier, "hash": state["hash"]}
            if action == "test-associate":
                identifier, key = payload.get("id"), payload.get("key")
                previous = self.authorized
                self.authorized = None
                if previous != (identifier, key):
                    self.granted.clear()
                self.check_key(state, identifier, key)
                self.authorized = (identifier, key)
                return {"id": identifier, "hash": state["hash"]}
            if action == "get-logins":
                self.authorized = None
                self.granted.clear()
                keys = payload.get("keys")
                if not isinstance(keys, list):
                    raise Denied(10, "Browser is not associated")
                for item in keys:
                    if not isinstance(item, dict):
                        continue
                    try:
                        self.check_key(state, item.get("id"), item.get("key"))
                    except Denied:
                        continue
                    self.authorized = (item["id"], item["key"])
                    break
            if self.authorized is None:
                raise Denied(10, "Browser is not associated")
            self.check_key(state, *self.authorized)
            if action == "lock-database":
                private_write(lock_path(), b"locked\n")
                self.authorized = None
                self.granted.clear()
                raise Denied(1, "Vault locked; use icloud-keychain unlock")
            if action == "get-logins":
                try:
                    page = origin(payload.get("url"))
                    if (
                        payload.get("submitUrl")
                        and origin(payload["submitUrl"]) != page
                    ):
                        raise ValueError()
                except ValueError:
                    raise Denied(
                        14, "An HTTPS URL and same-origin form target are required"
                    ) from None
                result = []
                for entry in entries:
                    try:
                        if origin(entry.get("domain"), stored=True) != page:
                            continue
                    except ValueError:
                        continue
                    identifier = entry_id(entry)
                    code = totp.generate(entry.get("totp", "")).get("code", "")
                    result.append(
                        {
                            "uuid": identifier,
                            "login": entry.get("username", ""),
                            "password": entry.get("password", ""),
                            "name": entry.get("title") or entry["domain"],
                            "totp": code,
                            "expired": "false",
                        }
                    )
                    self.granted.add(identifier)
                return {
                    "entries": result,
                    "count": str(len(result)),
                    "hash": state["hash"],
                }
            if action == "get-totp":
                identifier = payload.get("uuid")
                if not isinstance(identifier, str) or identifier not in self.granted:
                    raise Denied(
                        18, "Retrieve the matching login before requesting its TOTP"
                    )
                for entry in entries:
                    if entry_id(entry) == identifier:
                        code = totp.generate(entry.get("totp", "")).get("code")
                        if code:
                            return {"totp": code, "hash": state["hash"]}
                raise Denied(18, "No TOTP for this entry")
            raise Denied(
                6, "Read-only iCloud Keychain bridge: this action is not supported"
            )

    @staticmethod
    def check_key(state, identifier, key):
        if (
            not isinstance(identifier, str)
            or not isinstance(key, str)
            or identifier not in state["keys"]
            or not hmac.compare_digest(state["keys"][identifier], key)
        ):
            raise Denied(10, "Browser association is unknown or revoked")


def read_exact(stream, length):
    result = bytearray()
    while len(result) < length:
        part = stream.read(length - len(result))
        if not part:
            raise ValueError("Truncated native message")
        result.extend(part)
    return bytes(result)


def serve(instream, outstream):
    protocol = Protocol()
    while True:
        first = instream.read(1)
        if not first:
            return 0
        length = struct.unpack("=I", first + read_exact(instream, 3))[0]
        if not 0 < length <= MAX_MESSAGE:
            raise ValueError("Native message too large")
        request = json.loads(read_exact(instream, length))
        response = protocol.handle(request)
        encoded = json.dumps(response).encode()
        if len(encoded) > MAX_MESSAGE:
            encoded = json.dumps(
                {
                    "action": response["action"],
                    "errorCode": 6,
                    "error": "Response exceeds native messaging limit",
                }
            ).encode()
        outstream.write(struct.pack("=I", len(encoded)) + encoded)
        outstream.flush()


def native_main():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    try:
        return serve(sys.stdin.buffer, sys.stdout.buffer)
    except (ValueError, OSError):
        print("Invalid or closed native messaging stream", file=sys.stderr)
        return 1


def main(argv=None):
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    parser = argparse.ArgumentParser(
        description="Experimental read-only iCloud Keychain / KeePassXC-Browser bridge"
    )
    parser.add_argument(
        "--anisette",
        help="Public HTTPS anisette-v3 URL (default: https://ani.sidestore.io)",
    )
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser(
        "login",
        help="Interactive Apple login and explicitly confirmed escrow recovery; password is not saved",
    )
    commands.add_parser("sync", help="Refresh the encrypted local vault")
    show = commands.add_parser("show", help="Browse the local vault")
    show.add_argument("query", nargs="?")
    show.add_argument("--show-passwords", action="store_true")
    commands.add_parser("lock", help="Block browser access until explicitly unlocked")
    commands.add_parser(
        "unlock", help="Unlock browser access through the login keyring"
    )
    commands.add_parser(
        "logout",
        help="Remove local account tokens, caches and browser associations; keep device identity",
    )
    args = parser.parse_args(argv)
    fd = os.open(paths.config_dir() / "cli.guard", os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(fd, "rb") as guard:
        try:
            fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("Another iCloud Keychain CLI operation is running", file=sys.stderr)
            return 1
        return run_command(args)


def run_command(args):
    try:
        if args.command == "lock":
            private_write(lock_path(), b"locked\n")
            return 0
        if args.command == "logout":
            private_write(lock_path(), b"locked\n")
            with associations() as state:
                state.update(hash=secrets.token_hex(32), keys={})
                for name in ("session.enc", "vault.enc", "aliases.enc"):
                    (paths.config_dir() / name).unlink(missing_ok=True)
            return 0
        master_key(interactive=True)
        session._key_from_secret_service = lambda: master_key(interactive=True)
        if args.command == "unlock":
            if not paths.session_file().exists() or not paths.vault_file().exists():
                raise Denied(1, "Sign in and sync before unlocking the browser")
            nacl.secret.SecretBox(master_key()).decrypt(paths.vault_file().read_bytes())
            lock_path().unlink(missing_ok=True)
            return 0
        if args.command == "show":
            for entry in load_credentials(check_browser_lock=False):
                if (
                    args.query
                    and args.query.casefold()
                    not in " ".join(
                        entry.get(name, "") for name in ("domain", "title", "username")
                    ).casefold()
                ):
                    continue
                values = [
                    entry.get("domain", ""),
                    entry.get("username", ""),
                    entry.get("password", "") if args.show_passwords else "******",
                    totp.generate(entry.get("totp", "")).get("code", ""),
                ]
                print(
                    "\t".join(
                        "".join(ch if ch.isprintable() else "." for ch in value)
                        for value in values
                    )
                )
            return 0
        from .cli import app

        if args.command == "login":
            if not sys.stdin.isatty():
                raise Denied(
                    6, "Login and escrow recovery require an interactive terminal"
                )
            private_write(lock_path(), b"locked\n")
            with associations() as state:
                state.update(hash=secrets.token_hex(32), keys={})
            result = app.cmd_login(
                SimpleNamespace(
                    anisette=args.anisette,
                    username=None,
                    no_save_password=True,
                    debug=False,
                )
            )
            if result == 0:
                print(
                    "Run icloud-keychain unlock, then connect KeePassXC-Browser and approve its dialog."
                )
            return result
        if args.command == "sync":
            return app.cmd_sync(args)
    except KeyboardInterrupt:
        return 130
    except Denied as error:
        print(str(error), file=sys.stderr)
        return 1
    except Exception:
        print(
            "iCloud Keychain operation failed; no automatic retry was made.",
            file=sys.stderr,
        )
        return 1
