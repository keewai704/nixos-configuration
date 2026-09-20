import argparse
import asyncio
import fcntl
import io
import json
import logging
import os
import signal
import struct
import sys
import tempfile
import termios
import uuid
from contextlib import AsyncExitStack, asynccontextmanager, contextmanager
from pathlib import Path

from PIL import Image
from pymobiledevice3.remote.core_device.device_info import DeviceInfoService
from pymobiledevice3.remote.core_device.display_service import DisplayService
from pymobiledevice3.remote.core_device.hid_service import (
    ASCII_TO_HID,
    HID_BUTTON_STATE_DOWN,
    HID_BUTTON_STATE_UP,
    KEY_LEFT_GUI,
    KEY_LEFT_SHIFT,
    TOUCHSCREEN_STATE_CONTACT,
    TOUCHSCREEN_STATE_RELEASE,
    IndigoHIDService,
    UniversalHIDServiceService,
)
from pymobiledevice3.remote.core_device.pasteboard_service import PasteboardService
from pymobiledevice3.remote.core_device.screen_stream import open_media_receiver
from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
from pymobiledevice3.services.dvt.instruments.screenshot import Screenshot

from connection import MODES, get_tunnel, select_connection


def emit(**result):
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":")), flush=True)


@asynccontextmanager
async def media_hid_session(rsd, display_id):
    async with DisplayService(rsd) as display:
        transport, receiver_ip = open_media_receiver(display, (1024 * 1024,))
        session_id = uuid.uuid4()
        highest_sequence = None

        async def drain():
            nonlocal highest_sequence
            while True:
                data = await transport.recv()
                if len(data) < 12 or 64 <= (data[1] & 127) <= 95:
                    continue
                sequence = int.from_bytes(data[2:4], "big")
                if highest_sequence is None:
                    highest_sequence = sequence
                else:
                    delta = ((sequence - highest_sequence + 32768) & 65535) - 32768
                    if delta > 0:
                        highest_sequence += delta

        async def feedback(config):
            local, remote = int(config["RemoteSSRC"]), int(config["LocalSSRC"])
            source = struct.pack("!BBHIBBBB", 0x81, 202, 2, local, 1, 0, 0, 0)
            while True:
                report = struct.pack(
                    "!BBHIIIIIII",
                    0x81,
                    201,
                    7,
                    local,
                    remote,
                    0,
                    (highest_sequence or 0) & 0xFFFFFFFF,
                    0,
                    0,
                    0,
                )
                await transport.sendto(
                    report + source, rsd.service.address[0], int(config["SourcePort"])
                )
                await asyncio.sleep(1)

        try:
            async with asyncio.TaskGroup() as tasks:
                receiver = tasks.create_task(drain())
                keepalive = None
                try:
                    answer = await asyncio.wait_for(
                        display.start_video_stream(
                            receiver_ip=receiver_ip,
                            receiver_port=transport.port,
                            sender_ip=rsd.service.address[0],
                            display_id=display_id,
                            client_session_id=session_id,
                            allow_rtcp_fb=False,
                            ltrp_enabled=False,
                        ),
                        timeout=30,
                    )
                    keepalive = tasks.create_task(
                        feedback(answer["connection"]["streamConfig"])
                    )
                    await asyncio.sleep(0.3)
                    async with UniversalHIDServiceService(rsd) as hid:
                        yield hid
                finally:
                    try:
                        await asyncio.wait_for(
                            DisplayService.stop_all_streams(rsd), timeout=6
                        )
                    finally:
                        receiver.cancel()
                        if keepalive is not None:
                            keepalive.cancel()
        finally:
            transport.close()


def display_signature(info):
    primary = next(d for d in info["displays"] if d.get("primary"))
    return {
        "orientation": info["orientation"]["currentDeviceNonFlatOrientation"],
        "display": primary["displayId"],
        "size": primary["currentMode"]["size"],
        "frame": primary["frame"],
        "rotation": primary["currentOrientation"],
    }


async def current_display(rsd):
    async with DeviceInfoService(rsd) as info:
        return display_signature(await info.get_display_info())


def point(x, y, size, rotation):
    width, height = size
    if not all(type(n) is int for n in (x, y)) or not (
        0 <= x < width and 0 <= y < height
    ):
        raise ValueError("Coordinates must be integer pixels inside the returned image")
    u, v = x / width, y / height
    u, v = {0: (u, v), 90: (1 - v, u), 180: (1 - u, 1 - v), 270: (v, 1 - u)}[rotation]
    return round(u * 65535), round(v * 65535)


class Controller:
    def __init__(self, rsd, screenshot, product, output, max_size):
        self.rsd = rsd
        self.screenshot = screenshot
        self.product = product
        self.output = output
        self.max_size = max_size
        self.frame = 0
        self.signature = None
        self.size = None
        self.calibration = None
        self.hid = None
        self.keyboard_service = None

    def rotation(self, signature):
        if self.calibration and self.calibration[0] == signature:
            return self.calibration[1]
        if self.product == "iPad17,3" and signature["orientation"] == "landscapeLeft":
            return 90
        return None

    async def capture(self, max_size=None):
        self.signature = None
        before = await current_display(self.rsd)
        data = await self.screenshot.get_screenshot()
        after = await current_display(self.rsd)
        if before != after:
            raise ValueError("Display changed during capture; request a new shot")
        with Image.open(io.BytesIO(data)) as original:
            original.load()
            preview = original.convert("RGB")
        limit = self.max_size if max_size is None else max_size
        if limit:
            preview.thumbnail((limit, limit), Image.Resampling.LANCZOS)
        with tempfile.NamedTemporaryFile(
            dir=self.output, suffix="-full.png", delete=False
        ) as full:
            full.write(data)
        image = Path(full.name.replace("-full.png", ".png"))
        with image.open("xb") as target:
            preview.save(target, format="PNG")
        self.frame += 1
        self.signature = after
        self.size = preview.size
        return {
            "frame": self.frame,
            "image": str(image),
            "size": self.size,
            "original": full.name,
            "orientation": after["orientation"],
            "touch_rotation": self.rotation(after),
        }

    async def require_frame(self, command):
        if (
            type(command.get("frame")) is not int
            or command["frame"] != self.frame
            or self.signature is None
        ):
            raise ValueError(
                "Use the latest inspected frame number; request shot if needed"
            )
        if await current_display(self.rsd) != self.signature:
            self.signature = None
            raise ValueError(
                "Display changed; request shot and verify the touch mapping again"
            )

    async def keyboard(self, hid, reports):
        if self.keyboard_service is None:
            self.keyboard_service = await hid.create_keyboard_service()
        service = self.keyboard_service
        try:
            for usages in reports:
                modifiers = tuple(n for n in usages if 224 <= n <= 231)
                if modifiers:
                    await hid.send_keyboard(service, modifiers)
                    await asyncio.sleep(0.04)
                await hid.send_keyboard(service, usages)
                await asyncio.sleep(0.04)
                if modifiers:
                    await hid.send_keyboard(service, modifiers)
                    await asyncio.sleep(0.04)
                await hid.send_keyboard(service, ())
                await asyncio.sleep(0.02)
        finally:
            await hid.send_keyboard(service, ())

    async def gesture(self, hid, points):
        position = points[0]
        try:
            if len(points) == 1:
                await hid.send_touchscreen(TOUCHSCREEN_STATE_CONTACT, *position)
                await asyncio.sleep(0.05)
            else:
                start, end = points
                for step in range(31):
                    position = tuple(
                        round(a + (b - a) * step / 30) for a, b in zip(start, end)
                    )
                    await hid.send_touchscreen(TOUCHSCREEN_STATE_CONTACT, *position)
                    await asyncio.sleep(0.02)
        finally:
            await hid.send_touchscreen(TOUCHSCREEN_STATE_RELEASE, *position)

    async def execute(self, command):
        if not isinstance(command, dict):
            raise ValueError("Expected one JSON object")
        operations = set(command) - {"frame"}
        if len(operations) != 1:
            raise ValueError("Send one operation per line")
        operation = operations.pop()
        value = command[operation]
        if operation == "shot":
            if type(value) is not int or value < 0 or value > 4096:
                raise ValueError(
                    "shot is the maximum image edge (0 for full size, up to 4096)"
                )
            return await self.capture(value)
        if operation not in {
            "calibrate",
            "tap",
            "drag",
            "type",
            "paste",
            "key",
            "home",
        }:
            raise ValueError(
                "Unknown operation; use shot, calibrate, tap, drag, type, paste, key, home, or quit"
            )
        await self.require_frame(command)
        if operation == "calibrate":
            if type(value) is not int or value not in (0, 90, 180, 270):
                raise ValueError(
                    "calibrate is 0, 90, 180, or 270 degrees clockwise from image to HID"
                )
            self.calibration = (self.signature, value)
            return {
                "frame": self.frame,
                "touch_rotation": value,
                "verify": "Tap a harmless off-center target",
            }
        points, reports = [], []
        if operation in {"tap", "drag"}:
            rotation = self.rotation(self.signature)
            if rotation is None:
                raise ValueError(
                    "Unverified touch orientation; calibrate before tapping"
                )
            if not isinstance(value, list) or len(value) != (
                2 if operation == "tap" else 4
            ):
                raise ValueError("tap needs [x,y]; drag needs [x1,y1,x2,y2]")
            points = [
                point(*value[i : i + 2], self.size, rotation)
                for i in range(0, len(value), 2)
            ]
        elif operation in {"type", "paste"}:
            if not isinstance(value, str) or not value or len(value) > 1000:
                raise ValueError("Text must contain 1..1000 characters")
            if operation == "type":
                if any(ch not in ASCII_TO_HID for ch in value):
                    raise ValueError("type supports ASCII only; use paste for Unicode")
                for ch in value:
                    usage, shift = ASCII_TO_HID[ch]
                    reports.append((KEY_LEFT_SHIFT, usage) if shift else (usage,))
            else:
                reports = [(KEY_LEFT_GUI, ASCII_TO_HID["v"][0])]
        elif operation == "key":
            if (
                not isinstance(value, list)
                or not 1 <= len(value) <= 6
                or any(type(n) is not int or not 4 <= n <= 231 for n in value)
            ):
                raise ValueError("key needs 1..6 HID keyboard usage codes in 4..231")
            reports = [tuple(value)]
        elif value is not True:
            raise ValueError("home must be true")
        self.signature = None
        stage = "opening HID"
        try:
            if operation == "home":
                async with IndigoHIDService(self.rsd) as hid:
                    try:
                        await hid.send_button(0x0C, 0x40, HID_BUTTON_STATE_DOWN)
                        await asyncio.sleep(0.05)
                    finally:
                        await hid.send_button(0x0C, 0x40, HID_BUTTON_STATE_UP)
                        await asyncio.sleep(0.05)
            else:
                if operation == "paste":
                    stage = "setting clipboard"
                    async with PasteboardService(self.rsd) as pasteboard:
                        await pasteboard.set_text(value)
                    await asyncio.sleep(0.2)
                stage = "sending HID"
                if points:
                    await self.gesture(self.hid, points)
                else:
                    await self.keyboard(self.hid, reports)
            await asyncio.sleep(0.8)
            stage = "capturing result"
            return {"sent": operation, **await self.capture()}
        except Exception as error:
            raise RuntimeError(
                f"{stage}: {type(error).__name__}: {error}; "
                "action may have run; inspect a new shot before retrying"
            ) from error


async def session(args):
    async with AsyncExitStack() as resources:
        async with asyncio.timeout(90):
            mode, serial = await select_connection(args.connection, args.serial)
            rsd = await resources.enter_async_context(get_tunnel(mode, serial))
            if not await rsd.get_developer_mode_status():
                raise RuntimeError(
                    "Enable Developer Mode on the device, then mount its Developer Disk Image"
                )
            dvt = await resources.enter_async_context(DvtProvider(rsd))
            screenshot = await resources.enter_async_context(Screenshot(dvt))
            controller = Controller(
                rsd, screenshot, rsd.product_type, args.output, args.max_size
            )
            initial_display = await current_display(rsd)
            controller.hid = await resources.enter_async_context(
                media_hid_session(rsd, initial_display["display"])
            )
            first_frame = await controller.capture()
            if controller.signature["display"] != initial_display["display"]:
                raise RuntimeError("Primary display changed during startup; reconnect")
        emit(
            connection=mode,
            requested_connection=args.connection,
            device=rsd.all_values.get("DeviceName"),
            udid=rsd.udid,
            product=rsd.product_type,
            **first_frame,
        )
        reader = asyncio.StreamReader(limit=65536)
        transport, _ = await asyncio.get_running_loop().connect_read_pipe(
            lambda: asyncio.StreamReaderProtocol(reader),
            os.fdopen(os.dup(sys.stdin.fileno()), "rb", buffering=0),
        )
        try:
            while line := await reader.readline():
                try:
                    command = json.loads(line)
                    if command == {"quit": True}:
                        break
                    async with asyncio.timeout(180):
                        result = await controller.execute(command)
                    emit(**result)
                except (ValueError, TypeError) as error:
                    emit(error=str(error))
                except Exception as error:
                    emit(error=f"{type(error).__name__}: {error}", stopped=True)
                    return 1
        finally:
            transport.close()
    emit(closed=True)
    return 0


async def run(args):
    loop = asyncio.get_running_loop()
    task = asyncio.current_task()

    def request_stop():
        if not task.cancelling():
            task.cancel()

    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, request_stop)
    try:
        return await session(args)
    except asyncio.CancelledError:
        emit(closed=True)
        return 130
    finally:
        for sig in (signal.SIGINT, signal.SIGTERM):
            loop.remove_signal_handler(sig)


@contextmanager
def instance_lock():
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        raise RuntimeError("XDG_RUNTIME_DIR is required")
    fd = os.open(
        Path(runtime) / "apple-device-usb.lock",
        os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW,
        0o600,
    )
    with os.fdopen(fd, "r+") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("Another apple-device-usb session is running") from None
        yield


def main():
    parser = argparse.ArgumentParser(
        description="USB/Wi-Fi CoreDevice HID session: one JSON command per stdin line"
    )
    parser.add_argument("--connection", choices=MODES, default="auto")
    parser.add_argument(
        "--serial",
        "--udid",
        dest="serial",
        help="Select a USB device or saved Wi-Fi pairing",
    )
    parser.add_argument("--max-size", type=int, default=1280)
    parser.add_argument(
        "--output", type=Path, default=Path.home() / "Pictures/apple-device"
    )
    args = parser.parse_args()
    if not 128 <= args.max_size <= 4096 or not args.output.is_absolute():
        parser.error("--max-size must be 128..4096 and --output must be absolute")
    os.umask(0o077)
    args.output.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(level=logging.ERROR)
    terminal = termios.tcgetattr(sys.stdin) if sys.stdin.isatty() else None
    if terminal is not None:
        quiet = terminal.copy()
        quiet[3] &= ~termios.ECHO
        termios.tcsetattr(sys.stdin, termios.TCSANOW, quiet)
    try:
        with instance_lock():
            return asyncio.run(run(args))
    except KeyboardInterrupt:
        return 130
    except Exception as error:
        emit(error=f"{type(error).__name__}: {error}", stopped=True)
        return 1
    finally:
        if terminal is not None:
            termios.tcsetattr(sys.stdin, termios.TCSANOW, terminal)


if __name__ == "__main__":
    sys.exit(main())
