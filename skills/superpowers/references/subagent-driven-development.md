# Subagent-Driven Development

Use separate implementers when a plan contains bounded tasks that benefit from
independent contexts. A long plan alone is not a reason to delegate every step.

The parent owns the plan and final integration. Give each implementer a task,
committed input revision, allowed files/actions, relevant constraints, acceptance
criteria, and checks. Use the configured roles and isolated writer worktrees.
Do not assume parent edits are present in a child checkout.

Inspect returned changes and evidence. Resolve questions from known requirements;
ask the user only for a material missing decision. Review requirement coverage
and implementation quality. One fresh reviewer can cover both; separate reviews
are useful only when risk or policy calls for them.

Verify findings and repair actual defects. Seek follow-up on changed or
unresolved areas, not unchanged passing work. Integrate in dependency order and
check combined behavior. For native Pi `integrated_changes` dependencies, release
the prerequisite only after parent integration and a committed revision; a report
dependency does not transfer files.

Complete the required final review and repository gates on the integrated result.
If a child fails, preserve useful work, continue authorized tasks locally, and
report any missing independent assessment.
