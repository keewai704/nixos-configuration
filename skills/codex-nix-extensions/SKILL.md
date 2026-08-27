---
name: codex-nix-extensions
description: Manage Codex skills and MCP integrations on the orange NixOS system through /home/keewai/nixos-configuration. Use when adding, updating, installing, removing, enabling, disabling, or troubleshooting a Codex skill, MCP server, or related Codex tool configuration. Do not trigger when merely using an already configured skill or MCP tool.
---

# Nix-managed Codex Extensions

Treat `/home/keewai/nixos-configuration` as the source of truth for persistent Codex skills and MCP configuration on orange.

## Route changes through Nix

- Keep authored skill directories under `skills/<skill-name>/`. The Home Manager `programs.codex.skills` option publishes them under `CODEX_HOME/skills`; the current configuration supplies the complete `./skills` directory.
- Configure packaged MCP servers with `mcp-servers.programs.<name>` when the module supports that server.
- Configure local or otherwise unsupported MCP servers with `mcp-servers.settings.servers.<name>`, including their command, arguments, and non-secret environment.
- Preserve the existing Codex MCP projection in `flake.nix` so the shared MCP registry reaches Codex's generated system configuration.
- Keep secrets out of Nix store values. Reference an existing secret file or credential mechanism when authentication is required.

Generated files and live symlinks under `/etc/codex`, `/home/keewai/.codex`, `/home/keewai/.agents`, and the MCP registry are deployment outputs, not configuration sources.

## Workflow

1. Read the repository `AGENTS.md` and the relevant NixOS management guidance.
2. Inspect the pinned module implementation or evaluated options before choosing an option name or value shape.
3. Edit the repository source. Stage newly added flake inputs before evaluation because untracked files are absent from Git flakes.
4. Validate each changed skill with the skill-creator validator. Format and evaluate the Nix configuration, then build the orange system closure.
5. Follow the repository's commit, `nixos-rebuild test`, health-check, `nixos-rebuild switch`, and post-switch verification gates.

## Verification

- For a skill, confirm `/home/keewai/.codex/skills/<skill-name>` resolves to the intended Nix store source and that its `SKILL.md` matches the committed content.
- For an MCP server, inspect the generated Codex entry with `codex mcp get <name>` and perform a bounded tool or service smoke test.
- Confirm the repository is clean and the running and boot-default systems match the committed configuration before reporting completion.
