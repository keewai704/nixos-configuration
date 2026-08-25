# nixos-configuration

This repository contains the flake-based NixOS configuration for the `orange`
host.

## Agent tooling

The flake pins and loads both `mcp-servers-nix` and `agent-skills-nix` through
Home Manager for the `keewai` user. The MCP registry and the `mcp-nixos`
stdio server are enabled; no third-party skills are installed until they are
explicitly selected. MCP servers are launched on demand by a compatible
client rather than as persistent services.

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

An MCP-aware client must also opt into Home Manager's shared registry, for
example with `programs.codex.enableMcpIntegration = true` when Codex itself is
managed by Home Manager.

To manage skills, add a pinned skill source as a flake input, select skills
under `programs.agent-skills`, and enable only the desired target. Existing
non-managed target directories are deliberately not taken over automatically.

### Hermes Agent

Hermes Agent is installed for `keewai` from the official Nix package through
Home Manager. The flake input is pinned to the `v2026.8.19` release, and the
CLI is available as `hermes`, `hermes-agent`, and `hermes-acp` after
activation. The official `services.hermes-agent` Home Manager module owns the
agent settings, gateway, dashboard backend, and `CAMOFOX_URL`.

The web dashboard runs as the lingering `hermes-backend.service` user unit.
Hermes itself listens only on `127.0.0.1:9119`; nginx publishes it through
Tailscale Serve at <https://orange.tail1e65cd.ts.net/hermes/>. The proxy strips
the `/hermes/` prefix and supplies Hermes' supported `X-Forwarded-Prefix`
header for SPA routes, assets, API calls, and WebSockets.

The current model, browser, computer-use, web-search, reset, progress, and CLI
toolset settings are declared in `flake.nix`. Home Manager marks the install as
managed, so persistent configuration changes must be made in Nix rather than
with `hermes setup`, `hermes config set`, or the dashboard settings panes.

The existing OpenAI Codex OAuth credentials remain in the private runtime file
`~/.hermes/auth.json`, where Hermes can refresh them without copying a token
into the world-readable Nix store. The generated `~/.hermes/.env` contains
only the non-secret Camofox URL. Future API keys or messaging tokens should be
provided with `services.hermes-agent.environmentFiles` from agenix or sops-nix,
never through `settings` or `environment`.

The dashboard has no direct LAN or tailnet listener. Its loopback session token
is protected by Tailscale Serve and nginx, so tailnet ACLs are the access
boundary for the web UI. Check the persistent service with:

```console
systemctl --user status hermes-backend.service hermes-agent.service
journalctl --user --unit hermes-backend.service
journalctl --user --unit hermes-agent.service
```

### Camofox browser

Camofox runs as a rootless Podman container for `keewai`. The v1.14.0 amd64
image is pinned by digest, its persistent profiles live under
`~/.local/share/camofox`, and its crash telemetry is disabled. Neither port is
opened on the LAN or tailnet:

- Hermes control API: `http://127.0.0.1:9377`
- noVNC live view: `http://127.0.0.1:6080`

For remote noVNC access, tunnel the loopback port over SSH and then open
<http://127.0.0.1:6080> locally:

```console
ssh -L 6080:127.0.0.1:6080 orange
```

Hermes uses Camofox as its browser backend with `managed_persistence` disabled,
matching the pre-migration runtime setting. Both the backend selection and
`CAMOFOX_URL` are now declared through Home Manager; the URL is also exported
for interactive shells and other user services.

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

Nginx listens only on `127.0.0.1:8000`, and Tailscale Serve publishes it as:

- Immich: <https://orange.tail1e65cd.ts.net/>
- Vaultwarden: <https://orange.tail1e65cd.ts.net/vault/>
- Hermes dashboard: <https://orange.tail1e65cd.ts.net/hermes/>

Vaultwarden registration is disabled because the imported database already
contains a user. No application port is opened on the LAN or public firewall.
