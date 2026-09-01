---
name: yagni
description: Prevent speculative scope and future-proofing in software work. Use when the user explicitly asks for YAGNI, scope reduction, removal of unused code, or a check that proposed functionality is needed now. Do not use to remove explicit requirements or required safety measures.
---

# YAGNI

Implement only requirements with a current, concrete use case.

- Before adding a feature, option, abstraction, dependency, or extension point,
  identify its present caller or requirement. If none exists, defer it.
- Prefer deleting unused machinery and simplifying speculative flexibility over
  preserving it for a hypothetical future.
- Inspect callers and observable behavior before removing existing code. If use
  cannot be ruled out safely, report the uncertainty instead of deleting it.
- Never defer validation at trust boundaries, data-loss prevention, security,
  accessibility, compatibility, or anything the user explicitly requested.
- State what was deferred and the concrete requirement that would justify adding
  it later.
