---
name: diagnosing-superpowers
description: Use when investigating why a Superpowers skill triggered incorrectly, stalled work, repeated steps, or was not followed in a specified session.
license: MIT
---

# Diagnosing Superpowers

Apply the [Pi/Astra working agreement](../using-superpowers/SKILL.md).
Diagnose the requested session without silently changing skills or exporting
conversation data.

Identify the symptom and session from the request. Prefer relevant context
already available and the harness's bounded history tools. If a prior session
cannot be identified, ask for the needed locator rather than searching all user
conversations. Read only evidence needed for the symptom; avoid credentials,
unrelated accounts, and broad transcript dumps.

Locate the triggering request, discovered skill description, actual SKILL.md
content loaded, applicable higher-priority instructions, tool actions, and
result. Cite message IDs or file/line coordinates. Distinguish:

- A discovery or stale-deployment problem.
- An ambiguous trigger or conflicting workflow instruction.
- A tool/runtime failure or missing capability.
- A model decision that did not follow the available instruction.

State observed facts separately from hypotheses and identify missing evidence.
Recommend the smallest correction and a targeted scenario to verify it. Keep a
diagnosis-only request read-only; apply repairs only when requested or already
authorized. Use [writing-skills](../writing-skills/SKILL.md) for authorized skill
changes.

This local adaptation has no transcript-export or issue-filing helper. Do not
upload logs, bundles, or private session data, even if a tool promises automatic
scrubbing. A separately authorized export requires explicit content review;
public issue filing or other publication needs its own authority.
