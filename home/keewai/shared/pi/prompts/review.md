---
description: Review a diff for bugs, regressions, and missing verification
---

Target: $@

If no target is supplied, use Git status to identify staged and unstaged changes
and relevant untracked source files. Review both diffs and those new files; a
tracked-file diff alone is not the complete change. Exclude ignored/generated
artifacts and secret material, and mention exclusions that limit the review.
If a target is supplied, keep the review within that scope.
When native delegation is available and not disabled, request a fresh
`code-reviewer` assessment under the active delegation policy. Supply the exact
checkout, complete readable diff/new-file paths, and requirements, not your
conclusions. Do not reuse the implementer's context or create a repository/commit
just to obtain review. Verify findings and close the verified report. If delegation
is unavailable, disabled, or fails, review locally and state the limitation.
Read the applicable AGENTS.md and relevant callers. Look for concrete bugs,
regressions, and missing verification introduced by the changes. Check that file
names and placement match their responsibilities.
Report actionable findings by severity with file and line, triggering conditions,
impact, and how to demonstrate the failure. Separate defects from preferences.
If there are no concrete findings, say so and identify unverified scope. Do not
edit files or change Git's index during the review.
