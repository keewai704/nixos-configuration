import argparse
import asyncio
import hmac
import html
import http.cookies
import json
import logging
import os
import re
import secrets
import signal
import socket
import subprocess
import sys
import tempfile
import time
from contextlib import AsyncExitStack, suppress
from itertools import pairwise
from pathlib import Path
from urllib.parse import parse_qs, urlsplit


class ControlError(Exception):
    pass


def write_state(directory, **state):
    temporary = directory / "state.tmp"
    temporary.write_text(json.dumps(state))
    temporary.replace(directory / "state.json")


class HeaderReader:
    def __init__(self, reader, lines):
        self.reader = reader
        self.lines = iter(lines)

    async def readline(self):
        return next(self.lines, None) or await self.reader.readline()

    def __getattr__(self, name):
        return getattr(self.reader, name)


class BrowserVideo:
    def __init__(self, server):
        self.server = server
        self.process = None
        self.tasks = []
        self.input = asyncio.Queue(maxsize=64)
        self.subscribers = {}
        self.keyframe = None

    async def start(self):
        from pymobiledevice3.remote.core_device.screen_stream import _SubState

        self.process = await asyncio.create_subprocess_exec(
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-probesize",
            "32",
            "-analyzeduration",
            "0",
            "-f",
            "hevc",
            "-r",
            "30",
            "-i",
            "pipe:0",
            "-an",
            "-vf",
            "scale=w='min(iw,1920)':h='min(ih,1920)':force_original_aspect_ratio=decrease:force_divisible_by=2",
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            "-profile:v",
            "baseline",
            "-level:v",
            "5.1",
            "-preset",
            "ultrafast",
            "-tune",
            "zerolatency",
            "-crf",
            "20",
            "-g",
            "30",
            "-bf",
            "0",
            "-x264-params",
            "aud=1:repeat-headers=1",
            "-f",
            "h264",
            "pipe:1",
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        self.server._subscribers[self.input] = _SubState()
        if self.server._init_sequence:
            self.input.put_nowait(self.server._init_sequence)
        self.tasks = [
            asyncio.create_task(self.feed()),
            asyncio.create_task(self.receive()),
        ]

    async def feed(self):
        while True:
            message = await self.input.get()
            data = memoryview(message)[5:]
            while data:
                size = int.from_bytes(data[:4], "big")
                if size <= 0 or size > len(data) - 4:
                    raise ControlError("映像データの形式が不正です。")
                self.process.stdin.write(
                    b"\x00\x00\x00\x01" + data[4 : 4 + size].tobytes()
                )
                data = data[4 + size :]
            await self.process.stdin.drain()

    def publish(self, data):
        key = any(
            data[match.end()] & 31 == 5
            for match in re.finditer(b"\x00\x00(?:\x00)?\x01", data)
            if match.end() < len(data)
        )
        message = (len(data) + 1).to_bytes(4, "big") + bytes([0 if key else 1]) + data
        if key:
            self.keyframe = message
        for queue, needs_key in list(self.subscribers.items()):
            if queue.full():
                while not queue.empty():
                    queue.get_nowait()
                needs_key = True
            if key or not needs_key:
                queue.put_nowait(message)
                self.subscribers[queue] = False
            else:
                self.subscribers[queue] = True

    async def receive(self):
        buffer = b""
        while data := await self.process.stdout.read(65536):
            buffer += data
            if len(buffer) > 16 * 1024 * 1024:
                raise ControlError("映像変換が停止しました。")
            boundaries = list(re.finditer(b"\x00\x00(?:\x00)?\x01\x09", buffer))
            if len(boundaries) >= 2:
                for first, following in pairwise(boundaries):
                    self.publish(buffer[first.start() : following.start()])
                buffer = buffer[boundaries[-1].start() :]
        raise ControlError("映像変換が終了しました。")

    async def close(self):
        self.server._subscribers.pop(self.input, None)
        for task in self.tasks:
            task.cancel()
        await asyncio.gather(*self.tasks, return_exceptions=True)
        if self.process and self.process.returncode is None:
            self.process.terminate()
            try:
                await asyncio.wait_for(self.process.wait(), 3)
            except TimeoutError:
                self.process.kill()
                await self.process.wait()

    async def stream(self, writer):
        writer.write(
            b"HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nTransfer-Encoding: chunked\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        )
        await writer.drain()
        queue = asyncio.Queue(maxsize=64)
        self.subscribers[queue] = True
        if self.keyframe:
            queue.put_nowait(self.keyframe)
        try:
            while True:
                message = await queue.get()
                writer.write(f"{len(message):x}\r\n".encode() + message + b"\r\n")
                await writer.drain()
        finally:
            self.subscribers.pop(queue, None)


def make_server(rsd, directory, port, token):
    from pymobiledevice3.remote.core_device.screen_stream import (
        VIEWER_HTML,
        VIEWER_JS_TEMPLATE,
        ScreenStreamServer,
    )

    class LocalScreenServer(ScreenStreamServer):
        async def _eager_stream_start(self):
            await super()._eager_stream_start()
            try:
                await asyncio.wait_for(self._stream_ready.wait(), 10)
            except TimeoutError as error:
                raise ControlError(
                    "この端末から映像を取得できませんでした。ほかの画面共有を終了し、端末の対応状態を確認してください。"
                ) from error

        async def _reconnect_loop(self):
            self.browser_video = BrowserVideo(self)
            try:
                await self.browser_video.start()
                write_state(directory, ready=True)
                await asyncio.gather(*self.browser_video.tasks)
            except Exception:
                os.kill(os.getpid(), signal.SIGTERM)
            finally:
                await self.browser_video.close()

        async def _handle_http(self, reader, writer):
            try:
                async with asyncio.timeout(10):
                    block = await reader.readuntil(b"\r\n\r\n")
                lines = block.splitlines(keepends=True)
                method, target, version = lines[0].decode("ascii").split()
                headers = {}
                for line in lines[1:-1]:
                    name, value = line.decode("latin-1").split(":", 1)
                    name = name.lower()
                    if name in headers:
                        raise ValueError("Duplicate header")
                    headers[name] = value.strip()
                origin = f"http://127.0.0.1:{port}"
                allowed = (
                    version == "HTTP/1.1"
                    and headers.get("host") == f"127.0.0.1:{port}"
                    and headers.get("origin", origin) == origin
                    and "transfer-encoding" not in headers
                    and 0 <= int(headers.get("content-length", "0")) <= 8 * 1024 * 1024
                )
                if not allowed:
                    raise ValueError("Invalid request")
                url = urlsplit(target)
                bootstrap = parse_qs(url.query).get("token", [""])[0]
                if (
                    method == "GET"
                    and url.path == "/start"
                    and hmac.compare_digest(bootstrap, token)
                ):
                    body = b"<!doctype html><meta charset=utf-8><title>iPhone / iPad Control</title><script>location.replace('/')</script>"
                    writer.write(
                        b"HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n"
                        + f"Set-Cookie: iphone_control={token}; HttpOnly; SameSite=Strict; Path=/\r\n".encode()
                        + b"Cache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nContent-Length: "
                        + str(len(body)).encode()
                        + b"\r\nConnection: close\r\n\r\n"
                        + body
                    )
                    await writer.drain()
                    return
                cookies = http.cookies.SimpleCookie(headers.get("cookie", ""))
                cookie = cookies.get("iphone_control")
                if cookie is None or not hmac.compare_digest(cookie.value, token):
                    raise ValueError("Unauthorized")
                if url.path in ("/", "/index.html"):
                    body = VIEWER_HTML.replace(
                        b"pymobiledevice3 screen", b"iPhone / iPad Control"
                    ).replace(
                        b">pymobiledevice3</span>", b">iPhone / iPad Control</span>"
                    )
                    self._send_static(writer, body, b"text/html; charset=utf-8")
                    await writer.drain()
                    return
                if url.path == "/codec":
                    self._send_static(
                        writer,
                        b'{"codec":"avc1.42C033","description":null}',
                        b"application/json",
                    )
                    await writer.drain()
                    return
                if url.path == "/stream.bin":
                    await self.browser_video.stream(writer)
                    return
                if url.path == "/viewer.js":
                    body = VIEWER_JS_TEMPLATE.replace(
                        b"__AUDIO_DEFAULT_ON__", b"false"
                    ).replace(b"__COMPENSATE_DEFAULT__", b"true")
                    body = body.replace(
                        b"if (!info.codec || !info.description)", b"if (!info.codec)"
                    )
                    body = body.replace(
                        b"const description = Uint8Array.from(atob(info.description), c => c.charCodeAt(0));",
                        b"const description = info.description ? Uint8Array.from(atob(info.description), c => c.charCodeAt(0)) : undefined;",
                    )
                    body = body.replace(
                        b"description.length", b"(description?.length || 0)"
                    )
                    self._send_static(
                        writer, body, b"application/javascript; charset=utf-8"
                    )
                    await writer.drain()
                    return
                replay = [lines[0]]
                replay.extend(
                    line
                    for line in lines[1:-1]
                    if not line.lower().startswith(b"connection:")
                )
                replay.extend([b"Connection: close\r\n", b"\r\n"])
                await super()._handle_http(HeaderReader(reader, replay), writer)
            except (
                ValueError,
                TypeError,
                UnicodeError,
                http.cookies.CookieError,
                asyncio.LimitOverrunError,
            ):
                writer.write(
                    b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                )
                with suppress(ConnectionError):
                    await writer.drain()
            except (TimeoutError, asyncio.IncompleteReadError, ConnectionError):
                pass
            finally:
                writer.close()

    return LocalScreenServer(
        rsd,
        bind="127.0.0.1",
        http_port=port,
        audio_default_on=False,
        ltrp_enabled=False,
    )


async def serve(args, directory):
    from connection import get_tunnel, select_connection
    from control import instance_lock
    from pymobiledevice3.exceptions import NotMountedError
    from pymobiledevice3.lockdown import create_using_usbmux
    from pymobiledevice3.remote.core_device.display_service import DisplayService
    from pymobiledevice3.services.mobile_image_mounter import MobileImageMounterService

    config = json.loads((directory / "config.json").read_text())
    with instance_lock():
        async with AsyncExitStack() as resources:
            async with asyncio.timeout(90):
                try:
                    mode, serial = await select_connection("usb", args.serial)
                except RuntimeError as error:
                    raise ControlError(
                        "USB で iPhone または iPad を 1 台接続してください。複数台の場合は --serial で選択してください。"
                    ) from error
                device = await create_using_usbmux(
                    serial=serial, connection_type="USB", autopair=False
                )
                try:
                    if not device.paired:
                        raise ControlError(
                            "端末のロックを解除し、この PC を信頼してください。"
                        )
                    if not await device.get_developer_mode_status():
                        raise ControlError(
                            "端末の「設定 → プライバシーとセキュリティ → デベロッパモード」を有効にしてください。"
                        )
                    async with MobileImageMounterService(device) as mounter:
                        try:
                            await asyncio.wait_for(
                                mounter.lookup_image("Personalized"), 5
                            )
                        except NotMountedError:
                            mounted = await asyncio.wait_for(mounter.copy_devices(), 5)
                            if not any(
                                image.get("DiskImageType") == "Personalized"
                                for image in mounted
                            ):
                                raise ControlError(
                                    "開発者ディスクイメージの準備が必要です。端末を選択して、許可したうえでマウントしてください。"
                                )
                finally:
                    await device.close()
                rsd = await resources.enter_async_context(get_tunnel(mode, serial))
            server = make_server(rsd, directory, config["port"], config["token"])
            served = False
            try:
                await server.serve()
                served = True
            finally:
                if not served:
                    if server._active_service is not None:
                        with suppress(Exception):
                            await asyncio.wait_for(server._stop_active_stream(), 3)
                    await asyncio.wait_for(DisplayService.stop_all_streams(rsd), 6)


def stop_process(process, timeout=30):
    if process is None:
        return 0
    if process.poll() is not None:
        return process.returncode
    process.terminate()
    try:
        process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
    return process.returncode


def launch(args):
    if not args.no_prompt:
        result = subprocess.run(
            [
                "zenity",
                "--question",
                "--no-markup",
                "--title=iPhone / iPad Control",
                "--text=USB 接続した端末のロックを解除してください。\nAirPlay やほかの画面操作を終了し、このウィンドウで操作します。\nウィンドウを閉じると、端末の画面共有も終了します。",
                "--ok-label=接続",
                "--cancel-label=キャンセル",
            ],
            check=False,
        )
        if result.returncode:
            return 0
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        raise ControlError("デスクトップセッション内で起動してください。")
    with tempfile.TemporaryDirectory(
        prefix="iphone-control-", dir=runtime
    ) as temporary:
        directory = Path(temporary)
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        token = secrets.token_urlsafe(32)
        (directory / "config.json").write_text(
            json.dumps({"port": port, "token": token})
        )
        url = f"http://127.0.0.1:{port}/start?token={token}"
        (directory / "open.html").write_text(
            '<!doctype html><meta charset="utf-8"><title>iPhone / iPad Control</title>'
            + f'<meta http-equiv="refresh" content="0;url={html.escape(url, quote=True)}">'
        )
        child = browser = None
        finished = False
        try:
            child = subprocess.Popen(
                [
                    sys.executable,
                    __file__,
                    "--helper-dir",
                    args.helper_dir,
                    "--browser",
                    args.browser,
                    "--serve",
                    temporary,
                    *(["--serial", args.serial] if args.serial else []),
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            deadline = time.monotonic() + 120
            while time.monotonic() < deadline:
                state_file = directory / "state.json"
                if state_file.exists():
                    state = json.loads(state_file.read_text())
                    if state.get("error"):
                        raise ControlError(state["error"])
                    if state.get("ready"):
                        break
                if child.poll() is not None:
                    raise ControlError(
                        "端末に接続できませんでした。USB 接続とロック解除を確認してください。"
                    )
                time.sleep(0.1)
            else:
                raise ControlError(
                    "接続がタイムアウトしました。端末の状態を確認してから起動し直してください。"
                )
            browser = subprocess.Popen(
                [
                    args.browser,
                    f"--user-data-dir={directory / 'browser'}",
                    "--incognito",
                    "--no-first-run",
                    "--no-default-browser-check",
                    "--disable-background-mode",
                    f"--app={(directory / 'open.html').as_uri()}",
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            while browser.poll() is None:
                if child.poll() is not None:
                    raise ControlError(
                        "端末との接続が終了しました。状態を確認してから起動し直してください。"
                    )
                time.sleep(0.2)
            if browser.returncode:
                raise ControlError("画面表示用ブラウザを起動できませんでした。")
            finished = True
        finally:
            status = stop_process(child)
            stop_process(browser, timeout=10)
            if finished and status != 0:
                raise ControlError(
                    "端末の画面共有終了を確認できませんでした。端末側の共有状態を確認してください。"
                )
    return 0


def main():
    parser = argparse.ArgumentParser(
        description="View and control a USB-connected iPhone or iPad"
    )
    parser.add_argument("--helper-dir", required=True)
    parser.add_argument("--browser", required=True)
    parser.add_argument("--serial")
    parser.add_argument("--no-prompt", action="store_true")
    parser.add_argument("--serve", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    sys.path.insert(0, args.helper_dir)
    logging.disable(logging.CRITICAL)

    def interrupted(signum, frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, interrupted)
    try:
        if args.serve:
            asyncio.run(serve(args, args.serve))
            return 0
        return launch(args)
    except KeyboardInterrupt:
        return 130
    except Exception as error:
        message = (
            str(error)
            if isinstance(error, ControlError)
            else f"接続処理に失敗しました ({type(error).__name__})。端末の接続・ロック解除・開発者モードを確認してください。"
        )
        if args.serve:
            write_state(args.serve, error=message)
        else:
            subprocess.run(
                [
                    "zenity",
                    "--error",
                    "--no-markup",
                    "--title=iPhone / iPad Control",
                    f"--text={message}",
                ],
                check=False,
            )
        return 1


if __name__ == "__main__":
    sys.exit(main())
