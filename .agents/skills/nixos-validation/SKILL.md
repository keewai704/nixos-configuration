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
- Pi providers, context management, or TODO configuration: use disposable HOME,
  agent state, and synthetic providers without real credentials or paid requests.
  Check CLI/Web resource discovery, standard Pi tools, one registration of each
  native delegation tool, and the selected provider's model/auth/tool bridge.
  Test context notes and raw-history retrieval across repeated compaction, resume,
  and branches; check bounded output, opaque/private payload exclusion, aborts,
  failures, and preserved tool-call/result boundaries. Test pi-tasks CRUD,
  dependencies, persistence/resume, real runtime fork isolation, failed ledger
  reads/initialization preserving original data, and absence of execution tools
  or auto-cascade. Configuration alone does not prove live authentication.
  Verify deployed resources and affected service behavior after both activation
  gates without reloading the owning migration session. Preserve retired runtime
  artifacts and configuration locally; do not rewrite historical sessions.
- Native Pi delegation integration: use disposable HOME and agent state with
  synthetic local providers, never real credentials, sessions, or paid model APIs.
  Run package-local shared runtime and adapter tests using the pinned Pi SDK.
  Load the built CLI artifact and Web adapter with the configured filters; check
  one registration of Agent, get_subagent_result, steer_subagent, and
  manage_subagents, six exact roles, and actual child tools/model/provider bindings.
  Preserve MCP/search/LSP resources; do not make those ambient packages production
  build dependencies. Code Mode and its retired conversion fixture are not part
  of the configured runtime.
  Verify concurrency across batches/resumes, dependency failure and explicit
  integrated-change release, messages and input/follow-up/verified-close, durable
  delivery, parent process ownership, and teardown before resume. Use disposable
  providers to exercise root/child/grandchild tool calls, immediate-parent results,
  read-only capability ceilings, third-level rejection, and subtree cancellation
  and shutdown. Retained pre-change children must keep their captured tool scope.
  Confirm compact session rows and conversation shortcuts at both browser widths;
  do not add task counters, task cards, or parent-control forms. Sessions without
  child conversations must keep the original toolbar. Use disposable
  Git repositories with explicit committed writer inputs. Confirm no automatic
  commits, merges, worktree deletion, or restart replay; preserve abandoned work.
  Exercise original Web conversation navigation at mobile and desktop widths,
  including reconnect and retained history. Verify task controls through native
  tools and the shared API without introducing another management UI.
  Check managed role links are discoverable and read-only. Keep native settings
  enabled; old plugin registrations and loaded skills/prompts must be absent.
  Recheck deployed CLI/Web resource loading, native lifecycle, service health,
  canonical /pi/ assets and events after each activation gate. A launch receipt or
  accepted message is not completion or consumption, and isolated provider tests
  do not prove live provider authentication. Never reload the migration session.
  For resource/config-only changes, exercise the affected loading and bridge paths;
  do not rerun unchanged controller and browser-navigation suites by default.
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
