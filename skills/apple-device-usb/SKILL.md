---
name: apple-device-usb
description: Operate a USB-connected iPhone or iPad using screenshots and input. Not for simulators or macOS desktop control.
---

# Apple device control over USB

Use the installed `apple-device-usb` helper for one on-demand USB session:
observe a screenshot, send one frame-bound action, inspect the result, then close
the session. Do not operate while the user or another controller is changing the
device's screen. Editing this skill does not authorize connecting to a device.

This workflow adapts the explicit setup, session ownership, and failure handling
of [Omarchy iPhone Mirror](https://github.com/daniellemky/omarchy-iphone-mirror/tree/cd076dc9721554f2169c1f2a5cfb818d6ca0e954),
especially its [phone setup](https://github.com/daniellemky/omarchy-iphone-mirror/blob/cd076dc9721554f2169c1f2a5cfb818d6ca0e954/docs/phone-setup.md)
and [agent setup](https://github.com/daniellemky/omarchy-iphone-mirror/blob/cd076dc9721554f2169c1f2a5cfb818d6ca0e954/docs/agent-setup.md).
It is not an installer or wrapper for that application. Do not run its installer,
invent `setup-phone.sh` commands here, add Wi-Fi pairing, or enable autostart.

## Implementation and compatibility

The Nix-managed [launcher](/home/keewai/nixos-configuration/home/keewai/shared/apple-device-usb.nix)
pins the dependency; [scripts/control.py](scripts/control.py) defines the actual
JSON interface. Use those installed sources, not a different upstream version's
commands. The helper reuses one userspace tunnel, DVT screenshot channel,
CoreDevice media/HID session, and virtual keyboard. RTCP receiver reports keep
the media session alive between inputs. No root tunnel or VNC server is needed;
the media transport still uses sockets.

The initial lockdown connection is USB-only, but the pinned userspace tunnel's
internal lockdown selector prefers USB without excluding a matching network
device. Disabling RemotePairing fallback does not close that separate path.
Keep the cable attached. On USB loss, stop the recorded unit externally; a
successful helper response does not prove the transport is still USB. Never
intentionally continue over Wi-Fi. If the task requires a strict USB-only
transport guarantee, report this helper limitation and do not start it. That
guarantee needs a transport-level change, not another discovery check.

Omarchy decodes HEVC directly in MPV and gates input on viewer focus. This helper
instead uses inspected screenshots and frame IDs; there is no viewer-focus gate.
Do not copy MPV coordinates, shortcuts, or its automatic USB/Wi-Fi selection into
this workflow. Linux PyAV VNC frames were visibly corrupted in the original
local 11.5.0 test, so do not select targets from damaged VNC frames.

The USB transport requires iOS/iPadOS 17.4+, not every device on those versions
supports the required display/input services. The original local verification
used pymobiledevice3 11.5.0 and iPadOS 27.0 on iPad17,3; this does not verify later
dependency versions. Omarchy's reported ARM64/iPhone 13/iOS 27 results are also
not a support guarantee for this helper. A mounted developer image, advertised
display service, or successful command alone does not prove screenshots or input
work. Stop on unavailable media capabilities rather than cycling images.

## 1. Confirm the host and prepare the selected device

Confirm `hostnamectl --static` (fallback `hostname`) matches `/etc/hostname`;
stop on mismatch. Reuse an unchanged host check. Use only this host's USB device.

```sh
systemctl is-active usbmuxd
timeout -k 3 20 pymobiledevice3 usbmux list --usb --simple
```

This lists USB UDIDs without opening lockdown connections. Stop if none are
present; ask which device when ambiguous. Never select a saved network device
as fallback. Keep identifiers and personal device names out of external
diagnostics.

Phone preparation is separate from input. Before changing trust, revealing
Developer Mode, or downloading/mounting a developer image, explain the effect
and obtain authorization for that operation; reuse explicit authorization
already given. Developer Mode permits developer-service access from trusted
computers. The user enters passcodes, approves Trust, enables Developer Mode,
and confirms any restart on-device. Never request their passcode or automate
these confirmations. Preserve pairing records.

With the selected device already trusted and unlocked, check its state:

```sh
PYMOBILEDEVICE3_UDID='<observed-UDID>' pymobiledevice3 amfi developer-mode-status
PYMOBILEDEVICE3_UDID='<observed-UDID>' pymobiledevice3 mounter list
```

If Developer Mode is off, explain Settings → Privacy & Security → Developer
Mode. Use `amfi reveal-developer-mode` only when needed and authorized, with the
same UDID selection. Wait for the user's enable/restart/confirmation, then check
again. For versions older than 17.4, stop this workflow and inspect the installed
`pymobiledevice3 --help` and upstream transport guidance.

Mount only when no developer image is mounted and the operation is authorized:

```sh
PYMOBILEDEVICE3_UDID='<observed-UDID>' pymobiledevice3 mounter auto-mount
```

Allow the initial download to finish. Check again after a device reboot; do not
mount on every connection, unmount an existing image, or replace one as automatic
recovery. Close an existing controller before any image-changing operation.

## 2. Start one persistent helper

Use a private FIFO and a transient systemd user service so the helper survives
tool calls. Do not reconnect for every action or start a second controller for
the same device. If the user manager is unavailable, report that limitation;
do not substitute a root service or invent a terminal-session API.

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

Record the absolute session directory and unit name. Restore those literal
values in later shell calls; shell variables do not persist. The absolute Nix
launcher path is required because user services do not inherit the shell PATH.

Read complete new lines from `events.jsonl` with the available file-reading tool.
Track consumed lines. The initial event includes private device identifiers plus
`frame`, `image`, `size`, `original`, `orientation`, and `touch_rotation`. Open
`image` with the available image tool and use that image's pixel dimensions.
The default longest edge is 1280px; both preview and full-size captures remain
under `~/Pictures/apple-device`, outside the transient logs.

A launched unit is not a successful connection. If no initial frame arrives,
inspect only the recorded unit's status and `stderr.log`. Do not launch again
while its state is unknown.

## 3. Observe, act once, and verify

Send one JSON line to the existing FIFO, then read its new response event:

```sh
systemctl --user is-active --quiet "$unit" &&
  timeout 5 bash -c 'printf "%s\n" "$2" >"$1/input"' \
    _ "$session" '{"shot":1280}'
```

The write confirms queuing, not execution. Do not send another action until its
response is accounted for. A timeout or missing response is not permission to
replay; inspect logs and session state first. A fresh shot may be queued behind
an unfinished action and is not a cancellation mechanism.

Replace the JSON argument with one intended command. These are independent
examples, not a sequence to replay. Use the latest inspected `frame` and actual
target coordinates, not the example values:

| Command | Effect |
| --- | --- |
| `{"shot":1280}` | Refresh without input; `{"shot":0}` returns full size. |
| `{"frame":1,"tap":[240,180]}` | Tap an image pixel after verifying touch mapping. |
| `{"frame":2,"drag":[900,700,900,300]}` | Touch-contact drag, about 0.6 seconds; upstream `swipe` is pointer motion. |
| `{"frame":3,"type":"hello"}` | ASCII keyboard HID using the active device layout. |
| `{"frame":4,"key":[227,4]}` | Simultaneous HID chord, here Cmd+A. Enter: `[40]`; Backspace: `[42]`; Escape: `[41]`. |
| `{"frame":5,"paste":"日本語"}` | Replace the device clipboard and send Cmd+V. |
| `{"frame":6,"home":true}` | Hardware Home-button event, not a swipe. |

Select and verify the intended text field before typing or pasting. Batch a
known string or chord in one command; `type` and `paste` accept 1–1000 characters.
Paste is explicit, not clipboard synchronization, and may require app/device
permission. Do not overwrite the clipboard without the task's authorization.
Neither typed text nor clipboard contents belong in diagnostic reports.

Successful input releases keys/touches and returns the next screenshot. Inspect
it before a dependent action: `sent` means dispatched, not visually successful.
If animation or small text prevents verification, request another shot, using
its new frame and dimensions. Do not stream video or capture per keystroke.

Old frames, out-of-bounds coordinates, and changed display geometry are rejected.
For **iPad17,3 / landscapeLeft**, image-normalized `(u,v)` maps automatically to
HID `(1-v,u)`. For other model/orientation combinations, use a frame-bound
`{"frame":1,"calibrate":90}` with the appropriate 0/90/180/270-degree clockwise
rotation from image to HID. Calibration returns an acknowledgement, not a new
image or proof of correctness. Verify a harmless off-center target before
consequential input; do not guess using destructive controls. Recheck after
rotation or display changes. MPV's normalized video coordinates do not establish
this screenshot mapping.

## 4. Close only the owned session

Send `{"quit":true}` through the same FIFO. Confirm the new `closed` event and
inactive service before removing only the recorded temporary session directory.
Normal exit releases the media/HID resources and tunnel. If stuck, stop the exact
recorded unit with `systemctl --user stop "$unit"`, inspect its logs, and confirm
it is inactive; do not claim a graceful close without the event.

Captures are not deleted with session logs. Keep only task-needed captures under
the user's retention instructions; never delete unrelated images. Report only
visually verified operations, show relevant captures using absolute paths, and
distinguish setup success, screenshot success, input success, and cleanup status.

## Diagnose the failing layer; never replay blindly

| Observation | Next step |
| --- | --- |
| Empty USB list or `RX transfer stalled` | Inspect `journalctl -u usbmuxd` and USB topology locally. A different controller/port resolved the original citrus case; bus numbers are not stable identities. Preserve daemon/firewall settings and pairing records. |
| Trust, Developer Mode, or developer-image error | Return to the selected device's prerequisite check. No automatic pairing, image replacement, or reboot. |
| Missing/zero media capabilities | Report the compatibility limit. A mounted image is insufficient evidence; do not repeatedly reconnect. |
| Screenshot works but input does not | Check geometry/calibration separately from the media/HID connection. If the stock `display get-media-stream-server-status` also times out, stop HID retries and request a user-controlled device restart. |
| Validation error without `stopped` | Inspect the error and obtain a fresh shot if needed; correct the request only after checking state. |
| `stopped:true`, disconnect, or failed result capture | Input may already have run. Inspect logs, close the owned session, and establish current state before a justified new connection. Never replay the failed input automatically. |

Calls, locking, or other device activity can interrupt services; do not interpret
a stall as permission to change security settings. Omarchy reports call-related
interruptions on its test phone, not a verified recovery rule for this helper.

For unclear failures or upstream research, use available Jev analysis tools only
with bounded non-sensitive excerpts under their data-handling rules. Never send
UDIDs, serial numbers, personal device names, pairing records/keys, credentials,
account data, screenshots, clipboard contents, or typed input. The initial event
and arbitrary exception text may contain private data; never forward them raw.
If authorization or sensitivity is uncertain, diagnose locally without Jev.
Its advice does not authorize repair, reconnecting, or replaying input. Do not
use `jev_browser` or a web bridge to control this USB session.

For an explicitly requested VNC viewer only, inspect the installed
`display serve-vnc --help` first. Bind to `127.0.0.1` (for example port 5901), never
LAN or wildcard addresses: the upstream server is unauthenticated despite its
password prompt. Close this helper before opening another controller; a viewer
is not a fallback for uncertain input or corrupted captures.
