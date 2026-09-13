---
name: add-nix-mcp
description: Add or update Nix-managed MCP server configuration for local ChatGPT and Codex. Use for persistent server changes, not calls to an existing server.
---

# Add a Nix-managed MCP server

Use `/home/keewai/nixos-configuration` as the source. Follow its
[AGENTS.md](/home/keewai/nixos-configuration/AGENTS.md) for host confirmation,
worktree protection, checks, commits, and local activation. Reuse preparation
already completed for this task. Use the actual checkout's absolute paths with
`git -C` and flake references when working elsewhere or in an isolated worktree.

## Declare the server

The common registry is
[/home/keewai/nixos-configuration/home/keewai/shared/mcp.nix](/home/keewai/nixos-configuration/home/keewai/shared/mcp.nix).
Desktop-only servers belong in the desktop profile; CUA is defined in
[/home/keewai/nixos-configuration/home/keewai/desktop/cua.nix](/home/keewai/nixos-configuration/home/keewai/desktop/cua.nix).
The generated Codex registry combines only the profiles selected by that host.
Do not edit generated `/etc/codex/config.toml`, `~/.config/mcp/mcp.json`, or
application-owned `~/.codex/config.toml` for persistent server configuration.

Inspect the requested server's module in the pinned `mcp-servers-nix` input.
For the default checkout, resolve its source with:

```bash
nix eval --impure --raw --expr '(builtins.getFlake "/home/keewai/nixos-configuration").inputs."mcp-servers-nix".outPath'
```

- If `modules/servers/<server>.nix` exists, inspect its options and configure
  the server under `mcp-servers.programs`.
- Use `mcp-servers.settings.servers` for remote endpoints or servers without a
  module, following the registry's supported transport shape.
- Package unsupported local stdio executables under `pkgs/` and reference
  their Nix store paths. Do not rely on `npx -y`, mutable package caches, or
  executables available only in an interactive shell.
- Keep credentials out of Nix strings and the store. Use verified `envFile`,
  `passwordCommand`, or an existing runtime-secret mechanism.
- Leave Desktop's bundled `node_repl` and `cua_repl` entries application-owned.

Preserve the requested name, transport, arguments, environment, working
directory, and authentication behavior. Change the conversion in
[modules/codex.nix](/home/keewai/nixos-configuration/modules/codex.nix)
only if a required field is missing from generated Codex configuration.

## Verify the integration

In addition to AGENTS.md's change-specific checks:

- Inspect the affected host's evaluated
  `home-manager.users.keewai.programs.mcp.servers` and the built
  `environment.etc."codex/config.toml".source`. Check the intended command or
  URL and confirm that credentials were not copied into the output.
- Perform a bounded initialize or representative read-only call against the
  changed server before deployment. Report authentication requirements without
  inventing credentials or claiming success from configuration alone.
- When local activation applies, inspect `codex mcp get <server-name>` and
  repeat that smoke check after both `test` and `switch`.

Derive affected hosts from imports, as AGENTS.md requires; do not restrict live
activation to the physical desktop's hostname. Never terminate the application
owning the current task. If the client needs to reload the changed server,
tell the user to start a new task or restart it after the work is complete.
