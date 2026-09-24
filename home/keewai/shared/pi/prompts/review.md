---
description: Review a specified change for bugs, regressions, and verification gaps
argument-hint: "[target]"
---

Review $@ without editing files or changing Git's index.

If no target is supplied, include staged and unstaged changes and relevant
untracked source files. Exclude ignored/generated artifacts and secrets; state
exclusions that limit the review. Read applicable AGENTS.md instructions and
relevant callers, keeping the review within the supplied scope.

Report supported findings at every severity, prioritized by impact. For each,
give file/line, triggering conditions, consequence, and evidence or a way to
demonstrate the failure. Include correctness, security, regressions, and material
verification gaps; distinguish defects from design preferences. Check whether
file placement matches its responsibility. Do not invent findings to fill a quota.

Use native reviewers only when the active delegation policy or requested scope
warrants independent work, not as an automatic second pass. Give them accessible
complete diffs/new-file paths and requirements rather than your conclusions.
Inspect and resolve their findings within this read-only review and close verified
reports. If required independent review is unavailable, state that limitation.

Lead with findings. If none are supported, say so and identify unverified scope;
keep the summary brief rather than repeating the diff.
