# nixos-configuration

Flake-based NixOS configurations for three `x86_64-linux` machines. The layout
separates machine integration from user applications and settings.

## Layout

```text
.
├── flake.nix
├── modules/
│   ├── common.nix                 # system settings used by every host
│   ├── home-manager.nix           # shared NixOS/Home Manager integration
│   ├── desktop.nix                # opt-in desktop profile and its system integration
│   ├── codex.nix                  # system Codex instructions, MCP, and hooks
│   ├── codex-remote.nix           # user server startup before login
│   ├── dconf.nix                  # D-Bus/GIO integration for user GTK settings
│   ├── hyprland-package.nix       # shared Hyprland package and IME patch
│   ├── hyprlock.nix               # PAM authentication for the user-owned locker
│   └── shell.nix                  # login-shell integration
├── home/
│   └── keewai/
│       ├── common.nix             # entry point for every host
│       ├── shared/                # common CLI, shell, Codex, Remote, MCP, and skills
│       └── desktop/               # GUI apps, desktop services, CUA, IME, and themes
│           ├── hyperv.nix         # rendering adaptations when Hyper-V is enabled
│           ├── theme.nix          # palette, fonts, cursor, and shared theme values
│           ├── hyprland.lua       # Hyprland behavior and key bindings
│           └── assets/            # shared wallpaper
├── hosts/
│   ├── citrus/
│   │   ├── default.nix            # host entry point
│   │   ├── hardware-configuration.nix
│   │   ├── desktop.nix            # desktop environment
│   │   ├── browser.nix            # WebHID hardware access rules
│   │   └── assets/                # desktop localization files
│   ├── citrus-vm/                 # Citrus base with Hyper-V hardware overrides
│   └── orange/
│       ├── default.nix            # host entry point
│       ├── hardware-configuration.nix
│       ├── settings.nix           # values shared inside this host
│       └── services/
│           ├── storage.nix        # storage and SMB
│           ├── immich.nix
│           ├── vaultwarden.nix
│           ├── web.nix            # nginx and Tailscale Serve
│           ├── minecraft.nix
│           ├── health-monitor.nix
│           └── maintenance.nix
├── pkgs/                           # one directory per local package
│   ├── chatgpt-desktop/
│   ├── millennium-steam/          # reproducible dependency layout for Millennium
│   ├── hyprpaper-shm/             # Hyper-V wallpaper renderer and Island IPC adapter
│   └── cua-driver/
├── skills/                         # personal Codex skills
├── checks/                         # package, desktop, and Codex hook regression checks
├── secrets/                        # Agenix declarations and ciphertext
└── docs/                           # operational detail
```

The ownership rules are intentionally small:

1. Put a setting in `modules/common.nix` only when every host uses it.
2. Put system integration under `hosts/<name>/`, and user applications and
   configuration under `home/<user>/shared/` or `home/<user>/desktop/` according
   to whether they need a desktop session.
3. Put build recipes, skills, and encrypted secrets in their matching top-level
   directory.

Physical host entry points import only files from their own directory.
`citrus-vm` imports Citrus and applies VM-specific hardware and desktop overrides.
Orange modules read `settings.nix` directly, so there is no hidden host-specific argument
injection from `flake.nix`.

All three hosts receive the common Home Manager profile: CLI tools, shell,
Codex CLI and Remote, common MCP servers, skills, and the iPad USB CLI.
Citrus and its VM also import the same desktop profile through
`modules/desktop.nix`: GUI applications, Bitwarden desktop/launcher integration,
CUA, IME, desktop services, and themes. Orange imports only the common profile.
The desktop profile applies Hyper-V rendering adaptations by capability and
uses fingerprint authentication only where fprintd is enabled. Desktop sessions,
drivers, USB access, and other hardware integration remain NixOS-owned.

Prefer Home Manager for personal packages. Keep system scope only for a
concrete integration requirement; see the complete [package audit](docs/package-audit.md).
`nix flake check` also checks the migrated package boundaries and user launch
integration.

Citrus uses Brave Origin as its sole configured browser and default URL handler,
managed by `home/keewai/desktop/browser.nix`.

## Hosts

| Host | Role | Entry point | Guide |
| --- | --- | --- | --- |
| `citrus` | Hyprland desktop and local ChatGPT/Codex client | [`hosts/citrus/default.nix`](hosts/citrus/default.nix) | [Citrus](docs/citrus.md) |
| `citrus-vm` | Citrus desktop on Hyper-V | [`hosts/citrus-vm/default.nix`](hosts/citrus-vm/default.nix) | [Hyper-V](docs/citrus-vm.md) |
| `orange` | Tailnet server, storage, media, password manager, and Minecraft | [`hosts/orange/default.nix`](hosts/orange/default.nix) | [Orange](docs/orange.md) |

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

See [development and deployment](docs/development.md) for the mandatory commit
and scope-dependent activation workflow. Automated contributors must also
follow [`AGENTS.md`](AGENTS.md).

The native Codex CLI comes from the pinned `sadjow/codex-cli-nix` input and is
installed through Home Manager on all three hosts. See
[Codex Remote Control](docs/codex-remote.md) for the shared settings, automatic
user service, and device pairing.
