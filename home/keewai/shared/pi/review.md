---
description: Review a diff for bugs, regressions, and missing verification
---

Target: $@

If no target is supplied, review staged and unstaged changes to tracked files.
Read the applicable AGENTS.md and relevant callers. Look for concrete bugs,
regressions, and missing verification introduced by the changes. Check that file
names and placement match their responsibilities.
Report findings by severity with file and line, triggering conditions, impact,
and a suggested fix. If there are no concrete findings, say so and identify any
unverified scope. Do not change files during the review.
