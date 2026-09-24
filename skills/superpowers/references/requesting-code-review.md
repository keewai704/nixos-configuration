# Requesting Code Review

Request independent assessment when the user or policy requires it, or a concrete
risk warrants it. This workflow is not a mandatory second pass for every change.

Use a fresh configured reviewer for the actual changes and relevant callers.
Supply the goal, requirements, exact checkout, base revision or commit range,
allowed read-only actions, and constraints.
Include staged, unstaged, and relevant new files in a readable diff artifact
when the role has no shell. Provide factual check results without a verdict
that primes the reviewer.

Ask for correctness, security and regression risks, requirement coverage, missing
checks, and file responsibility. Report supported findings at every severity,
then prioritize them. Each finding needs file/line evidence, a concrete failure
scenario, and a repair direction. Separate defects from optional preferences and
state unverified scope; do not suppress a real defect merely because it is minor.

Verify findings before repairing them. Seek follow-up only on changed or unresolved
areas, and ensure the required final review covers the integrated result.
In Pi, inspect reports with `get_subagent_result` and close a verified delivery
with `manage_subagents(action: "close", delivery_id: ...)`.

If independent review is unavailable, report the limitation and any required gate
left unfinished. Do not create a repository, change global roles, or commit solely
to make a read-only review possible.
