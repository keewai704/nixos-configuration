---
name: kiss
description: Apply Keep It Simple, Stupid to code, designs, plans, and explanations. Use when the user explicitly asks for KISS, the simplest approach, fewer moving parts, clearer code, or removal of over-engineering. Do not use to skip explicit requirements, safety, or verification.
---

# KISS

Choose the easiest correct solution to understand, operate, and change.

- Understand the current requirement and trace the affected flow before
  simplifying it.
- Reuse an existing codebase pattern first, then the standard library, a native
  platform feature, or an installed dependency before writing new machinery.
- Prefer direct control flow, ordinary data structures, clear names, and the
  fewest files and configuration knobs that satisfy the requirement.
- Avoid cleverness, premature generalization, indirection with one
  implementation, and configuration for values that do not vary.
- Keep input validation, error handling that prevents data loss, security,
  accessibility, and proportionate verification intact.
- Complete the requested scope. Explain a simplification or omitted complexity
  only when it affects the user's decision; match detail to the request.
