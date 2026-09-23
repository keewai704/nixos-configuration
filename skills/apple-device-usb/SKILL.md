---
name: apple-device-usb
description: Operate a USB-connected iPhone or iPad using screenshots and input. Not for simulators or macOS desktop control.
---

# Apple device control over USB

Use the installed `apple-device-usb` helper; its dependency is pinned in the
Nix launcher linked below. It reuses the USB tunnel, screenshot channel,
screen-sharing media/HID session, and virtual keyboard. Each input releases
keys/touches and returns a fresh image.
RTCP receiver reports keep the media session alive while waiting for input.
No root tunnel, network listener, device app, or repeated coordinate arithmetic
is needed. Source: [scripts/control.py](scripts/control.py).
This transport needs iOS/iPadOS 17.4+. The original hardware verification used
pymobiledevice3 11.5.0 and iPadOS 27.0; that is not verification of later versions.
For older devices, inspect the installed `pymobiledevice3 --help` and upstream
transport guidance instead of forcing this helper's connection path.

## Protect device data during diagnosis and research

Keep UDIDs, serial numbers, personal device names, pairing records or keys,
credentials, account data, screenshots, clipboard contents, and typed input out
of web queries and external diagnostic uploads. Do not upload the initial device
event unchanged. If sensitivity or transmission authority is uncertain,
diagnose locally.

External advice does not authorize repairs, reconnecting, or replaying input.
Use the screenshot inspection and frame-bound commands below to verify actions.

## Connect once

Confirm `hostnamectl --static` (fallback `hostname`) matches `/etc/hostname`;
stop on mismatch. Use only this host's USB device. Reuse a host check already
completed in this environment.

```sh
systemctl is-active usbmuxd
timeout -k 3 20 pymobiledevice3 usbmux list
```

Identify the observed UDID, name, and USB connection. Ask which device when
ambiguous. Unlock/trust only if needed. Before the first developer connection,
check Developer Mode and mount the DDI once per device boot:

```sh
PYMOBILEDEVICE3_UDID='<observed-UDID>' pymobiledevice3 amfi developer-mode-status
PYMOBILEDEVICE3_UDID='<observed-UDID>' pymobiledevice3 mounter auto-mount
```

If disabled, `amfi reveal-developer-mode` reveals the setting; the user enables
it, restarts, and confirms on-device. Allow the initial DDI download to finish.

Pi's native `bash` tool has no `tty` parameter or terminal-session stdin API.
Use a private FIFO and a transient local user service to keep one helper alive
across tool calls. Use the absolute Nix launcher path as shown; user services do
not inherit the interactive shell's PATH. This requires the local systemd user
manager; if unavailable, report the transport limitation and continue only useful
authorized diagnostics.
Do not invent a terminal session ID or repeatedly reconnect for each input.

```sh
set -e
umask 077
session=$(mktemp -d "${XDG_RUNTIME_DIR:?}/apple-device-usb.XXXXXX")
unit="apple-device-usb-${session##*.}"
mkfifo "$session/input"
systemd-run --user --unit="$unit" --collect \
  --property=UMask=0077 \
  --property="StandardOutput=append:$session/events.jsonl" \
  --property="StandardError=append:$session/stderr.log" \
  "$(command -v bash)" -c \
  'exec 3<>"$1/input"; exec "$2" --udid "$3" <&3' \
  _ "$session" "$(command -v apple-device-usb)" '<observed-UDID>'
printf 'session=%s\nunit=%s\n' "$session" "$unit"
```

Record the printed absolute directory and unit name. Shell variables do not
persist across tool calls; set them to these recorded values in later commands.
Read complete new lines from `events.jsonl` with `read`. The initial event contains
`frame`, `image`, `size`, `original`, `orientation`, and `touch_rotation`.
If it does not arrive, inspect this unit's status and `stderr.log`; launching a
unit alone does not prove connection success.

Open `image` with Pi's `read` tool and use its returned pixel dimensions. The
default longest edge is 1280px, and the full original is retained. Screenshots
default to `~/Pictures/apple-device`, separate from the transient session logs.

## Operate with short commands

Send one JSON line to the existing FIFO, then read the new response event. For
example, refresh the image without input:

```sh
systemctl --user is-active --quiet "$unit" &&
  timeout 5 bash -c 'printf "%s\n" "$2" >"$1/input"' \
    _ "$session" '{"shot":1280}'
```

Replace the JSON argument with one intended command. Track the consumed event
lines so an old response cannot be mistaken for a new result. A successful write
means queued, not completed. A timeout or missing response is not permission to
replay input; inspect the logs and current state first.
Replace `frame` with the latest inspected frame number and coordinates/text with
the intended target:

```json
{"frame":1,"tap":[240,180]}
{"frame":2,"drag":[900,700,900,300]}
{"frame":3,"type":"hello"}
{"frame":4,"key":[227,4]}
{"frame":5,"paste":"日本語"}
{"frame":6,"home":true}
```

These are separate examples, not a script to replay. Every input returns the
next screenshot. Inspect it before a dependent action; `sent` means dispatched,
not visually successful. If an animation is unfinished, request another image.
Batch a known string/chord in one `type`, `paste`, or `key` command; do not
request screenshots per keystroke or stream video frames into model context.

- `drag` uses touch contact (30 steps, 0.6s). Upstream `swipe` is pointer motion.
- `type` sends ASCII keyboard HID using the device's active keyboard layout.
- `key` is a simultaneous chord of HID Keyboard/Keypad usage codes:
  Enter `[40]`, Backspace `[42]`, Escape `[41]`, Cmd+A `[227,4]`.
- `paste` replaces the device clipboard and sends Cmd+V; use for Unicode.
- `{"shot":1280}` refreshes without input; `{"shot":0}` returns full size
  for small text. Use the new frame and its own pixel dimensions afterwards.
- `{"quit":true}` closes the session. Confirm the `closed` event and inactive
  service before removing only this session's temporary directory. If the helper
  is stuck, stop the recorded unit with `systemctl --user stop "$unit"` and
  inspect its logs. Keep screenshots needed for the report. Restart after a
  disconnect/reboot; do not automatically replay an input after a failure.

Old frame IDs, out-of-bounds coordinates, and changed display geometry are
rejected. For **iPad17,3 / landscapeLeft**, the verified mapping is automatic:
image-normalized `(u,v)` becomes HID `(1-v,u)`. Other orientations require
`{"frame":1,"calibrate":90}` (0/90/180/270 clockwise from image to HID).
Calibration is tied to the observed display geometry. Verify with harmless
off-center targets before consequential input; it is not proof by itself.
Recheck after device rotation or display changes. Do not operate while someone
else is changing the device's screen.

## Screen Sharing and failures

The macOS Screen Sharing demo path is upstream
[`display serve-vnc`](https://github.com/doronz88/pymobiledevice3/blob/v11.5.0/pymobiledevice3/cli/developer/core_device.py):
CoreDevice video becomes VNC, and VNC input becomes virtual HID. For an explicitly
requested viewer, use `--bind 127.0.0.1 --port 5901` (macOS `vnc://127.0.0.1:5901`).
The server is unauthenticated despite its password prompt; never expose it.

On citrus/iPad17,3, Linux PyAV VNC frames were visibly corrupted in 11.5.0.
The helper therefore uses reliable DVT screenshots and the same underlying
media/HID services directly. Do not select targets from damaged VNC frames.

An empty USB list, failed developer connection, and wrong touch coordinates
are different failures. Check the relevant layer once rather than retrying
blindly. For `RX transfer stalled`, inspect `journalctl -u usbmuxd` and USB
topology: citrus's rear DP-capable USB-C port worked on a different controller
than the earlier failing ports. Bus numbers are not stable identifiers.
Preserve pairing records; do not print their keys or change firewall/daemon
settings to work around a physical USB issue.
If the stock `display get-media-stream-server-status` also times out while USB
and DVT screenshots still work, stop retrying HID and request a device restart.

Report only visually verified operations and display relevant captures using
absolute file paths. The Nix launcher is managed in
[apple-device-usb.nix](/home/keewai/nixos-configuration/home/keewai/shared/apple-device-usb.nix).
