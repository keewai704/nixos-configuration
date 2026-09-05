---
name: add-nix-skill
description: Create or update a personal ChatGPT Desktop and Codex skill as a Nix-managed source under /home/keewai/nixos-configuration/skills. Use when the user asks to add, author, split, replace, or persist a skill through Nix; do not use merely to invoke an existing skill or for an unrelated repository-local skill.
---

# Add a Nix-managed skill

Author personal skills in `/home/keewai/nixos-configuration/skills`; Home
Manager publishes them to `/home/keewai/.agents/skills`. The workflow must work
from any current directory. Use absolute paths, run Git as
`git -C /home/keewai/nixos-configuration`, and use flake references beginning
with `/home/keewai/nixos-configuration#`. Never rely on `.` or a prior `cd`.

## Establish the local boundary

1. Read `/home/keewai/nixos-configuration/AGENTS.md` completely.
2. Resolve the runtime host with the required fallback and compare it with
   `/etc/hostname`. Stop on any mismatch:

   ```bash
   runtime_host="$(hostnamectl --static 2>/dev/null || hostname)"
   etc_host="$(tr -d '\r\n' < /etc/hostname)"
   test "$runtime_host" = "$etc_host"
   ```
3. Confirm the exact runtime host exists in the flake:

   ```bash
   flake_host="$(nix eval --raw --no-write-lock-file \
     "/home/keewai/nixos-configuration#nixosConfigurations.${runtime_host}.config.networking.hostName")"
   test "$runtime_host" = "$flake_host"
   ```

4. Record the existing worktree before editing:

   ```bash
   git -C /home/keewai/nixos-configuration status --short --branch
   git -C /home/keewai/nixos-configuration diff
   git -C /home/keewai/nixos-configuration diff --cached
   ```

   Preserve every unrelated change. Do not format, stage, stash, reset, or
   delete it. If an unrelated tracked change can affect evaluation or
   activation, isolate the task safely or stop; do not claim that the mixed
   worktree validates only this task. If `git diff --cached --quiet` fails,
   isolate the task in a separate worktree or stop before editing; never share
   an existing index with this workflow. Never contact another host unless the
   current user request explicitly authorizes that exact remote operation.

## Author the skill

Read `/home/keewai/.codex/skills/.system/skill-creator/SKILL.md` completely
before creating or substantially changing a skill.

- Put the skill at
  `/home/keewai/nixos-configuration/skills/<skill-name>/SKILL.md`.
- Use lowercase letters, digits, and hyphens for `<skill-name>`, keep it under
  64 characters, and make the folder name equal the frontmatter `name`.
- Give the skill one focused job and a concise, discriminating `description`
  that states when it should and should not trigger.
- Keep a narrow workflow instruction-only. Add files under the absolute roots
  `/home/keewai/nixos-configuration/skills/<skill-name>/scripts`,
  `/home/keewai/nixos-configuration/skills/<skill-name>/references`, or
  `/home/keewai/nixos-configuration/skills/<skill-name>/assets` only when they
  materially improve repeatability.
- Add `/home/keewai/nixos-configuration/skills/<skill-name>/agents/openai.yaml`
  only when UI metadata, invocation policy, or tool dependencies are requested.
- Within the authored skill, express every repository or local-machine path as
  an absolute path. For commands that operate on this repository, use
  `git -C /home/keewai/nixos-configuration` and absolute flake references so
  the skill remains correct from any current directory.
- Do not write directly under `/home/keewai/.agents/skills`,
  `/home/keewai/.codex/skills`, or `/etc/codex/skills`. Preserve OpenAI-bundled
  system skills, plugin skills, and unrelated personal skills.

Create and edit repository files with `apply_patch`. Do not initialize an
existing skill again, and do not leave scaffold placeholders or unused resource
directories.

## Validate before committing

Validate every new or changed skill with the bundled validator and a Nix-provided
PyYAML runtime:

```bash
nix shell --impure --expr 'with import (builtins.getFlake "/home/keewai/nixos-configuration").inputs.nixpkgs { system = builtins.currentSystem; }; python3.withPackages (pythonPackages: [ pythonPackages.pyyaml ])' --command python3 /home/keewai/.codex/skills/.system/skill-creator/scripts/quick_validate.py /home/keewai/nixos-configuration/skills/<skill-name>
```

Markdown-only skill changes do not require Nix formatting. If the task also
changes Nix files, pass only those files' explicit absolute paths to
`/home/keewai/nixos-configuration#formatter.x86_64-linux`; never pass the
repository root as the formatting target.

Before the flake-based checks, stage every task path explicitly with
`git -C /home/keewai/nixos-configuration add -- <absolute-task-path>...` and
inspect `git -C /home/keewai/nixos-configuration diff --cached`. Git flakes
omit untracked files, so evaluation before this task-only staging step does not
validate a new skill or supporting resource. The initial clean-index gate
ensures the staged diff contains only this task.

Then validate the Nix-managed publication and full system configuration:

```bash
nix flake check --no-build --no-write-lock-file /home/keewai/nixos-configuration
nix flake check --no-write-lock-file /home/keewai/nixos-configuration
nix eval --json --no-write-lock-file /home/keewai/nixos-configuration#nixosConfigurations.citrus.config.home-manager.users.keewai.home.file --apply 'files: builtins.attrNames files'
nix build --no-link --no-write-lock-file /home/keewai/nixos-configuration#nixosConfigurations.citrus.config.system.build.toplevel
git -C /home/keewai/nixos-configuration diff --check
```

Confirm that the evaluated Home Manager file set contains
`.agents/skills/<skill-name>` and that deleted or renamed task skills are absent.

## Commit and deploy

Confirm that the staged diff contains only task paths, commit it, and confirm
that no task-related change remains uncommitted. Then follow every gate in
`/home/keewai/nixos-configuration/AGENTS.md`, substituting the absolute flake
reference `/home/keewai/nixos-configuration#${runtime_host}` wherever that
workflow uses `.#${runtime_host}`. Before and after `switch`, also verify Home
Manager and the deployed skill:

```bash
systemctl show home-manager-keewai.service -p Result -p ActiveState --no-pager
readlink -f /home/keewai/.agents/skills/<skill-name>
cmp /home/keewai/.agents/skills/<skill-name>/SKILL.md /home/keewai/nixos-configuration/skills/<skill-name>/SKILL.md
```

The personal skills in this repository are currently deployed by the
`citrus` configuration. Run the live gates only when the confirmed runtime
host is `citrus`. On another runtime host, validate the `citrus`
configuration locally, do not contact either host or activate an unrelated
local generation, and report that the skill was not activated on the desktop
host.

When the live gates apply, confirm that `/run/current-system` and
`/nix/var/nix/profiles/system` resolve to the tested generation. Report the
commit and whether deployment and boot-default checks were applied. Codex
usually detects skill changes automatically; if the skill is not listed in the
current client, tell the user to open a new task or restart the app without
terminating the process that owns the current task.
