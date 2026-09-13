# nixos-configuration

Flake-based NixOS configurations for three `x86_64-linux` machines. The layout
separates machine integration from user applications and settings.

## Layout

```text
.
├── flake.nix
├── devshell/
│   ├── default.nix                # repository development tools and Neovim extension
│   └── neovim.lua                 # Nix, Lua, and shell language servers and formatting
├── modules/
│   ├── common.nix                 # system settings used by every host
│   ├── home-manager.nix           # shared NixOS/Home Manager integration
│   ├── desktop.nix                # opt-in desktop profile and system integration
│   ├── codex.nix                  # Codex model preferences, instructions, and MCP conversion
│   ├── codex-ponytail.nix         # managed Ponytail hooks and system skill publication
│   ├── codex-remote.nix           # user server startup before login
│   ├── dconf.nix                  # D-Bus/GIO integration for user GTK settings
│   ├── hyprland-package.nix       # shared Hyprland package selection
│   ├── hyprlock.nix               # PAM authentication for the user-owned locker
│   └── shell.nix                  # login-shell integration
├── home/keewai/
│   ├── common.nix                 # common profile and CLI tools
│   ├── shared/
│   │   ├── codex.nix              # Codex CLI and user override cleanup
│   │   ├── codex-remote.nix       # Codex Remote user service
│   │   ├── mcp.nix                # common MCP server registry
│   │   ├── neovim.nix             # Neovim and pinned lazy.nvim plugins
│   │   ├── neovim.lua             # general editing, search, Git, completion, and key bindings
│   │   ├── skills.nix             # personal skill publication and filters
│   │   ├── apple-device-usb.nix   # pymobiledevice3 launcher and completion
│   │   ├── shell.nix              # interactive shell and CLI integration
│   │   ├── check-shell.zsh        # manual diagnostics for the common shell
│   │   └── starship.toml          # shell prompt
│   └── desktop/
│       ├── applications.nix       # desktop tools without additional configuration
│       ├── apple-music.nix        # Apple Music terminal client and authentication
│       ├── bitwarden.nix          # desktop client, launcher setup, and SSH agent
│       ├── browser.nix            # Brave Origin, native messaging, and URL handlers
│       ├── codex.nix              # Codex desktop client and protocol handler
│       ├── cua.nix                # desktop computer-use driver and MCP server
│       ├── dynamic-island.nix     # desktop shell appearance and preferences
│       ├── file-manager.nix       # Thunar, archives, directory handlers, and XDG folders
│       ├── firefox.nix            # Firefox, Sine/Natsumi, Japanese localization, and profile setup
│       ├── hyperv-rendering.nix    # rendering adaptations when Hyper-V is enabled
│       ├── hyprland.nix           # compositor configuration generation
│       ├── hyprland.lua           # compositor behavior and key bindings
│       ├── input-method.nix       # Fcitx5 and Hazkey integration
│       ├── kitty.nix              # terminal and font settings
│       ├── legcord.nix            # Discord client and theme selection
│       ├── legcord-system24.nix   # System24 CSS for Legcord
│       ├── screen-lock.nix        # Hyprlock appearance and idle/suspend locking
│       ├── steam-theme.nix        # Millennium SpaceTheme CSS
│       └── stylix.nix             # user theme, font, and toolkit integration
├── themes/tokyo-night-black/
│   ├── default.nix                # shared NixOS/Home Manager theme values
│   └── astronaut-and-angel.png    # desktop and lock-screen wallpaper
├── hosts/
│   ├── citrus/
│   │   ├── default.nix            # host entry point
│   │   ├── audio.nix              # PipeWire and Bluetooth LE Audio
│   │   ├── boot.nix               # bootloader and kernel selection
│   │   ├── hardware-configuration.nix
│   │   ├── desktop.nix            # desktop profile and session services
│   │   ├── steam.nix              # Steam/Millennium and Gamescope system integration
│   │   ├── hyprland.nix           # compositor, portal, and greetd login session
│   │   ├── fingerprint.nix        # CS9711 fprintd selection and PAM policy
│   │   ├── check-fingerprint.sh   # local CS9711 cancellation diagnostics
│   │   ├── apple-device-usb.nix   # usbmuxd system service
│   │   ├── nvidia.nix             # NVIDIA driver and stable device path
│   │   ├── stylix.nix             # system theme integration
│   │   └── webhid.nix             # keyboard and mouse hardware access rules
│   ├── citrus-vm/
│   │   ├── default.nix            # Citrus imports and VM host settings
│   │   ├── hardware-configuration.nix
│   │   ├── image.nix              # Hyper-V image format, size, and image-builder fix
│   │   ├── graphics.nix           # Hyper-V graphics package and environment
│   │   └── ssh.nix                # SSH access and authorized key
│   └── orange/
│       ├── default.nix            # host entry point
│       ├── hardware-configuration.nix
│       ├── settings.nix           # values shared inside this host
│       └── services/
│           ├── storage.nix        # HDD mount and shared service-directory preparation
│           ├── samba.nix          # SMB share, firewall, and mount dependencies
│           ├── immich.nix         # media service, database import, and directory permissions
│           ├── vaultwarden.nix    # password service, legacy import, and backup permissions
│           ├── web.nix            # nginx and Tailscale Serve
│           ├── tailscale-exit-node.nix # exit routing and UDP offload
│           ├── minecraft.nix
│           ├── health-monitor.nix
│           ├── local-backup.nix   # versioned Minecraft and Vaultwarden backups
│           ├── smart-tests.nix    # scheduled drive self-tests
│           └── maintenance.nix    # log cleanup, TRIM, and Nix Store maintenance
├── pkgs/                           # package recipes and their patches/runtime helpers
│   ├── apple-music-client/
│   ├── aquamarine-hyperv/
│   ├── brave-origin/
│   ├── chatgpt-desktop/
│   ├── cua-driver/
│   ├── fprintd-cs9711/
│   ├── hyprland/
│   ├── hyprpaper-shm/
│   ├── millennium-steam/
│   └── ponytail-hooks/
├── skills/                         # personal Codex skills
└── secrets/                        # Agenix declarations and ciphertext
```

The ownership rules are intentionally small:

1. Put a setting in `modules/common.nix` only when every host uses it.
2. Put system integration under `hosts/<name>/`, and user applications and
   configuration under `home/<user>/shared/` or `home/<user>/desktop/` according
   to whether they need a desktop session.
3. Put build recipes, skills, and encrypted secrets in their matching top-level
   directory. Shared visual values and assets belong in `themes/`; NixOS and
   Home Manager integration stays in their respective profiles.

Physical host entry points import only files from their own directory.
`citrus-vm` imports Citrus and applies VM-specific hardware and desktop overrides.
Orange modules read `settings.nix` directly, so there is no hidden host-specific
argument injection from `flake.nix`. Its storage module prepares the mounted HDD
directories used by Immich and Vaultwarden; each service owns its application
permissions and import lifecycle.

All three hosts receive the common Home Manager profile: CLI tools, shell,
Codex CLI and Remote, common MCP servers, skills, and the Apple device USB CLI.
Citrus and its VM also import the same desktop profile through
`modules/desktop.nix`: GUI applications, Bitwarden desktop/launcher integration,
CUA, IME, desktop services, and themes. Orange imports only the common profile.
The desktop profile applies Hyper-V rendering adaptations by capability and
uses fingerprint authentication only where fprintd is enabled. Desktop sessions,
drivers, USB access, and other hardware integration remain NixOS-owned.

Prefer Home Manager for personal packages. Keep system scope only for a
concrete integration requirement. Repository policy and validation requirements
live in [`AGENTS.md`](AGENTS.md).

Citrus and its VM use Brave Origin as the default URL handler, managed by
`home/keewai/desktop/browser.nix`. Firefox is also managed by Home Manager in
`home/keewai/desktop/firefox.nix`, which adapts the pinned `main` branch of
`keewai704/my-firefox-nix` without enabling its system-wide Firefox module.
It preserves the upstream Sine/Natsumi configuration, Japanese localization,
Bitwarden/uBlock Origin policies, and locked preferences. Preferences are locked
through AutoConfig so custom Sine settings also apply. The default profile is
initialized before Sine deployment, so the first activation installs the
theme without requiring a preliminary Firefox launch. Stylix's Firefox target
is disabled to leave styling to Sine/Natsumi. Fetching the private input requires
GitHub read authentication.

Siora (`apple-music-client`) runs entirely in a terminal. Start `siora`, use
`Ctrl+f` for Apple Music search, `/` to filter the loaded list, `Enter` to open
or play, `Space` to pause, `e`/`E` to append/play next, and `q` for the editable
queue. `Tab` changes focus, `Backspace` restores the previous page and position,
`a` opens item actions, `?` shows help, and `Ctrl+c` exits. Queue, lyrics, and
details share an optional panel; narrow terminals show one active pane.
`:login` and `:code` handle account authentication, and `,` opens audio settings.
The terminal controls colors and fonts. Existing `alac-room` library, downloads,
and authentication sessions remain compatible. Music videos play audio only.
Selected items show their cover above the list, and the playing track has its
own thumbnail in the playback bar. Images load asynchronously into the private
cache. Kitty uses its graphics protocol; other terminals and tmux use character
block previews. Missing covers leave text controls usable.
The package keeps the pinned upstream media/authentication backend and applies
the terminal frontend in `pkgs/apple-music-client/tui/`; GPUI, browser assets,
and the legacy Python frontend are removed from its build and installation.

## Hosts

| Host | Role | Entry point |
| --- | --- | --- |
| `citrus` | Hyprland desktop and local ChatGPT/Codex client | [`hosts/citrus/default.nix`](hosts/citrus/default.nix) |
| `citrus-vm` | Citrus desktop on Hyper-V | [`hosts/citrus-vm/default.nix`](hosts/citrus-vm/default.nix) |
| `orange` | Tailnet server, storage, media, password manager, and Minecraft | [`hosts/orange/default.nix`](hosts/orange/default.nix) |

## Non-activating quick start

To check the current host's configuration without activating it, this example
can be run from the repository root. For task-specific checks, use the scope
table in `AGENTS.md`; this is not a prerequisite for every edit.

```console
runtime_host="$(hostnamectl --static 2>/dev/null || hostname)"
etc_host="$(tr -d '\r\n' < /etc/hostname)"
test "$runtime_host" = "$etc_host"

flake_host="$(
  nix eval --raw --no-write-lock-file \
    ".#nixosConfigurations.$runtime_host.config.networking.hostName"
)"
test "$runtime_host" = "$flake_host"

nix flake show --no-write-lock-file
nix build ".#nixosConfigurations.$runtime_host.config.system.build.toplevel" \
  --no-link \
  --no-write-lock-file
```

These commands evaluate and build locally; they do not activate a generation.
Do not substitute another host when the runtime host has no matching flake
output.

Follow [`AGENTS.md`](AGENTS.md) for the mandatory commit and scope-dependent
local activation workflow.

The native Codex CLI comes from the pinned `sadjow/codex-cli-nix` input and is
installed through Home Manager on all three hosts. Its automatic user service
is configured in [`home/keewai/shared/codex-remote.nix`](home/keewai/shared/codex-remote.nix).

## Neovim and repository development

Home Manager installs Neovim as `nvim`, `vim`, and `vi` on all three hosts and
sets it as `EDITOR` and `VISUAL` for new sessions. The common configuration in
[`home/keewai/shared/neovim.nix`](home/keewai/shared/neovim.nix) uses
[lazy.nvim](https://lazy.folke.io/) to load Nix-pinned plugins. Inspect them with
`:Lazy`; update their versions through the repository's pinned Nixpkgs input.
Plugins are available without a first-launch download, and Wayland clipboard
integration is included.

The editor uses absolute line numbers. Its home screen links to file search,
the file explorer, recent files, workspace restoration, the terminal, and help.
Neo-tree provides a sidebar for browsing, creating, renaming, copying, moving,
and deleting files, plus a view of Git changes. In the tree, use `Enter` to open,
`a` / `A` to create a file / directory, `r` to rename, `y` / `x` then `p` to copy /
move, `d` to delete, `H` to toggle hidden entries, and `?` for the full key guide.

bufferline displays open files as tabs. ToggleTerm opens a floating terminal,
and persistence saves open files and window layouts per working directory and
Git branch on exit; restoration is manual. Trouble provides diagnostic and
document-symbol panels. Tree-sitter supplies syntax highlighting for common
configuration and programming languages, with parsers also pinned and installed
by Nix. Change the parser list in `neovim.nix` instead of running `:TSInstall`.

mini.nvim provides file and text search, Git history and diffs, completion, a
status line, comment toggling, text objects, paired delimiters, surrounding-text
edits, moving selected lines, alignment, and splitting/joining argument lists.
which-key shows available key bindings after a pause. nvim-lspconfig and
conform.nvim provide the language-server and formatter integration used by
project extensions. Outside a development shell, completion works with buffer
text without requiring a language server.

From this repository's root, start the development environment and open a file:

```console
nix develop --no-write-lock-file
nvim flake.nix
```

The shell supplies nixd, nixfmt, statix, deadnix, Lua Language Server, StyLua,
Bash Language Server, ShellCheck, and shfmt. It sets `NVIM_PROJECT_CONFIG` to
the Nix-store copy of [`devshell/neovim.lua`](devshell/neovim.lua), which extends
the same Home Manager editor with Nix, Lua, and Bash completion, diagnostics,
navigation, and manual formatting. nixd uses the edited flake's pinned Nixpkgs
and exposes NixOS and Home Manager options for the local hostname. To inspect
another declared configuration, set `NVIM_NIXOS_HOST=orange` before starting
Neovim. This only selects completion data and does not contact or deploy a host.
Zsh files retain general editing and highlighting; Bash diagnostics and shfmt
are not applied to Zsh syntax. statix and deadnix are available as CLI checks.

The extension is loaded only by Neovim processes started with
`NVIM_PROJECT_CONFIG`; starting Neovim outside the shell restores the common
setup. Re-enter `nix develop` after changing the extension. Another project's
devShell can set the same variable to its own trusted Lua configuration.

| Keys | Action |
| --- | --- |
| `Space ff` / `Space fg` | Find files / search contents |
| `Space fb` / `Space fh` | Find buffers / search help |
| `Space fr` | Find recent files |
| `Space e` | Toggle the file explorer |
| `Space h` / `Space ?` | Home screen / key guide |
| `Space t` or `Ctrl-\` | Toggle the floating terminal |
| `Esc Esc` in a terminal | Leave terminal input mode |
| `[b` / `]b` / `Space bd` | Previous file / next file / close file |
| `Space ws` / `Space wv` / `Space wc` | Horizontal split / vertical split / close window |
| `Space sr` / `Space ss` / `Space sd` | Restore workspace / select workspace / stop saving this session |
| `Space gd` / `Space gg` | Toggle Git diff overlay / show Git status |
| `Space gc` / `Space ge` | Git history / Git changes explorer |
| `Space l` | Open the plugin manager |
| `Space cf` | Format the buffer or selection when a formatter is available |
| `Space cd` / `Space cq` | Show diagnostic / list diagnostics |
| `Space xx` / `Space xb` / `Space cs` | Workspace diagnostics / buffer diagnostics / document symbols |
| `gd` / `gr` / `K` | Definition / references / documentation with an attached LSP |
| `Space cr` / `Space ca` | Rename symbol / code action with an attached LSP |
| `gcc` / `gc` in Visual mode | Toggle comments |
| `Alt-h/j/k/l` in Visual mode | Move selected text |
| `ga` in Visual mode | Align selected text interactively |
| `gS` | Split or join an argument list |
| `Ctrl-n` / `Ctrl-p` / `Ctrl-y` | Next / previous / accept completion |
