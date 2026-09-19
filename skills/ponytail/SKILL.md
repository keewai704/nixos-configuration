---
name: ponytail
description: Keep requested work simple, necessary, and complete. Use for coding work or explicit Ponytail, KISS, YAGNI, simplification, or speculative-scope reviews.
license: MIT
---

# Ponytail

Deliver the simplest correct solution for the requested scope. Apply this skill
to implementation, fixes, refactoring, and code review by default. Also use it
for designs, plans, or explanations when simplification or speculative-scope
review is explicitly requested, not for unrelated prose or research.

## Choose the solution

Understand the affected flow and callers; identify the complexity obstructing
the current requirement before changing it. Fix a shared root cause when
evidence supports it. Prefer direct control flow, ordinary data structures,
clear names, and fewer independently configured parts. Optimize for correctness
and ease of understanding, operation, and change, not a line count.

For code, prefer an existing codebase pattern, then the standard library, a
native platform feature, or an installed dependency. Add code or a dependency
when those do not meet the actual requirement.

Before adding a feature, option, abstraction, dependency, or extension point,
identify its present caller or concrete requirement. If none exists, defer it.
Avoid configuration for values that never vary. Remove unused machinery and
indirection only after checking callers, responsibilities, and observable
behavior; if use cannot be ruled out safely, report the uncertainty instead of
deleting it. Keep the files and changes needed for a complete solution.

Never trade away explicit requirements, compatibility, trust-boundary
validation, data-loss prevention, security, accessibility, or required checks.
Explain simplifications, deferrals, and material limits when they affect the
user's decision, including the concrete requirement or evidence that would
justify a different approach. Do not turn explicit scope into future work.

Use the project's existing checks and add regression coverage when changed
logic or risk needs it. Do not impose a fixed test count, ban the project's
framework, or reduce the requested scope to save code. Completion, approval,
and deployment follow the user's instructions and the repository's AGENTS.md.

## Modes and scope

Default to `full` unless the user has selected another mode in this session.
`lite` favors the straightforward implementation and mentions an alternative
only when it affects the user's decision. `full` follows the reuse order above.
`ultra` scrutinizes new machinery more strictly while still completing every
explicit requirement.
Ask for `ponytail lite`, `ponytail full`, or `ponytail ultra` in the
conversation to change level; `stop ponytail` or `normal mode` disables the mode.
Retain the selected mode within the session until changed. These are conversational
instructions, not registered Pi commands or persistent settings.
Mode changes do not grant permission or replace repository operational gates.

Locally adapted from Ponytail 4.9.0 using the
[Astra prompting guidance](https://developers.openai.com/api/docs/guides/latest-model#prompting-best-practices),
reviewed 2026-09-13. Pi loads this file on demand through native skill
discovery.
