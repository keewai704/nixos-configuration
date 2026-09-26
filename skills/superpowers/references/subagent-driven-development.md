# Subagent-Driven Development

Use separate implementers when a plan contains bounded tasks that benefit from
independent contexts. A long plan alone is not a reason to delegate every step.

The parent owns the plan and final integration. Give each implementer a task,
committed input revision, allowed files/actions, relevant constraints, acceptance
criteria, and checks. Use the configured roles and isolated writer worktrees.
Do not assume parent edits are present in a child checkout. Choose a model
suited to each implementer's task when the harness allows it rather than
defaulting to the most expensive one. Honor user choices.

Inspect returned changes and evidence for requirement coverage and implementation
quality. Resolve questions from known requirements; ask the user only for a
material missing decision. Independent review, when required by policy or useful
for a concrete risk, can cover both concerns. Do not assign a reviewer per task
by default.

Verify findings and repair actual defects. Seek follow-up on changed or
unresolved areas, not unchanged passing work. Integrate in dependency order and
check combined behavior. Start dependent writers only after the parent has
integrated and committed their prerequisites; a report does not transfer files.

Complete policy-required review and repository gates on the integrated result.
If a child fails, preserve useful work, continue authorized tasks locally, and
report any required assessment that remains unavailable.
