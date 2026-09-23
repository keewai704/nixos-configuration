---
name: requesting-code-review
description: Use when an implementation needs independent review before committing, integration, or declaring completion, or when a risky change needs an earlier review.
license: MIT
---

# Requesting Code Review

Apply the [Pi/Astra working agreement](../using-superpowers/SKILL.md).
Obtain an independent assessment of the actual changes and relevant callers.

Use the configured reviewer role with fresh context. Supply the objective,
requirements, exact checkout, base revision or commit range, allowed read-only
actions, and relevant constraints. Include staged, unstaged, and task-related
new files; reviewing only committed history can miss the implementation.
Provide factual check results without priming the reviewer with a verdict.

Ask for requirement coverage and out-of-scope changes, correctness and regression
risks, missing checks, and file responsibility/placement. Findings should include
severity, file/line evidence, a concrete failure scenario, and a suggested
direction. The reviewer should distinguish defects from optional preferences.
Keep scope bounded to the task and its affected interfaces.

Read the review and use [receiving-code-review](../receiving-code-review/SKILL.md).
Verify and repair real defects, then request follow-up on changed or unresolved
areas. Do not repeat an unchanged passing review. Ensure any required final
review covers the integrated diff, not only isolated child changes.

Inspect the role's actual prerequisites. In configured Pi, use pi-crew's
code-reviewer for correctness or quality-reviewer for maintainability. A core
read-only reviewer needs the complete diff and paths; adding bash creates a
worktree from committed inputs, not the original uncommitted changes. Do not
create a repository or commit solely to run a review. If independent
review is unavailable, report it honestly and keep mandatory gates unresolved.
