---
name: ponytail
description: Keep implementation, fixes, refactoring, and code review simple and complete. Use for coding work or an explicit Ponytail request.
license: MIT
---

# Ponytail

Deliver the simplest correct solution for the requested coding scope. Apply
this skill to coding work only, not unrelated prose or research.

## Choose the implementation

Understand the affected flow and callers; fix a shared root cause when evidence
supports it. Prefer an existing codebase pattern, then the standard library,
a native platform feature, or an installed dependency. Add code or a dependency when
those do not meet the actual requirement. Optimize for clarity and correctness,
not a line count.

Avoid speculative features, unused abstractions, and configuration for values
that never vary. Remove existing code only after checking its callers and
behavior. Keep the files and changes needed for a complete solution.

Never trade away explicit requirements, compatibility, trust-boundary
validation, data-loss prevention, security, accessibility, or required checks.
Retain calibration controls when real hardware needs them. If a deliberate
simplification has a material limit, document that limit and the evidence that
would justify a different approach.

Use the project's existing checks and add regression coverage when changed
logic or risk needs it. Do not impose a fixed test count, ban the project's
framework, or reduce the requested scope to save code. Completion, approval,
and deployment follow the user's instructions and the repository's AGENTS.md.

## Modes and scope

Default to `full` unless the user has selected another mode in this session.
`lite` favors the straightforward implementation and briefly notes a useful
alternative. `full` follows the reuse order above. `ultra` scrutinizes new
machinery more strictly while still completing every explicit requirement.
Ask for `ponytail lite`, `ponytail full`, or `ponytail ultra` in the conversation
to change level; `stop ponytail` or `normal mode` disables the mode. Retain the
selected mode within the session until changed. These are conversational
instructions, not registered Pi commands or persistent settings.
Mode changes do not grant permission or replace repository operational gates.

Locally adapted from Ponytail 4.9.0 using the
[Astra prompting guidance](https://developers.openai.com/api/docs/guides/latest-model#prompting-best-practices),
reviewed 2026-09-13. Pi loads this file on demand through native skill discovery.
