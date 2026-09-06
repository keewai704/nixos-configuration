# iPad access from citrus

`hosts/citrus/ipad.nix` enables `usbmuxd`.
`home/keewai/citrus/ipad.nix` installs the personal `pymobiledevice3` launcher,
currently pinned to 11.5.0. Nix owns the launcher, Python, compiler, and native
libraries; uv resolves and caches the Python packages in the user's environment.
Python dependencies are outside the Nix store; only the top-level
pymobiledevice3 version is pinned.

On citrus, use the **rear DP-capable USB-C port**. Connect the iPad, unlock it,
and accept **Trust This Computer**. This port was verified working; other
tested ports shared a failing USB controller path (see below).

```sh
pymobiledevice3 version
pymobiledevice3 usbmux list --simple
pymobiledevice3 usbmux list
pymobiledevice3 amfi developer-mode-status
```

If Developer Mode is disabled, reveal its Settings entry with
`pymobiledevice3 amfi reveal-developer-mode`, then enable it under
**Settings > Privacy & Security > Developer Mode**. Complete the iPad's
restart and on-device confirmation before continuing.

Mount the Developer Disk Image once per iPad boot. The first mount downloads
the image. On iPadOS 17.4+, these developer commands automatically use an
unprivileged userspace tunnel; a persistent root tunnel service is unnecessary.

```sh
pymobiledevice3 mounter auto-mount
mkdir -p ~/Pictures/ipad
pymobiledevice3 developer dvt screenshot ~/Pictures/ipad/screen.png
pymobiledevice3 developer core-device get-display-info
```

Coordinate taps use unsigned normalized coordinates in the digitizer's native
orientation. The CLI does **not** rotate them to match the screenshot.
Inspect a current screenshot and `get-display-info` before tapping.

For a screenshot pixel `(x, y)` in an image of width `w` and height `h`, first
calculate `u = round(x * 65535 / w)` and `v = round(y * 65535 / h)`.
On the verified iPad17,3 in **`landscapeLeft`**, send **`(65535 - v, u)`**.
Sending `(u, v)` directly missed the target. Other orientations were not tested;
do not reuse the landscape mapping after rotating the device.

```sh
# Example: tap the screen center (only run when the target is safe).
pymobiledevice3 developer core-device universal-hid-service tap -- 32768 32768
pymobiledevice3 developer dvt screenshot ~/Pictures/ipad/after-tap.png
```

If listing the USB identifier works but full device information hangs, check
the lock/trust prompt, then reconnect the cable with the iPad unlocked.
`journalctl -u usbmuxd` shows the local USB transport status.

On 2026-09-06, an iPad17,3 running iPadOS 27.0 (24A5430a) repeatedly produced
`RX transfer stalled` on the chipset controller (`bus 6`, `xhci-pci-prom21`).
Reboots, different cables/ports on that controller, and temporary USB software
variants did not fix it. Moving to the rear DP-capable USB-C port changed the
controller to `bus 1` and worked with **stock usbmuxd**, including after restoring
the desktop's GVFS automatic device detection. Both paths reported 480 Mbps.
This isolates the failing controller/port path; the precise hardware or driver
cause remains undetermined. Bus numbers are observations from this session,
not stable port identifiers across every boot.

Verified on the working port:

- Developer Mode and Developer Disk Image mounting.
- Repeated 3200×2400 screenshots and the Home button command.
- Coordinate taps opening Settings and then selecting General, confirmed by
  screenshots. The first tap used `(30563, 46636)` after the landscape transform;
  these numbers are evidence from that screen layout, not reusable targets.

Screenshots were saved locally under `~/Pictures/ipad/`, including
`before-tap.png` and `verified-coordinate-tap.png`; they are not stored in Git.
Temporary daemon variants, GVFS masking, and firewall allowances were removed.
No persistent root tunnel or USB software patch is required.

Upstream references: [CLI recipes](https://doronz88.github.io/pymobiledevice3/guides/cli-recipes/)
and [iOS 17+ tunnels](https://doronz88.github.io/pymobiledevice3/guides/ios17-tunnels/).
