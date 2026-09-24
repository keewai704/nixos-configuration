# Compatibility and troubleshooting

Diagnose the failing layer without replaying uncertain input. External advice
does not authorize repairs, reconnects, or security-setting changes.

## Compatibility and implementation

The helper reuses one userspace tunnel, DVT screenshot channel, CoreDevice
media/HID session, and virtual keyboard. RTCP receiver reports keep the media
session alive between inputs. No root tunnel or VNC server is needed; the media
transport still uses sockets.

The provider adapter uses the pinned library's private `_aopen_locked` hook, as
Omarchy does. It restores the temporary provider selector on success, failure,
and cancellation while the lifecycle lock is held. Unlike the stock USB-preferred
selector, its USB provider requires `connection_type="USB"`. Review this adapter
when changing the dependency version.

Omarchy decodes HEVC directly in MPV and gates input on viewer focus. This helper
uses inspected screenshots and frame IDs instead; there is no viewer-focus gate.
Do not copy MPV coordinates or shortcuts. Linux PyAV VNC frames were visibly
corrupted in the original local 11.5.0 test; never select targets from damaged
VNC frames.

USB requires iOS/iPadOS 17.4+, but not every device on those versions supports
these display/input services. The original local verification used pymobiledevice3
11.5.0 and iPadOS 27.0 on iPad17,3; it does not verify later dependencies.
Omarchy's reported ARM64/iPhone 13/iOS 27 results are not a support guarantee for
this helper. A mounted developer image, advertised display service, or successful
command does not prove screenshots or input work. Stop on unavailable media
capabilities rather than cycling images.

## Diagnose the failing layer

| Observation | Next step |
| --- | --- |
| Empty USB list or `RX transfer stalled` | Inspect `journalctl -u usbmuxd` and USB topology locally. A different controller/port resolved the original citrus case; bus numbers are not stable identities. Preserve daemon/firewall settings and pairing records. |
| Missing/ambiguous Wi-Fi pairing or unreachable LAN peer | Confirm the selected identifier and authorization for Wi-Fi. Do not pair automatically, delete other records, use a VPN fallback, or reopen failed USB as Wi-Fi. |
| Trust, Developer Mode, or image error | Return to the selected device's prerequisite check. No automatic pairing, image replacement, or reboot. |
| Missing/zero media capabilities | Report the compatibility limit. A mounted image is insufficient evidence; do not repeatedly reconnect. |
| Screenshot works but input does not | Check geometry/calibration separately from media/HID. If stock `display get-media-stream-server-status` also times out, stop HID retries and request a user-controlled device restart. |
| Validation error without `stopped` | Inspect the error and obtain a fresh shot if needed; correct the request only after checking state. |
| `stopped:true`, disconnect, or failed result capture | Input may already have run. Inspect logs, close the owned session, and establish current state before a justified new connection. Never replay automatically. |

Calls, locking, or other activity can interrupt services; a stall is not permission
to change security settings. Omarchy reports call-related interruptions on its
test phone, not a verified recovery rule for this helper.

## Explicitly requested VNC viewer

Inspect the installed `display serve-vnc --help` first. Bind to `127.0.0.1`
(for example port 5901), never LAN or wildcard addresses: the upstream server is
unauthenticated despite its password prompt. Close this helper before another
controller. A viewer is not a fallback for uncertain input or corrupted captures.
