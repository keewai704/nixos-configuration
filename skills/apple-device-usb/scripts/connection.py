import asyncio
import ipaddress
import json
from contextlib import suppress
from pathlib import Path

from pymobiledevice3.exceptions import (
    ConnectionFailedToUsbmuxdError,
    ConnectionTerminatedError,
)
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.remote import userspace_tunnel as ut
from pymobiledevice3.remote.tunnel_service import (
    CoreDeviceTunnelProxy,
    RemotePairingTunnelService,
    browse_remotepairing,
    iter_remote_paired_identifiers,
)

MODES = ("auto", "usb", "wifi")


async def select_connection(mode, serial=None):
    if mode not in MODES:
        raise ValueError("Unknown connection mode")
    if mode == "wifi":
        return "wifi", serial
    from pymobiledevice3.usbmux import list_devices

    try:
        devices = [
            device
            for device in await list_devices()
            if device.is_usb and (not serial or device.matches_udid(serial))
        ]
    except (OSError, ConnectionFailedToUsbmuxdError):
        if mode != "auto":
            raise
        devices = []
    if len(devices) > 1:
        raise RuntimeError(
            "Several USB iPhones are connected. Select one with --serial."
        )
    if devices:
        return "usb", devices[0].serial
    if mode == "auto":
        return "wifi", serial
    raise RuntimeError("No matching USB iPhone is connected.")


async def network_route_allowed(address):
    try:
        ip = ipaddress.ip_address(address.split("%", 1)[0])
    except ValueError:
        return False
    process = await asyncio.create_subprocess_exec(
        "ip",
        "-j",
        "route",
        "get",
        address,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL,
    )
    try:
        data, _ = await asyncio.wait_for(process.communicate(), 2)
    except BaseException:
        with suppress(OSError):
            process.kill()
        await process.wait()
        raise
    if process.returncode:
        return False
    try:
        routes = json.loads(data)
    except ValueError:
        return False
    if not routes or ip.is_loopback:
        return False
    device = routes[0].get("dev", "")
    if not isinstance(device, str) or not device:
        return False
    lowered = device.lower()
    if lowered in {"lo", "lo0"} or lowered.startswith(
        (
            "tailscale",
            "tun",
            "utun",
            "wg",
            "tap",
            "ppp",
            "ip6tnl",
            "ip6gre",
            "gre",
            "sit",
        )
    ):
        return False
    driver = (Path("/sys/class/net") / device / "device/driver").resolve()
    return driver.name != "ipheth"


async def connect_wifi(identifier, address, port):
    service = RemotePairingTunnelService(identifier, address, port)
    try:
        await asyncio.wait_for(service.connect(autopair=False), 8)
        return service
    except BaseException:
        with suppress(Exception):
            await asyncio.wait_for(service.close(), 1)
        raise


async def wifi_provider(serial=None, autopair=False, remotepairing_fallback=False):
    identifiers = list(iter_remote_paired_identifiers())
    if serial:
        wanted = serial.replace("-", "").casefold()
        identifiers = [
            identifier
            for identifier in identifiers
            if identifier.replace("-", "").casefold() == wanted
        ]
    if not identifiers:
        raise RuntimeError(
            "No saved CoreDevice pairing matches this device. Pair over USB first."
        )
    if len(identifiers) > 1:
        raise RuntimeError(
            "Several pairing records exist. Select an iPhone with --serial."
        )
    identifier = identifiers[0]
    answers = await browse_remotepairing(timeout=4)
    endpoints = {
        (address.full_ip, answer.port)
        for answer in answers
        for address in answer.addresses
    }
    endpoints = sorted(
        endpoints, key=lambda endpoint: (":" in endpoint[0], endpoint[0], endpoint[1])
    )
    for address, port in endpoints:
        try:
            if not await network_route_allowed(address):
                continue
            return await connect_wifi(identifier, address, port), None
        except (OSError, asyncio.IncompleteReadError, ConnectionTerminatedError):
            continue
    raise RuntimeError("The paired iPhone was not reachable on the local network.")


async def usb_provider(serial=None, autopair=False, remotepairing_fallback=False):
    lockdown = await create_using_usbmux(
        serial=serial,
        connection_type="USB",
        autopair=False,
    )
    try:
        return await CoreDeviceTunnelProxy.create(lockdown), lockdown
    except BaseException:
        with suppress(Exception):
            await lockdown.close()
        raise


class UsbTunnel(ut.UserspaceRsdTunnel):
    async def _aopen_locked(self):
        original = ut._create_no_root_tunnel_provider
        ut._create_no_root_tunnel_provider = usb_provider
        try:
            return await super()._aopen_locked()
        finally:
            ut._create_no_root_tunnel_provider = original


class WifiTunnel(ut.UserspaceRsdTunnel):
    async def _aopen_locked(self):
        original = ut._create_no_root_tunnel_provider
        ut._create_no_root_tunnel_provider = wifi_provider
        try:
            return await super()._aopen_locked()
        finally:
            ut._create_no_root_tunnel_provider = original


def get_tunnel(mode, serial=None):
    if mode == "usb":
        cls = UsbTunnel
    elif mode == "wifi":
        cls = WifiTunnel
    else:
        raise ValueError("get_tunnel requires a selected usb or wifi mode")
    return cls(serial=serial, autopair=False, remotepairing_fallback=False)
