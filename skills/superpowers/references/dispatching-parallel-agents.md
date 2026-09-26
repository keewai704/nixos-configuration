# Dispatching Parallel Agents

Parallelize independent questions or owned files when another context is worth
the overhead. Avoid duplicate investigations and concurrent writes to shared
files. Keep dependent work sequential or express real prerequisites with
dependencies.

Use the harness's subagent tool for bounded tasks. Inspect each agent type's
actual tools; read-only agents may have no shell. Choose a model suited to the
task difficulty when the harness allows it rather than defaulting to the most
expensive one. Honor user choices.

Give each task its goal, exact checkout, relevant inputs, allowed actions/files,
constraints, acceptance criteria, and expected evidence. Writers need a committed
revision and isolated worktree; uncommitted parent inputs do not transfer.
Use background execution while the parent handles complementary work. Follow
the active policy's concurrency and depth limits. Nested delegation cannot expand
the child's authority or effective tool/resource scope; a read-only child cannot
create a writer.

Collect terminal results and inspect actual evidence
and changes. A launch receipt is not completion. Keep integration, staging,
commits, and activation with the parent. Preserve worktrees and history; report
delegation failure and continue useful local work without inventing a review.
