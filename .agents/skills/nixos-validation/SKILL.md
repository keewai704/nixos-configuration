---
name: nixos-validation
description: Choose change-specific checks or diagnose failed checks in nixos-configuration and its worktrees.
---

# Validate NixOS configuration changes

[AGENTS.md](../../../AGENTS.md) owns host identity, worktree protection,
authorization, review, commits, and activation. This skill selects checks for
this repository, not other projects. Record the pre-edit Git commit once;
do not take routine pre-change evaluations or configuration snapshots.

## Select checks by impact

Format and check syntax only for task files. Use the smallest checks that cover
the changed behavior and its imports:

| Change | Checks |
| --- | --- |
| Repository documentation or repository-only skills | Whitespace, links, instruction consistency, and skill frontmatter; no Nix evaluation/build. |
| Local host configuration or deployed files | Use the evaluation/build in required `nixos-rebuild test`, not a duplicate prebuild or equivalent evaluation. Distributed personal skills count as deployed files. |
| File moves or renames without intended behavior change | Compare each affected host's `system.build.toplevel.drvPath` with the pre-move value; explain any difference. |
| Another host only | Locally evaluate changed attributes, or build the affected output when package implementation or build logic changed. Shared settings need every host only when host-specific branches warrant validation. |
| A failing check | Read [Failure diagnosis](references/failure-diagnosis.md); compare configuration values only when they could explain the failure. |

Personal skill authoring also uses `add-nix-skill` for loader, scenario, publication,
and deployed-content checks. Do not make a model request merely to validate loading.

## Display-manager and compositor migrations

Before replacing a compositor or session manager, inspect the active session's
unit graph and the incoming unit definitions. Removing UWSM units can terminate
the desktop even when greetd and the compositor use `restartIfChanged = false`.

Greetd's `initial_session` is boot-only: its runfile prevents repeating autologin
after a session ends or greetd restarts in the same boot. Restarting greetd,
changing PAM or credentials, deleting the runfile, or making the default greeter
passwordless is not a migration repair. Remembered tuigreet commands can also
override the new default session; do not retain user-session command restoration
when replacing that session.

If the old session's units must disappear, either retain their required
integration in a reviewed compatibility stage or obtain explicit authorization
for a controlled boot migration that bypasses the normal live test/switch gate.
Preserve the known-good boot entry. Neither a successful build nor a headless
compositor check proves physical login, NVIDIA output, or new-kernel bootability.
Until that transition is authorized and checked, report activation as blocked
and leave the current session and boot default unchanged.

## Evidence and completion

Keep syntax/dependency checks and tests included in upstream builds. Do not add
fixed-value tests that mirror configuration, standalone check suites, or routine
extra upstream test runs. `nix flake check`, full configuration evaluation,
expected-value inventories, and before/after comparisons are not universal gates.

Reuse passing checks while their relevant inputs remain unchanged. Repeat or
broaden for changed inputs, failures, or unresolved concerns. Distinguish executed
checks, manual scenario reviews, synthetic model tests, and unverified behavior.

Follow AGENTS.md through task-only diff review, required review, commit, and
applicable local `test` and `switch`. Each post-test and post-switch runtime check
is a separate gate: network connectivity, failed system/user units, affected
service behavior, and final running/boot-default store-path agreement cannot be
replaced by earlier static checks. Do not switch after a failed test or runtime
gate. Report the blocked gate and remaining work.
