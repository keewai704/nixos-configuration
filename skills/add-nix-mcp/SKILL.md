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

Before reading repository files, confirm `hostnamectl --static` (fallback
`hostname`) matches `/etc/hostname`. Then read and follow
[/home/keewai/nixos-configuration/AGENTS.md](/home/keewai/nixos-configuration/AGENTS.md),
including the matching flake-host check and preservation of unrelated changes.
That file owns the shared preparation, commit, test, health, and switch gates;
reuse checks already completed for unchanged inputs in this task.

If isolation is needed, use the actual isolated checkout's absolute paths in
place of `/home/keewai/nixos-configuration` throughout this procedure.
Never substitute a different runtime host or contact another host without the
specific remote authorization required by AGENTS.md.

## Choose the declaration route

Edit `/home/keewai/nixos-configuration/hosts/citrus/codex.nix`.
Do not edit `/etc/codex/config.toml`,
`/home/keewai/.codex/config.toml`, or
`/home/keewai/.config/mcp/mcp.json`; those are generated output or application
state.

Resolve and inspect the pinned `mcp-servers-nix` source before using an option:

```bash
mcp_servers_source="$(nix eval --impure --raw --expr '(builtins.getFlake "/home/keewai/nixos-configuration").inputs."mcp-servers-nix".outPath')"
rg --files "$mcp_servers_source/modules/servers" -g '*.nix'
```

- If the resolved absolute file
  `$mcp_servers_source/modules/servers/<server>.nix` exists, read that whole
  file and configure its actual options under `mcp-servers.programs`.
- For a remote endpoint or an unsupported server, declare it under
  `mcp-servers.settings.servers` using the shape supported by
  `/home/keewai/nixos-configuration/hosts/citrus/codex.nix`.
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

Format only the Nix files changed by this task. Start with `codex.nix` and append
an explicit absolute package or module path only when this task changed it;
never pass the repository root as the formatting target:

```bash
task_nix_files=(
  /home/keewai/nixos-configuration/hosts/citrus/codex.nix
)
nix run --no-write-lock-file /home/keewai/nixos-configuration#formatter.x86_64-linux -- \
  --tree-root /home/keewai/nixos-configuration "${task_nix_files[@]}"
```

Before any flake-based check, stage every task path explicitly with
`git -C /home/keewai/nixos-configuration add -- <absolute-task-path>...` and
inspect `git -C /home/keewai/nixos-configuration diff --cached`. Git flakes
omit untracked files, so evaluation before this task-only staging step does not
validate a new package or module. Verify that the staged diff contains
only this task, using isolation when required by AGENTS.md.

Then run every check against the absolute flake path:

```bash
nix flake check --no-write-lock-file /home/keewai/nixos-configuration
nix eval --json --no-write-lock-file /home/keewai/nixos-configuration#nixosConfigurations.citrus.config.home-manager.users.keewai.programs.mcp.servers
nix build --no-link --no-write-lock-file /home/keewai/nixos-configuration#nixosConfigurations.citrus.config.system.build.toplevel
git -C /home/keewai/nixos-configuration diff --check
```

Build and inspect the generated system layer:

```bash
nix build --no-link --no-write-lock-file --print-out-paths '/home/keewai/nixos-configuration#nixosConfigurations.citrus.config.environment.etc."codex/config.toml".source'
```

Verify that the new server has the intended command or URL and that no secret
was copied into the result. Perform a bounded MCP initialize or representative
read-only tool call against the built server before deployment.

## Commit and deploy

Confirm that the staged diff contains only task paths, commit it, and confirm
that no task-related change remains uncommitted. Then follow every gate in
`/home/keewai/nixos-configuration/AGENTS.md`, substituting the absolute flake
reference `/home/keewai/nixos-configuration#${runtime_host}` wherever that
workflow uses `.#${runtime_host}`. Before and after `switch`, also verify the
MCP-specific state:

```bash
systemctl is-active NetworkManager tailscaled
systemctl --failed --no-legend --plain
codex mcp list
codex mcp get <server-name>
```

The ChatGPT Desktop extension module is currently deployed by the `citrus`
configuration. Run the live gates only when the confirmed runtime host is
`citrus`. On another runtime host, validate the `citrus` configuration
locally, do not contact either host or activate an unrelated local generation,
and report that the MCP was not activated on the desktop host.

Repeat the bounded MCP smoke test after `switch` when the runtime host is
`citrus`. When those live gates apply, confirm that `/run/current-system`
and `/nix/var/nix/profiles/system` resolve to the tested generation. Report the
commit and whether deployment and boot-default checks were applied.

Do not terminate the ChatGPT Desktop process that owns the current task. Tell
the user to open a new task or restart the app after MCP configuration changes.
