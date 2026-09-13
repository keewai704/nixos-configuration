---
name: add-nix-skill
description: Create or update personal skills managed by nixos-configuration. Use for persistent skill changes, not ordinary skill invocation or unrelated repository skills.
---

# Add a Nix-managed skill

Author sources under `/home/keewai/nixos-configuration/skills`. Follow the
repository's [AGENTS.md](/home/keewai/nixos-configuration/AGENTS.md) for host
confirmation, worktree protection, checks, commits, and local activation.
Reuse preparation already completed for this task. When working outside the
checkout or in an isolated worktree, use that checkout's absolute paths with
`git -C` and flake references.

## Author and publish

For a new or substantially revised skill, use the available `skill-creator`
guidance, reusing it if already read. Keep one focused purpose, a concise
description, and only the references or scripts the workflow needs. Repository
operational gates belong in AGENTS.md rather than being repeated in the skill.

Home Manager publishes selected `skills/<name>` directories under
`~/.agents/skills`. Ponytail is published under `/etc/codex/skills/ponytail`;
its lifecycle hook injects a short reference instead of the full skill.
Check publication filters when adding, renaming, or removing a skill.

Use `apply_patch` to edit the source. Do not reinitialize an existing skill or
write into generated skill directories. Preserve application-managed system
skills and plugin caches; cross-project routing preferences belong in
`hosts/citrus/codex.nix`. Add `agents/openai.yaml` when invocation policy or UI
metadata needs to change, preserving other metadata.

## Verify skill behavior

Validate each changed skill with the available bundled `quick_validate.py`.
If Python/PyYAML is unavailable, the pinned runtime for the default checkout is:

```bash
nix shell --impure --no-write-lock-file --expr 'with import (builtins.getFlake "/home/keewai/nixos-configuration").inputs.nixpkgs { system = builtins.currentSystem; }; python3.withPackages (pythonPackages: [ pythonPackages.pyyaml ])' --command python3 /home/keewai/.codex/skills/.system/skill-creator/scripts/quick_validate.py /home/keewai/nixos-configuration/skills/<skill-name>
```

For material trigger or workflow changes, check realistic matching and
non-matching requests against the new instructions. Verify decisions and
boundaries, not exact wording; report whether this was a manual scenario review
or an executed model evaluation. Keep this check within the authorized
resources and the user's delegation policy.

In addition to AGENTS.md's checks, verify the evaluated Home Manager file set
or Ponytail's `environment.etc` source. After applicable local `test` and
`switch`, confirm Home Manager success and compare each deployed skill with
its repository source. For changed hook behavior, exercise activation and
mode changes with temporary state, leaving the active session untouched.

Use AGENTS.md's evaluated-host impact rule for deployment. If the client has
not reloaded a changed skill, tell the user to open a new task or restart the
app after completion; do not terminate the application owning the task.
