# nixos-configuration

This repository contains flake-based NixOS configurations for the `orange`
and `citrus-vm` hosts.

## Configuration layout

Every host is constructed through the shared `mkHost` helper in `flake.nix`.
Host-independent locale, user, Nix, logging, Home Manager, Pi, and generic
MCP settings live under `modules/global`. Reusable platform and role settings,
such as desktop clients, NetworkManager, UEFI systemd-boot, and tailnet
administration, live under `profiles` and are imported explicitly by each
compatible host.

Hardware, state versions, network roles, local endpoints, storage, secrets,
and services remain under `hosts/<name>`. Orange's repeated storage and local
service values are defined once in `hosts/orange/settings.nix`.

## Agent tooling

The flake installs Pi through Home Manager for the `keewai` user on every host.
Its package set is locked and built by Nix: `@ff-labs/pi-fff`,
`pi-mcp-adapter`, `pi-web-access`, `pi-hashline-edit-pro`,
`pi-background-tasks`, `pi-lens`, `pi-subagents`, and
`@juicesharp/rpiv-todo`. Pi Web is installed as the `pi-web` command and is
configured to bind to `127.0.0.1` without opening a browser automatically.

Pi's declarative settings live at `~/.pi/agent/settings.json`. FFF runs in
`override` mode, so its indexed `grep` and `find` tools replace the built-ins
and it exposes `multi_grep`. Hashline supplies anchor-aware `read`, `replace`,
and `insert` tools; Pi's default tool selection disables the built-in `edit`
tool. The global
`~/.pi/agent/AGENTS.md` tells Pi to prefer those search tools, use `multi_grep`
for OR searches, use `rg` when shell search is unavoidable, read only the
relevant offset/limit range after locating a hit, and directly read known
paths outside the workspace.

Pi-lens is configured globally at `~/.pi-lens/config.json`: LSP stays enabled and
its situational tools are registered eagerly instead of appearing inactive at
session start. Nix-managed baseline language servers are on Pi's `PATH`, while
`nix-ld` lets pi-lens run additional managed native servers installed on demand.

The flake also loads `mcp-servers-nix` through Home Manager. Pi's MCP adapter
consumes the shared registry at `~/.config/mcp/mcp.json`; Context7, NixOS,
Serena, and Ponytail are global on-demand servers. Orange adds its local
Camofox Browser MCP endpoint without exposing that loopback-only dependency to
other hosts.

The NixOS server is restricted to local stdio, with update checks, the startup
banner, and project `.env` loading disabled. Serena starts in the current Git
workspace with `nixd` and `nixfmt` on its private `PATH`; its dashboard and
usage reporting are disabled. Serena's global trust pattern is `**`, so project
configuration is trusted in every directory.

Pi defaults to `gpt-5.6-sol` with maximum thinking and trusts project-local
resources. Install telemetry and analytics are disabled. The internal
`openai-codex` provider identifier is Pi's name for ChatGPT subscription OAuth;
it does not install or invoke the Codex CLI.

After activation, verify the integration with:

```console
pi --version
pi list
readlink -f ~/.pi/agent/settings.json
pi-web --help
```

### Cua Driver

`profiles/desktop-client.nix` installs Cua Driver v0.22.1 only on hosts with
an interactive desktop; currently only `citrus-vm` imports this profile. The
profile enables AT-SPI and registers `cua-driver mcp` in the shared MCP
registry. Its launcher imports the active display and session-bus variables
from the user's systemd manager, so Pi Web can reach the logged-in Wayland
session even though Pi Web itself runs as a system service.
The upstream-experimental native Wayland backend is explicitly enabled with
`CUA_DRIVER_RS_ENABLE_WAYLAND=1`; XWayland remains available as a fallback.

Cua telemetry and automatic update checks are disabled. Upgrades remain pinned
to the source hash in `pkgs/cua-driver/package.nix` and are applied through the
normal NixOS workflow.

### Pi Web over Tailscale

Both hosts use the shared `tailnet-admin` and `tailnet-web` profiles. The
former enables Tailscale SSH and explicitly keeps each machine's NixOS
hostname as its Tailscale hostname. The latter publishes a loopback-only
nginx listener through one Tailscale Serve HTTPS listener on port 443, then
proxies `/pi` to a loopback-only Pi Web backend:

- citrus-vm: <https://citrus-vm.tail1e65cd.ts.net/pi/>
- Orange: <https://orange.tail1e65cd.ts.net/pi/>

Pi Web is built with `/pi` as its Next.js base path, including API, static
asset, manifest, service-worker, notification, and WebSocket/SSE URLs. No
nginx or Pi Web backend port is opened in the host firewall.

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
x11vnc remain stopped until the first noVNC WebSocket connection or Pi browser
tool call. A noVNC connection creates an idempotent `pi`/`default` browser
session before its RFB stream is forwarded. Pi's MCP adapter uses that same
user and session key, so `camofox_list_tabs` can discover and operate the tab
visible in noVNC (and vice versa).

`CAMOFOX_URL` is declared through Home Manager for interactive shells and user
services.

## Validate

```console
nix --extra-experimental-features 'nix-command flakes' flake check
sudo nixos-rebuild build --flake .#orange \
  --option experimental-features 'nix-command flakes'
nix build .#nixosConfigurations.citrus-vm.config.system.build.toplevel --no-link
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

## Maintenance and alerting

`orange-health-monitor.timer` checks the host every 15 minutes. It monitors
critical services, failed units, mounts, capacity, SMART health, memory and
swap pressure, temperatures, recent kernel errors, OOM events, coredumps,
Tailscale, HTTP/TCP endpoints, loopback-only backend listeners, backup
freshness, and pending kernel activation. New incidents are
grouped into one Discord webhook request and deduplicated until they clear.
Normal checks and recoveries do not produce notifications.

The Discord webhook is stored as `secrets/discord-webhook.age`, encrypted to
orange's SSH host key. Agenix decrypts it to a root-only runtime credential; the
plaintext is never committed or copied into the Nix Store.

Scheduled maintenance starts at or after 06:00 JST:

- 06:00 daily: Immich PostgreSQL backup
- 06:05 daily: Vaultwarden backup
- 06:15 daily: versioned Minecraft and Vaultwarden local backups (14 days)
- 06:20 daily: log rotation
- 06:30 daily: temporary-file cleanup
- 06:40 daily: Nix Store optimisation
- 06:50 Monday: filesystem TRIM
- 07:00 Monday: Nix garbage collection
- 06:50 Sunday: SMART short self-tests
- 07:30 on the first day of each month: SMART long self-tests
- 08:00 on the first day of each month: full Nix Store content verification

The local backups remain under `/srv/storage/server/backups/orange-local`.
There is intentionally no off-machine backup target. Missed timers are not run
before 06:00 after a reboot.
