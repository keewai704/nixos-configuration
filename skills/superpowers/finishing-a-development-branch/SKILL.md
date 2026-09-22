---
name: finishing-a-development-branch
description: Use when implementation is ready for authorized integration, commit, deployment, or handoff, including work produced in an isolated worktree.
license: MIT
---

# Finishing a Development Branch

Apply the [Pi/Astra working agreement](../using-superpowers/SKILL.md) and
[verification-before-completion](../verification-before-completion/SKILL.md).

Inspect the task diff, relevant new files, branch/base, check results, and
independent review. Resolve confirmed defects and missing gates. Confirm files
are in their responsible locations and unrelated user work remains untouched.

Use the completion path already authorized by the request and repository:

- If local commits or activation are required, perform them after their gates.
  Stage only intended files and verify the resulting commit and remaining state.
- If local integration is authorized, inspect the actual child/worktree changes,
  integrate them into the intended branch, and verify combined behavior.
- If the task requests a patch or review only, hand it off without inventing a
  merge, commit, deployment, or remote publication step.

Ask about integration only when a real decision remains. Do not always present
a fixed merge/PR/keep/discard menu, stop after implementation, or infer push/PR
permission from local edit permission. Failed publication does not undo a
completed local commit or deployment.

Before any authorized worktree or branch cleanup, verify that work is preserved
and inspect dirty, untracked, and unmerged content. Do not force-delete a branch,
reset files, or discard work as routine completion. Report retained paths and
outstanding decisions. State changes, verification, commit status, and applicable
live/boot-default deployment results concisely.
