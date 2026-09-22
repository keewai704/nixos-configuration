---
name: subagent-driven-development
description: Use when executing an implementation plan with cohesive tasks that benefit from separate implementer contexts and independent review.
license: MIT
---

# Subagent-Driven Development

Apply the [Pi/Astra working agreement](../using-superpowers/SKILL.md).
The parent owns the plan, integration, and final evidence.

1. Read the plan and identify task boundaries, dependencies, and acceptance
   criteria. Use [using-git-worktrees](../using-git-worktrees/SKILL.md) when
   isolation is needed.
2. Give an implementer the relevant task, input revision, allowed files/actions,
   context, and checks. Use configured native roles rather than inventing tool
   names or changing global agent profiles. Parallelize only independent work
   with [dispatching-parallel-agents](../dispatching-parallel-agents/SKILL.md).
3. Inspect the returned changes and evidence. Answer questions from existing
   context when possible; ask the user only for a material missing decision.
4. Review both requirement coverage and implementation quality. Check missing
   behavior, out-of-scope additions, correctness, maintainability, and tests.
   A fresh independent reviewer may cover both dimensions in one pass; use
   separate reviews when risk or repository policy calls for them.
5. Verify findings, have the owner repair actual defects, and seek follow-up on
   changed or unresolved areas. Do not repeat an unchanged passing review or
   replace independent assessment with the implementer's self-review.
6. Integrate in dependency order and check combined behavior. Ensure the final
   integrated diff receives the required independent review and repository
   completion gates. Keep staging, commits, activation, and publication with
   the parent; do not assume a child worktree has been merged or removed.

If delegation fails, preserve useful work and report the limitation. Continue
authorized tasks locally, but do not mark a mandatory review gate passed.
