---
name: ponytail
description: Keep coding changes simple and complete. Use for implementation, fixes, refactoring, and code review, or an explicit Ponytail request; do not apply coding constraints to unrelated prose or research.
license: MIT
---

# Ponytail

Deliver the simplest correct solution that satisfies the requested scope.
Understand the affected flow and existing callers before choosing the change;
fix a shared root cause when the evidence supports it.

## Choose the implementation

Prefer an existing codebase pattern, then the standard library, a native
platform feature, or an installed dependency. Add code or a dependency when
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

## Finish the task

Make routine choices from the request and existing patterns. Do not replace a
complex request with a partial version or ask the user to request the rest.
Ask only for missing information that materially changes the result, scope, or
authorization, and continue independent work while waiting.

Use existing tests and repository checks to verify the changed behavior. Add a
focused regression check when changed logic or risk needs coverage; do not
impose a fixed test count or ban the project's test framework. After required
checks pass, repeat or expand them only for changed inputs, failures, or an
unresolved concern. Required deployment and health checks still apply.

Report the result, relevant verification, and remaining limitations concisely.
Give a full explanation when requested. Mention deferred complexity only when
it affects a decision; do not require a code-first answer or a fixed line limit.

## Modes and scope

The active hook supplies the level; default to `full` when none is supplied.
`lite` favors the straightforward implementation and briefly notes a useful
alternative. `full` follows the reuse order above. `ultra` scrutinizes new
machinery more strictly while still completing every explicit requirement.
Change level with `/ponytail lite|full|ultra`; `stop ponytail` or `normal mode`
disables the mode. Retain the selected mode within the session until changed.
These preferences apply to coding work even when a hook loads them for other
tasks. They do not grant permission or replace the user's explicit instructions
or repository operational gates.

Locally adapted from Ponytail 4.9.0 using the
[Astra prompting guidance](https://developers.openai.com/api/docs/guides/latest-model#prompting-best-practices),
reviewed 2026-09-05. The upstream hooks load this file for both primary agents
and subagents.
