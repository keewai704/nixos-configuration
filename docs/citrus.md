# citrus

`citrus` is the local graphical workstation. It runs a Hyprland
session and the locally packaged ChatGPT desktop application used by Codex.

For the mandatory validation and activation sequence, use the
[development workflow](development.md). Only a machine whose confirmed runtime
hostname is `citrus` may run `nixos-rebuild test` or `switch` for this host.

## Composition

| Path | Responsibility |
| --- | --- |
| [`hosts/citrus/default.nix`](../hosts/citrus/default.nix) | Host imports, Hyprland session, Hazkey/Fcitx5, wallpaper, graphics, and state version |
| [`hosts/citrus/theme.nix`](../hosts/citrus/theme.nix) | Stylix palette adapter for Hyprland, Noctalia, and tuigreet |
| [`hosts/citrus/hardware-configuration.nix`](../hosts/citrus/hardware-configuration.nix) | Generated machine hardware, filesystems, and swap |
| [`hosts/citrus/hyprland.lua`](../hosts/citrus/hyprland.lua) | Hyprland behavior and key bindings; Nix prepends the shared theme table |
| [`hosts/citrus/desktop.nix`](../hosts/citrus/desktop.nix) | Thunar, GVfs, Tumbler, Xarchiver, and the ChatGPT application |
| [`hosts/citrus/fingerprint.nix`](../hosts/citrus/fingerprint.nix) | CS9711 fingerprint driver, fprintd, and local PAM authentication |
| [`hosts/citrus/browser.nix`](../hosts/citrus/browser.nix) | Firefox via `my-firefox-nix`, Brave Origin, Pywalfox, default handlers, and vendor-scoped WebHID access |
| [`hosts/citrus/codex.nix`](../hosts/citrus/codex.nix) | Home Manager, system MCP configuration, personal skills, and CUA |
| [`pkgs/chatgpt-desktop/default.nix`](../pkgs/chatgpt-desktop/default.nix) | ChatGPT desktop package and launcher |
| [`pkgs/cua-driver/default.nix`](../pkgs/cua-driver/default.nix) | CUA driver package |

The host entry point imports the browser, Codex, desktop, and hardware modules
explicitly. `codex.nix` imports Home Manager and `mcp-servers-nix`; the complete
desktop stack therefore stays inside the Citrus host directory without hidden
cross-module imports.

## Physical hardware

The host runs on the physical Citrus workstation. The generated hardware
configuration mounts `/` from ext4 UUID
`c751e1e4-4e57-4683-af63-66e3e39fdefc`, `/boot` from vfat UUID `CC6E-5D4E`,
and `/data` from XFS UUID `d8f1e5d1-774f-4b3d-85ac-6d4f938e8a51`; swap uses
UUID `8ad5ac3d-46a7-431a-9568-077dec33aa91`. The host uses
`linuxPackages_cachyos` with the cached NVIDIA driver, open modesetting, and
NVIDIA initrd modules. Hyprland identifies the primary display as
`DP-1` / `Dell Inc. AW3926QW` at `5120x2160@165`.

## Desktop

The session starts Hyprland through UWSM and greetd. Home Manager installs
Noctalia v5 from the pinned nixpkgs input and runs it as a systemd user service
for the graphical session. Hazkey is the default Fcitx5 input method. Thunar is
the directory handler and is paired with GVfs, Tumbler, and Xarchiver without
installing a full desktop environment.
The community-maintained [Stylix](https://github.com/nix-community/stylix)
module applies the faithful Tokyo Night Base16 palette to supported NixOS and
Home Manager targets. It owns GTK3/4, Qt5/6 through Base16 Kvantum, Kitty, the
virtual console, and Brave's browser theme color. Neutral dark Colloid icons
and cursors remain the system-wide choice.

`hosts/citrus/theme.nix` adapts `config.lib.stylix.colors` for components
outside the generic targets: the custom Hyprland Lua session, Noctalia's
`Stylix` palette, and tuigreet. The immutable Noctalia baseline selects that
palette with `theme.source = "custom"`, the Stylix font, and the Stylix
wallpaper. Noctalia's app templates stay disabled so Stylix remains the source
of application themes. All GUI changes are written separately to
`~/.local/state/noctalia/settings.toml`, load after the
baseline, and remain editable and persistent. Open Settings with `Super+Z`.
GNOME Keyring supplies Secret Service for Noctalia's encrypted clipboard history.
Fcitx5 uses [Stylix's Home Manager target](https://nix-community.github.io/stylix/options/modules/fcitx5.html)
for its candidate panel, menu, and fonts. NixOS still provides Hazkey, the input
method profile defaults, and UWSM's XDG autostart; Home Manager reuses that
package with its extra daemon disabled. Only the managed Classic UI file is
linked, leaving other Fcitx5 settings and dictionaries writable. Home Manager's
Wayland input-method integration also supplies GTK's X11 fallback and the
Kitty/SDL input-module variables without forcing a global GTK input module.
Stylix's Firefox target stays disabled to leave the `my-firefox-nix` profile
styling under the browser module's control.

GTK applications such as Thunar and Xarchiver inherit it directly, while
Firefox, Brave, and ChatGPT receive the shared dark desktop preference.
Noctalia, GTK/Qt, and Fcitx5 share Stylix's Noto Sans CJK JP sans-serif font;
Fcitx5's Classic UI uses the rounded panel generated from the same palette.

The initial wallpaper is repository-owned under `hosts/citrus/assets/` and
rendered by Noctalia; choosing another wallpaper in the GUI persists as a user
override. Keep machine-specific display and GPU settings in the
host entry point, not in a module used by Orange.

## Fingerprint authentication

The USB Chipsailing CS9711 (`2541:0236`) uses `fprintd` with the pinned
[community CS9711 driver](https://github.com/archeYR/libfprint-CS9711).
Upstream libfprint does not support this reader. The driver and its SIGFM
matcher are experimental; successful enrollment and matching do not establish
their false-acceptance rate or security.

Enroll and verify a finger as the desktop user:

```console
fprintd-enroll -f right-index-finger
fprintd-verify -f right-index-finger
fprintd-list "$USER"
```

Enrollment takes 15 scans; lift and reposition the same finger between scans.
The system stores templates under `/var/lib/fprint`, outside the Nix store and
Git. Local PAM services support fingerprint authentication with password
fallback, and Noctalia's lock screen uses fprintd directly. SSH fingerprint
authentication is disabled. Existing automatic login and passwordless wheel
sudo settings remain in effect; fingerprint login does not unlock GNOME
Keyring's password-encrypted secrets.

After changing the driver, run `bash hosts/citrus/check-fingerprint.sh` locally
with the screen unlocked and no finger on the sensor. It checks recognition,
cancellation during initialization and scanning, and reopening the device.

## Browsers and URL handlers

Firefox is the default browser for HTTP, HTTPS, HTML, and unknown URL schemes.

The `my-firefox-nix` flake input supplies its Sine/Natsumi customization, six
marketplace mods, and Japanese localization. Their source and update
instructions live in
[`keewai704/my-firefox-nix`](https://github.com/keewai704/my-firefox-nix).
The flake fetches it from `git+https://github.com/keewai704/my-firefox-nix.git`.
Commit and push changes to that repository's `main` branch, then run
`nix flake update my-firefox-nix` here before following the normal validation
and activation workflow. Fetching the private repository requires Git
authentication with an account that has read access.

Home Manager deploys the module's managed files into the default profile's
`chrome/` directory. Bookmarks, history, extensions, and `prefs.js` remain
user-managed. Restart Firefox after applying browser-module changes.

Brave Origin is also installed for sites that require Chromium behavior.
`x-scheme-handler/codex` remains mapped to `chatgpt.desktop` so authentication
and deep links return to the desktop application.

The Nix-managed Pywalfox native messenger is registered in the wrapped Firefox
package, and Home Manager publishes the shared Tokyo Night palette at
`~/.cache/wal/colors.json`. The Pywalfox Firefox add-on, its settings, and its
optional profile CSS remain user-managed; this configuration does not install
or modify them.

WebHID access is granted through vendor-scoped udev rules for the configured
TwinStar keyboard and OpenMouse-compatible device vendors. The rules do not
grant blanket access to every `hidraw` device.

## ChatGPT desktop package

The package repacks OpenAI's official Linux `.deb` for NixOS, patches its ELF
dependencies, and installs the upstream desktop entry and icon. Debian
maintainer scripts are not run, so it does not add an APT repository or write
outside the Nix store during the build. NixOS is a repository-supported
compatibility target rather than an upstream-supported distribution.
[OpenAI documents the upstream application and supported Linux distributions](https://developers.openai.com/codex/app).

The version, source URL, and hashes have one source of truth:
`pkgs/chatgpt-desktop/default.nix`. Update them there rather than copying them
into documentation.

Build the standalone flake output with:

```console
nix build .#chatgpt-desktop
```

After the host configuration has been applied, verify the installed commands:

```console
chatgpt --version
command -v chatgpt
command -v codex-desktop
```

`chatgpt` is the canonical executable; `codex-desktop` is a convenience alias.

### Writable resource overlay

The application rewrites bundled plugin manifests while materializing them.
Nix store resources are immutable, so the launcher creates a versioned writable
overlay below:

```text
~/.cache/chatgpt/bundled-plugin-resources/
```

Writable plugin resources are copied there and immutable siblings remain linked
to the Nix store. This cache is derived state, not a configuration source.

### Wayland and Japanese input

The host sets `NIXOS_OZONE_WL=1`. When a live Wayland display is present, the
launcher translates that opt-in into Chromium's native Wayland and Wayland IME
flags so Fcitx5 inline preedit works. User-supplied arguments remain last and
can override the platform.

Compare the upstream XWayland fallback with:

```console
env -u NIXOS_OZONE_WL chatgpt
```

## System and user configuration boundary

| Path | Owner and purpose |
| --- | --- |
| `/etc/codex/config.toml` | Nix-generated system MCP and developer-instruction layer shared by ChatGPT Desktop, Codex CLI, and the IDE extension; immutable at runtime |
| `~/.codex/config.toml` | Writable application/user layer for bundled helpers, plugin state, project trust, UI settings, and unrelated preferences |
| `skills/<name>/` | Repository source for personal skills |
| `~/.agents/skills/<name>` | Home Manager links to repository-owned personal skills |
| `~/.cache/chatgpt/bundled-plugin-resources/` | Disposable writable resource overlay |

A user MCP entry shadows a system entry of the same name. Home Manager removes
only user-level entries whose names are owned by the Nix MCP registry; bundled
`node_repl`/`cua_repl` entries and unrelated preferences remain writable and
untouched.

After changing an MCP server or personal skill, rebuild through the development
workflow and restart ChatGPT Desktop or begin a new local session.

## MCP and CUA

The declarative MCP registry enables Context7, the NixOS server, Serena, the
OpenAI Developer Docs endpoint, and the local CUA driver. Inspect deployed
state with:

```console
codex mcp list
codex mcp get context7
codex mcp get cua-driver
readlink -f /home/keewai/.agents/skills/add-nix-mcp
readlink -f /home/keewai/.agents/skills/add-nix-skill
```

The CUA wrapper imports the active Wayland, XWayland, D-Bus, and Hyprland
session variables before starting its local stdio MCP server. Native Wayland
and the driver's `standard` permission mode are enabled; telemetry and mutable
update checks are disabled. The system AT-SPI service provides accessibility
tree access. Codex marks the driver's write-capable tools as writes, while the
effective prompt behavior still depends on the active global approval policy.

The third-party driver is separate from ChatGPT Desktop's bundled `cua_repl`
helper. Verify it with:

```console
cua-driver --version
cua-driver doctor
codex mcp get cua-driver
```

## Verification

After both `test` and `switch`, run the common checks from
`docs/development.md` and verify the graphical/user components affected by the
change. Typical checks are:

```console
systemctl is-active greetd
systemctl --user --no-pager --full status noctalia.service
noctalia --version
noctalia config validate
noctalia msg status
test "$(noctalia msg color-scheme-get)" = "custom Stylix"
busctl --user list | rg org.freedesktop.secrets
systemctl --user show-environment | rg 'WAYLAND_DISPLAY|DISPLAY|DBUS_SESSION_BUS_ADDRESS'
test -r /etc/stylix/palette.html
fcitx5-remote --check
fcitx5-remote -n
rg '^Theme=stylix$' ~/.config/fcitx5/conf/classicui.conf
test -r ~/.local/share/fcitx5/themes/stylix/theme.conf
test -d ~/.config/fcitx5 && test ! -L ~/.config/fcitx5
xdg-mime query default x-scheme-handler/http
xdg-mime query default x-scheme-handler/codex
pywalfox --version
jq -e '.colors | length == 16' ~/.cache/wal/colors.json
firefox_root="$(dirname "$(dirname "$(readlink -f "$(command -v firefox)")")")"
jq -e '.name == "pywalfox"' "$firefox_root/lib/mozilla/native-messaging-hosts/pywalfox.json"
chatgpt --version
cua-driver doctor
codex mcp list
```

For theme, input-method, wallpaper, or window-manager changes, verify the
running Hyprland session directly as well as the corresponding service status.
