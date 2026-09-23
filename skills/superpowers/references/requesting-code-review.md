# Requesting Code Review

Request independent assessment of the actual changes and relevant callers.

Use a fresh configured reviewer. Supply the goal, requirements, exact checkout,
base revision or commit range, allowed read-only actions, and constraints.
Include staged, unstaged, and relevant new files in a readable diff artifact
when the role has no shell. Provide factual check results without a verdict
that primes the reviewer.

Ask for correctness, security and regression risks, requirement coverage, missing
checks, and file responsibility. Findings should identify severity, file/line
evidence, a concrete failure scenario, and a repair direction. Distinguish defects
from optional preferences.

Verify findings before repairing them. Seek follow-up only on changed or unresolved
areas, and ensure the required final review covers the integrated result.
In Pi, inspect reports with `get_subagent_result` and close a verified delivery
with `manage_subagents(action: "close", delivery_id: ...)`.

If independent review is unavailable, report the limitation and unfinished gate.
Do not create a repository, change global roles, or commit solely to make a
read-only review possible.
