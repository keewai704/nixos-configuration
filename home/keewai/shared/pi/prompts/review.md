---
description: Review a diff for bugs, regressions, and missing verification
---

Target: $@

If no target is supplied, use Git status to identify staged and unstaged changes
and relevant untracked source files. Review both diffs and those new files; a
tracked-file diff alone is not the complete change. Exclude ignored/generated
artifacts and secret material, and mention exclusions that limit the review.
If a target is supplied, keep the review within that scope.
Read the applicable AGENTS.md and relevant callers. Look for concrete bugs,
regressions, and missing verification introduced by the changes. Check that file
names and placement match their responsibilities.
Report findings by severity with file and line, triggering conditions, impact,
and a suggested fix. If there are no concrete findings, say so and identify any
unverified scope. Do not edit files or change Git's index during the review.
