# nixos-configuration

Flake-based NixOS configurations for three `x86_64-linux` machines. The layout
separates machine integration from user applications and settings.

## Layout

```text
.
├── flake.nix
├── modules/
│   ├── common.nix                 # system settings used by every host
│   └── home-manager.nix           # shared NixOS/Home Manager integration
├── home/
│   └── keewai/
│       ├── common.nix             # personal CLI packages on every host
│       ├── citrus/                # desktop apps, shell, IME, MCP, and user files
│       └── citrus-vm/             # VM desktop overrides
├── hosts/
│   ├── citrus/
│   │   ├── default.nix            # host entry point
│   │   ├── hardware-configuration.nix
│   │   ├── desktop.nix            # desktop environment
│   │   ├── browser.nix            # WebHID hardware access rules
│   │   ├── codex.nix              # system Codex instructions and managed hooks
│   │   ├── theme.nix              # shared desktop palette and assets
│   │   ├── hyprland.lua           # Hyprland behavior and key bindings
│   │   └── assets/                # wallpaper and Noctalia localization files
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
   configuration under `home/<user>/<host>/` (shared user tools in `common.nix`).
3. Put build recipes, skills, and encrypted secrets in their matching top-level
   directory.

Physical host entry points import only files from their own directory.
`citrus-vm` imports Citrus and applies VM-specific hardware and desktop overrides.
Orange modules read `settings.nix` directly, so there is no hidden host-specific argument
injection from `flake.nix`.

Prefer Home Manager for personal packages. Keep system scope only for a
concrete integration requirement; see the complete [package audit](docs/package-audit.md).
`nix flake check` also checks the migrated package boundaries and user launch
integration.

Citrus uses Brave Origin as its sole configured browser and default URL handler,
managed by `home/keewai/citrus/browser.nix`.

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
