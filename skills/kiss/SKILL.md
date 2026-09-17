---
name: kiss
description: Simplify a solution when the user explicitly requests KISS or reduced complexity.
---

# KISS

Choose the easiest correct solution to understand, operate, and change.
Use this lens for code, designs, plans, or explanations; it does not add a
separate workflow when Ponytail is already active.

- Identify the complexity that obstructs the current requirement before changing it.
- Prefer direct control flow, ordinary data structures, clear names, and fewer
  independently configured parts. Reuse established solutions where they fit.
- Remove indirection only when it does not serve a current responsibility or
  preserve required behavior; fewer lines alone are not evidence of simplicity.
- Keep trust-boundary validation, data-loss prevention, security, accessibility,
  compatibility, and proportionate verification intact.
- Complete the requested scope. Explain tradeoffs only when they affect the
  user's decision, with detail appropriate to the request.
