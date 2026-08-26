# nixos-configuration

This repository contains the flake-based NixOS configuration for the `orange`
host.

## Agent tooling

The flake loads `mcp-servers-nix` through Home Manager for the `keewai` user.
Codex consumes the shared MCP registry through
`programs.codex.enableMcpIntegration`; Camofox Browser, Context7, NixOS,
Serena, and Ponytail servers are launched on demand rather than as persistent
services.

The NixOS server is restricted to local stdio, with update checks, the startup
banner, and project `.env` loading disabled. Serena starts in the current Git
workspace with `nixd` and `nixfmt` on its private `PATH`; its dashboard and
usage reporting are disabled. Serena's global trust pattern is `**`, so project
configuration is trusted in every directory.

Codex itself remains installed by the separately pinned user profile
(`programs.codex.package = null`). Its shared defaults and MCP entries live in
the system configuration at `/etc/codex/config.toml`, including
`sandbox_mode = "danger-full-access"` and `approval_policy = "never"`. The user
configuration is a writable file at `~/.local/state/codex/config.toml`, linked
from `~/.codex/config.toml`, so Codex can persist trust decisions. The
`~/.local/bin/codex` launcher trusts the selected working directory and its Git
root before starting the pinned CLI, including directories selected with
`-C`/`--cd`.

After activation, verify the integration with:

```console
codex mcp get serena
codex doctor --summary
readlink -f ~/.codex/config.toml
```

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

The REST server and noVNC frontend start at boot, but Camoufox, Xvfb, and
x11vnc remain stopped until the first noVNC WebSocket connection or Codex
browser tool call. A noVNC connection creates an idempotent `codex`/`default`
browser session before its RFB stream is forwarded. The Codex MCP adapter uses
that same user and session key, so `camofox_list_tabs` can discover and operate
the tab visible in noVNC (and vice versa).

`CAMOFOX_URL` is declared through Home Manager for interactive shells and user
services.

### Yep Anywhere

Yep Anywhere v0.7.0 is packaged from a fixed npm release and starts
automatically as `yepanywhere.service`. It runs as `keewai`, so it discovers
the existing authenticated Codex CLI and compatible session history without a
second sign-in. Its state is stored in `~/.yep-anywhere`.

The application backend remains loopback-only on port 3400. Its client is
rebuilt with subpath-aware API, WebSocket, asset, router, and service-worker
URLs, then proxied through the shared loopback nginx frontend. The only
user-facing web ingress is Tailscale Serve HTTPS on port 443, at
<https://orange.tail1e65cd.ts.net/yep/>.

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
