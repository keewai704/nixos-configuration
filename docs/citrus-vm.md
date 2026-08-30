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
| [`hosts/citrus-vm/theme.nix`](../hosts/citrus-vm/theme.nix) | Canonical Catppuccin palette, semantic colors, and application theme selections |
| [`hosts/citrus-vm/hardware-configuration.nix`](../hosts/citrus-vm/hardware-configuration.nix) | Generated machine hardware, filesystems, and swap |
| [`hosts/citrus-vm/hyprland.lua`](../hosts/citrus-vm/hyprland.lua) | Hyprland behavior and key bindings; Nix prepends the shared theme table |
| [`hosts/citrus-vm/desktop.nix`](../hosts/citrus-vm/desktop.nix) | Thunar, GVfs, Tumbler, Xarchiver, and the ChatGPT application |
| [`hosts/citrus-vm/browser.nix`](../hosts/citrus-vm/browser.nix) | Firefox default handlers, Brave Origin, and vendor-scoped WebHID access |
| [`hosts/citrus-vm/codex.nix`](../hosts/citrus-vm/codex.nix) | Home Manager, system MCP configuration, personal skills, and CUA |
| [`pkgs/chatgpt-desktop/default.nix`](../pkgs/chatgpt-desktop/default.nix) | ChatGPT desktop package and launcher |
| [`pkgs/cua-driver/default.nix`](../pkgs/cua-driver/default.nix) | CUA driver package |

`desktop.nix` imports `codex.nix`, which imports Home Manager and
`mcp-servers-nix`. The complete desktop stack therefore stays inside the Citrus
host directory.

## Desktop

The session starts Hyprland through UWSM and greetd. Hazkey is the default
Fcitx5 input method. Thunar is the directory handler and is paired with GVfs,
Tumbler, and Xarchiver without installing a full desktop environment.
`hosts/citrus-vm/theme.nix` is the single source for the Catppuccin Mocha Blue
palette and semantic colors. Kitty and Hyprland are generated directly from
it, and Home Manager exports the same colors to QuickShell/K4 as
`~/.config/k4/theme.json`; GTK, Qt/Kvantum, Fcitx5, Colloid icons and cursors,
the virtual console, and tuigreet select their matching variants from the same
theme definition.
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
fcitx5-remote --check
fcitx5-remote -n
xdg-mime query default x-scheme-handler/http
xdg-mime query default x-scheme-handler/codex
chatgpt --version
cua-driver doctor
codex mcp list
```

For theme, input-method, wallpaper, or window-manager changes, verify the
running Hyprland session directly as well as the corresponding service status.
