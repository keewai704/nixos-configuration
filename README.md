# nixos-configuration

Flake-based NixOS configurations for two `x86_64-linux` hosts. The repository
keeps shared modules, host composition, local packages, personal Codex skills,
and encrypted secrets in one declarative tree.

## Hosts

| Host | Role | Entry point | Details |
| --- | --- | --- | --- |
| `citrus-vm` | Hyprland desktop and local ChatGPT/Codex client | [`hosts/citrus-vm/default.nix`](hosts/citrus-vm/default.nix) | [Citrus guide](docs/citrus-vm.md) |
| `orange` | Tailnet server, storage, media, browser, password manager, and Minecraft | [`hosts/orange/default.nix`](hosts/orange/default.nix) | [Orange guide](docs/orange.md) |

## How the configuration is assembled

```text
flake.nix
└── mkHost
    ├── modules/base.nix                    # imported by every host
    ├── hosts/citrus-vm/default.nix
    │   ├── modules/desktop-client.nix
    │   │   └── modules/chatgpt-desktop-extensions.nix
    │   │       └── Home Manager and mcp-servers-nix
    │   ├── modules/{networkmanager,tailnet-admin,uefi-systemd-boot}.nix
    │   └── hosts/citrus-vm/{hardware-configuration.nix,hyprland.lua,assets/}
    └── hosts/orange/default.nix
        ├── modules/{networkmanager,tailnet-admin,tailnet-web,uefi-systemd-boot}.nix
        ├── hosts/orange/{hardware-configuration,settings,health-monitor,maintenance}.nix
        └── hosts/orange/services/{camofox,storage,immich,vaultwarden,web,minecraft}.nix
```

`flake.nix` passes the flake inputs to every host. Orange also receives the
plain attribute set from `hosts/orange/settings.nix` as `orangeSettings`.
Citrus gets Home Manager indirectly through `modules/desktop-client.nix` and
`modules/chatgpt-desktop-extensions.nix`.

## Where a change belongs

| Change | Location |
| --- | --- |
| Baseline applied to every host | `modules/base.nix` |
| Reusable platform, role, or application configuration | `modules/*.nix` |
| Host composition, hardware, or machine-specific values | `hosts/<host>/default.nix`, `hardware-configuration.nix`, or `settings.nix` |
| One Orange service or its operating policy | `hosts/orange/services/*.nix` |
| Orange monitoring or scheduled maintenance | `hosts/orange/health-monitor.nix` or `hosts/orange/maintenance.nix` |
| Locally packaged software | `pkgs/<package>/default.nix` |
| Personal Codex skill deployed through Home Manager | `skills/<skill>/SKILL.md` |
| Agenix recipients or encrypted payloads | `secrets/secrets.nix` and `secrets/*.age` |

Keep host entry points as composition files. Put implementation in the narrowest
shared module, host service, or package that owns it.

## Read-only quick start

Run this from the repository root before inspecting or changing a host:

```console
runtime_host="$(hostnamectl --static 2>/dev/null || hostname)"
etc_host="$(tr -d '\r\n' < /etc/hostname)"
if [ "$runtime_host" != "$etc_host" ]; then
  printf 'hostname mismatch: runtime=%s /etc/hostname=%s\n' "$runtime_host" "$etc_host" >&2
  exit 1
fi

flake_host="$(nix eval --raw ".#nixosConfigurations.$runtime_host.config.networking.hostName")"
test "$runtime_host" = "$flake_host"

nix flake show --no-write-lock-file
nix build ".#nixosConfigurations.$runtime_host.config.system.build.toplevel" \
  --no-link \
  --no-write-lock-file
```

These commands evaluate and build locally; they do not activate a generation.
Do not substitute another host when the runtime host has no matching flake
output.

## Documentation

- [Development and deployment workflow](docs/development.md)
- [Citrus desktop, ChatGPT, MCP, and CUA](docs/citrus-vm.md)
- [Orange services, storage, ingress, backups, and monitoring](docs/orange.md)

Automated contributors must also follow [`AGENTS.md`](AGENTS.md).
