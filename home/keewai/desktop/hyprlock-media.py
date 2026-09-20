import asyncio
import html
import sys
import unicodedata

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
    title = text(value(metadata, "xesam:title"), 42) or "Unknown title"
    artists = value(metadata, "xesam:artist", [])
    if not isinstance(artists, list):
        artists = []
    artist = text(
        ", ".join(item[:512] for item in artists[:8] if isinstance(item, str)), 54
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


if __name__ == "__main__":
    try:
        media = asyncio.run(current_media())
    except (OSError, EOFError, AuthError, InvalidAddressError, asyncio.TimeoutError):
        media = {}
    print(render(media, sys.argv[1], sys.argv[2]))
