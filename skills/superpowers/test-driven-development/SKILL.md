---
name: test-driven-development
description: Use when implementing a feature or fixing a bug that changes executable behavior and benefits from a regression test. Not a mandatory code-test cycle for prose or declarative data edits.
license: MIT
---

# Test-Driven Development

Apply the [Pi/Astra working agreement](../using-superpowers/SKILL.md).
Use tests to specify observable behavior and prove the change fixes the intended
failure. Follow the project's test conventions and required gates.

1. **Red:** add the smallest meaningful test for one behavior or regression.
   Run it and confirm it fails for the missing behavior, not a syntax error,
   unavailable dependency, or broken fixture. Fix the test setup first.
2. **Green:** implement the simplest change that meets the requirement. Run the
   focused test and relevant existing checks. Do not weaken assertions merely
   to make the implementation pass.
3. **Refactor:** improve structure only where the change needs it, preserving
   behavior. Rerun affected tests after further edits.

Prefer public interfaces and real behavior over assertions about mock calls or
private structure. Mock external boundaries where needed for determinism; do
not replace the behavior under test with a mock or add production APIs solely
to support a test. Name tests for the contract and cover relevant failure paths.

For configuration, documentation, generated artifacts, or environment-bound
behavior, choose the appropriate parser, build, loader, or runtime check rather
than adding a test that copies constants. Explain a missing regression check
and its concrete limit. If implementation already exists, preserve it and add
meaningful coverage; never delete user work to recreate a ceremonial red phase.
Distinguish tests added after implementation from a witnessed red-green cycle.

Reuse passing evidence while relevant inputs stay unchanged. Do not impose a
fixed test count, new framework, full-suite run, or live paid model call without
a concrete requirement. Repository-mandated validation still applies.
