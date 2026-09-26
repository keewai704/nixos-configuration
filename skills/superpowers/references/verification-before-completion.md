# Verification Before Completion

Match each completion claim to evidence for the actual changed inputs.

Choose the check that demonstrates the claim. Run it when no applicable passing
result exists, inspect its exit status and relevant complete output, and state
what it establishes. Truncated output, an empty search, a launch receipt, and
another agent's confidence do not prove success.

Reuse a passing check while its relevant inputs and environment remain unchanged.
Repeat or broaden after changes, failures, or unresolved concerns, not merely
because it is time to answer. Repository-required post-activation checks remain
separate from build verification.

Inspect the task diff, new files, and required review. Distinguish static checks,
executed tests, manual scenario review, and model evaluations. If evidence is
missing, state the limitation and unfinished gate. Keep implementation, commit,
deployment, and publication outcomes separate.
