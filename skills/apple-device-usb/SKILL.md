---
name: apple-device-usb
description: >-
  Operate USB-connected iPhones and iPads with pymobiledevice3: verify connection,
  capture screenshots, and send touch gestures or hardware-button events. Use
  for real iOS/iPadOS device interaction, not simulators, macOS desktop control,
  or firmware restore.
---

# Apple device control over USB

Use the installed `pymobiledevice3` CLI. Start with the user's requested device
and operation; a connectivity check does not require changing Nix configuration.
This workflow uses 11.5.0; connection, screenshots, taps, and the Home button
were verified on iPadOS 27.0. Check installed command help when the version
or device differs.

## Establish the connection

Confirm the local runtime host with `hostnamectl --static` (fall back to
`hostname`) and compare it with `/etc/hostname`; stop on a mismatch. Operate the
locally attached device, not a different computer's USB connection.

```bash
pymobiledevice3 version
systemctl is-active usbmuxd
timeout -k 3 15 pymobiledevice3 usbmux list --simple
timeout -k 3 20 pymobiledevice3 usbmux list
```

Identify the device by its observed UDID, name, and connection type. If several
devices are present and the intended one is unclear, ask the user. Set
`PYMOBILEDEVICE3_UDID` to the selected identifier for every subsequent CLI
invocation, including screenshots and gestures. Environment variables set in
one shell tool call do not automatically persist into the next.

Ask for unlocking and **Trust This Computer** only when needed. Then check:

```bash
timeout -k 3 20 pymobiledevice3 amfi developer-mode-status
```

If Developer Mode is disabled, `pymobiledevice3 amfi reveal-developer-mode`
reveals its entry. The user enables it in **Settings > Privacy & Security >
Developer Mode**, restarts the device, and completes the on-device confirmation.
Mount the Developer Disk Image once per device boot:

```bash
pymobiledevice3 mounter auto-mount
```

The first mount may download an image; allow the download to finish. On iOS
17.4+ the installed CLI can use an unprivileged userspace tunnel automatically.
Use `--userspace` explicitly on developer commands if needed. Do not introduce
a persistent root tunnel or open firewall ports for this working USB path.
Older iOS versions may need a different transport; consult current upstream
instructions instead of treating this version's path as universal.

## Capture and inspect

Use the user's absolute output path, or a fresh file under
`/home/keewai/Pictures/apple-device`. For example, with the selected UDID set:

```bash
mkdir -p /home/keewai/Pictures/apple-device
apple_capture="/home/keewai/Pictures/apple-device/screen-$(date +%Y%m%d-%H%M%S).png"
timeout -k 3 40 pymobiledevice3 developer dvt screenshot "$apple_capture"
test -s "$apple_capture"
pymobiledevice3 developer core-device get-display-info
```

Some CLI failures log `ERROR` but exit with status zero. Verify that a **new,
nonempty image** exists, then inspect it with the image-viewing tool. Select a
target from that actual image. Read the primary display's dimensions and
orientation from `get-display-info`; inactive external displays can also appear
in its output. Do not confuse a tool's resized preview with the original pixels.

## Map coordinates and operate

HID coordinates are integers from 0 to 65535 in the digitizer's native
orientation. The CLI sends them unchanged; screenshot orientation matters.
For a pixel target `(x, y)` in a screenshot of width `w` and height `h`, compute:

```text
u = round(x * 65535 / w)
v = round(y * 65535 / h)
```

On the verified iPad17,3 in **landscapeLeft**, the working mapping is
**`hid_x = 65535 - v`, `hid_y = u`**. Direct `(u, v)` taps missed the target.
This was verified with two different targets, not just the screen center.
Other device/orientation combinations were not tested: establish the mapping
with a harmless, visibly verifiable target before consequential interaction.
Recompute after rotation, resolution changes, or a changed screen layout.
Reject out-of-bounds targets rather than clamping them to another control.

After assigning the calculated integer coordinates in the same shell call:

```bash
timeout -k 3 30 pymobiledevice3 developer core-device universal-hid-service tap -- "$hid_x" "$hid_y"
```

Capture and inspect the result before the next dependent action. A successful
send is not proof that the intended control was activated. During a connection
demo, opening Settings or selecting a settings category is sufficient; changing
a setting is unnecessary.

For a touch swipe or scroll, use **`drag`**, converting both endpoints:

```bash
timeout -k 3 30 pymobiledevice3 developer core-device universal-hid-service drag --steps 30 --duration 0.6 -- "$hid_x1" "$hid_y1" "$hid_x2" "$hid_y2"
```

In 11.5.0 the command named `swipe` sends pointer motion **without touch
contact**, so it is not interchangeable with a finger swipe. `tap` and `drag`
automatically open the media stream needed for touch delivery. For a known
sequence, `universal-hid-service session` accepts `tap`, `drag`, and `sleep`
lines through stdin or `--script` with an absolute file path, sharing one
stream. Keep actions that depend on a new screen separated by visual checks.

The Home button has its own working path:

```bash
timeout -k 3 30 pymobiledevice3 developer core-device hid button home press
```

## Diagnose without repeating failed experiments

An empty USB list, a stalled lockdown query, and a touch that misses despite
working screenshots are different failures. Check `journalctl -u usbmuxd` and
the USB topology before changing packages or repeatedly rebooting devices.

On **citrus's ROG STRIX B850-I GAMING WIFI**, the rear **DP-capable USB-C** port
worked with stock usbmuxd and GVFS enabled. Earlier ports all used the chipset
controller (`bus 6`, `xhci-pci-prom21`) and produced `RX transfer stalled`;
the working port used another controller (`bus 1`). Both reported 480 Mbps.
Bus numbers are session observations, not permanent identifiers. If this error
recurs, try a different controller path, not merely another connector on the
same controller. The exact hardware-versus-driver cause was not established.

Do not repeat the failed daemon/library/protocol variants as routine setup.
For persistent failures, report the observed layer and required physical action
instead of an unbounded retry loop. Restore any temporary service overrides or
firewall changes before ending diagnostics; preserve pairing records and never
print their private keys. Do not switch to wireless pairing merely because USB
needs a different port.

The local verified setup and diagnostic history are in
[/home/keewai/nixos-configuration/docs/ipad.md](/home/keewai/nixos-configuration/docs/ipad.md).
The Nix-owned launcher is declared in
[/home/keewai/nixos-configuration/home/keewai/citrus/ipad.nix](/home/keewai/nixos-configuration/home/keewai/citrus/ipad.nix).
For version-specific commands, use the installed `--help` and upstream
[CLI recipes](https://doronz88.github.io/pymobiledevice3/guides/cli-recipes/)
and [tunnel guide](https://doronz88.github.io/pymobiledevice3/guides/ios17-tunnels/).

Report what was actually verified and display captured images with an absolute
filesystem path. Do not claim touch success from an exit code alone.
