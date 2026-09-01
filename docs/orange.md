# orange

`orange` is the tailnet server and storage host. It provides Tailscale SSH and
exit-node routing, storage over SMB, Immich, Vaultwarden, and a Fabric Minecraft
server.

Use the mandatory [development workflow](development.md). Orange may be
evaluated and built from another local host, but `nixos-rebuild test`,
live-service checks, and `switch` are permitted only when the confirmed local
runtime hostname is `orange`. Do not connect remotely merely because Orange
configuration is being edited.

## Composition

| Path | Responsibility |
| --- | --- |
| [`hosts/orange/configuration.nix`](../hosts/orange/configuration.nix) | Host composition, exit-node settings, kernel choice, and state version |
| [`hosts/orange/settings.nix`](../hosts/orange/settings.nix) | Shared hostname, interface, storage paths, service ports, and identifiers |
| [`hosts/orange/hardware-configuration.nix`](../hosts/orange/hardware-configuration.nix) | Boot disk, filesystems, and generated hardware settings |
| [`hosts/orange/services/storage.nix`](../hosts/orange/services/storage.nix) | Existing HDD mount, SMB, ownership, and mount-ordered directory preparation |
| [`hosts/orange/services/immich.nix`](../hosts/orange/services/immich.nix) | Immich, PostgreSQL pin, hardware acceleration, and one-time database import |
| [`hosts/orange/services/vaultwarden.nix`](../hosts/orange/services/vaultwarden.nix) | Vaultwarden, backup, and one-time state import |
| [`hosts/orange/services/web.nix`](../hosts/orange/services/web.nix) | Tailscale Serve, loopback nginx, routes, proxy headers, and WebSockets |
| [`hosts/orange/services/minecraft.nix`](../hosts/orange/services/minecraft.nix) | Fabric server, pinned artifacts, firewall, and service sandbox |
| [`hosts/orange/health-monitor.nix`](../hosts/orange/health-monitor.nix) | Health checks, Discord alerting, and the 15-minute monitor timer |
| [`hosts/orange/maintenance.nix`](../hosts/orange/maintenance.nix) | Local backups, SMART tests, Nix maintenance, and timer scheduling |

Orange modules import `hosts/orange/settings.nix` directly. Put a shared path,
port, or identifier there only when multiple Orange modules consume it.

## Storage is non-destructive

The 8 TB ext4 disk mounted at `/srv/storage` contains existing data. The
configuration must never format, repartition, initialize, or replace that
filesystem. Its UUID and mount policy belong to
`hosts/orange/services/storage.nix`.

Important paths are:

| Data | Path |
| --- | --- |
| Immich media | `/srv/storage/Pictures` |
| Immich PostgreSQL backups | `/srv/storage/Pictures/backups` |
| Vaultwarden backup mirror | `/srv/storage/server/backups/vaultwarden-nixos` |
| Versioned local backups | `/srv/storage/server/backups/orange-local` |

PostgreSQL, Redis, and the live Vaultwarden SQLite database remain on the SSD.
Media, generated Immich data, and backups remain on the HDD.

The Immich import runs only when the target database has no application schema
and selects the newest existing SQL backup. The Vaultwarden import validates
the SQLite copy, reconciles missing legacy auxiliary files after an interrupted
run, and writes its completion marker last. Each import leaves the old source
data in place. Do not weaken those guards or delete the old data as part of an
ordinary activation.

There is intentionally no off-machine backup target. The local backup set is
not disaster recovery for loss of the Orange host or its storage disk.

## Web ingress

All user-facing HTTP, HTTPS, and WebSocket traffic follows one topology:

```text
tailnet client -> Tailscale Serve HTTPS :443 -> 127.0.0.1 nginx :8000 -> loopback application
```

Port 443 is the only user-facing web ingress. Application backends bind to
`127.0.0.1` or a Unix socket. Never expose nginx's internal port, a backend
port, or a second TLS listener on the LAN, public firewall, or `tailscale0`.
Tailscale Serve targets nginx, never an application directly.

The canonical tailnet origin is `https://orange.tail1e65cd.ts.net`:

| Service | Canonical URL | Internal backend |
| --- | --- | --- |
| Immich | `https://orange.tail1e65cd.ts.net/` | `127.0.0.1:2283` |
| Vaultwarden | `https://orange.tail1e65cd.ts.net/vault/` | `127.0.0.1:8222` |

Preserve forwarded host, HTTPS scheme, and tailnet client IP. Enable WebSocket
proxying where required. If an application cannot safely operate below its
canonical subpath, patch it or add a loopback adapter; do not work around it
with another externally reachable port.

Minecraft and SMB are deliberate non-web services. Their firewall rules remain
separate from this web topology; they do not authorize exposing an application
HTTP backend.

## Services

### Immich

Immich media lives on the HDD while PostgreSQL stays on the SSD. Machine
learning is disabled at both the NixOS worker and application-feature levels.
Scheduled/pre-generated transcoding is disabled; real-time playback
transcoding uses Intel QSV on `/dev/dri/renderD128`. PostgreSQL's major version
is pinned so a routine flake update cannot perform an implicit major upgrade.

Immich creates a daily PostgreSQL backup and retains the configured recent set.
Fourteen backups are retained. The backup directory must remain mounted before
Immich and its import unit start.

### Vaultwarden

Vaultwarden uses SQLite on the SSD and mirrors backups to the HDD. Its external
domain includes the `/vault` prefix and new registrations are disabled. The
backup timer is intentionally schedule-only rather than boot-triggered.

### Minecraft and SMB

Minecraft runs as its own system user and is reachable on the trusted LAN and
tailnet port declared in `settings.nix`. The storage SMB share is available on
the trusted LAN and over tailnet port 445; NetBIOS discovery is LAN-only.

## Backups and maintenance

Scheduled work begins at or after 06:00 JST:

| Time | Work |
| --- | --- |
| Daily 06:00 | Immich PostgreSQL backup |
| Daily 06:05 | Vaultwarden backup |
| Daily 06:15 | Versioned Minecraft and Vaultwarden local backups |
| Daily 06:20 | Log rotation |
| Daily 06:30 | Temporary-file cleanup |
| Daily 06:40 | Nix Store optimisation |
| Monday 06:50 | Filesystem TRIM |
| Monday 07:00 | Nix garbage collection |
| Sunday 06:50 | SMART short self-tests |
| First day 07:30 | SMART long self-tests |
| First day 08:00 | Full Nix Store content verification |

Versioned local backups retain a 14-day window. The maintenance timers are
deliberately non-persistent, so a missed task is not replayed before the next
scheduled window after reboot. Treat schedule or retention changes as
operational changes and verify the corresponding timer and backup output.

## Health monitoring and secrets

`orange-health-monitor.timer` runs every 15 minutes. It checks critical
services, failed units, mounts, disk and inode capacity, SMART health, memory
and swap pressure, temperatures, recent kernel errors, OOM events, coredumps,
time synchronization, Tailscale, HTTP/TCP endpoints, loopback-only backend
listeners, backup freshness, and pending kernel activation.

New incidents are grouped into one Discord webhook request and deduplicated
until they clear. Normal checks and recoveries do not send messages. Manually
starting the monitor can therefore send a real notification for a newly
detected incident.

The webhook ciphertext is `secrets/discord-webhook.age` and its recipients are
declared in `secrets/secrets.nix`. Agenix decrypts it to a root-only runtime
credential. Plaintext must never be committed, printed in logs, or copied into
the Nix store.

## Verification

Run these checks after both `nixos-rebuild test` and `switch`, in addition to
the common checks in `docs/development.md`:

```console
systemctl is-active \
  NetworkManager tailscaled sshd nginx \
  samba-smbd immich-server postgresql redis-immich \
  vaultwarden minecraft tailscale-serve-nginx

systemctl list-timers \
  orange-health-monitor.timer orange-local-backup.timer \
  orange-smart-short.timer orange-smart-long.timer \
  orange-nix-store-verify.timer backup-vaultwarden.timer

tailscale serve status
ss --listening --tcp --numeric
curl --fail --silent --show-error https://orange.tail1e65cd.ts.net/ >/dev/null
curl --fail --silent --show-error https://orange.tail1e65cd.ts.net/vault/ >/dev/null
```

Confirm that `tailscale serve status` contains exactly one web listener, HTTPS
port 443, proxying nginx at `127.0.0.1:8000`. Confirm with `ss` that nginx and
all application backends remain loopback-only.

Inspect monitoring and backup state with:

```console
systemctl status orange-health-monitor.timer orange-health-monitor.service
journalctl --unit orange-health-monitor.service --since today
systemctl status orange-local-backup.timer
journalctl --unit orange-local-backup.service --since today
```

To execute the complete monitor immediately:

```console
sudo systemctl start orange-health-monitor.service
```

This last command performs real checks and may send a Discord alert for new
failures.
