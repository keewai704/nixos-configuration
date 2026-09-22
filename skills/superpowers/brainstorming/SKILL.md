---
name: brainstorming
description: Use when a feature or design has unresolved requirements, user experience choices, or architectural trade-offs. Not for a fully specified routine edit.
license: MIT
---

# Brainstorming

Apply the [Pi/Astra working agreement](../using-superpowers/SKILL.md).
Turn an unclear idea into a concrete design at the level the task needs.

1. Inspect the relevant code, callers, constraints, and existing design. Reuse
   requirements already supplied rather than asking the user to repeat them.
2. Identify the intended behavior, boundaries, failure cases, and acceptance
   criteria. Make routine choices using existing conventions. Ask a focused
   question only about a decision that materially changes the solution.
3. Compare viable alternatives when there is a real trade-off, then recommend
   one. Do not invent alternatives to satisfy a fixed count.
4. Present a concise design covering the changed flow, interfaces, data,
   important errors, and verification. Include security and compatibility where
   affected; avoid speculative infrastructure.
5. For an implementation request, continue into planning or implementation once
   material uncertainty is resolved. For a design-only request, deliver the
   design without editing. Honor an explicitly requested approval checkpoint.

Keep the design in the conversation unless a durable artifact is requested or
repository policy calls for one. Use the repository's permitted location;
do not create a `docs/` tree, commit a spec, start a browser server, or stop for
ceremonial sign-off merely because an upstream workflow does so.
