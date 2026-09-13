# Native Codex CLI and Remote Control

All three hosts install the native CLI through Home Manager
`programs.codex`, using the `sadjow/codex-cli-nix` input pinned in `flake.lock`.
The initial package is Codex 0.154.0 from sadjow revision
`33542c7e7139127a4bac1cbe0fac8c81a570410a`. Its `nixpkgs` input follows this
repository's pinned `nixpkgs`; existing inputs are not upgraded for the install.

## Configuration and ownership

- [home/keewai/shared/codex.nix](../home/keewai/shared/codex.nix) installs the
  CLI and `~/.local/bin/codex` stable launcher. Home Manager does not generate a
  user config or global AGENTS file, or duplicate the system MCP registry.
- Existing `/etc/codex/config.toml` and `/etc/codex/requirements.toml` remain the
  shared Nix-managed settings and hook layers. Astra/xhigh, the subagent policy,
  additional instructions, MCP servers, and personal skills are retained.
  [modules/codex.nix](../modules/codex.nix) publishes them on every host.
- The CLI and server use the existing `~/.codex` configuration, authentication,
  plugins, and local state. Credentials are neither copied into Nix nor printed.
- ChatGPT Desktop keeps its own bundled backend. A terminal opened from an
  older Desktop task may still have that backend first in its inherited PATH;
  `~/.local/bin/codex` selects the Nix-installed CLI explicitly.

## Automatic user service

[home/keewai/shared/codex-remote.nix](../home/keewai/shared/codex-remote.nix)
declares `codex-remote.service`. It runs the pinned executable in the foreground:

```console
codex app-server --listen unix:// --remote-control
```

The `--remote-control` startup flag is verified in the
[pinned CLI source](https://github.com/openai/codex/blob/rust-v0.154.0/codex-rs/cli/src/main.rs).
The local control socket is
`~/.codex/app-server-control/app-server-control.sock`, protected by the user
directory and service umask. Remote Control establishes an authenticated
outbound connection to OpenAI's relay; this configuration adds no externally
reachable TCP listener, firewall opening, public HTTP service, or third-party bridge.

[modules/codex-remote.nix](../modules/codex-remote.nix) enables user
lingering so the default-target user service starts at boot and remains after
logout. The host must remain awake and online. The server runs as `keewai`
and uses the same task permissions and settings as that user.

Manage its lifecycle with systemd:

```console
systemctl --user status codex-remote.service
systemctl --user restart codex-remote.service
systemctl --user stop codex-remote.service
journalctl --user -u codex-remote.service -n 50 --no-pager
loginctl show-user keewai -p Linger
~/.local/bin/codex app-server daemon version
```

Use this service instead of `app-server daemon bootstrap`: the
[upstream bootstrap workflow](https://github.com/openai/codex/blob/rust-v0.154.0/codex-rs/app-server-daemon/README.md)
requires a mutable standalone install and starts its own updater, whereas Nix
owns the package and updates here. Pairing and read-only daemon version queries
can use the service's standard control socket.

Desktop and this service share `~/.codex`, including the installation identity.
OpenAI permits one active Remote Control relay connection for that identity.
Keep Desktop's **Settings > Connections > Control this PC > Allow connections**
off while the user service owns Remote Control. This leaves Desktop and its
local tasks running. Manage the always-on server with systemd instead of that
Desktop toggle.

An HTTP 409 with `Remote app server already online` means another process is
holding the shared connection. Turn off that process's Remote connection, then
allow the service to reconnect; do not create another Codex home or duplicate
credentials to work around it.

## Connect a phone or another PC

Use ChatGPT/Codex Remote on the controlling device, signed into the same
ChatGPT account and workspace. The server reuses the host's existing login:

```console
~/.local/bin/codex login status
~/.local/bin/codex remote-control pair
```

The pairing command issues a short-lived manual code for device registration.
Enter it in the client's Remote device-pairing flow when that option is
available; generate a new code if it expires. Each controlling device must be
paired. Do not put pairing codes in Git or service configuration.

Each host keeps its own existing `~/.codex` state and needs its own login and
pairing. Sharing the declarative profile does not copy credentials or device
identities between machines. A newly provisioned host needs that initial login
before its Remote Control connection can become ready.

[Official Remote documentation](https://learn.chatgpt.com/docs/remote-connections)
describes the desktop/mobile setup screens and QR pairing. Its supported-host
instructions focus on macOS and Windows; this Linux CLI service uses the
experimental native implementation in the pinned release. Server relay
connectivity and pairing-code issuance do not by themselves prove that a
particular phone/client has finished pairing. Client availability and any
account verification must be checked on that device.

For another PC using a Codex desktop SSH project connection, use its normal
SSH-host setup; the Nix-installed CLI is available in `keewai`'s login profile.
This repository's runtime-host boundary still requires explicit authorization
before an agent makes SSH connections to other hosts.

## Verify or update

Follow [AGENTS.md](../AGENTS.md) for staging, checks, commits, and local
test/health/switch/health gates. Confirm the native CLI version, the companion
executable, untouched configuration ownership, active user unit, lingering,
private Unix socket, Remote Control status, and pairing when provisioning.
Do not start model work merely to test connectivity.

Update the package through `nix flake update codex-cli-nix` and the normal
repository workflow. Recheck the startup flag and protocol when changing
versions. Do not replace the package with a global npm install or the mutable
standalone updater.
