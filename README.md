# nixos-configuration

This repository contains flake-based NixOS configurations for the `orange`
and `citrus-vm` hosts.

## Configuration layout

Every host is constructed through the shared `mkHost` helper in `flake.nix`.
Host-independent locale, user, Nix, and logging settings live under
`modules/global`. Reusable platform and role settings, such as desktop clients,
NetworkManager, UEFI systemd-boot, and tailnet administration, live under
`profiles` and are imported explicitly by each compatible host.

Hardware, state versions, network roles, local endpoints, storage, secrets,
and services remain under `hosts/<name>`. Orange's repeated storage and local
service values are defined once in `hosts/orange/settings.nix`.

## Codex desktop

`citrus-vm` imports `profiles/desktop-client.nix`, which installs the official
OpenAI Linux desktop application packaged locally by
`pkgs/chatgpt-desktop/package.nix`. OpenAI now distributes the Codex desktop
experience inside the ChatGPT desktop app, so the canonical executable and menu
entry are named `chatgpt`; `codex-desktop` is installed as a convenience alias.

The derivation downloads OpenAI's official x86_64 `.deb`, pins version
`26.825.41651` and SHA-256
`sha256-IbIulcDEOj8RTz7TJpKr7cY49AV6CPmMmINuLT6aZx4=`, extracts its payload with
`dpkg-deb`, patches ELF dependencies for NixOS, and installs the upstream desktop
entry and icon. Debian maintainer scripts are deliberately not executed, so the
package does not add OpenAI's APT repository or write outside the Nix store.
Updates are performed by refreshing the pinned version and hash in the Nix
derivation.

The app rewrites bundled plugin manifests when it materializes them. Because Nix
store files are read-only, the launcher creates a versioned, approximately 48 MiB
writable resource overlay under
`~/.cache/chatgpt/bundled-plugin-resources/`; immutable sibling resources remain
symlinked to the Nix store.

OpenAI documents the upstream package and supported Linux distributions at
<https://developers.openai.com/codex/app>. NixOS is not an upstream-supported
distribution; this repository supplies the compatibility packaging.

The flake also exposes the standalone package output:

```console
nix build .#chatgpt-desktop
nix profile install .#chatgpt-desktop
```

OpenAI's native Wayland path is experimental. The launcher detects a live
Wayland session and the existing `NIXOS_OZONE_WL` opt-in, then adds
`--ozone-platform=wayland --enable-wayland-ime=true` to the upstream binary.
This is required because the prebuilt binary does not implement the Nixpkgs
`NIXOS_OZONE_WL` wrapper convention; without it, Chromium selects XWayland and
Fcitx5's Wayland text-input preedit path is not used. The desktop entry and
`chatgpt` command therefore both get working inline Japanese input on
`citrus-vm`:

```console
chatgpt
```

To exercise the upstream default XWayland fallback for comparison, unset the
opt-in for that launch:

```console
env -u NIXOS_OZONE_WL chatgpt
```

Verify the installed package with:

```console
chatgpt --version
command -v chatgpt
command -v codex-desktop
```

## Tailnet web gateway

Orange uses the shared `tailnet-admin` and `tailnet-web` profiles. The former
enables Tailscale SSH and explicitly keeps the NixOS hostname as the Tailscale
hostname. The latter publishes a loopback-only nginx listener through one
Tailscale Serve HTTPS listener on port 443. Citrus-vm retains Tailscale SSH but
does not run nginx or a Tailscale Serve web mapping.

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
x11vnc remain stopped until the first noVNC WebSocket connection. A connection
creates an idempotent `shared`/`default` browser session before its RFB stream is
forwarded.

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
