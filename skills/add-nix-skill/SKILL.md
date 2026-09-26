---
name: add-nix-skill
description: Author or update Nix-managed personal skills, not invoke them or edit repository-only guidance.
---

# Add a Nix-managed skill

Edit `skills/` in the actual nixos-configuration checkout, not deployed links.
Use its [AGENTS.md](/home/keewai/nixos-configuration/AGENTS.md) for repository
gates and absolute checkout paths when working elsewhere. Reuse completed
preparation; do not restart a generic workflow for each skill.

## Author and publish

Follow the Agent Skills format: a `SKILL.md` with `name` and `description`
frontmatter, plus optional `references/` and `scripts/`. Give the description a
short, precise trigger. Keep a single workflow direct; for multiple workflows,
make the root a router to focused references and scripts. Put authority and
safety boundaries where they are loaded before the relevant action. Repository
operational gates belong in AGENTS.md rather than being copied into every skill.

Home Manager links every `skills/<name>` directory into both `~/.claude/skills`
(Claude Code) and `~/.agents/skills` (Codex) through
[skills.nix](/home/keewai/nixos-configuration/home/keewai/shared/skills.nix).
Keep skills harness-neutral: refer to "the harness's subagent tool" or "TODO
ledger" rather than one client's tool names.

Use the available editing tools on the source. Do not reinitialize an existing
skill or write into generated skill directories. Preserve unrelated metadata.

## Verify skill behavior

Check frontmatter, linked files, and relative paths. Do not add a permanent
repository test suite or make a model request merely to validate loading.

For material trigger or workflow changes, check matching, non-matching,
ambiguous, and blocked requests against the instructions. Label manual scenario
review separately from executed model evaluation.

After the local `test` and `switch` required by AGENTS.md, confirm Home Manager
succeeded and that each deployed skill link resolves to the new source. A
running client may need a new session to see changed skills; do not terminate
the application owning the task.
