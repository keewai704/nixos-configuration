---
name: add-nix-mcp
description: Add or update a persistent MCP server for local ChatGPT Desktop and Codex through the NixOS configuration at /home/keewai/nixos-configuration. Use when the user asks to install, register, configure, replace, or persist an MCP server with Nix; do not use merely to call an already configured MCP server.
---

# Add a Nix-managed MCP server

Use `/home/keewai/nixos-configuration` as the only source of truth. The workflow
must work from any current directory. Use the absolute paths below, run Git as
`git -C /home/keewai/nixos-configuration`, and use flake references beginning
with `/home/keewai/nixos-configuration#`. Never rely on `.` or a prior `cd`.

## Establish the local boundary

1. Read `/home/keewai/nixos-configuration/AGENTS.md` completely.
2. Resolve the runtime host with the required fallback and compare it with
   `/etc/hostname`. Stop on any mismatch:

   ```bash
   runtime_host="$(hostnamectl --static 2>/dev/null || hostname)"
   etc_host="$(tr -d '\n' < /etc/hostname)"
   test "$runtime_host" = "$etc_host"
   ```
3. Confirm the exact runtime host exists in the flake:

   ```bash
   nix eval --json /home/keewai/nixos-configuration#nixosConfigurations --apply builtins.attrNames
   ```

4. Inspect `git -C /home/keewai/nixos-configuration status --short` and preserve
   every unrelated change. Never contact another host unless the current user
   request explicitly authorizes that exact remote operation.

## Choose the declaration route

Edit `/home/keewai/nixos-configuration/modules/chatgpt-desktop-extensions.nix`.
Do not edit `/etc/codex/config.toml`,
`/home/keewai/.codex/config.toml`, or
`/home/keewai/.config/mcp/mcp.json`; those are generated output or application
state.

Resolve and inspect the pinned `mcp-servers-nix` source before using an option:

```bash
mcp_servers_source="$(nix eval --impure --raw --expr '(builtins.getFlake "/home/keewai/nixos-configuration").inputs."mcp-servers-nix".outPath')"
find "$mcp_servers_source/modules/servers" -maxdepth 1 -type f -name '*.nix' -print
```

- If the resolved absolute file
  `$mcp_servers_source/modules/servers/<server>.nix` exists, read that whole
  file and configure its actual options under `mcp-servers.programs`.
- For a remote endpoint or an unsupported server, declare it under
  `mcp-servers.settings.servers` using the shape supported by
  `/home/keewai/nixos-configuration/modules/chatgpt-desktop-extensions.nix`.
- For an unsupported local stdio server, package the executable in Nix under
  `/home/keewai/nixos-configuration/pkgs/` and reference its store executable.
  Do not depend on `npx -y`, mutable language-package caches, or a command found
  only in an interactive shell.
- Keep credentials out of Nix strings and the Nix store. Use a server module's
  verified `envFile` or `passwordCommand` support, or an existing runtime-secret
  mechanism. Do not invent an option that the pinned module does not expose.
- Leave ChatGPT Desktop's bundled `node_repl` and `cua_repl` entries
  application-managed.

Preserve the requested server name, transport, arguments, environment, working
directory semantics, and authentication behavior. Change the Codex conversion
logic only when the new server requires a field it currently drops, and inspect
the generated TOML when doing so.

## Validate before committing

Run every command against the absolute flake path:

```bash
nix run /home/keewai/nixos-configuration#formatter.x86_64-linux -- --tree-root /home/keewai/nixos-configuration /home/keewai/nixos-configuration
nix flake check --no-build /home/keewai/nixos-configuration
nix flake check /home/keewai/nixos-configuration
nix eval --json /home/keewai/nixos-configuration#nixosConfigurations.citrus-vm.config.home-manager.users.keewai.programs.mcp.servers
nix build --no-link /home/keewai/nixos-configuration#nixosConfigurations.citrus-vm.config.system.build.toplevel
git -C /home/keewai/nixos-configuration diff --check
```

Build and inspect the generated system layer:

```bash
nix build --no-link --print-out-paths '/home/keewai/nixos-configuration#nixosConfigurations.citrus-vm.config.environment.etc."codex/config.toml".source'
```

Verify that the new server has the intended command or URL and that no secret
was copied into the result. Perform a bounded MCP initialize or representative
tool call against the built server before deployment.

## Commit and deploy

Stage only task files with absolute paths, inspect the staged diff, commit, and
confirm that no task-related change remains uncommitted. Then follow every gate
in `/home/keewai/nixos-configuration/AGENTS.md`. Re-resolve the confirmed runtime
host and use only its flake output for the live operations:

```bash
runtime_host="$(hostnamectl --static 2>/dev/null || hostname)"
sudo nixos-rebuild test --flake "/home/keewai/nixos-configuration#${runtime_host}"
sudo nixos-rebuild switch --flake "/home/keewai/nixos-configuration#${runtime_host}"
```

Run `switch` only after the `test` generation, networking, and affected-service
checks pass. Before and after `switch`, verify at least:

```bash
systemctl is-active NetworkManager tailscaled
systemctl --failed --no-legend --plain
codex mcp list
codex mcp get <server-name>
```

The ChatGPT Desktop extension module is currently deployed by the `citrus-vm`
configuration. On another runtime host, validate the `citrus-vm` configuration
locally but do not contact or deploy to `citrus-vm`; perform the mandatory live
gates only against the confirmed runtime host and report that the MCP was not
activated on the desktop host.

Repeat the bounded MCP smoke test after `switch` when the runtime host is
`citrus-vm`. Confirm that
`/run/current-system` and `/nix/var/nix/profiles/system` resolve to the tested
generation, and report the commit, running state, and boot-default state.

Do not terminate the ChatGPT Desktop process that owns the current task. Tell
the user to open a new task or restart the app after MCP configuration changes.
