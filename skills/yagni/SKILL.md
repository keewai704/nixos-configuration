---
name: yagni
description: Assess speculative functionality when the user explicitly requests YAGNI or scope reduction.
---

# YAGNI

Implement only requirements with a current, concrete use case. Focus on whether
functionality is needed now, not how simply it is implemented. This lens does not
add a separate workflow when Ponytail is already active.

- Before adding a feature, option, abstraction, dependency, or extension point,
  identify its present caller or requirement. If none exists, defer it.
- Prefer deleting unused machinery and simplifying speculative flexibility over
  preserving it for a hypothetical future.
- Inspect callers and observable behavior before removing existing code. If use
  cannot be ruled out safely, report the uncertainty instead of deleting it.
- Never defer validation at trust boundaries, data-loss prevention, security,
  accessibility, compatibility, or anything the user explicitly requested.
- Explain a deferral when it affects the user's decision, including the concrete
  requirement that would justify it. Do not turn explicit scope into future work.
