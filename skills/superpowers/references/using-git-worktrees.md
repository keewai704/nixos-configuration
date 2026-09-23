# Using Git Worktrees

Use isolation when unrelated changes, concurrent writers, or repository policy
require it. Reuse a suitable task worktree rather than creating one for every edit.

Inspect Git status, staged and unstaged changes, existing worktrees, and directory
conventions. Choose the required base revision, an allowed location, and a
non-conflicting branch. If placing a worktree inside a checkout, confirm that
location is ignored; do not silently change global Git settings.

Verify the worktree's HEAD, branch, and status. Uncommitted inputs are not copied
by `git worktree add`; deliberately provide only authorized task inputs.
Use absolute paths or explicit working directories. Run setup and checks needed
for the task, not unconditional dependency installation or full-suite baselines.

Retain the path and base revision for integration or handoff. Before authorized
cleanup, verify that dirty, untracked, and unmerged work is preserved. Worktree
creation is not permission to force-delete it, reset files, or discard a branch.
