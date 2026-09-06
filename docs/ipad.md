# iPad access from citrus

`hosts/citrus/ipad.nix` enables `usbmuxd` and installs a system-wide
`pymobiledevice3` launcher pinned to 11.4.2. Nix owns the launcher, Python,
compiler, and native libraries; uv owns the Python packages in the user's
tool environment (`~/.local/share/uv/tools/pymobiledevice3` for `keewai`).
The launcher reuses that persistent installation and can download a cached
environment if it is absent. Python dependencies are outside the Nix store;
only the top-level pymobiledevice3 version is pinned.

Connect the iPad by USB, unlock it, and accept **Trust This Computer**.

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

Coordinate taps use unsigned normalized coordinates: top-left `(0, 0)` to
bottom-right `(65535, 65535)`. Inspect a current screenshot before tapping.
For a pixel coordinate `(x, y)` in an image of width `w` and height `h`, the
upstream conversion is `round(x * 65535 / w)`, `round(y * 65535 / h)`.

```sh
# Example: tap the screen center (only run when the target is safe).
pymobiledevice3 developer core-device universal-hid-service tap -- 32768 32768
pymobiledevice3 developer dvt screenshot ~/Pictures/ipad/after-tap.png
```

If listing the USB identifier works but full device information hangs, check
the lock/trust prompt, then reconnect the cable with the iPad unlocked.
`journalctl -u usbmuxd` shows the local USB transport status.

Upstream references: [CLI recipes](https://doronz88.github.io/pymobiledevice3/guides/cli-recipes/)
and [iOS 17+ tunnels](https://doronz88.github.io/pymobiledevice3/guides/ios17-tunnels/).
