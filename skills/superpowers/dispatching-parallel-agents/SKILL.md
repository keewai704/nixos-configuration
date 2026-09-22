---
name: dispatching-parallel-agents
description: Use when multiple independent investigations or implementation tasks can proceed concurrently without shared writes or unresolved dependencies.
license: MIT
---

# Dispatching Parallel Agents

Apply the [Pi/Astra working agreement](../using-superpowers/SKILL.md).

Separate tasks by independent questions or owned files. Parallelize only where
each child can make useful progress from available inputs. Keep dependent work
sequential and avoid sending several agents to investigate the same failure.

Use the configured delegation tool and roles by their real capabilities. In Pi,
prefer pi-subagents' bundled scout, worker, reviewer, oracle, or supported
research roles. Read its native guide when the API is unclear; do not assume
Claude's Task tool, obsolete Agent profiles, or unlimited parallelism.

Each task needs its objective, exact checkout and input revision, allowed
actions/files, relevant constraints, acceptance criteria, and expected evidence.
Pass only needed context. Use separate worktrees for concurrent writers and
ensure they contain the required inputs; uncommitted parent changes do not
automatically reach children. Read-only agents may share a checkout.

Use background work while the parent handles a complementary task. Honor the
configured concurrency limits, depth limit, and user opt-outs. Retain run IDs,
collect terminal results, and inspect returned worktrees and actual changes.
A launch acknowledgement is not a finished task. Keep integration, commits,
activation, and publication with the parent. If delegation is unavailable,
report it and continue useful local work without claiming an independent review.
