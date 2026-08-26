# nixos-configuration

This repository contains the flake-based NixOS configuration for the `orange`
host.

## Agent tooling

The flake pins and loads both `mcp-servers-nix` and `agent-skills-nix` through
Home Manager for the `keewai` user. The shared MCP registry is enabled and
Codex consumes it through `programs.codex.enableMcpIntegration`. No third-party
skills are installed until they are explicitly selected. MCP servers are
launched on demand rather than as persistent services.

The enabled NixOS MCP server is declared in the
`home-manager.users.keewai` module in `flake.nix`:

```nix
mcp-servers.programs.nixos = {
  enable = true;
  env = {
    MCP_NIXOS_TRANSPORT = "stdio";
    FASTMCP_CHECK_FOR_UPDATES = "off";
    FASTMCP_SHOW_SERVER_BANNER = "false";
    FASTMCP_ENV_FILE = "/dev/null";
  };
};
```

These environment settings keep the server on local stdio, disable FastMCP's
update check and banner, and prevent loading settings from a project `.env`.

Codex receives LSP-backed semantic code tools through Serena. Serena starts in
the current Git workspace, auto-detects the project language, and has `nixd`
on its private `PATH` for Nix files. `.serena/project.yml` pins this repository
to the Nix language server, and `.serena/nixd.json` supplies flake-aware NixOS
and Home Manager option sets. `nixfmt` is available to the same LSP wrapper.
The Serena dashboard and usage reporting are disabled. Codex itself remains
installed by the separately pinned user profile (`programs.codex.package =
null`); Home Manager manages its `config.toml`, including the shared MCP
entries, while preserving the existing model, approval, plugin, and
project-trust settings.

After activation, verify the integration with:

```console
codex mcp get serena
codex doctor --summary
```

To manage skills, add a pinned skill source as a flake input, select skills
under `programs.agent-skills`, and enable only the desired target. Existing
non-managed target directories are deliberately not taken over automatically.

### Camofox browser

Camofox Browser v1.14.0 and Camoufox 135.0.1-beta.24 are packaged with fixed
source hashes and run directly as the non-root `camofox.service`. Persistent
profiles live under `~/.local/share/camofox`, crash telemetry is disabled, and
all backend listeners remain loopback-only:

- Control API: `http://127.0.0.1:9377`
- noVNC backend: `http://127.0.0.1:6080`

Tailnet clients can open the nginx-proxied noVNC view at
<https://orange.tail1e65cd.ts.net/browser>; it redirects to the viewer and
connects automatically.

`CAMOFOX_URL` is declared through Home Manager for interactive shells and user
services.

## Validate

```console
nix --extra-experimental-features 'nix-command flakes' flake check
sudo nixos-rebuild build --flake .#orange \
  --option experimental-features 'nix-command flakes'
```

## Apply

Test a generation without changing the boot default:

```console
sudo nixos-rebuild test --flake .#orange \
  --option experimental-features 'nix-command flakes'
```

After verifying networking, SSH, and Tailscale, make it the boot default:

```console
sudo nixos-rebuild switch --flake .#orange \
  --option experimental-features 'nix-command flakes'
```

The extra feature flags are only needed for the first activation. This
configuration enables `nix-command` and `flakes` permanently.

## Media services

The existing 8 TB ext4 disk is mounted by UUID at `/srv/storage`. It is never
formatted by this configuration. Existing data is retained in place:

- Immich media: `/srv/storage/Pictures`
- Immich PostgreSQL backups: `/srv/storage/Pictures/backups` (daily, 14 kept)
- Vaultwarden backup mirror: `/srv/storage/server/backups/vaultwarden-nixos`

PostgreSQL, Redis, and the live Vaultwarden SQLite database remain on the SSD
for latency. Immich media, generated thumbnails, and backups stay on the HDD.
The first activation imports the newest existing Immich SQL backup and the
existing Vaultwarden SQLite database only when their new SSD databases are
empty. The old Docker-era data is not deleted and remains available for
rollback.

Immich machine learning is disabled at both the NixOS service and application
levels. Scheduled/pre-generated video transcoding is disabled; real-time HLS
transcoding is enabled with Intel QSV on `/dev/dri/renderD128`.

The nginx listener remains loopback-only on `127.0.0.1:8000`, and Tailscale
Serve publishes it as:

- Immich: <https://orange.tail1e65cd.ts.net/>
- Vaultwarden: <https://orange.tail1e65cd.ts.net/vault/>

Vaultwarden registration is disabled because the imported database already
contains a user. No application port is opened on the LAN or public firewall.
