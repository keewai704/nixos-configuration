import asyncio
import fcntl
import hashlib
import html
import http.client
import io
import ipaddress
import json
import os
import socket
import ssl
import stat
import subprocess
import sys
import tempfile
import time
import unicodedata
import warnings
from contextlib import closing
from pathlib import Path
from urllib.parse import unquote, urlsplit

from dbus_next import Message, MessageFlag, MessageType, Variant
from dbus_next.aio import MessageBus
from dbus_next.errors import AuthError, InvalidAddressError


def value(properties, key, default=None):
    item = properties.get(key)
    return item.value if isinstance(item, Variant) else default


def text(value, columns):
    if not isinstance(value, str):
        return ""
    value = " ".join(value[:512].split())
    result = ""
    width = 0
    for character in value:
        if unicodedata.category(character).startswith("C"):
            continue
        width += (
            0
            if unicodedata.combining(character)
            else (2 if unicodedata.east_asian_width(character) in ("W", "F") else 1)
        )
        if width > columns or len(result) >= 128:
            result += "…"
            break
        result += character
    return html.escape(result)


def duration(microseconds):
    seconds = microseconds // 1_000_000
    minutes, seconds = divmod(seconds, 60)
    hours, minutes = divmod(minutes, 60)
    return f"{hours}:{minutes:02}:{seconds:02}" if hours else f"{minutes}:{seconds:02}"


def render(properties, accent, muted):
    if value(properties, "PlaybackStatus") != "Playing":
        return ""
    metadata = value(properties, "Metadata", {})
    if not isinstance(metadata, dict):
        metadata = {}
    title = text(value(metadata, "xesam:title"), 36) or "Unknown title"
    artists = value(metadata, "xesam:artist", [])
    if not isinstance(artists, list):
        artists = []
    artist = text(
        ", ".join(item[:512] for item in artists[:8] if isinstance(item, str)), 48
    )
    lines = [
        f'<span foreground="#{accent}" size="small" weight="bold" letter_spacing="2400">♫  NOW PLAYING</span>',
        f'<span size="x-large" weight="bold">{title}</span>',
    ]
    if artist:
        lines.append(f'<span foreground="#{muted}">{artist}</span>')
    length = value(metadata, "mpris:length")
    position = value(properties, "Position")
    if isinstance(length, int) and length > 0 and isinstance(position, int):
        position = min(max(position, 0), length)
        progress = min(23, position * 24 // length)
        bar = (
            f'<span foreground="#{accent}">{"━" * progress}●</span>'
            f'<span foreground="#{muted}">{"━" * (23 - progress)}</span>'
        )
        lines.append(
            f'<span size="small" font_family="monospace" foreground="#{muted}">'
            f"{duration(position)}  {bar}  {duration(length)}</span>"
        )
    return '<span line_height="1.35">' + "\n".join(lines) + "</span>"


def artwork_identity(properties):
    if value(properties, "PlaybackStatus") != "Playing":
        return "", ""
    metadata = value(properties, "Metadata", {})
    if not isinstance(metadata, dict):
        return "", ""
    uri = value(metadata, "mpris:artUrl", "")
    if (
        not isinstance(uri, str)
        or not uri
        or len(uri) > 4096
        or len(uri.encode()) > 4096
    ):
        return "", ""
    identity = [uri]
    for name in ("mpris:trackid", "xesam:title"):
        item = value(metadata, name, "")
        identity.append(item[:4096] if isinstance(item, str) else "")
    try:
        parsed = urlsplit(uri)
    except ValueError:
        return "", ""
    if parsed.scheme == "file" and parsed.netloc in ("", "localhost"):
        try:
            info = Path(unquote(parsed.path)).stat()
            identity.extend([info.st_mtime_ns, info.st_size])
        except (OSError, ValueError):
            pass
    return uri, hashlib.sha256(json.dumps(identity).encode()).hexdigest()


def artwork_bytes(uri):
    limit = 8 * 1024 * 1024
    parsed = urlsplit(uri)
    if parsed.scheme == "file":
        if (
            parsed.netloc not in ("", "localhost")
            or not parsed.path.startswith("/")
            or parsed.query
            or parsed.fragment
        ):
            raise ValueError("Invalid local artwork URL")
        descriptor = os.open(unquote(parsed.path), os.O_RDONLY | os.O_NONBLOCK)
        with os.fdopen(descriptor, "rb") as source:
            info = os.fstat(source.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_size > limit:
                raise ValueError("Artwork is not a bounded regular file")
            data = source.read(limit + 1)
    elif parsed.scheme == "https":
        if (
            not parsed.hostname
            or parsed.username is not None
            or parsed.password is not None
            or parsed.port not in (None, 443)
        ):
            raise ValueError("Invalid HTTPS artwork URL")
        addresses = socket.getaddrinfo(parsed.hostname, 443, type=socket.SOCK_STREAM)
        if not addresses or any(
            not ipaddress.ip_address(item[4][0]).is_global
            or ipaddress.ip_address(item[4][0]).is_multicast
            for item in addresses
        ):
            raise ValueError("Artwork host must be public")
        address = min(addresses, key=lambda item: item[0] != socket.AF_INET)[4][0]
        context = ssl.create_default_context()
        with (
            closing(
                http.client.HTTPSConnection(
                    parsed.hostname, timeout=0.6, context=context
                )
            ) as connection,
            socket.create_connection((address, 443), timeout=0.6) as raw,
        ):
            connection.sock = context.wrap_socket(raw, server_hostname=parsed.hostname)
            target = parsed.path or "/"
            if parsed.query:
                target += "?" + parsed.query
            connection.request(
                "GET",
                target,
                headers={"User-Agent": "Hyprlock artwork", "Accept": "image/*"},
            )
            response = connection.getresponse()
            if (
                response.status != 200
                or int(response.getheader("Content-Length", "0")) > limit
            ):
                raise ValueError("Artwork response rejected")
            data = response.read(limit + 1)
    else:
        raise ValueError("Unsupported artwork URL")
    if len(data) > limit:
        raise ValueError("Artwork exceeds size limit")
    return data


def artwork_worker(uri):
    from PIL import Image, ImageOps

    Image.MAX_IMAGE_PIXELS = 16_000_000
    with warnings.catch_warnings():
        warnings.simplefilter("error", Image.DecompressionBombWarning)
        with Image.open(
            io.BytesIO(artwork_bytes(uri)), formats=["PNG", "JPEG", "WEBP", "GIF"]
        ) as source:
            if source.width * source.height > Image.MAX_IMAGE_PIXELS:
                raise ValueError("Artwork exceeds pixel limit")
            image = ImageOps.fit(
                ImageOps.exif_transpose(source).convert("RGBA"),
                (256, 256),
                method=Image.Resampling.LANCZOS,
            )
            image.info.clear()
            image.save(sys.stdout.buffer, format="PNG")


def atomic_write(path, data):
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as temporary:
        name = Path(temporary.name)
        try:
            temporary.write(data)
            temporary.flush()
            name.replace(path)
        finally:
            name.unlink(missing_ok=True)


def update_artwork(properties, empty):
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        return properties
    cache = Path(runtime) / "hyprlock-media"
    cache.mkdir(mode=0o700, exist_ok=True)
    with (cache / "lock").open("ab") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return properties
        pointer = cache / "artwork-path"
        cover = cache / "cover.png"
        uri, key = artwork_identity(properties)
        if not uri:
            atomic_write(pointer, empty.encode())
            return properties
        try:
            state = json.loads((cache / "state.json").read_text())
            if not isinstance(state, dict):
                state = {}
        except (OSError, ValueError):
            state = {}
        if state.get("key") == key:
            if state.get("ready") and cover.is_file():
                atomic_write(pointer, str(cover).encode())
                return properties
            retry = state.get("retry", 0)
            if isinstance(retry, (int, float)) and time.monotonic() < retry:
                atomic_write(pointer, empty.encode())
                return properties
        atomic_write(pointer, empty.encode())
        try:
            result = subprocess.run(
                [sys.executable, "-B", __file__, "--artwork"],
                input=uri.encode(),
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                timeout=2,
                check=True,
            )
            ready = True
        except (OSError, subprocess.SubprocessError):
            ready = False
        latest = snapshot()
        if artwork_identity(latest)[1] != key:
            return latest
        if ready:
            atomic_write(cache / "state.json", b"{}")
            atomic_write(cover, result.stdout)
        atomic_write(
            cache / "state.json",
            json.dumps(
                {"key": key, "ready": ready, "retry": time.monotonic() + 60}
            ).encode(),
        )
        if ready:
            atomic_write(pointer, str(cover).encode())
        return latest


async def request(bus, destination, path, interface, member, signature="", body=None):
    try:
        reply = await asyncio.wait_for(
            bus.call(
                Message(
                    destination=destination,
                    path=path,
                    interface=interface,
                    member=member,
                    signature=signature,
                    body=body or [],
                    flags=MessageFlag.NO_AUTOSTART,
                )
            ),
            timeout=0.4,
        )
    except (OSError, EOFError, asyncio.TimeoutError):
        return None
    if reply.message_type == MessageType.METHOD_RETURN and reply.body:
        return reply.body[0]
    return None


async def current_media():
    bus = MessageBus()
    try:
        await asyncio.wait_for(bus.connect(), timeout=0.4)
        names = await request(
            bus,
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "ListNames",
        )
        if not isinstance(names, list):
            return {}
        players = sorted(
            name for name in names if name.startswith("org.mpris.MediaPlayer2.")
        )
        snapshots = await asyncio.gather(
            *(
                request(
                    bus,
                    name,
                    "/org/mpris/MediaPlayer2",
                    "org.freedesktop.DBus.Properties",
                    "GetAll",
                    "s",
                    ["org.mpris.MediaPlayer2.Player"],
                )
                for name in players
            )
        )
        return next(
            (
                item
                for item in snapshots
                if isinstance(item, dict) and value(item, "PlaybackStatus") == "Playing"
            ),
            {},
        )
    finally:
        bus.disconnect()


def snapshot():
    try:
        return asyncio.run(current_media())
    except (OSError, EOFError, AuthError, InvalidAddressError, asyncio.TimeoutError):
        return {}


if __name__ == "__main__":
    if sys.argv[1] == "--artwork":
        from PIL import Image

        try:
            uri = sys.stdin.buffer.read(4097)
            if len(uri) > 4096:
                raise ValueError("Artwork URL exceeds size limit")
            artwork_worker(uri.decode())
        except (
            OSError,
            ValueError,
            http.client.HTTPException,
            Image.DecompressionBombWarning,
            Image.DecompressionBombError,
        ):
            sys.exit(1)
    else:
        media = snapshot()
        try:
            media = update_artwork(media, sys.argv[3])
        except (OSError, ValueError):
            pass
        print(render(media, sys.argv[1], sys.argv[2]))
