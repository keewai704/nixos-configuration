# Dispatching Parallel Agents

Parallelize independent questions or owned files when another context is worth
the overhead. Avoid duplicate investigations and concurrent writes to shared
files. Keep dependent work sequential or express real prerequisites with
`needs` edges.

In Pi, discover roles with `manage_subagents(action: "list")`, then use `Agent`
for bounded tasks. Inspect each role's actual tools; read-only roles may have no
shell, and children need not inherit extensions. Keep extension-dependent checks
with the parent unless availability is verified.

Give each task its goal, exact checkout, relevant inputs, allowed actions/files,
constraints, acceptance criteria, and expected evidence. Writers need a committed
`input_revision` and isolated worktree; uncommitted parent inputs do not transfer.
Use background execution while the parent handles complementary work. Follow
the configured concurrency limit and do not recursively delegate.

Collect terminal results with `get_subagent_result` and inspect actual evidence
and changes. A launch receipt is not completion. Keep integration, staging,
commits, and activation with the parent. Preserve worktrees and history; report
delegation failure and continue useful local work without inventing a review.
