# nixos-configuration

Flake-based NixOS configurations for two `x86_64-linux` machines. The layout
uses one shared module and keeps everything else beside the host that owns it.

## Layout

```text
.
├── flake.nix
├── modules/
│   └── common.nix                 # settings used by every host
├── hosts/
│   ├── citrus/
│   │   ├── default.nix            # host entry point
│   │   ├── hardware-configuration.nix
│   │   ├── desktop.nix            # desktop environment
│   │   ├── browser.nix            # Firefox, Brave Origin, Pywalfox, and WebHID
│   │   ├── codex.nix              # ChatGPT, MCP, CUA, and skills
│   │   ├── hyprland.lua           # Hyprland behavior and key bindings
│   │   └── assets/                # wallpaper
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
│   └── cua-driver/
├── skills/                         # personal Codex skills
├── secrets/                        # Agenix declarations and ciphertext
└── docs/                           # operational detail
```

The ownership rules are intentionally small:

1. Put a setting in `modules/common.nix` only when every host uses it.
2. Put machine-specific code under `hosts/<name>/`.
3. Put build recipes, skills, and encrypted secrets in their matching top-level
   directory.

Each host entry point imports only files from its own directory. Orange modules
read `settings.nix` directly, so there is no hidden host-specific argument
injection from `flake.nix`.

Firefox's Sine/Natsumi configuration lives in the separate Git repository at
`/home/keewai/browser-config`. Citrus imports its `nixosModules.default` through
the `browser-config` flake input, whose commit is pinned in `flake.lock`.

## Hosts

| Host | Role | Entry point | Guide |
| --- | --- | --- | --- |
| `citrus` | Hyprland desktop and local ChatGPT/Codex client | [`hosts/citrus/default.nix`](hosts/citrus/default.nix) | [Citrus](docs/citrus.md) |
| `orange` | Tailnet server, storage, media, password manager, and Minecraft | [`hosts/orange/default.nix`](hosts/orange/default.nix) | [Orange](docs/orange.md) |

## Non-activating quick start

Run this from the repository root before inspecting or changing a host:

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
