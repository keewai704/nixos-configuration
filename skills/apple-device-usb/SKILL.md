---
name: apple-device-usb
description: Operate an iPhone or iPad over USB or an already paired local Wi-Fi connection using screenshots and input. Not for simulators or macOS desktop control.
---

# Apple device control over USB or Wi-Fi

Use the installed `apple-device-usb` helper for one on-demand session:
observe a screenshot, send one frame-bound action, inspect the result, then close
the session. Do not operate while the user or another controller is changing the
device's screen. Editing this skill does not authorize connecting to a device.

The connection implementation and workflow adapt the design
of [Omarchy iPhone Mirror](https://github.com/daniellemky/omarchy-iphone-mirror/tree/cd076dc9721554f2169c1f2a5cfb818d6ca0e954),
especially its [phone setup](https://github.com/daniellemky/omarchy-iphone-mirror/blob/cd076dc9721554f2169c1f2a5cfb818d6ca0e954/docs/phone-setup.md)
and [agent setup](https://github.com/daniellemky/omarchy-iphone-mirror/blob/cd076dc9721554f2169c1f2a5cfb818d6ca0e954/docs/agent-setup.md).
It is not an installer or GUI wrapper for that application. Do not run its
installer, invent `setup-phone.sh` commands here, or enable autostart. The existing
skill and command names remain valid for both transports.

## Implementation and compatibility

The Nix-managed [launcher](/home/keewai/nixos-configuration/home/keewai/shared/apple-device-usb.nix)
pins the dependency; [scripts/connection.py](scripts/connection.py) selects the
transport and [scripts/control.py](scripts/control.py) defines the JSON interface.
The connection adaptation retains Omarchy's [MIT license](scripts/LICENSE.omarchy).
Use those installed sources, not a different upstream version's commands.
The helper reuses one userspace tunnel, DVT screenshot channel,
CoreDevice media/HID session, and virtual keyboard. RTCP receiver reports keep
the media session alive between inputs. No root tunnel or VNC server is needed;
the media transport still uses sockets.

Like Omarchy, connection selection happens once at startup:

| Option | Selection |
| --- | --- |
| `--connection auto` | Default: use a matching USB device first; otherwise use saved Wi-Fi pairing. Unavailable usbmuxd also permits Wi-Fi discovery. |
| `--connection usb` | Require USB. Missing devices and connection failures stop; never use a network usbmux device or Wi-Fi fallback. |
| `--connection wifi` | Skip USB discovery and authenticate a saved pairing on the local network. |
| `--serial <identifier>` | Select a USB device or saved pairing; `--udid` is an alias. Without it, ambiguous devices/records stop rather than guessing. |

Use `usb` for USB-only requests, `wifi` for explicitly requested wireless control,
and `auto` only when either transport is authorized. Selecting USB commits that
session to USB, even if its connection subsequently fails. Connecting or removing
a cable never changes an active session's transport. End the old session before
choosing again; never replay an uncertain input.

The provider adapter uses the pinned library's private `_aopen_locked` hook, as
Omarchy does. It restores the temporary provider selector on success, failure,
and cancellation while the library's lifecycle lock is held. Unlike the stock
USB-preferred selector, its USB provider explicitly requires `connection_type="USB"`.
Review this adapter when changing the dependency version.

Omarchy decodes HEVC directly in MPV and gates input on viewer focus. This helper
instead uses inspected screenshots and frame IDs; there is no viewer-focus gate.
Do not copy MPV coordinates or viewer shortcuts into this workflow. Linux PyAV
VNC frames were visibly corrupted in the original local 11.5.0 test, so do not
select targets from damaged VNC frames.

The USB transport requires iOS/iPadOS 17.4+, not every device on those versions
supports the required display/input services. The original local verification
used pymobiledevice3 11.5.0 and iPadOS 27.0 on iPad17,3; this does not verify later
dependency versions. Omarchy's reported ARM64/iPhone 13/iOS 27 results are also
not a support guarantee for this helper. A mounted developer image, advertised
display service, or successful command alone does not prove screenshots or input
work. Stop on unavailable media capabilities rather than cycling images.

## Protect device data during diagnosis and research

Keep UDIDs, serial numbers, personal device names, pairing records or keys,
credentials, account data, screenshots, clipboard contents, and typed input out
of web queries and external diagnostic uploads. Do not upload the initial device
event unchanged. If sensitivity or transmission authority is uncertain,
diagnose locally.

External advice does not authorize repairs, reconnecting, or replaying input.
Use the screenshot inspection and frame-bound commands below to verify actions.

## 1. Confirm the host and prepare the selected device

Confirm `hostnamectl --static` (fallback `hostname`) matches `/etc/hostname`;
stop on mismatch. Reuse an unchanged host check. Do not use another host's USB
device or a remote shell. For USB discovery and initial phone preparation:

```sh
systemctl is-active usbmuxd
timeout -k 3 20 pymobiledevice3 usbmux list --usb --simple
```

This lists USB UDIDs without opening lockdown connections. For USB control or
preparation, stop if none are present; ask which device when ambiguous. For
already paired Wi-Fi control, no attached USB device is required. Keep identifiers
and personal device names out of external diagnostics.

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
again. Do not force the USB path on versions older than 17.4; inspect the installed
`pymobiledevice3 --help` and upstream transport guidance. Wi-Fi still requires
compatible display and input services, regardless of OS version.

Mount only when no developer image is mounted and the operation is authorized:

```sh
PYMOBILEDEVICE3_UDID='<observed-UDID>' pymobiledevice3 mounter auto-mount
```

Allow the initial download to finish. Check again after a device reboot; do not
mount on every connection, unmount an existing image, or replace one as automatic
recovery. Close an existing controller before any image-changing operation.

### Optional Wi-Fi preparation

USB trust and CoreDevice Wi-Fi pairing are separate. If wireless control is
requested and no matching record exists, explain that this operation creates a
saved network credential and obtain authorization. With that same device trusted,
unlocked, and connected over USB, run once:

```sh
PYMOBILEDEVICE3_UDID='<observed-UDID>' pymobiledevice3 lockdown remotepairing --pair
```

Do not read pairing keys, delete records, or repeat pairing automatically. Reuse
an existing record; the helper always connects with automatic pairing disabled.
Keep the device and this host on the same local network. For a wireless check,
close the USB session, have the user disconnect the cable, and start with
`--connection wifi`. Discovery with `pymobiledevice3 remote browse` is optional;
its identifiers and addresses must stay local. The helper checks discovered
routes and rejects loopback, known tunnel interfaces, and `ipheth` USB tethering.
Do not change firewall or route settings to bypass a failed check.

## 2. Start one persistent helper

Use a private FIFO and a transient systemd user service so the helper survives
tool calls. An advisory file lock under `XDG_RUNTIME_DIR` rejects a second helper
instance; it does not lock other applications such as Omarchy's viewer. Close
other controllers first. Do not reconnect for every action. If the user manager
is unavailable, report that limitation; do not substitute a root service or
invent a terminal-session API.

Exclusive mirroring use is required: the pinned dependency's supported cleanup
stops all media streams on the selected device. Do not start while another
mirror or device-control session must remain active. The local lock cannot
establish that exclusivity on the device or on another computer.

Choose the authorized mode before starting; this example explicitly uses USB.
Change `connection` to `auto` or `wifi` when appropriate. Omit `--serial` and its
argument only when automatic selection of the sole device/record is intended.

```sh
set -e
umask 077
session=$(mktemp -d "${XDG_RUNTIME_DIR:?}/apple-device-usb.XXXXXX")
unit="apple-device-usb-${session##*.}"
connection=usb
mkfifo "$session/input"
systemd-run --user --unit="$unit" --collect \
  --property=UMask=0077 \
  --property="StandardOutput=append:$session/events.jsonl" \
  --property="StandardError=append:$session/stderr.log" \
  "$(command -v bash)" -c \
  'exec 3<>"$1/input"; exec "$2" --connection "$3" --serial "$4" <&3' \
  _ "$session" "$(command -v apple-device-usb)" "$connection" '<observed-identifier>'
printf 'session=%s\nunit=%s\n' "$session" "$unit"
```

Record the absolute session directory and unit name. Restore those literal
values in later shell calls; shell variables do not persist. The absolute Nix
launcher path is required because user services do not inherit the shell PATH.

Read complete new lines from `events.jsonl` with the available file-reading tool.
Track consumed lines. The initial event reports the actual `connection`, the
`requested_connection`, private device identifiers, and
`frame`, `image`, `size`, `original`, `orientation`, and `touch_rotation`. Open
`image` with the available image tool and use that image's pixel dimensions.
The default longest edge is 1280px; both preview and full-size captures remain
under `~/Pictures/apple-device`, outside the transient logs.

A launched unit is not a successful connection. Startup has a 90-second budget,
including tunnel and service setup. If no initial frame arrives,
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

## 4. Close the helper and media session

Send `{"quit":true}` through the same FIFO. Confirm the new `closed` event and
inactive service before removing only the recorded temporary session directory.
Normal exit releases input, requests media shutdown, then closes owned receiver
tasks, media/display resources, and finally the tunnel. On pymobiledevice3
11.15.5, `DisplayService.stop_all_streams(rsd)` opens a fresh display connection;
reusing the start connection or passing the session UUID to `stop_media_stream`
is invalid. This stops all media streams on the selected device, which is why
exclusive use is required. Cleanup failures report an error, not `closed`.
SIGINT/SIGTERM request the same context cleanup. If stuck, stop the exact
recorded unit with `systemctl --user stop "$unit"`, inspect its logs, and confirm
it is inactive; do not claim a graceful close without the event. `closed` confirms
local cleanup, not the remote service's state. Keep the shared
`apple-device-usb.lock` file in place; closing its descriptor releases the lock.

Captures are not deleted with session logs. Keep only task-needed captures under
the user's retention instructions; never delete unrelated images. Report only
visually verified operations, show relevant captures using absolute paths, and
distinguish setup success, screenshot success, input success, and cleanup status.

## Diagnose the failing layer; never replay blindly

| Observation | Next step |
| --- | --- |
| Empty USB list or `RX transfer stalled` | Inspect `journalctl -u usbmuxd` and USB topology locally. A different controller/port resolved the original citrus case; bus numbers are not stable identities. Preserve daemon/firewall settings and pairing records. |
| Missing/ambiguous Wi-Fi pairing or unreachable LAN peer | Confirm the selected identifier and prior authorization for Wi-Fi. Do not pair automatically, delete other records, use a VPN as fallback, or reopen a failed USB session as Wi-Fi. |
| Trust, Developer Mode, or developer-image error | Return to the selected device's prerequisite check. No automatic pairing, image replacement, or reboot. |
| Missing/zero media capabilities | Report the compatibility limit. A mounted image is insufficient evidence; do not repeatedly reconnect. |
| Screenshot works but input does not | Check geometry/calibration separately from the media/HID connection. If the stock `display get-media-stream-server-status` also times out, stop HID retries and request a user-controlled device restart. |
| Validation error without `stopped` | Inspect the error and obtain a fresh shot if needed; correct the request only after checking state. |
| `stopped:true`, disconnect, or failed result capture | Input may already have run. Inspect logs, close the owned session, and establish current state before a justified new connection. Never replay the failed input automatically. |

Calls, locking, or other device activity can interrupt services; do not interpret
a stall as permission to change security settings. Omarchy reports call-related
interruptions on its test phone, not a verified recovery rule for this helper.

For an explicitly requested VNC viewer only, inspect the installed
`display serve-vnc --help` first. Bind to `127.0.0.1` (for example port 5901), never
LAN or wildcard addresses: the upstream server is unauthenticated despite its
password prompt. Close this helper before opening another controller; a viewer
is not a fallback for uncertain input or corrupted captures.
