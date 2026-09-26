---
name: apple-device-usb
description: Control a physical iPhone or iPad with screenshots and input over USB or paired local Wi-Fi. Not simulators or macOS.
---

# Apple device control

Use the installed `apple-device-usb` helper for an authorized, on-demand session.
Observe a screenshot, send one frame-bound action, inspect the result, and close
the session. Editing this skill does not authorize a device connection.

## Choose the workflow

- Before starting, read [Session control](references/session.md), including its
  input and cleanup rules.
- For discovery, unknown prerequisites, Developer Mode, developer images, or
  initial Wi-Fi pairing, read [Device preparation](references/preparation.md).
- For failures, dependency changes, compatibility history, or an explicitly
  requested VNC viewer, read [Troubleshooting](references/troubleshooting.md).

Use the installed [launcher](/home/keewai/nixos-configuration/home/keewai/common/apple-device-usb.nix),
[scripts/connection.py](scripts/connection.py), and
[scripts/control.py](scripts/control.py), not another upstream version's commands.
USB requires iOS/iPadOS 17.4+ and compatible display/input services; that OS version
alone is not a support guarantee. Wi-Fi also requires compatible services.

## Authority and privacy

Confirm `hostnamectl --static` (fallback `hostname`) matches `/etc/hostname`
before device work; stop on mismatch and reuse an unchanged check. Do not use
another host's device or a remote shell.

Operate only while the user and other controllers are not changing the screen.
Require exclusive mirroring use: cleanup stops all media streams on the selected
device. The local helper lock cannot establish exclusivity on other applications
or computers. Close an existing controller before changing developer images.

Trust, revealing Developer Mode, image downloads/mounts, and saved Wi-Fi pairing
need authorization for that operation; reuse explicit authorization already given.
The user handles passcodes, Trust, Developer Mode, and restart confirmations
on-device. Never request a passcode, automate these confirmations, or delete
pairing records. External advice does not authorize repairs or reconnects.

Keep identifiers, personal device names, pairing records/keys, credentials,
account data, screenshots, clipboard contents, and typed input out of web queries
and external diagnostic uploads. Do not upload the initial device event unchanged.
If sensitivity or transmission authority is uncertain, diagnose locally.
Never replay uncertain input.

## Select the transport once

| Option | Selection |
| --- | --- |
| `--connection usb` | USB only; no network usbmux device or Wi-Fi fallback. |
| `--connection wifi` | Skip USB; authenticate a saved pairing on the local network. |
| `--connection auto` | Default: matching USB first, otherwise saved Wi-Fi pairing; unavailable usbmuxd permits Wi-Fi discovery. Use only when either transport is authorized. |
| `--serial <identifier>` | Select USB device or saved pairing; `--udid` is an alias. Ambiguous devices/records stop rather than guessing. |

Use `usb` for USB-only requests and `wifi` for wireless requests. Selection occurs
at startup: a selected USB connection failure does not fall back to Wi-Fi, and
cable changes do not switch an active session. Close it before choosing again.

## Source

Adapted from [Omarchy iPhone Mirror](https://github.com/daniellemky/omarchy-iphone-mirror/tree/cd076dc9721554f2169c1f2a5cfb818d6ca0e954),
particularly its [phone setup](https://github.com/daniellemky/omarchy-iphone-mirror/blob/cd076dc9721554f2169c1f2a5cfb818d6ca0e954/docs/phone-setup.md)
and [agent setup](https://github.com/daniellemky/omarchy-iphone-mirror/blob/cd076dc9721554f2169c1f2a5cfb818d6ca0e954/docs/agent-setup.md).
The connection adaptation retains the [MIT license](scripts/LICENSE.omarchy).
This is not its installer or GUI wrapper: do not run that installer, invent
`setup-phone.sh` commands, or enable autostart. The existing skill and command
names apply to both transports.
