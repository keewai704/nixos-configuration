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

Then validate the Nix-managed publication and full system configuration:

```bash
nix run /home/keewai/nixos-configuration#formatter.x86_64-linux -- --tree-root /home/keewai/nixos-configuration /home/keewai/nixos-configuration
nix flake check --no-build /home/keewai/nixos-configuration
nix flake check /home/keewai/nixos-configuration
nix eval --json /home/keewai/nixos-configuration#nixosConfigurations.citrus-vm.config.home-manager.users.keewai.home.file --apply 'files: builtins.attrNames files'
nix build --no-link /home/keewai/nixos-configuration#nixosConfigurations.citrus-vm.config.system.build.toplevel
git -C /home/keewai/nixos-configuration diff --check
```

Confirm that the evaluated Home Manager file set contains
`.agents/skills/<skill-name>` and that deleted or renamed task skills are absent.

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
checks pass. Before and after `switch`, verify networking, failed units, Home
Manager, and the deployed skill:

```bash
systemctl is-active NetworkManager tailscaled
systemctl --failed --no-legend --plain
systemctl show home-manager-keewai.service -p Result -p ActiveState --no-pager
readlink -f /home/keewai/.agents/skills/<skill-name>
cmp /home/keewai/.agents/skills/<skill-name>/SKILL.md /home/keewai/nixos-configuration/skills/<skill-name>/SKILL.md
```

The personal skills in this repository are currently deployed by the
`citrus-vm` configuration. On another runtime host, validate the `citrus-vm`
configuration locally but do not contact or deploy to `citrus-vm`; perform the
mandatory live gates only against the confirmed runtime host and report that the
skill was not activated on the desktop host.

Confirm that `/run/current-system` and `/nix/var/nix/profiles/system` resolve to
the tested generation, and report the commit, running state, and boot-default
state. Codex usually detects skill changes automatically; if the skill is not
listed in the current client, tell the user to open a new task or restart the
app without terminating the process that owns the current task.
