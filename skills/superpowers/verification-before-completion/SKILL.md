---
name: verification-before-completion
description: Use before claiming a change works, a bug is fixed, checks pass, or deployment is complete, and when evaluating evidence supplied by another agent.
license: MIT
---

# Verification Before Completion

Apply the [Pi/Astra working agreement](../using-superpowers/SKILL.md).
Match each claim to evidence for the actual changed inputs.

Identify the check that would demonstrate the claim. Run it if no applicable
passing result exists, inspect its exit status and relevant complete result,
and report what it establishes. Filter noisy output without hiding failures;
truncation, an empty search, a launch receipt, and an agent's confidence are not
proof of success.

Reuse a passing result when its relevant inputs and environment remain valid.
Repeat or broaden checks after changes, failures, or unresolved concerns, not
just because it is time to write the final answer. Required post-activation
runtime checks remain separate gates and cannot be replaced by a build.

Check the actual task diff, relevant new files, and repository-required review.
A child's report is evidence to inspect, not permission to skip validation.
Distinguish static checks, executed tests, manual scenario review, and model
evaluations. Never claim a command or model evaluation ran when it did not.

If evidence is unavailable, state the specific limitation and unfinished gate.
Do not use "should work" as a completion claim. Keep implementation, checks,
commit, running deployment, boot-default persistence, and publication outcomes
separate where applicable; do not imply a local change reached another host.
