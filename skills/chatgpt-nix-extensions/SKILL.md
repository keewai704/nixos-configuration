---
name: chatgpt-nix-extensions
description: Manage local ChatGPT Desktop and Codex MCP servers or personal skills through the NixOS configuration repository. Use when adding, updating, removing, enabling, disabling, or troubleshooting a persistent MCP or skill integration; do not trigger merely to use an already configured integration.
---

# Nix-managed ChatGPT extensions

Treat `/home/keewai/nixos-configuration` as the source of truth for persistent
local MCP servers and personal skills.

## Configuration routes

- Declare packaged MCP servers under `mcp-servers.programs` in
  `modules/chatgpt-desktop-extensions.nix`.
- Declare an unsupported or remote MCP server under
  `mcp-servers.settings.servers`.
- Put each authored skill in `skills/<skill-name>/`. Home Manager publishes
  those directories under `~/.agents/skills`, the personal-skill location
  shared by ChatGPT Desktop and Codex.
- Leave generated files under `/etc/codex`, `~/.codex`, `~/.agents`, and
  `~/.config/mcp` alone. They are deployment outputs or application state.
- Keep credentials out of Nix values and the Nix store. Use the MCP module's
  `envFile` or `passwordCommand` support, or reference an existing runtime
  credential mechanism.

ChatGPT's bundled `node_repl` and `cua_repl` servers, system skills, and plugin
skills remain application-managed. Do not vendor or overwrite them when making
a personal extension persistent.

## Workflow

1. Follow the repository `AGENTS.md`, including its local-host boundary and
   deployment gates.
2. Inspect the pinned Home Manager and `mcp-servers-nix` option definitions
   before choosing an option name or value shape.
3. Change the repository source. Validate every changed skill with the bundled
   skill-creator validator.
4. Format, evaluate, build, commit, test, switch, and verify as required by the
   repository workflow.

## Verification

- For a skill, resolve `~/.agents/skills/<name>` and compare its `SKILL.md`
  with the committed source.
- For an MCP server, inspect `codex mcp get <name>` and perform a bounded
  initialization or tool smoke test.
- Restart ChatGPT Desktop or start a new local session after MCP changes; an
  already-running session does not gain newly configured tools.
