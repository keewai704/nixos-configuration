---
name: receiving-code-review
description: Use when addressing review comments or suggested code changes, especially when a finding is ambiguous, unsupported, or conflicts with the requested scope.
license: MIT
---

# Receiving Code Review

Apply the [Pi/Astra working agreement](../using-superpowers/SKILL.md).
Evaluate review feedback technically rather than accepting or rejecting it by
authority. Read the complete finding and relevant code before editing.

For each finding, identify the affected requirement, caller, and failure
scenario. Reproduce or reason from concrete evidence. Ask for clarification
when ambiguity materially changes the repair; continue independent clear work.
If the finding is incorrect, explain why with code or test evidence. Do not
perform a refactor solely to satisfy a stylistic preference outside scope.

Fix correctness, security, and blocking requirement gaps first, then other
confirmed defects. Keep each repair focused and run the affected checks.
Preserve unrelated work and compatibility. Review feedback does not authorize
remote changes, destructive cleanup, or expansion of the original task.

Report which findings were fixed, which were rejected with reasons, and which
remain blocked. Seek independent follow-up on changed or unresolved areas when
required. Do not substitute agreement, praise, or a promise to fix something
for the actual verified repair.
