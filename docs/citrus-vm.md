# citrus-vm

`citrus-vm` is the local graphical workstation. It runs a small Hyprland
session and the locally packaged ChatGPT desktop application used by Codex.

For the mandatory validation and activation sequence, use the
[development workflow](development.md). Only a machine whose confirmed runtime
hostname is `citrus-vm` may run `nixos-rebuild test` or `switch` for this host.

## Composition

| Path | Responsibility |
| --- | --- |
| [`hosts/citrus-vm/default.nix`](../hosts/citrus-vm/default.nix) | Host imports, Home Manager setup, Hyprland session, Hazkey/Fcitx5, graphics, and state versions |
| [`hosts/citrus-vm/hardware-configuration.nix`](../hosts/citrus-vm/hardware-configuration.nix) | Generated machine hardware, filesystems, and swap |
| [`hosts/citrus-vm/hyprland.lua`](../hosts/citrus-vm/hyprland.lua) | 43PR Hyprland behavior and key bindings with Citrus hardware adaptations |
| [`hosts/citrus-vm/desktop.nix`](../hosts/citrus-vm/desktop.nix) | 43PR desktop components, Thunar, and the ChatGPT application |
| [`hosts/citrus-vm/browser.nix`](../hosts/citrus-vm/browser.nix) | Firefox, Brave Origin, Pywalfox, default handlers, and vendor-scoped WebHID access |
| [`hosts/citrus-vm/codex.nix`](../hosts/citrus-vm/codex.nix) | System MCP configuration, personal skills, Ponytail hooks, and CUA |
| [`pkgs/chatgpt-desktop/default.nix`](../pkgs/chatgpt-desktop/default.nix) | ChatGPT desktop package and launcher |
| [`pkgs/cua-driver/default.nix`](../pkgs/cua-driver/default.nix) | CUA driver package |

The host entry point imports Home Manager and the browser, Codex, desktop, and
hardware modules explicitly. It owns the shared Home Manager settings and
state version; `codex.nix` imports only the application-specific
`mcp-servers-nix` Home Manager module.

## Desktop

The session starts Hyprland through UWSM and greetd. Home Manager pins
[43PR/dotfiles](https://github.com/43PR/dotfiles) at commit
`5354e7d42cc3d76e63ba749cbc878f3f989939d5`. The desktop reproduces its
Hyprland spacing, blur, opacity, animations, complete key map, wallpapers,
Waybar, Rofi, Hyprlock, Wlogout, hyprquickpaper, Quickshell volume OSD, GTK,
Kitty, btop, cava, and Spotify's Spicetify text/Monochrome styling (including
Marketplace). Spicetify patches Spotify at build time, not the read-only Nix
store at runtime. Home Manager's native services run Waybar, Dunst, awww,
cliphist, hyprsunset, the network applet, and the Hyprland polkit agent.

Hyprland reads the stable `~/.config/hypr/hyprland.lua` Home Manager link rather
than a generation-specific command-line path. It includes the writable
`hyprland-gui.lua` used by HyprMod; the base file remains Nix-managed. `Super+O`
updates named opacity rules immediately and saves the selection under
`$XDG_STATE_HOME/43pr-opacity` (default `~/.local/state/43pr-opacity`).
Migrating an already running session from an old `--config /nix/store/...`
launch requires restarting greetd/the graphical session; a reload cannot
change the compositor's startup path. Restarting greetd closes graphical apps.

Xed, nwg-look, mpv, and HyprMod are installed. GTK settings and Xed shortcuts
are initialized from upstream only when absent, then remain writable for their
editors. GTK CSS remains Nix-managed. Neowofetch (from hyfetch) reads the
upstream neofetch configuration; unmaintained neofetch is no longer in nixpkgs.
Home Manager also initializes the matching GTK theme, font, and icon dconf
keys, so settings left by the previous desktop do not override `settings.ini`.

The VM has neither a physical GPU telemetry source nor a temperature sensor,
so the matching Waybar slots remain visible as `GPU 0%` and `--°C` instead of
being removed. Recording uses CPU-compatible `wf-recorder` at 30 fps on
`Virtual-1`. `Super+R` starts/stops a systemd user service, which sends SIGINT
on stop to finalize the MP4 in `~/Videos`. Audio comes from the default output's
monitor, not the VM's nonexistent default microphone; missing monitors produce
a notification and video-only recording. Hyprsunset provides software
brightness (20–100%) on the brightness keys and a 3000 K toggle on Waybar's
temperature slot because this VM has no backlight or hardware gamma control.
The browser shortcut opens the configured Firefox, and `Super+X` toggles
Fcitx5 rather than a second XKB layout. UWSM owns app/session lifecycle, and
Kitty uses the installed JetBrainsMono Nerd Font instead of Consolas.

Hazkey is the default Fcitx5 input method. Thunar is the directory handler and
is paired with GVfs, Tumbler, and Xarchiver without installing a full desktop
environment.
The community-maintained [Stylix](https://github.com/nix-community/stylix)
module applies the Tokyo Night Base16 palette to the remaining supported NixOS
and Home Manager targets. The 43PR source owns GTK3/4 and Kitty; Qt5/6, the
virtual console, Brave's browser theme color, and the system cursor remain
Stylix-managed. GTK uses the rice's white-folder Papirus variant.

The host entry point declares the cursor, icon, Fcitx5, and tuigreet settings
directly. `browser.nix` uses Stylix colors for Pywalfox. Fcitx5 keeps
its Tokyo Night Storm panel, while Stylix's Firefox target stays disabled to
leave Sine/Natsumi styling under the browser module's control.

GTK applications such as Thunar and Xarchiver inherit it directly, while
Firefox, Brave, and ChatGPT receive the shared dark desktop preference.
Fcitx5's Classic UI keeps its rounded candidate panel and Noto Sans CJK JP
fonts.

The complete upstream wallpaper set is linked into
`~/Pictures/Wallpapers/43PR` and rendered by awww. The initial background is the
mountain image used by the showcase; the hyprquickpaper picker at `Super+W`
changes it and awww restores its cached selection on later sessions. Keep
machine-specific display and software-rendering settings in the host entry
point, not in a module used by Orange.

## Browsers and URL handlers

Firefox is the default browser for HTTP, HTTPS, HTML, and unknown URL schemes.
The `browser-config` flake input supplies its Sine/Natsumi customization,
six marketplace mods, and Japanese localization. Their source and update
instructions live in the independent repository at `/home/keewai/browser-config`.
Commit changes there, then run `nix flake update browser-config` here before
following the normal validation and activation workflow. Evaluation requires
that local Git repository at the configured path.

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
SparkLink keyboard and OpenMouse-compatible device vendors. The rules do not
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
systemctl --user --no-pager --full status waybar.service awww.service
systemctl --user --no-pager --full status cliphist.service cliphist-images.service
systemctl --user --no-pager --full status quickshell-volume-osd.service hyprpolkitagent.service
systemctl --user is-active hyprsunset.service network-manager-applet.service
hyprctl hyprsunset gamma
hyprctl hyprsunset temperature
hyprctl configerrors
test -w ~/.config/hypr/hyprland-gui.lua
test -w ~/.config/gtk-3.0/settings.ini
waybar --version
quickshell --version
awww query
dunstctl is-paused
busctl --user list | rg org.freedesktop.secrets
systemctl --user show-environment | rg 'WAYLAND_DISPLAY|DISPLAY|DBUS_SESSION_BUS_ADDRESS'
test -r /etc/stylix/palette.html
fcitx5-remote --check
fcitx5-remote -n
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
The offline control regression check runs without changing the live desktop:

```console
nix build .#nixosConfigurations.citrus-vm.config.system.build.desktop43prCheck --no-link
```

Also exercise Rofi, opacity, brightness/night mode, the wallpaper picker,
HyprMod, and a short start/stop recording in the live session. Use `ffprobe` to
check the resulting video/audio streams. Do not test power-off, logout, or
locking by interrupting unsaved work; Spotify playback additionally needs a
user login.
