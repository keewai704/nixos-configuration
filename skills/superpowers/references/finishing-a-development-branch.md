# Finishing Work

Use the completion path already authorized by the request and repository.

Inspect the task diff, relevant new files, branch/base, check results, and required
independent review. Resolve actual defects and missing gates. Confirm file
placement and preserve unrelated work.

When integration is authorized, inspect the worktree changes, integrate into the
intended branch, and verify combined behavior. Stage only intended files and
perform required commits and deployment after their gates. A patch-only or
review-only request does not imply a merge or activation.

Ask about integration only when a real decision remains; do not force a fixed
merge/PR/keep/discard menu. Remote publication and destructive cleanup need their
own authority. Retain unmerged worktrees and report their paths rather than
removing them as routine tidying.

Report changes, evidence, commit status, and any deployment results the
repository requires. A blocked push does not undo a completed local delivery.
