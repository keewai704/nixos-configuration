# citrus-vm

`citrus-vm` is the local graphical workstation. It runs a small Hyprland
session and the locally packaged ChatGPT desktop application used by Codex.

For the mandatory validation and activation sequence, use the
[development workflow](development.md). Only a machine whose confirmed runtime
hostname is `citrus-vm` may run `nixos-rebuild test` or `switch` for this host.

## Composition

| Path | Responsibility |
| --- | --- |
| [`hosts/citrus-vm/configuration.nix`](../hosts/citrus-vm/configuration.nix) | Host imports, Hyprland session, Hazkey/Fcitx5, wallpaper, graphics, and state version |
| [`hosts/citrus-vm/theme.nix`](../hosts/citrus-vm/theme.nix) | Stylix palette adapter for Hyprland, K4, Fcitx5, and tuigreet |
| [`hosts/citrus-vm/hardware-configuration.nix`](../hosts/citrus-vm/hardware-configuration.nix) | Generated machine hardware, filesystems, and swap |
| [`hosts/citrus-vm/hyprland.lua`](../hosts/citrus-vm/hyprland.lua) | Hyprland behavior and key bindings; Nix prepends the shared theme table |
| [`hosts/citrus-vm/desktop.nix`](../hosts/citrus-vm/desktop.nix) | Thunar, GVfs, Tumbler, Xarchiver, and the ChatGPT application |
| [`hosts/citrus-vm/browser.nix`](../hosts/citrus-vm/browser.nix) | Pywalfox, Brave Origin, default handlers, and vendor-scoped WebHID access |
| [`hosts/citrus-vm/browser/sine.nix`](../hosts/citrus-vm/browser/sine.nix) | Firefox, pinned Sine assembly, locale validation, and profile activation |
| [`hosts/citrus-vm/codex.nix`](../hosts/citrus-vm/codex.nix) | Home Manager, system MCP configuration, personal skills, and CUA |
| [`pkgs/chatgpt-desktop/default.nix`](../pkgs/chatgpt-desktop/default.nix) | ChatGPT desktop package and launcher |
| [`pkgs/cua-driver/default.nix`](../pkgs/cua-driver/default.nix) | CUA driver package |

The host entry point imports the browser, Codex, desktop, and hardware modules
explicitly. `codex.nix` imports Home Manager and `mcp-servers-nix`; the complete
desktop stack therefore stays inside the Citrus host directory without hidden
cross-module imports.

## Desktop

The session starts Hyprland through UWSM and greetd. Hazkey is the default
Fcitx5 input method. Thunar is the directory handler and is paired with GVfs,
Tumbler, and Xarchiver without installing a full desktop environment.
The community-maintained [Stylix](https://github.com/nix-community/stylix)
module applies the faithful Tokyo Night Base16 palette to supported NixOS and
Home Manager targets. It owns GTK3/4, Qt5/6 through Base16 Kvantum, Kitty, the
virtual console, and Brave's browser theme color. Neutral dark Colloid icons
and cursors remain the system-wide choice.

`hosts/citrus-vm/theme.nix` adapts `config.lib.stylix.colors` for components
outside the generic targets: the custom Hyprland Lua session, QuickShell/K4's
`~/.config/k4/theme.json`, and tuigreet. Fcitx5 keeps its Tokyo Night Storm
panel because its active configuration is managed by the NixOS input-method
module. Stylix's Firefox target stays disabled to avoid replacing Sine and
Natsumi profile styling.

GTK applications such as Thunar and Xarchiver inherit it directly, while
Firefox, Brave, and ChatGPT receive the shared dark desktop preference.
Fcitx5's Classic UI keeps its rounded candidate panel and Noto Sans CJK JP
fonts.

The wallpaper is repository-owned under `hosts/citrus-vm/assets/`. Keep
machine-specific display and software-rendering settings in the host entry
point, not in a module used by Orange.

## Browsers and URL handlers

Firefox is the default browser for HTTP, HTTPS, HTML, and unknown URL schemes.
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

### Firefox Sine mods

Firefox loads Sine through the Nix-generated AutoConfig file. Home Manager
resolves the current default profile from `profiles.ini` and copies Sine's
writable engine, bootloader utilities, and pinned marketplace mods into that
profile's `chrome/` directory. It does not replace the profile or manage
`prefs.js`, extensions, history, or other browser data.

Sine `2.3.3` uses bootloader `0.1.4`. The following marketplace mods are
installed and enabled:

| Mod | Version |
| --- | --- |
| Better Music Bar | `1.0.4` |
| Context Menu Icons | `2.7.4.3` |
| Natsumi Browser | `6.12.1` |
| Tidy Popup & Extension | `2.9.1` |
| Zen Compact Transparent Mode | `2.0.0` |
| Zen Custom URL Bar | `2.0.3` |

The Sine engine and mods are pinned in `browser/sine.nix`, and their mutable
update checks are disabled. Update the release, marketplace revision,
fixed-output hashes, and documented versions together. Sine requires
privileged profile scripts, so the Firefox AutoConfig sandbox is disabled only
as part of this explicit browser configuration.

Firefox's Japanese language pack and requested locale cover the native browser
UI. Sine `2.3.3` has no upstream Japanese locale, so the profile adds matching
Japanese Fluent resources for its settings, toasts, and command palette.
Natsumi `6.12.1` hard-codes its UI in English and exposes no localization API;
a Japanese-only translation layer, restricted to Natsumi/Sine-owned UI in the
pinned release, covers its onboarding, preferences, shortcuts, notifications,
Picture-in-Picture indicator, and the installed mods' preference labels while
leaving preference values and behavior unchanged.

Context Menu Icons is set to its Firefox branch and receives its required SVG
preference. The marketplace lists every mod above as Firefox-compatible, but
Better Music Bar and Zen Compact Transparent Mode target controls that exist
only in Zen Browser, so they have no visible effect in stock Firefox. Zen
Custom URL Bar has only partial Firefox coverage and can overlap Natsumi's URL
bar styling; the requested mods remain installed so Sine can manage them.

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
| `/etc/codex/config.toml` | Nix-generated system MCP layer shared by ChatGPT Desktop, Codex CLI, and the IDE extension; immutable at runtime |
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
systemctl --user --no-pager --full status citrus-wallpaper.service
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
