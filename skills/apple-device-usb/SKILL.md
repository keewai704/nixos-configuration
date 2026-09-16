---
name: apple-device-usb
description: >-
  Operate USB-connected iPhones and iPads with compact screenshots, touch,
  keyboard HID, and Unicode paste through a reusable CoreDevice session.
  Use for real iOS/iPadOS devices, not simulators or macOS desktop control.
---

# Apple device control over USB

Use the installed `apple-device-usb` helper (pymobiledevice3 11.5.0). It reuses
the USB tunnel, screenshot channel, screen-sharing media/HID session, and virtual
keyboard. Each input releases keys/touches and returns a fresh image.
RTCP receiver reports keep the media session alive while waiting for input.
No root tunnel, network listener, device app, or repeated coordinate arithmetic
is needed. Source: [scripts/control.py](scripts/control.py).
This transport needs iOS/iPadOS 17.4+; the hardware verification is iPadOS 27.0.
For older devices, inspect the installed `pymobiledevice3 --help` and upstream
transport guidance instead of forcing this helper's connection path.

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

Start this in a persistent terminal tool session with stdin open (`tty: true`):

```sh
apple-device-usb --udid '<observed-UDID>'
```

Keep the returned terminal session ID. The helper emits one JSON line with
`frame`, `image`, `size`, `original`, `orientation`, and `touch_rotation`.
Inspect `image` with the image-viewing tool; use its returned pixel dimensions.
The default longest edge is 1280px, and the full original is retained. Output
defaults to `~/Pictures/apple-device`; `--output` accepts an absolute directory.

## Operate with short commands

Send one JSON line through the same terminal's stdin. Replace `frame` with the
latest inspected frame number and coordinates/text with the intended target:

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
- `{"quit":true}` closes the session. Close it when finished; restart after
  disconnect/reboot. Do not automatically replay an input after a failure.

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
