# Subagent-Driven Development

Use separate implementers when a plan contains bounded tasks that benefit from
independent contexts. A long plan alone is not a reason to delegate every step.

The parent owns the plan and final integration. Give each implementer a task,
committed input revision, allowed files/actions, relevant constraints, acceptance
criteria, and checks. Use the configured roles and isolated writer worktrees.
Do not assume parent edits are present in a child checkout. Explicitly select
`model` and `thinking` under the active cost/task policy for each implementer;
user choices take priority, and the parent's model is not an automatic default.

Inspect returned changes and evidence for requirement coverage and implementation
quality. Resolve questions from known requirements; ask the user only for a
material missing decision. Independent review, when required by policy or useful
for a concrete risk, can cover both concerns. Do not assign a reviewer per task
by default.

Verify findings and repair actual defects. Seek follow-up on changed or
unresolved areas, not unchanged passing work. Integrate in dependency order and
check combined behavior. For native Pi `integrated_changes` dependencies, release
the prerequisite only after parent integration and a committed revision; a report
dependency does not transfer files.

Complete policy-required review and repository gates on the integrated result.
If a child fails, preserve useful work, continue authorized tasks locally, and
report any required assessment that remains unavailable.
