---
name: nixos-validation
description: Select checks and diagnose post-change failures in nixos-configuration or its worktrees.
---

# Validate NixOS configuration changes

Use [AGENTS.md](../../../AGENTS.md) for host identity, worktree protection,
authorization, commits, and local activation. This skill selects validation for
this repository, not other projects.

## Choose checks by impact

Record the pre-edit Git commit once; do not take routine pre-change evaluations
or configuration snapshots. Format and check syntax only for changed files.

- Repository documentation or repository-only skills: check whitespace, links,
  instruction consistency, and skill frontmatter; no Nix evaluation or build.
- Changes affecting the local host: use the evaluation/build in the required
  `nixos-rebuild test`, not a duplicate prebuild or equivalent separate evaluation.
  Nix-distributed personal skills and Pi instructions count as deployed files.
- Personal Pi extension TypeScript: use the scoped
  `home/keewai/shared/pi/tsconfig.json` with the pinned TypeScript compiler or LSP.
  It resolves Pi and Node types from the deployed user profile; a missing profile
  is an environment limitation, not a reason to install mutable npm dependencies.
- pi-subagents integration: use disposable agent state and synthetic local model
  responses to check the pinned Pi SDK, bundled-role discovery and explicit
  child-provider bindings, foreground/background completion, status, resume, and control.
  Give bundled-reviewer fixtures a disposable Git repository with a committed
  HEAD; its watchdog_diff provider cannot initialize from an unborn repository.
  A launch receipt or accepted steering request is not a completed child or
  delivered message. Inspect terminal metadata and process cleanup separately.
  Verify that Pi Web's built-in tools are disabled and that Code Mode keeps the
  native subagent tool available. Use the configured resource filters when
  testing other packages; do not enable disabled hooks in the test fixture.
  Never read real auth/session data or contact paid model APIs for these checks.
  Recheck deployed settings and affected behavior after each activation gate;
  isolated mock tests do not prove live provider authentication or deployment.
- Another host only: locally evaluate the changed attributes, or build the affected
  output when package implementation or build logic changed. Shared settings do
  not require every host's build unless host-specific branches need validation.

Keep necessary syntax/dependency checks and tests included in upstream builds.
Do not add fixed-value tests that merely mirror configuration, standalone check
suites, or routine extra upstream test runs. Do not make `nix flake check`, full
configuration evaluation, expected-value inventories, or before/after comparisons
universal completion requirements.

Reuse passing checks while their relevant inputs remain unchanged. Repeat or
broaden them when changes, failures, or unresolved concerns justify it. Each
post-test and post-switch runtime check required by AGENTS.md is a separate gate.

## Diagnose a failure

Start with the failing command and its logs. Only compare evaluations when a
configuration-value change could explain the failure. Select the same small,
JSON-serializable attribute in the recorded commit and current checkout; never
serialize the entire configuration. An example is
`nixosConfigurations.citrus.config.services.openssh.settings`, but choose the
actual host and attribute from the failure.

Set `repo` to the actual checkout's absolute path, `before` to the recorded commit,
`attribute` to the selected attribute, and `comparison_dir` to a fresh `mktemp -d`
directory. Stage new files before evaluating a Git flake. If the initial worktree
was dirty, the recorded commit does not reproduce those uncommitted changes.

Run each evaluation separately and inspect its exit status before continuing:

```sh
nix eval --json --no-write-lock-file "git+file://$repo?rev=$before#$attribute" \
  >"$comparison_dir/before.raw.json" 2>"$comparison_dir/before.stderr"
nix eval --json --no-write-lock-file "$repo#$attribute" \
  >"$comparison_dir/after.raw.json" 2>"$comparison_dir/after.stderr"
```

Only after both succeed, normalize object keys without changing values or array
order, then compare the complete normalized files:

```sh
jq -S . "$comparison_dir/before.raw.json" >"$comparison_dir/before.json" &&
  jq -S . "$comparison_dir/after.raw.json" >"$comparison_dir/after.json"
```

Only after normalization succeeds:

```sh
diff_status=0
diff -u --label before --label after "$comparison_dir/before.json" "$comparison_dir/after.json" \
  >"$comparison_dir/values.diff" || diff_status=$?
printf 'diff exit=%s\n' "$diff_status"
```

A diff exit status of 0 means equal, 1 means different, and 2 or higher means a
comparison error. Report equality briefly. For differences, inspect relevant
passages in the saved diff. Bound displayed excerpts and errors to 8 KiB,
announce truncation, and narrow the attribute or search saved files for missing
evidence. Long strings can exceed a line-based limit.

Compare full values, not summaries or key-only JSON. Evaluation failures are not
empty values or equality; successful display filtering is not a successful source
command. Equal values do not prove a successful build or correct runtime behavior.
Rerun the failed check after repairs, expanding to extra hosts or
`nix flake check --no-write-lock-file` only when the investigation or request
justifies it. Remove the temporary directory created for this comparison when
finished; do not add repository scripts, permanent suites, or comparison files.
