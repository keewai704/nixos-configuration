---
name: writing-plans
description: Use when a defined goal needs several dependent implementation steps, coordinated work, or an explicit implementation plan.
license: MIT
---

# Writing Plans

Apply the [Pi/Astra working agreement](../using-superpowers/SKILL.md).
Make a plan another implementer can execute without guessing important decisions.

Inspect the implementation and callers first. State the goal, scope boundaries,
constraints, and observable acceptance criteria. Resolve material ambiguity
with [brainstorming](../brainstorming/SKILL.md), not speculative detail.

For each cohesive task, record:

- The behavior to change and exact files or symbols to inspect or edit.
- Dependencies, inputs, ownership, and any isolation needed.
- The smallest meaningful verification and expected evidence.

Use existing APIs and patterns. Include concrete code or commands where they
remove uncertainty; do not prewrite every line or divide work into arbitrary
time slices. Separate independent tasks from those that must be sequential.
Include required review and deployment gates in the completion path.

Keep a short plan in session state. Write a plan file only when requested or
required, in a repository-approved location. Do not add `docs/plans` by default.
For an implementation request, continue using
[executing-plans](../executing-plans/SKILL.md) or
[subagent-driven-development](../subagent-driven-development/SKILL.md) according
to the actual task and delegation policy. A plan-only request ends with the
plan; do not force an execution-mode question or start a new session.
