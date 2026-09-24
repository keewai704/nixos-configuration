---
name: add-nix-mcp
description: Configure persistent Nix-managed MCP servers for Pi, not call an existing server.
---

# Add a Nix-managed MCP server

Edit the actual nixos-configuration checkout. Its
[AGENTS.md](/home/keewai/nixos-configuration/AGENTS.md) owns repository gates;
reuse completed preparation and use absolute checkout paths when working elsewhere.

## Declare the server

The common registry is
[shared/pi/mcp.nix](/home/keewai/nixos-configuration/home/keewai/shared/pi/mcp.nix).
Desktop-only servers belong in the desktop profile; CUA is defined in
[desktop/pi/cua.nix](/home/keewai/nixos-configuration/home/keewai/desktop/pi/cua.nix).
Pi combines only the profiles selected by that host. Do not edit generated
`~/.pi/agent/mcp.json` or `~/.config/mcp/mcp.json` for persistent configuration.

Inspect the requested server's module in the pinned `mcp-servers-nix` input.
Resolve its source from the actual checkout. This example uses the default
checkout; substitute the absolute task worktree path when working in isolation:

```bash
nix eval --impure --raw --no-write-lock-file --expr '(builtins.getFlake "/home/keewai/nixos-configuration").inputs."mcp-servers-nix".outPath'
```

- If `modules/servers/<server>.nix` exists, inspect its options and configure
  the server under `mcp-servers.programs`.
- Use `mcp-servers.settings.servers` for remote endpoints or servers without a
  module, following the registry's supported transport shape.
- Package unsupported local stdio executables under `pkgs/` and reference
  their Nix store paths. Do not rely on `npx -y`, mutable package caches, or
  executables available only in an interactive shell.
- Keep credentials out of Nix strings and the store. Use verified `envFile`,
  `passwordCommand`, or an existing runtime-secret mechanism supported by the
  server and Pi adapter.

Preserve the requested name, transport, arguments, environment, working
directory, and authentication behavior. Change the conversion in
[shared/pi/mcp.nix](/home/keewai/nixos-configuration/home/keewai/shared/pi/mcp.nix)
only if a required field is missing from Pi's generated configuration, after
checking the pinned adapter's support for that field.

## Verify the integration

In addition to AGENTS.md's change-specific checks:

- Inspect the affected host's generated `.pi/agent/mcp.json` from Home Manager.
  Check the intended command or URL and confirm that credentials were not
  copied into the output. Evaluate the source registry only when needed to
  diagnose a conversion problem.
- Perform a bounded initialize or representative read-only call against the
  changed server before deployment. Report authentication requirements without
  inventing credentials or claiming success from configuration alone.
- When local activation applies, inspect the deployed registry and repeat that
  smoke check after both `test` and `switch`. A fresh adapter process or a
  direct stdio/HTTP protocol check can test the deployed configuration without
  reloading the active conversation.

Derive affected hosts from imports, as AGENTS.md requires; do not restrict live
activation to the physical desktop's hostname. Never terminate the application
owning the current task. If the client needs to reload the changed server,
tell the user to start a new task or restart it after the work is complete.
