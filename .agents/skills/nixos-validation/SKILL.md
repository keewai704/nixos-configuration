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
| Local host configuration or deployed files | Use the evaluation/build in required `nixos-rebuild test`, not a duplicate prebuild or equivalent evaluation. Distributed personal skills and Pi instructions count as deployed files. |
| Personal Pi extension TypeScript | Use `home/keewai/shared/pi/tsconfig.json` with the pinned compiler or LSP. It resolves Pi/Node types from the deployed user profile; a missing profile is an environment limitation, not a reason to install mutable npm dependencies. |
| Pi providers, context management, TODO configuration, or latency tuning | Read [Pi runtime checks](references/pi-runtime.md), selecting the affected sections. |
| Native Pi delegation integration or its resources | Read [Native delegation checks](references/pi-delegation.md). Resource/config-only changes need affected loading and bridge checks, not unchanged controller/browser suites. |
| Another host only | Locally evaluate changed attributes, or build the affected output when package implementation or build logic changed. Shared settings need every host only when host-specific branches warrant validation. |
| A failing check | Read [Failure diagnosis](references/failure-diagnosis.md); compare configuration values only when they could explain the failure. |

Personal skill authoring also uses `add-nix-skill` for loader, scenario, publication,
and deployed-content checks. Do not make a model request merely to validate loading.

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
