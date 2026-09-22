---
name: using-git-worktrees
description: Use when work needs isolation from unrelated changes, parallel writers need separate checkouts, or the repository requires a worktree for the task.
license: MIT
---

# Using Git Worktrees

Apply the [Pi/Astra working agreement](../using-superpowers/SKILL.md).

Inspect Git status, staged and unstaged changes, existing worktrees, and the
repository's directory conventions. Reuse a suitable task worktree. Create one
when isolation is needed, not as a mandatory ceremony for every small edit.

Choose an allowed location and a non-conflicting branch. Prefer existing
repository conventions; when placing a worktree inside the checkout, confirm
the directory is ignored before creation. Otherwise use a suitable external
location. Do not silently alter global Git configuration or repository ignore
rules merely to enforce a preferred layout.

Create from the required revision and verify its branch, HEAD, and status.
Uncommitted parent inputs are not copied by `git worktree add`; deliberately
provide authorized task inputs without staging, stashing, or copying unrelated
user work. Give each concurrent writer its own checkout and ownership scope.

Use absolute checkout paths or explicit working directories in commands. Apply
only the setup and checks needed for the task; do not automatically install
mutable dependencies or run every suite as a pre-change baseline. Follow any
repository-required baseline checks and report failures before relying on them.

Return the worktree path, input revision, and checks to the parent. Keep the
worktree until its work has been integrated or handed off. Cleanup must preserve
dirty, untracked, or unmerged work and follow the user's authority; never force
removal to make the checkout look clean.
